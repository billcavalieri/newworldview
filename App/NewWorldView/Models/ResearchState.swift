import Combine
import Foundation
import NewWorldROM

struct MillBookmark: Codable, Identifiable, Hashable {
    var id: UUID
    var label: String
    var addressText: String
    var createdAt: Date

    init(label: String, addressText: String) {
        self.id = UUID()
        self.label = label
        self.addressText = addressText
        self.createdAt = Date()
    }
}

@MainActor
final class ResearchState: ObservableObject {
    @Published var logJumpText = ""
    @Published var addressQuery = ""
    @Published var bookmarks: [MillBookmark] = []
    @Published var skipOverlayOffsets: Set<UInt64> = []
    @Published var showSkipOverlay = true
    @Published var trapFilter: GhidraExport.TrapExportFilter = .all
    @Published var historicalReport: MillResearchEngine.HistoricalReport?
    @Published var isAnalyzingLogs = false
    @Published var logAnalysisProgress = MillLogAnalysisProgress.zero
    @Published var logDirectoryPath = MillResearchEngine.defaultLogDirectory.path
    @Published var logCacheStatus: MillLogCacheStore.CacheStatus?
    @Published var grokSnippet = ""
    @Published var compareLines: [DisasmCompare.Line] = []
    @Published var lookupResult: AnalysisLookup.LookupResult?
    @Published var callPath: [CallPathTracer.PathStep] = []
    @Published var macROM: Data?
    @Published var lastError: String?

    private var logAnalysisSession: MillLogAnalysisSession?
    private var logCacheStore: MillLogCacheStore?

    var hasLogDirectoryAccess: Bool {
        UserDefaults.standard.data(forKey: Self.logDirectoryBookmarkDefaultsKey) != nil
    }

    private var bookmarksKey: String { "NewWorldView.millBookmarks.\(romKey)" }
    private let romKey: String

    init(romKey: String) {
        self.romKey = romKey
        if let saved = UserDefaults.standard.string(forKey: Self.logDirectoryDefaultsKey),
           FileManager.default.fileExists(atPath: saved) {
            logDirectoryPath = saved
        }
        loadBookmarks()
    }

