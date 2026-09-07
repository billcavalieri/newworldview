import AppKit
import Combine
import Foundation
import NewWorldROM

enum MillAnalysisServiceError: LocalizedError {
    case modelUnavailable(String)
    case invalidModelOutput(String)
    case addressNotFound
    case grokBinaryMissing
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelUnavailable(let reason): return reason
        case .invalidModelOutput(let reason): return reason
        case .addressNotFound: return "Could not resolve an address to classify."
        case .grokBinaryMissing: return "Grok binary not found. Set the path in Settings or install grok."
        case .exportFailed(let reason): return reason
        }
    }
}

@MainActor
final class MillAnalysisService: ObservableObject {
    @Published var isClassifying = false
    @Published var triageProgress = MillLogAnalysisProgress.zero
    @Published var lastError: String?

    private let annotationStore: MillAnnotationStore
    private var modelProvider: MillAnalysisModelProvider
    private var triageSession: MillLogAnalysisSession?

    init(romKey: String) {
        self.annotationStore = MillAnnotationStore(romKey: romKey)
        self.modelProvider = AppleFMProvider()
        if !modelProvider.isAvailable {
            self.modelProvider = UnavailableMillAnalysisModelProvider(
                unavailableReason: modelProvider.unavailableReason
            )
        }
    }

    var annotations: [MillAnnotation] {
        annotationStore.annotations
    }

    var modelAvailable: Bool {
        modelProvider.isAvailable
    }

    var modelUnavailableReason: String? {
        modelProvider.unavailableReason
    }

    func refreshProvider() {
        let apple = AppleFMProvider()
        if apple.isAvailable {
            modelProvider = apple
        } else {
            modelProvider = UnavailableMillAnalysisModelProvider(unavailableReason: apple.unavailableReason)
        }
    }

    func annotation(for address: ProgramAddress) -> MillAnnotation? {
        annotationStore.annotation(for: address)
    }

    func filteredAnnotations(status: AnnotationStatus?) -> [MillAnnotation] {
        annotationStore.filtered(status: status)
    }

