import Foundation

public enum MillAnnotationExport {
    public static let formatID = "NewWorldView-mill-annotations"
    public static let formatVersion = 1

    public struct Document: Codable, Sendable, Equatable {
        public var format: String
        public var version: Int
        public var romKey: String
        public var exportedAt: Date
        public var entries: [Entry]
        public var tokenUsage: MillTokenUsage?

        public init(
            romKey: String,
            exportedAt: Date = Date(),
            entries: [Entry],
            tokenUsage: MillTokenUsage? = nil
        ) {
            self.format = formatID
            self.version = formatVersion
            self.romKey = romKey
            self.exportedAt = exportedAt
            self.entries = entries
            self.tokenUsage = tokenUsage
        }
    }

    public struct Entry: Codable, Sendable, Equatable, Identifiable {
        public var id: UUID
        public var address: String
        public var romOffset: String?
        public var action: String
        public var kind: String
        public var symbol: String?
        public var evidence: [String]
        public var reasoning: String
        public var approvedAt: Date
        public var tokenUsage: MillTokenUsage?

        public init(annotation: MillAnnotation) {
            id = annotation.id
            address = annotation.address.display
            if let offset = annotation.contextSnapshot.romOffset {
                romOffset = String(format: "0x%X", offset)
            } else {
                romOffset = nil
            }
            action = annotation.classification.recommendedAction.rawValue
            kind = annotation.classification.kind.rawValue
            symbol = annotation.classification.suggestedSymbolName ?? annotation.contextSnapshot.symbolName
            evidence = annotation.classification.evidenceUsed
            reasoning = annotation.classification.reasoning
            approvedAt = annotation.reviewedAt ?? annotation.createdAt
            tokenUsage = annotation.source == .appleFM ? annotation.tokenUsage : nil
        }
    }

    public static func document(
        romKey: String,
        annotations: [MillAnnotation]
    ) -> Document {
        let approved = annotations.filter { $0.status == .approved }
        let summed = approved.compactMap(\.tokenUsage).reduce(MillTokenUsage.zero, +)
        let aggregate = summed.totalTokens > 0 ? summed : nil
        return Document(
            romKey: romKey,
            entries: approved.map(Entry.init),
            tokenUsage: aggregate
        )
    }

    public static func write(
        romKey: String,
        annotations: [MillAnnotation],
        to directory: URL
    ) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let payload = document(romKey: romKey, annotations: annotations)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let url = directory.appendingPathComponent("mill-annotations.json")
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
