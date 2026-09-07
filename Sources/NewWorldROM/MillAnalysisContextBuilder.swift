import Foundation

public enum MillAnalysisContextBuilder {
    public static let defaultIncomingLimit = 8
    public static let defaultDisasmLineLimit = 12
    public static let defaultPathStepLimit = 8
    public static let defaultContextBytes = 48

    public static func make(
        address: ProgramAddress,
        parsed: ParsedROM,
        database: AnalysisDatabase,
        macROM: Data?,
        logHits: Int? = nil,
        logLine: String? = nil,
        deterministicHint: String? = nil,
        reachability: MillReachabilityReport? = nil
    ) -> MillAnalysisContext {
        let lookup = AnalysisLookup.lookup(address, in: parsed, database: database)
        let path = CallPathTracer.traceToHeartbeatCluster(from: address, database: database)
        let incoming = lookup.incomingXRefs.prefix(defaultIncomingLimit).map {
            MillXRefSummary(
                fromDisplay: $0.from.display,
                kind: $0.kind,
                fromSymbol: $0.fromSymbol
            )
        }
        let outgoingTraps = trapNames(from: lookup.outgoingXRefs)
        let disasm = disasmLines(
            at: address,
            parsed: parsed,
            macROM: macROM,
            limit: defaultDisasmLineLimit
        )
        let heartbeatPath = path.prefix(defaultPathStepLimit).map {
            MillPathStep(address: $0.address, symbolName: $0.symbolName, edgeKind: $0.edgeKind)
        }

        return MillAnalysisContext(
            address: address,
            romOffset: lookup.romOffset,
            nodeName: lookup.nodeName,
            symbolName: lookup.symbol?.name,
            logHits: logHits,
            logLine: logLine,
            tags: lookup.tags,
            incomingXrefs: Array(incoming),
            outgoingTraps: outgoingTraps,
            disasmLines: disasm,
            heartbeatPath: Array(heartbeatPath),
            reachability: reachability,
            deterministicHint: deterministicHint
        )
    }

    public static func make(
        from logLine: String,
        parsed: ParsedROM,
        database: AnalysisDatabase,
        macROM: Data?,
        logHits: Int? = nil,
        deterministicHint: String? = nil,
        reachability: MillReachabilityReport? = nil
    ) -> MillAnalysisContext? {
        guard let address = MillLogParser.parseLogLine(logLine) else { return nil }
        return make(
            address: address,
            parsed: parsed,
            database: database,
            macROM: macROM,
            logHits: logHits,
            logLine: logLine,
            deterministicHint: deterministicHint,
            reachability: reachability
        )
    }

    public static func logHits(
        for address: ProgramAddress,
        in report: MillResearchEngine.HistoricalReport?
    ) -> Int? {
        guard let report else { return nil }
        guard let offset = AddressTranslation.romOffset(fromVirtual: address.address, space: address.space)
            ?? (address.space == .m68kToolbox ? address.address : nil)
        else { return nil }

        switch address.space {
        case .m68kToolbox:
            return report.top68kOffsets.first(where: { $0.offset == offset })?.count
        case .ppcMacROM:
            return report.topPPCOffsets.first(where: { $0.offset == offset })?.count
        default:
            return nil
        }
    }

    public static func deterministicHint(
        for address: ProgramAddress,
        in report: MillResearchEngine.HistoricalReport?
    ) -> String? {
        guard let report else { return nil }
        guard let offset = AddressTranslation.romOffset(fromVirtual: address.address, space: address.space)
            ?? (address.space == .m68kToolbox ? address.address : nil)
        else { return nil }

        let entries = address.space == .m68kToolbox ? report.top68kOffsets : report.topPPCOffsets
        return entries.first(where: { $0.offset == offset })?.recommendation
    }

    public static func toastCatalogNotes(
        launchA9F2: Bool = false,
        loadSeg66: Bool = false
    ) -> [String] {
        ToastCatalogLookup.millContextLines(launchA9F2: launchA9F2, loadSeg66: loadSeg66)
    }

