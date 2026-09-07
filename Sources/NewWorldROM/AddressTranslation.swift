import Foundation

/// Virtual address ↔ MacROM file offset translation (`ROM_BASE = 0x50000000`).
public enum AddressTranslation {
    public static let heartbeatClusterLow: UInt64 = 0x5032_5000
    public static let heartbeatClusterHigh: UInt64 = 0x5032_7000
    public static let reached68kPC: UInt64 = 0x5036_6084

    public struct ParsedAddress: Sendable, Equatable {
        public var space: AddressSpace
        public var address: UInt64
        public var romOffset: UInt64?

        public var programAddress: ProgramAddress {
            ProgramAddress(space: space, address: address)
        }

        public var display: String { programAddress.display }
    }

    /// Normalize SheepShaver 68k map/spin `r24=` values to MacROM file offsets.
    public static func romOffset(fromR24 r24: UInt64) -> UInt64 {
        r24 >= AddressSpaces.ppcMacROMBase ? r24 - AddressSpaces.ppcMacROMBase : r24
    }

    public static func romOffset(fromVirtual address: UInt64, space: AddressSpace = .ppcMacROM) -> UInt64? {
        switch space {
        case .ppcMacROM:
            guard address >= AddressSpaces.ppcMacROMBase else { return nil }
            let offset = address - AddressSpaces.ppcMacROMBase
            guard offset < AddressSpaces.ppcMacROMSize else { return nil }
            return offset
        case .m68kToolbox, .toolboxTrap:
            guard address < AddressSpaces.ppcMacROMSize else { return nil }
            return address
        case .pef, .elf, .unknown:
            return nil
        }
    }

    public static func virtualAddress(fromRomOffset offset: UInt64, space: AddressSpace) -> ProgramAddress {
        switch space {
        case .ppcMacROM:
            return ProgramAddress(space: .ppcMacROM, address: AddressSpaces.ppcMacROMBase + offset)
        case .m68kToolbox, .toolboxTrap:
            return ProgramAddress(space: space, address: offset)
        case .pef, .elf, .unknown:
            return ProgramAddress(space: space, address: offset)
        }
    }

    public static func parse(_ text: String) -> ParsedAddress? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            let prefix = parts[0].uppercased()
            let valueText = parts[1].replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
            guard let value = UInt64(valueText, radix: 16) else { return nil }
            switch prefix {
            case "PPC", "ROM", "MACROM":
                return ParsedAddress(space: .ppcMacROM, address: value, romOffset: romOffset(fromVirtual: value))
            case "68K", "M68K", "TOOLBOX":
                return ParsedAddress(space: .m68kToolbox, address: value, romOffset: value)
            case "TRAP", "A":
                return ParsedAddress(space: .toolboxTrap, address: value, romOffset: nil)
            default:
                break
            }
        }

        let hex = trimmed
            .replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: " ", with: "")
        guard let value = UInt64(hex, radix: 16) else { return nil }

        if value >= AddressSpaces.ppcMacROMBase {
            return ParsedAddress(
                space: .ppcMacROM,
                address: value,
                romOffset: romOffset(fromVirtual: value)
            )
        }
        if value >= 0x5030_0000 {
            return ParsedAddress(
                space: .ppcMacROM,
                address: value,
                romOffset: romOffset(fromVirtual: value)
            )
        }
        if value <= 0xFFFF {
            return ParsedAddress(space: .m68kToolbox, address: value, romOffset: value)
        }
        return ParsedAddress(space: .ppcMacROM, address: AddressSpaces.ppcMacROMBase + value, romOffset: value)
    }

    public static func isHeartbeatCluster(_ address: UInt64) -> Bool {
        address >= heartbeatClusterLow && address < heartbeatClusterHigh
    }

    public static func isGetNewDialogStubRange(_ offset: UInt64) -> Bool {
        offset >= AddressSpaces.getNewDialogStub && offset < AddressSpaces.getNewDialogStubEnd
    }

    public static func isCode66HelperRange(_ offset: UInt64) -> Bool {
        MillSkip68kPolicy.code66HelperRange.contains(offset)
    }

    public static func millTags(for address: ProgramAddress) -> [String] {
        var tags: [String] = []
        switch address.space {
        case .ppcMacROM:
            if isHeartbeatCluster(address.address) { tags.append("heartbeat-cluster") }
            if address.address == reached68kPC { tags.append("reached-68k") }
            if let offset = romOffset(fromVirtual: address.address) {
                if isGetNewDialogStubRange(offset) { tags.append("get-new-dialog-stub") }
                if isCode66HelperRange(offset) { tags.append("code66-helper") }
                if offset >= 0x350_000 && offset < 0x400_000 { tags.append("68k-emulator-JT") }
            }
        case .m68kToolbox:
            if isGetNewDialogStubRange(address.address) { tags.append("get-new-dialog-stub") }
            if isCode66HelperRange(address.address) { tags.append("code66-helper") }
            if address.address >= 0x26E80 && address.address <= 0x26EA0 { tags.append("skip-slot-helper") }
            if !MillSkip68kPolicy.isMillable(offset: address.address) {
                tags.append("mill-blocked")
            }
        case .toolboxTrap:
            let trap = UInt16(address.address & 0xFFFF)
            if ATrapTable.noSkipUITraps.contains(trap) { tags.append("no-skip-ui-trap") }
            if MillCriticalTraps.all.contains(trap) { tags.append("mill-critical-trap") }
        default:
            break
        }
        return tags
    }
}

public enum MillCriticalTraps {
    public static let all: Set<UInt16> = ATrapTable.noSkipUITraps
        .union([0xAA5A, 0xA868, 0xA01F, 0xA002, 0xA003, 0xA044])
}
