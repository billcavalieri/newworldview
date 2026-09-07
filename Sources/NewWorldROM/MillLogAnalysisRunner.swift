import Foundation

enum MillLogAnalysisRunner {
    private static let keepMarker1 = Data("KEEP 68k hang".utf8)
    private static let keepMarker2 = Data("pc=50366084".utf8)
    private static let keepTailReadSize = 8192
    private static let progressStride = 16

    static func tailContainsKeepMarkers(_ url: URL) -> Bool {
        guard let data = try? MillLogReader.readTail(of: url, maxBytes: keepTailReadSize), !data.isEmpty else {
            return false
        }
        return data.range(of: keepMarker1) != nil || data.range(of: keepMarker2) != nil
    }

    static func filterKeepLogs(
        _ urls: [URL],
        keepLog: URL?,
        pinnedMillNumbers: [Int],
        options: MillLogDiscovery.Options
    ) -> [URL] {
        guard !urls.isEmpty else { return urls }
        let keepLogPath = keepLog?.standardizedFileURL.path
        let pinned = Set(pinnedMillNumbers)
        var keep = [Bool](repeating: false, count: urls.count)

        let filterOne: (Int) -> Void = { index in
            let url = urls[index]
            if let keepLogPath, url.standardizedFileURL.path == keepLogPath {
                keep[index] = true
                return
            }
            if let mill = MillLogDiscovery.millNumber(from: url), pinned.contains(mill) {
                keep[index] = true
                return
            }
            guard MillLogDiscovery.resolvedLogURL(url, options: options) != nil else { return }
            keep[index] = tailContainsKeepMarkers(url)
        }

        if urls.count >= 64 {
            DispatchQueue.concurrentPerform(iterations: urls.count, execute: filterOne)
        } else {
            for index in urls.indices {
                filterOne(index)
            }
        }

        return urls.enumerated().compactMap { keep[$0.offset] ? $0.element : nil }
    }

    static func analyzeLogs(
        _ logs: [URL],
        progress: MillResearchEngine.MillLogAnalysisProgressHandler?,
        isCancelled: MillResearchEngine.MillLogAnalysisCancellationHandler?
    ) throws -> [MillLogParser.LogAggregates] {
        guard !logs.isEmpty else { return [] }

        progress?(0, logs.count, nil)

        if logs.count < 32 {
            return try analyzeLogsSequentially(logs, progress: progress, isCancelled: isCancelled)
        }

        var results = [MillLogParser.LogAggregates?](repeating: nil, count: logs.count)
        var firstError: Error?
        var completed = 0
        let lock = NSLock()

        let analyzeOne: (Int) -> Void = { index in
            if firstError != nil || isCancelled?() == true {
                return
            }
            do {
                let aggregates = try MillLogParser.accumulateAggregates(from: logs[index])
                lock.lock()
                if firstError == nil {
                    results[index] = aggregates
                    completed += 1
                    let done = completed
                    let fileName = logs[index].lastPathComponent
                    lock.unlock()
                    reportProgress(done: done, total: logs.count, fileName: fileName, progress: progress)
                } else {
                    lock.unlock()
                }
            } catch {
                lock.lock()
                if firstError == nil {
                    firstError = error
                }
                lock.unlock()
            }
        }

        DispatchQueue.concurrentPerform(iterations: logs.count, execute: analyzeOne)

        if isCancelled?() == true {
            throw CancellationError()
        }
        if let firstError {
            throw firstError
        }

        return results.compactMap { $0 }
    }

    private static func analyzeLogsSequentially(
        _ logs: [URL],
        progress: MillResearchEngine.MillLogAnalysisProgressHandler?,
        isCancelled: MillResearchEngine.MillLogAnalysisCancellationHandler?
    ) throws -> [MillLogParser.LogAggregates] {
        var results: [MillLogParser.LogAggregates] = []
        results.reserveCapacity(logs.count)

        for (index, url) in logs.enumerated() {
            if isCancelled?() == true {
                throw CancellationError()
            }
            let aggregates = try MillLogParser.accumulateAggregates(from: url)
            results.append(aggregates)
            reportProgress(done: index + 1, total: logs.count, fileName: url.lastPathComponent, progress: progress)
        }

        return results
    }

    private static func reportProgress(
        done: Int,
        total: Int,
        fileName: String,
        progress: MillResearchEngine.MillLogAnalysisProgressHandler?
    ) {
        guard done == 0 || done == total || done % progressStride == 0 else { return }
        progress?(done, total, fileName)
    }
}
