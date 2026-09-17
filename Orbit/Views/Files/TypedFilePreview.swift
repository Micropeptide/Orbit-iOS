import SwiftUI

/// A workspace file shown the way its kind reads best: Markdown rendered, a
/// CSV as a table you can filter and sort, a notebook as its cells, code and
/// text in monospace with line numbers, a page rendered or as its source.
/// Everything else goes to QuickLook from the Files list.
struct TypedFilePreview: View {
    let file: RemoteFile
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var text: String?
    @State private var failed: String?
    @State private var truncated = false
    @State private var showSource = false
    @State private var shareURL: URL?

    /// Past this, only the start is read: a phone is no place for a 50 MB log.
    static let limit = 2_000_000

    enum Kind { case markdown, table, notebook, page, text }

    static func kind(_ f: RemoteFile) -> Kind? {
        switch f.ext {
        case "md", "markdown": return .markdown
        case "csv", "tsv": return .table
        case "ipynb": return .notebook
        case "html", "htm": return .page
        case "txt", "log", "json", "jsonl", "py", "r", "swift", "js", "ts", "sh", "yaml", "yml", "toml", "xml",
             "tex", "bib", "sql", "css", "c", "h", "cpp", "go", "rs", "rb", "pl", "jl", "lua", "ini", "cfg", "conf":
            return .text
        default: return nil
        }
    }

    static func handles(_ f: RemoteFile) -> Bool { kind(f) != nil }

    var body: some View {
        NavigationStack {
            Group {
                if let text {
                    content(text)
                } else if let failed {
                    ContentUnavailableView("Couldn't open it", systemImage: "doc.questionmark",
                                           description: Text(failed))
                } else {
                    ProgressView("Asking your Mac").frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if truncated {
                    Text("Large file (\(ByteCountFormatter.string(fromByteCount: Int64(file.bytes ?? 0), countStyle: .file))) — showing the start. Share it to see all of it.")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(8).frame(maxWidth: .infinity).background(.bar)
                }
            }
            .navigationTitle(file.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        if Self.kind(file) == .page {
                            Toggle(isOn: $showSource) { Label("Show source", systemImage: "chevron.left.forwardslash.chevron.right") }
                        }
                        if let text {
                            Button {
                                UIPasteboard.general.string = text
                                Haptics.success()
                            } label: { Label("Copy contents", systemImage: "doc.on.doc") }
                        }
                        Button { share() } label: { Label("Share", systemImage: "square.and.arrow.up") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .sheet(item: $shareURL) { ActivityView(items: [$0]).ignoresSafeArea() }
            .task { await load() }
        }
    }

    @ViewBuilder
    private func content(_ text: String) -> some View {
        switch Self.kind(file) ?? .text {
        case .markdown:
            ScrollView { MarkdownText(text).padding() }
        case .table:
            ScrollView {
                TableBlock(rows: CSV.parse(text, separator: file.ext == "tsv" ? "\t" : ","), full: true).padding()
            }
        case .notebook:
            ScrollView { NotebookCells(json: text).padding() }
        case .page:
            if showSource { NumberedText(text: text) } else { SandboxedPage(html: text).ignoresSafeArea(edges: .bottom) }
        case .text:
            NumberedText(text: prettyIfJSON(text))
        }
    }

    private func prettyIfJSON(_ s: String) -> String {
        guard file.ext == "json", s.utf8.count < 1_000_000,
              let obj = try? JSONSerialization.jsonObject(with: Data(s.utf8), options: [.fragmentsAllowed]),
              let d = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .withoutEscapingSlashes, .fragmentsAllowed])
        else { return s }
        return String(decoding: d, as: UTF8.self)
    }

    private func load() async {
        guard let server = state.server else { failed = "Not paired with a Mac."; return }
        do {
            var data = try await server.workspaceBytes(rel: file.rel)
            // a notebook cut short is not JSON any more: read those whole
            if data.count > Self.limit && file.ext != "ipynb" {
                data = data.prefix(Self.limit)
                truncated = true
            }
            text = String(decoding: data, as: UTF8.self)
        } catch { failed = error.localizedDescription }
    }

    private func share() {
        guard let server = state.server else { return }
        Task {
            do { shareURL = try await server.download(rel: file.rel, name: file.name) }
            catch { failed = error.localizedDescription }
        }
    }
}

/// Monospaced text with line numbers, scrolling both ways.
struct NumberedText: View {
    let text: String

    var body: some View {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let width = CGFloat(String(lines.count).count) * 8 + 6
        ScrollView([.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(i + 1)").foregroundStyle(.tertiary).frame(width: width, alignment: .trailing)
                        Text(String(line)).textSelection(.enabled)
                    }
                    .font(.system(.caption, design: .monospaced))
                    .fixedSize(horizontal: true, vertical: true)
                }
            }
            .padding(12)
        }
    }
}

/// A Jupyter notebook's cells: Markdown rendered, code with what it printed and drew.
struct NotebookCells: View {
    private let cells: [Cell]?
    private let language: String

    /// Read once: a notebook with plots is megabytes of JSON.
    init(json: String) {
        language = Self.language(json)
        cells = Self.cells(json)
    }

    private struct Cell: Identifiable {
        let id: Int
        let kind: String
        let source: String
        let outputs: [Output]
    }

    private enum Output { case text(String), image(UIImage) }

    private static func language(_ json: String) -> String {
        guard let o = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let meta = o["metadata"] as? [String: Any],
              let info = meta["language_info"] as? [String: Any], let name = info["name"] as? String else { return "python" }
        return name
    }

    private static func cells(_ json: String) -> [Cell]? {
        guard let o = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let raw = o["cells"] as? [[String: Any]] else { return nil }
        func joined(_ v: Any?) -> String {
            if let s = v as? String { return s }
            return ((v as? [Any]) ?? []).map { "\($0)" }.joined()
        }
        return raw.enumerated().map { i, c in
            var outs: [Output] = []
            for out in (c["outputs"] as? [[String: Any]]) ?? [] {
                if let t = out["text"] { outs.append(.text(joined(t))) }
                if let data = out["data"] as? [String: Any] {
                    if let png = data["image/png"], let d = Data(base64Encoded: joined(png).replacingOccurrences(of: "\n", with: "")),
                       let img = UIImage(data: d) {
                        outs.append(.image(img))
                    } else if let plain = data["text/plain"] {
                        outs.append(.text(joined(plain)))
                    }
                }
                if let tb = out["traceback"] as? [Any] {
                    // tracebacks carry terminal colour codes
                    let clean = tb.map { "\($0)" }.joined(separator: "\n")
                        .replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
                    outs.append(.text(clean))
                }
            }
            return Cell(id: i, kind: (c["cell_type"] as? String) ?? "code", source: joined(c["source"]), outputs: outs)
        }
    }

    var body: some View {
        if let cells {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(cells) { cell in
                    if cell.kind == "markdown" {
                        MarkdownText(cell.source)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            CodeBlock(language: cell.kind == "code" ? language : cell.kind, code: cell.source)
                            ForEach(Array(cell.outputs.enumerated()), id: \.offset) { _, out in
                                switch out {
                                case .text(let t):
                                    Text(t).font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary).textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                case .image(let img):
                                    Image(uiImage: img).resizable().scaledToFit()
                                        .frame(maxWidth: .infinity, maxHeight: 320)
                                }
                            }
                        }
                    }
                }
            }
        } else {
            Text("This notebook could not be read.").foregroundStyle(.secondary)
        }
    }
}
