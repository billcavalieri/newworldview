import Foundation

enum PEFParser {
    static let magic = Data("Joy!peff".utf8)
    private static let containerHeaderSize = 40
    private static let sectionHeaderSize = 28

    private static let regionNames = [
        0: "Code",
        1: "UnpackedData",
        2: "PatternData",
        3: "Constant",
        4: "Loader",
        5: "Debug",
        6: "ExecutableData",
        8: "Exception",
        9: "Traceback"
    ]

    static func parse(
        _ data: Data,
        name: String,
        id: String,
        containerOffset: Int?
    ) throws -> ROMNode {
        guard data.starts(with: magic) else { throw ROMParseError.unrecognizedFormat }
        let pef = try unpack(data)
        var children: [ROMNode] = []

        for (index, section) in pef.sections.enumerated() {
            let kindName = regionNames[section.kind] ?? "Section\(section.kind)"
            let sectionName = "\(index)-\(kindName)"
            let displayData: Data
            if section.kind == 2 {
                displayData = (try? pidata(section.raw)) ?? section.raw
            } else {
                displayData = section.raw
            }

            let kind: ROMContentKind
            if section.kind == 0 {
                kind = .disassemblable(.powerPC)
            } else {
                kind = ROMDispatcher.inferredKind(displayData)
            }

            children.append(
                ROMNode.leaf(
                    id: id + "/" + sectionName,
                    name: sectionName,
                    data: displayData,
                    kind: kind,
                    containerOffset: (containerOffset ?? 0) + section.containerOffset,
                    runtimeAddress: UInt64(section.address),
                    metadata: [
                        "regionKind": String(section.kind),
                        "execSize": String(section.execSize),
                        "rawSize": String(section.raw.count),
                        "addressSpace": section.kind == 0 ? AddressSpace.pef.rawValue : AddressSpace.unknown.rawValue
                    ]
                )
            )
        }

        let suggested = suggestName(data)
        let summary = """
        PEF container
        Architecture: \(pef.architecture)
        Sections: \(pef.sections.count)
        \(suggested.map { "Driver: \($0)" } ?? "")
        """

        return ROMNode(
            id: id,
            name: name,
            kind: .folder,
            data: data,
            text: summary,
            containerOffset: containerOffset,
            children: children,
            metadata: [
                "architecture": pef.architecture,
                "sectionCount": String(pef.sections.count)
            ]
        )
    }

    static func suggestName(_ data: Data) -> String? {
        guard data.starts(with: magic) else { return nil }
        guard let pef = try? unpack(data) else { return nil }
        for section in pef.sections {
            var blob = section.raw
            if section.kind == 2 {
                blob = (try? pidata(blob)) ?? blob
            }
            guard section.kind == 1 || section.kind == 2, !blob.isEmpty else { continue }
            guard let hdr = blob.range(of: Data("mtej".utf8)) else { continue }
            let offset = hdr.location
            guard offset + 44 <= blob.count else { continue }
            let devnam = try? BinaryCursor.slice(blob, offset: offset + 8, count: 32, context: "ndrv name")
            let version = (try? BinaryCursor.u32be(blob, offset + 40)) ?? 0
            guard let devnam else { continue }
            let name = pstringOrCString(devnam)
            if name.isEmpty { continue }
            return "\(name)-\(parseVersion(version))"
        }
        return nil
    }

    private struct PEFSection {
        var kind: Int
        var address: UInt32
        var execSize: Int
        var containerOffset: Int
        var raw: Data
    }

    private struct PEFFile {
        var architecture: String
        var sections: [PEFSection]
    }

