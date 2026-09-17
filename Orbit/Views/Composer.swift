import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// The bar at the bottom of a conversation. Attachments come from three places
/// — the photo library, the camera, or the Files app — and each opens the real
/// system picker, so it looks and behaves like every other app on the phone.
struct Composer: View {
    @EnvironmentObject var state: AppState
    @Binding var draft: String
    var typing: FocusState<Bool>.Binding
    var modelName: String
    var onPickModel: () -> Void
    /// Returns true when it handled a `/command`, so the text is not sent as a message.
    var onCommand: ((String) -> Bool)? = nil

    static let commands: [(String, String)] = [
        ("/new", "start a new chat"), ("/model", "switch the model for this chat"),
        ("/compact", "compact the history"), ("/find", "find in this chat"),
        ("/rewind", "go back to an earlier message — chat only, or files too"),
        ("/context", "what is filling the context window right now"),
        ("/copy", "copy the last answer (/copy 2 for the one before)"),
        ("/diff", "every file change shown in this chat, as a diff"),
        ("/verbose", "show every tool call in full, or fold them again"),
        ("/todos", "show or hide the todo list"),
        ("/usage", "cost, tokens and time — this chat and lately"),
        ("/permissions", "what it may do without asking"),
        ("/theme", "light, dark or follow the system"),
        ("/fork", "copy this chat into a new one and carry on there"),
        ("/help", "show these commands"),
    ]

    /// A leading `!` runs a shell command; a single `# line` goes to memory.
    private enum Mode { case message, shell, memory }
    private var mode: Mode {
        if draft.hasPrefix("!") { return .shell }
        if draft.hasPrefix("# "), !draft.contains("\n") { return .memory }
        return .message
    }
    /// Library: the "/" menu (commands, saved prompts, Claude's commands) and what it opens.
    @StateObject private var slash = SlashController()

