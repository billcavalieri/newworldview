import SwiftUI

struct MillResearchSettingsView: View {
    @EnvironmentObject private var millSettings: MillResearchSettings

    var body: some View {
        Form {
            Section {
                Picker("Logs per analysis", selection: $millSettings.logScanLimit) {
                    ForEach(MillResearchSettings.scanLimitOptions, id: \.self) { limit in
                        Text(MillResearchSettings.label(for: limit))
                            .tag(limit)
                    }
                }
                Picker("Histogram entries", selection: $millSettings.histogramLimit) {
                    ForEach(MillResearchSettings.histogramLimitOptions, id: \.self) { limit in
                        Text(MillResearchSettings.histogramLabel(for: limit))
                            .tag(limit)
                    }
                }
                Toggle("KEEP logs only", isOn: $millSettings.keepLogsOnly)
            } header: {
                Text("Historical mill logs")
            } footer: {
                Text("KEEP logs only prioritizes state.json keep_log, pinned mill logs (6613/1116/680/35/22), and logs that reached stable 68k. Histogram entries controls how many ranked offsets are kept (Unlimited exports the full histogram).")
            }

            Section {
                Stepper(
                    "Batch triage count: \(millSettings.batchTriageCount)",
                    value: $millSettings.batchTriageCount,
                    in: 1...100
                )
                HStack {
                    Text("FM confidence threshold")
                    Slider(value: $millSettings.fmConfidenceThreshold, in: 0.1...1.0)
                    Text(String(format: "%.0f%%", millSettings.fmConfidenceThreshold * 100))
                        .font(.caption.monospacedDigit())
                        .frame(width: 44)
                }
            } header: {
                Text("Apple Foundation Model")
            } footer: {
                Text("Classifications below the confidence threshold stay pending and suggest Grok Build escalation.")
            }

            Section {
                HStack {
                    Text(millSettings.macemuRepoPath.isEmpty ? "Not set" : millSettings.macemuRepoPath)
                        .font(.caption.monospaced())
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Choose…") {
                        chooseMacemuRepo()
                    }
                }
                TextField("Grok binary path (optional)", text: $millSettings.grokPath)
                    .font(.caption.monospaced())
            } header: {
                Text("Grok Build CLI")
            } footer: {
                Text("Escalation exports pack-escalation.md and grok-prompt.md. Optional macemu repo access enables Run Grok Build from the app.")
            }

            Section {
                Button("Reset to Defaults") {
                    millSettings.resetToDefaults()
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 420)
        .navigationTitle("Mill Research")
    }

    private func chooseMacemuRepo() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Select the macemu repository root for Grok Build."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        millSettings.setMacemuRepo(url)
    }
}
