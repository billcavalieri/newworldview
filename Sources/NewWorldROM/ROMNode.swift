import Foundation

public enum DisassemblyISA: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case powerPC
    case m68k

    public var displayName: String {
        switch self {
        case .powerPC: return "PowerPC"
        case .m68k: return "68000"
        }
    }
}

public enum ROMContentKind: Sendable, Equatable, Hashable {
    case folder
    case text
    case binary
    case disassemblable(DisassemblyISA)

    public var allowsText: Bool {
        switch self {
        case .folder, .text: return true
        case .binary, .disassemblable: return false
        }
    }

    public var allowsDisassembly: Bool {
        if case .disassemblable = self { return true }
        return false
    }

    public var isa: DisassemblyISA? {
        if case .disassemblable(let isa) = self { return isa }
        return nil
    }
}

public struct ROMNode: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let kind: ROMContentKind
    public let data: Data
    public let text: String?
    public let containerOffset: Int?
    public let runtimeAddress: UInt64?
    public let children: [ROMNode]
    public let metadata: [String: String]

    public init(
        id: String,
        name: String,
        kind: ROMContentKind,
        data: Data = Data(),
        text: String? = nil,
        containerOffset: Int? = nil,
        runtimeAddress: UInt64? = nil,
        children: [ROMNode] = [],
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.data = data
        self.text = text
        self.containerOffset = containerOffset
        self.runtimeAddress = runtimeAddress
        self.children = children
        self.metadata = metadata
    }

    public var size: Int { data.count }

    public func node(id: String) -> ROMNode? {
        if self.id == id { return self }
        for child in children {
            if let found = child.node(id: id) { return found }
        }
        return nil
    }

    /// IDs from this node down toward `targetID`, excluding the target itself.
    public func ancestorIDs(of targetID: String) -> [String]? {
        if id == targetID { return [] }
        for child in children {
            if child.id == targetID {
                return [id]
            }
            if let tail = child.ancestorIDs(of: targetID) {
                return [id] + tail
            }
        }
        return nil
    }

    public var descendants: [ROMNode] {
        [self] + children.flatMap(\.descendants)
    }

    public var displayText: String? {
        if let text, !text.isEmpty { return text }
        if kind == .text {
            return BinaryCursor.macRoman(data)
        }
        return nil
    }

    public func childID(_ component: String) -> String {
        id + "/" + component
    }

    public static func leaf(
        id: String,
        name: String,
        data: Data,
        kind: ROMContentKind? = nil,
        text: String? = nil,
        containerOffset: Int? = nil,
        runtimeAddress: UInt64? = nil,
        metadata: [String: String] = [:]
    ) -> ROMNode {
        let resolvedKind: ROMContentKind
        if let kind {
            resolvedKind = kind
        } else if data.looksLikeText {
            resolvedKind = .text
        } else {
            resolvedKind = .binary
        }
        return ROMNode(
            id: id,
            name: name,
            kind: resolvedKind,
            data: data,
            text: text,
            containerOffset: containerOffset,
            runtimeAddress: runtimeAddress,
            metadata: metadata
        )
    }
}

public struct ParsedROM: Sendable, Equatable {
    public let root: ROMNode
    public let fileName: String
    public let fileSize: Int
    public let warnings: [String]

    public init(root: ROMNode, fileName: String, fileSize: Int, warnings: [String] = []) {
        self.root = root
        self.fileName = fileName
        self.fileSize = fileSize
        self.warnings = warnings
    }
}
