import Foundation
import NewWorldROM
import Testing

struct MillResearchTests {
    @Test func parsesFixtureTail() throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ss-pr10-2d295270.tail.txt")
        let text = try String(contentsOf: fixture, encoding: .utf8)
        let parsed = MillLogParser.parse(text, fileName: "fixture.tail.txt")
        #expect(!parsed.millPairs.isEmpty)
        #expect(parsed.clusterPairs.count >= 1)
    }

    @Test func addressTranslationRoundTrip() {
        let virtual = AddressSpaces.ppcMacROMBase + 0x326564
        let offset = AddressTranslation.romOffset(fromVirtual: virtual)
        #expect(offset == 0x326564)
        let back = AddressTranslation.virtualAddress(fromRomOffset: 0x326564, space: .ppcMacROM)
        #expect(back.address == virtual)
    }

    @Test func parseLogLineExtractsPC() {
        let line = "NW-BOOT G3: DEC leave 50326 cmp pc=50326564 op=900107d4 nxt=7c0604a6"
        let address = MillLogParser.parseLogLine(line)
        #expect(address?.address == 0x5032_6564)
    }

    @Test func decodesRealROMWhenPresent() throws {
        let romURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Downloads/Mac OS ROM")
        guard FileManager.default.fileExists(atPath: romURL.path) else { return }
        let raw = try Data(contentsOf: romURL)
        let decoded = try MacROMImageDecoder.decode(raw)
        #expect(decoded.image.count == MacROMImageDecoder.romSize)
        #expect(decoded.newWorldOK)
    }

    @Test func ghidraExportVersionTwoIncludesOffsets() throws {
        let node = ROMNode.leaf(
            id: "rom/MacROM/NanoKernel",
            name: "NanoKernel",
            data: Data(repeating: 0, count: 16),
            kind: .disassemblable(.powerPC),
            runtimeAddress: AddressSpaces.ppcMacROMBase + 0x310000,
            metadata: [
                "addressSpace": AddressSpace.ppcMacROM.rawValue,
                "macromOffset": String(0x310000)
            ]
        )
        let parsed = ParsedROM(root: node, fileName: "fixture", fileSize: 16)
        let database = AnalysisEngine.analyze(parsed)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NewWorldView-ghidra-v2-\(UUID().uuidString)", isDirectory: true)
        try GhidraExport.write(database: database, parsed: parsed, to: directory)
        let json = try String(contentsOf: directory.appendingPathComponent("analysis.json"), encoding: .utf8)
        #expect(json.contains("\"version\" : 2"))
        #expect(json.contains("\"romOffset\" : \"0x310000\""))
    }

    @Test func aggregatorMatchesFullParseOnFixture() throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ss-pr10-2d295270.tail.txt")
        let text = try String(contentsOf: fixture, encoding: .utf8)
        let parsed = MillLogParser.parse(text, fileName: fixture.lastPathComponent)
        let aggregates = try MillLogParser.accumulateAggregates(from: fixture)
        #expect(aggregates.millMax == parsed.millMax)
        #expect(aggregates.reached68k == parsed.reached68k)
        #expect(aggregates.skipEventCount == parsed.skipEvents.count)
        #expect(aggregates.ppcOffsetCounts == parsed.observedPPCOffsets)
    }

    @Test func cancellationStopsAnalysisEarly() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nw-cancel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        for mill in [1, 2] {
            var text = ""
            for _ in 0..<4_000 {
                text += "G3: filler mill=\(mill)\n"
            }
            text += "KEEP 68k hang pc=50366084\n"
            try text.write(
                to: directory.appendingPathComponent("ss-g3-mill-\(mill).log"),
                atomically: true,
                encoding: .utf8
            )
        }

        final class Flag: @unchecked Sendable {
            private let lock = NSLock()
            private var cancelled = false
            func trip() {
                lock.lock()
                cancelled = true
                lock.unlock()
            }
            func isSet() -> Bool {
                lock.lock()
                defer { lock.unlock() }
                return cancelled
            }
        }

        let flag = Flag()
        do {
            _ = try MillResearchEngine.analyzeHistoricalLogs(
                in: directory,
                limit: 2,
                discoveryOptions: MillLogDiscovery.Options(
                    directory: directory,
                    tmpDirectory: directory,
                    keepLogsOnly: false
                ),
                progress: { _, _, _ in flag.trip() },
                isCancelled: { flag.isSet() }
            )
            Issue.record("Expected cancellation")
        } catch is CancellationError {
            #expect(flag.isSet())
        }
    }

    @Test func r24NormalizationMatchesMacemu() {
        #expect(AddressTranslation.romOffset(fromR24: 0x5002_5814) == 0x25814)
        #expect(AddressTranslation.romOffset(fromR24: 0x26E88) == 0x26E88)
    }

    @Test func skip68kPolicyBlocksCode66HelperRange() {
        #expect(!MillSkip68kPolicy.isMillable(offset: 0x9440))
        #expect(!MillSkip68kPolicy.isMillable(offset: 0x9464))
        #expect(!MillSkip68kPolicy.isMillable(offset: 0x94C2))
        #expect(MillSkip68kPolicy.blockReason(offset: 0x9440)?.contains("CODE 66") == true)
    }

    @Test func parsesCode66LifecycleLines() {
        let text = """
        G3: 68k Launch A9F2 enter CODE0 r24=1007d45e
        G3: 68k LoadSeg A9F0 enter seg=66 r24=1007d45e
        G3: 68k stay CODE 66 r24=1007d45e from=50009440
        """
        let parsed = MillLogParser.parse(text, fileName: "code66.log")
        #expect(parsed.launchA9F2Count == 1)
        #expect(parsed.loadSeg66Count == 1)
        #expect(parsed.stayCode66Count == 1)
        #expect(parsed.code66HelperSnapCount == 1)
    }

    @Test func trapTableMatchesMacemu() {
        #expect(ATrapTable.names[0xA97C] == "GetNewDialog")
        #expect(ATrapTable.names[0xA97D] == "NewDialog")
        #expect(ATrapTable.names[0xA9F0] == "LoadSeg")
        #expect(ATrapTable.names[0xA9F2] == "Launch")
        #expect(ATrapTable.names[0xAA1B] == "GetCCursor")
        #expect(ATrapTable.names[0xA9C9] == "SysError")
        #expect(ATrapTable.noSkipUITraps.contains(0xAA1B))
    }

    @Test func g3ClassifiesLoadSeg66AsFalsePath() throws {
        let text = """
        G3: 68k LoadSeg A9F0 enter seg=66 r24=1007d45e
        """
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("nw-loadseg66-\(UUID().uuidString).log")
        try text.write(to: temp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: temp) }
        let aggregates = try MillLogParser.accumulateAggregates(from: temp)
        let report = MillResearchEngine.buildHistoricalReport(
            from: [aggregates],
            database: .empty,
            histogramLimit: 10,
            discoveredLogs: 1,
            scannedLogs: 1,
            totalAvailableLogs: 1,
            keepLogsOnly: true,
            logScanLimit: 0
        )
        let line = try #require(report.skipRecommendations.first { $0.contains("LoadSeg seg=66") })
        #expect(line.contains(G3MillClassification.loadSeg66FalsePathLabel))
        #expect(line.contains("6AFC600"))
    }

    @Test func g3ScoresCFMUpgraderLaunch() throws {
        let text = """
        G3: 68k Launch A9F2 enter CODE0 r24=1007d45e pc=1007d45e toc=1007d460
        G3: 68k Launch A9F2 CFM Upgrader PEF enter pc=101013d0 toc=10115000
        """
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("nw-launch-\(UUID().uuidString).log")
        try text.write(to: temp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: temp) }
        let parsed = MillLogParser.parse(text, fileName: temp.lastPathComponent)
        #expect(parsed.launchA9F2Count == 1)
        #expect(parsed.pefEnterCount == 1)
        let aggregates = try MillLogParser.accumulateAggregates(from: temp)
        #expect(aggregates.trapCounts[0xA9F2] == 1)
        let report = MillResearchEngine.buildHistoricalReport(
            from: [aggregates],
            database: .empty,
            histogramLimit: 10,
            discoveredLogs: 1,
            scannedLogs: 1,
            totalAvailableLogs: 1,
            keepLogsOnly: true,
            logScanLimit: 0
        )
        #expect(report.launchA9F2Logs == 1)
        #expect(report.launchA9F2Count == 1)
        #expect(report.pefEnterCount == 1)
        let line = try #require(report.skipRecommendations.first { $0.contains("PEF enter") || $0.contains("CFM Upgrader") })
        #expect(line.contains("101013d0") || line.contains("InterfaceLib") || line.contains("hosted"))
    }

    @Test func g3ClassifiesGetNewDialogByResourceID() throws {
        let text = """
        G3: 68k GetNewDialog id=59840 r24=5005c86e
        G3: 68k GetNewDialog A97C Splash 510 even dlg=1005130c
        G3: 68k GetNewDialog A97C toast id=510 dlg=1005130c pc=1010b428
        """
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("nw-gnd-\(UUID().uuidString).log")
        try text.write(to: temp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: temp) }
        let parsed = MillLogParser.parse(text, fileName: temp.lastPathComponent)
        #expect(parsed.getNewDialogOverlayHits == 1)
        #expect(parsed.getNewDialogSplashHits == 1)
    }

    @Test func g3ParsesHostedPEFStamps() throws {
        let text = """
        G3: 68k Launch A9F2 CFM Upgrader PEF import idx=1 r3=10115c5e
        G3: 68k Launch A9F2 CFM Upgrader PEF WaitNextEvent idx=149 r3=00000001
        G3: DSI n=2 SRR0=1010b428 DAR=00015018
        """
        let parsed = MillLogParser.parse(text, fileName: "pef-stamps.log")
        #expect(parsed.pefImportCount == 1)
        #expect(parsed.pefWaitNextEventCount == 1)
        #expect(parsed.pefHostedDSICount == 1)
        #expect(!parsed.pefHostedLocationSamples.isEmpty)
    }

    @Test func g3ParsesXlateMissNers() throws {
        let text = "G3: xlate miss ea=6e657273 r24=1007d45e\n"
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("nw-xlate-\(UUID().uuidString).log")
        try text.write(to: temp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: temp) }
        let parsed = MillLogParser.parse(text, fileName: temp.lastPathComponent)
        #expect(parsed.xlateMissNersCount == 1)
        let aggregates = try MillLogParser.accumulateAggregates(from: temp)
        let report = MillResearchEngine.buildHistoricalReport(
            from: [aggregates],
            database: .empty,
            histogramLimit: 10,
            discoveredLogs: 1,
            scannedLogs: 1,
            totalAvailableLogs: 1,
            keepLogsOnly: true,
            logScanLimit: 0
        )
        let line = try #require(report.skipRecommendations.first { $0.contains("ners") })
        #expect(line.contains("GetResource"))
    }

    @Test func code66RecommendationPrefersGetResourceAfterHelperSnaps() throws {
        let text = """
        G3: 68k LoadSeg A9F0 enter seg=66 r24=1007d45e
        G3: 68k stay CODE 66 r24=1007d45e from=50009440
        """
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("nw-code66-rec-\(UUID().uuidString).log")
        try text.write(to: temp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: temp) }
        let aggregates = try MillLogParser.accumulateAggregates(from: temp)
        let report = MillResearchEngine.buildHistoricalReport(
            from: [aggregates],
            database: .empty,
            histogramLimit: 10,
            discoveredLogs: 1,
            scannedLogs: 1,
            totalAvailableLogs: 1,
            keepLogsOnly: true,
            logScanLimit: 0
        )
        let line = try #require(report.skipRecommendations.first { $0.contains("GetResource") })
        #expect(line.contains("kajr ROM fall-through"))
        #expect(line.contains("not stay-code66"))
    }

    @Test func researchReportExportIncludesCode66Fields() {
        let report = MillResearchEngine.HistoricalReport(
            discoveredLogs: 1,
            scannedLogs: 1,
            totalAvailableLogs: 1,
            keepLogsOnly: true,
            logScanLimit: 0,
            histogramLimit: 0,
            logSummaries: [],
            topPPCOffsets: [],
            top68kOffsets: [],
            trapObservations: [],
            skipRecommendations: [],
            getNewDialogStubHits: 10,
            heartbeatClusterHits: 0,
            code66LogsWithStay: 3,
            code66HelperSnaps: 5,
            loadSeg66Logs: 4
        )
        let exported = MillResearchReportExport(report: report)
        #expect(exported.code66LogsWithStay == 3)
        #expect(exported.code66HelperSnaps == 5)
        #expect(exported.loadSeg66Logs == 4)
        #expect(exported.launchA9F2Logs == 0)
    }

    @Test func skip68kPolicyBlocksHardOffsets() {
        #expect(!MillSkip68kPolicy.isMillable(offset: 0x326564))
        #expect(!MillSkip68kPolicy.isMillable(offset: 0x26E88))
        #expect(!MillSkip68kPolicy.isMillable(offset: 0x5C86C))
        #expect(MillSkip68kPolicy.isMillable(offset: 0x1DDD4))
        #expect(!MillSkip68kPolicy.isMillable(offset: 0x1DDD4, op: 0xA97C))
    }

    @Test func aggregatorNormalizesMapR24() throws {
        let line = "G3: 68k map r24=50025814 op=a97c"
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("nw-r24-\(UUID().uuidString).log")
        try line.write(to: temp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: temp) }
        let aggregates = try MillLogParser.accumulateAggregates(from: temp)
        #expect(aggregates.m68kOffsetCounts[0x5002_5814] == nil)
        #expect(aggregates.m68kOffsetCounts[0x25814] == nil)
        #expect(aggregates.trapCounts[0xA97C] == 1)
        #expect(aggregates.getNewDialogStubHits == 1)
        #expect(aggregates.m68kOffsetCounts[0x5C86C] == nil)
    }

    @Test func aggregatorCountsMillableMapR24Offset() throws {
        let line = "G3: 68k map r24=5001ddd4 op=4e75"
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("nw-r24-millable-\(UUID().uuidString).log")
        try line.write(to: temp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: temp) }
        let aggregates = try MillLogParser.accumulateAggregates(from: temp)
        #expect(aggregates.m68kOffsetCounts[0x1DDD4] == 1)
        #expect(aggregates.trapCounts[0xA97C] == nil)
    }

    @Test func ranked68kHistogramExcludesBlockedOffsets() {
        let blocked = MillResearchEngine.rankedOffsets(
            [0x26E88: 100, 0x1DDD4: 50, 0x366084: 40],
            space: .m68kToolbox,
            database: .empty,
            limit: 0
        )
        #expect(blocked.map(\.offset) == [0x1DDD4])
    }

    @Test func discoverySortsMillNumbersDescending() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nw-logs-\(UUID().uuidString)", isDirectory: true)
        let tmpDirectory = directory.appendingPathComponent("tmp", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "KEEP 68k hang pc=50366084".write(
            to: directory.appendingPathComponent("ss-g3-mill-6613.log"),
            atomically: true,
            encoding: .utf8
        )
        try "empty".write(
            to: directory.appendingPathComponent("ss-g3-mill-10.log"),
            atomically: true,
            encoding: .utf8
        )
        let ordered = try MillLogDiscovery.orderedLogURLs(
            options: MillLogDiscovery.Options(
                directory: directory,
                tmpDirectory: tmpDirectory,
                stateJSONPath: directory.appendingPathComponent("missing-state.json"),
                pinnedMillNumbers: [],
                keepLogsOnly: false
            )
        )
        #expect(ordered.first?.lastPathComponent == "ss-g3-mill-6613.log")
    }

    @Test func discoveryPrefersDirectoryOverTmpForPinnedMill() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nw-logs-\(UUID().uuidString)", isDirectory: true)
        let tmpDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nw-tmp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tmpDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: tmpDirectory)
        }
        try "dir".write(
            to: directory.appendingPathComponent("ss-g3-mill-6613.log"),
            atomically: true,
            encoding: .utf8
        )
        try "tmp".write(
            to: tmpDirectory.appendingPathComponent("ss-g3-mill-6613.log"),
            atomically: true,
            encoding: .utf8
        )
        let url = try #require(
            MillLogDiscovery.orderedLogURLs(
                options: MillLogDiscovery.Options(
                    directory: directory,
                    tmpDirectory: tmpDirectory,
                    stateJSONPath: nil,
                    pinnedMillNumbers: [6613],
                    keepLogsOnly: false
                )
            ).first
        )
        #expect(url.deletingLastPathComponent().lastPathComponent == directory.lastPathComponent)
    }

    @Test func discoveryRemapsTmpKeepLogToDirectory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nw-logs-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = directory.appendingPathComponent("ss-g3-mill-8518.log")
        try "KEEP 68k hang pc=50366084".write(to: log, atomically: true, encoding: .utf8)
        let stateDir = directory.appendingPathComponent("g3_driver", isDirectory: true)
        try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        let state = stateDir.appendingPathComponent("state.json")
        let payload = #"{"mill":{"keep_log":"/tmp/ss-g3-mill-8518.log"}}"#
        try payload.write(to: state, atomically: true, encoding: .utf8)
        let keepLog = try #require(
            MillLogDiscovery.keepLogFromState(state, preferredDirectory: directory)
        )
        #expect(keepLog.path == log.path)
        let ordered = try MillLogDiscovery.orderedLogURLs(
            options: MillLogDiscovery.Options.sandboxed(in: directory, keepLogsOnly: false)
        )
        #expect(ordered.contains { $0.path == log.path })
        #expect(!ordered.contains { $0.path == "/tmp/ss-g3-mill-8518.log" })
    }

    @Test func historicalAnalysisRunsOnResearchScoreWhenPresent() throws {
        let directory = MillResearchEngine.defaultLogDirectory
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        let logs = try MillResearchEngine.discoverLogs(in: directory)
        guard !logs.isEmpty else { return }
        let report = try MillResearchEngine.analyzeHistoricalLogs(in: directory, limit: 5)
        #expect(report.scannedLogs > 0)
        #expect(report.discoveredLogs >= report.scannedLogs)
        #expect(!report.skipRecommendations.isEmpty)
    }
}
