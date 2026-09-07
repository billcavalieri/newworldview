import Foundation

public enum ROMParseError: Error, Equatable, Sendable, LocalizedError {
    case unrecognizedFormat
    case truncated(String)
    case invalidMagic(expected: String, found: String)

    public var errorDescription: String? {
        switch self {
        case .unrecognizedFormat:
            return "Not a recognized NewWorld ROM format."
        case .truncated(let detail):
            return "ROM data is truncated: \(detail)"
        case .invalidMagic(let expected, let found):
            return "Unexpected magic (expected \(expected), found \(found))."
        }
    }
}

enum BinaryCursor {
    static func require(_ data: Data, offset: Int, count: Int, context: String) throws {
        guard offset >= 0, count >= 0, offset <= data.count, offset + count <= data.count else {
            throw ROMParseError.truncated("\(context) at \(offset)+\(count) in \(data.count) bytes")
        }
    }

    static func slice(_ data: Data, offset: Int, count: Int, context: String) throws -> Data {
        try require(data, offset: offset, count: count, context: context)
        return data.subdata(in: offset..<(offset + count))
    }

    static func u8(_ data: Data, _ offset: Int, context: String = "u8") throws -> UInt8 {
        try require(data, offset: offset, count: 1, context: context)
        return data[data.startIndex + offset]
    }

    static func u16be(_ data: Data, _ offset: Int, context: String = "u16") throws -> UInt16 {
        let bytes = try slice(data, offset: offset, count: 2, context: context)
        return UInt16(bytes[bytes.startIndex]) << 8 | UInt16(bytes[bytes.startIndex + 1])
    }

    static func u32be(_ data: Data, _ offset: Int, context: String = "u32") throws -> UInt32 {
        let bytes = try slice(data, offset: offset, count: 4, context: context)
        return UInt32(bytes[bytes.startIndex]) << 24
            | UInt32(bytes[bytes.startIndex + 1]) << 16
            | UInt32(bytes[bytes.startIndex + 2]) << 8
            | UInt32(bytes[bytes.startIndex + 3])
    }

    static func i32be(_ data: Data, _ offset: Int, context: String = "i32") throws -> Int32 {
        Int32(bitPattern: try u32be(data, offset, context: context))
    }

    static func u64be(_ data: Data, _ offset: Int, context: String = "u64") throws -> UInt64 {
        let hi = try u32be(data, offset, context: context)
        let lo = try u32be(data, offset + 4, context: context)
        return UInt64(hi) << 32 | UInt64(lo)
    }

    static func fourCC(_ data: Data, _ offset: Int, context: String = "FourCC") throws -> String {
        let bytes = try slice(data, offset: offset, count: 4, context: context)
        if let mac = String(data: bytes, encoding: .macOSRoman) {
            return mac
        }
        return String(data: bytes, encoding: .isoLatin1) ?? String(repeating: "?", count: bytes.count)
    }

    static func cString(_ data: Data, offset: Int, maxLength: Int, context: String = "cString") throws -> String {
        let bytes = try slice(data, offset: offset, count: maxLength, context: context)
        let trimmed = bytes.prefix { $0 != 0 }
        return String(data: Data(trimmed), encoding: .macOSRoman)
            ?? String(data: Data(trimmed), encoding: .isoLatin1)
            ?? ""
    }

    static func pascalString(_ data: Data, offset: Int, context: String = "pString") throws -> Data {
        let length = Int(try u8(data, offset, context: context))
        return try slice(data, offset: offset + 1, count: length, context: context)
    }

    static func macRoman(_ data: Data) -> String {
        String(data: data, encoding: .macOSRoman)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
    }

    static func hex(_ value: UInt32, width: Int = 8) -> String {
        String(format: "0x%0\(width)X", value)
    }

    static func hex(_ value: Int, width: Int = 8) -> String {
        if value < 0 {
            return String(format: "-0x%0\(width)X", -value)
        }
        return String(format: "0x%0\(width)X", value)
    }
}

extension Data {
    func starts(withASCII ascii: String) -> Bool {
        starts(with: ascii.utf8)
    }

    var looksLikeText: Bool {
        if isEmpty { return false }
        let sample = prefix(4096)
        if sample.contains(0) { return false }
        let printable = sample.filter { byte in
            byte == 9 || byte == 10 || byte == 13 || (32...126).contains(byte)
        }
        return printable.count * 10 >= sample.count * 8
    }
}
