import Foundation
import NewWorldROM
import Testing

struct MillLogCacheStoreTests {
    @Test func roundTripsAggregatesThroughSQLite() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mill-cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let logURL = directory.appendingPathComponent("ss-g3-mill-6613.log")
        try "KEEP 68k hang pc=50366084\n".write(to: logURL, atomically: true, encoding: .utf8)

        let aggregates = try MillLogParser.accumulateAggregates(from: logURL)
        let dbURL = directory.appendingPathComponent("cache.sqlite")
        let store = try MillLogCacheStore(databaseURL: dbURL)

        try store.store(aggregates: aggregates, logURL: logURL, logDirectory: directory)
        let loaded = try #require(try store.loadAggregates(for: logURL))
        #expect(loaded == aggregates)

        let status = try store.cacheStatus(for: directory)
        #expect(status.cachedLogCount == 1)
        #expect(status.lastUpdated != nil)
    }

    @Test func incrementalAnalysisUsesCache() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mill-cache-incr-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let logURL = directory.appendingPathComponent("ss-g3-mill-6613.log")
        try "KEEP 68k hang pc=50366084\n".write(to: logURL, atomically: true, encoding: .utf8)

        let dbURL = directory.appendingPathComponent("cache.sqlite")
        let store = try MillLogCacheStore(databaseURL: dbURL)
        let aggregates = try MillLogParser.accumulateAggregates(from: logURL)
        try store.store(aggregates: aggregates, logURL: logURL, logDirectory: directory)

        let report = try MillResearchEngine.analyzeHistoricalLogs(
            in: directory,
            limit: 0,
            histogramLimit: 100,
            discoveryOptions: MillLogDiscovery.Options(
                directory: directory,
                tmpDirectory: directory,
                keepLogsOnly: false
            ),
            cacheStore: store
        )
        #expect(report.scannedLogs == 1)
        #expect(report.logSummaries.first?.fileName == logURL.lastPathComponent)
    }

    @Test func purgeRemovesDirectoryEntries() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mill-cache-purge-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let logURL = directory.appendingPathComponent("ss-g3-mill-6613.log")
        try "KEEP 68k hang pc=50366084\n".write(to: logURL, atomically: true, encoding: .utf8)

        let dbURL = directory.appendingPathComponent("cache.sqlite")
        let store = try MillLogCacheStore(databaseURL: dbURL)
        let aggregates = try MillLogParser.accumulateAggregates(from: logURL)
        try store.store(aggregates: aggregates, logURL: logURL, logDirectory: directory)
        #expect(try store.cacheStatus(for: directory).cachedLogCount == 1)

        try store.purge(logDirectory: directory)
        #expect(try store.cacheStatus(for: directory).cachedLogCount == 0)
        #expect(try store.loadAggregates(for: logURL) == nil)
    }

    @Test func staleFileIsReparsedAfterModification() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mill-cache-stale-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let logURL = directory.appendingPathComponent("ss-g3-mill-6613.log")
        try "KEEP 68k hang pc=50366084\n".write(to: logURL, atomically: true, encoding: .utf8)

        let dbURL = directory.appendingPathComponent("cache.sqlite")
        let store = try MillLogCacheStore(databaseURL: dbURL)
        let first = try MillLogParser.accumulateAggregates(from: logURL)
        try store.store(aggregates: first, logURL: logURL, logDirectory: directory)

        try "KEEP 68k hang pc=50366084\nmill=6613\n".write(to: logURL, atomically: true, encoding: .utf8)
        #expect(try store.loadAggregates(for: logURL) == nil)

        let report = try MillResearchEngine.analyzeHistoricalLogs(
            in: directory,
            limit: 0,
            histogramLimit: 100,
            discoveryOptions: MillLogDiscovery.Options(
                directory: directory,
                tmpDirectory: directory,
                keepLogsOnly: false
            ),
            cacheStore: store
        )
        #expect(report.logSummaries.first?.millMax == 6613)
    }
}
