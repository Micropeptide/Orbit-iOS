import Foundation

/// What a chat keeps working toward across answers. The Mac drives it: after each
/// answer it checks the work against the objective and carries on, or stops and says
/// why (done, stuck, over budget, out of turns, stopped by you). The phone shows where
/// it stands and offers the same controls as the Mac.
struct Goal: Codable, Hashable {
    var objective: String
    var status: String            // active | paused | blocked | budget | complete
    var token_budget: Int
    var tokens_used: Int
    var max_turns: Int
    var turns_used: Int
    var reason: String
    var note: String

    enum CodingKeys: String, CodingKey {
        case objective, status, token_budget, tokens_used, max_turns, turns_used, reason, note
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        objective = c.lenientString(.objective) ?? ""
        status = c.lenientString(.status) ?? "paused"
        token_budget = Int(c.lenientDouble(.token_budget) ?? 0)
        tokens_used = Int(c.lenientDouble(.tokens_used) ?? 0)
        max_turns = Int(c.lenientDouble(.max_turns) ?? 20)
        turns_used = Int(c.lenientDouble(.turns_used) ?? 0)
        reason = c.lenientString(.reason) ?? ""
        note = c.lenientString(.note) ?? ""
    }

    init?(_ d: [String: Any]?) {
        guard let d, let data = try? JSONSerialization.data(withJSONObject: d),
              let g = try? JSONDecoder().decode(Goal.self, from: data) else { return nil }
        self = g
    }

    /// In words, as the strip shows it.
    var word: String {
        switch status {
        case "active": return "working toward"
        case "paused": return "paused"
        case "blocked": return "needs you"
        case "budget": return "over budget"
        case "complete": return "done"
        default: return status
        }
    }

    var usage: String {
        var bits = ["\(turns_used)/\(max_turns) turns"]
        if token_budget > 0 {
            bits.append("\(tokens_used.formatted())/\(token_budget.formatted()) tokens")
        } else if tokens_used > 0 {
            bits.append("\(tokens_used.formatted()) tokens")
        }
        return bits.joined(separator: " · ")
    }

    var overBudget: Bool { token_budget > 0 && tokens_used >= token_budget }
}

extension OrbitServer {
    /// `/api/goal`: get | set | edit | pause | resume | clear. Returns the goal as it now
    /// stands, and whether a resume started the next answer.
    func goal(_ sid: String, op: String, objective: String? = nil, tokenBudget: Int? = nil,
              maxTurns: Int? = nil) async throws -> (goal: Goal?, started: Bool) {
        var body: [String: Any] = ["sid": sid, "op": op]
        if let objective { body["objective"] = objective }
        if let tokenBudget { body["token_budget"] = tokenBudget }
        if let maxTurns { body["max_turns"] = maxTurns }
        let obj = try await postJSON("/api/goal", body)
        return (Goal(obj["goal"] as? [String: Any]), (obj["started"] as? Bool) ?? false)
    }
}

extension AppState {
    /// Read the open chat's goal again -- after an answer, when the Mac has checked it.
    func refreshGoal(_ sid: String) async {
        guard let server, let r = try? await server.goal(sid, op: "get") else { return }
        if openChat?.sid == sid { goal = r.goal }
    }

    /// After an answer in a chat with an active goal the Mac checks the work, which
    /// takes a few seconds; ask then, and again a little later.
    func followGoal(_ sid: String) {
        guard goal?.status == "active" else { return }
        Task {
            for wait in [3, 12] {
                try? await Task.sleep(for: .seconds(wait))
                await refreshGoal(sid)
                guard goal?.status == "active" else { return }
            }
        }
    }

    func goalAction(_ op: String, objective: String? = nil, tokenBudget: Int? = nil,
                    maxTurns: Int? = nil) async {
        guard let server, let sid = openChat?.sid else { return }
        do {
            let r = try await server.goal(sid, op: op, objective: objective,
                                          tokenBudget: tokenBudget, maxTurns: maxTurns)
            goal = r.goal
            if r.started {
                toast("Carrying on toward the goal")
                try? await Task.sleep(for: .milliseconds(700))
                await open(sid)                 // joins the answer it just started
            }
            await loadChats()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Send this message as the chat's goal: it keeps working until the Mac judges it done.
    func sendGoal(_ text: String) async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { showGoalEditor = true; return }
        await send(t, goal: true)
    }
}
