import SwiftUI

struct MillLogAnalysisProgressView: View {
    let progress: MillLogAnalysisProgress
    var compact: Bool = false
    var onCancel: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            if progress.total > 0 {
                ProgressView(value: progress.fraction) {
                    Text(progress.statusText)
                        .font(compact ? .caption : .body)
                } currentValueLabel: {
                    Text("\(Int(progress.fraction * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .progressViewStyle(.linear)
            } else {
                ProgressView {
                    Text("Preparing log scan…")
                        .font(compact ? .caption : .body)
                }
                .progressViewStyle(.linear)
            }

            if progress.startedAt != nil {
                TimelineView(.periodic(from: progress.startedAt ?? .now, by: 1.0)) { context in
                    statisticsView(for: progress.statistics(at: context.date))
                }
            }

            if let currentFileName = progress.currentFileName {
                Text(currentFileName)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if let onCancel {
                Button("Cancel", role: .cancel, action: onCancel)
                    .controlSize(compact ? .small : .regular)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func statisticsView(for statistics: MillLogAnalysisStatistics) -> some View {
        if compact {
            VStack(alignment: .leading, spacing: 2) {
                Text("Elapsed \(statistics.elapsedText) · Remaining \(statistics.remainingText)")
                Text("Rate \(statistics.rateText)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        } else {
            HStack(spacing: 16) {
                statisticItem(title: "Elapsed", value: statistics.elapsedText)
                statisticItem(title: "Remaining", value: statistics.remainingText)
                statisticItem(title: "Rate", value: statistics.rateText)
            }
        }
    }

    private func statisticItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
