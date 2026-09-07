import Foundation

public enum MillReachabilityEngine {
    public static let defaultMaxPaths = 8
    public static let defaultMaxDepth = 16

    public static func analyze(
        target: ProgramAddress,
        database: AnalysisDatabase,
        maxPaths: Int = defaultMaxPaths,
        maxDepth: Int = defaultMaxDepth
    ) -> MillReachabilityReport {
        var paths: [[MillPathStep]] = []
        var touchesProtectedTrap = false
        var touchesGetNewDialogStub = false

        var frontier: [[MillPathStep]] = [[MillPathStep(address: target)]]
        var seenPathKeys = Set<String>()

        while !frontier.isEmpty, paths.count < maxPaths {
            let path = frontier.removeFirst()
            guard let head = path.first else { continue }
            let pathKey = path.map(\.address.key).joined(separator: ">")
            if !seenPathKeys.insert(pathKey).inserted { continue }

            let tags = AddressTranslation.millTags(for: head.address)
            if tags.contains("get-new-dialog-stub") {
                touchesGetNewDialogStub = true
            }
            if tags.contains("no-skip-ui-trap") || tags.contains("get-new-dialog-stub") {
                touchesProtectedTrap = true
            }
            if head.address.space == .toolboxTrap {
                let trap = UInt16(head.address.address & 0xFFFF)
                if ATrapTable.noSkipUITraps.contains(trap) {
                    touchesProtectedTrap = true
                }
            }
            for edge in database.xrefs(from: head.address) where edge.kind == .trap {
                if edge.to.space == .toolboxTrap {
                    let trap = UInt16(edge.to.address & 0xFFFF)
                    if ATrapTable.noSkipUITraps.contains(trap) {
                        touchesProtectedTrap = true
                    }
                }
            }

            if path.count > 1 {
                paths.append(path)
                if paths.count >= maxPaths { break }
            }

            guard path.count <= maxDepth else { continue }

            let incoming = database.xrefs(to: head.address)
                .filter { $0.kind == .call || $0.kind == .jump || $0.kind == .trap }
                .sorted { ($0.fromSymbol ?? $0.from.display) < ($1.fromSymbol ?? $1.from.display) }

            for edge in incoming {
                guard !path.contains(where: { $0.address.key == edge.from.key }) else { continue }
                let step = MillPathStep(
                    address: edge.from,
                    symbolName: edge.fromSymbol ?? database.symbol(at: edge.from)?.name,
                    edgeKind: edge.kind
                )
                frontier.append([step] + path)
            }
        }

        let verdict: MillReachabilityVerdict
        if touchesProtectedTrap || touchesGetNewDialogStub {
            verdict = .protectedPath
        } else if paths.isEmpty {
            verdict = .ambiguous
        } else {
            verdict = .safeCandidate
        }

        return MillReachabilityReport(
            verdict: verdict,
            paths: paths,
            touchesProtectedTrap: touchesProtectedTrap,
            touchesGetNewDialogStub: touchesGetNewDialogStub
        )
    }

    public static func pathTouchesProtectedTrap(_ path: [MillPathStep]) -> Bool {
        for step in path {
            let tags = AddressTranslation.millTags(for: step.address)
            if tags.contains("get-new-dialog-stub") || tags.contains("no-skip-ui-trap") {
                return true
            }
            if step.address.space == .toolboxTrap {
                let trap = UInt16(step.address.address & 0xFFFF)
                if ATrapTable.noSkipUITraps.contains(trap) {
                    return true
                }
            }
        }
        return false
    }
}