    @State private var showAttachMenu = false
    @State private var showLibrary = false
    @State private var showCamera = false
    @State private var showFiles = false
    @State private var picked: [PhotosPickerItem] = []
    @State private var showLater = false

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !state.attachments.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            if !state.queue.items.isEmpty { QueueStrip() }
            HStack(spacing: 8) {
            // Which model answers is the single fact you most want in view, so it
            // lives here rather than in a toolbar that folds it away when cramped.
            Button(action: onPickModel) {
                HStack(spacing: 5) {
                    Image(systemName: "cpu").font(.caption2)
                    Text(state.streaming && !state.liveModel.isEmpty ? state.liveModel : modelName)
                        .font(.caption.weight(.medium)).lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(.quaternary.opacity(0.35), in: .capsule)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Model: \(modelName). Tap to change.")
            OffpeakBadge()
            if canSend && !state.streaming {
                Button { showLater = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "clock").font(.caption2)
                        Text("Send later").font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.quaternary.opacity(0.35), in: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Send later")
            }
            }
            .padding(.top, 6)
            if !state.attachments.isEmpty || state.uploading { attachmentStrip }
            SlashMenu(draft: $draft, controller: slash, builtins: Self.commands, onCommand: onCommand)
            HStack(alignment: .bottom, spacing: 8) {
                Button {
                    Haptics.tap()
                    showAttachMenu = true
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .frame(width: 36, height: 36)
                        .background(.quaternary.opacity(0.5), in: .circle)
                }
                .disabled(state.streaming)
                .accessibilityLabel("Attach")

                TextField("Message", text: $draft, axis: .vertical)
                    .lineLimit(1...6)
                    .font(mode == .shell ? .body.monospaced() : .body)
                    .focused(typing)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(.background, in: .rect(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(modeBorder, lineWidth: mode == .message ? 1 : 1.5))

                if state.streaming && canSend {
                    // a note for the running answer, read at its next step
                    Button {
                        let text = draft
                        draft = ""
                        Haptics.tap()
                        Task { await state.steer(text) }
                    } label: {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.body.weight(.bold))
                            .frame(width: 36, height: 36)
                            .background(Color.accentColor, in: .circle)
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("Steer: send a note to the running answer")
                }
                if state.streaming {
                    Button {
                        Task { await state.stopGenerating() }
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.footnote.weight(.bold))
                            .frame(width: 36, height: 36)
                            .background(.red, in: .circle)
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("Stop")
                } else {
                    Button {
                        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        let sending = mode
                        draft = ""
                        Haptics.tap()
                        if sending == .shell {
                            let cmd = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
                            if !cmd.isEmpty { Task { await state.runBang(cmd) } }
                            return
                        }
                        if sending == .memory {
                            Task { await state.rememberLine(String(text.dropFirst(2))) }
                            return
                        }
                        if text.hasPrefix("/"), let replaced = slash.intercept(text, state: state) {
                            draft = replaced      // a saved prompt expands in place; a Library command ran
                            return
                        }
                        if text.hasPrefix("/"), onCommand?(text) == true { return }
                        Task { await state.send(text) }
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.body.weight(.bold))
                            .frame(width: 36, height: 36)
                            .background(canSend ? Color.accentColor : Color.secondary.opacity(0.35),
                                        in: .circle)
                            .foregroundStyle(.white)
                    }
                    .disabled(!canSend)
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityLabel("Send")
                    // hold to send it later instead
                    .contextMenu {
                        if canSend {
                            ForEach(SendLaterSheet.presets(), id: \.label) { p in
                                Button { schedule(at: p.date, repeat: .once) } label: {
                                    Label("Send \(p.label)", systemImage: "clock")
                                }
                            }
                            Button { showLater = true } label: {
                                Label("Pick a time…", systemImage: "calendar.badge.clock")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, mode == .message ? 6 : 4)
            if let hint = modeHint {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(modeBorder)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.bottom, 4)
            }
            PermissionModeLine()
        }
        .slashSheets(slash)
        .sheet(isPresented: $showLater) {
            SendLaterSheet { date, rep in schedule(at: date, repeat: rep) }
                .presentationDetents([.medium, .large])
        }
        // Three real pickers. Each is a system sheet, presented from a bool it
        // owns, so nothing is hidden under anything else.
        .confirmationDialog("Attach", isPresented: $showAttachMenu, titleVisibility: .hidden) {
            Button("Photo Library") { showLibrary = true }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take Photo") { showCamera = true }
            }
            Button("Choose File") { showFiles = true }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(isPresented: $showLibrary, selection: $picked,
                      maxSelectionCount: 4, matching: .images)
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            let batch = items
            picked = []
            Task { for item in batch { await state.attach(photo: item) } }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                showCamera = false
                guard let image else { return }
                Task { await state.attach(image: image) }
            }
            .ignoresSafeArea()
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.item],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                Task { for u in urls { await state.attach(fileAt: u) } }
            }
        }
    }

    private var modeBorder: AnyShapeStyle {
        switch mode {
        case .shell: return AnyShapeStyle(Color.orange)
        case .memory: return AnyShapeStyle(Color.purple)
        case .message: return AnyShapeStyle(.quaternary)
        }
    }

    private var modeHint: String? {
        switch mode {
        case .shell: return "! shell mode — runs in this chat's folder; the output joins the conversation"
        case .memory: return "# memory — send saves this line to memory"
        case .message: return nil
        }
    }

    /// The draft goes into the chat's queue for later, and the box clears.
    private func schedule(at date: Date, repeat rep: Repeat) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !(text.isEmpty && state.attachments.isEmpty) else { return }
        let kept = draft
        draft = ""
        Haptics.success()
        Task { if !(await state.sendLater(text, at: date, repeat: rep)) { draft = kept } }
    }

    /// What is going up with the next message, and how to change your mind.
    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(state.attachments) { a in
                    HStack(spacing: 6) {
                        if let thumb = a.thumbnail {
                            Image(uiImage: thumb).resizable().scaledToFill()
                                .frame(width: 28, height: 28).clipShape(.rect(cornerRadius: 6))
                        } else {
                            Image(systemName: a.kind == "image" ? "photo" : "doc").font(.caption)
                        }
                        Text(a.name).font(.caption).lineLimit(1).frame(maxWidth: 140)
                        Button {
                            state.attachments.removeAll { $0.id == a.id }
                        } label: { Image(systemName: "xmark.circle.fill").font(.caption) }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                    .padding(.leading, 6).padding(.trailing, 9).padding(.vertical, 5)
                    .background(.quaternary.opacity(0.5), in: .capsule)
                }
                if state.uploading {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("uploading").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 9).padding(.vertical, 6)
                }
            }
            .padding(.horizontal, 12).padding(.top, 8)
        }
        .frame(height: 46)
    }
}

/// The system camera, wrapped. Returns nil if the person backs out.
struct CameraPicker: UIViewControllerRepresentable {
    var onDone: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let c = UIImagePickerController()
        c.sourceType = .camera
        c.delegate = context.coordinator
        return c
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onDone: (UIImage?) -> Void
        init(onDone: @escaping (UIImage?) -> Void) { self.onDone = onDone }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onDone(info[.originalImage] as? UIImage)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onDone(nil) }
    }
}
