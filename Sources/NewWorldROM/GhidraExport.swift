import Foundation

public enum GhidraExport {
    public static let formatID = "NewWorldView-ghidra"
    public static let formatVersion = 2

    public struct ExportOptions: Sendable {
        public var includeMillTags: Bool
        public var trapFilter: TrapExportFilter

        public init(includeMillTags: Bool = true, trapFilter: TrapExportFilter = .all) {
            self.includeMillTags = includeMillTags
            self.trapFilter = trapFilter
        }

        public static let `default` = ExportOptions()
    }

    public enum TrapExportFilter: String, Sendable {
        case all
        case millCritical
        case noSkipUI
    }

    public static func write(
        database: AnalysisDatabase,
        parsed: ParsedROM,
        to directory: URL,
        options: ExportOptions = .default
    ) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let payload = snapshot(database: database, parsed: parsed, options: options)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let json = try encoder.encode(payload)
        try json.write(to: directory.appendingPathComponent("analysis.json"))
        try xml(payload).write(
            to: directory.appendingPathComponent("analysis.xml"),
            atomically: true,
            encoding: .utf8
        )
        try pythonLoader.write(
            to: directory.appendingPathComponent("LoadNewWorldROM.py"),
            atomically: true,
            encoding: .utf8
        )
        let readme = """
        NewWorldView Ghidra export
        ==========================

        analysis.json   Canonical symbol / function / xref database (no ROM bytes).
        analysis.xml    Ghidra-oriented PROGRAM XML (symbols, functions, refs).
        LoadNewWorldROM.py  Ghidra script: apply JSON onto a program you load locally.

        ROM bytes are never exported. In Ghidra:

        1. File → New Program, language PowerPC:BE:32:default (or 68000:BE:32:default for Toolbox).
        2. Map your local decompressed 4 MB MacROM at 0x50000000, and/or Mac68KROM at 0x00000000.
        3. Window → Script Manager → Run LoadNewWorldROM.py and choose analysis.json.

        ppcMacROM base: 0x50000000 (SheepShaver / rom_disasm.py).
        """
        try readme.write(to: directory.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
    }

    public static func snapshot(
        database: AnalysisDatabase,
        parsed: ParsedROM,
        options: ExportOptions = .default
    ) -> GhidraSnapshot {
        let filteredXrefs = filterXRefs(database.xrefs, options: options)
        let filteredSymbols = filterSymbols(database.symbols, xrefs: filteredXrefs, options: options)
        return GhidraSnapshot(
            format: formatID,
            version: formatVersion,
            fileName: parsed.fileName,
            fileSize: parsed.fileSize,
            ppcMacROMBase: String(format: "0x%08X", AddressSpaces.ppcMacROMBase),
            blocks: database.blocks.map { block in
                GhidraBlock(
                    name: block.name,
                    space: block.address.space.rawValue,
                    address: hex(block.address.address),
                    size: block.size,
                    nodeID: block.nodeID,
                    isa: block.isa?.rawValue,
                    language: (block.isa == .m68k ? AddressSpace.m68kToolbox : AddressSpace.ppcMacROM).ghidraLanguage,
                    romOffset: romOffsetString(for: block.address),
                    tags: options.includeMillTags ? AddressTranslation.millTags(for: block.address) : []
                )
            },
            symbols: filteredSymbols.map { symbol in
                GhidraSymbol(
                    name: symbol.name,
                    space: symbol.address.space.rawValue,
                    address: hex(symbol.address.address),
                    kind: symbol.kind.rawValue,
                    nodeID: symbol.nodeID,
                    romOffset: romOffsetString(for: symbol.address),
                    tags: options.includeMillTags ? AddressTranslation.millTags(for: symbol.address) : []
                )
            },
            functions: database.functions.map { function in
                GhidraFunction(
                    name: function.name,
                    space: function.address.space.rawValue,
                    address: hex(function.address.address),
                    size: function.size,
                    nodeID: function.nodeID,
                    romOffset: romOffsetString(for: function.address),
                    tags: options.includeMillTags ? AddressTranslation.millTags(for: function.address) : []
                )
            },
            xrefs: filteredXrefs.map { xref in
                GhidraXRef(
                    kind: xref.kind.rawValue,
                    ghidraType: xref.kind.ghidraRefType,
                    fromSpace: xref.from.space.rawValue,
                    fromAddress: hex(xref.from.address),
                    toSpace: xref.to.space.rawValue,
                    toAddress: hex(xref.to.address),
                    fromSymbol: xref.fromSymbol,
                    toSymbol: xref.toSymbol,
                    fromNodeID: xref.fromNodeID,
                    toNodeID: xref.toNodeID,
                    fromRomOffset: romOffsetString(for: xref.from),
                    toRomOffset: romOffsetString(for: xref.to)
                )
            }
        )
    }

