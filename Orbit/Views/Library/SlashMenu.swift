import SwiftUI

/// Saved prompts and Claude Code's commands, fetched once and kept for a while,
/// so typing "/" answers at once.
@MainActor
final class SlashCatalog: ObservableObject {
    static let shared = SlashCatalog()

    @Published private(set) var prompts: [SavedPrompt] = []
    @Published private(set) var claudeCommands: [ClaudeCommand] = []
    private var promptsAt: Date?
    private var claudeAt: Date?

    func invalidate() { promptsAt = nil }

    func refresh(_ server: OrbitServer?, claude: Bool) async {
        guard let server else { return }
        if promptsAt.map({ Date().timeIntervalSince($0) > 60 }) ?? true,
           let p = try? await server.prompts() {
            prompts = p
            promptsAt = Date()
        }
        if claude, claudeAt.map({ Date().timeIntervalSince($0) > 300 }) ?? true,
           let c = try? await server.claudeCommands() {
            claudeCommands = c
            claudeAt = Date()
        }
    }

    /// Whether the open chat answers through Claude Code — the same test the web uses.
    static func isClaudeChat(_ state: AppState) -> Bool {
        let m = state.currentModel ?? state.defaultModel ?? ""
        return m.hasPrefix("claude-qwen-cli") || m.hasPrefix("harness:")
    }
}

/// One line of the "/" menu.
struct SlashItem: Identifiable, Hashable {
    enum Kind: Hashable { case builtin, library, prompt, claude }
    var command: String
    var detail: String
    var kind: Kind
    var id: String { "\(kind)\(command)" }
}

/// What a library command opens.
enum SlashSheet: Identifiable {
    case section(LibrarySection, sid: String?)
    case chat(String)
    var id: String {
        switch self {
        case .section(let s, _): return "section." + s.rawValue
        case .chat(let sid):  return "chat." + sid
        }
    }
}

/// The composer's side of the Library: the "/" menu's contents, the commands
/// that open Library screens, and saved prompts expanding into the message box.
@MainActor
final class SlashController: ObservableObject {
    @Published var sheet: SlashSheet?
    @Published var note: String?

    /// Orbit commands that make sense on a phone, beyond the composer's own.
    static let libraryCommands: [(String, String)] = [
        ("/prompts", "saved prompts"), ("/knowledge", "your document library"),
        ("/agents", "agent presets"), ("/skills", "saved procedures"),
        ("/memory", "memory and instructions"),
        ("/agent", "choose this chat's agent"), ("/instructions", "this chat's own instructions"),
        ("/remember", "save a note to memory: /remember <text>"),
        ("/scheduled", "messages and tasks for later"), ("/files", "files Orbit made or you gave it"),
    ]

    func items(for draft: String, builtins: [(String, String)], catalog: SlashCatalog,
               claude: Bool) -> [SlashItem] {
        guard draft.hasPrefix("/"), !draft.contains(" "), !draft.contains("\n") else { return [] }
        let typed = draft.lowercased()
        var seen = Set<String>()
        var out: [SlashItem] = []
        func add(_ c: String, _ d: String, _ k: SlashItem.Kind) {
            guard c.lowercased().hasPrefix(typed), seen.insert(c.lowercased()).inserted else { return }
            out.append(SlashItem(command: c, detail: d, kind: k))
        }
        for (c, d) in builtins { add(c, d, .builtin) }
        for (c, d) in Self.libraryCommands { add(c, d, .library) }
        for p in catalog.prompts {
            add("/" + p.name, p.desc.isEmpty ? "saved prompt" : p.desc, .prompt)
        }
        if claude {
            for c in catalog.claudeCommands {
                guard let n = c.name, !n.isEmpty else { continue }
                add("/" + n, String((c.description ?? "Claude Code").prefix(120)), .claude)
            }
        }
        return out
    }

