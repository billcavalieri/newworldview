import Foundation

enum MacROMParser {
    static let expectedSize = 0x400000
    private static let padPattern: Data = {
        var data = Data()
        data.reserveCapacity(200)
        for _ in 0..<100 { data.append(contentsOf: [0x6B, 0x63]) } // "kc" * 100
        return data
    }()

    static func parse(
        _ data: Data,
        name: String,
        id: String,
        containerOffset: Int?
    ) throws -> ROMNode {
        guard isPowerPC(data) else { throw ROMParseError.unrecognizedFormat }

        let configOffsets = findConfigInfo(in: data)
        guard let first = configOffsets.first,
              let config = try? ConfigInfo.unpack(data, offset: first)
        else {
            throw ROMParseError.unrecognizedFormat
        }

        var working = Array(data)
        var children: [ROMNode] = []
        var filenameMap: [String: String] = [:]

        struct Field {
            var key: String
            var start: Int
            var declaredEnd: Int
            var trimZeros: Bool
            var kind: ROMContentKind
        }

        let fields: [Field] = [
            Field(
                key: "Mac68KROM",
                start: first + config.mac68KROMOffset,
                declaredEnd: first + config.mac68KROMOffset + config.mac68KROMSize,
                trimZeros: false,
                kind: .binary
            ),
            Field(
                key: "ExceptionTable",
                start: first + config.exceptionTableOffset,
                declaredEnd: first + config.exceptionTableOffset + config.exceptionTableSize,
                trimZeros: false,
                kind: .disassemblable(.powerPC)
            ),
            Field(
                key: "HWInitCode",
                start: first + config.hwInitCodeOffset,
                declaredEnd: first + config.hwInitCodeOffset + config.hwInitCodeSize,
                trimZeros: true,
                kind: .disassemblable(.powerPC)
            ),
            Field(
                key: "KernelCode",
                start: first + config.kernelCodeOffset,
                declaredEnd: first + config.kernelCodeOffset + config.kernelCodeSize,
                trimZeros: true,
                kind: .disassemblable(.powerPC)
            ),
            Field(
                key: "EmulatorCode",
                start: first + config.emulatorCodeOffset,
                declaredEnd: first + config.emulatorCodeOffset + config.emulatorCodeSize,
                trimZeros: false,
                kind: .disassemblable(.powerPC)
            ),
            Field(
                key: "OpcodeTable",
                start: first + config.opcodeTableOffset,
                declaredEnd: first + config.opcodeTableOffset + config.opcodeTableSize,
                trimZeros: false,
                kind: .binary
            ),
            Field(
                key: "OpenFWBundle",
                start: first + config.openFWBundleOffset,
                declaredEnd: first + config.openFWBundleOffset + config.openFWBundleSize,
                trimZeros: true,
                kind: .binary
            )
        ]

        let sorted = fields.sorted { $0.start < $1.start }
        for field in sorted {
            let start = field.start
            var stop = field.declaredEnd
            guard start >= 0, start < working.count else { continue }
            if field.trimZeros {
                if let zeroAt = firstRunOfZeros(in: working, start: start, count: 1024) {
                    stop = zeroAt
                }
            }
            while stop % 4 != 0 { stop += 1 }
            stop = min(max(stop, start), working.count)
            let fragment = Data(working[start..<stop])
            guard fragment.contains(where: { $0 != 0 }) else { continue }
            for i in start..<stop { working[i] = 0 }

            var filename = field.key
                .replacingOccurrences(of: "Code", with: "")
                .replacingOccurrences(of: "Bundle", with: "")
                .replacingOccurrences(of: "Kern", with: "NanoKern")
            if field.key == "KernelCode", let version = nanoKernelVersion(fragment) {
                filename += "-\(version)"
            }
            filenameMap[field.key + "Offset"] = filename

            let runtime: UInt64?
            var metadata = ["configField": field.key]
            switch field.key {
            case "Mac68KROM":
                runtime = 0
                metadata["addressSpace"] = AddressSpace.m68kToolbox.rawValue
            case "OpenFWBundle":
                runtime = UInt64(bitPattern: Int64(config.laOpenFirmware))
                metadata["addressSpace"] = AddressSpace.pef.rawValue
            default:
                runtime = AddressSpaces.ppcMacROMBase + UInt64(start)
                metadata["addressSpace"] = AddressSpace.ppcMacROM.rawValue
                metadata["macromOffset"] = String(start)
            }

            if field.key == "Mac68KROM" {
                children.append(
                    ROMDispatcher.parse(
                        fragment,
                        name: filename,
                        id: id + "/" + filename,
                        containerOffset: (containerOffset ?? 0) + start,
                        resourceFork: nil
                    )
                )
            } else if field.key == "OpenFWBundle" {
                children.append(
                    ROMDispatcher.parse(
                        fragment,
                        name: filename,
                        id: id + "/" + filename,
                        containerOffset: (containerOffset ?? 0) + start,
                        resourceFork: nil
                    )
                )
            } else {
                children.append(
                    ROMNode.leaf(
                        id: id + "/" + filename,
                        name: filename,
                        data: fragment,
                        kind: field.kind,
                        containerOffset: (containerOffset ?? 0) + start,
                        runtimeAddress: runtime,
                        metadata: metadata
                    )
                )
            }
        }

        let leftover = Data(working)
        if leftover.contains(where: { $0 != 0 }) {
            children.append(
                ROMNode.leaf(
                    id: id + "/EverythingElse",
                    name: "EverythingElse",
                    data: leftover,
                    kind: .binary,
                    containerOffset: containerOffset
                )
            )
        }

        for (index, offset) in configOffsets.enumerated() {
            let text = ConfigInfo.dump(data, offset: offset, filenameMap: filenameMap)
            children.insert(
                ROMNode(
                    id: id + "/Configfile-\(index + 1)",
                    name: "Configfile-\(index + 1)",
                    kind: .text,
                    data: try BinaryCursor.slice(data, offset: offset, count: min(0x1000, data.count - offset), context: "ConfigInfo"),
                    text: text,
                    containerOffset: (containerOffset ?? 0) + offset
                ),
                at: index
            )
        }

        let summary = """
        PowerPC Mac ROM
        Size: \(data.count) bytes
        ConfigInfo pages: \(configOffsets.count)
        Bootstrap: \(config.bootstrapVersion)
        """

        return ROMNode(
            id: id,
            name: name,
            kind: .folder,
            data: data,
            text: summary,
            containerOffset: containerOffset,
            children: children
        )
    }

