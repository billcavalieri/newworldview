import AppKit
import NewWorldROM
import SwiftUI

struct InspectorTabs: View {
    @ObservedObject var research: ResearchState
    @ObservedObject var millAnalysis: MillAnalysisService
    let parsed: ParsedROM
    let database: AnalysisDatabase
    let isAnalyzing: Bool
    var analysisSelection: AnalysisSelection?
    @Binding var selectedTab: Tab
    var onNavigate: (AnalysisSelection, ROMNode.ID, ProgramAddress) -> Void
    var onNavigateAddress: (ProgramAddress) -> Void
    var onMillReportReady: () -> Void = {}

    init(
        research: ResearchState,
        millAnalysis: MillAnalysisService,
        parsed: ParsedROM,
        database: AnalysisDatabase,
        isAnalyzing: Bool,
        analysisSelection: AnalysisSelection?,
        selectedTab: Binding<Tab>,
        onNavigate: @escaping (AnalysisSelection, ROMNode.ID, ProgramAddress) -> Void,
        onNavigateAddress: @escaping (ProgramAddress) -> Void,
        onMillReportReady: @escaping () -> Void = {}
    ) {
        self.research = research
        self.millAnalysis = millAnalysis
        self.parsed = parsed
        self.database = database
        self.isAnalyzing = isAnalyzing
        self.analysisSelection = analysisSelection
        self._selectedTab = selectedTab
        self.onNavigate = onNavigate
        self.onNavigateAddress = onNavigateAddress
        self.onMillReportReady = onMillReportReady
    }

    enum Tab: String, CaseIterable, Identifiable {
        case analysis
        case research

        var id: String { rawValue }
        var title: String {
            switch self {
            case .analysis: return "Analysis"
            case .research: return "Research"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Inspector", selection: $selectedTab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(12)

            ZStack {
                AnalysisInspector(
                    database: database,
                    isAnalyzing: isAnalyzing,
                    selection: analysisSelection,
                    trapFilter: $research.trapFilter,
                    onNavigate: onNavigate
                )
                .opacity(selectedTab == .analysis ? 1 : 0)
                .allowsHitTesting(selectedTab == .analysis)
                .accessibilityHidden(selectedTab != .analysis)

                ResearchInspector(
                    research: research,
                    millAnalysis: millAnalysis,
                    parsed: parsed,
                    database: database,
                    onNavigateAddress: onNavigateAddress,
                    onMillReportReady: onMillReportReady
                )
                .opacity(selectedTab == .research ? 1 : 0)
                .allowsHitTesting(selectedTab == .research)
                .accessibilityHidden(selectedTab != .research)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ResearchInspector: View {
    @ObservedObject var research: ResearchState
    @ObservedObject var millAnalysis: MillAnalysisService
    let parsed: ParsedROM
    let database: AnalysisDatabase
    var onNavigateAddress: (ProgramAddress) -> Void
    var onMillReportReady: () -> Void = {}

    @EnvironmentObject private var millResearchSettings: MillResearchSettings
    @State private var showPurgeCacheConfirmation = false

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                logJumpSection
                addressSection
                bookmarksSection
                historicalSection
                millAnalysisSection
                if !research.compareLines.isEmpty {
                    compareSection
                }
                if !research.callPath.isEmpty {
                    callPathSection
                }
            }
            .padding(12)
        }
        .scrollClipDisabled()
    }

    private var logJumpSection: some View {
        GroupBox("Log jump") {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Paste NW-BOOT G3 line", text: $research.logJumpText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                HStack(spacing: 12) {
                    Button("Go to PC") {
                        guard let address = research.jumpAddress(from: research.logJumpText) else {
                            research.lastError = "No pc= found in line."
                            return
                        }
                        research.lastError = nil
                        onNavigateAddress(address)
                    }
                    .hoverHelp(
                        "Parse pc= from the pasted NW-BOOT line and jump the detail pane to that PPC address in the ROM."
                    )

                    Button("Grok pack") {
                        research.makeGrokPackFromLog(parsed: parsed, database: database)
                    }
                    .hoverHelp(
                        "Build a paste-ready snippet from this log line: address, symbols, bytes, disassembly, xrefs, and a static path toward the heartbeat cluster."
                    )

                    Button("Classify") {
                        classifyLogLine()
                    }
                    .disabled(millAnalysis.isClassifying)
                    .hoverHelp("Run on-device Apple FM classification for the log line PC.")
                }
            }
        }
    }

