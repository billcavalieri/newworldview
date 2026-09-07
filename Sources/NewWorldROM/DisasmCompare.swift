import Foundation

public enum DisasmCompare {
    public struct Line: Sendable, Equatable, Identifiable {
        public var id: UInt64 { address }
        public var address: UInt64
        public var formatted: String
        public var tags: [String]
        public var millable: Bool
    }

    public struct Result: Sendable, Equatable {
        public var lines: [Line]
        public var romOffset: UInt64
        public var source: String
        public var isa: DisassemblyISA
    }

    /// Lower MacROM file offsets are 68k toolbox; from 0x300000 upward is PPC/NK territory.
    public static func disassemblyISA(forRomOffset offset: UInt64) -> DisassemblyISA {
        offset < 0x300_000 ? .m68k : .powerPC
    }

    public static func compareAtROMOffset(
        _ offset: UInt64,
        macROM: Data,
        database: AnalysisDatabase = .empty,
        instructionCount: Int = 12
    ) -> Result? {
        guard Int(offset) < macROM.count else { return nil }
        let isa = disassemblyISA(forRomOffset: offset)
        let slice = macROM.subdata(in: Int(offset)..<min(macROM.count, Int(offset) + 64))
        let baseAddress: UInt64
        let source: String
        switch isa {
        case .m68k:
            baseAddress = offset
            source = "capstone-m68k"
        case .powerPC:
            baseAddress = AddressSpaces.ppcMacROMBase + offset
            source = "capstone-ppc"
        }
        let dis = DisassemblyService.disassemble(slice, isa: isa, baseAddress: baseAddress, byteLimit: slice.count)
        let lines = dis.instructions.prefix(instructionCount).map { ins in
            let address = switch isa {
            case .m68k:
                ProgramAddress(space: .m68kToolbox, address: ins.address)
            case .powerPC:
                ProgramAddress(space: .ppcMacROM, address: ins.address)
            }
            let tags = AddressTranslation.millTags(for: address)
            let millable = MillSkip68kPolicy.isMillable(offset: offset)
                && !tags.contains("68k-emulator-JT")
                && !tags.contains("get-new-dialog-stub")
            return Line(
                address: ins.address,
                formatted: ins.formatted,
                tags: tags,
                millable: millable
            )
        }
        return Result(lines: Array(lines), romOffset: offset, source: source, isa: isa)
    }

    public static func compareAtAddress(
        _ address: ProgramAddress,
        macROM: Data,
        database: AnalysisDatabase = .empty
    ) -> Result? {
        switch address.space {
        case .ppcMacROM:
            guard let offset = AddressTranslation.romOffset(fromVirtual: address.address) else { return nil }
            return compareAtROMOffset(offset, macROM: macROM, database: database)
        case .m68kToolbox:
            return compareAtROMOffset(address.address, macROM: macROM, database: database)
        case .toolboxTrap, .pef, .elf, .unknown:
            return nil
        }
    }
}
