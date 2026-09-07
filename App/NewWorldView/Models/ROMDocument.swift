import NewWorldROM
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    nonisolated static var macOSROM: UTType {
        UTType(importedAs: "com.newworldview.macos-rom")
    }
}

struct ROMDocument: FileDocument {
    nonisolated static var readableContentTypes: [UTType] { [.macOSROM, .data] }
    nonisolated static var writableContentTypes: [UTType] { [] }

    let data: Data
    let parsed: ParsedROM

    nonisolated init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
        let name = configuration.file.filename ?? "Mac OS ROM"
        self.parsed = ROMParser.parse(data: data, fileName: name)
    }

    nonisolated func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        throw CocoaError(.fileWriteNoPermission)
    }
}

enum ResourceForkLoader {
    nonisolated static func data(at url: URL) -> Data? {
        let namedFork = url.appendingPathComponent("..namedfork/rsrc")
        guard let data = try? Data(contentsOf: namedFork), !data.isEmpty else {
            return nil
        }
        return data
    }
}
