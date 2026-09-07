import Foundation
import NewWorldROM

struct MillReportExport: Codable {
    var discoveredLogs: Int
    var scannedLogs: Int
    var totalAvailableLogs: Int
    var keepLogsOnly: Bool
    var logScanLimit: Int
    var histogramLimit: Int
    var skipRecommendations: [String]
    var getNewDialogStubHits: Int
    var heartbeatClusterHits: Int
    var code66LogsWithStay: Int
    var code66HelperSnaps: Int
    var loadSeg66Logs: Int
    var launchA9F2Logs: Int
    var launchA9F2Count: Int
    var pefEnterCount: Int
    var pefImportCount: Int
    var pefWaitNextEventCount: Int
    var pefDceCount: Int
    var pefVolCount: Int
    var pefHostedDSICount: Int
    var pefHostedLocationSamples: [String]
    var getNewDialogOverlayHits: Int
    var getNewDialogSplashHits: Int
    var xlateMissNersCount: Int
    var top68kOffsets: [OffsetEntry]
    var topPPCOffsets: [OffsetEntry]
    var logSummaries: [LogEntry]

    struct OffsetEntry: Codable {
        var offset: String
        var count: Int
        var tags: [String]
        var recommendation: String?
    }

    struct LogEntry: Codable {
        var fileName: String
        var classification: String
        var millMax: Int
        var reached68k: Bool
    }

    init(report: MillResearchEngine.HistoricalReport) {
        discoveredLogs = report.discoveredLogs
        scannedLogs = report.scannedLogs
        totalAvailableLogs = report.totalAvailableLogs
        keepLogsOnly = report.keepLogsOnly
        logScanLimit = report.logScanLimit
        histogramLimit = report.histogramLimit
        skipRecommendations = report.skipRecommendations
        getNewDialogStubHits = report.getNewDialogStubHits
        heartbeatClusterHits = report.heartbeatClusterHits
        code66LogsWithStay = report.code66LogsWithStay
        code66HelperSnaps = report.code66HelperSnaps
        loadSeg66Logs = report.loadSeg66Logs
        launchA9F2Logs = report.launchA9F2Logs
        launchA9F2Count = report.launchA9F2Count
        pefEnterCount = report.pefEnterCount
        pefImportCount = report.pefImportCount
        pefWaitNextEventCount = report.pefWaitNextEventCount
        pefDceCount = report.pefDceCount
        pefVolCount = report.pefVolCount
        pefHostedDSICount = report.pefHostedDSICount
        pefHostedLocationSamples = report.pefHostedLocationSamples
        getNewDialogOverlayHits = report.getNewDialogOverlayHits
        getNewDialogSplashHits = report.getNewDialogSplashHits
        xlateMissNersCount = report.xlateMissNersCount
        top68kOffsets = report.top68kOffsets.map {
            OffsetEntry(
                offset: String(format: "0x%X", $0.offset),
                count: $0.count,
                tags: $0.tags,
                recommendation: $0.recommendation
            )
        }
        topPPCOffsets = report.topPPCOffsets.map {
            OffsetEntry(
                offset: String(format: "0x%X", $0.offset),
                count: $0.count,
                tags: $0.tags,
                recommendation: $0.recommendation
            )
        }
        logSummaries = report.logSummaries.map {
            LogEntry(
                fileName: $0.fileName,
                classification: $0.classification,
                millMax: $0.millMax,
                reached68k: $0.reached68k
            )
        }
    }
}
