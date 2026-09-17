import SwiftUI

/// What the chat list presents: tags, projects, rename, export. One per list.
@MainActor
final class ChatListModel: ObservableObject {
    @Published var tagging: ChatSummary?
    @Published var showProjects = false
    @Published var showStats = false
    @Published var renaming: ChatSummary?
    @Published var newTitle = ""
    @Published var exportURL: URL?
    @Published var seen: [String: Double] = SeenChats.all()

    func refreshSeen() { seen = SeenChats.all() }
}

/// A chat's state at a glance: waiting for you, answering, queued, new, scheduled.
struct ChatStatusBadge: View {
    let status: ChatRowStatus

    var body: some View {
        switch status {
        case .none:
            EmptyView()
        case .waiting:
            badge("exclamationmark.circle.fill", status.label!, .orange)
        case .answering:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("answering").font(.caption2.weight(.medium)).foregroundStyle(.tint)
            }
        case .queued:
            badge("tray.full", status.label!, .purple)
        case .unread:
            HStack(spacing: 4) {
                Circle().fill(Color.accentColor).frame(width: 7, height: 7)
                Text("new").font(.caption2.weight(.medium)).foregroundStyle(.tint)
            }
            .accessibilityElement(children: .combine)
        case .scheduled:
            badge("clock", status.label!, .secondary)
        }
    }

    private func badge(_ icon: String, _ text: String, _ tint: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.caption2.weight(.medium))
            .foregroundStyle(tint)
            .labelStyle(.titleAndIcon)
    }
}

/// Everything you can do to a chat from the list, as the Mac's chat menu offers it.
struct ChatRowMenu: View {
    let chat: ChatSummary
    @ObservedObject var model: ChatListModel
    @EnvironmentObject var state: AppState

    var body: some View {
        Button {
            Task { await state.setPinned(chat.id, !(chat.pinned ?? false)) }
        } label: {
            Label(chat.pinned == true ? "Unpin" : "Pin to top", systemImage: chat.pinned == true ? "pin.slash" : "pin")
        }
        Button {
            model.newTitle = chat.displayTitle
            model.renaming = chat
        } label: { Label("Rename", systemImage: "pencil") }
        Button { model.tagging = chat } label: {
            Label("Tags…", systemImage: "tag")
        }
        Menu {
            ForEach(state.projects) { p in
                Button {
                    Task { await state.assign(chat.id, project: p.id) }
                } label: {
                    if chat.project == p.id {
                        Label(p.name, systemImage: "checkmark")
                    } else {
                        Text(p.name)
                    }
                }
            }
            if chat.project != nil {
                Divider()
                Button(role: .destructive) {
                    Task { await state.assign(chat.id, project: nil) }
                } label: { Label("Remove from project", systemImage: "folder.badge.minus") }
            }
            Divider()
            Button { model.showProjects = true } label: {
                Label("Manage projects…", systemImage: "folder.badge.gearshape")
            }
        } label: {
            Label("Project", systemImage: "folder")
        }
        Button {
            Task {
                guard let server = state.server else { return }
                do { model.exportURL = try await server.exportMarkdown(chat.id, title: chat.displayTitle) }
                catch { state.lastError = error.localizedDescription }
            }
        } label: { Label("Export Markdown", systemImage: "square.and.arrow.up") }
        Button {
            Task { await state.setArchived(chat.id, !(chat.archived ?? false)) }
        } label: {
            Label(chat.archived == true ? "Unarchive" : "Archive", systemImage: "archivebox")
        }
        Button {
            Task { await state.sortByRecent() }
        } label: { Label("Sort by most recent", systemImage: "arrow.up.arrow.down") }
        Divider()
        Button(role: .destructive) {
            Task { await state.binWithUndo(chat.id) }
        } label: { Label("Move to bin", systemImage: "trash") }
    }
}

/// Sheets and alerts for the list, attached once.
struct ChatListHost: ViewModifier {
    @ObservedObject var model: ChatListModel
    @EnvironmentObject var state: AppState

    func body(content: Content) -> some View {
        content
            .sheet(item: $model.tagging) { TagsEditor(chat: $0) }
            .sheet(isPresented: $model.showProjects) { ProjectsManager() }
            .sheet(isPresented: $model.showStats) { UsageStatsView(sid: nil) }
            .sheet(item: $model.exportURL) { ActivityView(items: [$0]).ignoresSafeArea() }
            .alert("Rename chat", isPresented: Binding(
                get: { model.renaming != nil },
                set: { if !$0 { model.renaming = nil } })) {
                TextField("Title", text: $model.newTitle)
                Button("Save") {
                    if let c = model.renaming {
                        let t = model.newTitle
                        Task { await state.rename(c.id, to: t) }
                    }
                    model.renaming = nil
                }
                Button("Cancel", role: .cancel) { model.renaming = nil }
            }
            .modifier(ToastOverlay())
    }
}

