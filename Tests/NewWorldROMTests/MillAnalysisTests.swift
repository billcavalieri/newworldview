import Foundation
import NewWorldROM
import Testing

struct MillAnalysisTests {
    @Test func contextBuilderIncludesLookupFields() throws {
        var ppcBytes = Data()
        for _ in 0..<16 {
            ppcBytes.append(contentsOf: [0x48, 0x00, 0x00, 0x00])
        }
        let node = ROMNode.leaf(
            id: "rom/MacROM/NanoKernel",
            name: "NanoKernel",
            data: ppcBytes,
            kind: .disassemblable(.powerPC),
            runtimeAddress: AddressSpaces.ppcMacROMBase + 0x326564,
            metadata: [
                "addressSpace": AddressSpace.ppcMacROM.rawValue,
                "macromOffset": String(0x326564)
            ]
        )
        let parsed = ParsedROM(root: node, fileName: "fixture", fileSize: 64)
        let database = AnalysisEngine.analyze(parsed)
        let address = ProgramAddress(space: .ppcMacROM, address: AddressSpaces.ppcMacROMBase + 0x326564)
        let context = MillAnalysisContextBuilder.make(
            address: address,
            parsed: parsed,
            database: database,
            macROM: nil
        )
        #expect(context.romOffset == 0x326564)
        #expect(context.nodeName == "NanoKernel")
        #expect(!context.disasmLines.isEmpty)
    }

    @Test func grokPackUsesContextBuilder() throws {
        let node = ROMNode.leaf(
            id: "rom/MacROM/NanoKernel",
            name: "NanoKernel",
            data: Data(repeating: 0x4E, count: 64),
            kind: .disassemblable(.powerPC),
            runtimeAddress: AddressSpaces.ppcMacROMBase + 0x326564,
            metadata: [
                "addressSpace": AddressSpace.ppcMacROM.rawValue,
                "macromOffset": String(0x326564)
            ]
        )
        let parsed = ParsedROM(root: node, fileName: "fixture", fileSize: 64)
        let database = AnalysisEngine.analyze(parsed)
        let address = ProgramAddress(space: .ppcMacROM, address: AddressSpaces.ppcMacROMBase + 0x326564)
        let snippet = GrokPackGenerator.makeSnippet(
            address: address,
            parsed: parsed,
            database: database,
            macROM: nil
        )
        #expect(snippet.body.contains("# NewWorldView grok pack"))
        #expect(snippet.body.contains("0x326564"))
    }

    @Test func reachabilityFlagsProtectedTrapPath() {
        let trap = ProgramAddress(space: .toolboxTrap, address: UInt64(ATrapTable.noSkipUITraps.first ?? 0xA97C))
        let caller = ProgramAddress(space: .m68kToolbox, address: 0x26E90)
        let target = ProgramAddress(space: .m68kToolbox, address: 0x26E88)
        let database = AnalysisDatabase(
            xrefs: [
                XRef(from: caller, to: trap, kind: .trap, fromNodeID: "n1", toSymbol: "GetNewDialog"),
                XRef(from: caller, to: target, kind: .call, fromNodeID: "n2")
            ]
        )
        let report = MillReachabilityEngine.analyze(target: target, database: database, maxPaths: 4, maxDepth: 6)
        #expect(report.verdict == .protectedPath)
        #expect(report.touchesProtectedTrap)
    }

    @Test func safetyVerifierVetoesGetNewDialogStubTag() {
        let context = MillAnalysisContext(
            address: ProgramAddress(space: .m68kToolbox, address: AddressSpaces.getNewDialogStub),
            tags: ["get-new-dialog-stub"]
        )
        let reachability = MillReachabilityReport(verdict: .protectedPath, touchesGetNewDialogStub: true)
        let result = MillSafetyVerifier.precheck(context: context, reachability: reachability)
        #expect(result?.classification.recommendedAction == .revert)
        #expect(result?.skippedModel == true)
    }

    @Test func safetyVerifierOverridesSkipCandidateOnProtectedReachability() {
        let context = MillAnalysisContext(
            address: ProgramAddress(space: .m68kToolbox, address: 0x26E88),
            tags: ["skip-slot-helper"]
        )
        let reachability = MillReachabilityReport(verdict: .protectedPath, touchesProtectedTrap: true)
        let model = MillClassification(
            kind: .millableSpin,
            confidence: 0.91,
            recommendedAction: .skipCandidate,
            reasoning: "Looks like a spin loop."
        )
        let result = MillSafetyVerifier.verify(
            context: context,
            reachability: reachability,
            modelClassification: model
        )
        #expect(result.classification.recommendedAction == .investigate)
        #expect(result.suggestsEscalation)
    }

