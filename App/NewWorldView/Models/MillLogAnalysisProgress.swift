import Foundation

struct MillLogAnalysisProgress: Equatable {
    var completed: Int
    var total: Int
    var currentFileName: String?
    var startedAt: Date?

    static let zero = MillLogAnalysisProgress(completed: 0, total: 0, currentFileName: nil, startedAt: nil)

    var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    var statusText: String {
        guard total > 0 else { return "Preparing log scan…" }
        return "Scanning log \(completed) of \(total)"
    }

    func statistics(at now: Date = Date()) -> MillLogAnalysisStatistics {
        guard let startedAt else {
            return MillLogAnalysisStatistics(
                elapsed: 0,
                estimatedRemaining: nil,
                logsPerSecond: nil
            )
        }

        let elapsed = max(0, now.timeIntervalSince(startedAt))
        let remaining: TimeInterval?
        let rate: Double?

        if completed > 0, total > completed, elapsed > 0 {
            let logsPerSecond = Double(completed) / elapsed
            rate = logsPerSecond
            remaining = Double(total - completed) / logsPerSecond
        } else {
            rate = nil
            remaining = nil
        }

        return MillLogAnalysisStatistics(
            elapsed: elapsed,
            estimatedRemaining: remaining,
            logsPerSecond: rate
        )
    }
}

struct MillLogAnalysisStatistics: Equatable {
    var elapsed: TimeInterval
    var estimatedRemaining: TimeInterval?
    var logsPerSecond: Double?

    var elapsedText: String {
        Self.formatDuration(elapsed)
    }

    var remainingText: String {
        guard let estimatedRemaining else { return "Estimating…" }
        return "~\(Self.formatDuration(estimatedRemaining))"
    }

    var rateText: String {
        guard let logsPerSecond else { return "—" }
        if logsPerSecond >= 10 {
            return String(format: "%.0f logs/s", logsPerSecond)
        }
        return String(format: "%.1f logs/s", logsPerSecond)
    }

    private static func formatDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        }
        if minutes > 0 {
            return String(format: "%dm %ds", minutes, seconds)
        }
        return String(format: "%ds", seconds)
    }
}

final class MillLogAnalysisSession: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    func isCancelled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}
