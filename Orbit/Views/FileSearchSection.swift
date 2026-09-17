import SwiftUI
import QuickLook

/// Search in the chat list also finds files in the workspace by name, as the
/// web page's search does. The list is read when a search starts (and again
/// once it is a couple of minutes old) and filtered here — the Mac has no
/// file-name search of its own.
struct FileSearchSection: View {
    @EnvironmentObject var state: AppState
    let query: String
    @StateObject private var model = FileSearchModel()
    @State private var preview: URL?
    @State private var failed: String?

    private var term: String { query.trimmingCharacters(in: .whitespaces).lowercased() }

    private var matches: [RemoteFile] {
        guard term.count >= 2 else { return [] }
        return model.files.filter { $0.name.lowercased().contains(term) || $0.rel.lowercased().contains(term) }
            .sorted { $0.mtime > $1.mtime }
            .prefix(8).map { $0 }
    }

    var body: some View {
        if term.count >= 2 && model.needsLoad {
            // the row exists only while the list is being read, so its task is what reads it
            HStack(spacing: 8) {
                ProgressView().controlSize(.mini)
                Text("searching files").font(.caption).foregroundStyle(.secondary)
            }
            .task { await model.load(state.server) }
        } else if !matches.isEmpty {
            Section("Files") {
                ForEach(matches) { f in
                    Button { open(f) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: f.symbol).foregroundStyle(.secondary).frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(f.name).font(.callout).lineLimit(1).foregroundStyle(.primary)
                                Text(f.rel).font(.caption2).foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                if let failed { Text(failed).font(.caption).foregroundStyle(.orange) }
            }
            .quickLookPreview($preview)
        }
    }

    private func open(_ f: RemoteFile) {
        guard let server = state.server else { return }
        Task {
            do { preview = try await server.download(rel: f.rel, name: f.name); failed = nil }
            catch { failed = error.localizedDescription }
        }
    }
}

@MainActor
final class FileSearchModel: ObservableObject {
    @Published var files: [RemoteFile] = []
    @Published private(set) var loadedAt: Date?

    var needsLoad: Bool {
        guard let loadedAt else { return true }
        return Date().timeIntervalSince(loadedAt) > 120
    }

    func load(_ server: OrbitServer?) async {
        guard let server else { loadedAt = Date(); return }
        files = (try? await server.files(limit: 200)) ?? files
        // a Mac that did not answer is not asked again on every keystroke
        loadedAt = Date()
    }
}
