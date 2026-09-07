import Combine
import Foundation
import NewWorldROM

@MainActor
final class MillResearchSettings: ObservableObject {
    static let storageKey = "NewWorldView.millResearchSettings"
    static let defaultScanLimit = MillResearchEngine.defaultScanLimit
    static let defaultBatchTriageCount = 20
    static let defaultFMConfidenceThreshold = MillSafetyVerifier.defaultConfidenceThreshold
    static let defaultHistogramLimit = 500
    static let defaultKeepLogsOnly = true
    static let minScanLimit = 0
    static let maxScanLimit = 10_000
    static let maxHistogramLimit = 50_000
    static let scanLimitOptions = [50, 100, 200, 500, 1000, 0]
    static let histogramLimitOptions = [40, 100, 500, 1000, 0]

    private static let macemuBookmarkDefaultsKey = "NewWorldView.macemuRepoBookmark"

    @Published var logScanLimit: Int {
        didSet { normalizeAndSave(.logScanLimit) }
    }

    @Published var histogramLimit: Int {
        didSet { normalizeAndSave(.histogramLimit) }
    }

    @Published var batchTriageCount: Int {
        didSet { normalizeAndSave(.batchTriageCount) }
    }

    @Published var keepLogsOnly: Bool {
        didSet { normalizeAndSave(.keepLogsOnly) }
    }

    @Published var fmConfidenceThreshold: Double {
        didSet { normalizeAndSave(.fmConfidenceThreshold) }
    }

    @Published var macemuRepoPath: String {
        didSet {
            UserDefaults.standard.set(macemuRepoPath, forKey: "NewWorldView.macemuRepoPath")
        }
    }

    @Published var grokPath: String {
        didSet {
            UserDefaults.standard.set(grokPath, forKey: "NewWorldView.grokPath")
        }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(StoredSettings.self, from: data) {
            logScanLimit = Self.normalizeScanLimit(decoded.logScanLimit)
            histogramLimit = Self.normalizeHistogramLimit(decoded.histogramLimit ?? Self.defaultHistogramLimit)
            keepLogsOnly = decoded.keepLogsOnly ?? Self.defaultKeepLogsOnly
            batchTriageCount = Self.normalizeBatchCount(decoded.batchTriageCount)
            fmConfidenceThreshold = Self.normalizeThreshold(decoded.fmConfidenceThreshold)
        } else {
            logScanLimit = Self.defaultScanLimit
            histogramLimit = Self.defaultHistogramLimit
            keepLogsOnly = Self.defaultKeepLogsOnly
            batchTriageCount = Self.defaultBatchTriageCount
            fmConfidenceThreshold = Self.defaultFMConfidenceThreshold
        }
        macemuRepoPath = UserDefaults.standard.string(forKey: "NewWorldView.macemuRepoPath") ?? ""
        grokPath = UserDefaults.standard.string(forKey: "NewWorldView.grokPath") ?? ""
    }

    var effectiveScanLimit: Int {
        logScanLimit
    }

    var hasMacemuRepoAccess: Bool {
        UserDefaults.standard.data(forKey: Self.macemuBookmarkDefaultsKey) != nil
    }

    static func label(for limit: Int) -> String {
        limit == 0 ? "Unlimited" : "\(limit)"
    }

    var effectiveHistogramLimit: Int {
        histogramLimit
    }

    static func histogramLabel(for limit: Int) -> String {
        limit == 0 ? "Unlimited" : "\(limit)"
    }

    func resetToDefaults() {
        logScanLimit = Self.defaultScanLimit
        histogramLimit = Self.defaultHistogramLimit
        keepLogsOnly = Self.defaultKeepLogsOnly
        batchTriageCount = Self.defaultBatchTriageCount
        fmConfidenceThreshold = Self.defaultFMConfidenceThreshold
    }

    func setMacemuRepo(_ url: URL) {
        macemuRepoPath = url.path
        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: Self.macemuBookmarkDefaultsKey)
        } catch {
            // Best-effort; path still saved.
        }
    }

    func resolveMacemuRepoURL() throws -> URL? {
        guard let bookmarkData = UserDefaults.standard.data(forKey: Self.macemuBookmarkDefaultsKey) else {
            if macemuRepoPath.isEmpty { return nil }
            return URL(fileURLWithPath: macemuRepoPath)
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
            UserDefaults.standard.set(refreshed, forKey: Self.macemuBookmarkDefaultsKey)
        }
        macemuRepoPath = url.path
        return url
    }

    func resolvedGrokPath() -> String? {
        GrokBuildRunner.resolveGrokPath(customPath: grokPath.isEmpty ? nil : grokPath)
    }

    private struct StoredSettings: Codable {
        var logScanLimit: Int
        var histogramLimit: Int
        var keepLogsOnly: Bool?
        var batchTriageCount: Int
        var fmConfidenceThreshold: Double
    }

    private enum Field {
        case logScanLimit
        case histogramLimit
        case keepLogsOnly
        case batchTriageCount
        case fmConfidenceThreshold
    }

    private func normalizeAndSave(_ field: Field) {
        switch field {
        case .logScanLimit:
            let normalized = Self.normalizeScanLimit(logScanLimit)
            if normalized != logScanLimit {
                logScanLimit = normalized
                return
            }
        case .histogramLimit:
            let normalized = Self.normalizeHistogramLimit(histogramLimit)
            if normalized != histogramLimit {
                histogramLimit = normalized
                return
            }
        case .keepLogsOnly:
            break
        case .batchTriageCount:
            let normalized = Self.normalizeBatchCount(batchTriageCount)
            if normalized != batchTriageCount {
                batchTriageCount = normalized
                return
            }
        case .fmConfidenceThreshold:
            let normalized = Self.normalizeThreshold(fmConfidenceThreshold)
            if normalized != fmConfidenceThreshold {
                fmConfidenceThreshold = normalized
                return
            }
        }
        save()
    }

    private func save() {
        let payload = StoredSettings(
            logScanLimit: logScanLimit,
            histogramLimit: histogramLimit,
            keepLogsOnly: keepLogsOnly,
            batchTriageCount: batchTriageCount,
            fmConfidenceThreshold: fmConfidenceThreshold
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private static func normalizeScanLimit(_ value: Int) -> Int {
        if value == 0 { return 0 }
        if scanLimitOptions.contains(value) { return value }
        return min(max(value, 1), maxScanLimit)
    }

    private static func normalizeHistogramLimit(_ value: Int) -> Int {
        if value == 0 { return 0 }
        if histogramLimitOptions.contains(value) { return value }
        return min(max(value, 1), maxHistogramLimit)
    }

    private static func normalizeBatchCount(_ value: Int) -> Int {
        min(max(value, 1), 100)
    }

    private static func normalizeThreshold(_ value: Double) -> Double {
        min(max(value, 0.1), 1.0)
    }
}
