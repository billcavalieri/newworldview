import Foundation

extension MillLogParser {
    /// Lightweight per-log statistics for historical analysis without retaining full parse trees.
    public struct LogAggregates: Sendable, Equatable {
        public var fileName: String
        public var millMax: Int
        public var reached68k: Bool
        public var g2Live: Bool
        public var empty300: Bool
        public var hang04cecd36: Bool
        public var launchA9F2Count: Int
        public var loadSeg66Count: Int
        public var stayCode66Count: Int
        public var code66HelperSnapCount: Int
        public var getNewDialogStubHits: Int
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
        public var clusterPairCount: Int
        public var skipEventCount: Int
        public var ppcOffsetCounts: [UInt64: Int]
        public var m68kOffsetCounts: [UInt64: Int]
        public var trapCounts: [UInt16: Int]
    }

    public static func accumulateAggregates(from url: URL) throws -> LogAggregates {
        var accumulator = LogAccumulator(fileName: MillLogReader.displayFileName(for: url))
        let handle = try MillLogReader.open(forReadingFrom: url)
        defer { handle.close() }

        var pending = Data()
        pending.reserveCapacity(4096)
        var lineIndex = 0

        while true {
            let chunk = try handle.read(upToCount: 512 * 1024)
            guard let chunk, !chunk.isEmpty else { break }
            pending.append(chunk)

            while let newline = pending.firstIndex(of: 0x0A) {
                var lineData = pending[..<newline]
                pending.removeSubrange(pending.startIndex...newline)

                if lineData.last == 0x0D {
                    lineData = lineData.dropLast()
                }
                guard MillLogLineScanner.mayContainAggregates(lineData) else {
                    lineIndex += 1
                    continue
                }
                guard let line = String(data: lineData, encoding: .utf8) else {
                    lineIndex += 1
                    continue
                }
                accumulator.processLine(line, lineIndex: lineIndex)
                lineIndex += 1
            }
        }

        if !pending.isEmpty {
            var lineData = pending
            if lineData.last == 0x0D {
                lineData = lineData.dropLast()
            }
            if MillLogLineScanner.mayContainAggregates(lineData),
               let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                accumulator.processLine(line, lineIndex: lineIndex)
            }
        }

        return accumulator.finish()
    }
}

private enum MillLogLineScanner {
    private static let aggregateMarkers: [Data] = [
        Data("mill=".utf8),
        Data("NW-BOOT heartbeat".utf8),
        Data("hang 04cecd36".utf8),
        Data("empty 0x300".utf8),
        Data("illegal pc=".utf8),
        Data("ILLEGAL pc=".utf8),
        Data("50366084".utf8),
        Data("DSI".utf8),
        Data("DEC handler left".utf8),
        Data("DEC rfi restore".utf8),
        Data("DEC leave".utf8),
        Data("68k map ".utf8),
        Data("68k spin ".utf8),
        Data("68k skip".utf8),
        Data("KEEP".utf8),
        Data("poison callback".utf8),
        Data("stw+mfsr".utf8),
        Data("mfsr skip".utf8),
        Data("reenter from hang".utf8),
        Data("68k A-line".utf8),
        Data("68k Launch A9F2".utf8),
        Data("68k LoadSeg A9F0".utf8),
        Data("68k stay CODE 66".utf8),
        Data("68k DialogDispatch".utf8),
        Data("68k GetCCursor".utf8),
        Data("68k NewDialog".utf8),
        Data("68k ModalDialog".utf8),
        Data("68k DisposeDialog".utf8),
        Data("68k GetNewDialog".utf8),
        Data("PEF enter".utf8),
        Data("PEF import idx=".utf8),
        Data("PEF WaitNextEvent".utf8),
        Data("PEF dce".utf8),
        Data("PEF vol idx=".utf8),
        Data("SRR0=1010".utf8),
        Data("xlate miss".utf8),
        Data("68k OpenResFile".utf8),
        Data("68k SysError".utf8),
        Data("68k GetResource".utf8),
        Data("68k InitCursor".utf8),
        Data("68k SetPort".utf8),
        Data("68k CloseRgn".utf8),
        Data("68k GetEOF".utf8),
        Data("68k GetFPos".utf8),
        Data("68k SetFPos".utf8),
        Data("68k Read".utf8),
        Data("68k HOpen".utf8),
        Data("68k CodeFragmentDispatch".utf8),
        Data("68k FixMul".utf8),
        Data("68k DisposePtr".utf8)
    ]

    static func mayContainAggregates(_ line: Data) -> Bool {
        guard !line.isEmpty else { return false }
        for marker in aggregateMarkers where line.range(of: marker) != nil {
            return true
        }
        return false
    }

