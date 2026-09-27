import SwiftUI

/// Above the message box: the chat's goal, where it stands, and its controls. The Mac
/// keeps the chat working until the goal is done; this is how you see and steer that.
struct GoalStrip: View {
    let sid: String
    @EnvironmentObject var state: AppState
    @State private var confirmClear = false

    var body: some View {
        Group {
            if let g = state.goal, state.openChat?.sid == sid {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: icon(g.status)).foregroundStyle(tint(g.status))
                        Text(g.word).font(.caption.weight(.semibold)).foregroundStyle(tint(g.status))
                        Text(g.objective).font(.caption).lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 4)
                        Menu {
                            if g.status == "active" {
                                Button("Pause", systemImage: "pause") { Task { await state.goalAction("pause") } }
                            } else if g.status != "complete" {
                                Button("Resume", systemImage: "play") { Task { await resume(g) } }
                            }
                            Button("Edit…", systemImage: "pencil") { state.showGoalEditor = true }
                            Button("Clear goal", systemImage: "xmark", role: .destructive) { confirmClear = true }
                        } label: {
                            Image(systemName: "ellipsis.circle").font(.callout)
                        }
                        .accessibilityLabel("Goal actions")
                    }
                    Text(g.usage).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    if !g.reason.isEmpty {
                        Text(g.reason).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .leading) {
                    Rectangle().fill(tint(g.status)).frame(width: 3)
                }
                .overlay(Divider(), alignment: .top)
                .confirmationDialog("Stop keeping this goal?", isPresented: $confirmClear) {
                    Button("Clear goal", role: .destructive) { Task { await state.goalAction("clear") } }
                } message: {
                    Text("The chat stays as it is; it just won't carry on by itself.")
                }
            }
        }
        .sheet(isPresented: $state.showGoalEditor) { GoalEditor(sid: sid) }
    }

    private func resume(_ g: Goal) async {
        // a goal that used its budget needs a bigger one to carry on
        if g.overBudget { state.showGoalEditor = true; return }
        await state.goalAction("resume")
    }

    private func icon(_ s: String) -> String {
        switch s {
        case "active": return "scope"
        case "complete": return "checkmark.circle.fill"
        case "paused": return "pause.circle"
        default: return "exclamationmark.circle"
        }
    }

    private func tint(_ s: String) -> Color {
        switch s {
        case "active": return .accentColor
        case "complete": return .green
        case "paused": return .secondary
        default: return .orange
        }
    }
}

/// Set a goal, or change one: what done looks like, a token budget, a turn limit.
struct GoalEditor: View {
    let sid: String
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var objective = ""
    @State private var budget = ""
    @State private var turns = 20

    private var existing: Goal? { state.goal }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. every test in tests/ passes and the README documents the new flag",
                              text: $objective, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text("What done looks like")
                } footer: {
                    Text("After each answer the Mac checks the work against this and carries on, or stops "
                         + "and says why — done, stuck three checks running, over its budget, or out of turns. "
                         + "Stop pauses it.")
                }
                Section("Limits") {
                    TextField("Token budget (none)", text: $budget).keyboardType(.numberPad)
                    Stepper("Up to \(turns) turns", value: $turns, in: 1...200)
                }
            }
            .navigationTitle(existing == nil ? "Set a goal" : "Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? "Start" : "Save") { Task { await save() } }
                        .disabled(objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if let g = existing {
                    objective = g.objective
                    budget = g.token_budget > 0 ? String(g.token_budget) : ""
                    turns = g.max_turns
                }
            }
        }
    }

    private func save() async {
        let obj = objective.trimmingCharacters(in: .whitespacesAndNewlines)
        let tb = Int(budget.filter(\.isNumber)) ?? 0
        let had = existing
        await state.goalAction(had == nil ? "set" : "edit", objective: obj, tokenBudget: tb, maxTurns: turns)
        // a new goal starts at once; one that stopped at its budget carries on with the new one
        if had == nil || had?.status == "budget" {
            await state.goalAction("resume")
        }
        dismiss()
    }
}
