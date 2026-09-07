import Foundation

/// Correlate mill logs with static ROM analysis to suggest skip enhancements.
public enum MillResearchEngine {
    public struct OffsetHistogramEntry: Sendable, Equatable, Identifiable {
        public var id: UInt64 { offset }
        public var offset: UInt64
        public var count: Int
        public var space: AddressSpace
        public var tags: [String]
        public var symbolName: String?
        public var recommendation: String?

        public init(
            offset: UInt64,
            count: Int,
            space: AddressSpace,
            tags: [String],
            symbolName: String? = nil,
            recommendation: String? = nil
        ) {
            self.offset = offset
            self.count = count
            self.space = space
            self.tags = tags
            self.symbolName = symbolName
            self.recommendation = recommendation
        }
    }

    public struct TrapObservation: Sendable, Equatable, Identifiable {
        public var id: UInt16 { trap }
        public var trap: UInt16
        public var name: String
        public var count: Int
        public var noSkipProtected: Bool
    }

    public struct LogSummary: Sendable, Equatable, Identifiable {
        public var id: String { fileName }
        public var fileName: String
        public var millMax: Int
        public var reached68k: Bool
        public var g2Live: Bool
        public var empty300: Bool
        public var clusterPairCount: Int
        public var skipEventCount: Int
        public var classification: String
        public var launchA9F2Count: Int
        public var loadSeg66Count: Int
        public var stayCode66Count: Int
        public var code66HelperSnapCount: Int
    }

    public struct HistoricalReport: Sendable, Equatable {
        public var discoveredLogs: Int
        public var scannedLogs: Int
        public var totalAvailableLogs: Int
        public var keepLogsOnly: Bool
        public var logScanLimit: Int
        public var histogramLimit: Int
        public var logSummaries: [LogSummary]
        public var topPPCOffsets: [OffsetHistogramEntry]
        public var top68kOffsets: [OffsetHistogramEntry]
        public var trapObservations: [TrapObservation]
        public var skipRecommendations: [String]
        public var getNewDialogStubHits: Int
        public var heartbeatClusterHits: Int
        public var code66LogsWithStay: Int
        public var code66HelperSnaps: Int
        public var loadSeg66Logs: Int
        public var launchA9F2Logs: Int
        public var launchA9F2Count: Int
        public var pefEnterCount: Int
        public var pefImportCount: Int
        public var pefWaitNextEventCount: Int
        public var pefDceCount: Int
        public var pefVolCount: Int
        public var pefHostedDSICount: Int
        public var pefHostedLocationSamples: [String]
        public var getNewDialogOverlayHits: Int
        public var getNewDialogSplashHits: Int
        public var xlateMissNersCount: Int

        public init(
            discoveredLogs: Int,
            scannedLogs: Int,
            totalAvailableLogs: Int,
            keepLogsOnly: Bool,
            logScanLimit: Int,
            histogramLimit: Int,
            logSummaries: [LogSummary],
            topPPCOffsets: [OffsetHistogramEntry],
            top68kOffsets: [OffsetHistogramEntry],
            trapObservations: [TrapObservation],
            skipRecommendations: [String],
            getNewDialogStubHits: Int,
            heartbeatClusterHits: Int,
            code66LogsWithStay: Int = 0,
            code66HelperSnaps: Int = 0,
            loadSeg66Logs: Int = 0,
            launchA9F2Logs: Int = 0,
            launchA9F2Count: Int = 0,
            pefEnterCount: Int = 0,
            pefImportCount: Int = 0,
            pefWaitNextEventCount: Int = 0,
            pefDceCount: Int = 0,
            pefVolCount: Int = 0,
            pefHostedDSICount: Int = 0,
            pefHostedLocationSamples: [String] = [],
            getNewDialogOverlayHits: Int = 0,
            getNewDialogSplashHits: Int = 0,
            xlateMissNersCount: Int = 0
        ) {
            self.discoveredLogs = discoveredLogs
            self.scannedLogs = scannedLogs
            self.totalAvailableLogs = totalAvailableLogs
            self.keepLogsOnly = keepLogsOnly
            self.logScanLimit = logScanLimit
            self.histogramLimit = histogramLimit
            self.logSummaries = logSummaries
            self.topPPCOffsets = topPPCOffsets
            self.top68kOffsets = top68kOffsets
            self.trapObservations = trapObservations
            self.skipRecommendations = skipRecommendations
            self.getNewDialogStubHits = getNewDialogStubHits
            self.heartbeatClusterHits = heartbeatClusterHits
            self.code66LogsWithStay = code66LogsWithStay
            self.code66HelperSnaps = code66HelperSnaps
            self.loadSeg66Logs = loadSeg66Logs
            self.launchA9F2Logs = launchA9F2Logs
            self.launchA9F2Count = launchA9F2Count
            self.pefEnterCount = pefEnterCount
            self.pefImportCount = pefImportCount
            self.pefWaitNextEventCount = pefWaitNextEventCount
            self.pefDceCount = pefDceCount
            self.pefVolCount = pefVolCount
            self.pefHostedDSICount = pefHostedDSICount
            self.pefHostedLocationSamples = pefHostedLocationSamples
            self.getNewDialogOverlayHits = getNewDialogOverlayHits
            self.getNewDialogSplashHits = getNewDialogSplashHits
            self.xlateMissNersCount = xlateMissNersCount
        }
    }

