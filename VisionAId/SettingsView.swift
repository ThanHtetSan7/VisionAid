import SwiftUI

/// Lets the user choose which objects to detect, how sure the model must be, and which lens to use.
struct SettingsView: View {
    @Bindable var vm: DetectionViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    /// Walking obstacles first, sorted by risk, then everything else alphabetically.
    private let obstacles = Obstacles.allLabels
        .filter { Obstacles.defaultEnabled.contains($0) }
        .sorted { (Obstacles.risk(of: $0), $1) > (Obstacles.risk(of: $1), $0) }
    private let others = Obstacles.allLabels
        .filter { !Obstacles.defaultEnabled.contains($0) }
        .sorted()

    var body: some View {
        NavigationStack {
            List {
                if search.isEmpty {
                    Section {
                        VStack(alignment: .leading) {
                            Text("Minimum confidence: \(Int(vm.minConfidence * 100))%")
                            Slider(value: $vm.minConfidence, in: 0.25...0.85, step: 0.05)
                                .accessibilityLabel("Minimum confidence")
                                .accessibilityValue("\(Int(vm.minConfidence * 100)) percent")
                        }
                        Toggle("Only warn about my path", isOn: $vm.pathOnly)
                        Toggle("Ultra-wide lens", isOn: $vm.ultraWide)
                    } header: {
                        Text("Detection")
                    } footer: {
                        Text("Higher confidence means fewer false alarms but more missed objects. Warning only about your path ignores things beside you, including traffic on the road. The ultra-wide lens sees more of the path but detects small or distant objects less reliably.")
                    }
                }

                labelSection("Obstacles", labels: obstacles)
                labelSection("Other objects", labels: others)
            }
            .searchable(text: $search, prompt: "Search objects")
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu("Select") {
                        Button("Obstacles only") { vm.enabledLabels = Obstacles.defaultEnabled }
                        Button("All objects") { vm.enabledLabels = Set(Obstacles.allLabels) }
                        Button("None") { vm.enabledLabels = [] }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func labelSection(_ title: String, labels: [String]) -> some View {
        let shown = search.isEmpty ? labels : labels.filter { $0.localizedCaseInsensitiveContains(search) }
        if !shown.isEmpty {
            Section(title) {
                ForEach(shown, id: \.self) { label in
                    Toggle(label.capitalized, isOn: binding(for: label))
                }
            }
        }
    }

    private func binding(for label: String) -> Binding<Bool> {
        Binding(
            get: { vm.enabledLabels.contains(label) },
            set: { on in
                if on { vm.enabledLabels.insert(label) } else { vm.enabledLabels.remove(label) }
            }
        )
    }
}