    private static func filterXRefs(_ xrefs: [XRef], options: ExportOptions) -> [XRef] {
        switch options.trapFilter {
        case .all:
            return xrefs
        case .millCritical:
            return xrefs.filter { xref in
                guard xref.kind == .trap else { return true }
                let trap = UInt16(xref.to.address & 0xFFFF)
                return MillCriticalTraps.all.contains(trap)
            }
        case .noSkipUI:
            return xrefs.filter { xref in
                guard xref.kind == .trap else { return true }
                let trap = UInt16(xref.to.address & 0xFFFF)
                return ATrapTable.noSkipUITraps.contains(trap)
            }
        }
    }

    private static func filterSymbols(_ symbols: [ProgramSymbol], xrefs: [XRef], options: ExportOptions) -> [ProgramSymbol] {
        switch options.trapFilter {
        case .all:
            return symbols
        case .millCritical, .noSkipUI:
            let trapAddresses = Set(xrefs.filter { $0.kind == .trap }.map(\.to.key))
            return symbols.filter { symbol in
                symbol.kind != .trap || trapAddresses.contains(symbol.address.key)
            }
        }
    }

    private static func romOffsetString(for address: ProgramAddress) -> String? {
        guard let offset = AddressTranslation.romOffset(fromVirtual: address.address, space: address.space)
            ?? (address.space == .m68kToolbox ? address.address : nil)
        else { return nil }
        return String(format: "0x%X", offset)
    }

    public static func snapshot(database: AnalysisDatabase, parsed: ParsedROM) -> GhidraSnapshot {
        snapshot(database: database, parsed: parsed, options: .default)
    }

    static func xml(_ snapshot: GhidraSnapshot) -> String {
        var lines = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<PROGRAM NAME=\"\(escape(snapshot.fileName))\" FORMAT=\"NewWorld-tbxi\">",
            "  <INFO_SOURCE TOOL=\"NewWorldView\" FORMAT=\"\(formatID)\" VERSION=\"\(formatVersion)\"/>",
            "  <PROCESSOR NAME=\"PowerPC\" LANGUAGE=\"PowerPC:BE:32:default\"/>",
            "  <MEMORY_MAP>"
        ]
        for block in snapshot.blocks {
            lines.append(
                "    <MEMORY_SECTION NAME=\"\(escape(block.name))\" START_ADDR=\"\(block.address)\" LENGTH=\"\(String(format: "0x%X", block.size))\" SPACE=\"\(block.space)\" LANGUAGE=\"\(block.language)\" PERMISSIONS=\"rx\"/>"
            )
        }
        lines.append("  </MEMORY_MAP>")
        lines.append("  <SYMBOL_TABLE>")
        for symbol in snapshot.symbols {
            lines.append(
                "    <SYMBOL ADDRESS=\"\(symbol.address)\" NAME=\"\(escape(symbol.name))\" TYPE=\"\(symbol.kind)\" SPACE=\"\(symbol.space)\"/>"
            )
        }
        lines.append("  </SYMBOL_TABLE>")
        lines.append("  <FUNCTIONS>")
        for function in snapshot.functions {
            lines.append(
                "    <FUNCTION ENTRY_POINT=\"\(function.address)\" NAME=\"\(escape(function.name))\" SIZE=\"\(function.size)\" SPACE=\"\(function.space)\"/>"
            )
        }
        lines.append("  </FUNCTIONS>")
        lines.append("  <MARK_REFS>")
        for xref in snapshot.xrefs {
            lines.append(
                "    <REF FROM=\"\(xref.fromAddress)\" TO=\"\(xref.toAddress)\" TYPE=\"\(xref.ghidraType)\" FROM_SPACE=\"\(xref.fromSpace)\" TO_SPACE=\"\(xref.toSpace)\" KIND=\"\(xref.kind)\"/>"
            )
        }
        lines.append("  </MARK_REFS>")
        lines.append("</PROGRAM>")
        return lines.joined(separator: "\n")
    }

    private static func hex(_ value: UInt64) -> String {
        String(format: "0x%08X", value)
    }

    private static func escape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static let pythonLoader = #"""
# LoadNewWorldROM.py
# @category NewWorld
# Apply NewWorldView analysis.json onto a Ghidra program.
# ROM bytes are not in the export: map your local MacROM at 0x50000000 first.

from __future__ import print_function
import json

json_file = askFile("NewWorldView analysis.json", "Load")
path = str(json_file.getAbsolutePath()) if hasattr(json_file, "getAbsolutePath") else str(json_file)
with open(path, "r") as handle:
    data = json.load(handle)

from ghidra.program.model.symbol import RefType, SourceType

refman = currentProgram.getReferenceManager()
space = currentProgram.getAddressFactory().getDefaultAddressSpace()

def to_addr(value):
    text = value
    if isinstance(value, str) and value.lower().startswith("0x"):
        text = value[2:]
    return space.getAddress(int(str(text), 16))

