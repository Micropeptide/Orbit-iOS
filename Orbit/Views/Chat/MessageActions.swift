import SwiftUI

/// The per-message actions a chat offers, and the sheets they open. One
/// `ChatActionsModel` per chat screen holds what is presented, so the chat
/// view only has to attach `ChatActionsHost` and pass `actions` to each bubble.
@MainActor
final class ChatActionsModel: ObservableObject {
    @Published var citations: CitationsRequest?
    @Published var undo: Message?
    @Published var askSkillName = false
    @Published var skillName = ""
    @Published var confirmRegenerate: Bool? = nil        // false = regenerate, true = deeper
    @Published var showJump = false
    @Published var showStats = false
    @Published var exportURL: URL?
    @Published var confirmBurn = false
    /// Row index to scroll to, picked in the jump sheet.
    @Published var jumpRequest: Int?
    // the Claude Code commands' sheets: /rewind, /context, /diff, /help, /permissions
    @Published var showRewind = false
    @Published var showContext = false
    @Published var showDiffs = false
    @Published var showHelp = false
    @Published var showPermissions = false
    /// A command picked in /help, for the message box.
    @Published var helpPick: String?

    struct CitationsRequest: Identifiable {
        let id = UUID()
        let text: String
    }

    func actions(_ state: AppState) -> MessageActions {
        MessageActions(
            busy: state.streaming,
            fork: { m in Task { await state.fork(from: m) } },
            regenerate: { [weak self] in self?.confirmRegenerate = false },
            retryDeeper: { [weak self] in self?.confirmRegenerate = true },
            continueAnswer: { Task { await state.continueAnswer() } },
            checkDOIs: { [weak self] m in self?.citations = CitationsRequest(text: m.text) },
            saveSkill: { [weak self] in
                self?.skillName = "captured-\(Int(Date.now.timeIntervalSince1970) % 10000)"
                self?.askSkillName = true
            },
            undo: { [weak self] m in self?.undo = m })
    }
}

struct MessageActions {
    var busy: Bool
    var fork: (Message) -> Void
    var regenerate: () -> Void
    var retryDeeper: () -> Void
    var continueAnswer: () -> Void
    var checkDOIs: (Message) -> Void
    var saveSkill: () -> Void
    var undo: (Message) -> Void

    /// Added to a user message's menu.
    @ViewBuilder
    func userItems(_ m: Message) -> some View {
        Button { fork(m) } label: {
            Label("Fork from here", systemImage: "arrow.triangle.branch")
        }
        .disabled(busy)
    }

    /// Added to an answer's menu.
    @ViewBuilder
    func answerItems(_ m: Message, isLast: Bool) -> some View {
        Menu {
            Button {
                UIPasteboard.general.string = m.text
                Haptics.success()
            } label: { Label("As Markdown", systemImage: "number") }
            Button {
                UIPasteboard.general.string = m.plainText
                Haptics.success()
            } label: { Label("As plain text", systemImage: "textformat") }
        } label: {
            Label("Copy as…", systemImage: "doc.on.clipboard")
        }
        Button { checkDOIs(m) } label: {
            Label("Check DOIs", systemImage: "checkmark.seal")
        }
        Button { saveSkill() } label: {
            Label("Save chat as a skill", systemImage: "wand.and.stars")
        }
        .disabled(busy)
        if isLast {
            Divider()
            Button { retryDeeper() } label: {
                Label("Retry with deeper reasoning", systemImage: "brain")
            }
            .disabled(busy)
            Button { continueAnswer() } label: {
                Label("Continue", systemImage: "arrow.right.circle")
            }
            .disabled(busy)
        }
        let n = m.undoableChanges.count
        if n > 0 {
            Divider()
            Button(role: .destructive) { undo(m) } label: {
                Label("Undo \(n) file change\(n == 1 ? "" : "s")…", systemImage: "arrow.uturn.backward")
            }
            .disabled(busy)
        }
    }
}

/// Under an answer: how long it took and what it cost, and the files it changed.
struct AnswerFooter: View {
    let message: Message
    var actions: MessageActions?

    var body: some View {
        let n = message.undoableChanges.count
        if message.statsLine != nil || (n > 0 && actions != nil) {
            HStack(spacing: 10) {
                if let s = message.statsLine {
                    Text(s).font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                }
                if n > 0, let actions {
                    Button { actions.undo(message) } label: {
                        Label("\(n) file change\(n == 1 ? "" : "s")", systemImage: "arrow.uturn.backward")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.orange)
                    .disabled(actions.busy)
                }
            }
        }
    }
}

