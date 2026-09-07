import Foundation

/// Decompress a NewWorld tbxi image into the 4 MiB SheepShaver MacROM layout
/// (`rom_disasm.py` / `nw_decode_rom_image` parity).
public enum MacROMImageDecoder {
    public static let romSize = Int(AddressSpaces.ppcMacROMSize)
    public static let fourCCPrcl: UInt32 = 0x7072_636C // "prcl"
    public static let fourCCRom: UInt32 = 0x726F_6D20 // "rom "

    public enum DecodeError: Error, LocalizedError {
        case unsupportedFormat
        case truncatedPayload
        case parcelDecodeFailed

        public var errorDescription: String? {
            switch self {
            case .unsupportedFormat: return "Could not decode a 4 MiB MacROM from this tbxi image."
            case .truncatedPayload: return "Compressed ROM payload extends past the file end."
            case .parcelDecodeFailed: return "Parcel chain did not contain a decompressible ROM parcel."
            }
        }
    }

    public struct DecodeResult: Sendable, Equatable {
        public var image: Data
        public var source: String
        public var newWorldOK: Bool

        public init(image: Data, source: String, newWorldOK: Bool) {
            self.image = image
            self.source = source
            self.newWorldOK = newWorldOK
        }
    }

    public static func decode(_ raw: Data) throws -> DecodeResult {
        if raw.count == romSize {
            return DecodeResult(image: raw, source: "plain-4mb", newWorldOK: g0OK(raw))
        }
        if raw.count >= romSize, !isBootInfo(raw) {
            let slice = Data(raw.prefix(romSize))
            return DecodeResult(image: slice, source: "prefix-4mb", newWorldOK: g0OK(slice))
        }
        guard isBootInfo(raw) else {
            throw DecodeError.unsupportedFormat
        }

        let constants = BootInfoParser.parseConstants(raw)
        var offset = constants["lzss-offset"]
        var size = constants["lzss-size"]
        if offset == nil || size == nil || size == 0 {
            offset = constants["parcels-offset"]
            size = constants["parcels-size"]
        }
        guard let payloadOffset = offset, let payloadSize = size, payloadSize > 0 else {
            throw DecodeError.unsupportedFormat
        }
        guard payloadOffset + payloadSize <= raw.count else {
            throw DecodeError.truncatedPayload
        }
        let blob = raw.subdata(in: payloadOffset..<(payloadOffset + payloadSize))
        let signature = blob.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }

        let image: Data
        let source: String
        if signature == fourCCPrcl {
            guard let decoded = decodeParcels(blob) else {
                throw DecodeError.parcelDecodeFailed
            }
            image = decoded
            source = "parcels"
        } else {
            image = LZSSDecoder.decompress(blob, destinationLength: romSize)
            source = "lzss"
        }
        return DecodeResult(image: image, source: source, newWorldOK: g0OK(image))
    }

    public static func g0OK(_ image: Data) -> Bool {
        let markerOffset = 0x30D064
        guard image.count >= markerOffset + 8 else { return false }
        return image.subdata(in: markerOffset..<(markerOffset + 8)) == Data("NewWorld".utf8)
    }

    private static func isBootInfo(_ data: Data) -> Bool {
        BootInfoParser.isBootInfo(data)
    }

    private static func decodeParcels(_ src: Data) -> Data? {
        var dest = Data(repeating: 0, count: romSize)
        var parcelOffset = 0x14
        var decoded = false

        while parcelOffset != 0, parcelOffset + 12 <= src.count {
            guard let next = be32(src, parcelOffset),
                  let parcelType = be32(src, parcelOffset + 4)
            else { break }

            if parcelType == fourCCRom {
                guard let lzssOffset = be32(src, parcelOffset + 8) else { return nil }
                let parcelEnd = next == 0 ? src.count : next
                let blobStart = parcelOffset + lzssOffset
                guard parcelEnd > blobStart, blobStart < src.count else { return nil }
                let blob = src.subdata(in: blobStart..<min(parcelEnd, src.count))
                let out = LZSSDecoder.decompress(blob, destinationLength: romSize)
                dest.replaceSubrange(0..<min(out.count, romSize), with: out.prefix(romSize))
                decoded = true
            }

            if next == 0 || next <= parcelOffset { break }
            parcelOffset = next
        }
        return decoded ? dest : nil
    }

    private static func be32(_ data: Data, _ offset: Int) -> Int? {
        guard offset + 4 <= data.count else { return nil }
        let value = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self).bigEndian }
        return Int(value)
    }
}