/// Tags on one chat: tap to toggle, or add a new one.
struct TagsEditor: View {
    let chat: ChatSummary
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var tags: [String] = []
    @State private var known: [(name: String, count: Int)] = []
    @State private var adding = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("New tag", text: $adding)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .onSubmit(add)
                        Button("Add", action: add)
                            .disabled(adding.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Section("Tags") {
                    let all = Array(NSOrderedSet(array: tags + known.map(\.name))) as? [String] ?? tags
                    if all.isEmpty { Text("No tags yet").foregroundStyle(.secondary) }
                    ForEach(all, id: \.self) { t in
                        Button {
                            if let i = tags.firstIndex(of: t) { tags.remove(at: i) } else { tags.append(t) }
                        } label: {
                            HStack {
                                Image(systemName: tags.contains(t) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(tags.contains(t) ? Color.accentColor : .secondary)
                                Text(t).foregroundStyle(.primary)
                                Spacer()
                                if let n = known.first(where: { $0.name == t })?.count {
                                    Text("\(n)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(chat.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let t = tags
                        Task { await state.setTags(chat.id, t) }
                        dismiss()
                    }
                }
            }
            .task {
                tags = chat.tags ?? []
                if let server = state.server { known = (try? await server.tags()) ?? [] }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func add() {
        for part in adding.split(separator: ",") {
            let t = part.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty, !tags.contains(t) { tags.append(t) }
        }
        adding = ""
    }
}

/// Projects: folders for chats, with their own instructions.
struct ProjectsManager: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var items: [ProjectDetail] = []
    @State private var editing: ProjectDetail?
    @State private var deleting: ProjectDetail?

    var body: some View {
        NavigationStack {
            List {
                if items.isEmpty {
                    Text("No projects yet. A project groups chats and adds its instructions to each of them.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(items) { p in
                    Button { editing = p } label: {
                        HStack(spacing: 10) {
                            Circle().fill(Color(projectHex: p.color)).frame(width: 12, height: 12)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name).foregroundStyle(.primary)
                                let n = state.chats.filter { $0.project == p.id }.count
                                Text(p.description.isEmpty ? "\(n) chat\(n == 1 ? "" : "s")" : p.description)
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) { deleting = p } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
            .navigationTitle("Projects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { editing = ProjectDetail() } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New project")
                }
            }
            .sheet(item: $editing) { p in
                ProjectEditor(project: p) { Task { await load() } }
            }
            .confirmationDialog("Delete “\(deleting?.name ?? "")”?",
                                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible) {
                Button("Delete project", role: .destructive) {
                    guard let p = deleting, let server = state.server else { return }
                    Task {
                        do { try await server.deleteProject(p.id) }
                        catch { state.lastError = error.localizedDescription }
                        await load()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Its chats are kept; they just lose the project.")
            }
            .task { await load() }
        }
    }

    private func load() async {
        guard let server = state.server else { return }
        items = (try? await server.projectDetails()) ?? []
        await state.loadProjects()
        await state.loadChats()
    }
}

struct ProjectEditor: View {
    @State var project: ProjectDetail
    var saved: () -> Void
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $project.name)
                    TextField("What this project is about", text: $project.description)
                    HStack(spacing: 10) {
                        ForEach(ProjectDetail.colors, id: \.self) { c in
                            Circle().fill(Color(projectHex: c)).frame(width: 26, height: 26)
                                .overlay(Circle().strokeBorder(.primary, lineWidth: project.color == c ? 2 : 0))
                                .onTapGesture { project.color = c }
                                .accessibilityLabel("Colour \(c)")
                                .accessibilityAddTraits(project.color == c ? .isSelected : [])
                        }
                    }
                }
                Section {
                    TextField("/absolute/path (optional)", text: $project.folder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.callout.monospaced())
                    Toggle("Trust this folder's tools", isOn: $project.trustTools)
                } header: {
                    Text("Folder on the Mac")
                } footer: {
                    Text("A rules file there (ORBIT.md or AGENTS.md) and a .orbit/tools folder apply to this project's chats.")
                }
                Section {
                    TextEditor(text: $project.instructions).frame(minHeight: 140)
                } header: {
                    Text("Instructions")
                } footer: {
                    Text("Added to every chat in this project.")
                }
                if let error {
                    Text(error).foregroundStyle(.red).font(.footnote)
                }
            }
            .navigationTitle(project.id.isEmpty ? "New project" : "Edit project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(project.name.trimmingCharacters(in: .whitespaces).isEmpty || busy)
                }
            }
        }
    }

    private func save() async {
        guard let server = state.server else { return }
        let folder = project.folder.trimmingCharacters(in: .whitespaces)
        if !folder.isEmpty, !(folder.hasPrefix("/") || folder.hasPrefix("~/")) {
            error = "The folder needs an absolute path."
            return
        }
        busy = true
        defer { busy = false }
        var p = project
        p.name = p.name.trimmingCharacters(in: .whitespaces)
        p.folder = folder
        do {
            let r = try await server.saveProjectNotingFolder(p)
            saved()
            // saved either way; stay open so the warning is read before it is gone
            if r.folderMissing {
                project.id = r.id
                self.error = "Saved — but that folder does not exist yet."
                return
            }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

extension Color {
    /// "#6b5bd6" → a colour; anything unreadable is grey.
    init(projectHex hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard s.count == 6, let v = UInt32(s, radix: 16) else { self = .gray; return }
        self.init(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255,
                  blue: Double(v & 0xff) / 255)
    }
}
