import Foundation

public enum AnalysisLookup {
    public struct LookupResult: Sendable, Equatable {
        public var address: ProgramAddress
        public var romOffset: UInt64?
        public var nodeID: String?
        public var nodeName: String?
        public var symbol: ProgramSymbol?
        public var function: RecoveredFunction?
        public var tags: [String]
        public var incomingXRefs: [XRef]
        public var outgoingXRefs: [XRef]
    }

    public static func lookup(_ text: String, in parsed: ParsedROM, database: AnalysisDatabase) -> LookupResult? {
        guard let parsedAddress = AddressTranslation.parse(text) else { return nil }
        return lookup(parsedAddress.programAddress, in: parsed, database: database)
    }

    public static func lookup(_ address: ProgramAddress, in parsed: ParsedROM, database: AnalysisDatabase) -> LookupResult {
        let romOffset = AddressTranslation.romOffset(fromVirtual: address.address, space: address.space)
            ?? (address.space == .m68kToolbox ? address.address : nil)
        let node = findNode(containing: address, in: parsed.root)
        return LookupResult(
            address: address,
            romOffset: romOffset,
            nodeID: node?.id,
            nodeName: node?.name,
            symbol: database.symbol(at: address),
            function: enclosingFunction(for: address, in: database),
            tags: AddressTranslation.millTags(for: address),
            incomingXRefs: database.xrefs(to: address),
            outgoingXRefs: database.xrefs(from: address)
        )
    }

    public static func navigationTarget(
        for address: ProgramAddress,
        in parsed: ParsedROM
    ) -> (ROMNode.ID, ProgramAddress)? {
        guard let node = findNode(containing: address, in: parsed.root) else { return nil }
        return (node.id, address)
    }

    public static func findNode(containing address: ProgramAddress, in root: ROMNode) -> ROMNode? {
        for node in root.descendants where node.children.isEmpty {
            guard let isa = node.kind.isa else { continue }
            if AnalysisEngine.byteOffset(for: address, in: node) != nil {
                return node
            }
            let space = AnalysisEngine.space(for: node, isa: isa)
            let base = AnalysisEngine.baseAddress(for: node, space: space)
            if address.space == space,
               address.address >= base,
               address.address < base + UInt64(node.data.count) {
                return node
            }
        }
        return nil
    }

    public static func enclosingFunction(for address: ProgramAddress, in database: AnalysisDatabase) -> RecoveredFunction? {
        database.functions
            .filter { $0.address.space == address.space && $0.address.address <= address.address }
            .max(by: { $0.address.address < $1.address.address })
    }
}
