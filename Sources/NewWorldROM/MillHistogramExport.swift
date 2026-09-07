import Foundation

public enum MillHistogramExport {
    public static let formatID = "NewWorldView-mill-histogram"
    public static let formatVersion = 1

    public struct Document: Codable, Sendable, Equatable {
        public var format: String
        public var version: Int
        public var romKey: String
        public var exportedAt: Date
        public var scannedLogs: Int
        public var discoveredLogs: Int
        public var histogramLimit: Int
        public var entries: [Entry]
        public var tokenUsage: MillTokenUsage?

        public init(
            romKey: String,
            report: MillResearchEngine.HistoricalReport,
            exportedAt: Date = Date(),
            entries: [Entry],
            tokenUsage: MillTokenUsage? = nil
        ) {
            format = formatID
            version = formatVersion
            self.romKey = romKey
            self.exportedAt = exportedAt
            scannedLogs = report.scannedLogs
            discoveredLogs = report.discoveredLogs
            histogramLimit = report.histogramLimit
            self.entries = entries
            self.tokenUsage = tokenUsage
        }
    }

    public struct Entry: Codable, Sendable, Equatable, Identifiable {
        public var id: String { romOffset }
        public var romOffset: String
        public var count: Int
        public var space: String
        public var tags: [String]
        public var symbol: String?
        public var recommendation: String?
        public var annotationAction: String?
        public var annotationStatus: String?
        public var annotationKind: String?
        public var tokenUsage: MillTokenUsage?

        public init(
            histogramEntry: MillResearchEngine.OffsetHistogramEntry,
            annotation: MillAnnotation? = nil
        ) {
            romOffset = String(format: "0x%X", histogramEntry.offset)
            count = histogramEntry.count
            space = histogramEntry.space.rawValue
            tags = histogramEntry.tags
            symbol = histogramEntry.symbolName
            recommendation = histogramEntry.recommendation
            if let annotation {
                annotationAction = annotation.classification.recommendedAction.rawValue
                annotationStatus = annotation.status.rawValue
                annotationKind = annotation.classification.kind.rawValue
                tokenUsage = annotation.source == .appleFM ? annotation.tokenUsage : nil
            } else {
                annotationAction = nil
                annotationStatus = nil
                annotationKind = nil
                tokenUsage = nil
            }
        }
    }

    public static func document(
        romKey: String,
        report: MillResearchEngine.HistoricalReport,
        annotations: [MillAnnotation] = []
    ) -> Document {
        let byAddress = Dictionary(uniqueKeysWithValues: annotations.map { ($0.address.key, $0) })
        let entries = report.top68kOffsets.map { entry in
            let address = AddressTranslation.virtualAddress(fromRomOffset: entry.offset, space: entry.space)
            return Entry(histogramEntry: entry, annotation: byAddress[address.key])
        }
        let tokenUsage = annotations
            .filter { $0.source == .appleFM }
            .compactMap(\.tokenUsage)
            .reduce(MillTokenUsage.zero, +)
        let aggregate = tokenUsage.totalTokens > 0 ? tokenUsage : nil
        return Document(romKey: romKey, report: report, entries: entries, tokenUsage: aggregate)
    }

    public static func write(
        romKey: String,
        report: MillResearchEngine.HistoricalReport,
        annotations: [MillAnnotation] = [],
        to directory: URL
    ) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let payload = document(romKey: romKey, report: report, annotations: annotations)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let url = directory.appendingPathComponent("mill-histogram.json")
        try encoder.encode(payload).write(to: url)
        return url
    }

    public static func load(from url: URL) throws -> Document {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Document.self, from: data)
    }
}
