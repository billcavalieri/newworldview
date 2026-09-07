import Foundation

/// G3 installer / toast-catalog classification for mill log research (ResViewer parity).
public enum G3MillClassification {
    public static let loadSeg66FalsePathLabel = "kajr 4.x / Modem Scripts Installer — not G3"

    /// Toast `Mac OS Install` CFM Upgrader (KEEP 16511/16518/16527 live path).
    public static let cfmUpgraderLaunchTrap: UInt16 = 0xA9F2
    public static let loadSegTrap: UInt16 = 0xA9F0

    /// Overlay GetNewDialog id from planted ROM stub — not on the toast fork.
    public static let overlayResourceID = 59840
    public static let overlayVirtualPC: UInt64 = 0x5005_C86E

    /// Real installer Splash DLOG from toast `Mac OS Install` (354×266).
    public static let splashResourceID = 510
    public static let splashWindowSize = (width: 354, height: 266)

    /// KEEP 16527 banner — not the Splash WINDOW.
    public static let keepBannerSize = (width: 506, height: 44)

    /// Do not LoadSeg seg=66 from kajr toast rsrc offset.
    public static let loadSegKajrRsrcOffset: UInt64 = 112_182_784

    /// xlate miss FourCC `ners` → GetResource id 500 in Mac OS Install.
    public static let nersFourCC: UInt32 = 0x6E65_7273
    public static let nersResourceID = 500

    public enum GetNewDialogKind: Sendable, Equatable {
        case overlayNotInToast
        case realSplash
        case other(id: Int)
    }

    public enum PEFMillPhase: Sendable, Equatable, Comparable {
        case none
        case enter
        case imports
        case vol
        case dce
        case waitNextEvent

        public static func < (lhs: PEFMillPhase, rhs: PEFMillPhase) -> Bool {
            lhs.rank < rhs.rank
        }

        private var rank: Int {
            switch self {
            case .none: return 0
            case .enter: return 1
            case .imports: return 2
            case .vol: return 3
            case .dce: return 4
            case .waitNextEvent: return 5
            }
        }
    }

    public struct EventCounts: Sendable, Equatable {
        public var pefEnterCount: Int = 0
        public var pefImportCount: Int = 0
        public var pefWaitNextEventCount: Int = 0
        public var pefDceCount: Int = 0
        public var pefVolCount: Int = 0
        public var pefHostedDSICount: Int = 0
        public var getNewDialogOverlayHits: Int = 0
        public var getNewDialogSplashHits: Int = 0
        public var xlateMissNersCount: Int = 0
        public var hostedLocationSamples: [String] = []

        public init() {}

