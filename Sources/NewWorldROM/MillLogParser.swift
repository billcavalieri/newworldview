import Foundation

/// Parse SheepShaver `NW-BOOT` mill logs (`g3_driver/parse_log.py` parity).
public enum MillLogParser {
    public static let clusterLow: UInt64 = 0x5032_5000
    public static let clusterHigh: UInt64 = 0x5032_7000

    public struct Heartbeat: Sendable, Equatable, Identifiable {
        public var id: Int { lineIndex }
        public var pc: UInt64
        public var msr: UInt64
        public var same: Int
        public var line: String
        public var lineIndex: Int
    }

    public struct MillPair: Sendable, Equatable, Identifiable {
        public var id: Int { lineIndex }
        public var pc: UInt64?
        public var op: UInt64?
        public var nxt: UInt64?
        public var line: String
        public var lineIndex: Int
    }

    public struct SkipEvent: Sendable, Equatable, Identifiable {
        public var id: String
        public var kind: String
        public var offset: UInt64?
        public var trap: UInt16?
        public var line: String
        public var lineIndex: Int
    }

    public struct ParsedLog: Sendable, Equatable {
        public var heartbeats: [Heartbeat]
        public var millPairs: [MillPair]
        public var clusterPairs: [MillPair]
        public var skipEvents: [SkipEvent]
        public var millMax: Int
        public var reached68k: Bool
        public var g2Live: Bool
        public var empty300: Bool
        public var secondDSI: Bool
        public var hang04cecd36: Bool
        public var launchA9F2Count: Int
        public var loadSeg66Count: Int
        public var stayCode66Count: Int
        public var code66HelperSnapCount: Int
        public var pefEnterCount: Int
        public var pefImportCount: Int
        public var pefWaitNextEventCount: Int
        public var pefDceCount: Int
        public var pefVolCount: Int
        public var pefHostedDSICount: Int
        public var pefHostedLocationSamples: [String]
        public var getNewDialogOverlayHits: Int
        public var getNewDialogSplashHits: Int
        public var xlateMissNersCount: Int
        public var lastHeartbeat: Heartbeat?
        public var fileName: String

        public var observedPPCOffsets: [UInt64: Int] {
            var counts: [UInt64: Int] = [:]
            for hb in heartbeats {
                if let offset = AddressTranslation.romOffset(fromVirtual: hb.pc) {
                    counts[offset, default: 0] += 1
                }
            }
            for pair in millPairs {
                if let pc = pair.pc, let offset = AddressTranslation.romOffset(fromVirtual: pc) {
                    counts[offset, default: 0] += 1
                }
            }
            return counts
        }

        public var observed68kOffsets: [UInt64: Int] {
            var counts: [UInt64: Int] = [:]
            let directPatterns = [
                #"68k skip slot helper 0x([0-9a-fA-F]+)"#,
                #"68k skip 1adc mill 0x([0-9a-fA-F]+)"#
            ]
            let mapPattern = #"68k map r24=([0-9a-fA-F]+) op=([0-9a-fA-F]+)"#
            let spinPattern = #"68k spin r24=([0-9a-fA-F]+)(?: op=([0-9a-fA-F]+))?"#
            for pair in millPairs {
                for pattern in directPatterns {
                    if let match = firstMatch(in: pair.line, pattern: pattern),
                       let value = UInt64(match, radix: 16),
                       MillSkip68kPolicy.isMillable(offset: value) {
                        counts[value, default: 0] += 1
                    }
                }
                if let groups = firstMatchGroups(in: pair.line, pattern: mapPattern),
                   groups.count >= 2,
                   let r24 = parseHex(groups[0]) {
                    let op = parseHex(groups[1]).map { UInt16($0 & 0xFFFF) }
                    MillLogParser.recordNormalizedR24Hit(r24: r24, op: op, into: &counts)
                }
                if let groups = firstMatchGroups(in: pair.line, pattern: spinPattern),
                   let r24 = parseHex(groups[0]) {
                    let op = groups.count >= 2 ? parseHex(groups[1]).map { UInt16($0 & 0xFFFF) } : nil
                    MillLogParser.recordNormalizedR24Hit(r24: r24, op: op, into: &counts)
                }
            }
            for event in skipEvents {
                if let offset = event.offset, MillSkip68kPolicy.isMillable(offset: offset) {
                    counts[offset, default: 0] += 1
                }
            }
            return counts
        }
    }

    private static func recordNormalizedR24Hit(
        r24: UInt64,
        op: UInt16?,
        into counts: inout [UInt64: Int]
    ) {
        if MillSkip68kPolicy.isBlockedUIOperation(op) {
            return
        }
        let offset = AddressTranslation.romOffset(fromR24: r24)
        guard MillSkip68kPolicy.isMillable(offset: offset, op: op) else { return }
        counts[offset, default: 0] += 1
    }

