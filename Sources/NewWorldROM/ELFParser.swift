import Foundation

enum ELFParser {
    static func parse(
        _ data: Data,
        name: String,
        id: String,
        containerOffset: Int?
    ) throws -> ROMNode {
        guard data.count >= 52, data.starts(with: Data([0x7F, 0x45, 0x4C, 0x46])) else {
            throw ROMParseError.unrecognizedFormat
        }

        let is32 = data[4] == 1
        let bigEndian = data[5] == 2
        guard is32, bigEndian else {
            return ROMNode.leaf(
                id: id,
                name: name,
                data: data,
                kind: .binary,
                containerOffset: containerOffset,
                metadata: ["note": "ELF is not 32-bit big-endian PowerPC"]
            )
        }

        let machine = try BinaryCursor.u16be(data, 18)
        let entry = try BinaryCursor.u32be(data, 24)
        let shoff = Int(try BinaryCursor.u32be(data, 32))
        let shentsize = Int(try BinaryCursor.u16be(data, 46))
        let shnum = Int(try BinaryCursor.u16be(data, 48))
        let shstrndx = Int(try BinaryCursor.u16be(data, 50))

        var children: [ROMNode] = []
        if shoff > 0, shentsize >= 40, shnum > 0 {
            let names = sectionNames(data, shoff: shoff, shentsize: shentsize, shnum: shnum, shstrndx: shstrndx)
            for index in 0..<shnum {
                let header = shoff + index * shentsize
                guard header + 40 <= data.count else { break }
                let nameOffset = Int(try BinaryCursor.u32be(data, header))
                let type = try BinaryCursor.u32be(data, header + 4)
                let flags = try BinaryCursor.u32be(data, header + 8)
                let addr = try BinaryCursor.u32be(data, header + 12)
                let offset = Int(try BinaryCursor.u32be(data, header + 16))
                let size = Int(try BinaryCursor.u32be(data, header + 20))
                guard type != 0, size > 0, offset + size <= data.count else { continue }
                let sectionName = names[nameOffset] ?? "section-\(index)"
                let slice = try BinaryCursor.slice(data, offset: offset, count: size, context: sectionName)
                let executable = flags & 0x4 != 0
                children.append(
                    ROMNode.leaf(
                        id: id + "/" + sectionName,
                        name: sectionName,
                        data: slice,
                        kind: executable ? .disassemblable(.powerPC) : ROMDispatcher.inferredKind(slice),
                        containerOffset: (containerOffset ?? 0) + offset,
                        runtimeAddress: UInt64(addr),
                        metadata: [
                            "sh_type": BinaryCursor.hex(type),
                            "sh_flags": BinaryCursor.hex(flags)
                        ]
                    )
                )
            }
        }

        let isaNote = machine == 20 ? "PowerPC" : "machine \(machine)"
        let summary = """
        ELF 32-bit big-endian
        Machine: \(isaNote)
        Entry: \(BinaryCursor.hex(entry))
        Sections: \(children.count)
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
                "entry": BinaryCursor.hex(entry),
                "machine": String(machine)
            ]
        )
    }

    private static func sectionNames(
        _ data: Data,
        shoff: Int,
        shentsize: Int,
        shnum: Int,
        shstrndx: Int
    ) -> [Int: String] {
        guard shstrndx < shnum else { return [:] }
        let header = shoff + shstrndx * shentsize
        guard header + 24 <= data.count else { return [:] }
        guard let offset = try? Int(BinaryCursor.u32be(data, header + 16)),
              let size = try? Int(BinaryCursor.u32be(data, header + 20)),
              let table = try? BinaryCursor.slice(data, offset: offset, count: size, context: ".shstrtab")
        else { return [:] }

        var names: [Int: String] = [:]
        var cursor = 0
        while cursor < table.count {
            let remaining = table[table.startIndex + cursor ..< table.endIndex]
            let end = remaining.firstIndex(of: 0) ?? table.endIndex
            let bytes = table[table.startIndex + cursor ..< end]
            names[cursor] = String(decoding: bytes, as: UTF8.self)
            let length = table.startIndex.distance(to: end) - cursor
            cursor += length + 1
        }
        return names
    }
}
