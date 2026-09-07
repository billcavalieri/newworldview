import Foundation
import NewWorldROM

enum AnalysisSelection: Equatable, Hashable, Identifiable {
    case function(String)
    case xref(String)
    case trap(String)

    var id: String {
        switch self {
        case .function(let id): return "function:\(id)"
        case .xref(let id): return "xref:\(id)"
        case .trap(let id): return "trap:\(id)"
        }
    }
}

enum AnalysisSelectionResolver {
    static func selection(
        for address: ProgramAddress,
        nodeID: ROMNode.ID,
        in database: AnalysisDatabase
    ) -> AnalysisSelection? {
        if let function = database.functions.first(where: { $0.address == address && $0.nodeID == nodeID }) {
            return .function(function.id)
        }

        let outgoing = database.xrefs(from: address).filter { $0.fromNodeID == nodeID }
        if let trap = outgoing.first(where: { $0.kind == .trap }) {
            return .trap(trap.id)
        }
        if let xref = outgoing.first {
            return .xref(xref.id)
        }

        if let function = enclosingFunction(for: address, nodeID: nodeID, in: database) {
            return .function(function.id)
        }

        if let function = database.functions.first(where: { $0.address == address }) {
            return .function(function.id)
        }
        return nil
    }

    private static func enclosingFunction(
        for address: ProgramAddress,
        nodeID: ROMNode.ID,
        in database: AnalysisDatabase
    ) -> RecoveredFunction? {
        database.functions
            .filter { $0.nodeID == nodeID && $0.address.space == address.space && $0.size > 0 }
            .first { function in
                let start = function.address.address
                let end = start + UInt64(function.size)
                return address.address >= start && address.address < end
            }
    }

    static func navigationTarget(
        for selection: AnalysisSelection,
        in database: AnalysisDatabase
    ) -> (ROMNode.ID, ProgramAddress)? {
        switch selection {
        case .function(let id):
            guard let function = database.functions.first(where: { $0.id == id }) else { return nil }
            return (function.nodeID, function.address)
        case .xref(let id), .trap(let id):
            guard let xref = database.xrefs.first(where: { $0.id == id }) else { return nil }
            return (xref.fromNodeID, xref.from)
        }
    }
}