    @Test func escalationPackContainsHardRules() {
        let context = MillAnalysisContext(
            address: ProgramAddress(space: .m68kToolbox, address: 0x26E90),
            tags: ["skip-slot-helper"]
        )
        let bundle = MillEscalationPackBuilder.build(
            context: context,
            classification: MillClassification(
                kind: .unknown,
                confidence: 0.4,
                recommendedAction: .investigate,
                reasoning: "Needs review."
            ),
            annotation: nil
        )
        #expect(bundle.packMarkdown.contains("## HARD"))
        #expect(bundle.packMarkdown.contains("0x5c86c"))
        #expect(bundle.promptMarkdown.contains("MILL_APPLIED=yes"))
    }

    @Test func annotationExportIncludesApprovedOnly() throws {
        let context = MillAnalysisContext(
            address: ProgramAddress(space: .m68kToolbox, address: 0x26E90),
            romOffset: 0x26E90
        )
        let approved = MillAnnotation(
            address: context.address,
            classification: MillClassification(
                kind: .millableSpin,
                confidence: 0.9,
                recommendedAction: .skipCandidate,
                reasoning: "Spin"
            ),
            source: .appleFM,
            status: .approved,
            contextSnapshot: context
        )
        let pending = MillAnnotation(
            address: context.address,
            classification: MillClassification(
                kind: .unknown,
                confidence: 0.4,
                recommendedAction: .investigate,
                reasoning: "Maybe"
            ),
            source: .appleFM,
            status: .pending,
            contextSnapshot: context
        )
        let doc = MillAnnotationExport.document(romKey: "fixture", annotations: [approved, pending])
        #expect(doc.entries.count == 1)
        #expect(doc.entries[0].romOffset == "0x26E90")
    }

    @Test func annotationExportSumsAppleFMTokenUsage() throws {
        let context = MillAnalysisContext(
            address: ProgramAddress(space: .m68kToolbox, address: 0x26E90),
            romOffset: 0x26E90
        )
        let approved = MillAnnotation(
            address: context.address,
            classification: MillClassification(
                kind: .millableSpin,
                confidence: 0.9,
                recommendedAction: .skipCandidate,
                reasoning: "Spin"
            ),
            source: .appleFM,
            status: .approved,
            contextSnapshot: context,
            tokenUsage: MillTokenUsage(inTokens: 1200, outTokens: 48)
        )
        let doc = MillAnnotationExport.document(romKey: "fixture", annotations: [approved])
        #expect(doc.tokenUsage == MillTokenUsage(inTokens: 1200, outTokens: 48))
        #expect(doc.entries[0].tokenUsage == MillTokenUsage(inTokens: 1200, outTokens: 48))
    }

    @Test func fmParserRepairsSkipCandidateInKindField() {
        let parsed = MillFMClassificationParser.parse(
            kind: "skipCandidate",
            recommendedAction: "",
            confidence: 0.9,
            reasoning: "Repeated slot-helper spin."
        )
        #expect(parsed.kind == .millableSpin)
        #expect(parsed.recommendedAction == .skipCandidate)
    }

    @Test func fmParserAcceptsCanonicalFields() {
        let parsed = MillFMClassificationParser.parse(
            kind: "millableSpin",
            recommendedAction: "skipCandidate",
            confidence: 0.91,
            reasoning: "Spin loop."
        )
        #expect(parsed.kind == .millableSpin)
        #expect(parsed.recommendedAction == .skipCandidate)
    }

    @Test func fmParserSwapsSwappedKindAndAction() {
        let parsed = MillFMClassificationParser.parse(
            kind: "skipCandidate",
            recommendedAction: "millableSpin",
            confidence: 0.88,
            reasoning: "Swapped fields."
        )
        #expect(parsed.kind == .millableSpin)
        #expect(parsed.recommendedAction == .skipCandidate)
    }

    @Test func neverApproveSkipCandidateOnProtectedPath() {
        let context = MillAnalysisContext(
            address: ProgramAddress(space: .m68kToolbox, address: 0x26E88),
            tags: ["skip-slot-helper"]
        )
        let reachability = MillReachabilityReport(verdict: .protectedPath, touchesProtectedTrap: true)
        let skipAnnotation = MillAnnotation(
            address: context.address,
            classification: MillClassification(
                kind: .millableSpin,
                confidence: 0.95,
                recommendedAction: .skipCandidate,
                reasoning: "Spin loop."
            ),
            source: .appleFM,
            status: .pending,
            contextSnapshot: context
        )
        #expect(!MillSafetyVerifier.allowsApprovedSkipCandidate(skipAnnotation, reachability: reachability))
    }

