import Foundation

/// Classic Mac LZSS as used by NewWorld parcels and tbxi (`N=0x1000`, `F=18`, threshold 2).
public enum LZSSDecoder {
    public static let windowSize = 0x1000
    public static let matchMax = 18

    public static func decompress(_ lzss: Data, destinationLength: Int? = nil) -> Data {
        var plain = Data()
        let capacity = destinationLength ?? max(lzss.count * 2, 64)
        plain.reserveCapacity(capacity)

        var dictionary = [UInt8](repeating: 0x20, count: windowSize)
        var dictIndex = windowSize - matchMax
        var input = lzss.makeIterator()

        func push(_ byte: UInt8) {
            dictionary[dictIndex % windowSize] = byte
            dictIndex += 1
            if let destinationLength, plain.count >= destinationLength { return }
            plain.append(byte)
        }

        while let header = input.next() {
            if let destinationLength, plain.count >= destinationLength { break }
            for bit in 0..<8 {
                if (header >> bit) & 1 == 1 {
                    guard let literal = input.next() else { return plain }
                    push(literal)
                } else {
                    guard let byte1 = input.next(), let byte2 = input.next() else { return plain }
                    let lookup = Int((UInt16(byte2) << 4) & 0xF00) | Int(byte1)
                    let length = Int(byte2 & 0x0F) + 3
                    for index in lookup..<(lookup + length) {
                        if let destinationLength, plain.count >= destinationLength { break }
                        push(dictionary[index % windowSize])
                    }
                }
            }
        }

        return plain
    }
}
