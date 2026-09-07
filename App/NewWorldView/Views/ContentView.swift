import AppKit
import NewWorldROM
import SwiftUI

struct ContentView: View {
    let document: ROMDocument
    let fileURL: URL?

    @State private var parsed: ParsedROM
    @State private var selection: ROMNode.ID
    @State private var scrollTarget: DetailScrollTarget?
    @State private var viewMode: DetailViewMode = .automatic
    @State private var detailTab: DetailPaneTab = .rom
    @State private var search = ""
    @State private var analysis = AnalysisDatabase.empty
    @State private var isAnalyzing = false
    @State private var showInspector = true
    @State private var inspectorTab: InspectorTabs.Tab = .analysis
    @State private var showTree = true
    @State private var exportError: String?
    @State private var treeRevealRequest: ROMTreeRevealRequest?
    @State private var analysisSelection: AnalysisSelection?
    @StateObject private var research: ResearchState
    @StateObject private var millAnalysis: MillAnalysisService

    init(document: ROMDocument, fileURL: URL?) {
        self.document = document
        self.fileURL = fileURL
        _parsed = State(initialValue: document.parsed)
        _selection = State(initialValue: document.parsed.root.id)
        _research = StateObject(wrappedValue: ResearchState(romKey: document.parsed.fileName))
        _millAnalysis = StateObject(wrappedValue: MillAnalysisService(romKey: document.parsed.fileName))
    }

    @EnvironmentObject private var millResearchSettings: MillResearchSettings