    @Test func mockProviderPipelineOverridesUnsafeSkipCandidate() {
        let context = MillAnalysisContext(
            address: ProgramAddress(space: .m68kToolbox, address: 0x26E88),
            tags: ["skip-slot-helper"]
        )
        let reachability = MillReachabilityReport(verdict: .protectedPath, touchesProtectedTrap: true)
        let model = MillClassification(
            kind: .millableSpin,
            confidence: 0.95,
            recommendedAction: .skipCandidate,
            reasoning: "Spin loop."
        )
        let verification = MillSafetyVerifier.verify(
            context: context,
            reachability: reachability,
            modelClassification: model
        )
        #expect(verification.classification.recommendedAction == .investigate)
        #expect(verification.status == .pending)
        #expect(verification.suggestsEscalation)
    }

    @Test func precheckSkipsModelForProtectedReachability() {
        let context = MillAnalysisContext(
            address: ProgramAddress(space: .m68kToolbox, address: 0x26E88),
            tags: ["skip-slot-helper"]
        )
        let reachability = MillReachabilityReport(verdict: .protectedPath, touchesProtectedTrap: true)
        let result = MillSafetyVerifier.precheck(context: context, reachability: reachability)
        #expect(result?.skippedModel == true)
        #expect(result?.classification.recommendedAction == .revert)
    }

    @Test func histogramExportRoundTrip() throws {
        let report = MillResearchEngine.HistoricalReport(
            discoveredLogs: 12,
            scannedLogs: 10,
            totalAvailableLogs: 12,
            keepLogsOnly: true,
            logScanLimit: 200,
            histogramLimit: 0,
            logSummaries: [],
            topPPCOffsets: [],
            top68kOffsets: [
                MillResearchEngine.OffsetHistogramEntry(
                    offset: 0x26E90,
                    count: 412,
                    space: .m68kToolbox,
                    tags: ["skip-slot-helper"],
                    symbolName: "SlotHelperSpin",
                    recommendation: "skip-68k candidate"
                )
            ],
            trapObservations: [],
            skipRecommendations: ["test"],
            getNewDialogStubHits: 0,
            heartbeatClusterHits: 0
        )
        let context = MillAnalysisContext(
            address: ProgramAddress(space: .m68kToolbox, address: 0x26E90),
            romOffset: 0x26E90
        )
        let approved = MillAnnotation(
            address: context.address,
            classification: MillClassification(
                kind: .millableSpin,
                confidence: 0.9,
                recommendedAction: .skipCandidate,
                reasoning: "Spin"
            ),
            source: .appleFM,
            status: .approved,
            contextSnapshot: context,
            tokenUsage: MillTokenUsage(inTokens: 100, outTokens: 4)
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nw-histogram-\(UUID().uuidString)", isDirectory: true)
        let url = try MillHistogramExport.write(
            romKey: "fixture",
            report: report,
            annotations: [approved],
            to: directory
        )
        let loaded = try MillHistogramExport.load(from: url)
        #expect(loaded.format == MillHistogramExport.formatID)
        #expect(loaded.entries.count == 1)
        #expect(loaded.entries[0].romOffset == "0x26E90")
        #expect(loaded.entries[0].annotationAction == "skipCandidate")
        #expect(loaded.tokenUsage == MillTokenUsage(inTokens: 100, outTokens: 4))
    }

    @Test func logEscalationExporterIncludesExcerpt() throws {
        let line = "G3: 68k GetCCursor pc=5005c86c"
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("nw-escalate-\(UUID().uuidString).log")
        try line.write(to: temp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: temp) }
        let excerpt = try MillLogEscalationExporter.relevantLines(from: temp)
        #expect(excerpt.contains("GetCCursor"))
    }

    @Test func pipelineExportWritesManifest() throws {
        let report = MillResearchEngine.HistoricalReport(
            discoveredLogs: 4,
            scannedLogs: 3,
            totalAvailableLogs: 4,
            keepLogsOnly: true,
            logScanLimit: 200,
            histogramLimit: 0,
            logSummaries: [],
            topPPCOffsets: [],
            top68kOffsets: [
                MillResearchEngine.OffsetHistogramEntry(
                    offset: 0x1DDD4,
                    count: 88,
                    space: .m68kToolbox,
                    tags: [],
                    symbolName: nil,
                    recommendation: nil
                )
            ],
            trapObservations: [],
            skipRecommendations: [],
            getNewDialogStubHits: 0,
            heartbeatClusterHits: 0
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nw-pipeline-\(UUID().uuidString)", isDirectory: true)
        let result = try MillPipelineExport.write(
            romKey: "fixture",
            report: report,
            annotations: [],
            to: directory
        )
        #expect(FileManager.default.fileExists(atPath: result.manifestURL.path))
    }
}
