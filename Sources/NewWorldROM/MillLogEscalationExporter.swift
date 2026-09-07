import Foundation

public enum MillLogEscalationExporter {
    public static let defaultFocusMarkers = [
        "GetNewDialog",
        "NewDialog",
        "GetCCursor",
        "DialogDispatch",
        "DisposeDialog",
        "ModalDialog",
        "Launch A9F2",
        "LoadSeg A9F0",
        "PEF enter",
        "PEF import idx=",
        "PEF WaitNextEvent",
        "PEF dce",
        "PEF vol idx=",
        "SRR0=1010",
        "DAR=00015018",
        "xlate miss",
        "GetNewDialog id=",
        "stay CODE 66",
        "KEEP 68k hang",
        "68k map r24=",
        "68k spin r24="
    ]

    public static func relevantLines(
        from logURL: URL,
        focusMarkers: [String] = defaultFocusMarkers,
        limit: Int = 120
    ) throws -> String {
        let text = try MillLogReader.decompressedString(from: logURL)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let selected = lines.enumerated().compactMap { index, line -> String? in
            guard focusMarkers.contains(where: { line.contains($0) }) else { return nil }
            return String(format: "%5d: %@", index + 1, line)
        }
        if selected.isEmpty {
            return "(no focus markers matched in \(logURL.lastPathComponent))"
        }
        return selected.suffix(limit).joined(separator: "\n")
    }

    public static func buildPack(
        logURL: URL,
        address: ProgramAddress,
        parsed: ParsedROM,
        database: AnalysisDatabase,
        macROM: Data?,
        classification: MillClassification? = nil,
        annotation: MillAnnotation? = nil,
        macemuRepoPath: String? = nil
    ) throws -> MillEscalationPackBuilder.ExportBundle {
        let reachability = MillReachabilityEngine.analyze(target: address, database: database)
        let context = MillAnalysisContextBuilder.make(
            address: address,
            parsed: parsed,
            database: database,
            macROM: macROM,
            reachability: reachability
        )
        let excerpt = try relevantLines(from: logURL)
        return MillEscalationPackBuilder.build(
            context: context,
            classification: classification,
            annotation: annotation,
            macemuRepoPath: macemuRepoPath,
            logExcerpt: excerpt,
            sourceLogPath: logURL.path
        )
    }
}