    public static let defaultLogDirectory = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Documents/GitHub/macemu/research-score", isDirectory: true)

    public static let defaultScanLimit = 0
    public static let defaultHistogramLimit = 0

    public typealias MillLogAnalysisProgressHandler = @Sendable (_ completed: Int, _ total: Int, _ currentFileName: String?) -> Void
    public typealias MillLogAnalysisCancellationHandler = @Sendable () -> Bool

    public static func discoverLogs(
        in directory: URL = defaultLogDirectory,
        options: MillLogDiscovery.Options? = nil
    ) throws -> [URL] {
        var discoveryOptions = options ?? MillLogDiscovery.Options.default
        discoveryOptions.directory = directory
        return try MillLogDiscovery.orderedLogURLs(options: discoveryOptions)
    }

    public static func analyzeLog(
        at url: URL,
        database: AnalysisDatabase = .empty,
        histogramLimit: Int = defaultHistogramLimit
    ) throws -> HistoricalReport {
        let directory = url.deletingLastPathComponent()
        return try analyzeHistoricalLogs(
            at: [url],
            in: directory,
            database: database,
            limit: 1,
            histogramLimit: histogramLimit,
            discoveredCount: 1
        )
    }

    public static func analyzeHistoricalLogs(
        in directory: URL = defaultLogDirectory,
        database: AnalysisDatabase = .empty,
        limit: Int = defaultScanLimit,
        histogramLimit: Int = defaultHistogramLimit,
        discoveryOptions: MillLogDiscovery.Options? = nil,
        cacheStore: MillLogCacheStore? = nil,
        forceReload: Bool = false,
        progress: MillLogAnalysisProgressHandler? = nil,
        isCancelled: MillLogAnalysisCancellationHandler? = nil
    ) throws -> HistoricalReport {
        var options = discoveryOptions ?? MillLogDiscovery.Options.default
        options.directory = directory
        let totalAvailable = MillLogDiscovery.countAvailableLogFiles(in: directory)
        let discovered = try MillLogDiscovery.orderedLogURLs(options: options)
        return try analyzeHistoricalLogs(
            at: discovered,
            in: directory,
            database: database,
            limit: limit,
            histogramLimit: histogramLimit,
            discoveredCount: discovered.count,
            totalAvailableLogs: totalAvailable,
            keepLogsOnly: options.keepLogsOnly,
            cacheStore: cacheStore,
            forceReload: forceReload,
            progress: progress,
            isCancelled: isCancelled
        )
    }

