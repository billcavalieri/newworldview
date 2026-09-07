import Foundation
import NewWorldROM
import Testing

struct LZSSDecoderTests {
    @Test func decompressesLiteralBytes() {
        let compressed = Data([0x1F, 0x48, 0x65, 0x6C, 0x6C, 0x6F])
        #expect(LZSSDecoder.decompress(compressed) == Data("Hello".utf8))
    }

    @Test func decompressesDictionaryMatchFromInitialSpaces() {
        let compressed = Data([0x01, 0x58, 0x00, 0x02])
        #expect(LZSSDecoder.decompress(compressed) == Data("X     ".utf8))
    }

    @Test func decompressesBackReference() {
        let compressed = Data([0x07, 0x41, 0x42, 0x43, 0xEE, 0xF0])
        #expect(LZSSDecoder.decompress(compressed) == Data("ABCABC".utf8))
    }

    @Test func roundTripViaLiteralEncoding() {
        let plain = Data("NewWorld ROM viewer LZSS fixture".utf8)
        let compressed = literalLZSS(plain)
        #expect(LZSSDecoder.decompress(compressed) == plain)
    }

    private func literalLZSS(_ plain: Data) -> Data {
        var output = Data()
        var index = 0
        let bytes = Array(plain)
        while index < bytes.count {
            let remaining = min(8, bytes.count - index)
            var header: UInt8 = 0
            var block = Data()
            for bit in 0..<remaining {
                header |= 1 << bit
                block.append(bytes[index + bit])
            }
            output.append(header)
            output.append(block)
            index += remaining
        }
        return output
    }
}
