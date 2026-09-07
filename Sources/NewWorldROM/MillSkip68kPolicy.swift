import Foundation

/// Skip-68k millability rules aligned with macemu `mill_apply.skip_68k_millable` / `skip_68k_ui_op`.
public enum MillSkip68kPolicy {
    public static let hardSkipOffsets: Set<UInt64> = [0x3264FC, 0x326564, 0x326568]
    public static let off68k: UInt64 = 0x366084
    public static let spin26E88: UInt64 = 0x26E88
    public static let uiRange: ClosedRange<UInt64> = 0x5C86C...0x5C8BF
    /// ROM helper kajr CODE 66 fall-through (`g3_rom_9440` in ppc-cpu.cpp) — false path, not G3 installer.
    public static let code66HelperRange: ClosedRange<UInt64> = 0x9440...0x94CF
    public static let a190DataRange: ClosedRange<UInt64> = 0x16DE8...0x16E1F
    public static let nkBand: ClosedRange<UInt64> = 0x326000...0x326FFF
    public static let emulatorJTRange: ClosedRange<UInt64> = 0x350000...0x3FFFFF

    public static let lookAgainSkip68k: Set<UInt64> = [
        0x16FC2, 0x173F0, 0x16DB8, 0x151D8, 0x50D28, 0x50D38, 0x8670
    ]

    public static let pinnedKeepMillNumbers = [6613, 1116, 680, 35, 22]

    public static func isBlockedUIOperation(_ op: UInt16?) -> Bool {
        guard let op else { return false }
        return ATrapTable.noSkipUITraps.contains(op)
    }

    public static func isMillable(offset: UInt64, op: UInt16? = nil) -> Bool {
        if isBlockedUIOperation(op) {
            return false
        }
        let o = offset
        if o == off68k || o == spin26E88 || hardSkipOffsets.contains(o) {
            return false
        }
        if nkBand.contains(o) || uiRange.contains(o) || code66HelperRange.contains(o) || a190DataRange.contains(o) {
            return false
        }
        if lookAgainSkip68k.contains(o) || emulatorJTRange.contains(o) {
            return false
        }
        if o < 0x1000 || o >= 0x400000 {
            return false
        }
        return true
    }

    public static func blockReason(offset: UInt64, op: UInt16? = nil) -> String? {
        if isBlockedUIOperation(op) {
            return "NO_SKIP A-trap op=0x\(String(format: "%X", op ?? 0))"
        }
        if hardSkipOffsets.contains(offset) || offset == off68k {
            return "HARD NK / heartbeat offset"
        }
        if offset == spin26E88 {
            return "spin-26e88 REVERT — do not remill"
        }
        if nkBand.contains(offset) {
            return "50325/50326 NK band"
        }
        if uiRange.contains(offset) {
            return "GetNewDialog overlay stub (id=\(G3MillClassification.overlayResourceID), pc=0x5C86C–0x5C8C0) — not on toast; overlay ≠ WINDOW"
        }
        if code66HelperRange.contains(offset) {
            return "\(G3MillClassification.loadSeg66FalsePathLabel); CODE 66 helper (0x9440–0x94CF) — do not skip-68k"
        }
        if a190DataRange.contains(offset) {
            return "$a190 data table"
        }
        if lookAgainSkip68k.contains(offset) {
            return "KEEP look-again offset"
        }
        if emulatorJTRange.contains(offset) {
            return "68k emulator jump table"
        }
        if offset < 0x1000 || offset >= 0x400000 {
            return "Out of millable ROM range"
        }
        return nil
    }
}