created_labels = 0
for symbol in data.get("symbols", []):
    try:
        a = to_addr(symbol["address"])
        name = str(symbol.get("name") or "sym")
        createLabel(a, name, False)
        created_labels += 1
    except Exception as exc:
        print("label skip", symbol.get("name"), exc)

created_fns = 0
for function in data.get("functions", []):
    try:
        a = to_addr(function["address"])
        name = str(function.get("name") or "sub")
        if getFunctionAt(a) is None:
            createFunction(a, name)
        created_fns += 1
    except Exception as exc:
        print("function skip", function.get("name"), exc)

created_refs = 0
for xref in data.get("xrefs", []):
    try:
        frm = to_addr(xref["fromAddress"])
        to = to_addr(xref["toAddress"])
        kind = str(xref.get("kind") or "jump")
        if kind in ("call", "trap"):
            rt = RefType.UNCONDITIONAL_CALL
        elif kind == "data":
            rt = RefType.DATA
        else:
            rt = RefType.UNCONDITIONAL_JUMP
        refman.addMemoryReference(frm, to, rt, SourceType.IMPORTED, 0)
        created_refs += 1
    except Exception as exc:
        print("xref skip", xref.get("fromAddress"), exc)

print("NewWorldView import: labels=%d functions=%d xrefs=%d" % (created_labels, created_fns, created_refs))
print("Expected PPC MacROM base 0x50000000; 68k Toolbox at 0x00000000.")
"""#
}

public struct GhidraSnapshot: Codable, Sendable, Equatable {
    public var format: String
    public var version: Int
    public var fileName: String
    public var fileSize: Int
    public var ppcMacROMBase: String
    public var blocks: [GhidraBlock]
    public var symbols: [GhidraSymbol]
    public var functions: [GhidraFunction]
    public var xrefs: [GhidraXRef]
}

public struct GhidraBlock: Codable, Sendable, Equatable {
    public var name: String
    public var space: String
    public var address: String
    public var size: Int
    public var nodeID: String
    public var isa: String?
    public var language: String
    public var romOffset: String?
    public var tags: [String]

    public init(
        name: String,
        space: String,
        address: String,
        size: Int,
        nodeID: String,
        isa: String?,
        language: String,
        romOffset: String? = nil,
        tags: [String] = []
    ) {
        self.name = name
        self.space = space
        self.address = address
        self.size = size
        self.nodeID = nodeID
        self.isa = isa
        self.language = language
        self.romOffset = romOffset
        self.tags = tags
    }
}

public struct GhidraSymbol: Codable, Sendable, Equatable {
    public var name: String
    public var space: String
    public var address: String
    public var kind: String
    public var nodeID: String
    public var romOffset: String?
    public var tags: [String]

    public init(
        name: String,
        space: String,
        address: String,
        kind: String,
        nodeID: String,
        romOffset: String? = nil,
        tags: [String] = []
    ) {
        self.name = name
        self.space = space
        self.address = address
        self.kind = kind
        self.nodeID = nodeID
        self.romOffset = romOffset
        self.tags = tags
    }
}

public struct GhidraFunction: Codable, Sendable, Equatable {
    public var name: String
    public var space: String
    public var address: String
    public var size: Int
    public var nodeID: String
    public var romOffset: String?
    public var tags: [String]

    public init(
        name: String,
        space: String,
        address: String,
        size: Int,
        nodeID: String,
        romOffset: String? = nil,
        tags: [String] = []
    ) {
        self.name = name
        self.space = space
        self.address = address
        self.size = size
        self.nodeID = nodeID
        self.romOffset = romOffset
        self.tags = tags
    }
}

public struct GhidraXRef: Codable, Sendable, Equatable {
    public var kind: String
    public var ghidraType: String
    public var fromSpace: String
    public var fromAddress: String
    public var toSpace: String
    public var toAddress: String
    public var fromSymbol: String?
    public var toSymbol: String?
    public var fromNodeID: String
    public var toNodeID: String?
    public var fromRomOffset: String?
    public var toRomOffset: String?

    public init(
        kind: String,
        ghidraType: String,
        fromSpace: String,
        fromAddress: String,
        toSpace: String,
        toAddress: String,
        fromSymbol: String?,
        toSymbol: String?,
        fromNodeID: String,
        toNodeID: String?,
        fromRomOffset: String? = nil,
        toRomOffset: String? = nil
    ) {
        self.kind = kind
        self.ghidraType = ghidraType
        self.fromSpace = fromSpace
        self.fromAddress = fromAddress
        self.toSpace = toSpace
        self.toAddress = toAddress
        self.fromSymbol = fromSymbol
        self.toSymbol = toSymbol
        self.fromNodeID = fromNodeID
        self.toNodeID = toNodeID
        self.fromRomOffset = fromRomOffset
        self.toRomOffset = toRomOffset
    }
}