    static func isPowerPC(_ data: Data) -> Bool {
        data.count == expectedSize && data.prefix(0x300000).firstRange(of: padPattern) != nil
    }

    static func findConfigInfo(in data: Data) -> [Int] {
        var lanes = [Int](repeating: 0, count: 8)
        for (index, byte) in data.enumerated() {
            lanes[index % 8] += Int(byte)
        }

        var found: Int?
        for candidate in stride(from: 0, to: data.count, by: 0x100) {
            guard candidate + 40 <= data.count else { break }
            var zeroed = lanes
            for j in candidate..<(candidate + 40) {
                zeroed[j % 8] -= Int(data[data.startIndex + j])
            }
            let sum32 = zeroed.map { UInt32(truncatingIfNeeded: $0) }
            var sum64: UInt64 = 0
            for k in 0..<8 {
                let lane = UInt64(bitPattern: Int64(zeroed[7 - k]))
                sum64 &+= lane &<< UInt64(k * 8)
            }
            var checksum = Data()
            checksum.reserveCapacity(40)
            for value in sum32 {
                checksum.append(UInt8(truncatingIfNeeded: value >> 24))
                checksum.append(UInt8(truncatingIfNeeded: value >> 16))
                checksum.append(UInt8(truncatingIfNeeded: value >> 8))
                checksum.append(UInt8(truncatingIfNeeded: value))
            }
            checksum.append(UInt8(truncatingIfNeeded: sum64 >> 56))
            checksum.append(UInt8(truncatingIfNeeded: sum64 >> 48))
            checksum.append(UInt8(truncatingIfNeeded: sum64 >> 40))
            checksum.append(UInt8(truncatingIfNeeded: sum64 >> 32))
            checksum.append(UInt8(truncatingIfNeeded: sum64 >> 24))
            checksum.append(UInt8(truncatingIfNeeded: sum64 >> 16))
            checksum.append(UInt8(truncatingIfNeeded: sum64 >> 8))
            checksum.append(UInt8(truncatingIfNeeded: sum64))
            if data[data.startIndex + candidate ..< data.startIndex + candidate + 40].elementsEqual(checksum) {
                found = candidate
                break
            }
        }

        if found == nil {
            for candidate in stride(from: 0x300000, to: data.count, by: 0x100) {
                guard candidate + 0x74 <= data.count else { break }
                if data[data.startIndex + candidate + 0x64 ..< data.startIndex + candidate + 0x69]
                    .elementsEqual("Boot ".utf8) {
                    found = candidate
                    break
                }
            }
        }

        guard let match = found, match + 0x74 <= data.count else { return [] }
        let signature = data[data.startIndex + match + 0x64 ..< data.startIndex + match + 0x74]
        var offsets: [Int] = []
        for candidate in stride(from: 0, to: data.count, by: 0x100) {
            guard candidate + 0x74 <= data.count else { break }
            if data[data.startIndex + candidate + 0x64 ..< data.startIndex + candidate + 0x74]
                .elementsEqual(signature) {
                offsets.append(candidate)
            }
        }
        return offsets
    }