    public static func markdown(from context: MillAnalysisContext) -> String {
        var lines: [String] = []
        lines.append("# NewWorldView grok pack")
        if let logLine = context.logLine {
            lines.append("logLine: \(logLine)")
        }
        lines.append("address: \(context.address.display)")
        if let romOffset = context.romOffset {
            lines.append("romOffset: 0x\(String(format: "%X", romOffset))")
        }
        if let nodeName = context.nodeName {
            lines.append("node: \(nodeName)")
        }
        if let symbolName = context.symbolName {
            lines.append("symbol: \(symbolName)")
        }
        if let logHits = context.logHits {
            lines.append("logHits: \(logHits)")
        }
        if !context.tags.isEmpty {
            lines.append("tags: \(context.tags.joined(separator: ", "))")
        }
        if let hint = context.deterministicHint {
            lines.append("deterministicHint: \(hint)")
        }
        if context.tags.contains("get-new-dialog-stub") {
            lines.append("getNewDialogClass: overlay id=\(G3MillClassification.overlayResourceID) (not on toast); Splash id=\(G3MillClassification.splashResourceID) is \(G3MillClassification.splashWindowSize.width)×\(G3MillClassification.splashWindowSize.height)")
        }
        if context.tags.contains("code66-helper") {
            lines.append("code66Class: \(G3MillClassification.loadSeg66FalsePathLabel)")
        }
        if let reachability = context.reachability {
            lines.append("reachability: \(reachability.verdict.rawValue)")
        }
        lines.append("")
        lines.append("## Static path toward heartbeat cluster")
        if context.heartbeatPath.isEmpty {
            lines.append("- (none)")
        } else {
            for step in context.heartbeatPath {
                let edge = step.edgeKind.map { " (\($0.displayName))" } ?? ""
                lines.append("- \(step.address.display) \(step.symbolName ?? "")\(edge)")
            }
        }
        lines.append("")
        lines.append("## Disassembly")
        if context.disasmLines.isEmpty {
            lines.append("(none)")
        } else {
            lines.append(contentsOf: context.disasmLines)
        }
        lines.append("")
        lines.append("## Incoming xrefs")
        if context.incomingXrefs.isEmpty {
            lines.append("- (none)")
        } else {
            for xref in context.incomingXrefs {
                let symbol = xref.fromSymbol.map { " \($0)" } ?? ""
                lines.append("- \(xref.fromDisplay) \(xref.kind.displayName)\(symbol)")
            }
        }
        if !context.outgoingTraps.isEmpty {
            lines.append("")
            lines.append("## Outgoing traps")
            lines.append(context.outgoingTraps.joined(separator: ", "))
        }
        let launch = context.logLine?.contains("Launch A9F2") == true
        let loadSeg66 = context.logLine?.contains("LoadSeg A9F0 enter seg=66") == true
        let toastNotes = toastCatalogNotes(launchA9F2: launch, loadSeg66: loadSeg66)
        if !toastNotes.isEmpty {
            lines.append("")
            lines.append("## Toast catalog (ResViewer)")
            for note in toastNotes {
                lines.append("- \(note)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func trapNames(from xrefs: [XRef]) -> [String] {
        var names: [String] = []
        var seen = Set<String>()
        for xref in xrefs where xref.kind == .trap {
            let name = xref.toSymbol ?? xref.to.display
            if seen.insert(name).inserted {
                names.append(name)
            }
        }
        return names
    }

    static func disasmLines(
        at address: ProgramAddress,
        parsed: ParsedROM,
        macROM: Data?,
        limit: Int
    ) -> [String] {
        guard let bytes = bytes(at: address, parsed: parsed, macROM: macROM, count: defaultContextBytes) else {
            return []
        }
        let isa: DisassemblyISA = address.space == .m68kToolbox || address.space == .toolboxTrap ? .m68k : .powerPC
        let result = DisassemblyService.disassemble(bytes, isa: isa, baseAddress: address.address, byteLimit: bytes.count)
        return result.instructions.prefix(limit).map(\.formatted)
    }

    static func bytes(at address: ProgramAddress, parsed: ParsedROM, macROM: Data?, count: Int) -> Data? {
        if let node = AnalysisLookup.findNode(containing: address, in: parsed.root),
           let offset = AnalysisEngine.byteOffset(for: address, in: node) {
            let end = min(node.data.count, offset + count)
            return node.data.subdata(in: offset..<end)
        }
        if address.space == .ppcMacROM,
           let romOffset = AddressTranslation.romOffset(fromVirtual: address.address),
           let macROM,
           Int(romOffset) + count <= macROM.count {
            return macROM.subdata(in: Int(romOffset)..<(Int(romOffset) + count))
        }
        return nil
    }
}