    public static func parse(_ text: String, fileName: String = "") -> ParsedLog {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var heartbeats: [Heartbeat] = []
        var millPairs: [MillPair] = []
        var millVals: [Int] = []
        var skipEvents: [SkipEvent] = []
        var g2Live = false
        var empty300 = false
        var hang04cecd36 = false
        var dsiNMax = 0
        var handlerCut = -1
        var reached68k = false
        var launchA9F2Count = 0
        var loadSeg66Count = 0
        var stayCode66Count = 0
        var code66HelperSnapCount = 0
        var g3Events = G3MillClassification.EventCounts()

        for (index, line) in lines.enumerated() {
            for match in matches(in: line, pattern: #"\bmill=(\d+)"#) {
                if let value = Int(match) { millVals.append(value) }
            }

            if let hb = firstMatchGroups(in: line, pattern: #"NW-BOOT heartbeat pc=([0-9a-fA-F]+) msr=([0-9a-fA-F]+) same=(\d+)"#) {
                heartbeats.append(
                    Heartbeat(
                        pc: parseHex(hb[0]) ?? 0,
                        msr: parseHex(hb[1]) ?? 0,
                        same: Int(hb[2]) ?? 0,
                        line: line,
                        lineIndex: index
                    )
                )
            }

            if line.contains("hang 04cecd36") { hang04cecd36 = true }
            if line.lowercased().contains("illegal pc=00000300") || line.contains("empty 0x300") {
                empty300 = true
            }
            if line.contains("first DSI") && line.contains("DRhit=1") { g2Live = true }
            if line.contains("pc=50366084") { reached68k = true }

            if let dsi = firstMatch(in: line, pattern: #"DSI n=(\d+)"#), let n = Int(dsi) {
                dsiNMax = max(dsiNMax, n)
            }

            if line.contains("DEC handler left") || line.contains("DEC rfi restore") {
                handlerCut = index
            }

            if line.contains("DEC leave") {
                let pc = firstMatch(in: line, pattern: #"\bpc=([0-9a-fA-F]+)"#).flatMap { parseHex($0) }
                let op = firstMatch(in: line, pattern: #"\bop=([0-9a-fA-F]+)"#).flatMap { parseHex($0) }
                let nxt = firstMatch(in: line, pattern: #"\bnxt=([0-9a-fA-F]+)"#).flatMap { parseHex($0) }
                if op != nil || nxt != nil {
                    millPairs.append(MillPair(pc: pc, op: op, nxt: nxt, line: line, lineIndex: index))
                }
            }

            if line.contains("68k map") || line.contains("68k spin") {
                millPairs.append(MillPair(pc: nil, op: nil, nxt: nil, line: line, lineIndex: index))
            }

            recordCode66Events(
                from: line,
                launchCount: &launchA9F2Count,
                loadSeg66Count: &loadSeg66Count,
                stayCount: &stayCode66Count,
                helperSnapCount: &code66HelperSnapCount
            )
            recordG3MillEvents(from: line, into: &g3Events)

            recordSkipEvents(from: line, lineIndex: index, into: &skipEvents)
        }

        let postLeave: [MillPair]
        if handlerCut >= 0 {
            postLeave = millPairs.filter { $0.lineIndex > handlerCut }
        } else {
            postLeave = millPairs.filter { pair in
                guard let pc = pair.pc else { return false }
                return inCluster(pc)
            }
        }
        let clusterPairs = postLeave.filter { pair in
            guard pair.op != nil else { return false }
            guard let pc = pair.pc else { return true }
            return inCluster(pc)
        }

        return ParsedLog(
            heartbeats: heartbeats,
            millPairs: millPairs,
            clusterPairs: clusterPairs,
            skipEvents: skipEvents,
            millMax: millVals.max() ?? 0,
            reached68k: reached68k || heartbeats.contains { $0.pc == AddressTranslation.reached68kPC },
            g2Live: g2Live && !empty300,
            empty300: empty300,
            secondDSI: dsiNMax >= 2,
            hang04cecd36: hang04cecd36,
            launchA9F2Count: launchA9F2Count,
            loadSeg66Count: loadSeg66Count,
            stayCode66Count: stayCode66Count,
            code66HelperSnapCount: code66HelperSnapCount,
            pefEnterCount: g3Events.pefEnterCount,
            pefImportCount: g3Events.pefImportCount,
            pefWaitNextEventCount: g3Events.pefWaitNextEventCount,
            pefDceCount: g3Events.pefDceCount,
            pefVolCount: g3Events.pefVolCount,
            pefHostedDSICount: g3Events.pefHostedDSICount,
            pefHostedLocationSamples: g3Events.hostedLocationSamples,
            getNewDialogOverlayHits: g3Events.getNewDialogOverlayHits,
            getNewDialogSplashHits: g3Events.getNewDialogSplashHits,
            xlateMissNersCount: g3Events.xlateMissNersCount,
            lastHeartbeat: heartbeats.last,
            fileName: fileName
        )
    }

    public static func parseFile(at url: URL) throws -> ParsedLog {
        let text = try MillLogReader.decompressedString(from: url)
        return parse(text, fileName: MillLogReader.displayFileName(for: url))
    }

    public static func parseLogLine(_ line: String) -> ProgramAddress? {
        if let pc = firstMatch(in: line, pattern: #"\bpc=([0-9a-fA-F]+)"#),
           let value = parseHex(pc) {
            return ProgramAddress(space: .ppcMacROM, address: value)
        }
        return AddressTranslation.parse(line)?.programAddress
    }

    public static func inCluster(_ pc: UInt64) -> Bool {
        pc >= clusterLow && pc < clusterHigh
    }

    static func recordCode66Events(
        from line: String,
        launchCount: inout Int,
        loadSeg66Count: inout Int,
        stayCount: inout Int,
        helperSnapCount: inout Int
    ) {
        if G3MillClassification.isCFMUpgraderLaunch(line) {
            launchCount += 1
        }
        if G3MillClassification.isLoadSeg66(line) {
            loadSeg66Count += 1
        }
        if line.contains("stay CODE 66") {
            stayCount += 1
            if let fromHex = firstMatch(in: line, pattern: #"from=([0-9a-fA-F]+)"#),
               let from = parseHex(fromHex) {
                let offset = AddressTranslation.romOffset(fromR24: from)
                if AddressTranslation.isCode66HelperRange(offset) {
                    helperSnapCount += 1
                }
            }
        }
    }

    static func recordG3MillEvents(
        from line: String,
        into events: inout G3MillClassification.EventCounts
    ) {
        events.record(line: line)
    }

    static func trapName(in line: String) -> UInt16? {
        ATrapTable.trapName(in: line)
    }

    private static func recordSkipEvents(from line: String, lineIndex: Int, into events: inout [SkipEvent]) {
        let rules: [(String, String)] = [
            (#"68k skip slot helper 0x([0-9a-fA-F]+)"#, "skip-slot-helper"),
            (#"68k skip 1adc mill 0x([0-9a-fA-F]+)"#, "skip-1adc-mill"),
            (#"68k (DialogDispatch|GetCCursor|NewDialog|DisposeDialog|GetNewDialog|OpenResFile|GetResource|InitCursor|SetPort|CloseRgn|GetEOF|GetFPos|SetFPos|Read|HOpen|ModalDialog)"#, "no-skip-ui-trap"),
            (#"68k A-line default native"#, "trap-68k-default"),
            (#"KEEP 68k hang"#, "keep-68k"),
            (#"KEEP hang skip"#, "skip-hang"),
            (#"DEC leave 50326 stw\+mfsr skip"#, "skip-pair"),
            (#"DEC leave 50326 mfsr skip"#, "skip-mfsr"),
            (#"poison callback skip"#, "poison-skip"),
            (#"68k reenter from hang"#, "reenter-68k")
        ]
        for (pattern, kind) in rules {
            if let offset = firstMatch(in: line, pattern: pattern), kind.hasPrefix("skip") || kind.contains("slot") || kind.contains("1adc") {
                events.append(
                    SkipEvent(
                        id: "\(lineIndex)-\(kind)-\(offset)",
                        kind: kind,
                        offset: UInt64(offset, radix: 16),
                        trap: nil,
                        line: line,
                        lineIndex: lineIndex
                    )
                )
            } else if line.contains(kind.replacingOccurrences(of: "-", with: " ")) || matchesWholeMarker(line, kind: kind) {
                events.append(
                    SkipEvent(
                        id: "\(lineIndex)-\(kind)",
                        kind: kind,
                        offset: nil,
                        trap: nil,
                        line: line,
                        lineIndex: lineIndex
                    )
                )
            }
        }
    }

    private static func matchesWholeMarker(_ line: String, kind: String) -> Bool {
        switch kind {
        case "skip-pair": return line.contains("stw+mfsr skip")
        case "skip-mfsr": return line.contains("mfsr skip")
        case "trap-68k-default": return line.contains("A-line default native")
        case "keep-68k": return line.contains("KEEP 68k hang")
        case "skip-hang": return line.contains("KEEP hang skip")
        case "poison-skip": return line.contains("poison callback skip")
        case "reenter-68k": return line.contains("reenter from hang")
        default: return false
        }
    }

    private static func parseHex(_ text: String) -> UInt64? {
        UInt64(text, radix: 16)
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

    private static func matches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let swiftRange = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[swiftRange])
        }
    }
}