        public mutating func record(line: String) {
            if isPEFEnter(line) {
                pefEnterCount += 1
            }
            if line.localizedCaseInsensitiveContains("pef import idx=") {
                pefImportCount += 1
                recordHostedAddress(in: line, key: "r3=")
            }
            if line.localizedCaseInsensitiveContains("pef waitnextevent") {
                pefWaitNextEventCount += 1
                recordHostedAddress(in: line, key: "r3=")
            }
            if line.localizedCaseInsensitiveContains("pef dce") {
                pefDceCount += 1
                recordHostedAddress(in: line, key: "h=")
            }
            if line.localizedCaseInsensitiveContains("pef vol idx=") {
                pefVolCount += 1
                recordHostedAddress(in: line, key: "r3=")
            }
            if let groups = firstMatchGroups(
                in: line,
                pattern: #"SRR0=([0-9a-fA-F]+).*(?:DAR|dar)=([0-9a-fA-F]+)"#
            ), groups.count >= 2,
               let srr0 = parseHex(groups[0]),
               G3PEFPlantMap.isHosted(srr0) {
                pefHostedDSICount += 1
                let dar = parseHex(groups[1])
                appendSample(G3PEFPlantMap.describeFault(srr0: srr0, dar: dar))
            } else if let srr0Text = firstMatch(in: line, pattern: #"SRR0=([0-9a-fA-F]+)"#),
                      let srr0 = parseHex(srr0Text),
                      G3PEFPlantMap.isHosted(srr0) {
                pefHostedDSICount += 1
                appendSample(G3PEFPlantMap.describeFault(srr0: srr0, dar: nil))
            }

            if isXlateMissNers(line) {
                xlateMissNersCount += 1
            }

            switch classifyGetNewDialog(line: line) {
            case .overlayNotInToast:
                getNewDialogOverlayHits += 1
            case .realSplash:
                getNewDialogSplashHits += 1
            case .other, .none:
                break
            }
        }

        public var pefPhase: PEFMillPhase {
            Self.pefPhase(
                enter: pefEnterCount,
                imports: pefImportCount,
                vol: pefVolCount,
                dce: pefDceCount,
                wait: pefWaitNextEventCount
            )
        }

        public static func pefPhase(
            enter: Int,
            imports: Int,
            vol: Int,
            dce: Int,
            wait: Int
        ) -> PEFMillPhase {
            if wait > 0 { return .waitNextEvent }
            if dce > 0 { return .dce }
            if vol > 0 { return .vol }
            if imports > 0 { return .imports }
            if enter > 0 { return .enter }
            return .none
        }

        private mutating func recordHostedAddress(in line: String, key: String) {
            let escapedKey = NSRegularExpression.escapedPattern(for: key)
            guard let valueText = firstMatch(in: line, pattern: "\(escapedKey)([0-9a-fA-F]+)"),
                  let value = parseHex(valueText),
                  G3PEFPlantMap.isHosted(value) else { return }
            appendSample(G3PEFPlantMap.format(value))
        }

        private mutating func appendSample(_ sample: String) {
            guard !sample.isEmpty, !hostedLocationSamples.contains(sample) else { return }
            guard hostedLocationSamples.count < 8 else { return }
            hostedLocationSamples.append(sample)
        }
    }

    public enum ToastCatalogRole: String, Sendable {
        case macOSInstall = "Mac OS Install"
        case kajrInstaller = "kajr 4.x / Modem Scripts Installer"
        case installMacOS921 = "Install Mac OS 9.2.1 document"

        public var millNote: String {
            switch self {
            case .macOSInstall:
                return "Toast catalog: Mac OS Install — CFM Upgrader Launch A9F2 is the live G3 path."
            case .kajrInstaller:
                return "Toast catalog: kajr Installer — LoadSeg seg=66 false path; not the G3 installer."
            case .installMacOS921:
                return "Toast catalog: Install Mac OS 9.2.1 document — host-side resources, not ROM LoadSeg 66."
            }
        }
    }

    public static func toastRole(launchA9F2: Bool, loadSeg66: Bool) -> ToastCatalogRole? {
        if launchA9F2 { return .macOSInstall }
        if loadSeg66 { return .kajrInstaller }
        return nil
    }