    func setLogDirectory(_ url: URL) {
        logDirectoryPath = url.path
        UserDefaults.standard.set(url.path, forKey: Self.logDirectoryDefaultsKey)
        lastError = nil

        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: Self.logDirectoryBookmarkDefaultsKey)
        } catch {
            lastError = "Could not save folder access: \(error.localizedDescription)"
        }
    }

    private static let logDirectoryDefaultsKey = "NewWorldView.millLogDirectory"
    private static let logDirectoryBookmarkDefaultsKey = "NewWorldView.millLogDirectoryBookmark"

    func loadBookmarks() {
        guard let data = UserDefaults.standard.data(forKey: bookmarksKey),
              let decoded = try? JSONDecoder().decode([MillBookmark].self, from: data)
        else { return }
        bookmarks = decoded
    }

    func saveBookmarks() {
        guard let data = try? JSONEncoder().encode(bookmarks) else { return }
        UserDefaults.standard.set(data, forKey: bookmarksKey)
    }

    func addBookmark(label: String, addressText: String) {
        bookmarks.insert(MillBookmark(label: label, addressText: addressText), at: 0)
        saveBookmarks()
    }

    func removeBookmark(id: UUID) {
        bookmarks.removeAll { $0.id == id }
        saveBookmarks()
    }

    func decodeMacROMIfNeeded(from rawData: Data) async {
        guard macROM == nil else { return }
        let decoded = await Task.detached(priority: .utility) {
            try? MacROMImageDecoder.decode(rawData).image
        }.value
        macROM = decoded
    }

    func runLookup(parsed: ParsedROM, database: AnalysisDatabase) {
        lookupResult = AnalysisLookup.lookup(addressQuery, in: parsed, database: database)
        if let address = lookupResult?.address {
            callPath = CallPathTracer.traceToHeartbeatCluster(from: address, database: database)
            if let macROM {
                compareLines = DisasmCompare.compareAtAddress(address, macROM: macROM, database: database)?.lines ?? []
            }
        } else {
            callPath = []
            compareLines = []
        }
    }

    func jumpAddress(from logLine: String) -> ProgramAddress? {
        MillLogParser.parseLogLine(logLine)
    }

    func makeGrokPack(
        address: ProgramAddress,
        parsed: ParsedROM,
        database: AnalysisDatabase
    ) {
        let snippet = GrokPackGenerator.makeSnippet(
            address: address,
            parsed: parsed,
            database: database,
            macROM: macROM
        )
        grokSnippet = snippet.body
    }

    func makeGrokPackFromLog(
        parsed: ParsedROM,
        database: AnalysisDatabase
    ) {
        guard let snippet = GrokPackGenerator.makeSnippet(
            from: logJumpText,
            parsed: parsed,
            database: database,
            macROM: macROM
        ) else {
            lastError = "Could not parse a PC from that log line."
            return
        }
        grokSnippet = snippet.body
        lastError = nil
    }

    func cancelLogAnalysis() {
        logAnalysisSession?.cancel()
    }

    func refreshLogCacheStatus() {
        guard hasLogDirectoryAccess,
              let directory = try? resolveLogDirectoryURL(),
              let store = try? ensureLogCacheStore()
        else {
            logCacheStatus = nil
            return
        }
        logCacheStatus = try? store.cacheStatus(for: directory)
    }

    func loadCachedReportIfAvailable(
        database: AnalysisDatabase,
        logScanLimit: Int,
        histogramLimit: Int,
        keepLogsOnly: Bool
    ) async {
        guard hasLogDirectoryAccess else { return }

        do {
            let directory = try resolveLogDirectoryURL()
            let store = try ensureLogCacheStore()
            refreshLogCacheStatus()

            let accessing = directory.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    directory.stopAccessingSecurityScopedResource()
                }
            }

            let discoveryOptions = MillLogDiscovery.Options.sandboxed(
                in: directory,
                keepLogsOnly: keepLogsOnly
            )
            let discovered = try MillLogDiscovery.orderedLogURLs(options: discoveryOptions)
            let totalAvailable = MillLogDiscovery.countAvailableLogFiles(in: directory)
            let logs: [URL]
            if logScanLimit <= 0 {
                logs = discovered
            } else {
                logs = Array(discovered.prefix(logScanLimit))
            }
            guard !logs.isEmpty else { return }

            if let report = try store.buildReportIfComplete(
                logURLs: logs,
                logDirectory: directory,
                database: database,
                histogramLimit: histogramLimit,
                discoveredLogs: discovered.count,
                totalAvailableLogs: totalAvailable,
                keepLogsOnly: keepLogsOnly,
                logScanLimit: logScanLimit
            ) {
                historicalReport = report
                skipOverlayOffsets = MillResearchEngine.overlayOffsets(from: report)
                lastError = nil
            }
        } catch {
            lastError = friendlyLogAnalysisError(error, directory: logDirectoryPath)
        }
    }

    func purgeLogCache(clearReport: Bool = true) {
        guard hasLogDirectoryAccess,
              let directory = try? resolveLogDirectoryURL(),
              let store = try? ensureLogCacheStore()
        else {
            lastError = "Choose the log folder before purging the cache."
            return
        }

        do {
            try store.purge(logDirectory: directory)
            if clearReport {
                historicalReport = nil
                skipOverlayOffsets = []
            }
            refreshLogCacheStatus()
            lastError = nil
        } catch {
            lastError = "Could not purge mill log cache: \(error.localizedDescription)"
        }
    }

    func analyzeHistoricalLogs(
        database: AnalysisDatabase,
        logScanLimit: Int,
        histogramLimit: Int,
        keepLogsOnly: Bool = MillResearchSettings.defaultKeepLogsOnly,
        forceReload: Bool = false
    ) async {
        logAnalysisSession?.cancel()

        let session = MillLogAnalysisSession()
        logAnalysisSession = session
        let startedAt = Date()

        isAnalyzingLogs = true
        logAnalysisProgress = MillLogAnalysisProgress(
            completed: 0,
            total: 0,
            currentFileName: nil,
            startedAt: startedAt
        )
        defer {
            isAnalyzingLogs = false
            logAnalysisProgress = .zero
            logAnalysisSession = nil
        }

        guard hasLogDirectoryAccess else {
            historicalReport = nil
            lastError = "Choose the log folder once so NewWorldView can read it under the app sandbox."
            return
        }

        do {
            let directory = try resolveLogDirectoryURL()
            let cacheStore = try ensureLogCacheStore()
            let report = try await Task.detached(priority: .userInitiated) {
                [logScanLimit, histogramLimit, keepLogsOnly, forceReload, session, startedAt, directory, cacheStore] in
                let accessing = directory.startAccessingSecurityScopedResource()
                defer {
                    if accessing {
                        directory.stopAccessingSecurityScopedResource()
                    }
                }

                let discoveryOptions = MillLogDiscovery.Options.sandboxed(
                    in: directory,
                    keepLogsOnly: keepLogsOnly
                )
                return try MillResearchEngine.analyzeHistoricalLogs(
                    in: directory,
                    database: database,
                    limit: logScanLimit,
                    histogramLimit: histogramLimit,
                    discoveryOptions: discoveryOptions,
                    cacheStore: cacheStore,
                    forceReload: forceReload,
                    progress: { completed, total, currentFileName in
                        guard completed == 0 || completed == total || completed % 16 == 0 else { return }
                        Task { @MainActor in
                            self.logAnalysisProgress = MillLogAnalysisProgress(
                                completed: completed,
                                total: total,
                                currentFileName: currentFileName,
                                startedAt: startedAt
                            )
                        }
                    },
                    isCancelled: { session.isCancelled() }
                )
            }.value

            guard !session.isCancelled() else {
                lastError = "Analysis cancelled."
                return
            }

            await Task.yield()
            historicalReport = report
            skipOverlayOffsets = MillResearchEngine.overlayOffsets(from: report)
            refreshLogCacheStatus()
            if report.scannedLogs == 0 {
                lastError = "No ss-g3-mill-*.log or ss-g3-mill-*.log.gz files found in the selected folder."
            } else {
                lastError = nil
            }
        } catch is CancellationError {
            lastError = "Analysis cancelled."
        } catch {
            historicalReport = nil
            lastError = friendlyLogAnalysisError(error, directory: (try? resolveLogDirectoryURL())?.path)
        }
    }

    private func friendlyLogAnalysisError(_ error: Error, directory: String?) -> String {
        let message = error.localizedDescription
        if message.contains("permission") || message.contains("Permission") {
            let folder = directory ?? logDirectoryPath
            return """
            Could not read a mill log outside the granted folder (often `/tmp`). \
            Copy logs into `\(folder)` or click Choose… again, then retry Analyze logs. \
            (\(message))
            """
        }
        return message
    }

    private func ensureLogCacheStore() throws -> MillLogCacheStore {
        if let logCacheStore {
            return logCacheStore
        }
        let store = try MillLogCacheStore.defaultStore()
        logCacheStore = store
        return store
    }

    private func resolveLogDirectoryURL() throws -> URL {
        guard let bookmarkData = UserDefaults.standard.data(forKey: Self.logDirectoryBookmarkDefaultsKey) else {
            throw LogDirectoryAccessError.bookmarkMissing
        }

        var stale = false
        let url = try URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )

        if stale {
            let refreshed = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(refreshed, forKey: Self.logDirectoryBookmarkDefaultsKey)
        }

        logDirectoryPath = url.path
        UserDefaults.standard.set(url.path, forKey: Self.logDirectoryDefaultsKey)
        return url
    }
}

private enum LogDirectoryAccessError: LocalizedError {
    case bookmarkMissing

    var errorDescription: String? {
        switch self {
        case .bookmarkMissing:
            return "Choose the log folder once so NewWorldView can read it under the app sandbox."
        }
    }
}
