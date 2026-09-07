import Foundation
import NewWorldROM

struct DetailScrollTarget: Equatable {
    var nodeID: ROMNode.ID
    var address: ProgramAddress
    var requestID: UUID
}

enum DetailNavigation {
    static func scrollLinePrefix(for address: ProgramAddress) -> String {
        String(format: "%08X:", address.address)
    }

    static func address(fromDisassemblyLine line: String) -> UInt64? {
        guard line.count >= 9, line[line.index(line.startIndex, offsetBy: 8)] == ":" else { return nil }
        let prefix = line.prefix(8)
        guard prefix.allSatisfy({ $0.isHexDigit }) else { return nil }
        return UInt64(prefix, radix: 16)
    }

    static func line(containingUTF16Index index: Int, in text: String) -> String {
        guard !text.isEmpty else { return "" }
        let lineRange = lineRange(containingUTF16Index: index, in: text)
        return (text as NSString).substring(with: lineRange)
    }

    static func lineRange(containingUTF16Index index: Int, in text: String) -> NSRange {
        guard !text.isEmpty else { return NSRange(location: 0, length: 0) }
        let clamped = max(0, min(index, text.utf16.count))
        return (text as NSString).lineRange(for: NSRange(location: clamped, length: 0))
    }
}