    private var addressSection: some View {
        GroupBox("Address translator") {
            VStack(alignment: .leading, spacing: 8) {
                TextField("50326564 or PPC:50326564", text: $research.addressQuery)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Lookup") {
                        research.runLookup(parsed: parsed, database: database)
                    }
                    if let result = research.lookupResult, let offset = result.romOffset {
                        Text("ROM+0x\(String(format: "%X", offset))")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                if let result = research.lookupResult {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.address.display).font(.caption.monospaced())
                        if let nodeName = result.nodeName {
                            Text(nodeName).font(.caption)
                        }
                        if !result.tags.isEmpty {
                            Text(result.tags.joined(separator: ", "))
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    HStack {
                        Button("Navigate") { onNavigateAddress(result.address) }
                        Button("Bookmark") {
                            research.addBookmark(
                                label: result.symbol?.name ?? result.address.display,
                                addressText: research.addressQuery
                            )
                        }
                        Button("Grok") {
                            research.makeGrokPack(address: result.address, parsed: parsed, database: database)
                        }
                        Button("Classify") {
                            classifyLookup()
                        }
                        .disabled(millAnalysis.isClassifying)
                    }
                }
            }
        }
    }

    private var bookmarksSection: some View {
        GroupBox("Mill bookmarks") {
            if research.bookmarks.isEmpty {
                Text("Pin PCs you revisit while milling.")
                    .font(.callout)
                    .foregroundStyle(.primary.opacity(0.82))
            } else {
                List {
                    ForEach(research.bookmarks) { bookmark in
                        Button {
                            research.addressQuery = bookmark.addressText
                            research.runLookup(parsed: parsed, database: database)
                            if let address = AddressTranslation.parse(bookmark.addressText)?.programAddress {
                                onNavigateAddress(address)
                            }
                        } label: {
                            VStack(alignment: .leading) {
                                Text(bookmark.label).font(.caption.bold())
                                Text(bookmark.addressText).font(.caption2.monospaced())
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            research.removeBookmark(id: research.bookmarks[index].id)
                        }
                    }
                }
                .frame(minHeight: 80, maxHeight: 140)
            }
        }
    }

    private var historicalSection: some View {
        GroupBox("Historical mill logs") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(logDirectoryLabel)
                            .font(.caption.bold())
                        Text(research.logDirectoryPath)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button("Choose…") {
                        chooseLogDirectory()
                    }
                }
                Toggle("Skip-68k overlay on hex", isOn: $research.showSkipOverlay)
                Toggle("KEEP logs only", isOn: $millResearchSettings.keepLogsOnly)
                if millResearchSettings.keepLogsOnly {
                    Text("Only logs that reached stable 68k (plus pinned mills) are analyzed. Turn off to scan all ss-g3-mill-*.log(.gz) files in the folder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !research.hasLogDirectoryAccess {
                    Text("Choose the log folder once to grant read access under the app sandbox.")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                if let status = research.logCacheStatus, status.cachedLogCount > 0 {
                    Text(cacheStatusLabel(status))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                HStack(spacing: 8) {
                    Button(research.isAnalyzingLogs ? "Analyzing…" : "Analyze logs") {
                        Task {
                            onMillReportReady()
                            await research.analyzeHistoricalLogs(
                                database: database,
                                logScanLimit: millResearchSettings.effectiveScanLimit,
                                histogramLimit: millResearchSettings.effectiveHistogramLimit,
                                keepLogsOnly: millResearchSettings.keepLogsOnly
                            )
                            if research.historicalReport != nil, research.lastError == nil {
                                onMillReportReady()
                            }
                        }
                    }
                    .disabled(research.isAnalyzingLogs || !research.hasLogDirectoryAccess)

                    Button("Reload all") {
                        Task {
                            onMillReportReady()
                            await research.analyzeHistoricalLogs(
                                database: database,
                                logScanLimit: millResearchSettings.effectiveScanLimit,
                                histogramLimit: millResearchSettings.effectiveHistogramLimit,
                                keepLogsOnly: millResearchSettings.keepLogsOnly,
                                forceReload: true
                            )
                            if research.historicalReport != nil, research.lastError == nil {
                                onMillReportReady()
                            }
                        }
                    }
                    .disabled(research.isAnalyzingLogs || !research.hasLogDirectoryAccess)
                    .help("Ignore the SQLite cache and re-parse every log file.")

                    Button("Purge cache…") {
                        showPurgeCacheConfirmation = true
                    }
                    .disabled(research.isAnalyzingLogs || !research.hasLogDirectoryAccess)
                    .help("Delete cached aggregates for this log folder.")
                }
                .confirmationDialog(
                    "Purge cached mill logs?",
                    isPresented: $showPurgeCacheConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Purge cache", role: .destructive) {
                        research.purgeLogCache()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Removes SQLite-cached aggregates for the selected log folder. The next Analyze logs run will re-import every file.")
                }
                if research.isAnalyzingLogs {
                    MillLogAnalysisProgressView(
                        progress: research.logAnalysisProgress,
                        compact: true,
                        onCancel: { research.cancelLogAnalysis() }
                    )
                }
                if let report = research.historicalReport, !research.isAnalyzingLogs {
                    if report.keepLogsOnly, report.totalAvailableLogs > report.scannedLogs {
                        Text("Scanned \(report.scannedLogs) KEEP logs of \(report.totalAvailableLogs) total — turn off KEEP logs only to analyze all.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } else if report.discoveredLogs > report.scannedLogs {
                        Text("Scanned \(report.scannedLogs) of \(report.discoveredLogs) logs — open the Mill logs tab for the full report.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } else {
                        Text("Scanned \(report.scannedLogs) logs — open the Mill logs tab for the full report.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                if let error = research.lastError {
                    Text(error).font(.caption2).foregroundStyle(.red)
                }
            }
        }
    }

    private var millAnalysisSection: some View {
        GroupBox("Mill analysis") {
            VStack(alignment: .leading, spacing: 8) {
                MillAnalysisStatusBanner(millAnalysis: millAnalysis)
                if millAnalysis.isClassifying {
                    ProgressView("Classifying…")
                }
                if let result = research.lookupResult,
                   let annotation = millAnalysis.annotation(for: result.address) {
                    MillAnalysisVerdictCard(
                        annotation: annotation,
                        onApprove: { _ = millAnalysis.approve(id: annotation.id, database: database) },
                        onReject: { millAnalysis.reject(id: annotation.id) },
                        onEscalate: {
                            millAnalysis.runEscalationFlow(
                                annotation: annotation,
                                settings: millResearchSettings
                            )
                        }
                    )
                } else if research.grokSnippet.isEmpty {
                    Text("Classify an address or build a Grok pack. Review results on the Annotations tab.")
                        .font(.callout)
                        .foregroundStyle(.primary.opacity(0.82))
                } else {
                    Text(research.grokSnippet)
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Copy Grok pack") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(research.grokSnippet, forType: .string)
                    }
                }
                if let error = millAnalysis.lastError {
                    Text(error).font(.caption2).foregroundStyle(.red)
                }
            }
        }
    }

    private var compareSection: some View {
        GroupBox("Disasm compare (rom_disasm-style)") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(research.compareLines) { line in
                    Text(line.formatted + (line.millable ? " ; millable" : " ; hard"))
                        .font(.caption2.monospaced())
                }
            }
        }
    }

    private func classifyLookup() {
        guard research.lookupResult != nil else { return }
        Task {
            guard let result = research.lookupResult else { return }
            _ = await millAnalysis.classifyAddress(
                result.address,
                parsed: parsed,
                database: database,
                macROM: research.macROM,
                historicalReport: research.historicalReport,
                settings: millResearchSettings
            )
        }
    }

    private func classifyLogLine() {
        Task {
            _ = await millAnalysis.classifyLogLine(
                research.logJumpText,
                parsed: parsed,
                database: database,
                macROM: research.macROM,
                historicalReport: research.historicalReport,
                settings: millResearchSettings
            )
        }
    }

    private var callPathSection: some View {
        GroupBox("Call path to heartbeat") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(research.callPath) { step in
                    Text(String(repeating: " ", count: step.depth * 2) + step.address.display + " " + (step.symbolName ?? ""))
                        .font(.caption2.monospaced())
                }
            }
        }
    }

    private var logDirectoryLabel: String {
        URL(fileURLWithPath: research.logDirectoryPath).lastPathComponent
    }

    private func cacheStatusLabel(_ status: MillLogCacheStore.CacheStatus) -> String {
        var parts = ["Cache: \(status.cachedLogCount) logs stored"]
        if let lastUpdated = status.lastUpdated {
            parts.append("updated \(lastUpdated.formatted(date: .abbreviated, time: .shortened))")
        }
        return parts.joined(separator: " · ")
    }

    private func chooseLogDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Select the folder containing ss-g3-mill-*.log or .log.gz files."
        let current = URL(fileURLWithPath: research.logDirectoryPath)
        if FileManager.default.fileExists(atPath: current.path) {
            panel.directoryURL = current
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        research.setLogDirectory(url)
        research.refreshLogCacheStatus()
        Task {
            await research.loadCachedReportIfAvailable(
                database: database,
                logScanLimit: millResearchSettings.effectiveScanLimit,
                histogramLimit: millResearchSettings.effectiveHistogramLimit,
                keepLogsOnly: millResearchSettings.keepLogsOnly
            )
        }
    }
}
