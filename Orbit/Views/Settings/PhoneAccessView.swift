import SwiftUI

/// Settings → Phone on the Mac: how phones reach it, and the pairing token.
/// Both switches can cut this very phone off, so both ask hard first.
struct PhoneAccessView: View {
    @EnvironmentObject var state: AppState
    @State private var remote: RemoteAccess?
    @State private var error: String?
    @State private var note: String?
    @State private var pendingMode: String?
    @State private var confirmRotate = false
    @State private var busy = false

    private let modes: [(id: String, label: String, why: String)] = [
        ("off", "Off", "Only the Mac itself can reach Orbit. The default."),
        ("tailscale", "Tailscale", "Reachable from anywhere on your tailnet, and bound to the tailnet "
            + "interface only — the port is not on whatever Wi-Fi the Mac is using."),
        ("lan", "Local network", "Reachable from the Mac's Wi-Fi. Simplest at home; don't use it on a "
            + "network you don't trust."),
    ]

    var body: some View {
        List {
            if let error { ErrorRow(message: error) }
            if let r = remote {
                Section {
                    ForEach(modes, id: \.id) { m in
                        Button {
                            if m.id != r.mode { pendingMode = m.id }
                        } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(m.label).foregroundStyle(.primary)
                                    Text(m.why).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if m.id == r.mode { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                        }
                        .tint(.primary)
                        .disabled(busy)
                    }
                    if let h = r.hint, !h.isEmpty {
                        Text(h).font(.caption).foregroundStyle(.orange)
                    }
                } header: {
                    Text("Phone access")
                } footer: {
                    Text("A change takes effect when Orbit restarts on the Mac (Status & health → Restart Orbit). "
                         + "Orbit has no login, so nothing reaches it unpaired.")
                }

                Section("Status") {
                    LabeledContent("Reachable at") {
                        Text(r.url ?? "not reachable yet").font(.caption.monospaced())
                            .lineLimit(1).truncationMode(.middle)
                    }
                    if !r.alts.isEmpty {
                        LabeledContent("Also at") {
                            Text(r.alts.joined(separator: "\n")).font(.caption.monospaced())
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    LabeledContent("Tailscale", value: tailscaleLine(r.tailscale))
                    LabeledContent("Pairing token", value: r.tokenSet ? "set" : "none")
                }

                if r.enabled {
                    Section {
                        Button("Rotate pairing token", role: .destructive) { confirmRotate = true }
                            .disabled(busy)
                    } footer: {
                        Text("Unpairs every device, including this phone. Use it if a phone is lost; then scan "
                             + "the new code in Settings → Phone on the Mac.")
                    }
                }
            } else if error == nil {
                LoadingRow()
            }
        }
        .navigationTitle("Phone access")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .settingsNote($note)
        .confirmationDialog(modeTitle, isPresented: Binding(
            get: { pendingMode != nil }, set: { if !$0 { pendingMode = nil } }), titleVisibility: .visible) {
            if let m = pendingMode {
                Button(m == "off" ? "Turn phone access off" : "Switch to \(label(m))",
                       role: .destructive) { Task { await setMode(m) } }
            }
            Button("Cancel", role: .cancel) { pendingMode = nil }
        } message: {
            Text(modeMessage)
        }
        .confirmationDialog("Rotate the pairing token?", isPresented: $confirmRotate, titleVisibility: .visible) {
            Button("Rotate — unpair every device", role: .destructive) { Task { await rotate() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every paired device stops working at once — this phone too. To use Orbit here again you "
                 + "will need to be at the Mac and scan the new QR code.")
        }
    }

    private var modeTitle: String {
        pendingMode == "off" ? "Turn off phone access?" : "Change how phones reach the Mac?"
    }

    private var modeMessage: String {
        guard let m = pendingMode else { return "" }
        if m == "off" {
            return "Once Orbit restarts, no phone can reach it — this one included. You can only turn it "
                + "back on at the Mac itself."
        }
        return "Once Orbit restarts it answers only on \(label(m)). If this phone isn't on that network "
            + "it loses the connection until you pair again at the Mac."
    }

    private func label(_ id: String) -> String { modes.first { $0.id == id }?.label ?? id }

    private func tailscaleLine(_ t: RemoteAccess.Tailscale?) -> String {
        guard let t, t.installed ?? false else { return "not installed" }
        guard t.running ?? false else { return "installed, not connected" }
        return "connected" + (t.name.map { " · \($0)" } ?? "")
    }

    private func load() async {
        do { remote = try await state.requireServer().remoteAccess(); error = nil }
        catch { self.error = error.localizedDescription }
    }

    private func setMode(_ m: String) async {
        pendingMode = nil
        busy = true
        defer { busy = false }
        do {
            try await state.requireServer().setRemoteMode(m)
            note = "saved — restart Orbit to apply"
            await load()
        } catch { note = error.localizedDescription }
    }

    private func rotate() async {
        busy = true
        defer { busy = false }
        do {
            try await state.requireServer().rotateRemoteToken()
            note = "new token — scan it at the Mac"
            await load()
        } catch { note = error.localizedDescription }
    }
}
