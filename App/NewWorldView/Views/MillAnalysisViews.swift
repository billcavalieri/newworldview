import AppKit
import NewWorldROM
import SwiftUI

struct MillAnalysisVerdictCard: View {
    let annotation: MillAnnotation
    var onApprove: (() -> Void)?
    var onReject: (() -> Void)?
    var onEscalate: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(annotation.classification.kind.displayName)
                    .font(.caption.bold())
                Text(annotation.classification.recommendedAction.displayName)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                Text(String(format: "%.0f%%", annotation.classification.confidence * 100))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(annotation.status.rawValue)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }

            Text(annotation.address.display)
                .font(.caption.monospaced())

            if let reachability = annotation.contextSnapshot.reachability {
                Text("Reachability: \(reachability.verdict.rawValue)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(annotation.classification.reasoning)
                .font(.caption)
                .textSelection(.enabled)

            HStack(spacing: 8) {
                if annotation.status == .pending {
                    Button("Approve", action: { onApprove?() })
                    Button("Reject", role: .destructive, action: { onReject?() })
                }
                if annotation.suggestsEscalation {
                    Button("Escalate to Grok Build", action: { onEscalate?() })
                }
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private var statusColor: Color {
        switch annotation.status {
        case .pending: return .orange
        case .approved: return .green
        case .rejected: return .red
        }
    }
}

struct MillAnnotationQueueView: View {
    @ObservedObject var millAnalysis: MillAnalysisService
    let database: AnalysisDatabase
    var onNavigateAddress: (ProgramAddress) -> Void
    var onEscalate: (MillAnnotation) -> Void

    @State private var filter: AnnotationStatus? = .pending

    var body: some View {
        VStack(spacing: 0) {
            queueToolbar
            Divider()
            ScrollView(.vertical) {
                queueContent
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var queueToolbar: some View {
        HStack(spacing: 12) {
            Text("Annotation queue")
                .font(.headline)

            Picker("Filter", selection: $filter) {
                Text("All").tag(Optional<AnnotationStatus>.none)
                ForEach(AnnotationStatus.allCases, id: \.self) { status in
                    Text(status.rawValue.capitalized).tag(Optional(status))
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)

            if let filter {
                Text("\(millAnalysis.filteredAnnotations(status: filter).count) \(filter.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(millAnalysis.annotations.count) total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Export approved JSON") {
                exportApproved()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var queueContent: some View {
        MillAnalysisStatusBanner(millAnalysis: millAnalysis)

        if millAnalysis.isClassifying {
            ProgressView("Classifying…")
                .padding(.vertical, 4)
        }

        let items = millAnalysis.filteredAnnotations(status: filter)
        if items.isEmpty {
            ContentUnavailableView(
                filter == .pending ? "No pending annotations" : "No annotations",
                systemImage: "checklist",
                description: Text("Classify an address in the Research inspector, or triage hotspots on the Mill logs tab.")
            )
            .frame(maxWidth: .infinity, minHeight: 240)
        } else {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(items) { annotation in
                    VStack(alignment: .leading, spacing: 6) {
                        MillAnalysisVerdictCard(
                            annotation: annotation,
                            onApprove: { _ = millAnalysis.approve(id: annotation.id, database: database) },
                            onReject: { millAnalysis.reject(id: annotation.id) },
                            onEscalate: { onEscalate(annotation) }
                        )
                        Button("Navigate") {
                            onNavigateAddress(annotation.address)
                        }
                        .controlSize(.small)
                    }
                }
            }
        }

        if let error = millAnalysis.lastError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private func exportApproved() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        panel.message = "Choose a folder for mill-annotations.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let exported = try millAnalysis.exportApprovedAnnotations(to: url)
            NSWorkspace.shared.activateFileViewerSelecting([exported])
            millAnalysis.lastError = nil
        } catch {
            millAnalysis.lastError = error.localizedDescription
        }
    }
}

struct MillAnalysisStatusBanner: View {
    @ObservedObject var millAnalysis: MillAnalysisService

    var body: some View {
        if millAnalysis.modelAvailable {
            Text("Apple Foundation Model ready for on-device classification.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else if let reason = millAnalysis.modelUnavailableReason {
            Text("Apple FM unavailable: \(reason)")
                .font(.caption2)
                .foregroundStyle(.orange)
        }
    }
}