    public static func classifyGetNewDialog(line: String) -> GetNewDialogKind? {
        guard line.localizedCaseInsensitiveContains("getnewdialog") else { return nil }

        // Host splash plant (`Splash 510 even dlg=`) is not PEF GetNewDialog 510.
        if line.localizedCaseInsensitiveContains("splash 510") {
            return nil
        }

        if line.localizedCaseInsensitiveContains("5005c86e")
            || line.localizedCaseInsensitiveContains("5c86c") {
            return .overlayNotInToast
        }

        for pattern in [#"id=(\d+)"#, #"res=(\d+)"#, #"dialog=(\d+)"#] {
            guard let idText = firstMatch(in: line, pattern: pattern),
                  let id = Int(idText) else { continue }
            if id == overlayResourceID { return .overlayNotInToast }
            if id == splashResourceID {
                if line.localizedCaseInsensitiveContains("toast id=") {
                    return .realSplash
                }
                if let pcText = firstMatch(in: line, pattern: #"\bpc=([0-9a-fA-F]+)"#),
                   let pc = parseHex(pcText),
                   G3PEFPlantMap.isHosted(pc) {
                    return .realSplash
                }
                return nil
            }
            return .other(id: id)
        }
        return nil
    }

    public static func isXlateMissNers(_ line: String) -> Bool {
        guard line.localizedCaseInsensitiveContains("xlate miss") else { return false }
        return line.localizedCaseInsensitiveContains("ea=6e657273")
            || line.localizedCaseInsensitiveContains("6e657273")
    }

    public static func isPEFEnter(_ line: String) -> Bool {
        line.localizedCaseInsensitiveContains("pef enter")
    }

    public static func recommendationLines(
        launchA9F2Logs: Int,
        launchA9F2Count: Int,
        pefEnterCount: Int,
        pefImportCount: Int,
        pefVolCount: Int,
        pefDceCount: Int,
        pefWaitNextEventCount: Int,
        pefHostedDSICount: Int,
        hostedLocationSamples: [String]
    ) -> [String] {
        guard launchA9F2Logs > 0 else { return [] }
        var lines: [String] = []
        let phase = EventCounts.pefPhase(
            enter: pefEnterCount,
            imports: pefImportCount,
            vol: pefVolCount,
            dce: pefDceCount,
            wait: pefWaitNextEventCount
        )

        switch phase {
        case .waitNextEvent:
            lines.append(
                "PEF WaitNextEvent live (\(pefWaitNextEventCount)×) — past KEEP 16527/16533 InterfaceLib import tip. Next: PEF GetNewDialog 510 / ParamText after wait returns 0, not skip-68k ROM map."
            )
        case .dce:
            lines.append(
                "PEF DCE plant live (\(pefDceCount)×) — hosted `.vfc` driver path before WaitNextEvent; do not re-mill InterfaceLib import idx= as if PEF enter were the tip."
            )
        case .vol:
            lines.append(
                "PEF vol idx= live (\(pefVolCount)×) — volume setup in hosted InterfaceLib; map pc=1010xxxx via plant 0x\(String(format: "%X", G3PEFPlantMap.plantBase)), code 0x\(String(format: "%X", G3PEFPlantMap.codeEntryPC))."
            )
        case .imports:
            lines.append(
                "PEF import idx= live (\(pefImportCount)×) in \(launchA9F2Logs) log(s) — map r3/pc=1010xxxx → PEF section + toast offset (plant 0x\(String(format: "%X", G3PEFPlantMap.plantBase)), code 0x\(String(format: "%X", G3PEFPlantMap.codeEntryPC))). Not +2 skip-68k ROM map."
            )
        case .enter:
            lines.append(
                "PEF enter at code 0x\(String(format: "%X", G3PEFPlantMap.codeEntryPC)) (\(pefEnterCount)×) — hosted InterfaceLib live after Launch A9F2 (\(launchA9F2Count)×). Next: import idx= / xlate miss ners, not skip-68k leftover."
            )
        case .none:
            lines.append(
                "Launch A9F2 CFM Upgrader in \(launchA9F2Logs) log(s) (\(launchA9F2Count)×) — live path after KEEP 16511/16518/16527. Next: PEF enter + hosted InterfaceLib imports, not +2 skip-68k ROM map."
            )
        }

        if pefHostedDSICount > 0 {
            lines.append(
                "Hosted PEF DSI (\(pefHostedDSICount)×) with SRR0=1010… — use plant map (not Python dump): \(hostedLocationSamples.prefix(3).joined(separator: "; "))"
            )
        }
        return lines
    }

    public static func isCFMUpgraderLaunch(_ line: String) -> Bool {
        guard line.contains("Launch A9F2") else { return false }
        return !line.localizedCaseInsensitiveContains("pef ")
    }

    public static func isLoadSeg66(_ line: String) -> Bool {
        guard let groups = firstMatchGroups(
            in: line,
            pattern: #"LoadSeg A9F0 enter seg=(\d+)(?: r24=[0-9a-fA-F]+)?"#
        ), groups.count >= 1, let seg = Int(groups[0]) else { return false }
        return seg == 66
    }

    public static func fourCCString(_ value: UInt32) -> String {
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ]
        let printable = bytes.allSatisfy { (32...126).contains($0) }
        if printable {
            return String(bytes: bytes, encoding: .ascii) ?? String(format: "0x%08X", value)
        }
        return String(format: "0x%08X", value)
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        firstMatchGroups(in: text, pattern: pattern)?.first
    }

    private static func firstMatchGroups(in text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        return (1..<match.numberOfRanges).compactMap { index in
            guard let swiftRange = Range(match.range(at: index), in: text) else { return nil }
            return String(text[swiftRange])
        }
    }

    private static func parseHex(_ text: String) -> UInt64? {
        UInt64(text, radix: 16)
    }
}
