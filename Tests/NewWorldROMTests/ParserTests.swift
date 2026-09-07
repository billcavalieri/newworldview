import Foundation
import NewWorldROM
import Testing

struct ParcelParserTests {
    @Test func walksPrclTreeAndExposesCStringChildren() {
        let parcel = minimalParcel()
        let parsed = ROMParser.parse(data: parcel, fileName: "parcels")
        let names = parsed.root.descendants.map(\.name)
        #expect(names.contains("Parcelfile"))
        #expect(names.contains("hello"))

        let hello = parsed.root.descendants.first { $0.name == "hello" }
        #expect(hello?.kind == .text)
        #expect(hello?.text?.contains("hello") == true)
        #expect(hello?.text?.contains("world") == true)
    }
}

struct PEFParserTests {
    @Test func ignoresNonPEF() {
        let parsed = ROMParser.parse(data: Data("notpef".utf8), fileName: "x")
        #expect(parsed.root.kind == .text || parsed.root.kind == .binary)
    }

    @Test func parsesMinimalPEFHeader() throws {
        var data = Data("Joy!peffpwpc".utf8) // magic + fourcc + arch = 12 bytes
        data.append(u32be(1)) // ver
        data.append(u32be(0)) // timestamp
        data.append(u32be(0))
        data.append(u32be(0))
        data.append(u32be(0))
        data.append(contentsOf: [0x00, 0x01]) // sec_count = 1
        data.append(contentsOf: [0x00, 0x01]) // inst_sec_count
        data.append(u32be(0)) // reserved

        data.append(u32be(0xFFFF_FFFF)) // sectionName
        data.append(u32be(0x1000)) // address
        data.append(u32be(4)) // execSize
        data.append(u32be(4)) // initSize
        data.append(u32be(4)) // rawSize
        data.append(u32be(68)) // containerOffset
        data.append(contentsOf: [0, 1, 4, 0]) // code, share, align, reserved
        data.append(contentsOf: [0x48, 0x00, 0x00, 0x00]) // bl .+0

        let parsed = ROMParser.parse(data: data, fileName: "driver.pef")
        #expect(parsed.root.children.contains { $0.name.contains("Code") })
        let code = parsed.root.children.first { $0.name.contains("Code") }
        #expect(code?.kind == .disassemblable(.powerPC))
        #expect(code?.data.count == 4)
    }
}

struct DisassemblyServiceTests {
    @Test func disassemblesPowerPCBranch() {
        let code = Data([0x48, 0x00, 0x00, 0x00])
        let listing = DisassemblyService.listing(code, isa: .powerPC, baseAddress: 0x1000)
        #expect(listing.contains("1000:"))
        #expect(listing.localizedCaseInsensitiveContains("b") || listing.contains("Capstone produced no instructions") == false)
    }
}

struct ROMParserIntegrationTests {
    @Test func parsesLocalMacOSROMWhenPathIsSet() throws {
        let envPath = ProcessInfo.processInfo.environment["TBXI_ROM_PATH"]
        let defaultPath = NSString(string: "~/Downloads/Mac OS ROM").expandingTildeInPath
        let path = envPath ?? defaultPath
        guard FileManager.default.isReadableFile(atPath: path) else { return }

        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        let rsrc = try? Data(contentsOf: url.appendingPathComponent("..namedfork/rsrc"))
        let parsed = ROMParser.parse(data: data, resourceFork: rsrc, fileName: url.lastPathComponent)
        let names = parsed.root.descendants.map(\.name)

        #expect(parsed.fileSize == data.count)
        #expect(names.contains("Bootscript"))
        #expect(names.contains("Parcels") || names.contains("MacROM"))
        #expect(names.contains(where: { $0.contains("NanoKern") || $0 == "MacROM" || $0.contains("Configfile") }))
    }
}

