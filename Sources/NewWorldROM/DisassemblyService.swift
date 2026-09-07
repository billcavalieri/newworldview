import Capstone
import Foundation

public struct DisassembledInstruction: Sendable, Hashable, Identifiable {
    public var id: String { String(format: "%08llX-%@", address, bytes.map { String(format: "%02X", $0) }.joined()) }
    public let address: UInt64
    public let bytes: Data
    public let mnemonic: String
    public let operands: String

    public var formatted: String {
        let byteString = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        let paddedBytes = byteString.padding(toLength: 18, withPad: " ", startingAt: 0)
        let paddedMnemonic = mnemonic.padding(toLength: 8, withPad: " ", startingAt: 0)
        return String(format: "%08X:  ", address) + paddedBytes + paddedMnemonic + operands
    }
}

public enum DisassemblyService {
    public static let defaultByteLimit = 512 * 1024

    public static func disassemble(
        _ data: Data,
        isa: DisassemblyISA,
        baseAddress: UInt64 = 0,
        byteLimit: Int = defaultByteLimit
    ) -> (instructions: [DisassembledInstruction], truncated: Bool) {
        let truncated = data.count > byteLimit
        let slice = Data(truncated ? data.prefix(byteLimit) : data)
        do {
            let disassembler = try Disassembler(arch: architecture(isa), mode: mode(isa))
            let raw = disassembler.disassemble(code: slice, address: baseAddress)
            let instructions = raw.map { instruction in
                DisassembledInstruction(
                    address: instruction.address,
                    bytes: Data(instruction.bytes),
                    mnemonic: instruction.mnemonic,
                    operands: instruction.operandString
                )
            }
            return (instructions, truncated)
        } catch {
            return ([], truncated)
        }
    }

    public static func listing(
        _ data: Data,
        isa: DisassemblyISA,
        baseAddress: UInt64 = 0,
        byteLimit: Int = defaultByteLimit
    ) -> String {
        let result = disassemble(data, isa: isa, baseAddress: baseAddress, byteLimit: byteLimit)
        var lines: [String] = []
        if result.truncated {
            lines.append("# Disassembly truncated to \(byteLimit) bytes of \(data.count)")
        }
        if result.instructions.isEmpty {
            lines.append("# Capstone produced no instructions for \(isa.displayName).")
            return lines.joined(separator: "\n")
        }
        for instruction in result.instructions {
            lines.append(instruction.formatted)
        }
        return lines.joined(separator: "\n")
    }

    private static func architecture(_ isa: DisassemblyISA) -> cs_arch {
        switch isa {
        case .powerPC: return CS_ARCH_PPC
        case .m68k: return CS_ARCH_M68K
        }
    }

    private static func mode(_ isa: DisassemblyISA) -> cs_mode {
        switch isa {
        case .powerPC:
            return CS_MODE_BIG_ENDIAN
        case .m68k:
            return cs_mode(rawValue: CS_MODE_BIG_ENDIAN.rawValue | CS_MODE_M68K_040.rawValue)
        }
    }
}
