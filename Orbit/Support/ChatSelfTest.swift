#if DEBUG
import Foundation

/// Development only: `ORBIT_CHAT_SELFTEST=read|keep|cleanup` exercises the chat
/// actions against a paired Mac without a finger, and writes what happened to
/// Documents/chat-selftest.txt (and stdout).
///
/// - `read`: read-only endpoints, and stream events parsed from sample payloads.
/// - `keep`: a throwaway chat named "zz-test" is created, renamed, put in plan
///   mode (which saves it), pinned, tagged, archived and unarchived — and left
///   in place so the list can be looked at.
/// - `cleanup`: plan mode off, bin with undo, restore, bin again; a temporary
///   chat created and burned.
///
/// Nothing here sends a message or starts an answer.
extension AppState {
    func runChatSelfTest() async {
        guard let mode = ProcessInfo.processInfo.environment["ORBIT_CHAT_SELFTEST"],
              let server else { return }
        var log: [String] = []
        func note(_ s: String) { log.append(s); print("[selftest] " + s) }
        func check(_ label: String, _ body: () async throws -> String) async {
            do { note("ok   \(label): \(try await body())") }
            catch { note("FAIL \(label): \(error.localizedDescription)") }
        }

        if mode == "read" {
            await check("running") { let r = try await server.runningState(); return "\(r.running.count) running, \(r.waiting.count) waiting" }
            await check("tags") { "\(try await server.tags().prefix(5))" }
            await check("projects") { "\(try await server.projectDetails().map(\.name))" }
            await check("stats 7d") { let s = try await server.usageStats(days: 7); return "\(s.turns) turns, \(s.models.count) models, \(s.tools.count) tools" }
            await check("ledger") { let l = try await server.ledger(sid: chats.first?.id); return "chat \(l.chat.turns) turns, all \(l.all.turns) turns, \(l.all.tok_per_s) tok/s" }
            await check("checkpoints (missing file)") { "\(try await server.checkpoints(rel: "zz-no-such-file.txt"))" }
            await check("citations") { "\(try await server.checkCitations("see doi 10.1038/nature14539").map { "\($0.doi) ok=\($0.ok)" })" }
            if let c = chats.first {
                await check("export") {
                    let u = try await server.exportMarkdown(c.id, title: c.displayTitle)
                    let t = (try? String(contentsOf: u, encoding: .utf8)) ?? ""
                    return "\(u.lastPathComponent), \(t.count) chars, starts \(String(t.prefix(2)).debugDescription)"
                }
                await check("saved answer fields") {
                    let d = try await server.peek(c.id)
                    let a = d.messages.filter { !$0.isUser }
                    return "\(a.count) answers; with stats \(a.filter { $0.statsLine != nil }.count); with t \(a.filter { $0.t != nil }.count); plan_mode \(d.plan_mode.map(String.init) ?? "nil")"
                }
            }
            let samples = [
                #"{"k":"question","p":{"id":"qa1","question":"Which?","options":["A","B"],"multiple":true}}"#,
                #"{"k":"approval_request","p":{"id":"ap1","name":"Bash","args":{"command":"ls"},"reason":"run","claude":true,"suggested_pattern":"Bash(ls:*)","suggestions":["Bash(ls:*)","Bash"]}}"#,
                #"{"k":"approval_request","p":{"id":"ap2","name":"shell","args":{},"reason":"x","codex":true}}"#,
                #"{"k":"round_limit","p":{"reason":"rounds","rounds":40,"pending":["a"]}}"#,
            ]
            for s in samples {
                switch OrbitServer.parse(s) {
                case .question(let q)?: note("ok   parse question: \(q.id) \(q.options) multiple=\(q.multiple)")
                case .approvalPrompt(let a)?: note("ok   parse approval: \(a.id) claude=\(a.claude) codex=\(a.codex) pattern=\(a.suggestedPattern) args=\(a.args.count)")
                case .roundLimit(let r)?: note("ok   parse round_limit: \(r)")
                default: note("FAIL parse: \(s)")
                }
            }
            let plain = Message(role: "assistant", text: "# Title\n\n**bold** and `code`\n\n- one\n- two").plainText
            note("ok   plain text: \(plain.debugDescription)")
        }

        if mode == "keep" {
            guard let sid = await newChat() else { note("FAIL new chat"); return write(log) }
            note("ok   new chat \(sid)")
            await rename(sid, to: "zz-test")
            await setPlanMode(true)
            note("plan mode now \(chatExtras.planMode)")
            await loadChats()
            guard chats.contains(where: { $0.id == sid }) else { note("FAIL zz-test not listed after plan mode save"); return write(log) }
            note("ok   zz-test listed")
            await setPinned(sid, true)
            await setTags(sid, ["zz-test-tag"])
            await setArchived(sid, true)
            note("archived=\(chats.first { $0.id == sid }?.archived == true)")
            await setArchived(sid, false)
            await loadChats()
            let c = chats.first { $0.id == sid }
            note("zz-test: pinned=\(c?.pinned == true) archived=\(c?.archived == true) tags=\(c?.tags ?? []) title=\(c?.title ?? "")")
            await check("tags include zz-test-tag") { "\(try await server.tags().contains { $0.name == "zz-test-tag" })" }
            UserDefaults.standard.set(sid, forKey: "orbit.selftest.sid")
        }

        if mode == "cleanup" {
            if let sid = UserDefaults.standard.string(forKey: "orbit.selftest.sid") {
                await open(sid)
                if openChat?.sid == sid, chatExtras.planMode { await setPlanMode(false) }
                note("plan mode after off: \(chatExtras.planMode)")
                await binWithUndo(sid)
                note("binned; undo offered: \(chatExtras.binned != nil); listed: \(chats.contains { $0.id == sid })")
                await undoBin()
                await loadChats()
                note("restored; listed: \(chats.contains { $0.id == sid })")
                await check("bin again") { try await server.bin(sid).map { "in bin as \($0.name)" } ?? "not found in bin" }
                UserDefaults.standard.removeObject(forKey: "orbit.selftest.sid")
            }
            await check("temporary chat + burn") {
                let t = try await server.temporaryChat(on: true)
                try await server.burn(sid: t)
                return "burned \(t)"
            }
            // leave the Mac on a fresh, unsaved chat rather than a temporary or binned one
            _ = try? await server.newChat()
            openChat = nil; messages = []
            await loadChats()
        }
        write(log)
    }

    private func write(_ log: [String]) {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        try? log.joined(separator: "\n").write(to: dir.appendingPathComponent("chat-selftest.txt"),
                                               atomically: true, encoding: .utf8)
    }
}
#endif
