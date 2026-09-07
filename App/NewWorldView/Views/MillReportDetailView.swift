import NewWorldROM
import SwiftUI

enum DetailPaneTab: String, CaseIterable, Identifiable {
    case rom
    case millLogs
    case annotations

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rom: return "ROM"
        case .millLogs: return "Mill logs"
        case .annotations: return "Annotations"
        }
    }
}

struct MillReportDetailView: View {
    private static let logSummaryPageSize = 100
    private static let offsetDisplayLimit = 250

    let report: MillResearchEngine.HistoricalReport
    var logDirectoryPath: String
    var annotationLookup: (ProgramAddress) -> MillAnnotation? = { _ in nil }
    var onNavigateOffset: (UInt64, AddressSpace) -> Void

    @State private var visibleLogSummaryCount = logSummaryPageSize

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 24) {
                headerSection
                MillHistogramPanel(
                    report: report,
                    annotationLookup: annotationLookup,
                    onNavigateOffset: onNavigateOffset
                )
                recommendationsSection
                logSummariesSection
                offsetSection(title: "PPC offsets", entries: report.topPPCOffsets)
                offsetSection(title: "68k offsets", entries: report.top68kOffsets)
                trapSection
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: report.scannedLogs) { _, _ in
            visibleLogSummaryCount = Self.logSummaryPageSize
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Historical mill log analysis")
                .font(.title2.bold())
            LabeledContent("Log directory") {
                Text(logDirectoryPath)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            }
            LabeledContent("Logs scanned") {
                if report.keepLogsOnly, report.totalAvailableLogs > report.scannedLogs {
                    Text("\(report.scannedLogs) KEEP of \(report.totalAvailableLogs) total")
                } else if report.discoveredLogs > report.scannedLogs {
                    Text("\(report.scannedLogs) of \(report.discoveredLogs)")
                } else if report.totalAvailableLogs > report.scannedLogs {
                    Text("\(report.scannedLogs) of \(report.totalAvailableLogs)")
                } else {
                    Text("\(report.scannedLogs)")
                }
            }
            if report.keepLogsOnly, report.totalAvailableLogs > report.discoveredLogs {
                LabeledContent("KEEP filter") {
                    Text("On — \(report.discoveredLogs) of \(report.totalAvailableLogs) logs")
                }
            }
            if report.logScanLimit > 0, report.discoveredLogs > report.scannedLogs {
                LabeledContent("Scan limit") {
                    Text("\(report.logScanLimit)")
                }
            }
            LabeledContent("Histogram limit") {
                Text(report.histogramLimit == 0 ? "Unlimited" : "\(report.histogramLimit)")
            }
            LabeledContent("68k histogram entries") {
                Text("\(report.top68kOffsets.count)")
            }
            LabeledContent("GetNewDialog stub hits") {
                Text("\(report.getNewDialogStubHits)")
            }
            LabeledContent("CFM Upgrader Launch A9F2") {
                Text("\(report.launchA9F2Count) in \(report.launchA9F2Logs) log(s)")
            }
            if report.pefEnterCount > 0 {
                LabeledContent("PEF enter") {
                    Text("\(report.pefEnterCount)")
                }
            }
            if report.pefImportCount > 0 {
                LabeledContent("PEF import idx=") {
                    Text("\(report.pefImportCount)")
                }
            }
            if report.pefWaitNextEventCount > 0 {
                LabeledContent("PEF WaitNextEvent") {
                    Text("\(report.pefWaitNextEventCount)")
                }
            }
            if report.pefHostedDSICount > 0 {
                LabeledContent("Hosted PEF DSI") {
                    Text("\(report.pefHostedDSICount)")
                }
            }
            if report.loadSeg66Logs > 0 {
                LabeledContent("LoadSeg seg=66 (false path)") {
                    Text("\(report.loadSeg66Logs) log(s) — kajr installer, not G3")
                }
            }
            if report.getNewDialogOverlayHits > 0 {
                LabeledContent("GetNewDialog overlay") {
                    Text("id=\(G3MillClassification.overlayResourceID) (\(report.getNewDialogOverlayHits)×)")
                }
            }
            if report.getNewDialogSplashHits > 0 {
                LabeledContent("GetNewDialog Splash") {
                    Text("id=\(G3MillClassification.splashResourceID) (\(report.getNewDialogSplashHits)×)")
                }
            }
            if report.xlateMissNersCount > 0 {
                LabeledContent("xlate miss 'ners'") {
                    Text("\(report.xlateMissNersCount)")
                }
            }
            LabeledContent("Heartbeat cluster hits") {
                Text("\(report.heartbeatClusterHits)")
            }
        }
    }

    private var recommendationsSection: some View {
        section(title: "Skip recommendations") {
            if report.skipRecommendations.isEmpty {
                Text("No recommendations generated.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(report.skipRecommendations, id: \.self) { line in
                        Text(line)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var visibleLogSummaries: [MillResearchEngine.LogSummary] {
        Array(report.logSummaries.prefix(visibleLogSummaryCount))
    }

    private var logSummariesSection: some View {
        section(title: "Log classifications (\(report.logSummaries.count))") {
            VStack(spacing: 0) {
                logSummaryHeader
                Divider()
                LazyVStack(spacing: 0) {
                    ForEach(visibleLogSummaries) { entry in
                        logSummaryRow(entry)
                        Divider()
                    }
                }
                if visibleLogSummaryCount < report.logSummaries.count {
                    Button("Show \(min(Self.logSummaryPageSize, report.logSummaries.count - visibleLogSummaryCount)) more…") {
                        visibleLogSummaryCount = min(
                            visibleLogSummaryCount + Self.logSummaryPageSize,
                            report.logSummaries.count
                        )
                    }
                    .buttonStyle(.borderless)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
            }
        }
    }

    private var logSummaryHeader: some View {
        HStack(spacing: 12) {
            Text("File")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Class")
                .frame(width: 120, alignment: .leading)
            Text("Mill")
                .frame(width: 48, alignment: .trailing)
            Text("68k")
                .frame(width: 40, alignment: .center)
        }
        .font(.caption.bold())
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func logSummaryRow(_ entry: MillResearchEngine.LogSummary) -> some View {
        HStack(spacing: 12) {
            Text(entry.fileName)
                .font(.body.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(entry.classification)
                .font(.body)
                .frame(width: 120, alignment: .leading)
            Text("\(entry.millMax)")
                .font(.body.monospaced())
                .frame(width: 48, alignment: .trailing)
            Text(entry.reached68k ? "yes" : "no")
                .font(.body.monospaced())
                .frame(width: 40, alignment: .center)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func offsetSection(
        title: String,
        entries: [MillResearchEngine.OffsetHistogramEntry]
    ) -> some View {
        let visibleEntries = Array(entries.prefix(Self.offsetDisplayLimit))
        return section(title: title) {
            if entries.isEmpty {
                Text("No offsets recorded.")
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(visibleEntries) { entry in
                        offsetRow(entry)
                    }
                }
                if entries.count > visibleEntries.count {
                    Text("Showing top \(visibleEntries.count) of \(entries.count) — export histogram for the full list.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func offsetRow(_ entry: MillResearchEngine.OffsetHistogramEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Button {
                    onNavigateOffset(entry.offset, entry.space)
                } label: {
                    Text("0x\(String(format: "%X", entry.offset))")
                        .font(.body.monospaced())
                }
                .buttonStyle(.plain)
                Text("\(entry.count)×")
                    .font(.body.monospaced())
                if let symbol = entry.symbolName {
                    Text(symbol)
                        .font(.body)
                }
                if let annotation = annotationLookup(
                    AddressTranslation.virtualAddress(fromRomOffset: entry.offset, space: entry.space)
                ) {
                    Text(annotation.classification.recommendedAction.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(annotationBadgeColor(annotation), in: Capsule())
                }
                Spacer()
            }
            if !entry.tags.isEmpty {
                Text(entry.tags.joined(separator: ", "))
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            if let recommendation = entry.recommendation {
                Text(recommendation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 2)
    }

    private func annotationBadgeColor(_ annotation: MillAnnotation) -> Color {
        switch annotation.status {
        case .approved: return .green.opacity(0.25)
        case .rejected: return .red.opacity(0.25)
        case .pending: return .orange.opacity(0.25)
        }
    }

    private var trapSection: some View {
        section(title: "Trap observations") {
            if report.trapObservations.isEmpty {
                Text("No trap observations recorded.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(report.trapObservations.prefix(20)) { trap in
                        HStack(spacing: 12) {
                            Text(trap.name)
                                .font(.body.monospaced())
                            Text("\(trap.count)×")
                                .font(.body.monospaced())
                            if trap.noSkipProtected {
                                Text("protected")
                                    .font(.callout)
                                    .foregroundStyle(.orange)
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
    }
}