    static func mayContainSkipEvents(_ line: String) -> Bool {
        if line.contains("68k skip") { return true }
        if line.contains("KEEP") { return true }
        if line.contains("poison callback") { return true }
        if line.contains("stw+mfsr") || line.contains("mfsr skip") { return true }
        if line.contains("reenter from hang") { return true }
        if line.contains("68k A-line") { return true }
        return MillLogRegex.matchesWholeMarker(line, kind: "no-skip-ui-trap")
    }
}

private struct LogAccumulator {
    let fileName: String
    var millMax = 0
    var reached68k = false
    var g2Live = false
    var empty300 = false
    var hang04cecd36 = false
    var launchA9F2Count = 0
    var loadSeg66Count = 0
    var stayCode66Count = 0
    var code66HelperSnapCount = 0
    var getNewDialogStubHits = 0
    var getNewDialogOverlayHitsFromR24 = 0
    var g3Events = G3MillClassification.EventCounts()
    var dsiNMax = 0
    var handlerCut = -1
    var skipEventCount = 0
    var ppcOffsetCounts: [UInt64: Int] = [:]
    var m68kOffsetCounts: [UInt64: Int] = [:]
    var trapCounts: [UInt16: Int] = [:]
    var decLeaveRecords: [DecLeaveRecord] = []
    var sawHeartbeatAtReached68k = false

    init(fileName: String) {
        self.fileName = fileName
        decLeaveRecords.reserveCapacity(128)
    }

    mutating func processLine(_ line: String, lineIndex: Int) {
        if line.contains("mill=") {
            for match in MillLogRegex.matches(in: line, pattern: .millValue) {
                if let value = Int(match) {
                    millMax = max(millMax, value)
                }
            }
        }

        if line.contains("NW-BOOT heartbeat"),
           let heartbeat = MillLogRegex.firstMatchGroups(in: line, pattern: .heartbeat) {
            let pc = MillLogRegex.parseHex(heartbeat[0]) ?? 0
            recordPPCOffset(pc)
            if pc == AddressTranslation.reached68kPC {
                sawHeartbeatAtReached68k = true
            }
        }

        if line.contains("hang 04cecd36") { hang04cecd36 = true }
        if line.lowercased().contains("illegal pc=00000300") || line.contains("empty 0x300") {
            empty300 = true
        }
        if line.contains("first DSI"), line.contains("DRhit=1") { g2Live = true }
        if line.contains("pc=50366084") { reached68k = true }

        if line.contains("DSI"),
           let dsi = MillLogRegex.firstMatch(in: line, pattern: .dsiCount),
           let n = Int(dsi) {
            dsiNMax = max(dsiNMax, n)
        }

        if line.contains("DEC handler left") || line.contains("DEC rfi restore") {
            handlerCut = lineIndex
        }

        if line.contains("DEC leave") {
            let pc = MillLogRegex.firstMatch(in: line, pattern: .pcValue).flatMap(MillLogRegex.parseHex)
            let op = MillLogRegex.firstMatch(in: line, pattern: .opValue).flatMap(MillLogRegex.parseHex)
            let nxt = MillLogRegex.firstMatch(in: line, pattern: .nxtValue).flatMap(MillLogRegex.parseHex)
            if op != nil || nxt != nil {
                if let pc {
                    recordPPCOffset(pc)
                }
                record68kPatterns(in: line)
                decLeaveRecords.append(
                    DecLeaveRecord(lineIndex: lineIndex, pc: pc, hasOp: op != nil)
                )
            }
        }

        if line.contains("68k map") || line.contains("68k spin") {
            recordR24Lines(from: line)
        }
        MillLogParser.recordCode66Events(
            from: line,
            launchCount: &launchA9F2Count,
            loadSeg66Count: &loadSeg66Count,
            stayCount: &stayCode66Count,
            helperSnapCount: &code66HelperSnapCount
        )
        MillLogParser.recordG3MillEvents(from: line, into: &g3Events)
        if MillLogLineScanner.mayContainSkipEvents(line) {
            recordSkipEvents(from: line)
        }
    }

