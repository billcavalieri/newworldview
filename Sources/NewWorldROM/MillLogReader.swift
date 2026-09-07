import Foundation
import zlib

public enum MillLogReader {
    public enum ReadError: Error, LocalizedError {
        case openFailed(URL)
        case readFailed(URL)
        case invalidUTF8(URL)

        public var errorDescription: String? {
            switch self {
            case .openFailed(let url):
                return "Could not open mill log at \(url.path)."
            case .readFailed(let url):
                return "Could not read mill log at \(url.path)."
            case .invalidUTF8(let url):
                return "Mill log is not valid UTF-8: \(url.path)."
            }
        }
    }

    public static func isMillLogFile(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        guard name.hasPrefix("ss-g3-mill-") else { return false }
        return name.hasSuffix(".log") || name.hasSuffix(".log.gz")
    }

    public static func isGzipFile(_ url: URL) -> Bool {
        url.lastPathComponent.hasSuffix(".log.gz")
    }

    /// Stable display name (`ss-g3-mill-6613.log`) even when stored as `.log.gz`.
    public static func displayFileName(for url: URL) -> String {
        let name = url.lastPathComponent
        if name.hasSuffix(".log.gz") {
            return String(name.dropLast(3))
        }
        return name
    }

    public static func millNumber(from url: URL) -> Int? {
        let displayName = displayFileName(for: url)
        guard displayName.hasPrefix("ss-g3-mill-"), displayName.hasSuffix(".log") else { return nil }
        let suffix = displayName.dropFirst("ss-g3-mill-".count).dropLast(".log".count)
        return Int(suffix)
    }

    /// Resolve a log path to an on-disk sibling (raw or `.log.gz`) inside `directory`.
    public static func resolveOnDiskLog(named name: String, in directory: URL) -> URL? {
        let base = directory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: base.path) {
            return base
        }
        if name.hasSuffix(".log") {
            let gz = directory.appendingPathComponent(name + ".gz")
            if FileManager.default.fileExists(atPath: gz.path) {
                return gz
            }
        } else if name.hasSuffix(".log.gz") {
            let raw = directory.appendingPathComponent(String(name.dropLast(3)))
            if FileManager.default.fileExists(atPath: raw.path) {
                return raw
            }
        }
        return nil
    }

    public static func decompressedContents(of url: URL) throws -> Data {
        if isGzipFile(url) {
            return try GzipLogReadHandle(url: url).readAll()
        }
        return try Data(contentsOf: url)
    }

    public static func decompressedString(from url: URL) throws -> String {
        let data = try decompressedContents(of: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ReadError.invalidUTF8(url)
        }
        return text
    }

    public static func readTail(of url: URL, maxBytes: Int) throws -> Data {
        let handle = try LogReadHandle(url: url)
        defer { handle.close() }
        return try handle.readTail(maxBytes: maxBytes)
    }

    static func open(forReadingFrom url: URL) throws -> LogReadHandle {
        try LogReadHandle(url: url)
    }
}

final class LogReadHandle {
    private let url: URL
    private var fileHandle: FileHandle?
    private var gzFile: gzFile?

    init(url: URL) throws {
        self.url = url
        if MillLogReader.isGzipFile(url) {
            gzFile = gzopen(url.path, "rb")
            guard gzFile != nil else { throw MillLogReader.ReadError.openFailed(url) }
        } else {
            fileHandle = try FileHandle(forReadingFrom: url)
        }
    }

    deinit {
        close()
    }

    func close() {
        if let gzFile {
            gzclose(gzFile)
            self.gzFile = nil
        }
        if let fileHandle {
            try? fileHandle.close()
            self.fileHandle = nil
        }
    }

    func read(upToCount: Int) throws -> Data? {
        guard upToCount > 0 else { return nil }
        if let gzFile {
            var buffer = [UInt8](repeating: 0, count: upToCount)
            let read = gzread(gzFile, &buffer, UInt32(upToCount))
            if read < 0 {
                throw MillLogReader.ReadError.readFailed(url)
            }
            if read == 0 {
                return nil
            }
            return Data(buffer.prefix(Int(read)))
        }
        guard let fileHandle else { return nil }
        guard let chunk = try fileHandle.read(upToCount: upToCount) else { return nil }
        return chunk.isEmpty ? nil : chunk
    }

    func readTail(maxBytes: Int) throws -> Data {
        if gzFile != nil {
            var tail = Data()
            tail.reserveCapacity(min(maxBytes, 8192))
            while let chunk = try read(upToCount: 8192) {
                tail.append(chunk)
                if tail.count > maxBytes {
                    tail.removeFirst(tail.count - maxBytes)
                }
            }
            return tail
        }

        guard let fileHandle else { return Data() }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let tailSize = min(size, maxBytes)
        guard tailSize > 0 else { return Data() }
        try fileHandle.seek(toOffset: UInt64(max(0, size - tailSize)))
        return try fileHandle.readToEnd() ?? Data()
    }

    func readAll() throws -> Data {
        var result = Data()
        result.reserveCapacity(4096)
        while true {
            guard let chunk = try read(upToCount: 512 * 1024) else { break }
            result.append(chunk)
        }
        return result
    }
}

private typealias GzipLogReadHandle = LogReadHandle
