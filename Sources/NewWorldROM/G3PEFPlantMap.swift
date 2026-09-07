import Foundation

/// Map hosted InterfaceLib PEF guest PCs to planted sections (macemu `g3_pef_plant` / `g3_pef_enter`).
public enum G3PEFPlantMap {
    public static let plantBase: UInt64 = 0x1010_0000
    public static let codeSectionOffset: UInt64 = 5072
    public static let dataSectionOffset: UInt64 = 0x15000
    public static let stubSectionOffset: UInt64 = 0x16000
    public static let loaderOffset: UInt64 = 128
    public static let pidataOffset: UInt64 = 85952

    /// Toast `Mac OS Install` data fork (g3_df_off / g3_df_len in ppc-cpu.cpp).
    public static let toastDataForkOffset: UInt64 = 74_182_144
    public static let toastDataForkLength: UInt64 = 86_446

    public static let codeEntryPC: UInt64 = plantBase + codeSectionOffset

    public struct Location: Sendable, Equatable, Codable {
        public var section: String
        public var sectionOffset: UInt64
        public var plantOffset: UInt64
        public var toastFileOffset: UInt64?
    }

    public static func isHosted(_ address: UInt64) -> Bool {
        guard address >= plantBase else { return false }
        let end = plantBase + max(toastDataForkLength, stubSectionOffset + 0x4000)
        return address < end
    }

    public static func map(_ address: UInt64) -> Location? {
        guard address >= plantBase else { return nil }
        let plantOffset = address - plantBase

        if address >= plantBase + stubSectionOffset {
            return Location(
                section: "stub",
                sectionOffset: address - (plantBase + stubSectionOffset),
                plantOffset: plantOffset,
                toastFileOffset: nil
            )
        }
        if address >= plantBase + dataSectionOffset {
            return Location(
                section: "data",
                sectionOffset: address - (plantBase + dataSectionOffset),
                plantOffset: plantOffset,
                toastFileOffset: nil
            )
        }
        if address >= plantBase + codeSectionOffset {
            return Location(
                section: "code",
                sectionOffset: address - (plantBase + codeSectionOffset),
                plantOffset: plantOffset,
                toastFileOffset: plantOffset < toastDataForkLength ? toastDataForkOffset + plantOffset : nil
            )
        }
        if address >= plantBase + pidataOffset {
            return Location(
                section: "pidata",
                sectionOffset: address - (plantBase + pidataOffset),
                plantOffset: plantOffset,
                toastFileOffset: toastDataForkOffset + plantOffset
            )
        }
        if address >= plantBase + loaderOffset {
            return Location(
                section: "loader",
                sectionOffset: address - (plantBase + loaderOffset),
                plantOffset: plantOffset,
                toastFileOffset: toastDataForkOffset + plantOffset
            )
        }
        if plantOffset < toastDataForkLength {
            return Location(
                section: "pef-file",
                sectionOffset: plantOffset,
                plantOffset: plantOffset,
                toastFileOffset: toastDataForkOffset + plantOffset
            )
        }
        return Location(
            section: "plant",
            sectionOffset: plantOffset,
            plantOffset: plantOffset,
            toastFileOffset: nil
        )
    }

    public static func format(_ address: UInt64) -> String {
        guard let location = map(address) else {
            return String(format: "0x%08X", address)
        }
        return format(location, guestPC: address)
    }

    public static func format(_ location: Location, guestPC: UInt64) -> String {
        var parts = [
            "PEF \(location.section)+\(hex(location.sectionOffset))",
            "plant+\(hex(location.plantOffset))",
        ]
        if let toastFileOffset = location.toastFileOffset {
            parts.append("toast+\(hex(toastFileOffset))")
        }
        parts.append(String(format: "pc=0x%08X", guestPC))
        return parts.joined(separator: ", ")
    }

    public static func describeFault(srr0: UInt64, dar: UInt64?) -> String {
        let pcText = format(srr0)
        guard let dar else { return "DSI SRR0 → \(pcText)" }
        if isHosted(srr0), dar >= dataSectionOffset, dar < stubSectionOffset {
            return "DSI SRR0 → \(pcText); DAR → PEF data+\(hex(dar - dataSectionOffset))"
        }
        if let darLocation = map(dar) {
            return "DSI SRR0 → \(pcText); DAR → PEF \(darLocation.section)+\(hex(darLocation.sectionOffset))"
        }
        return "DSI SRR0 → \(pcText); DAR=0x\(String(format: "%X", dar))"
    }

    private static func hex(_ value: UInt64) -> String {
        "0x" + String(format: "%X", value)
    }
}