    private static func unpack(_ data: Data) throws -> PEFFile {
        let architecture = try BinaryCursor.fourCC(data, 8)
        let sectionCount = Int(try BinaryCursor.u16be(data, 32, context: "pef.sec_count"))
        var sections: [PEFSection] = []
        for index in 0..<sectionCount {
            let header = containerHeaderSize + sectionHeaderSize * index
            let address = try BinaryCursor.u32be(data, header + 4)
            let execSize = Int(try BinaryCursor.u32be(data, header + 8))
            let rawSize = Int(try BinaryCursor.u32be(data, header + 16))
            let containerOffset = Int(try BinaryCursor.u32be(data, header + 20))
            let kind = Int(try BinaryCursor.u8(data, header + 24))
            let raw = try BinaryCursor.slice(data, offset: containerOffset, count: rawSize, context: "pef section \(index)")
            sections.append(
                PEFSection(
                    kind: kind,
                    address: address,
                    execSize: execSize,
                    containerOffset: containerOffset,
                    raw: raw
                )
            )
        }
        return PEFFile(architecture: architecture, sections: sections)
    }

    static func pidata(_ packed: Data) throws -> Data {
        var iterator = packed.makeIterator()
        var unpacked = Data()

        func pullArg() throws -> Int {
            var arg = 0
            for _ in 0..<4 {
                guard let cont = iterator.next() else {
                    throw ROMParseError.truncated("pidata argument")
                }
                arg <<= 7
                arg |= Int(cont & 0x7F)
                if cont & 0x80 == 0 { return arg }
            }
            throw ROMParseError.truncated("pidata argument too long")
        }

        func nextByte() throws -> UInt8 {
            guard let byte = iterator.next() else {
                throw ROMParseError.truncated("pidata stream")
            }
            return byte
        }

        while let header = iterator.next() {
            let opcode = header >> 5
            var arg = Int(header & 0x1F)
            if arg == 0 { arg = try pullArg() }

            switch opcode {
            case 0b000:
                unpacked.append(contentsOf: repeatElement(0, count: arg))
            case 0b001:
                for _ in 0..<arg { unpacked.append(try nextByte()) }
            case 0b010:
                let repeatCount = try pullArg() + 1
                var block = Data()
                for _ in 0..<arg { block.append(try nextByte()) }
                for _ in 0..<repeatCount { unpacked.append(block) }
            case 0b011, 0b100:
                let customSize = try pullArg()
                let repeatCount = try pullArg()
                let common: Data
                if opcode == 0b011 {
                    var block = Data()
                    for _ in 0..<arg { block.append(try nextByte()) }
                    common = block
                } else {
                    common = Data(repeating: 0, count: arg)
                }
                for _ in 0..<repeatCount {
                    unpacked.append(common)
                    for _ in 0..<customSize { unpacked.append(try nextByte()) }
                }
                unpacked.append(common)
            default:
                throw ROMParseError.truncated("unknown pidata opcode \(opcode)")
            }
        }
        return unpacked
    }

    private static func pstringOrCString(_ data: Data) -> String {
        guard let first = data.first else { return "" }
        let length = Int(first)
        if length + 1 <= data.count {
            let pstr = data.dropFirst().prefix(length)
            if !pstr.contains(0) {
                return BinaryCursor.macRoman(Data(pstr))
            }
        }
        let cstr = data.prefix { $0 != 0 }
        return BinaryCursor.macRoman(Data(cstr))
    }

    private static func parseVersion(_ number: UInt32) -> String {
        let bytes = withUnsafeBytes(of: number.bigEndian) { Data($0) }
        let maj = String(bytes[0], radix: 16)
        let minbug = String(format: "%02x", bytes[1])
        let minor = String(minbug.prefix(1))
        let bugfix = String(minbug.suffix(1))
        let stageByte = bytes[2]
        let stage: String
        switch stageByte {
        case 0x80: stage = "f"
        case 0x60: stage = "b"
        case 0x40: stage = "a"
        case 0x20: stage = "d"
        default: stage = "?"
        }
        let unreleased = Int(bytes[3])
        var version = "\(maj).\(minor)"
        if bugfix != "0" { version += ".\(bugfix)" }
        if !(stage == "f" && unreleased == 0) {
            version += "\(stage)\(unreleased)"
        }
        return version
    }
}

private extension Data {
    func range(of pattern: Data) -> (location: Int, length: Int)? {
        guard let found = firstRange(of: pattern) else { return nil }
        return (startIndex.distance(to: found.lowerBound), pattern.count)
    }
}