    public static func analyzeHistoricalLogs(
        at urls: [URL],
        in logDirectory: URL,
        database: AnalysisDatabase = .empty,
        limit: Int = defaultScanLimit,
        histogramLimit: Int = defaultHistogramLimit,
        discoveredCount: Int? = nil,
        totalAvailableLogs: Int? = nil,
        keepLogsOnly: Bool = false,
        cacheStore: MillLogCacheStore? = nil,
        forceReload: Bool = false,
        progress: MillLogAnalysisProgressHandler? = nil,
        isCancelled: MillLogAnalysisCancellationHandler? = nil
    ) throws -> HistoricalReport {
        let discovered = discoveredCount ?? urls.count
        let available = totalAvailableLogs ?? discovered
        let logs: [URL]
        if limit <= 0 {
            logs = urls
        } else {
            logs = Array(urls.prefix(limit))
        }

        progress?(0, logs.count, nil)

        var aggregateResults = Array<MillLogParser.LogAggregates?>(repeating: nil, count: logs.count)
        var parseIndices: [Int] = []

        if !forceReload, let cacheStore {
            for index in logs.indices {
                if isCancelled?() == true { throw CancellationError() }
                if let cached = try cacheStore.loadAggregates(for: logs[index]) {
                    aggregateResults[index] = cached
                } else {
                    parseIndices.append(index)
                }
            }
        } else {
            parseIndices = Array(logs.indices)
        }

        let cachedCount = logs.count - parseIndices.count
        if cachedCount > 0 {
            progress?(cachedCount, logs.count, nil)
        }

        if !parseIndices.isEmpty {
            let urlsToParse = parseIndices.map { logs[$0] }
            let parsed = try MillLogAnalysisRunner.analyzeLogs(
                urlsToParse,
                progress: { completed, total, currentFileName in
                    progress?(cachedCount + completed, logs.count, currentFileName)
                },
                isCancelled: isCancelled
            )
            for (parsedIndex, aggregate) in zip(parseIndices, parsed) {
                aggregateResults[parsedIndex] = aggregate
                if let cacheStore {
                    try cacheStore.store(
                        aggregates: aggregate,
                        logURL: logs[parsedIndex],
                        logDirectory: logDirectory
                    )
                }
            }
        }

        let aggregates = aggregateResults.compactMap { $0 }
        guard aggregates.count == logs.count else {
            throw MillLogCacheError.sqlite(context: "analyzeHistoricalLogs", message: "missing aggregates after analysis")
        }

        return buildHistoricalReport(
            from: aggregates,
            database: database,
            histogramLimit: histogramLimit,
            discoveredLogs: discovered,
            scannedLogs: logs.count,
            totalAvailableLogs: available,
            keepLogsOnly: keepLogsOnly,
            logScanLimit: limit
        )
    }

    public static func logSummary(from aggregates: MillLogParser.LogAggregates) -> LogSummary {
        classify(aggregates)
    }