    static func nanoKernelVersion(_ nk: Data) -> String? {
        if nk.count >= 6, nk.starts(with: Data([0x48, 0x00, 0x00, 0x0C])) {
            return String(format: "v%02X.%02X", nk[nk.startIndex + 4], nk[nk.startIndex + 5])
        }
        var offset = 0
        while offset + 8 <= nk.count {
            if nk[nk.startIndex + offset] == 0x39, nk[nk.startIndex + offset + 1] == 0x80,
               nk[nk.startIndex + offset + 4] == 0xB1,
               nk[nk.startIndex + offset + 5] == 0x81,
               nk[nk.startIndex + offset + 6] == 0x0F,
               nk[nk.startIndex + offset + 7] == 0xE4 {
                return String(format: "v%02X.%02X", nk[nk.startIndex + offset + 2], nk[nk.startIndex + offset + 3])
            }
            offset += 4
        }
        return nil
    }

    private static func firstRunOfZeros(in bytes: [UInt8], start: Int, count: Int) -> Int? {
        guard start < bytes.count else { return nil }
        var run = 0
        for index in start..<bytes.count {
            if bytes[index] == 0 {
                run += 1
                if run == count { return index - count + 1 }
            } else {
                run = 0
            }
        }
        return nil
    }
}

struct ConfigInfo {
    var romImageBaseOffset: Int32
    var romImageSize: UInt32
    var romImageVersion: UInt32
    var mac68KROMOffset: Int
    var mac68KROMSize: Int
    var exceptionTableOffset: Int
    var exceptionTableSize: Int
    var hwInitCodeOffset: Int
    var hwInitCodeSize: Int
    var kernelCodeOffset: Int
    var kernelCodeSize: Int
    var emulatorCodeOffset: Int
    var emulatorCodeSize: Int
    var opcodeTableOffset: Int
    var opcodeTableSize: Int
    var bootstrapVersion: String
    var laEmulatorCode: Int32
    var macLowMemInitOffset: Int
    var pageAttributeInit: UInt32
    var pageMapInitSize: Int
    var pageMapInitOffset: Int
    var pageMapIRPOffset: Int
    var pageMapKDPOffset: Int
    var pageMapEDPOffset: Int
    var segMap32SupInit: Data
    var segMap32UsrInit: Data
    var segMap32CPUInit: Data
    var segMap32OvlInit: Data
    var batRangeInit: Data
    var batMap32SupInit: UInt32
    var batMap32UsrInit: UInt32
    var batMap32CPUInit: UInt32
    var batMap32OvlInit: UInt32
    var sharedMemoryAddr: UInt32
    var paRelocatedLowMemInit: UInt32
    var openFWBundleOffset: Int
    var openFWBundleSize: Int
    var laOpenFirmware: Int32
    var paOpenFirmware: UInt32
    var laHardwarePriv: Int32
    var rawFields: [(String, String)]

