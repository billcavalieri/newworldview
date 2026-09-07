import Foundation
import NewWorldROM
import Testing

struct AnalysisEngineTests {
    @Test func recordsGetNewDialogATrap() {
        let node = ROMNode.leaf(
            id: "rom/Mac68KROM/MainCode",
            name: "MainCode",
            data: Data([0xA9, 0x7C]),
            kind: .disassemblable(.m68k),
            runtimeAddress: AddressSpaces.getNewDialogStub,
            metadata: ["addressSpace": AddressSpace.m68kToolbox.rawValue]
        )
        let parsed = ParsedROM(root: node, fileName: "fixture", fileSize: 2)
        let database = AnalysisEngine.analyze(parsed)
        #expect(database.xrefs.contains { xref in
            xref.kind == .trap && xref.toSymbol == "_GetNewDialog"
        })
        #expect(database.symbols.contains { $0.name == "GetNewDialog_stub" })
        #expect(ATrapTable.noSkipUITraps.contains(0xA97C))
        #expect(ATrapTable.noSkipUITraps.contains(0xA97D))
        #expect(ATrapTable.names[0xAA1B] == "GetCCursor")
    }

    @Test func recordsPowerPCCall() {
        let node = ROMNode.leaf(
            id: "rom/MacROM/NanoKernel",
            name: "NanoKernel",
            data: Data([0x48, 0x00, 0x00, 0x01]),
            kind: .disassemblable(.powerPC),
            runtimeAddress: AddressSpaces.ppcMacROMBase + 0x310000,
            metadata: [
                "addressSpace": AddressSpace.ppcMacROM.rawValue,
                "macromOffset": String(0x310000)
            ]
        )
        let parsed = ParsedROM(root: node, fileName: "fixture", fileSize: 4)
        let database = AnalysisEngine.analyze(parsed)
        #expect(database.xrefs.contains { $0.kind == .call })
        #expect(database.functions.contains { $0.name == "NanoKernel" })
        #expect(database.blocks.contains { $0.address.space == .ppcMacROM })
    }

    @Test func mapsProgramAddressToNodeByteOffset() {
        let node = ROMNode.leaf(
            id: "rom/MacROM/NanoKernel",
            name: "NanoKernel",
            data: Data(repeating: 0, count: 256),
            kind: .disassemblable(.powerPC),
            runtimeAddress: AddressSpaces.ppcMacROMBase + 0x310000,
            metadata: [
                "addressSpace": AddressSpace.ppcMacROM.rawValue,
                "macromOffset": String(0x310000)
            ]
        )
        let address = ProgramAddress(space: .ppcMacROM, address: AddressSpaces.ppcMacROMBase + 0x310040)
        #expect(AnalysisEngine.byteOffset(for: address, in: node) == 0x40)
    }

    @Test func ghidraExportWritesSidecarFilesWithoutROMBytes() throws {
        let node = ROMNode.leaf(
            id: "rom/MainCode",
            name: "MainCode",
            data: Data([0xA9, 0xA0]),
            kind: .disassemblable(.m68k),
            runtimeAddress: 0x100,
            metadata: ["addressSpace": AddressSpace.m68kToolbox.rawValue]
        )
        let parsed = ParsedROM(root: node, fileName: "Mac OS ROM", fileSize: 2)
        let database = AnalysisEngine.analyze(parsed)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NewWorldView-ghidra-test-\(UUID().uuidString)", isDirectory: true)
        try GhidraExport.write(database: database, parsed: parsed, to: directory)
        let json = try String(contentsOf: directory.appendingPathComponent("analysis.json"), encoding: .utf8)
        let xml = try String(contentsOf: directory.appendingPathComponent("analysis.xml"), encoding: .utf8)
        let script = try String(contentsOf: directory.appendingPathComponent("LoadNewWorldROM.py"), encoding: .utf8)
        #expect(json.contains(GhidraExport.formatID))
        #expect(json.contains("0x50000000"))
        #expect(json.contains("_GetResource") || xml.contains("_GetResource"))
        #expect(xml.contains("<SYMBOL"))
        #expect(script.contains("askFile"))
        #expect(script.contains("addMemoryReference"))
        let jsonData = try Data(contentsOf: directory.appendingPathComponent("analysis.json"))
        #expect(jsonData.count < 1_000_000)
    }
}
