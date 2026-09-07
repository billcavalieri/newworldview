import Foundation

public enum CallPathTracer {
    public struct PathStep: Sendable, Equatable, Identifiable {
        public var id: String { address.key }
        public var address: ProgramAddress
        public var symbolName: String?
        public var edgeKind: XRefKind?
        public var depth: Int
    }

    public static func traceToHeartbeatCluster(
        from start: ProgramAddress,
        database: AnalysisDatabase,
        maxDepth: Int = 24
    ) -> [PathStep] {
        trace(
            from: start,
            database: database,
            maxDepth: maxDepth,
            stopWhen: { AddressTranslation.isHeartbeatCluster($0.address) }
        )
    }

    public static func trace(
        from start: ProgramAddress,
        database: AnalysisDatabase,
        maxDepth: Int = 16,
        stopWhen: (ProgramAddress) -> Bool = { _ in false }
    ) -> [PathStep] {
        var path: [PathStep] = [
            PathStep(
                address: start,
                symbolName: database.symbol(at: start)?.name,
                edgeKind: nil,
                depth: 0
            )
        ]
        var current = start
        var visited = Set<String>([start.key])

        for depth in 1...maxDepth {
            if stopWhen(current) { break }
            let incoming = database.xrefs(to: current)
                .filter { $0.kind == .call || $0.kind == .jump || $0.kind == .trap }
                .sorted { ($0.fromSymbol ?? "") < ($1.fromSymbol ?? "") }
            guard let edge = incoming.first(where: { !visited.contains($0.from.key) }) ?? incoming.first else {
                break
            }
            current = edge.from
            visited.insert(current.key)
            path.append(
                PathStep(
                    address: current,
                    symbolName: edge.fromSymbol ?? database.symbol(at: current)?.name,
                    edgeKind: edge.kind,
                    depth: depth
                )
            )
        }
        return path
    }
}
