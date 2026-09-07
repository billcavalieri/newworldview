import CryptoKit
import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Persists per-log mill aggregates so historical analysis can skip unchanged files.
public final class MillLogCacheStore: @unchecked Sendable {
    public static let schemaVersion = 5

    public struct CacheStatus: Sendable, Equatable {
        public var directoryPath: String
        public var cachedLogCount: Int
        public var lastUpdated: Date?

        public init(directoryPath: String, cachedLogCount: Int, lastUpdated: Date?) {
            self.directoryPath = directoryPath
            self.cachedLogCount = cachedLogCount
            self.lastUpdated = lastUpdated
        }
    }

    private let dbURL: URL
    private let lock = NSLock()
    private var db: OpaquePointer?

    public init(databaseURL: URL) throws {
        dbURL = databaseURL
        let directory = databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try openDatabase()
        try migrate()
    }

    public static func defaultStore() throws -> MillLogCacheStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NewWorldView", isDirectory: true)
        return try MillLogCacheStore(databaseURL: base.appendingPathComponent("mill-log-cache.sqlite"))
    }

    deinit {
        lock.lock()
        if db != nil {
            sqlite3_close(db)
        }
        lock.unlock()
    }

    public func cacheStatus(for directory: URL) throws -> CacheStatus {
        let path = Self.standardPath(directory)
        return try withDatabase { db in
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            let sql = """
            SELECT COUNT(*), MAX(parsed_at)
            FROM log_aggregate
            WHERE directory_path = ?1;
            """
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw Self.databaseError(db, context: "prepare cacheStatus")
            }
            sqlite3_bind_text(statement, 1, path, -1, sqliteTransient)

            guard sqlite3_step(statement) == SQLITE_ROW else {
                return CacheStatus(directoryPath: path, cachedLogCount: 0, lastUpdated: nil)
            }
            let count = Int(sqlite3_column_int64(statement, 0))
            let updatedAt: Date?
            if sqlite3_column_type(statement, 1) == SQLITE_NULL {
                updatedAt = nil
            } else {
                updatedAt = Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 1))
            }
            return CacheStatus(directoryPath: path, cachedLogCount: count, lastUpdated: updatedAt)
        }
    }

    public func loadAggregates(for logURL: URL) throws -> MillLogParser.LogAggregates? {
        let path = Self.standardPath(logURL)
        return try withDatabase { db in
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            let sql = """
            SELECT file_name, mtime, file_size, file_digest, mill_max, reached_68k, g2_live, empty_300,
                   hang_04cecd36, cluster_pair_count, skip_event_count,
                   launch_a9f2_count, load_seg66_count, stay_code66_count, code66_helper_snap_count,
                   get_new_dialog_stub_hits, pef_enter_count, get_new_dialog_overlay_hits,
                   get_new_dialog_splash_hits, xlate_miss_ners_count,
                   pef_import_count, pef_wait_count, pef_dce_count, pef_vol_count,
                   pef_hosted_dsi_count, pef_hosted_samples
            FROM log_aggregate
            WHERE path = ?1;
            """
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw Self.databaseError(db, context: "prepare loadAggregates")
            }
            sqlite3_bind_text(statement, 1, path, -1, sqliteTransient)
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }

            let storedMtime = sqlite3_column_double(statement, 1)
            let storedSize = sqlite3_column_int64(statement, 2)
            let storedDigest = String(cString: sqlite3_column_text(statement, 3))
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            let currentMtime = (attributes[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate ?? 0
            let currentSize = (attributes[.size] as? NSNumber)?.int64Value ?? -1
            let currentDigest = try Self.fileDigest(for: logURL)
            guard storedMtime == currentMtime,
                  storedSize == currentSize,
                  storedDigest == currentDigest
            else { return nil }

            let fileName = String(cString: sqlite3_column_text(statement, 0))
            var aggregates = MillLogParser.LogAggregates(
                fileName: fileName,
                millMax: Int(sqlite3_column_int(statement, 4)),
                reached68k: sqlite3_column_int(statement, 5) != 0,
                g2Live: sqlite3_column_int(statement, 6) != 0,
                empty300: sqlite3_column_int(statement, 7) != 0,
                hang04cecd36: sqlite3_column_int(statement, 8) != 0,
                launchA9F2Count: Self.columnInt(statement, 11, default: 0),
                loadSeg66Count: Self.columnInt(statement, 12, default: 0),
                stayCode66Count: Self.columnInt(statement, 13, default: 0),
                code66HelperSnapCount: Self.columnInt(statement, 14, default: 0),
                getNewDialogStubHits: Self.columnInt(statement, 15, default: 0),
                pefEnterCount: Self.columnInt(statement, 16, default: 0),
                pefImportCount: Self.columnInt(statement, 20, default: 0),
                pefWaitNextEventCount: Self.columnInt(statement, 21, default: 0),
                pefDceCount: Self.columnInt(statement, 22, default: 0),
                pefVolCount: Self.columnInt(statement, 23, default: 0),
                pefHostedDSICount: Self.columnInt(statement, 24, default: 0),
                pefHostedLocationSamples: Self.columnStringArray(statement, 25),
                getNewDialogOverlayHits: Self.columnInt(statement, 17, default: 0),
                getNewDialogSplashHits: Self.columnInt(statement, 18, default: 0),
                xlateMissNersCount: Self.columnInt(statement, 19, default: 0),
                clusterPairCount: Int(sqlite3_column_int(statement, 9)),
                skipEventCount: Int(sqlite3_column_int(statement, 10)),
                ppcOffsetCounts: [:],
                m68kOffsetCounts: [:],
                trapCounts: [:]
            )
            aggregates.ppcOffsetCounts = try Self.loadOffsetHits(db: db, logPath: path, table: "ppc_offset_hit")
            aggregates.m68kOffsetCounts = try Self.loadOffsetHits(db: db, logPath: path, table: "m68k_offset_hit")
            aggregates.trapCounts = try Self.loadTrapHits(db: db, logPath: path)
            return aggregates
        }
    }

    public func store(
        aggregates: MillLogParser.LogAggregates,
        logURL: URL,
        logDirectory: URL
    ) throws {
        let logPath = Self.standardPath(logURL)
        let directoryPath = Self.standardPath(logDirectory)
        let attributes = try FileManager.default.attributesOfItem(atPath: logPath)
        let mtime = (attributes[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate ?? 0
        let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let fileDigest = try Self.fileDigest(for: logURL)
        let summary = MillResearchEngine.logSummary(from: aggregates)
        let parsedAt = Date.timeIntervalSinceReferenceDate

        try withDatabase { db in
            try Self.exec(db, "BEGIN IMMEDIATE TRANSACTION;")
            do {
                try Self.exec(
                    db,
                    """
                    INSERT INTO directory_cache(path, updated_at)
                    VALUES (?1, ?2)
                    ON CONFLICT(path) DO UPDATE SET updated_at = excluded.updated_at;
                    """,
                    directoryPath,
                    parsedAt
                )

                try Self.exec(
                    db,
                    """
                    INSERT INTO log_aggregate(
                        path, directory_path, file_name, mtime, file_size, file_digest, mill_max, reached_68k,
                        g2_live, empty_300,                         hang_04cecd36, cluster_pair_count, skip_event_count,
                        launch_a9f2_count, load_seg66_count, stay_code66_count, code66_helper_snap_count,
                        get_new_dialog_stub_hits,
                        pef_enter_count, get_new_dialog_overlay_hits, get_new_dialog_splash_hits,
                        xlate_miss_ners_count,
                        pef_import_count, pef_wait_count, pef_dce_count, pef_vol_count,
                        pef_hosted_dsi_count, pef_hosted_samples,
                        classification, parsed_at
                    ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20, ?21, ?22, ?23, ?24, ?25, ?26, ?27, ?28, ?29, ?30)
                    ON CONFLICT(path) DO UPDATE SET
                        directory_path = excluded.directory_path,
                        file_name = excluded.file_name,
                        mtime = excluded.mtime,
                        file_size = excluded.file_size,
                        file_digest = excluded.file_digest,
                        mill_max = excluded.mill_max,
                        reached_68k = excluded.reached_68k,
                        g2_live = excluded.g2_live,
                        empty_300 = excluded.empty_300,
                        hang_04cecd36 = excluded.hang_04cecd36,
                        cluster_pair_count = excluded.cluster_pair_count,
                        skip_event_count = excluded.skip_event_count,
                        launch_a9f2_count = excluded.launch_a9f2_count,
                        load_seg66_count = excluded.load_seg66_count,
                        stay_code66_count = excluded.stay_code66_count,
                        code66_helper_snap_count = excluded.code66_helper_snap_count,
                        get_new_dialog_stub_hits = excluded.get_new_dialog_stub_hits,
                        pef_enter_count = excluded.pef_enter_count,
                        get_new_dialog_overlay_hits = excluded.get_new_dialog_overlay_hits,
                        get_new_dialog_splash_hits = excluded.get_new_dialog_splash_hits,
                        xlate_miss_ners_count = excluded.xlate_miss_ners_count,
                        pef_import_count = excluded.pef_import_count,
                        pef_wait_count = excluded.pef_wait_count,
                        pef_dce_count = excluded.pef_dce_count,
                        pef_vol_count = excluded.pef_vol_count,
                        pef_hosted_dsi_count = excluded.pef_hosted_dsi_count,
                        pef_hosted_samples = excluded.pef_hosted_samples,
                        classification = excluded.classification,
                        parsed_at = excluded.parsed_at;
                    """,
                    logPath,
                    directoryPath,
                    summary.fileName,
                    mtime,
                    fileSize,
                    fileDigest,
                    Int64(summary.millMax),
                    summary.reached68k ? 1 : 0,
                    summary.g2Live ? 1 : 0,
                    summary.empty300 ? 1 : 0,
                    aggregates.hang04cecd36 ? 1 : 0,
                    Int64(summary.clusterPairCount),
                    Int64(summary.skipEventCount),
                    Int64(aggregates.launchA9F2Count),
                    Int64(aggregates.loadSeg66Count),
                    Int64(aggregates.stayCode66Count),
                    Int64(aggregates.code66HelperSnapCount),
                    Int64(aggregates.getNewDialogStubHits),
                    Int64(aggregates.pefEnterCount),
                    Int64(aggregates.getNewDialogOverlayHits),
                    Int64(aggregates.getNewDialogSplashHits),
                    Int64(aggregates.xlateMissNersCount),
                    Int64(aggregates.pefImportCount),
                    Int64(aggregates.pefWaitNextEventCount),
                    Int64(aggregates.pefDceCount),
                    Int64(aggregates.pefVolCount),
                    Int64(aggregates.pefHostedDSICount),
                    Self.encodeStringArray(aggregates.pefHostedLocationSamples),
                    summary.classification,
                    parsedAt
                )

                try Self.deleteHits(db: db, logPath: logPath)
                try Self.insertOffsetHits(db: db, logPath: logPath, table: "ppc_offset_hit", counts: aggregates.ppcOffsetCounts)
                try Self.insertOffsetHits(db: db, logPath: logPath, table: "m68k_offset_hit", counts: aggregates.m68kOffsetCounts)
                try Self.insertTrapHits(db: db, logPath: logPath, counts: aggregates.trapCounts)
                try Self.exec(db, "COMMIT;")
            } catch {
                _ = try? Self.exec(db, "ROLLBACK;")
                throw error
            }
        }
    }

    public func purge(logDirectory: URL) throws {
        let directoryPath = Self.standardPath(logDirectory)
        try withDatabase { db in
            try Self.exec(db, "BEGIN IMMEDIATE TRANSACTION;")
            defer {
                _ = try? Self.exec(db, "COMMIT;")
            }
            try Self.exec(db, "DELETE FROM log_aggregate WHERE directory_path = ?1;", directoryPath)
            try Self.exec(db, "DELETE FROM directory_cache WHERE path = ?1;", directoryPath)
        }
    }

    public func purgeAll() throws {
        try withDatabase { db in
            try Self.exec(db, "DELETE FROM ppc_offset_hit;")
            try Self.exec(db, "DELETE FROM m68k_offset_hit;")
            try Self.exec(db, "DELETE FROM trap_hit;")
            try Self.exec(db, "DELETE FROM log_aggregate;")
            try Self.exec(db, "DELETE FROM directory_cache;")
        }
    }

    public func buildReportIfComplete(
        logURLs: [URL],
        logDirectory: URL,
        database: AnalysisDatabase,
        histogramLimit: Int,
        discoveredLogs: Int,
        totalAvailableLogs: Int,
        keepLogsOnly: Bool,
        logScanLimit: Int
    ) throws -> MillResearchEngine.HistoricalReport? {
        guard !logURLs.isEmpty else { return nil }

        var aggregates: [MillLogParser.LogAggregates] = []
        aggregates.reserveCapacity(logURLs.count)
        for url in logURLs {
            guard let cached = try loadAggregates(for: url) else { return nil }
            aggregates.append(cached)
        }
        return MillResearchEngine.buildHistoricalReport(
            from: aggregates,
            database: database,
            histogramLimit: histogramLimit,
            discoveredLogs: discoveredLogs,
            scannedLogs: logURLs.count,
            totalAvailableLogs: totalAvailableLogs,
            keepLogsOnly: keepLogsOnly,
            logScanLimit: logScanLimit
        )
    }

    private func openDatabase() throws {
        lock.lock()
        defer { lock.unlock() }
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else {
            let message = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw MillLogCacheError.openFailed(message)
        }
        try Self.exec(db!, "PRAGMA foreign_keys = ON;")
        try Self.exec(db!, "PRAGMA journal_mode = WAL;")
    }

    private func migrate() throws {
        try withDatabase { db in
            try Self.exec(
                db,
                """
                CREATE TABLE IF NOT EXISTS meta (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL
                );
                """
            )
            try Self.exec(
                db,
                """
                CREATE TABLE IF NOT EXISTS directory_cache (
                    path TEXT PRIMARY KEY,
                    updated_at REAL NOT NULL
                );
                """
            )
            try Self.exec(
                db,
                """
                CREATE TABLE IF NOT EXISTS log_aggregate (
                    path TEXT PRIMARY KEY,
                    directory_path TEXT NOT NULL,
                    file_name TEXT NOT NULL,
                    mtime REAL NOT NULL,
                    file_size INTEGER NOT NULL,
                    file_digest TEXT NOT NULL,
                    mill_max INTEGER NOT NULL,
                    reached_68k INTEGER NOT NULL,
                    g2_live INTEGER NOT NULL,
                    empty_300 INTEGER NOT NULL,
                    hang_04cecd36 INTEGER NOT NULL,
                    cluster_pair_count INTEGER NOT NULL,
                    skip_event_count INTEGER NOT NULL,
                    classification TEXT NOT NULL,
                    parsed_at REAL NOT NULL
                );
                """
            )
            try Self.ensureColumn(db, table: "log_aggregate", column: "file_digest", definition: "TEXT NOT NULL DEFAULT ''")
            try Self.ensureColumn(db, table: "log_aggregate", column: "launch_a9f2_count", definition: "INTEGER NOT NULL DEFAULT 0")
            try Self.ensureColumn(db, table: "log_aggregate", column: "load_seg66_count", definition: "INTEGER NOT NULL DEFAULT 0")
            try Self.ensureColumn(db, table: "log_aggregate", column: "stay_code66_count", definition: "INTEGER NOT NULL DEFAULT 0")
            try Self.ensureColumn(db, table: "log_aggregate", column: "code66_helper_snap_count", definition: "INTEGER NOT NULL DEFAULT 0")
            try Self.ensureColumn(db, table: "log_aggregate", column: "get_new_dialog_stub_hits", definition: "INTEGER NOT NULL DEFAULT 0")
            try Self.ensureColumn(db, table: "log_aggregate", column: "pef_enter_count", definition: "INTEGER NOT NULL DEFAULT 0")
            try Self.ensureColumn(db, table: "log_aggregate", column: "get_new_dialog_overlay_hits", definition: "INTEGER NOT NULL DEFAULT 0")
            try Self.ensureColumn(db, table: "log_aggregate", column: "get_new_dialog_splash_hits", definition: "INTEGER NOT NULL DEFAULT 0")
            try Self.ensureColumn(db, table: "log_aggregate", column: "xlate_miss_ners_count", definition: "INTEGER NOT NULL DEFAULT 0")
            try Self.ensureColumn(db, table: "log_aggregate", column: "pef_import_count", definition: "INTEGER NOT NULL DEFAULT 0")
            try Self.ensureColumn(db, table: "log_aggregate", column: "pef_wait_count", definition: "INTEGER NOT NULL DEFAULT 0")
            try Self.ensureColumn(db, table: "log_aggregate", column: "pef_dce_count", definition: "INTEGER NOT NULL DEFAULT 0")
            try Self.ensureColumn(db, table: "log_aggregate", column: "pef_vol_count", definition: "INTEGER NOT NULL DEFAULT 0")
            try Self.ensureColumn(db, table: "log_aggregate", column: "pef_hosted_dsi_count", definition: "INTEGER NOT NULL DEFAULT 0")
            try Self.ensureColumn(db, table: "log_aggregate", column: "pef_hosted_samples", definition: "TEXT NOT NULL DEFAULT '[]'")
            try Self.exec(
                db,
                """
                CREATE TABLE IF NOT EXISTS ppc_offset_hit (
                    log_path TEXT NOT NULL,
                    offset INTEGER NOT NULL,
                    count INTEGER NOT NULL,
                    PRIMARY KEY (log_path, offset)
                );
                """
            )
            try Self.exec(
                db,
                """
                CREATE TABLE IF NOT EXISTS m68k_offset_hit (
                    log_path TEXT NOT NULL,
                    offset INTEGER NOT NULL,
                    count INTEGER NOT NULL,
                    PRIMARY KEY (log_path, offset)
                );
                """
            )
            try Self.exec(
                db,
                """
                CREATE TABLE IF NOT EXISTS trap_hit (
                    log_path TEXT NOT NULL,
                    trap INTEGER NOT NULL,
                    count INTEGER NOT NULL,
                    PRIMARY KEY (log_path, trap)
                );
                """
            )
            try Self.exec(
                db,
                "CREATE INDEX IF NOT EXISTS idx_log_aggregate_directory ON log_aggregate(directory_path);"
            )
            try Self.exec(
                db,
                """
                INSERT INTO meta(key, value) VALUES ('schema_version', ?1)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value;
                """,
                String(Self.schemaVersion)
            )
        }
    }

    private func withDatabase<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { throw MillLogCacheError.notOpen }
        return try body(db)
    }

    private static func columnInt(_ statement: OpaquePointer?, _ index: Int32, default defaultValue: Int) -> Int {
        guard let statement else { return defaultValue }
        if sqlite3_column_type(statement, index) == SQLITE_NULL {
            return defaultValue
        }
        return Int(sqlite3_column_int(statement, index))
    }

    private static func columnStringArray(_ statement: OpaquePointer?, _ index: Int32) -> [String] {
        guard let statement,
              sqlite3_column_type(statement, index) != SQLITE_NULL,
              let text = sqlite3_column_text(statement, index) else { return [] }
        let json = String(cString: text)
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return decoded
    }

    private static func encodeStringArray(_ values: [String]) -> String {
        guard let data = try? JSONEncoder().encode(values),
              let json = String(data: data, encoding: .utf8) else { return "[]" }
        return json
    }

    private static func standardPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func fileDigest(for url: URL) throws -> String {
        let data = try MillLogReader.decompressedContents(of: url)
        return SHA256.hash(data: data).hexString
    }

    private static func ensureColumn(
        _ db: OpaquePointer,
        table: String,
        column: String,
        definition: String
    ) throws {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table));", -1, &statement, nil) == SQLITE_OK else {
            throw databaseError(db, context: "prepare ensureColumn")
        }
        while sqlite3_step(statement) == SQLITE_ROW {
            let name = String(cString: sqlite3_column_text(statement, 1))
            if name == column {
                return
            }
        }
        try exec(db, "ALTER TABLE \(table) ADD COLUMN \(column) \(definition);")
    }

    private static func loadOffsetHits(db: OpaquePointer, logPath: String, table: String) throws -> [UInt64: Int] {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let sql = "SELECT offset, count FROM \(table) WHERE log_path = ?1;"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError(db, context: "prepare loadOffsetHits")
        }
        sqlite3_bind_text(statement, 1, logPath, -1, sqliteTransient)
        var counts: [UInt64: Int] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            let offset = UInt64(sqlite3_column_int64(statement, 0))
            let count = Int(sqlite3_column_int(statement, 1))
            counts[offset] = count
        }
        return counts
    }

    private static func loadTrapHits(db: OpaquePointer, logPath: String) throws -> [UInt16: Int] {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let sql = "SELECT trap, count FROM trap_hit WHERE log_path = ?1;"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError(db, context: "prepare loadTrapHits")
        }
        sqlite3_bind_text(statement, 1, logPath, -1, sqliteTransient)
        var counts: [UInt16: Int] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            let trap = UInt16(sqlite3_column_int(statement, 0))
            let count = Int(sqlite3_column_int(statement, 1))
            counts[trap] = count
        }
        return counts
    }

    private static func deleteHits(db: OpaquePointer, logPath: String) throws {
        try exec(db, "DELETE FROM ppc_offset_hit WHERE log_path = ?1;", logPath)
        try exec(db, "DELETE FROM m68k_offset_hit WHERE log_path = ?1;", logPath)
        try exec(db, "DELETE FROM trap_hit WHERE log_path = ?1;", logPath)
    }

    private static func insertOffsetHits(
        db: OpaquePointer,
        logPath: String,
        table: String,
        counts: [UInt64: Int]
    ) throws {
        guard !counts.isEmpty else { return }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let sql = "INSERT INTO \(table)(log_path, offset, count) VALUES (?1, ?2, ?3);"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError(db, context: "prepare insertOffsetHits")
        }
        for (offset, count) in counts {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            sqlite3_bind_text(statement, 1, logPath, -1, sqliteTransient)
            sqlite3_bind_int64(statement, 2, Int64(offset))
            sqlite3_bind_int(statement, 3, Int32(count))
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw databaseError(db, context: "insertOffsetHits step")
            }
        }
    }

    private static func insertTrapHits(
        db: OpaquePointer,
        logPath: String,
        counts: [UInt16: Int]
    ) throws {
        guard !counts.isEmpty else { return }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let sql = "INSERT INTO trap_hit(log_path, trap, count) VALUES (?1, ?2, ?3);"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError(db, context: "prepare insertTrapHits")
        }
        for (trap, count) in counts {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            sqlite3_bind_text(statement, 1, logPath, -1, sqliteTransient)
            sqlite3_bind_int(statement, 2, Int32(trap))
            sqlite3_bind_int(statement, 3, Int32(count))
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw databaseError(db, context: "insertTrapHits step")
            }
        }
    }

    private static func exec(_ db: OpaquePointer, _ sql: String, _ bindings: Any...) throws {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw databaseError(db, context: "prepare exec")
        }
        for (index, binding) in bindings.enumerated() {
            let parameter = Int32(index + 1)
            switch binding {
            case let value as String:
                sqlite3_bind_text(statement, parameter, value, -1, sqliteTransient)
            case let value as Int64:
                sqlite3_bind_int64(statement, parameter, value)
            case let value as Int:
                sqlite3_bind_int64(statement, parameter, Int64(value))
            case let value as Double:
                sqlite3_bind_double(statement, parameter, value)
            case let value as Bool:
                sqlite3_bind_int(statement, parameter, value ? 1 : 0)
            default:
                throw MillLogCacheError.unsupportedBinding
            }
        }
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_DONE:
                return
            case SQLITE_ROW:
                continue
            default:
                throw databaseError(db, context: "exec step")
            }
        }
    }

    private static func databaseError(_ db: OpaquePointer, context: String) -> MillLogCacheError {
        MillLogCacheError.sqlite(context: context, message: String(cString: sqlite3_errmsg(db)))
    }
}

private extension SHA256.Digest {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

public enum MillLogCacheError: Error, LocalizedError {
    case openFailed(String)
    case notOpen
    case unsupportedBinding
    case sqlite(context: String, message: String)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let message):
            return "Could not open mill log cache: \(message)"
        case .notOpen:
            return "Mill log cache is not open."
        case .unsupportedBinding:
            return "Unsupported SQLite binding type."
        case .sqlite(let context, let message):
            return "Mill log cache \(context): \(message)"
        }
    }
}