    public static func buildHistoricalReport(
        from aggregateResults: [MillLogParser.LogAggregates],
        database: AnalysisDatabase,
        histogramLimit: Int,
        discoveredLogs: Int,
        scannedLogs: Int,
        totalAvailableLogs: Int,
        keepLogsOnly: Bool,
        logScanLimit: Int
    ) -> HistoricalReport {
        var summaries: [LogSummary] = []
        summaries.reserveCapacity(aggregateResults.count)
        var ppcCounts: [UInt64: Int] = [:]
        var m68kCounts: [UInt64: Int] = [:]
        var trapCounts: [UInt16: Int] = [:]
        var getNewDialogStubHits = 0
        var heartbeatHits = 0
        var code66LogsWithStay = 0
        var code66HelperSnaps = 0
        var loadSeg66Logs = 0
        var launchA9F2Logs = 0
        var launchA9F2Count = 0
        var pefEnterCount = 0
        var pefImportCount = 0
        var pefWaitNextEventCount = 0
        var pefDceCount = 0
        var pefVolCount = 0
        var pefHostedDSICount = 0
        var pefHostedLocationSamples: [String] = []
        var getNewDialogOverlayHits = 0
        var getNewDialogSplashHits = 0
        var xlateMissNersCount = 0

        for aggregates in aggregateResults {
            summaries.append(classify(aggregates))
            if aggregates.stayCode66Count > 0 { code66LogsWithStay += 1 }
            if aggregates.loadSeg66Count > 0 { loadSeg66Logs += 1 }
            if aggregates.launchA9F2Count > 0 { launchA9F2Logs += 1 }
            code66HelperSnaps += aggregates.code66HelperSnapCount
            launchA9F2Count += aggregates.launchA9F2Count
            pefEnterCount += aggregates.pefEnterCount
            pefImportCount += aggregates.pefImportCount
            pefWaitNextEventCount += aggregates.pefWaitNextEventCount
            pefDceCount += aggregates.pefDceCount
            pefVolCount += aggregates.pefVolCount
            pefHostedDSICount += aggregates.pefHostedDSICount
            mergeHostedSamples(from: aggregates.pefHostedLocationSamples, into: &pefHostedLocationSamples)
            getNewDialogStubHits += aggregates.getNewDialogStubHits
            getNewDialogOverlayHits += aggregates.getNewDialogOverlayHits
            getNewDialogSplashHits += aggregates.getNewDialogSplashHits
            xlateMissNersCount += aggregates.xlateMissNersCount
            mergeCounts(from: aggregates.ppcOffsetCounts, into: &ppcCounts) { offset, count in
                let va = AddressSpaces.ppcMacROMBase + offset
                if AddressTranslation.isHeartbeatCluster(va) { heartbeatHits += count }
            }
            mergeCounts(from: aggregates.m68kOffsetCounts, into: &m68kCounts)
            mergeCounts(from: aggregates.trapCounts, into: &trapCounts)
        }

        let topPPC = rankedOffsets(
            ppcCounts,
            space: .ppcMacROM,
            database: database,
            limit: histogramLimit
        )
        let top68k = rankedOffsets(
            m68kCounts,
            space: .m68kToolbox,
            database: database,
            limit: histogramLimit
        )
        let traps = trapCounts.map { trap, count in
            TrapObservation(
                trap: trap,
                name: ATrapTable.name(for: trap),
                count: count,
                noSkipProtected: ATrapTable.noSkipUITraps.contains(trap)
            )
        }.sorted { $0.count > $1.count }

        let recommendations = buildRecommendations(
            ppc: topPPC,
            m68k: top68k,
            traps: traps,
            summaries: summaries,
            discoveredLogs: discoveredLogs,
            scannedLogs: scannedLogs,
            totalAvailableLogs: totalAvailableLogs,
            keepLogsOnly: keepLogsOnly,
            logScanLimit: logScanLimit,
            getNewDialogStubHits: getNewDialogStubHits,
            code66LogsWithStay: code66LogsWithStay,
            code66HelperSnaps: code66HelperSnaps,
            loadSeg66Logs: loadSeg66Logs,
            launchA9F2Logs: launchA9F2Logs,
            launchA9F2Count: launchA9F2Count,
            pefEnterCount: pefEnterCount,
            pefImportCount: pefImportCount,
            pefWaitNextEventCount: pefWaitNextEventCount,
            pefDceCount: pefDceCount,
            pefVolCount: pefVolCount,
            pefHostedDSICount: pefHostedDSICount,
            pefHostedLocationSamples: pefHostedLocationSamples,
            getNewDialogOverlayHits: getNewDialogOverlayHits,
            getNewDialogSplashHits: getNewDialogSplashHits,
            xlateMissNersCount: xlateMissNersCount
        )

        return HistoricalReport(
            discoveredLogs: discoveredLogs,
            scannedLogs: scannedLogs,
            totalAvailableLogs: totalAvailableLogs,
            keepLogsOnly: keepLogsOnly,
            logScanLimit: logScanLimit,
            histogramLimit: histogramLimit,
            logSummaries: summaries,
            topPPCOffsets: topPPC,
            top68kOffsets: top68k,
            trapObservations: traps,
            skipRecommendations: recommendations,
            getNewDialogStubHits: getNewDialogStubHits,
            heartbeatClusterHits: heartbeatHits,
            code66LogsWithStay: code66LogsWithStay,
            code66HelperSnaps: code66HelperSnaps,
            loadSeg66Logs: loadSeg66Logs,
            launchA9F2Logs: launchA9F2Logs,
            launchA9F2Count: launchA9F2Count,
            pefEnterCount: pefEnterCount,
            pefImportCount: pefImportCount,
            pefWaitNextEventCount: pefWaitNextEventCount,
            pefDceCount: pefDceCount,
            pefVolCount: pefVolCount,
            pefHostedDSICount: pefHostedDSICount,
            pefHostedLocationSamples: pefHostedLocationSamples,
            getNewDialogOverlayHits: getNewDialogOverlayHits,
            getNewDialogSplashHits: getNewDialogSplashHits,
            xlateMissNersCount: xlateMissNersCount
        )
    }