    func finish() -> MillLogParser.LogAggregates {
        let postLeave: [DecLeaveRecord]
        if handlerCut >= 0 {
            postLeave = decLeaveRecords.filter { $0.lineIndex > handlerCut }
        } else {
            postLeave = decLeaveRecords.filter { record in
                guard let pc = record.pc else { return false }
                return MillLogParser.inCluster(pc)
            }
        }
        let clusterPairCount = postLeave.filter { record in
            guard record.hasOp else { return false }
            guard let pc = record.pc else { return true }
            return MillLogParser.inCluster(pc)
        }.count

        return MillLogParser.LogAggregates(
            fileName: fileName,
            millMax: millMax,
            reached68k: reached68k || sawHeartbeatAtReached68k,
            g2Live: g2Live && !empty300,
            empty300: empty300,
            hang04cecd36: hang04cecd36,
            launchA9F2Count: launchA9F2Count,
            loadSeg66Count: loadSeg66Count,
            stayCode66Count: stayCode66Count,
            code66HelperSnapCount: code66HelperSnapCount,
            getNewDialogStubHits: getNewDialogStubHits,
            pefEnterCount: g3Events.pefEnterCount,
            pefImportCount: g3Events.pefImportCount,
            pefWaitNextEventCount: g3Events.pefWaitNextEventCount,
            pefDceCount: g3Events.pefDceCount,
            pefVolCount: g3Events.pefVolCount,
            pefHostedDSICount: g3Events.pefHostedDSICount,
            pefHostedLocationSamples: g3Events.hostedLocationSamples,
            getNewDialogOverlayHits: g3Events.getNewDialogOverlayHits + getNewDialogOverlayHitsFromR24,
            getNewDialogSplashHits: g3Events.getNewDialogSplashHits,
            xlateMissNersCount: g3Events.xlateMissNersCount,
            clusterPairCount: clusterPairCount,
            skipEventCount: skipEventCount,
            ppcOffsetCounts: ppcOffsetCounts,
            m68kOffsetCounts: m68kOffsetCounts,
            trapCounts: trapCounts
        )
    }

    private mutating func recordPPCOffset(_ virtualPC: UInt64) {
        guard let offset = AddressTranslation.romOffset(fromVirtual: virtualPC) else { return }
        ppcOffsetCounts[offset, default: 0] += 1
    }

    private mutating func record68kPatterns(in line: String) {
        for pattern in [MillLogRegex.Pattern.skipSlotHelper, .skip1adcMill] {
            if let match = MillLogRegex.firstMatch(in: line, pattern: pattern),
               let value = UInt64(match, radix: 16) {
                recordMillable68kOffset(value)
            }
        }
    }

    private mutating func recordR24Lines(from line: String) {
        if let groups = MillLogRegex.firstMatchGroups(in: line, pattern: .m68kMap),
           groups.count >= 2,
           let r24 = MillLogRegex.parseHex(groups[0]),
           let op = MillLogRegex.parseHex(groups[1]).map({ UInt16($0 & 0xFFFF) }) {
            record68kHit(r24: r24, op: op, line: line)
            return
        }
        if let groups = MillLogRegex.firstMatchGroups(in: line, pattern: .m68kSpin),
           let r24 = MillLogRegex.parseHex(groups[0]) {
            let op = groups.count >= 2 ? MillLogRegex.parseHex(groups[1]).map({ UInt16($0 & 0xFFFF) }) : nil
            record68kHit(r24: r24, op: op, line: line)
        }
    }

    private mutating func record68kHit(r24: UInt64, op: UInt16?, line: String? = nil) {
        let offset = AddressTranslation.romOffset(fromR24: r24)
        if AddressTranslation.isGetNewDialogStubRange(offset) || op == 0xA97C {
            getNewDialogStubHits += 1
            if offset == AddressTranslation.romOffset(fromVirtual: G3MillClassification.overlayVirtualPC)
                || AddressTranslation.isGetNewDialogStubRange(offset) {
                getNewDialogOverlayHitsFromR24 += 1
            }
        }
        if let line, let kind = G3MillClassification.classifyGetNewDialog(line: line) {
            switch kind {
            case .overlayNotInToast:
                getNewDialogOverlayHitsFromR24 += 1
            case .realSplash, .other:
                break
            }
        }
        if MillSkip68kPolicy.isBlockedUIOperation(op), let op {
            trapCounts[op, default: 0] += 1
            return
        }
        recordMillable68kOffset(offset, op: op)
    }

    private mutating func recordMillable68kOffset(_ offset: UInt64, op: UInt16? = nil) {
        guard MillSkip68kPolicy.isMillable(offset: offset, op: op) else { return }
        m68kOffsetCounts[offset, default: 0] += 1
    }

