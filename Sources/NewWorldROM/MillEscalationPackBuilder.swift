import Foundation

public enum MillEscalationPackBuilder {
    public struct ExportBundle: Sendable, Equatable {
        public var packMarkdown: String
        public var promptMarkdown: String
    }

    public static func build(
        context: MillAnalysisContext,
        classification: MillClassification?,
        annotation: MillAnnotation?,
        macemuRepoPath: String? = nil,
        logExcerpt: String? = nil,
        sourceLogPath: String? = nil
    ) -> ExportBundle {
        let pack = packMarkdown(
            context: context,
            classification: classification,
            annotation: annotation,
            logExcerpt: logExcerpt,
            sourceLogPath: sourceLogPath
        )
        let prompt = promptMarkdown(packPath: "pack-escalation.md", macemuRepoPath: macemuRepoPath)
        return ExportBundle(packMarkdown: pack, promptMarkdown: prompt)
    }

    public static func write(
        bundle: ExportBundle,
        to directory: URL
    ) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try bundle.packMarkdown.write(
            to: directory.appendingPathComponent("pack-escalation.md"),
            atomically: true,
            encoding: .utf8
        )
        try bundle.promptMarkdown.write(
            to: directory.appendingPathComponent("grok-prompt.md"),
            atomically: true,
            encoding: .utf8
        )
    }

    private static func packMarkdown(
        context: MillAnalysisContext,
        classification: MillClassification?,
        annotation: MillAnnotation?,
        logExcerpt: String? = nil,
        sourceLogPath: String? = nil
    ) -> String {
        var lines: [String] = []
        lines.append("# NewWorldView grok pack (escalation)")
        lines.append("")
        lines.append("Grok Build headless mill context for one ambiguous skip-68k address.")
        lines.append("NewWorldView facts below are authoritative; do not invent addresses.")
        lines.append("")
        lines.append("## Job")
        lines.append("")
        lines.append("- Review the address under investigation for macemu skip-68k KEEP/REVERT.")
        lines.append("- If milling C++ is warranted, edit only ppc-cpu.cpp and/or mill_apply.py.")
        lines.append("- Do not skip GetNewDialog overlay / DialogDispatch UI path or NO_SKIP A-traps.")
        lines.append("")
        lines.append("## HARD")
        lines.append("")
        lines.append("- do not skip 0x3264fc / 0x326564 / 0x326568")
        lines.append("- do not skip-68k UI path 0x5c86c-0x5c8c0 (GetNewDialog overlay / DialogDispatch/SetPort/DisposeDialog)")
        lines.append("- do not skip-68k A-lines GetNewDialog/NewDialog/DialogDispatch/SetPort/DisposeDialog/CloseRgn/OpenResFile/GetResource/InitCursor/GetEOF/GetFPos/Read/SetFPos/ModalDialog")
        lines.append("- do not skip-68k CODE 66 fall-through helper 0x9440-0x94cf (kajr false path — not G3 installer)")
        lines.append("- do not skip-68k $a190 data 0x16de8-0x16e20")
        lines.append(contentsOf: pefHardRules(from: logExcerpt))
        lines.append("- LoadSeg seg=66 / kajr 4.x Modem Scripts Installer is a false path — do not LoadSeg 66 from rsrc offset 0x\(String(format: "%X", G3MillClassification.loadSegKajrRsrcOffset))")
        lines.append("- GetNewDialog id=\(G3MillClassification.overlayResourceID) overlay (pc=0x5005C86E) is not on toast; real Splash is id=\(G3MillClassification.splashResourceID) (\(G3MillClassification.splashWindowSize.width)×\(G3MillClassification.splashWindowSize.height)). KEEP 16527 banner is \(G3MillClassification.keepBannerSize.width)×\(G3MillClassification.keepBannerSize.height). Overlay ≠ WINDOW.")
        lines.append("- Do not count host `Splash 510 even dlg=` as PEF GetNewDialog 510; only toast id=510 / pc=1010… counts.")
        lines.append("")
        let launch = logExcerpt?.contains("Launch A9F2") == true
        let loadSeg66 = logExcerpt?.contains("LoadSeg A9F0 enter seg=66") == true
        lines.append(ToastCatalogLookup.markdownSection(launchA9F2: launch, loadSeg66: loadSeg66))
        lines.append("")
        if let sourceLogPath {
            lines.append("## Source log")
            lines.append("")
            lines.append("- path: `\(sourceLogPath)`")
            lines.append("")
        }
        if let logExcerpt, !logExcerpt.isEmpty {
            lines.append("## Log excerpt")
            lines.append("")
            lines.append("```")
            lines.append(logExcerpt)
            lines.append("```")
            lines.append("")
        }
        lines.append("## Address under review")
        lines.append("")
        lines.append(MillAnalysisContextBuilder.markdown(from: context))
        lines.append("")
        lines.append("## Apple FM verdict")
        lines.append("")
        if let classification {
            lines.append("- kind: \(classification.kind.rawValue)")
            lines.append("- action: \(classification.recommendedAction.rawValue)")
            lines.append("- confidence: \(String(format: "%.2f", classification.confidence))")
            lines.append("- reasoning: \(classification.reasoning)")
            if !classification.evidenceUsed.isEmpty {
                lines.append("- evidence: \(classification.evidenceUsed.joined(separator: ", "))")
            }
        } else {
            lines.append("(no model classification — deterministic review only)")
        }
        if let annotation {
            lines.append("- annotationStatus: \(annotation.status.rawValue)")
            lines.append("- annotationSource: \(annotation.source.rawValue)")
        }
        lines.append("")
        lines.append("## Open question for Grok Build")
        lines.append("")
        lines.append("Should this site be a skip-68k KEEP candidate, REVERT/protected, or need a different mill kind?")
        lines.append("Cite the incoming xrefs and traps above.")
        return lines.joined(separator: "\n")
    }

    private static func pefHardRules(from excerpt: String?) -> [String] {
        var events = G3MillClassification.EventCounts()
        if let excerpt {
            for line in excerpt.split(separator: "\n", omittingEmptySubsequences: false) {
                events.record(line: String(line))
            }
        }
        var lines: [String] = [
            "- Launch A9F2 CFM Upgrader (0xA9F2) is the live G3 path; mill hosted InterfaceLib PEF by stamp phase, not ROM skip-68k map",
            "- PEF plant base 0x\(String(format: "%X", G3PEFPlantMap.plantBase)), code entry 0x\(String(format: "%X", G3PEFPlantMap.codeEntryPC)) — map pc=1010xxxx → section + toast offset (replaces Python dump per mill)",
        ]
        switch events.pefPhase {
        case .waitNextEvent:
            lines.append("- PEF WaitNextEvent is live — do not re-tip KEEP 16527/16533 InterfaceLib import idx=; next is PEF GetNewDialog 510 after wait returns 0")
        case .dce:
            lines.append("- PEF dce plant is live — `.vfc` driver path before WaitNextEvent; not import-idx escalation")
        case .vol:
            lines.append("- PEF vol idx= is live — volume setup in hosted InterfaceLib")
        case .imports:
            lines.append("- PEF import idx= is live — map r3/pc via plant sections; not +2 skip-68k ROM map")
        case .enter:
            lines.append("- PEF enter is live — next import idx= / xlate miss ners; not skip-68k leftover")
        case .none:
            lines.append("- Next after Launch A9F2: PEF enter + hosted imports (not blr stubs, not cfm-aa5a sel=65532)")
        }
        if !events.hostedLocationSamples.isEmpty {
            lines.append("- Hosted PEF locations: \(events.hostedLocationSamples.prefix(3).joined(separator: "; "))")
        }
        return lines
    }

    private static func promptMarkdown(packPath: String, macemuRepoPath: String?) -> String {
        let cwd = macemuRepoPath ?? "$MACEMU_REPO"
        return """
        You are milling SheepShaver toward Mac OS 9.2.1 G3 in this repo.
        Grok Build headless review. One analysis pass only, then stop.

        Read \(packPath) in the output folder and answer the open question.
        If a C++ mill is warranted, edit only:
        - SheepShaver/src/kpx_cpu/src/cpu/ppc/ppc-cpu.cpp
        - research-score/g3_driver/mill_apply.py

        Do not launch SheepShaver. Do not git commit. Do not commit ROM/disk.
        Do not skip-68k protected UI paths or NO_SKIP A-traps listed in the pack.

        Working directory: \(cwd)

        When done, print exactly:
        MILL_APPLIED=yes KIND=...
        or
        MILL_APPLIED=no REASON=...
        """
    }
}
