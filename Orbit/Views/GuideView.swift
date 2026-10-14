import SwiftUI

/// The user guide, read from the Mac (the same text the Mac's Guide shows): its sections as a
/// list you can search, each opening on its own page.
struct GuideView: View {
    @EnvironmentObject var state: AppState
    @State private var intro = ""
    @State private var sections: [Section] = []
    @State private var failure: String?
    @State private var search = ""

    struct Section: Identifiable, Hashable {
        var title: String
        var text: String
        var id: String { title }
    }

    private var shown: [Section] {
        let t = search.trimmingCharacters(in: .whitespaces).lowercased()
        return t.isEmpty ? sections : sections.filter { $0.title.lowercased().contains(t) || $0.text.lowercased().contains(t) }
    }

    var body: some View {
        List {
            if let failure {
                Text(failure).foregroundStyle(.secondary)
            } else if sections.isEmpty {
                HStack(spacing: 8) { OrbitSpinner(size: 12); Text("Loading the guide").foregroundStyle(.secondary) }
            } else {
                if search.isEmpty, !intro.isEmpty {
                    SwiftUI.Section { MarkdownText(intro).font(.callout) }
                }
                SwiftUI.Section {
                    ForEach(shown) { s in
                        NavigationLink(s.title) { GuidePage(section: s) }
                    }
                }
            }
        }
        .navigationTitle("User guide")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Search the guide")
        .task { await load() }
    }

    private func load() async {
        guard let server = state.server else { failure = "Pair with your Mac to read the guide."; return }
        do {
            let data = try await server.run(try server.request("/guide.md"))
            let text = String(decoding: data, as: UTF8.self)
            (intro, sections) = Self.split(text)
        } catch {
            failure = "Could not load the guide from your Mac — \(error.localizedDescription)"
        }
    }

    /// The text before the first "## " heading, and one section per heading.
    static func split(_ md: String) -> (String, [Section]) {
        var intro: [String] = [], out: [Section] = [], title: String?, lines: [String] = []
        for line in md.components(separatedBy: "\n") {
            if line.hasPrefix("## ") {
                if let title { out.append(Section(title: title, text: lines.joined(separator: "\n"))) }
                title = String(line.dropFirst(3)); lines = []
            } else if title == nil {
                if !line.hasPrefix("# ") { intro.append(line) }
            } else {
                lines.append(line)
            }
        }
        if let title { out.append(Section(title: title, text: lines.joined(separator: "\n"))) }
        return (intro.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), out)
    }
}

private struct GuidePage: View {
    let section: GuideView.Section

    var body: some View {
        ScrollView {
            MarkdownText(section.text.replacingOccurrences(of: "\n---\n", with: "\n"))
                .padding(.horizontal, 18).padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(OrbitTheme.paper.ignoresSafeArea())
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
