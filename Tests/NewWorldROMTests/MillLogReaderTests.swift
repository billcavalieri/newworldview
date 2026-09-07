import Foundation
import NewWorldROM
import Testing
import zlib

struct MillLogReaderTests {
    @Test func discoversGzipMillLogs() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nw-gzip-logs-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let gzURL = directory.appendingPathComponent("ss-g3-mill-6613.log.gz")
        try writeGzip("KEEP 68k hang pc=50366084\nmill=6613\n", to: gzURL)

        #expect(MillLogReader.isMillLogFile(gzURL))
        #expect(MillLogReader.millNumber(from: gzURL) == 6613)
        #expect(MillLogReader.displayFileName(for: gzURL) == "ss-g3-mill-6613.log")

        let ordered = try MillLogDiscovery.orderedLogURLs(
            options: MillLogDiscovery.Options(
                directory: directory,
                tmpDirectory: directory,
                keepLogsOnly: false
            )
        )
        #expect(ordered.count == 1)
        #expect(ordered[0].lastPathComponent == "ss-g3-mill-6613.log.gz")
    }

    @Test func parsesGzipAggregatesMatchRaw() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nw-gzip-parse-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let payload = "KEEP 68k hang pc=50366084\nG3: 68k map r24=5005c86c op=a97c\n"
        let rawURL = directory.appendingPathComponent("ss-g3-mill-6613.log")
        let gzURL = directory.appendingPathComponent("ss-g3-mill-6613.log.gz")
        try payload.write(to: rawURL, atomically: true, encoding: .utf8)
        try writeGzip(payload, to: gzURL)

        let rawAggregates = try MillLogParser.accumulateAggregates(from: rawURL)
        let gzAggregates = try MillLogParser.accumulateAggregates(from: gzURL)
        #expect(gzAggregates == rawAggregates)
        #expect(gzAggregates.fileName == "ss-g3-mill-6613.log")
        let tail = try MillLogReader.readTail(of: gzURL, maxBytes: 8192)
        #expect(tail.range(of: Data("KEEP 68k hang".utf8)) != nil)
    }

    @Test func remapsKeepLogToGzipSibling() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nw-gzip-keep-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let gzURL = directory.appendingPathComponent("ss-g3-mill-8518.log.gz")
        try writeGzip("KEEP 68k hang pc=50366084\n", to: gzURL)
        let stateDir = directory.appendingPathComponent("g3_driver", isDirectory: true)
        try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        let state = stateDir.appendingPathComponent("state.json")
        try #"{"mill":{"keep_log":"/tmp/ss-g3-mill-8518.log"}}"#.write(to: state, atomically: true, encoding: .utf8)

        let keepLog = try #require(MillLogDiscovery.keepLogFromState(state, preferredDirectory: directory))
        #expect(keepLog.path == gzURL.path)
    }

    private func writeGzip(_ text: String, to url: URL) throws {
        guard let handle = gzopen(url.path, "wb") else {
            Issue.record("Could not open gzip writer for \(url.path)")
            return
        }
        defer { gzclose(handle) }
        let data = Data(text.utf8)
        data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            let written = gzwrite(handle, base.assumingMemoryBound(to: UInt8.self), UInt32(data.count))
            if written != Int32(data.count) {
                Issue.record("Incomplete gzip write for \(url.path)")
            }
        }
    }
}