    private mutating func recordSkipEvents(from line: String) {
        let rules: [(MillLogRegex.Pattern, String, Bool)] = [
            (.skipSlotHelper, "skip-slot-helper", true),
            (.skip1adcMill, "skip-1adc-mill", true),
            (.skipPair, "skip-pair", false),
            (.skipMfsr, "skip-mfsr", false),
            (.trap68kDefault, "trap-68k-default", false),
            (.keep68k, "keep-68k", false),
            (.skipHang, "skip-hang", false),
            (.poisonSkip, "poison-skip", false),
            (.reenter68k, "reenter-68k", false)
        ]

        for (pattern, kind, capturesOffset) in rules {
            guard MillLogRegex.matchesWholeMarker(line, kind: kind)
                || (capturesOffset && MillLogRegex.firstMatch(in: line, pattern: pattern) != nil)
            else { continue }

            skipEventCount += 1
            if capturesOffset,
               let offset = MillLogRegex.firstMatch(in: line, pattern: pattern).flatMap({ UInt64($0, radix: 16) }) {
                recordMillable68kOffset(offset)
            }
            record68kPatterns(in: line)
            if let trap = MillLogRegex.trapName(in: line) {
                trapCounts[trap, default: 0] += 1
            }
        }

        if MillLogRegex.matchesWholeMarker(line, kind: "no-skip-ui-trap") {
            skipEventCount += 1
            if let trap = MillLogRegex.trapName(in: line) {
                trapCounts[trap, default: 0] += 1
            }
        }
    }
}

private struct DecLeaveRecord: Sendable {
    var lineIndex: Int
    var pc: UInt64?
    var hasOp: Bool
}

private enum MillLogRegex {
    enum Pattern: String {
        case millValue = #"\bmill=(\d+)"#
        case heartbeat = #"NW-BOOT heartbeat pc=([0-9a-fA-F]+) msr=([0-9a-fA-F]+) same=(\d+)"#
        case dsiCount = #"DSI n=(\d+)"#
        case pcValue = #"\bpc=([0-9a-fA-F]+)"#
        case opValue = #"\bop=([0-9a-fA-F]+)"#
        case nxtValue = #"\bnxt=([0-9a-fA-F]+)"#
        case skipSlotHelper = #"68k skip slot helper 0x([0-9a-fA-F]+)"#
        case skip1adcMill = #"68k skip 1adc mill 0x([0-9a-fA-F]+)"#
        case m68kSpin = #"68k spin r24=([0-9a-fA-F]+)(?: op=([0-9a-fA-F]+))?"#
        case m68kMap = #"68k map r24=([0-9a-fA-F]+) op=([0-9a-fA-F]+)"#
        case skipPair = #"DEC leave 50326 stw\+mfsr skip"#
        case skipMfsr = #"DEC leave 50326 mfsr skip"#
        case trap68kDefault = #"68k A-line default native"#
        case keep68k = #"KEEP 68k hang"#
        case skipHang = #"KEEP hang skip"#
        case poisonSkip = #"poison callback skip"#
        case reenter68k = #"68k reenter from hang"#
    }

    static let m68kOffsetPatterns: [Pattern] = [.skipSlotHelper, .skip1adcMill]

    static let m68kR24Patterns: [Pattern] = [.m68kSpin, .m68kMap]

    private static let cache: [Pattern: NSRegularExpression] = {
        var result: [Pattern: NSRegularExpression] = [:]
        for pattern in Pattern.allCases {
            result[pattern] = try? NSRegularExpression(pattern: pattern.rawValue, options: [.caseInsensitive])
        }
        return result
    }()

    static func matchesWholeMarker(_ line: String, kind: String) -> Bool {
        switch kind {
        case "skip-pair": return line.contains("stw+mfsr skip")
        case "skip-mfsr": return line.contains("mfsr skip")
        case "trap-68k-default": return line.contains("A-line default native")
        case "keep-68k": return line.contains("KEEP 68k hang")
        case "skip-hang": return line.contains("KEEP hang skip")
        case "poison-skip": return line.contains("poison callback skip")
        case "reenter-68k": return line.contains("reenter from hang")
        case "no-skip-ui-trap":
            return ATrapTable.logTrapNames.contains { line.contains("68k \($0.0)") }
        default: return false
        }
    }

    static func parseHex(_ text: String) -> UInt64? {
        UInt64(text, radix: 16)
    }

    static func firstMatch(in text: String, pattern: Pattern) -> String? {
        firstMatchGroups(in: text, pattern: pattern)?.first
    }

    static func firstMatchGroups(in text: String, pattern: Pattern) -> [String]? {
        guard let regex = cache[pattern] else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        return (1..<match.numberOfRanges).compactMap { index in
            guard let swiftRange = Range(match.range(at: index), in: text) else { return nil }
            return String(text[swiftRange])
        }
    }

    static func matches(in text: String, pattern: Pattern) -> [String] {
        guard let regex = cache[pattern] else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let swiftRange = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[swiftRange])
        }
    }

    static func trapName(in line: String) -> UInt16? {
        ATrapTable.trapName(in: line)
    }
}

extension MillLogRegex.Pattern: CaseIterable {}
