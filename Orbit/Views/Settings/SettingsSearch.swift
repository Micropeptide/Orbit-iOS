import SwiftUI

/// Search in Settings: every page and the settings on it, by the words you would use
/// for them. A hit on a page opens it; a hit on this screen scrolls to it.
struct SettingsSearchEntry: Identifiable {
    enum Target { case here(String), page(() -> AnyView) }
    let id = UUID()
    let title: String
    let place: String
    let words: String
    let target: Target

    func matches(_ term: String) -> Bool {
        let t = term.lowercased()
        return title.lowercased().contains(t) || words.contains(t) || place.lowercased().contains(t)
    }
}

enum SettingsIndex {
    static func page<V: View>(_ v: @autoclosure @escaping () -> V) -> SettingsSearchEntry.Target {
        .page { AnyView(v()) }
    }

    static let all: [SettingsSearchEntry] = [
        // this screen
        .init(title: "Model server", place: "Settings", words: "local model start stop restart mtplx memory", target: .here("server")),
        .init(title: "How chats run", place: "Settings", words: "harness engine claude code codex orbit mode", target: .here("harness")),
        .init(title: "Autonomy", place: "Settings", words: "auto ask full access approve permissions reviewer", target: .here("autonomy")),
        .init(title: "Backup", place: "Settings", words: "backup restore export", target: .here("backup")),
        .init(title: "Default model", place: "Settings", words: "new chats use model default", target: .here("default")),
        .init(title: "Connected to", place: "Settings", words: "mac address reachable latency diagnostics check again", target: .here("connected")),
        .init(title: "Appearance", place: "Settings", words: "theme dark light text size answer text code output haptics", target: .here("appearance")),
        .init(title: "Require Face ID", place: "Settings", words: "face id passcode lock privacy lock screen notifications", target: .here("faceid")),
        .init(title: "Bin", place: "Settings", words: "bin trash restore deleted recycle", target: .here("bin")),
        .init(title: "Offline copy", place: "Settings", words: "offline cache clear", target: .here("offline")),
        .init(title: "Unpair this phone", place: "Settings", words: "unpair pairing token forget", target: .here("unpair")),
        .init(title: "About Orbit", place: "Settings", words: "about version licence license", target: .here("about")),
        // pages on the Mac's settings
        .init(title: "Models & keys", place: "Settings on the Mac", words: "models keys api key provider openai anthropic deepseek opencode fetch hidden removed", target: page(ModelsKeysView())),
        .init(title: "When a model keeps failing", place: "Settings on the Mac", words: "fallback failing retry usage limit resume after limit", target: page(FallbackView())),
        .init(title: "General", place: "Settings on the Mac", words: "side work helper model reviewer review what an answer changed report fix check the work verify thinking reasoning effort tool rounds minutes auto-compact quiet mode recycle bin system prompt temperature sampling", target: page(MacGeneralView())),
        .init(title: "Local server", place: "Settings on the Mac", words: "local server context window kv quantization fan idle shutdown draft depth prefill scheduler", target: page(LocalServerView())),
        .init(title: "Tools & rules", place: "Settings on the Mac", words: "tools rules permissions allow deny shell write anywhere code execution screen control cluster", target: page(ToolsRulesView())),
        .init(title: "Easy mode", place: "Settings on the Mac", words: "easy mode fewer tools small model", target: page(EasyModeView())),
        .init(title: "MCP servers", place: "Settings on the Mac", words: "mcp servers connectors", target: page(MCPServersView())),
        .init(title: "Claude Code", place: "Settings on the Mac", words: "claude code permission mode hooks skills plugins mcp remote machines ssh profile instructions", target: page(ClaudeCodeSettingsView())),
        .init(title: "Codex", place: "Settings on the Mac", words: "codex agents.md chatgpt limits instructions", target: page(CodexSettingsView())),
        .init(title: "Phone access", place: "Settings on the Mac", words: "phone access tailscale pairing qr code token rotate network push ntfy", target: page(PhoneAccessView())),
        .init(title: "Status & health", place: "Settings on the Mac", words: "status health doctor launch flags system prompt", target: page(StatusHealthView())),
    ]
}

struct SettingsSearchResults: View {
    let term: String
    let jump: (String) -> Void
    @Environment(\.dismissSearch) private var dismissSearch

    private var hits: [SettingsSearchEntry] {
        SettingsIndex.all.filter { $0.matches(term.trimmingCharacters(in: .whitespaces)) }
    }

    var body: some View {
        Section {
            if hits.isEmpty {
                Text("Nothing in Settings matches “\(term)”").foregroundStyle(.secondary)
            }
            ForEach(hits) { e in
                switch e.target {
                case .here(let id):
                    Button { dismissSearch(); jump(id) } label: { row(e) }
                        .foregroundStyle(.primary)
                case .page(let make):
                    NavigationLink { make() } label: { row(e) }
                }
            }
        } header: {
            Text("Results")
        }
    }

    private func row(_ e: SettingsSearchEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(e.title)
            Text(e.place).font(.caption).foregroundStyle(.secondary)
        }
    }
}
