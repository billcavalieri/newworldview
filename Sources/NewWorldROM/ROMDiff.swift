import Foundation

public enum ROMDiff {
    public struct RegionDiff: Sendable, Equatable, Identifiable {
        public var id: UInt64 { offset }
        public var offset: UInt64
        public var oldByte: UInt8?
        public var newByte: UInt8?
    }

    public struct Result: Sendable, Equatable {
        public var changedBytes: Int
        public var firstChanges: [RegionDiff]
        public var leftNewWorldOK: Bool
        public var rightNewWorldOK: Bool
    }

    public static func compare(_ left: Data, _ right: Data, sampleLimit: Int = 64) -> Result {
        let count = max(left.count, right.count)
        var changes: [RegionDiff] = []
        var changedBytes = 0
        for offset in 0..<count {
            let oldByte = offset < left.count ? left[offset] : nil
            let newByte = offset < right.count ? right[offset] : nil
            if oldByte != newByte {
                changedBytes += 1
                if changes.count < sampleLimit {
                    changes.append(RegionDiff(offset: UInt64(offset), oldByte: oldByte, newByte: newByte))
                }
            }
        }
        return Result(
            changedBytes: changedBytes,
            firstChanges: changes,
            leftNewWorldOK: MacROMImageDecoder.g0OK(left),
            rightNewWorldOK: MacROMImageDecoder.g0OK(right)
        )
    }

    public static func compareFiles(at leftURL: URL, rightURL: URL) throws -> Result {
        let left = try MacROMImageDecoder.decode(Data(contentsOf: leftURL)).image
        let right = try MacROMImageDecoder.decode(Data(contentsOf: rightURL)).image
        return compare(left, right)
    }
}
