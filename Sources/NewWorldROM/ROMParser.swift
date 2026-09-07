import Foundation

enum ROMDispatcher {
    static func parse(
        _ data: Data,
        name: String,
        id: String,
        containerOffset: Int?,
        resourceFork: Data?
    ) -> ROMNode {
        do {
            return try BootInfoParser.parse(
                data,
                name: name,
                id: id,
                containerOffset: containerOffset,
                resourceFork: resourceFork
            )
        } catch ROMParseError.unrecognizedFormat {
            // try the next format
        } catch {
            return errorNode(id: id, name: name, data: data, error: error, containerOffset: containerOffset)
        }

        do {
            return try ParcelParser.parse(data, name: name, id: id, containerOffset: containerOffset)
        } catch ROMParseError.unrecognizedFormat {
            // continue
        } catch {
            return errorNode(id: id, name: name, data: data, error: error, containerOffset: containerOffset)
        }

        do {
            return try MacROMParser.parse(data, name: name, id: id, containerOffset: containerOffset)
        } catch ROMParseError.unrecognizedFormat {
            // continue
        } catch {
            return errorNode(id: id, name: name, data: data, error: error, containerOffset: containerOffset)
        }

        do {
            return try SuperMarioParser.parse(data, name: name, id: id, containerOffset: containerOffset)
        } catch ROMParseError.unrecognizedFormat {
            // continue
        } catch {
            return errorNode(id: id, name: name, data: data, error: error, containerOffset: containerOffset)
        }

        do {
            return try PEFParser.parse(data, name: name, id: id, containerOffset: containerOffset)
        } catch ROMParseError.unrecognizedFormat {
            // continue
        } catch {
            return errorNode(id: id, name: name, data: data, error: error, containerOffset: containerOffset)
        }

        do {
            return try ELFParser.parse(data, name: name, id: id, containerOffset: containerOffset)
        } catch ROMParseError.unrecognizedFormat {
            // continue
        } catch {
            return errorNode(id: id, name: name, data: data, error: error, containerOffset: containerOffset)
        }

        return ROMNode.leaf(
            id: id,
            name: name,
            data: data,
            kind: inferredKind(data),
            containerOffset: containerOffset
        )
    }

    static func inferredKind(_ data: Data) -> ROMContentKind {
        if data.looksLikeText { return .text }
        return .binary
    }

    static func uniquedName(_ base: String, used: inout Set<String>) -> String {
        let candidate = base.isEmpty ? "untitled" : base
        if !used.contains(candidate) {
            used.insert(candidate)
            return candidate
        }
        var index = 2
        while used.contains("\(candidate)-\(index)") {
            index += 1
        }
        let unique = "\(candidate)-\(index)"
        used.insert(unique)
        return unique
    }

    private static func errorNode(
        id: String,
        name: String,
        data: Data,
        error: Error,
        containerOffset: Int?
    ) -> ROMNode {
        ROMNode(
            id: id,
            name: name,
            kind: .folder,
            data: data,
            text: "Parse error: \(error.localizedDescription)",
            containerOffset: containerOffset,
            children: [
                ROMNode.leaf(
                    id: id + "/raw",
                    name: "Raw data",
                    data: data,
                    kind: .binary,
                    containerOffset: containerOffset
                )
            ],
            metadata: ["error": error.localizedDescription]
        )
    }
}

public enum ROMParser {
    public static func parse(data: Data, resourceFork: Data? = nil, fileName: String) -> ParsedROM {
        var warnings: [String] = []
        if data.isEmpty {
            warnings.append("The file is empty.")
        }

        let root = ROMDispatcher.parse(
            data,
            name: fileName,
            id: fileName,
            containerOffset: 0,
            resourceFork: resourceFork
        )

        if root.children.isEmpty {
            warnings.append("The file was not recognized as a NewWorld tbxi ROM; showing raw bytes.")
        }

        return ParsedROM(root: root, fileName: fileName, fileSize: data.count, warnings: warnings)
    }
}
