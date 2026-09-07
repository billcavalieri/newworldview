import Foundation

public enum ROMBinaryExport {
    public struct RegionExport: Sendable, Equatable, Codable {
        public var name: String
        public var nodeID: String
        public var loadAddress: String
        public var space: String
        public var size: Int
        public var fileName: String
    }

    public struct Manifest: Sendable, Equatable, Codable {
        public var format: String
        public var version: Int
        public var sourceFile: String
        public var macROMSize: Int
        public var decodeSource: String
        public var newWorldOK: Bool
        public var regions: [RegionExport]
    }

    public static let manifestFormat = "NewWorldView-rom-export"
    public static let manifestVersion = 1

    public static func writeMacROM(
        rawData: Data,
        parsed: ParsedROM,
        to directory: URL
    ) throws -> Manifest {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let decoded = try MacROMImageDecoder.decode(rawData)
        let macROMURL = directory.appendingPathComponent("MacROM.bin")
        try decoded.image.write(to: macROMURL)

        var regions: [RegionExport] = []
        let regionsDir = directory.appendingPathComponent("regions", isDirectory: true)
        try FileManager.default.createDirectory(at: regionsDir, withIntermediateDirectories: true)

        for node in parsed.root.descendants where node.children.isEmpty && node.kind.isa != nil {
            guard let isa = node.kind.isa else { continue }
            let space = AnalysisEngine.space(for: node, isa: isa)
            let base = AnalysisEngine.baseAddress(for: node, space: space)
            let safeName = node.name.replacingOccurrences(of: "/", with: "_")
            let fileName = "\(safeName).bin"
            try node.data.write(to: regionsDir.appendingPathComponent(fileName))
            regions.append(
                RegionExport(
                    name: node.name,
                    nodeID: node.id,
                    loadAddress: String(format: "0x%08X", base),
                    space: space.rawValue,
                    size: node.data.count,
                    fileName: "regions/\(fileName)"
                )
            )
        }

        let manifest = Manifest(
            format: manifestFormat,
            version: manifestVersion,
            sourceFile: parsed.fileName,
            macROMSize: decoded.image.count,
            decodeSource: decoded.source,
            newWorldOK: decoded.newWorldOK,
            regions: regions.sorted { $0.loadAddress < $1.loadAddress }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: directory.appendingPathComponent("rom-export.json"))
        return manifest
    }
}
