import Foundation
import NewWorldROM
import Testing

struct BootInfoParserTests {
    @Test func parsesCHRPConstants() {
        let parcel = minimalParcel()
        let elf: Data = {
            var data = Data([0x7F, 0x45, 0x4C, 0x46, 0x01, 0x02, 0x01, 0x00])
            data.append(Data(repeating: 0, count: 0x20 - data.count))
            return data
        }()
        let elfOffset = 0x1000
        let parcelsOffset = elfOffset + elf.count

        var script = """
        <CHRP-BOOT>
        <COMPATIBLE>
        MacRISC
        </COMPATIBLE>
        h# \(String(elfOffset, radix: 16)) constant elf-offset
        h# \(String(elf.count, radix: 16)) constant elf-size
        h# \(String(parcelsOffset, radix: 16)) constant parcels-offset
        h# \(String(parcel.count, radix: 16)) constant parcels-size
        """
        script = script.replacingOccurrences(of: "\n", with: "\r")

        var rom = Data(script.utf8)
        if rom.count < elfOffset {
            rom.append(Data(repeating: 0x20, count: elfOffset - rom.count))
        }
        rom.append(elf)
        rom.append(parcel)

        let parsed = ROMParser.parse(data: rom, fileName: "fixture.tbxi")
        let names = parsed.root.descendants.map(\.name)
        #expect(names.contains("Bootscript"))
        #expect(names.contains("MacOS.elf"))
        #expect(names.contains("Parcels"))
        #expect(names.contains("hello"))

        let bootscript = parsed.root.descendants.first { $0.name == "Bootscript" }
        #expect(bootscript?.kind == .text)
        #expect(bootscript?.text?.contains("constant elf-offset") == true)
    }

    @Test func rejectsRandomData() {
        let parsed = ROMParser.parse(data: Data("not a rom".utf8), fileName: "noise.bin")
        #expect(parsed.root.children.isEmpty)
        #expect(parsed.warnings.isEmpty == false)
    }
}

func u32be(_ value: UInt32) -> Data {
    Data([
        UInt8(truncatingIfNeeded: value >> 24),
        UInt8(truncatingIfNeeded: value >> 16),
        UInt8(truncatingIfNeeded: value >> 8),
        UInt8(truncatingIfNeeded: value)
    ])
}

func fourCC(_ value: String) -> Data {
    var data = Data(value.utf8)
    while data.count < 4 { data.append(0) }
    return Data(data.prefix(4))
}

func padded(_ string: String, _ count: Int) -> Data {
    var data = Data(string.utf8)
    if data.count > count { return Data(data.prefix(count)) }
    data.append(Data(repeating: 0, count: count - data.count))
    return data
}

func minimalParcel() -> Data {
    let nodeOffset: UInt32 = 20
    let payloadOffset = 20 + 148
    let payload = Data("hello\0world\0".utf8)

    var data = Data("prcl".utf8)
    data.append(contentsOf: [0x01, 0x00, 0x00, 0x00])
    data.append(u32be(0))
    data.append(u32be(nodeOffset))
    data.append(u32be(0))

    data.append(u32be(0))
    data.append(fourCC("node"))
    data.append(u32be(148))
    data.append(u32be(0))
    data.append(u32be(1))
    data.append(u32be(60))
    data.append(padded("test-node", 32))
    data.append(padded("", 32))

    data.append(fourCC("cstr"))
    data.append(u32be(0))
    data.append(padded("none", 4))
    data.append(u32be(UInt32(payload.count)))
    data.append(u32be(0))
    data.append(u32be(UInt32(payload.count)))
    data.append(u32be(UInt32(payloadOffset)))
    data.append(padded("hello", 32))

    data.append(payload)
    return data
}
