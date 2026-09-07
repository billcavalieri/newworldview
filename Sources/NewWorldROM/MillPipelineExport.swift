import Foundation

public enum MillPipelineExport {
    public static let manifestFormatID = "NewWorldView-mill-pipeline"
    public static let manifestVersion = 1

    public struct Manifest: Codable, Sendable, Equatable {
        public var format: String
        public var version: Int
        public var romKey: String
        public var exportedAt: Date
        public var scannedLogs: Int
        public var histogramEntries: Int
        public var approvedAnnotations: Int
        public var files: [String]
        public var tokenUsage: MillTokenUsage?

        public init(
            romKey: String,
            exportedAt: Date = Date(),
            scannedLogs: Int,
            histogramEntries: Int,
            approvedAnnotations: Int,
            files: [String],
            tokenUsage: MillTokenUsage? = nil
        ) {
            format = manifestFormatID
            version = manifestVersion
            self.romKey = romKey
            self.exportedAt = exportedAt
            self.scannedLogs = scannedLogs
            self.histogramEntries = histogramEntries
            self.approvedAnnotations = approvedAnnotations
            self.files = files
            self.tokenUsage = tokenUsage
        }
    }

    public struct Result: Sendable, Equatable {
        public var directory: URL
        public var histogramURL: URL
        public var annotationsURL: URL
        public var manifestURL: URL
        public var researchReportURL: URL
    }

    @discardableResult
    public static func write(
        romKey: String,
        report: MillResearchEngine.HistoricalReport,
        annotations: [MillAnnotation],
        to directory: URL
    ) throws -> Result {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let histogramURL = try MillHistogramExport.write(
            romKey: romKey,
            report: report,
            annotations: annotations,
            to: directory
        )
        let annotationsURL = try MillAnnotationExport.write(
            romKey: romKey,
            annotations: annotations,
            to: directory
        )
        let researchReportURL = directory.appendingPathComponent("mill-research-report.json")
        let researchPayload = MillResearchReportExport(report: report)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(researchPayload).write(to: researchReportURL)

        let tokenUsage = annotations
            .filter { $0.source == .appleFM }
            .compactMap(\.tokenUsage)
            .reduce(MillTokenUsage.zero, +)
        let aggregate = tokenUsage.totalTokens > 0 ? tokenUsage : nil
        let manifest = Manifest(
            romKey: romKey,
            scannedLogs: report.scannedLogs,
            histogramEntries: report.top68kOffsets.count,
            approvedAnnotations: annotations.filter { $0.status == .approved }.count,
            files: [
                histogramURL.lastPathComponent,
                annotationsURL.lastPathComponent,
                researchReportURL.lastPathComponent,
                "mill-pipeline.json"
            ],
            tokenUsage: aggregate
        )
        let manifestURL = directory.appendingPathComponent("mill-pipeline.json")
        try encoder.encode(manifest).write(to: manifestURL)

        return Result(
            directory: directory,
            histogramURL: histogramURL,
            annotationsURL: annotationsURL,
            manifestURL: manifestURL,
            researchReportURL: researchReportURL
        )
    }
}

public struct MillResearchReportExport: Codable, Sendable {
    public var discoveredLogs: Int
    public var scannedLogs: Int
    public var logScanLimit: Int
    public var histogramLimit: Int
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
    public var top68kOffsets: [MillHistogramExport.Entry]
    public var topPPCOffsets: [OffsetSummary]
    public var trapObservations: [TrapSummary]
    public var logSummaries: [LogSummary]

    public struct OffsetSummary: Codable, Sendable {
        public var offset: String
        public var count: Int
        public var tags: [String]
        public var recommendation: String?
    }

    public struct TrapSummary: Codable, Sendable {
        public var trap: String
        public var name: String
        public var count: Int
        public var noSkipProtected: Bool
    }

    public struct LogSummary: Codable, Sendable {
        public var fileName: String
        public var classification: String
        public var millMax: Int
        public var reached68k: Bool
    }

    public init(report: MillResearchEngine.HistoricalReport, annotations: [MillAnnotation] = []) {
        discoveredLogs = report.discoveredLogs
        scannedLogs = report.scannedLogs
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
        top68kOffsets = report.top68kOffsets.map { MillHistogramExport.Entry(histogramEntry: $0) }
        topPPCOffsets = report.topPPCOffsets.map {
            OffsetSummary(
                offset: String(format: "0x%X", $0.offset),
                count: $0.count,
                tags: $0.tags,
                recommendation: $0.recommendation
            )
        }
        trapObservations = report.trapObservations.map {
            TrapSummary(
                trap: String(format: "0x%X", $0.trap),
                name: $0.name,
                count: $0.count,
                noSkipProtected: $0.noSkipProtected
            )
        }
        logSummaries = report.logSummaries.map {
            LogSummary(
                fileName: $0.fileName,
                classification: $0.classification,
                millMax: $0.millMax,
                reached68k: $0.reached68k
            )
        }
        _ = annotations
    }
}