    /// A typed "/command words" the Library handles. Returns the new message-box
    /// text (empty when the command ran), or nil to let the message go on as usual.
    func intercept(_ text: String, state: AppState) -> String? {
        let head = text.split(whereSeparator: { $0 == " " || $0 == "\n" }).first.map(String.init) ?? ""
        let rest = text.dropFirst(head.count).trimmingCharacters(in: .whitespacesAndNewlines)
        let name = String(head.dropFirst())
        if let p = SlashCatalog.shared.prompts.first(where: { $0.name == name }) {
            return PromptExpander.expand(p.text, rest: rest)
        }
        let sid = state.openChat?.sid
        switch head.lowercased() {
        case "/prompts":   sheet = .section(.prompts, sid: sid)
        case "/knowledge": sheet = .section(.knowledge, sid: sid)
        case "/agents":    sheet = .section(.agents, sid: sid)
        case "/skills":    sheet = .section(.skills, sid: sid)
        case "/memory":
            sheet = .section(SlashCatalog.isClaudeChat(state) ? .claudeMemory : .memory, sid: sid)
        case "/agent", "/instructions":
            guard let sid else { note = "Open a chat first"; return "" }
            sheet = .chat(sid)
        case "/scheduled": state.tab = "scheduled"
        case "/files":     state.tab = "files"
        case "/remember":
            guard !rest.isEmpty else { return "/remember " }
            Task { await remember(rest, state: state) }
        default: return nil
        }
        return ""
    }

    /// Tapping a line in the menu.
    func picked(_ item: SlashItem, draft: inout String, state: AppState,
                onCommand: ((String) -> Bool)?) {
        switch item.kind {
        case .builtin:
            draft = ""
            _ = onCommand?(item.command)
        case .library:
            if item.command == "/remember" { draft = "/remember "; return }
            draft = intercept(item.command, state: state) ?? ""
        case .prompt:
            let p = SlashCatalog.shared.prompts.first { "/" + $0.name == item.command }
            let body = p?.text ?? ""
            // a prompt that takes words waits for them; one that doesn't goes in whole
            let takesWords = body.contains("$ARGUMENTS")
                || body.range(of: #"\$\{?\d"#, options: .regularExpression) != nil
            draft = takesWords || p == nil ? item.command + " " : body
        case .claude:
            draft = item.command + " "
        }
    }

    /// Same naming as the web: the first four words, lowercased, joined with -.
    private func remember(_ text: String, state: AppState) async {
        let words = text.lowercased().split(whereSeparator: \.isWhitespace).prefix(4).joined(separator: "-")
        let name = String(words.unicodeScalars.filter {
            ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-"
        }.map(Character.init))
        do {
            let saved = try await state.server?.saveMemory(name: name.isEmpty ? "note" : name, text: text)
            note = "Saved to memory: \(saved ?? name)"
            Haptics.success()
        } catch {
            note = error.localizedDescription
        }
    }
}

/// The "/" menu above the message box.
struct SlashMenu: View {
    @EnvironmentObject var state: AppState
    @Binding var draft: String
    @ObservedObject var controller: SlashController
    @ObservedObject private var catalog = SlashCatalog.shared
    var builtins: [(String, String)]
    var onCommand: ((String) -> Bool)?

    private var claude: Bool { SlashCatalog.isClaudeChat(state) }

    var body: some View {
        let items = controller.items(for: draft, builtins: builtins, catalog: catalog, claude: claude)
        VStack(spacing: 0) {
            if let note = controller.note {
                Text(note).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.top, 6)
                    .task(id: note) {
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        controller.note = nil
                    }
            }
            if !items.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(items) { item in
                            Button {
                                Haptics.tap()
                                controller.picked(item, draft: &draft, state: state, onCommand: onCommand)
                            } label: { row(item) }
                            .buttonStyle(.plain)
                            Divider().padding(.leading, 12)
                        }
                    }
                }
                .frame(maxHeight: min(CGFloat(items.count) * 46, 230))
                .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 12))
                .padding(.horizontal, 12).padding(.top, 8)
            }
        }
        .task(id: draft.hasPrefix("/")) {
            if draft.hasPrefix("/") { await catalog.refresh(state.server, claude: claude) }
        }
    }

    private func row(_ item: SlashItem) -> some View {
        HStack(spacing: 8) {
            Text(item.command).font(.callout.monospaced().weight(.semibold))
                .lineLimit(1).layoutPriority(1)
            Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 4)
            switch item.kind {
            case .prompt: tag("prompt")
            case .claude: tag("Claude")
            default: EmptyView()
            }
        }
        .padding(.horizontal, 12).frame(minHeight: 45)
        .contentShape(.rect)
    }

    private func tag(_ s: String) -> some View {
        Text(s).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(.quaternary, in: .capsule)
    }
}

extension View {
    /// The Library screens a slash command opens, presented over the chat.
    func slashSheets(_ controller: SlashController) -> some View {
        sheet(item: Binding(get: { controller.sheet }, set: { controller.sheet = $0 })) { target in
            switch target {
            case .section(let s, let sid): LibrarySheet(section: s, sid: sid)
            case .chat(let sid):  ChatLibrarySheet(sid: sid)
            }
        }
    }
}