    var body: some View {
        HSplitView {
            if showTree {
                ROMTreeView(
                    root: parsed.root,
                    selection: $selection,
                    search: $search,
                    revealRequest: treeRevealRequest
                )
                .frame(minWidth: 220, idealWidth: 280, maxWidth: 420, maxHeight: .infinity)
            }

            VStack(spacing: 0) {
                detailPanelHeader
                Divider()
                Group {
                    switch detailTab {
                    case .rom:
                        DetailView(
                            node: selectedNode,
                            database: analysis,
                            mode: $viewMode,
                            scrollTarget: scrollTarget,
                            skipHighlightByteOffsets: skipHighlightByteOffsets(in: selectedNode),
                            onProgramAddressSelected: selectAnalysisItem
                        )
                        .id(selection)
                    case .millLogs:
                        millLogsDetailPane
                    case .annotations:
                        annotationsDetailPane
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(minWidth: 280, maxHeight: .infinity)
            .layoutPriority(1)

            InspectorTabs(
                research: research,
                millAnalysis: millAnalysis,
                parsed: parsed,
                database: analysis,
                isAnalyzing: isAnalyzing,
                analysisSelection: analysisSelection,
                selectedTab: $inspectorTab,
                onNavigate: navigateFromAnalysis,
                onNavigateAddress: navigateFromAddress,
                onMillReportReady: { detailTab = .millLogs }
            )
            .frame(
                minWidth: showInspector ? 320 : 0,
                idealWidth: showInspector ? 380 : 0,
                maxWidth: showInspector ? 720 : 0,
                maxHeight: .infinity
            )
            .allowsHitTesting(showInspector)
            .accessibilityHidden(!showInspector)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: fileURL?.path) {
            await research.decodeMacROMIfNeeded(from: document.data)
        }
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    showTree.toggle()
                } label: {
                    Label("Toggle ROM tree", systemImage: "sidebar.leading")
                }
                .help("Hide or show the ROM tree")
            }
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(parsed.fileName)
                        .font(.headline)
                    Label("Locked", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            statusBar
        }
        .alert("Export failed", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
        .task(id: fileURL?.path) {
            await loadResourceForkIfNeeded()
        }
        .task(id: parsed.root.id) {
            await analyze()
            await research.loadCachedReportIfAvailable(
                database: analysis,
                logScanLimit: millResearchSettings.effectiveScanLimit,
                histogramLimit: millResearchSettings.effectiveHistogramLimit,
                keepLogsOnly: millResearchSettings.keepLogsOnly
            )
            research.refreshLogCacheStatus()
        }
        .onChange(of: millResearchSettings.keepLogsOnly) { _, _ in
            Task {
                await research.loadCachedReportIfAvailable(
                    database: analysis,
                    logScanLimit: millResearchSettings.effectiveScanLimit,
                    histogramLimit: millResearchSettings.effectiveHistogramLimit,
                    keepLogsOnly: millResearchSettings.keepLogsOnly
                )
            }
        }
        .onChange(of: selection) { _, nodeID in
            guard let analysisSelection,
                  let target = AnalysisSelectionResolver.navigationTarget(for: analysisSelection, in: analysis),
                  target.0 != nodeID
            else { return }
            self.analysisSelection = nil
        }
    }

    private var detailPanelHeader: some View {
        HStack(spacing: 12) {
            Picker("Pane", selection: $detailTab) {
                ForEach(DetailPaneTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)

            if detailTab == .rom {
                Picker("View", selection: $viewMode) {
                    ForEach(DetailViewMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
            }

            Spacer(minLength: 8)

            Button {
                showInspector.toggle()
            } label: {
                Label("Analysis", systemImage: "arrow.triangle.branch")
            }
            .help("Show functions, A-traps, and xrefs")
            .labelStyle(.iconOnly)

            Menu {
                Button("Ghidra metadata (JSON/XML)", action: exportGhidra)
                Button("MacROM.bin + regions", action: exportROMBinary)
                Button("Mill research report", action: exportMillReport)
                Button("Mill histogram (macemu)", action: exportMillHistogramFromMenu)
                Button("Macemu pipeline bundle", action: exportMillPipelineFromMenu)
                Button("Escalation pack from log…", action: exportEscalationFromLog)
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .help("Export Ghidra metadata, decompressed ROM bytes, or mill research")
            .disabled(isAnalyzing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var selectedNode: ROMNode {
        parsed.root.node(id: selection) ?? parsed.root
    }

    @ViewBuilder
    private var millLogsDetailPane: some View {
        if research.isAnalyzingLogs {
            VStack {
                Spacer(minLength: 0)
                MillLogAnalysisProgressView(
                    progress: research.logAnalysisProgress,
                    onCancel: { research.cancelLogAnalysis() }
                )
                    .padding(24)
                    .frame(maxWidth: 420)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if millAnalysis.isClassifying, millAnalysis.triageProgress.total > 0 {
            VStack {
                Spacer(minLength: 0)
                MillLogAnalysisProgressView(
                    progress: millAnalysis.triageProgress,
                    onCancel: { millAnalysis.cancelTriage() }
                )
                .padding(24)
                .frame(maxWidth: 420)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let report = research.historicalReport {
            VStack(spacing: 0) {
                millLogsToolbar(report: report)
                Divider()
                MillReportDetailView(
                    report: report,
                    logDirectoryPath: research.logDirectoryPath,
                    annotationLookup: { address in
                        millAnalysis.annotation(for: address)
                    },
                    onNavigateOffset: { offset, space in
                        navigateFromAddress(
                            AddressTranslation.virtualAddress(fromRomOffset: offset, space: space)
                        )
                    }
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            millLogsEmptyState
        }
    }

    private var millLogsEmptyState: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No mill report")
                .font(.title2.bold())
            VStack(alignment: .center, spacing: 8) {
                if research.hasLogDirectoryAccess {
                    Text("Run **Analyze logs** in the Research inspector to build the KEEP-log histogram, skip recommendations, and macemu pipeline export.")
                    if millResearchSettings.keepLogsOnly {
                        Text("KEEP logs only is on — analysis scans state.json keep_log, pinned mills (6613/1116/680/35/22), and logs that reached stable 68k.")
                            .foregroundStyle(.secondary)
                    }
                    if let error = research.lastError, !error.isEmpty {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                } else {
                    Text("Choose your macemu **research-score** log folder in the Research inspector, then run **Analyze logs**.")
                    Text("Default path: `\(MillResearchEngine.defaultLogDirectory.path)`")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 420)
            .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("Open Research") {
                    showInspector = true
                    inspectorTab = .research
                }
                if research.hasLogDirectoryAccess {
                    Button(research.isAnalyzingLogs ? "Analyzing…" : "Analyze logs") {
                        Task { await analyzeMillLogsFromEmptyState() }
                    }
                    .disabled(research.isAnalyzingLogs)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func analyzeMillLogsFromEmptyState() async {
        await research.analyzeHistoricalLogs(
            database: analysis,
            logScanLimit: millResearchSettings.effectiveScanLimit,
            histogramLimit: millResearchSettings.effectiveHistogramLimit,
            keepLogsOnly: millResearchSettings.keepLogsOnly
        )
    }

    private var annotationsDetailPane: some View {
        MillAnnotationQueueView(
            millAnalysis: millAnalysis,
            database: analysis,
            onNavigateAddress: navigateFromAddress,
            onEscalate: { annotation in
                millAnalysis.runEscalationFlow(
                    annotation: annotation,
                    settings: millResearchSettings
                )
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func navigateFromAddress(_ address: ProgramAddress) {
        detailTab = .rom
        guard let target = AnalysisLookup.navigationTarget(for: address, in: parsed) else { return }
        let item = AnalysisSelectionResolver.selection(
            for: address,
            nodeID: target.0,
            in: analysis
        )
        if let item {
            navigateFromAnalysis(item, nodeID: target.0, address: address)
        } else {
            search = ""
            analysisSelection = nil
            selection = target.0
            treeRevealRequest = ROMTreeRevealRequest(nodeID: target.0, requestID: UUID())
            scrollTarget = DetailScrollTarget(nodeID: target.0, address: address, requestID: UUID())
            if let node = parsed.root.node(id: target.0), node.kind.allowsDisassembly {
                viewMode = .disassembly
            }
        }
    }

    private func skipHighlightByteOffsets(in node: ROMNode) -> Set<Int> {
        guard research.showSkipOverlay, !research.skipOverlayOffsets.isEmpty,
              let isa = node.kind.isa else { return [] }
        let space = AnalysisEngine.space(for: node, isa: isa)
        var result = Set<Int>()
        for romOffset in research.skipOverlayOffsets {
            let address = AddressTranslation.virtualAddress(
                fromRomOffset: romOffset,
                space: space == .m68kToolbox ? .m68kToolbox : .ppcMacROM
            )
            if let byteOffset = AnalysisEngine.byteOffset(for: address, in: node) {
                result.insert(byteOffset)
            }
        }
        return result
    }

    private func navigateFromAnalysis(_ item: AnalysisSelection, nodeID: ROMNode.ID, address: ProgramAddress) {
        search = ""
        analysisSelection = item
        selection = nodeID
        treeRevealRequest = ROMTreeRevealRequest(nodeID: nodeID, requestID: UUID())
        scrollTarget = DetailScrollTarget(nodeID: nodeID, address: address, requestID: UUID())
        if let node = parsed.root.node(id: nodeID), node.kind.allowsDisassembly, viewMode == .text {
            viewMode = .disassembly
        }
    }

    private func selectAnalysisItem(_ address: ProgramAddress, in node: ROMNode) {
        scrollTarget = nil
        analysisSelection = AnalysisSelectionResolver.selection(
            for: address,
            nodeID: node.id,
            in: analysis
        )
    }

    private func loadResourceForkIfNeeded() async {
        guard let fileURL, let rsrc = ResourceForkLoader.data(at: fileURL) else { return }
        let data = document.data
        let name = parsed.fileName
        let updated = await Task.detached(priority: .userInitiated) {
            ROMParser.parse(data: data, resourceFork: rsrc, fileName: name)
        }.value
        parsed = updated
        if parsed.root.node(id: selection) == nil {
            selection = updated.root.id
        }
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            Text("Read-only")
            Text("·")
            Text(parsed.fileName)
            Text("·")
            Text(byteCount(parsed.fileSize))
            Text("·")
            Text(selectedNode.name)
            Text(byteCount(selectedNode.size))
            if let offset = selectedNode.containerOffset {
                Text("offset \(String(format: "0x%X", offset))")
            }
            if isAnalyzing {
                Text("·")
                Text("Analyzing xrefs…")
            } else if !analysis.xrefs.isEmpty {
                Text("·")
                Text("\(analysis.xrefs.count) xrefs")
            }
            Spacer()
            if !parsed.warnings.isEmpty {
                Text(parsed.warnings.joined(separator: " "))
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func millLogsToolbar(report: MillResearchEngine.HistoricalReport) -> some View {
        HStack(spacing: 12) {
            Button("Triage top 68k hotspots") {
                Task {
                    await millAnalysis.triageHotspots(
                        report: report,
                        parsed: parsed,
                        database: analysis,
                        macROM: research.macROM,
                        settings: millResearchSettings
                    )
                }
            }
            .disabled(millAnalysis.isClassifying || research.isAnalyzingLogs)

            Button("Export approved annotations") {
                exportAnnotationsOnly()
            }

            Button("Export histogram") {
                exportHistogramOnly(report: report)
            }

            Button("Export macemu pipeline") {
                exportPipelineBundle(report: report)
            }

            Spacer()

            if !millAnalysis.modelAvailable, let reason = millAnalysis.modelUnavailableReason {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func analyze() async {
        isAnalyzing = true
        let snapshot = parsed
        analysis = await Task.detached(priority: .userInitiated) {
            AnalysisEngine.analyze(snapshot)
        }.value
        isAnalyzing = false
    }

    private func exportGhidra() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        panel.message = "Choose a folder for analysis.json, analysis.xml, and LoadNewWorldROM.py. ROM bytes are not written."
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        let destination = parent.appendingPathComponent("NewWorldView-ghidra", isDirectory: true)
        let accessing = parent.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                parent.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let options = GhidraExport.ExportOptions(
                includeMillTags: true,
                trapFilter: research.trapFilter
            )
            try GhidraExport.write(database: analysis, parsed: parsed, to: destination, options: options)
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func exportROMBinary() {
        guard let parent = chooseExportDirectory(message: "Choose a folder for MacROM.bin, per-region binaries, and rom-export.json.") else { return }
        let accessing = parent.startAccessingSecurityScopedResource()
        defer {
            if accessing { parent.stopAccessingSecurityScopedResource() }
        }
        do {
            _ = try ROMBinaryExport.writeMacROM(rawData: document.data, parsed: parsed, to: parent)
            NSWorkspace.shared.activateFileViewerSelecting([parent])
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func exportMillReport() {
        guard let parent = chooseExportDirectory(message: "Choose a folder for the mill research report JSON.") else { return }
        let accessing = parent.startAccessingSecurityScopedResource()
        defer {
            if accessing { parent.stopAccessingSecurityScopedResource() }
        }
        Task {
            if research.historicalReport == nil {
                await research.analyzeHistoricalLogs(
                    database: analysis,
                    logScanLimit: millResearchSettings.effectiveScanLimit,
                    histogramLimit: millResearchSettings.effectiveHistogramLimit,
                    keepLogsOnly: millResearchSettings.keepLogsOnly
                )
            }
            guard let report = research.historicalReport else {
                exportError = research.lastError ?? "Analyze logs first to build a report."
                return
            }
            detailTab = .millLogs
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let url = parent.appendingPathComponent("mill-research-report.json")
                try encoder.encode(MillReportExport(report: report)).write(to: url)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                exportError = error.localizedDescription
            }
        }
    }

    private func exportAnnotationsOnly() {
        guard let parent = chooseExportDirectory(message: "Choose a folder for mill-annotations.json") else { return }
        let accessing = parent.startAccessingSecurityScopedResource()
        defer {
            if accessing { parent.stopAccessingSecurityScopedResource() }
        }
        do {
            let exported = try millAnalysis.exportApprovedAnnotations(to: parent)
            NSWorkspace.shared.activateFileViewerSelecting([exported])
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func exportHistogramOnly(report: MillResearchEngine.HistoricalReport) {
        guard let parent = chooseExportDirectory(message: "Choose a folder for mill-histogram.json") else { return }
        let accessing = parent.startAccessingSecurityScopedResource()
        defer {
            if accessing { parent.stopAccessingSecurityScopedResource() }
        }
        do {
            let exported = try millAnalysis.exportHistogram(report: report, to: parent)
            NSWorkspace.shared.activateFileViewerSelecting([exported])
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func exportPipelineBundle(report: MillResearchEngine.HistoricalReport) {
        guard let parent = chooseExportDirectory(message: "Choose a folder for the macemu pipeline bundle") else { return }
        let accessing = parent.startAccessingSecurityScopedResource()
        defer {
            if accessing { parent.stopAccessingSecurityScopedResource() }
        }
        do {
            let result = try millAnalysis.exportPipeline(report: report, to: parent)
            NSWorkspace.shared.activateFileViewerSelecting([result.directory])
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func exportMillHistogramFromMenu() {
        guard let report = research.historicalReport else {
            exportError = "Analyze logs first to build a histogram."
            return
        }
        exportHistogramOnly(report: report)
    }

    private func exportMillPipelineFromMenu() {
        guard let report = research.historicalReport else {
            exportError = "Analyze logs first to build a histogram."
            return
        }
        exportPipelineBundle(report: report)
    }

    private func exportEscalationFromLog() {
        millAnalysis.runEscalationFromLogFlow(
            parsed: parsed,
            database: analysis,
            macROM: research.macROM,
            settings: millResearchSettings
        )
        if let error = millAnalysis.lastError {
            exportError = error
        }
    }

    private func chooseExportDirectory(message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        panel.message = message
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    private func byteCount(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }
}
