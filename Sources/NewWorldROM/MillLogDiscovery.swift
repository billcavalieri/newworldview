import Foundation

public enum MillLogDiscovery {
    public struct Options: Sendable, Equatable {
        public var directory: URL
        public var tmpDirectory: URL
        public var stateJSONPath: URL?
        public var pinnedMillNumbers: [Int]
        public var keepLogsOnly: Bool

        public init(
            directory: URL = MillResearchEngine.defaultLogDirectory,
            tmpDirectory: URL = URL(fileURLWithPath: "/tmp"),
            stateJSONPath: URL? = nil,
            pinnedMillNumbers: [Int] = MillSkip68kPolicy.pinnedKeepMillNumbers,
            keepLogsOnly: Bool = true
        ) {
            self.directory = directory
            self.tmpDirectory = tmpDirectory
            self.stateJSONPath = stateJSONPath
            self.pinnedMillNumbers = pinnedMillNumbers
            self.keepLogsOnly = keepLogsOnly
        }

        public static var `default`: Options {
            Options(stateJSONPath: defaultStateJSONPath())
        }

        /// Discovery options scoped to a user-granted log folder (sandbox-safe: no `/tmp` scan).
        public static func sandboxed(in directory: URL, keepLogsOnly: Bool = true) -> Options {
            Options(
                directory: directory,
                tmpDirectory: directory,
                stateJSONPath: MillLogDiscovery.resolveStateJSONPath(in: directory),
                keepLogsOnly: keepLogsOnly
            )
        }
    }

    public static func defaultStateJSONPath() -> URL? {
        resolveStateJSONPath(in: MillResearchEngine.defaultLogDirectory)
    }

    public static func resolveStateJSONPath(in directory: URL) -> URL? {
        let path = directory.appendingPathComponent("g3_driver/state.json")
        return FileManager.default.fileExists(atPath: path.path) ? path : nil
    }

    /// macemu writes active logs under `/tmp`; remap to the granted research-score folder when possible.
    public static func remappedLogURL(_ url: URL, preferredDirectory directory: URL) -> URL {
        let standardizedDirectory = directory.standardizedFileURL
        if url.standardizedFileURL.path.hasPrefix(standardizedDirectory.path) {
            return url
        }
        let name = url.lastPathComponent
        guard name.hasPrefix("ss-g3-mill-") || name.hasPrefix("ss-pr10-") else {
            return url
        }
        let candidate = standardizedDirectory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        if let resolved = MillLogReader.resolveOnDiskLog(named: name, in: standardizedDirectory) {
            return resolved
        }
        return url
    }

    public static func millNumber(from url: URL) -> Int? {
        MillLogReader.millNumber(from: url)
    }

    public static func keepLogFromState(_ stateURL: URL?, preferredDirectory: URL? = nil) -> URL? {
        guard let stateURL, FileManager.default.fileExists(atPath: stateURL.path),
              let data = try? Data(contentsOf: stateURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let mill = json["mill"] as? [String: Any],
              let keepLog = mill["keep_log"] as? String
        else { return nil }
        let url = URL(fileURLWithPath: keepLog)
        if let preferredDirectory {
            let remapped = remappedLogURL(url, preferredDirectory: preferredDirectory)
            if FileManager.default.fileExists(atPath: remapped.path) {
                return remapped
            }
        }
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return nil
    }

    /// When discovery is scoped to a granted folder (`tmpDirectory == directory`), drop `/tmp` paths.
    public static func isSandboxScoped(_ options: Options) -> Bool {
        options.tmpDirectory.standardizedFileURL.path == options.directory.standardizedFileURL.path
    }

    public static func resolvedLogURL(_ url: URL, options: Options) -> URL? {
        let remapped = remappedLogURL(url, preferredDirectory: options.directory)
        if isSandboxScoped(options) {
            let root = options.directory.standardizedFileURL.path
            guard remapped.standardizedFileURL.path.hasPrefix(root + "/") || remapped.standardizedFileURL.path == root else {
                return nil
            }
        }
        guard FileManager.default.fileExists(atPath: remapped.path) else { return nil }
        return remapped
    }

    public static func countAvailableLogFiles(in directory: URL) -> Int {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        return urls.filter { MillLogReader.isMillLogFile($0) }.count
    }

    public static func orderedLogURLs(options: Options = .default) throws -> [URL] {
        var ordered: [URL] = []
        var seen = Set<String>()

        func append(_ url: URL?) {
            guard let url, let resolved = resolvedLogURL(url, options: options) else { return }
            let key = resolved.standardizedFileURL.path
            guard seen.insert(key).inserted else { return }
            ordered.append(resolved)
        }

        let statePath = options.stateJSONPath ?? resolveStateJSONPath(in: options.directory)
        let keepLog = keepLogFromState(statePath, preferredDirectory: options.directory)
        append(keepLog)

        for millNumber in options.pinnedMillNumbers {
            append(logURL(forMillNumber: millNumber, tmpDirectory: options.tmpDirectory, directory: options.directory))
        }

        var numericLogs: [(mill: Int, url: URL)] = []
        var scanBases = [options.directory]
        if options.tmpDirectory.standardizedFileURL.path != options.directory.standardizedFileURL.path {
            scanBases.append(options.tmpDirectory)
        }
        for base in scanBases {
            guard let urls = try? FileManager.default.contentsOfDirectory(
                at: base,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for url in urls where MillLogReader.isMillLogFile(url) {
                guard let mill = millNumber(from: url) else { continue }
                numericLogs.append((mill, url))
            }
        }

        numericLogs.sort { lhs, rhs in
            if lhs.mill == rhs.mill {
                return lhs.url.path < rhs.url.path
            }
            return lhs.mill > rhs.mill
        }
        for entry in numericLogs {
            append(entry.url)
        }

        if options.keepLogsOnly {
            ordered = MillLogAnalysisRunner.filterKeepLogs(
                ordered,
                keepLog: keepLog,
                pinnedMillNumbers: options.pinnedMillNumbers,
                options: options
            )
        }

        return ordered
    }

    public static func logLooksLikeKeep(_ url: URL, options: Options = .default) -> Bool {
        guard let resolved = resolvedLogURL(url, options: options) else { return false }
        return MillLogAnalysisRunner.tailContainsKeepMarkers(resolved)
    }

    private static func logURL(forMillNumber mill: Int, tmpDirectory: URL, directory: URL) -> URL? {
        let name = "ss-g3-mill-\(mill).log"
        if let inDirectory = MillLogReader.resolveOnDiskLog(named: name, in: directory) {
            return inDirectory
        }
        if tmpDirectory.standardizedFileURL.path != directory.standardizedFileURL.path,
           let tmp = MillLogReader.resolveOnDiskLog(named: name, in: tmpDirectory) {
            return tmp
        }
        return nil
    }
}