    func classifyAddress(
        _ address: ProgramAddress,
        parsed: ParsedROM,
        database: AnalysisDatabase,
        macROM: Data?,
        historicalReport: MillResearchEngine.HistoricalReport?,
        settings: MillResearchSettings
    ) async -> MillAnnotation? {
        isClassifying = true
        defer { isClassifying = false }

        let logHits = MillAnalysisContextBuilder.logHits(for: address, in: historicalReport)
        let hint = MillAnalysisContextBuilder.deterministicHint(for: address, in: historicalReport)
        let reachability = MillReachabilityEngine.analyze(target: address, database: database)
        let context = MillAnalysisContextBuilder.make(
            address: address,
            parsed: parsed,
            database: database,
            macROM: macROM,
            logHits: logHits,
            deterministicHint: hint,
            reachability: reachability
        )

        if let verification = MillSafetyVerifier.precheck(context: context, reachability: reachability) {
            let annotation = MillAnnotation(
                address: address,
                classification: verification.classification,
                source: verification.source,
                status: verification.status,
                contextSnapshot: context,
                suggestsEscalation: verification.suggestsEscalation
            )
            annotationStore.upsert(annotation)
            lastError = nil
            return annotation
        }

        do {
            let modelResult = try await modelProvider.classify(context: context)
            var classification = modelResult.classification
            MillSafetyVerifier.mergeDeterministicHint(into: &classification, hint: hint)
            let verification = MillSafetyVerifier.verify(
                context: context,
                reachability: reachability,
                modelClassification: classification,
                confidenceThreshold: settings.fmConfidenceThreshold
            )
            let annotation = MillAnnotation(
                address: address,
                classification: verification.classification,
                source: verification.source,
                status: verification.status,
                contextSnapshot: context,
                suggestsEscalation: verification.suggestsEscalation,
                tokenUsage: modelResult.tokenUsage
            )
            annotationStore.upsert(annotation)
            lastError = nil
            return annotation
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func classifyLogLine(
        _ logLine: String,
        parsed: ParsedROM,
        database: AnalysisDatabase,
        macROM: Data?,
        historicalReport: MillResearchEngine.HistoricalReport?,
        settings: MillResearchSettings
    ) async -> MillAnnotation? {
        guard let address = MillLogParser.parseLogLine(logLine) else {
            lastError = "Could not parse a PC from that log line."
            return nil
        }
        return await classifyAddress(
            address,
            parsed: parsed,
            database: database,
            macROM: macROM,
            historicalReport: historicalReport,
            settings: settings
        )
    }

    func triageHotspots(
        report: MillResearchEngine.HistoricalReport,
        parsed: ParsedROM,
        database: AnalysisDatabase,
        macROM: Data?,
        settings: MillResearchSettings
    ) async {
        triageSession?.cancel()
        let session = MillLogAnalysisSession()
        triageSession = session
        let startedAt = Date()
        let entries = Array(report.top68kOffsets.prefix(settings.batchTriageCount))
        isClassifying = true
        triageProgress = MillLogAnalysisProgress(
            completed: 0,
            total: entries.count,
            currentFileName: nil,
            startedAt: startedAt
        )
        defer {
            isClassifying = false
            triageProgress = .zero
            triageSession = nil
        }

        for (index, entry) in entries.enumerated() {
            if session.isCancelled() { break }
            let address = AddressTranslation.virtualAddress(fromRomOffset: entry.offset, space: .m68kToolbox)
            triageProgress = MillLogAnalysisProgress(
                completed: index,
                total: entries.count,
                currentFileName: address.display,
                startedAt: startedAt
            )
            _ = await classifyAddress(
                address,
                parsed: parsed,
                database: database,
                macROM: macROM,
                historicalReport: report,
                settings: settings
            )
            triageProgress = MillLogAnalysisProgress(
                completed: index + 1,
                total: entries.count,
                currentFileName: address.display,
                startedAt: startedAt
            )
        }
    }

    func cancelTriage() {
        triageSession?.cancel()
    }

    func approve(id: UUID, database: AnalysisDatabase) -> Bool {
        guard let annotation = annotations.first(where: { $0.id == id }) else { return false }
        let reachability = MillReachabilityEngine.analyze(target: annotation.address, database: database)
        let ok = annotationStore.approve(id: id, reachability: reachability)
        if !ok {
            lastError = "Cannot approve skip candidate on a protected path."
        } else {
            lastError = nil
        }
        return ok
    }

    func reject(id: UUID) {
        annotationStore.reject(id: id)
        lastError = nil
    }

    func exportEscalation(
        annotation: MillAnnotation,
        to directory: URL,
        settings: MillResearchSettings
    ) throws -> URL {
        let bundle = MillEscalationPackBuilder.build(
            context: annotation.contextSnapshot,
            classification: annotation.classification,
            annotation: annotation,
            macemuRepoPath: settings.macemuRepoPath.isEmpty ? nil : settings.macemuRepoPath
        )
        try MillEscalationPackBuilder.write(bundle: bundle, to: directory)
        return directory
    }

    func exportApprovedAnnotations(to directory: URL) throws -> URL {
        try annotationStore.exportApproved(to: directory)
    }

    func exportHistogram(
        report: MillResearchEngine.HistoricalReport,
        to directory: URL
    ) throws -> URL {
        try MillHistogramExport.write(
            romKey: annotationStore.romKeyForExport,
            report: report,
            annotations: annotations,
            to: directory
        )
    }

    func exportPipeline(
        report: MillResearchEngine.HistoricalReport,
        to directory: URL
    ) throws -> MillPipelineExport.Result {
        try MillPipelineExport.write(
            romKey: annotationStore.romKeyForExport,
            report: report,
            annotations: annotations,
            to: directory
        )
    }

    func exportEscalationFromLog(
        logURL: URL,
        address: ProgramAddress,
        parsed: ParsedROM,
        database: AnalysisDatabase,
        macROM: Data?,
        to directory: URL,
        settings: MillResearchSettings
    ) throws -> URL {
        let bundle = try MillLogEscalationExporter.buildPack(
            logURL: logURL,
            address: address,
            parsed: parsed,
            database: database,
            macROM: macROM,
            macemuRepoPath: settings.macemuRepoPath.isEmpty ? nil : settings.macemuRepoPath
        )
        try MillEscalationPackBuilder.write(bundle: bundle, to: directory)
        return directory
    }

    func runEscalationFromLogFlow(
        parsed: ParsedROM,
        database: AnalysisDatabase,
        macROM: Data?,
        settings: MillResearchSettings
    ) {
        let logPanel = NSOpenPanel()
        logPanel.canChooseFiles = true
        logPanel.canChooseDirectories = false
        logPanel.allowsMultipleSelection = false
        logPanel.prompt = "Choose"
        logPanel.message = "Select a KEEP mill log (e.g. ss-g3-mill-6613.log)"
        guard logPanel.runModal() == .OK, let logURL = logPanel.url else { return }

        let exportPanel = NSOpenPanel()
        exportPanel.canChooseFiles = false
        exportPanel.canChooseDirectories = true
        exportPanel.canCreateDirectories = true
        exportPanel.prompt = "Export"
        exportPanel.message = "Choose a folder for pack-escalation.md and grok-prompt.md"
        guard exportPanel.runModal() == .OK, let directory = exportPanel.url else { return }

        let address = ProgramAddress(space: .m68kToolbox, address: AddressSpaces.getNewDialogStub)
        do {
            _ = try exportEscalationFromLog(
                logURL: logURL,
                address: address,
                parsed: parsed,
                database: database,
                macROM: macROM,
                to: directory,
                settings: settings
            )
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func runGrokBuild(
        outputDirectory: URL,
        settings: MillResearchSettings
    ) throws -> String {
        let macemuRepoURL = try? settings.resolveMacemuRepoURL()
        return try GrokBuildRunner.run(
            outputDirectory: outputDirectory,
            macemuRepoURL: macemuRepoURL,
            grokPath: settings.resolvedGrokPath()
        )
    }

    func runEscalationFlow(annotation: MillAnnotation, settings: MillResearchSettings) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        panel.message = "Choose a folder for pack-escalation.md and grok-prompt.md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            _ = try exportEscalation(annotation: annotation, to: url, settings: settings)
            let alert = NSAlert()
            alert.messageText = "Escalation pack exported"
            alert.informativeText = "Run Grok Build using the exported prompt?"
            alert.addButton(withTitle: "Run Grok Build")
            alert.addButton(withTitle: "Done")
            if alert.runModal() == .alertFirstButtonReturn {
                _ = try runGrokBuild(outputDirectory: url, settings: settings)
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
