import Foundation

/// Classic Mac OS A-line / toolbox traps. Names follow Inside Macintosh and the
/// SheepShaver G3 mill (`rom_disasm.py` / `NO_SKIP_68K_OPS`).
public enum ATrapTable {
    public static let names: [UInt16: String] = {
        var table: [UInt16: String] = [
            0xA000: "Open",
            0xA001: "Close",
            0xA002: "Read",
            0xA003: "Write",
            0xA009: "GetFileInfo",
            0xA00A: "SetFileInfo",
            0xA013: "GetEOF",
            0xA014: "SetEOF",
            0xA01B: "GetVolInfo",
            0xA01F: "GetEOF",
            0xA023: "GetFPos",
            0xA02E: "BlockMove",
            0xA031: "GetOSEvent",
            0xA044: "SetFPos",
            0xA050: "FlushVol",
            0xA051: "ReadDateTime",
            0xA054: "AddDrive",
            0xA060: "HFSDispatch",
            0xA06E: "OpenResFile",
            0xA08E: "BTreeDispatch",
            0xA146: "GetTrapAddress",
            0xA190: "GetResourceData",
            0xA198: "HOpen",
            0xA200: "HOpen",
            0xA207: "HGetFileInfo",
            0xA20A: "HSetFPos",
            0xA22E: "BlockMove",
            0xA247: "GetOSTrapAddress",
            0xA260: "HFSDispatch",
            0xA346: "GetToolTrapAddress",
            0xA450: "Read",
            0xA71E: "GetFCB",
            0xA86D: "OpenPort",
            0xA86E: "InitPort",
            0xA873: "SetPort",
            0xA88F: "InitCursor",
            0xA8A2: "NewWindow",
            0xA8A3: "DisposeWindow",
            0xA8A7: "SetRect",
            0xA8D9: "CloseRgn",
            0xA8FE: "InitGraf",
            0xA8FF: "OpenPort",
            0xA914: "GetNewWindow",
            0xA91F: "GetNewControl",
            0xA96F: "Enqueue",
            0xA97B: "InitDialogs",
            0xA97C: "GetNewDialog",
            0xA97D: "NewDialog",
            0xA983: "DisposeDialog",
            0xA985: "NewDialog",
            0xA9A0: "GetResource",
            0xA9A2: "LoadResource",
            0xA9C9: "SysError",
            0xA9F0: "LoadSeg",
            0xA9F2: "Launch",
            0xAA1B: "GetCCursor",
            0xAA5A: "CodeFragmentDispatch",
            0xAA68: "DialogDispatch",
            0xABE8: "InitCPort",
            0xABE9: "InitCPort"
        ]
        return table
    }()

    /// Trap names as they appear in SheepShaver `G3: 68k …` log lines.
    public static let logTrapNames: [(String, UInt16)] = [
        ("GetNewDialog", 0xA97C),
        ("NewDialog", 0xA97D),
        ("Launch", 0xA9F2),
        ("LoadSeg", 0xA9F0),
        ("GetCCursor", 0xAA1B),
        ("DialogDispatch", 0xAA68),
        ("DisposeDialog", 0xA983),
        ("OpenResFile", 0xA06E),
        ("GetResource", 0xA9A0),
        ("SysError", 0xA9C9),
        ("InitCursor", 0xA88F),
        ("SetPort", 0xA873),
        ("CloseRgn", 0xA8D9),
        ("GetEOF", 0xA01F),
        ("GetFPos", 0xA023),
        ("SetFPos", 0xA044),
        ("Read", 0xA002),
        ("HOpen", 0xA200),
        ("CodeFragmentDispatch", 0xAA5A),
        ("FixMul", 0xA868),
        ("DisposePtr", 0xA01F),
        ("ModalDialog", 0xA991)
    ]

    public static func name(for trap: UInt16) -> String {
        if let named = names[trap] {
            return "_\(named)"
        }
        return String(format: "_A%03X", trap & 0x0FFF)
    }

    public static func trapName(in line: String) -> UInt16? {
        for (name, trap) in logTrapNames where line.contains(name) {
            if trap == 0xA9F2, line.localizedCaseInsensitiveContains("pef ") {
                continue
            }
            return trap
        }
        return nil
    }

    public static var noSkipUITraps: Set<UInt16> {
        [
            0xA97C, 0xA97D, 0xAA1B, 0xAA68, 0xA873, 0xA983, 0xA8D9,
            0xA06E, 0xA9C9, 0xA9A0, 0xA88F, 0xA991,
            0xA01F, 0xA023, 0xA044, 0xA002, 0xA450
        ]
    }
}

public enum AddressSpaces {
    /// SheepShaver / `rom_disasm.py` mapping for the 4 MB NewWorld MacROM.
    public static let ppcMacROMBase: UInt64 = 0x5000_0000
    public static let ppcMacROMSize: UInt64 = 0x40_0000
    /// GetNewDialog ROM overlay stub (trap A97C; mill `UI_SKIP_68K_LO`).
    public static let getNewDialogStub: UInt64 = 0x5C86C
    public static let getNewDialogStubEnd: UInt64 = 0x5C8C0
}
