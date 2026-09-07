import Foundation

public enum AddressSpace: String, Sendable, Hashable, Codable, CaseIterable {
    case ppcMacROM
    case m68kToolbox
    case toolboxTrap
    case pef
    case elf
    case unknown

    public var displayName: String {
        switch self {
        case .ppcMacROM: return "PPC MacROM"
        case .m68kToolbox: return "68k Toolbox"
        case .toolboxTrap: return "A-trap"
        case .pef: return "PEF"
        case .elf: return "ELF"
        case .unknown: return "Unknown"
        }
    }

    public var shortName: String {
        switch self {
        case .ppcMacROM: return "PPC"
        case .m68kToolbox: return "68K"
        case .toolboxTrap: return "TRAP"
        case .pef: return "PEF"
        case .elf: return "ELF"
        case .unknown: return "?"
        }
    }

    public var ghidraLanguage: String {
        switch self {
        case .ppcMacROM, .pef, .elf:
            return "PowerPC:BE:32:default"
        case .m68kToolbox, .toolboxTrap:
            return "68000:BE:32:default"
        case .unknown:
            return "DATA:BE:32:default"
        }
    }
}

public struct ProgramAddress: Hashable, Sendable, Codable {
    public var space: AddressSpace
    public var address: UInt64

    public init(space: AddressSpace, address: UInt64) {
        self.space = space
        self.address = address
    }

    public var key: String {
        "\(space.rawValue):\(String(address, radix: 16))"
    }

    public var display: String {
        "\(space.shortName):\(String(format: "%08X", address))"
    }
}

public enum XRefKind: String, Sendable, Hashable, Codable, CaseIterable {
    case call
    case jump
    case trap
    case data
    case importRef = "import"
    case exportRef = "export"

    public var displayName: String {
        switch self {
        case .call: return "call"
        case .jump: return "jump"
        case .trap: return "A-trap"
        case .data: return "data"
        case .importRef: return "import"
        case .exportRef: return "export"
        }
    }

    public var ghidraRefType: String {
        switch self {
        case .call: return "UNCONDITIONAL_CALL"
        case .jump: return "UNCONDITIONAL_JUMP"
        case .trap: return "CALL_OVERRIDE_UNCONDITIONAL"
        case .data: return "DATA"
        case .importRef: return "EXTERNAL_REF"
        case .exportRef: return "DATA"
        }
    }
}

public enum SymbolKind: String, Sendable, Hashable, Codable, CaseIterable {
    case function
    case label
    case trap
    case data
    case importSym = "import"
    case exportSym = "export"

    public var displayName: String {
        switch self {
        case .function: return "function"
        case .label: return "label"
        case .trap: return "trap"
        case .data: return "data"
        case .importSym: return "import"
        case .exportSym: return "export"
        }
    }
}

public struct ProgramSymbol: Hashable, Sendable, Codable, Identifiable {
    public var id: String { address.key + "/" + name }
    public var address: ProgramAddress
    public var name: String
    public var kind: SymbolKind
    public var nodeID: String

    public init(address: ProgramAddress, name: String, kind: SymbolKind, nodeID: String) {
        self.address = address
        self.name = name
        self.kind = kind
        self.nodeID = nodeID
    }
}

public struct RecoveredFunction: Hashable, Sendable, Codable, Identifiable {
    public var id: String { address.key }
    public var address: ProgramAddress
    public var name: String
    public var size: Int
    public var nodeID: String

    public init(address: ProgramAddress, name: String, size: Int, nodeID: String) {
        self.address = address
        self.name = name
        self.size = size
        self.nodeID = nodeID
    }
}

public struct XRef: Hashable, Sendable, Codable, Identifiable {
    public var id: String {
        "\(from.key)>\(to.key):\(kind.rawValue)"
    }

    public var from: ProgramAddress
    public var to: ProgramAddress
    public var kind: XRefKind
    public var fromNodeID: String
    public var toNodeID: String?
    public var fromSymbol: String?
    public var toSymbol: String?

    public init(
        from: ProgramAddress,
        to: ProgramAddress,
        kind: XRefKind,
        fromNodeID: String,
        toNodeID: String? = nil,
        fromSymbol: String? = nil,
        toSymbol: String? = nil
    ) {
        self.from = from
        self.to = to
        self.kind = kind
        self.fromNodeID = fromNodeID
        self.toNodeID = toNodeID
        self.fromSymbol = fromSymbol
        self.toSymbol = toSymbol
    }
}

public struct MemoryBlock: Hashable, Sendable, Codable, Identifiable {
    public var id: String { address.key + "/" + name }
    public var name: String
    public var address: ProgramAddress
    public var size: Int
    public var nodeID: String
    public var isa: DisassemblyISA?

    public init(name: String, address: ProgramAddress, size: Int, nodeID: String, isa: DisassemblyISA?) {
        self.name = name
        self.address = address
        self.size = size
        self.nodeID = nodeID
        self.isa = isa
    }
}

public struct AnalysisDatabase: Sendable, Equatable {
    public var blocks: [MemoryBlock]
    public var symbols: [ProgramSymbol]
    public var functions: [RecoveredFunction]
    public var xrefs: [XRef]

    public var symbolByKey: [String: ProgramSymbol]
    public var xrefsFrom: [String: [XRef]]
    public var xrefsTo: [String: [XRef]]
    public var blockByNodeID: [String: MemoryBlock]

    public init(
        blocks: [MemoryBlock] = [],
        symbols: [ProgramSymbol] = [],
        functions: [RecoveredFunction] = [],
        xrefs: [XRef] = []
    ) {
        self.blocks = blocks
        self.symbols = symbols
        self.functions = functions
        self.xrefs = xrefs
        var symbolByKey: [String: ProgramSymbol] = [:]
        for symbol in symbols {
            if symbolByKey[symbol.address.key] == nil || symbol.kind == .trap || symbol.name.contains("GetNewDialog_stub") {
                symbolByKey[symbol.address.key] = symbol
            }
        }
        self.symbolByKey = symbolByKey
        var xrefsFrom: [String: [XRef]] = [:]
        var xrefsTo: [String: [XRef]] = [:]
        for xref in xrefs {
            xrefsFrom[xref.from.key, default: []].append(xref)
            xrefsTo[xref.to.key, default: []].append(xref)
        }
        self.xrefsFrom = xrefsFrom
        self.xrefsTo = xrefsTo
        var blockByNodeID: [String: MemoryBlock] = [:]
        for block in blocks {
            blockByNodeID[block.nodeID] = block
        }
        self.blockByNodeID = blockByNodeID
    }

    public static let empty = AnalysisDatabase()

    public func xrefs(from address: ProgramAddress) -> [XRef] {
        xrefsFrom[address.key] ?? []
    }

    public func xrefs(to address: ProgramAddress) -> [XRef] {
        xrefsTo[address.key] ?? []
    }

    public func symbol(at address: ProgramAddress) -> ProgramSymbol? {
        symbolByKey[address.key]
    }

    public func block(forNodeID id: String) -> MemoryBlock? {
        blockByNodeID[id]
    }
}

