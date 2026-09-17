import SwiftUI

struct ModelPickerView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    /// Only these models (the new-chat sheet shows one harness's). nil = all.
    var only: ((ModelInfo) -> Bool)? = nil
    /// The model to tick. nil = the open chat's.
    var selected: String? = nil
    var title = "Model for this chat"
    /// Called instead of changing the open chat's model.
    var onPick: ((ModelInfo) -> Void)? = nil
    /// Pushed inside another sheet's navigation rather than presented on its own.
    var embedded = false
    @State private var filter = ""

    private var grouped: [(String, [ModelInfo])] {
        let q = filter.trimmingCharacters(in: .whitespaces).lowercased()
        let shown = state.models.filter { m in
            (only?(m) ?? true)
                && (q.isEmpty || m.display.lowercased().contains(q) || m.group.lowercased().contains(q))
        }
        return Dictionary(grouping: shown) { $0.group }
            .sorted { $0.key < $1.key }
    }

    private var tickedID: String? { selected ?? state.effectiveModelID }

    var body: some View {
        if embedded {
            list
        } else {
            NavigationStack {
                list.toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
    }

    private var list: some View {
        List {
            ForEach(grouped, id: \.0) { provider, models in
                Section(provider) {
                    ForEach(models) { m in
                        Button {
                            if let onPick { onPick(m); dismiss() }
                            else { Task { await state.choose(model: m); dismiss() } }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(m.display).foregroundStyle(.primary)
                                    if let n = m.note, !n.isEmpty {
                                        Text(n).font(.caption2).foregroundStyle(.secondary)
                                    } else if !m.isReady {
                                        Text("needs an API key on your Mac")
                                            .font(.caption2).foregroundStyle(.orange)
                                    } else if let c = m.context {
                                        Text("\(c / 1000)k context")
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if m.id == tickedID {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                        .disabled(!m.isReady)
                    }
                }
            }
        }
        .searchable(text: $filter, prompt: "Filter models")
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if state.models.isEmpty {
                ContentUnavailableView("No models", systemImage: "cpu",
                    description: Text("Your Mac hasn't reported any models yet."))
            }
        }
    }
}
