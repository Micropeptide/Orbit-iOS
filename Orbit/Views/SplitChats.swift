import SwiftUI

/// Two panes on a wide screen. The sidebar is the same list; picking a chat
/// fills the detail rather than pushing a new screen.
struct SplitChats: View {
    @EnvironmentObject var state: AppState
    @State private var selected: String?
    @StateObject private var listModel = ChatListModel()     // Views/Chat/ChatListExtras.swift

    var body: some View {
        NavigationSplitView {
            List(sorted, selection: $selected) { chat in
                NavigationLink(value: chat.id) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(chat.displayTitle).lineLimit(1)
                        Text("\(chat.n) messages").font(.caption2)
                            .foregroundStyle(.secondary)
                        ChatStatusBadge(status: state.status(of: chat, seen: listModel.seen))
                    }
                }
                .contextMenu { ChatRowMenu(chat: chat, model: listModel) }
            }
            .navigationTitle("Chats")
            .refreshable { await state.refreshEverything() }
            .task {
                while !Task.isCancelled {
                    await state.refreshRunningState()
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                }
            }
            // a fork or a temporary chat opens in the detail pane
            .onChange(of: state.deepLink) { _, sid in
                guard let sid else { return }
                selected = sid
                state.deepLink = nil
            }
            .onChange(of: selected) { _, _ in listModel.refreshSeen() }
            .modifier(ChatListHost(model: listModel))
            .toolbar {
                ToolbarItem {
                    Button {
                        Task { selected = await state.newChat() }
                    } label: { Image(systemName: "square.and.pencil") }
                    .contextMenu {
                        Button { Task { await state.startTemporaryChat() } } label: {
                            Label("New temporary chat", systemImage: "flame")
                        }
                    }
                }
            }
        } detail: {
            if let selected {
                ChatView(sid: selected)
            } else {
                ContentUnavailableView("Pick a conversation",
                                       systemImage: "bubble.left.and.bubble.right")
            }
        }
    }

    private var sorted: [ChatSummary] {
        state.chats.filter { $0.archived != true }.sorted {
            if ($0.pinned ?? false) != ($1.pinned ?? false) { return $0.pinned ?? false }
            return $0.mtime > $1.mtime
        }
    }
}
