import Foundation

struct ResourceForkResource: Sendable {
    var type: String
    var id: Int
    var name: String
    var data: Data
}

enum ResourceForkParser {
    static func parse(_ fork: Data) throws -> [ResourceForkResource] {
        guard fork.count >= 16 else { throw ROMParseError.unrecognizedFormat }
        let dataOffset = Int(try BinaryCursor.u32be(fork, 0))
        let mapOffset = Int(try BinaryCursor.u32be(fork, 4))
        guard mapOffset + 28 <= fork.count, dataOffset < fork.count else {
            throw ROMParseError.unrecognizedFormat
        }

        let typeListOffset = mapOffset + Int(try BinaryCursor.u16be(fork, mapOffset + 24))
        let nameListOffset = mapOffset + Int(try BinaryCursor.u16be(fork, mapOffset + 26))
        guard typeListOffset + 2 <= fork.count else { throw ROMParseError.truncated("type list") }

        let typeCount = Int(try BinaryCursor.u16be(fork, typeListOffset)) &+ 1
        var resources: [ResourceForkResource] = []

        for typeIndex in 0..<typeCount {
            let entry = typeListOffset + 2 + typeIndex * 8
            let type = try BinaryCursor.fourCC(fork, entry)
            let refCount = Int(try BinaryCursor.u16be(fork, entry + 4)) &+ 1
            let refListOffset = typeListOffset + Int(try BinaryCursor.u16be(fork, entry + 6))

            for refIndex in 0..<refCount {
                let ref = refListOffset + refIndex * 12
                guard ref + 8 <= fork.count else { continue }
                let resourceID = Int(Int16(bitPattern: try BinaryCursor.u16be(fork, ref)))
                let nameOffset = try BinaryCursor.u16be(fork, ref + 2)
                let dataRel = Int(try BinaryCursor.u8(fork, ref + 5)) << 16
                    | Int(try BinaryCursor.u8(fork, ref + 6)) << 8
                    | Int(try BinaryCursor.u8(fork, ref + 7))
                let dataAbs = dataOffset + dataRel
                guard dataAbs + 4 <= fork.count else { continue }
                let length = Int(try BinaryCursor.u32be(fork, dataAbs))
                let payload: Data
                if let slice = try? BinaryCursor.slice(fork, offset: dataAbs + 4, count: length, context: "\(type)#\(resourceID)") {
                    payload = slice
                } else {
                    continue
                }

                var resourceName = ""
                if nameOffset != 0xFFFF {
                    let nameAbs = nameListOffset + Int(nameOffset)
                    if let nameData = try? BinaryCursor.pascalString(fork, offset: nameAbs) {
                        resourceName = BinaryCursor.macRoman(nameData)
                    }
                }

                resources.append(
                    ResourceForkResource(type: type, id: resourceID, name: resourceName, data: payload)
                )
            }
        }
        return resources
    }
}

enum CFRGParser {
    static func dataForkRange(cfrgs: [Data], dataForkLength: Int) -> Range<Int>? {
        var left = dataForkLength
        var right = 0
        var found = false

        for cfrg in cfrgs {
            for field in offsetFields(in: cfrg) {
                guard let start = try? Int(BinaryCursor.u32be(cfrg, field)),
                      let length = try? Int(BinaryCursor.u32be(cfrg, field + 4))
                else { continue }
                found = true
                left = min(left, start)
                if length == 0 {
                    right = dataForkLength
                } else {
                    right = max(right, start + length)
                }
            }
        }

        guard found, left < right, right <= dataForkLength else { return nil }
        return left..<right
    }

    private static func offsetFields(in cfrg: Data) -> [Int] {
        guard cfrg.count >= 32, let count = try? Int(BinaryCursor.u32be(cfrg, 28)) else { return [] }
        var fields: [Int] = []
        var cursor = 32
        for _ in 0..<count {
            guard cursor + 43 <= cfrg.count else { break }
            if cfrg[cfrg.startIndex + cursor + 23] == 1 {
                fields.append(cursor + 24)
            }
            let nameLength = Int(cfrg[cfrg.startIndex + cursor + 42])
            cursor += 42 + 1 + nameLength
            while cursor % 4 != 0 { cursor += 1 }
        }
        return fields
    }
}

struct SysEnablerExtractor {
    struct Result {
        var start: Int
        var data: Data
        var resources: [ROMNode]
        var listing: String
    }

    static func extract(dataFork: Data, resourceFork: Data) -> Result? {
        guard let resources = try? ResourceForkParser.parse(resourceFork) else { return nil }
        let cfrgs = resources.filter { $0.type == "cfrg" }.map(\.data)
        guard let range = CFRGParser.dataForkRange(cfrgs: cfrgs, dataForkLength: dataFork.count),
              let slice = try? BinaryCursor.slice(dataFork, offset: range.lowerBound, count: range.count, context: "SysEnabler")
        else { return nil }

        var listing = "SysEnabler resources from the ROM resource fork\n\n"
        var nodes: [ROMNode] = []
        for resource in resources {
            let label = resource.name.isEmpty
                ? "\(resource.type)#\(resource.id)"
                : "\(resource.type)#\(resource.id) \(resource.name)"
            listing += "\(label)  \(resource.data.count) bytes\n"
            nodes.append(
                ROMDispatcher.parse(
                    resource.data,
                    name: label,
                    id: "SysEnabler/\(label)",
                    containerOffset: nil,
                    resourceFork: nil
                )
            )
        }

        return Result(start: range.lowerBound, data: slice, resources: nodes, listing: listing)
    }
}