/// Sheets, dialogs and alerts for the chat actions, attached once to the chat view.
struct ChatActionsHost: ViewModifier {
    let sid: String
    @ObservedObject var model: ChatActionsModel
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .sheet(item: $model.citations) { CitationsSheet(text: $0.text) }
            .sheet(item: $model.undo) { UndoChangesSheet(message: $0) }
            .sheet(isPresented: $model.showJump) {
                JumpSheet(messages: state.messages) { model.jumpRequest = $0 }
            }
            .sheet(isPresented: $model.showStats) { UsageStatsView(sid: sid) }
            .sheet(isPresented: $model.showRewind) { RewindSheet() }
            .sheet(isPresented: $model.showContext) { ContextSheet(sid: sid) }
            .sheet(isPresented: $model.showDiffs) { DiffsSheet(diffs: state.shownDiffs[sid] ?? []) }
            .sheet(isPresented: $model.showHelp) { CommandHelpSheet { model.helpPick = $0 } }
            .sheet(isPresented: $model.showPermissions) { PermissionsSheet(sid: sid) }
            .alert("Run this?", isPresented: Binding(get: { state.chatExtras.bangConfirm != nil },
                                                     set: { if !$0 { state.chatExtras.bangConfirm = nil } }),
                   presenting: state.chatExtras.bangConfirm) { c in
                Button("Run") {
                    state.chatExtras.bangConfirm = nil
                    Task { await state.runBang(c.cmd, confirmed: true) }
                }
                Button("Cancel", role: .cancel) {
                    state.chatExtras.bangConfirm = nil
                    model.helpPick = "! " + c.cmd       // back in the box to change
                }
            } message: { c in
                Text(c.cmd + "\n\n" + c.reason)
            }
            .sheet(item: $model.exportURL) { ActivityView(items: [$0]).ignoresSafeArea() }
            .alert("Save as a skill", isPresented: $model.askSkillName) {
                TextField("Skill name", text: $model.skillName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Save") {
                    let n = model.skillName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !n.isEmpty else { return }
                    Task { await state.captureSkill(named: n) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Writes this chat's procedure up as a reusable skill on your Mac. It takes a little while.")
            }
            .confirmationDialog(model.confirmRegenerate == true ? "Retry with deeper reasoning?" : "Ask again?",
                                isPresented: Binding(get: { model.confirmRegenerate != nil },
                                                     set: { if !$0 { model.confirmRegenerate = nil } }),
                                titleVisibility: .visible) {
                Button(model.confirmRegenerate == true ? "Retry deeper" : "Ask again") {
                    let deeper = model.confirmRegenerate == true
                    model.confirmRegenerate = nil
                    Task { await state.regenerateLast(deeper: deeper) }
                }
                Button("Cancel", role: .cancel) { model.confirmRegenerate = nil }
            } message: {
                Text("The last answer is replaced by a new one.")
            }
            .confirmationDialog("Erase this conversation completely?", isPresented: $model.confirmBurn,
                                titleVisibility: .visible) {
                Button("Burn", role: .destructive) {
                    Task { if await state.burnTemporaryChat() { dismiss() } }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("A temporary chat is never written to disk. Burning it leaves no trace, and it cannot be recovered.")
            }
    }
}

/// Items for the chat's own menu (the toolbar's ellipsis).
struct ChatMenuItems: View {
    let sid: String
    @ObservedObject var model: ChatActionsModel
    @EnvironmentObject var state: AppState

    var body: some View {
        Button {
            Task { await state.setPlanMode(!state.chatExtras.planMode) }
        } label: {
            Label(state.chatExtras.planMode ? "Leave plan mode" : "Plan mode",
                  systemImage: state.chatExtras.planMode ? "hammer" : "list.bullet.clipboard")
        }
        Button { model.showJump = true } label: {
            Label("Jump to a message…", systemImage: "arrow.down.to.line")
        }
        Button { model.showRewind = true } label: {
            Label("Rewind…", systemImage: "clock.arrow.circlepath")
        }
        .disabled(!state.messages.contains(where: \.isUser))
        Button { model.showContext = true } label: {
            Label("Context window", systemImage: "square.grid.3x3")
        }
        Button {
            Task {
                guard let server = state.server else { return }
                do {
                    model.exportURL = try await server.exportMarkdown(
                        sid, title: state.openChat?.title ?? "Chat")
                } catch { state.lastError = error.localizedDescription }
            }
        } label: {
            Label("Export from the Mac (.md)", systemImage: "square.and.arrow.down")
        }
        Button { model.showStats = true } label: {
            Label("Usage stats", systemImage: "chart.bar")
        }
        if state.chatExtras.tempSid == sid {
            Button(role: .destructive) { model.confirmBurn = true } label: {
                Label("Burn this chat", systemImage: "flame")
            }
        }
    }
}

/// Chips above the transcript: plan mode, temporary chat.
struct ChatModeChips: View {
    let sid: String
    @ObservedObject var model: ChatActionsModel
    @EnvironmentObject var state: AppState

    var body: some View {
        let plan = state.chatExtras.planMode && state.openChat?.sid == sid
        let temp = state.chatExtras.tempSid == sid
        if plan || temp {
            HStack(spacing: 8) {
                if plan {
                    Button { Task { await state.setPlanMode(false) } } label: {
                        Label("plan mode · tap to leave", systemImage: "list.bullet.clipboard")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Color.accentColor, in: .capsule)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("It may read and propose, and change nothing")
                }
                if temp {
                    Button { model.confirmBurn = true } label: {
                        Label("temporary · burn", systemImage: "flame")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Color.red.opacity(0.85), in: .capsule)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(.bar)
        }
    }
}

/// A short message floating at the bottom, and Undo after binning a chat.
struct ToastOverlay: ViewModifier {
    @EnvironmentObject var state: AppState

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            VStack(spacing: 8) {
                if let b = state.chatExtras.binned {
                    HStack(spacing: 12) {
                        Text("“\(b.title)” moved to the bin").font(.footnote).lineLimit(1)
                        Button("Undo") { Task { await state.undoBin() } }
                            .font(.footnote.weight(.semibold))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(.thinMaterial, in: .capsule)
                }
                if let t = state.chatExtras.toast {
                    Text(t).font(.footnote.weight(.medium))
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(.thinMaterial, in: .capsule)
                        .transition(.opacity)
                }
            }
            .padding(.bottom, 70)
            .animation(.default, value: state.chatExtras.toast)
        }
    }
}