    static func unpack(_ data: Data, offset: Int) throws -> ConfigInfo {
        func i32(_ at: Int) throws -> Int32 { try BinaryCursor.i32be(data, offset + at) }
        func u32(_ at: Int) throws -> UInt32 { try BinaryCursor.u32be(data, offset + at) }
        func slice(_ at: Int, _ count: Int) throws -> Data {
            try BinaryCursor.slice(data, offset: offset + at, count: count, context: "ConfigInfo")
        }

        let bootstrap = try BinaryCursor.macRoman(slice(0x64, 16)).trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
        let romBase = try i32(0x28)

        func offsetField(_ key: String, _ at: Int) throws -> String {
            let raw = try i32(at)
            if raw == 0 { return "0x00000000" }
            let relative = Int(raw) - Int(romBase)
            let sign = relative < 0 ? "-" : "+"
            return "BASE\(sign)0x\(String(format: "%X", abs(relative)))"
        }

        let rawFields: [(String, String)] = [
            ("ROMImageBaseOffset", BinaryCursor.hex(Int(try i32(0x28)))),
            ("ROMImageSize", BinaryCursor.hex(try u32(0x2C))),
            ("ROMImageVersion", BinaryCursor.hex(try u32(0x30))),
            ("Mac68KROMOffset", try offsetField("Mac68KROMOffset", 0x34)),
            ("Mac68KROMSize", BinaryCursor.hex(try u32(0x38))),
            ("ExceptionTableOffset", try offsetField("ExceptionTableOffset", 0x3C)),
            ("ExceptionTableSize", BinaryCursor.hex(try u32(0x40))),
            ("HWInitCodeOffset", try offsetField("HWInitCodeOffset", 0x44)),
            ("HWInitCodeSize", BinaryCursor.hex(try u32(0x48))),
            ("KernelCodeOffset", try offsetField("KernelCodeOffset", 0x4C)),
            ("KernelCodeSize", BinaryCursor.hex(try u32(0x50))),
            ("EmulatorCodeOffset", try offsetField("EmulatorCodeOffset", 0x54)),
            ("EmulatorCodeSize", BinaryCursor.hex(try u32(0x58))),
            ("OpcodeTableOffset", try offsetField("OpcodeTableOffset", 0x5C)),
            ("OpcodeTableSize", BinaryCursor.hex(try u32(0x60))),
            ("BootstrapVersion", bootstrap),
            ("LA_EmulatorCode", BinaryCursor.hex(try u32(0xAC))),
            ("OpenFWBundleOffset", try offsetField("OpenFWBundleOffset", 0x364)),
            ("OpenFWBundleSize", BinaryCursor.hex(try u32(0x368))),
            ("LA_OpenFirmware", BinaryCursor.hex(try u32(0x36C))),
            ("PA_OpenFirmware", BinaryCursor.hex(try u32(0x370))),
            ("LA_HardwarePriv", BinaryCursor.hex(try u32(0x374)))
        ]

        return ConfigInfo(
            romImageBaseOffset: romBase,
            romImageSize: try u32(0x2C),
            romImageVersion: try u32(0x30),
            mac68KROMOffset: Int(try i32(0x34)),
            mac68KROMSize: Int(try u32(0x38)),
            exceptionTableOffset: Int(try i32(0x3C)),
            exceptionTableSize: Int(try u32(0x40)),
            hwInitCodeOffset: Int(try i32(0x44)),
            hwInitCodeSize: Int(try u32(0x48)),
            kernelCodeOffset: Int(try i32(0x4C)),
            kernelCodeSize: Int(try u32(0x50)),
            emulatorCodeOffset: Int(try i32(0x54)),
            emulatorCodeSize: Int(try u32(0x58)),
            opcodeTableOffset: Int(try i32(0x5C)),
            opcodeTableSize: Int(try u32(0x60)),
            bootstrapVersion: bootstrap,
            laEmulatorCode: try i32(0xAC),
            macLowMemInitOffset: Int(try u32(0xB0)),
            pageAttributeInit: try u32(0xB4),
            pageMapInitSize: Int(try u32(0xB8)),
            pageMapInitOffset: Int(try u32(0xBC)),
            pageMapIRPOffset: Int(try u32(0xC0)),
            pageMapKDPOffset: Int(try u32(0xC4)),
            pageMapEDPOffset: Int(try u32(0xC8)),
            segMap32SupInit: try slice(0xCC, 128),
            segMap32UsrInit: try slice(0x14C, 128),
            segMap32CPUInit: try slice(0x1CC, 128),
            segMap32OvlInit: try slice(0x24C, 128),
            batRangeInit: try slice(0x2CC, 128),
            batMap32SupInit: try u32(0x34C),
            batMap32UsrInit: try u32(0x350),
            batMap32CPUInit: try u32(0x354),
            batMap32OvlInit: try u32(0x358),
            sharedMemoryAddr: try u32(0x35C),
            paRelocatedLowMemInit: try u32(0x360),
            openFWBundleOffset: Int(try i32(0x364)),
            openFWBundleSize: Int(try u32(0x368)),
            laOpenFirmware: try i32(0x36C),
            paOpenFirmware: try u32(0x370),
            laHardwarePriv: try i32(0x374),
            rawFields: rawFields
        )
    }

    static func dump(_ data: Data, offset: Int, filenameMap: [String: String]) -> String {
        guard let info = try? unpack(data, offset: offset) else {
            return "Unable to unpack ConfigInfo at \(BinaryCursor.hex(offset))"
        }
        var lines: [String] = [
            "# ConfigInfo page at \(BinaryCursor.hex(offset))",
            ""
        ]
        for (key, value) in info.rawFields {
            var line = "\(key)=\(value)"
            if let file = filenameMap[key] {
                line += "=\(file)"
            }
            lines.append(line)
        }
        lines.append("")
        lines.append("[LowMemory]")
        var lm = offset + info.macLowMemInitOffset
        while lm + 8 <= data.count {
            guard let key = try? BinaryCursor.u32be(data, lm), key != 0 else { break }
            let value = (try? BinaryCursor.u32be(data, lm + 4)) ?? 0
            lines.append("address=\(BinaryCursor.hex(key)) value=\(BinaryCursor.hex(value))")
            lm += 8
        }
        return lines.joined(separator: "\n")
    }
}