    public static func rankedOffsets(
        _ counts: [UInt64: Int],
        space: AddressSpace,
        database: AnalysisDatabase,
        limit: Int = defaultHistogramLimit
    ) -> [OffsetHistogramEntry] {
        let filteredCounts: [UInt64: Int]
        if space == .m68kToolbox {
            filteredCounts = counts.filter { MillSkip68kPolicy.isMillable(offset: $0.key) }
        } else {
            filteredCounts = counts
        }
        let sorted = filteredCounts.sorted { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key < rhs.key
            }
            return lhs.value > rhs.value
        }
        let capped: [(key: UInt64, value: Int)]
        if limit > 0 {
            capped = Array(sorted.prefix(limit))
        } else {
            capped = sorted
        }
        return enrichOffsets(capped, space: space, database: database)
    }

    private static func mergeCounts(
        from source: [UInt64: Int],
        into destination: inout [UInt64: Int],
        onInsert: ((UInt64, Int) -> Void)? = nil
    ) {
        for (key, count) in source {
            destination[key, default: 0] += count
            onInsert?(key, count)
        }
    }

    private static func mergeCounts(
        from source: [UInt16: Int],
        into destination: inout [UInt16: Int]
    ) {
        for (key, count) in source {
            destination[key, default: 0] += count
        }
    }

    public static func overlayOffsets(
        from report: HistoricalReport,
        threshold: Int = 3,
        limit: Int = 200
    ) -> Set<UInt64> {
        var result = Set<UInt64>()
        for entry in report.top68kOffsets where entry.count >= threshold {
            result.insert(entry.offset)
            if result.count >= limit {
                break
            }
        }
        result.insert(AddressSpaces.getNewDialogStub)
        return result
    }

    private static func classify(_ aggregates: MillLogParser.LogAggregates) -> LogSummary {
        let classification: String
        if aggregates.hang04cecd36 {
            classification = "hang_04cecd36"
        } else if aggregates.empty300 {
            classification = "empty_300"
        } else if aggregates.reached68k && aggregates.g2Live {
            classification = "keep-68k"
        } else if aggregates.millMax > 0 {
            classification = "mill-\(aggregates.millMax)"
        } else if aggregates.g2Live {
            classification = "g2-live"
        } else {
            classification = "other"
        }
        return LogSummary(
            fileName: aggregates.fileName,
            millMax: aggregates.millMax,
            reached68k: aggregates.reached68k,
            g2Live: aggregates.g2Live,
            empty300: aggregates.empty300,
            clusterPairCount: aggregates.clusterPairCount,
            skipEventCount: aggregates.skipEventCount,
            classification: classification,
            launchA9F2Count: aggregates.launchA9F2Count,
            loadSeg66Count: aggregates.loadSeg66Count,
            stayCode66Count: aggregates.stayCode66Count,
            code66HelperSnapCount: aggregates.code66HelperSnapCount
        )
    }

    private static func enrichOffsets(
        _ pairs: [(key: UInt64, value: Int)],
        space: AddressSpace,
        database: AnalysisDatabase
    ) -> [OffsetHistogramEntry] {
        pairs.map { offset, count in
            let address = AddressTranslation.virtualAddress(fromRomOffset: offset, space: space)
            let tags = AddressTranslation.millTags(for: address)
            let symbol = database.symbol(at: address)?.name
            let recommendation = recommendation(for: address, count: count, tags: tags)
            return OffsetHistogramEntry(
                offset: offset,
                count: count,
                space: space,
                tags: tags,
                symbolName: symbol,
                recommendation: recommendation
            )
        }
    }

    private static func recommendation(for address: ProgramAddress, count: Int, tags: [String]) -> String? {
        let offset: UInt64? = switch address.space {
        case .m68kToolbox: address.address
        case .ppcMacROM: AddressTranslation.romOffset(fromVirtual: address.address)
        default: nil
        }
        if let offset, let reason = MillSkip68kPolicy.blockReason(offset: offset) {
            return reason
        }
        if tags.contains("get-new-dialog-stub") {
            return "GetNewDialog overlay (id=\(G3MillClassification.overlayResourceID), pc=0x5C86C–0x5C8C0); not on toast — overlay ≠ WINDOW (\(G3MillClassification.splashWindowSize.width)×\(G3MillClassification.splashWindowSize.height) Splash is id=\(G3MillClassification.splashResourceID))."
        }
        if tags.contains("code66-helper") {
            return "\(G3MillClassification.loadSeg66FalsePathLabel); CODE 66 helper at 0x9440 — do not skip-68k leftover after KEEP 16511."
        }
        if tags.contains("no-skip-ui-trap") {
            return "Trap is in NO_SKIP_68K_OPS; keep native execution."
        }
        if tags.contains("skip-slot-helper") && count >= 5 {
            return "Repeated slot-helper spin; already milled or blocked by mill policy."
        }
        if address.space == .m68kToolbox && count >= 10 && !tags.contains("get-new-dialog-stub") {
            return "High-frequency millable 68k offset; review against rom_disasm."
        }
        return nil
    }

    private static func mergeHostedSamples(from source: [String], into destination: inout [String]) {
        for sample in source where !destination.contains(sample) {
            guard destination.count < 8 else { return }
            destination.append(sample)
        }
    }

    private static func buildRecommendations(
        ppc: [OffsetHistogramEntry],
        m68k: [OffsetHistogramEntry],
        traps: [TrapObservation],
        summaries: [LogSummary],
        discoveredLogs: Int,
        scannedLogs: Int,
        totalAvailableLogs: Int,
        keepLogsOnly: Bool,
        logScanLimit: Int,
        getNewDialogStubHits: Int,
        code66LogsWithStay: Int,
        code66HelperSnaps: Int,
        loadSeg66Logs: Int,
        launchA9F2Logs: Int,
        launchA9F2Count: Int,
        pefEnterCount: Int,
        pefImportCount: Int,
        pefWaitNextEventCount: Int,
        pefDceCount: Int,
        pefVolCount: Int,
        pefHostedDSICount: Int,
        pefHostedLocationSamples: [String],
        getNewDialogOverlayHits: Int,
        getNewDialogSplashHits: Int,
        xlateMissNersCount: Int
    ) -> [String] {
        var lines: [String] = []
        if keepLogsOnly, totalAvailableLogs > discoveredLogs {
            lines.append(
                "KEEP filter: analyzing \(discoveredLogs) of \(totalAvailableLogs) logs in folder. Turn off KEEP logs only to include empty/hang logs."
            )
        } else if !keepLogsOnly, totalAvailableLogs > discoveredLogs {
            lines.append("Discovered \(discoveredLogs) of \(totalAvailableLogs) logs in folder.")
        }
        if discoveredLogs > scannedLogs {
            if logScanLimit > 0 {
                lines.append("Processed \(scannedLogs) of \(discoveredLogs) discovered logs (scan limit \(logScanLimit)).")
            } else {
                lines.append("Processed \(scannedLogs) of \(discoveredLogs) discovered logs.")
            }
        }
        let keepCount = summaries.filter { $0.classification == "keep-68k" }.count
        let emptyCount = summaries.filter { $0.classification == "empty_300" }.count
        lines.append("Scanned \(summaries.count) logs: \(keepCount) reached stable 68k, \(emptyCount) empty-0x300 failures.")

        lines.append(contentsOf: G3MillClassification.recommendationLines(
            launchA9F2Logs: launchA9F2Logs,
            launchA9F2Count: launchA9F2Count,
            pefEnterCount: pefEnterCount,
            pefImportCount: pefImportCount,
            pefVolCount: pefVolCount,
            pefDceCount: pefDceCount,
            pefWaitNextEventCount: pefWaitNextEventCount,
            pefHostedDSICount: pefHostedDSICount,
            hostedLocationSamples: pefHostedLocationSamples
        ))

        if loadSeg66Logs > 0 {
            lines.append(
                "LoadSeg seg=66 in \(loadSeg66Logs) log(s): \(G3MillClassification.loadSeg66FalsePathLabel). Do not LoadSeg 66 from rsrc offset 0x\(String(format: "%X", G3MillClassification.loadSegKajrRsrcOffset)). Do not skip-68k leftover on CODE 66 after KEEP 16511."
            )
        }

        if getNewDialogOverlayHits > 0 {
            lines.append(
                "GetNewDialog overlay id=\(G3MillClassification.overlayResourceID) / pc=0x5005C86E (\(getNewDialogOverlayHits)×) — not on toast; overlay ≠ WINDOW (Splash id=\(G3MillClassification.splashResourceID) is \(G3MillClassification.splashWindowSize.width)×\(G3MillClassification.splashWindowSize.height); KEEP 16527 banner is \(G3MillClassification.keepBannerSize.width)×\(G3MillClassification.keepBannerSize.height))."
            )
        } else if getNewDialogStubHits > 0 {
            lines.append("GetNewDialog ROM stub (0x5C86C–0x5C8C0) observed \(getNewDialogStubHits)× — keep NO_SKIP protection; overlay not on toast.")
        }

        if getNewDialogSplashHits > 0 {
            lines.append(
                "PEF/toast GetNewDialog Splash id=\(G3MillClassification.splashResourceID) (\(getNewDialogSplashHits)×) — real installer DLOG \(G3MillClassification.splashWindowSize.width)×\(G3MillClassification.splashWindowSize.height); excludes host `Splash 510 even dlg=` pre-PEF plant."
            )
        }

        if xlateMissNersCount > 0 {
            lines.append(
                "xlate miss FourCC '\(G3MillClassification.fourCCString(G3MillClassification.nersFourCC))' (GetResource id \(G3MillClassification.nersResourceID) in Mac OS Install) observed \(xlateMissNersCount)× — missing GetResource 'ners', not a random DSI."
            )
        }

        if code66HelperSnaps > 0 {
            lines.append(
                "CODE 66 helper snap at 0x9440–0x94CF (\(code66HelperSnaps)×) in \(code66LogsWithStay) log(s) — kajr ROM fall-through, not G3 installer. Prefer CFM Upgrader / GetResource real DLOG id=\(G3MillClassification.splashResourceID), not stay-code66 or skip-68k 0x9440."
            )
        } else if code66LogsWithStay > 0, launchA9F2Logs == 0 {
            lines.append(
                "stay CODE 66 in \(code66LogsWithStay) log(s) without CFM Upgrader Launch — likely kajr false path; do not treat as G3 installer progress."
            )
        }

        if let candidate = m68k.first(where: {
            $0.count >= 5
                && MillSkip68kPolicy.isMillable(offset: $0.offset)
                && ($0.recommendation?.contains("High-frequency millable") ?? false)
        }) {
            lines.append("Top skip candidate: 68k offset 0x\(String(format: "%X", candidate.offset)) (\(candidate.count)×).")
        }

        let protectedTraps = traps.filter(\.noSkipProtected).prefix(5)
        if !protectedTraps.isEmpty {
            let names = protectedTraps.map(\.name).joined(separator: ", ")
            lines.append("Protected traps still exercised in logs: \(names).")
        }

        if let heartbeat = ppc.first(where: { $0.tags.contains("heartbeat-cluster") }) {
            lines.append("Heartbeat cluster hotspot ROM+0x\(String(format: "%X", heartbeat.offset)) (\(heartbeat.count)×).")
        }

        return lines
    }
}
