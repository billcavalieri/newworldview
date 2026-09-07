import Foundation

/// ResViewer toast catalog access via `ResViewerCLI ls/get` (JSON envelope).
public enum ToastCatalogLookup {
    public static let cliEnvironmentKey = "RESVIEWER_CLI"
    public static let toastEnvironmentKey = "RESVIEWER_TOAST"

    public static let macOSInstallPath = "Mac OS 9.2.1/Mac OS Install"
    public static let kajrInstallerPath = "Mac OS 9.2.1/CD Extras/Additional Modem Scripts/Installer"
    public static let installDocumentPath = "Mac OS 9.2.1/Install Mac OS 9.2.1"

    public struct Configuration: Sendable, Equatable {
        public var cliURL: URL
        public var toastImageURL: URL

        public init(cliURL: URL, toastImageURL: URL) {
            self.cliURL = cliURL
            self.toastImageURL = toastImageURL
        }
    }

    public struct CatalogEntry: Sendable, Codable, Equatable, Identifiable {
        public var id: String { path }
        public var path: String
        public var name: String
        public var isDirectory: Bool
        public var type: String
        public var creator: String
        public var dataSize: UInt32
        public var resourceSize: UInt32
        public var role: String?
    }

    public struct QuickDrawRect: Sendable, Codable, Equatable {
        public var top: Int
        public var left: Int
        public var bottom: Int
        public var right: Int

        public var width: Int { max(0, right - left) }
        public var height: Int { max(0, bottom - top) }
    }

    public struct DLOGTemplate: Sendable, Codable, Equatable {
        public var bounds: QuickDrawRect
        public var procID: Int
        public var visible: Bool
        public var goAway: Bool
        public var refCon: Int
        public var itemsID: Int
        public var title: String
        public var warning: String?
    }

    public struct CFRGFragment: Sendable, Codable, Equatable {
        public var architecture: String?
        public var name: String?
    }

    public struct CFRGTemplate: Sendable, Codable, Equatable {
        public var fragments: [CFRGFragment]
    }

    public struct PEFSummary: Sendable, Codable, Equatable {
        public var architecture: String?
        public var sectionCount: Int?
    }

    public struct GetResult: Sendable, Codable, Equatable {
        public var path: String
        public var type: String
        public var id: Int
        public var name: String
        public var size: Int
        public var role: String?
        public var dlog: DLOGTemplate?
        public var cfrg: CFRGTemplate?
        public var pef: PEFSummary?
        public var warning: String?
    }

    public enum LookupError: Error, LocalizedError, Sendable {
        case configurationUnavailable
        case cliFailed(status: Int32, message: String)
        case invalidResponse(String)

        public var errorDescription: String? {
            switch self {
            case .configurationUnavailable:
                return "ResViewerCLI or toast image not found. Set RESVIEWER_CLI and RESVIEWER_TOAST."
            case .cliFailed(let status, let message):
                return "ResViewerCLI exited \(status): \(message)"
            case .invalidResponse(let detail):
                return "Invalid ResViewerCLI JSON: \(detail)"
            }
        }
    }

    public struct Client: Sendable {
        public var configuration: Configuration

        public init(configuration: Configuration) {
            self.configuration = configuration
        }

        public static func resolved() throws -> Client {
            guard let configuration = resolveConfiguration() else {
                throw LookupError.configurationUnavailable
            }
            return Client(configuration: configuration)
        }

        public func ls(path: String? = nil) throws -> [CatalogEntry] {
            var args: [String] = []
            if let path, !path.isEmpty {
                args += ["--path", path]
            }
            return try run(command: "ls", arguments: args)
        }

        public func get(
            type: String,
            id: Int,
            path: String? = nil,
            format: String = "json",
            offset: UInt64? = nil
        ) throws -> GetResult {
            var args = ["--type", type, "--id", String(id), "--format", format]
            if let path, !path.isEmpty {
                args += ["--path", path]
            }
            if let offset {
                args += ["--offset", String(offset)]
            }
            return try run(command: "get", arguments: args)
        }

        public func find(type: String, id: Int, path: String? = nil) throws -> [CatalogEntry] {
            var args = ["--type", type, "--id", String(id)]
            if let path, !path.isEmpty {
                args += ["--path", path]
            }
            let hits: [FindHit] = try run(command: "find", arguments: args)
            return hits.map {
                CatalogEntry(
                    path: $0.path,
                    name: $0.name,
                    isDirectory: false,
                    type: $0.type,
                    creator: "",
                    dataSize: 0,
                    resourceSize: UInt32(clamping: $0.size),
                    role: nil
                )
            }
        }

        private struct FindHit: Decodable {
            var path: String
            var type: String
            var id: Int
            var name: String
            var size: Int
        }

        private func run<T: Decodable>(command: String, arguments: [String]) throws -> T {
            let process = Process()
            process.executableURL = configuration.cliURL
            process.arguments = [command, configuration.toastImageURL.path] + arguments

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            try process.run()
            process.waitUntilExit()

            let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            guard process.terminationStatus == 0 else {
                let message = ToastCatalogLookup.extractErrorMessage(from: stdout) ?? stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                throw LookupError.cliFailed(status: process.terminationStatus, message: message.isEmpty ? "no output" : message)
            }
            return try ToastCatalogLookup.decodeEnvelope(command: command, from: stdout)
        }
    }

    public static func resolveConfiguration(
        cliURL: URL? = nil,
        toastImageURL: URL? = nil
    ) -> Configuration? {
        let cli = cliURL ?? resolveCLIURL()
        let toast = toastImageURL ?? resolveToastImageURL()
        guard let cli, let toast,
              FileManager.default.isExecutableFile(atPath: cli.path),
              FileManager.default.fileExists(atPath: toast.path)
        else { return nil }
        return Configuration(cliURL: cli, toastImageURL: toast)
    }

    /// Markdown lines for mill escalation / analysis when toast is available.
    public static func millContextLines(
        launchA9F2: Bool = false,
        loadSeg66: Bool = false,
        client: Client? = try? Client.resolved()
    ) -> [String] {
        var lines: [String] = []
        if let role = G3MillClassification.toastRole(launchA9F2: launchA9F2, loadSeg66: loadSeg66) {
            lines.append(role.millNote)
        }

        guard let client else {
            lines.append("(Toast catalog unavailable — set RESVIEWER_CLI and RESVIEWER_TOAST to enable ResViewer lookup.)")
            return lines
        }

        lines.append("Toast image: `\(client.configuration.toastImageURL.path)`")
        if let upgrader = try? client.ls(path: macOSInstallPath).first(where: { $0.role == "g3Upgrader" || $0.name == "Mac OS Install" }) {
            lines.append("ResViewer ls: `\(upgrader.path)` role=\(upgrader.role ?? "g3Upgrader") type=\(upgrader.type) creator context from catalog.")
        }
        if let kajr = try? client.ls(path: kajrInstallerPath).first {
            lines.append("ResViewer ls: `\(kajr.path)` role=\(kajr.role ?? "modemScriptsInstaller") — false G3 path (LoadSeg 66 / CODE 66).")
        }

        if let splash = try? client.get(type: "DLOG", id: G3MillClassification.splashResourceID, path: macOSInstallPath).dlog {
            lines.append(
                "ResViewer get DLOG \(G3MillClassification.splashResourceID) @ Mac OS Install: \"\(splash.title)\" \(splash.bounds.width)×\(splash.bounds.height) (toast Splash WINDOW)."
            )
        }
        if loadSeg66,
           let kajrSplash = try? client.get(
               type: "DLOG",
               id: G3MillClassification.splashResourceID,
               path: kajrInstallerPath,
               offset: G3MillClassification.loadSegKajrRsrcOffset
           ).dlog {
            lines.append(
                "ResViewer get DLOG \(G3MillClassification.splashResourceID) @ kajr offset 0x\(String(format: "%X", G3MillClassification.loadSegKajrRsrcOffset)): \"\(kajrSplash.title)\" \(kajrSplash.bounds.width)×\(kajrSplash.bounds.height) — not G3 Splash (\(G3MillClassification.splashWindowSize.width)×\(G3MillClassification.splashWindowSize.height))."
            )
        }
        if let cfrg = try? client.get(type: "cfrg", id: 0, path: macOSInstallPath).cfrg?.fragments.first {
            lines.append("ResViewer get cfrg @ Mac OS Install: \(cfrg.architecture ?? "?") \"\(cfrg.name ?? "?")\" (CFM Upgrader live path).")
        }
        if let ners = try? client.get(type: "ners", id: G3MillClassification.nersResourceID, path: macOSInstallPath) {
            lines.append("ResViewer get ners id=\(G3MillClassification.nersResourceID) @ Mac OS Install (\(ners.size) bytes) — xlate miss FourCC 'ners' target.")
        }
        return lines
    }

    public static func markdownSection(
        title: String = "Toast catalog (ResViewer)",
        launchA9F2: Bool = false,
        loadSeg66: Bool = false
    ) -> String {
        let body = millContextLines(launchA9F2: launchA9F2, loadSeg66: loadSeg66)
        return "## \(title)\n\n" + body.map { "- \($0)" }.joined(separator: "\n")
    }

    private static func resolveCLIURL() -> URL? {
        if let env = ProcessInfo.processInfo.environment[cliEnvironmentKey], !env.isEmpty {
            return URL(fileURLWithPath: env)
        }
        let candidates = [
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents/GitHub/resviewer/.build/debug/ResViewerCLI"),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents/GitHub/resviewer/.build/arm64-apple-macosx/debug/ResViewerCLI")
        ]
        for url in candidates where FileManager.default.isExecutableFile(atPath: url.path) {
            return url
        }
        return whichExecutable(named: "ResViewerCLI")
    }

    private static func resolveToastImageURL() -> URL? {
        if let env = ProcessInfo.processInfo.environment[toastEnvironmentKey], !env.isEmpty {
            return URL(fileURLWithPath: env)
        }
        let candidates = [
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads/Mac OS 9.2.1.toast"),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads/Mac OS 9.2.1 Toast.img")
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func whichExecutable(named name: String) -> URL? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let path = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    private static func extractErrorMessage(from stdout: String) -> String? {
        guard let data = stdout.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(FailureEnvelope.self, from: data)
        else { return nil }
        return envelope.error.message
    }

    private static func decodeEnvelope<T: Decodable>(command: String, from stdout: String) throws -> T {
        guard let data = stdout.data(using: .utf8) else {
            throw LookupError.invalidResponse("non-UTF8 output")
        }
        let envelope = try JSONDecoder().decode(SuccessEnvelope<T>.self, from: data)
        guard envelope.ok, envelope.command == command else {
            throw LookupError.invalidResponse("unexpected envelope for \(command)")
        }
        return envelope.data
    }

    private struct SuccessEnvelope<T: Decodable>: Decodable {
        var ok: Bool
        var schema: Int
        var command: String
        var data: T
    }

    private struct FailureEnvelope: Decodable {
        struct ErrorBody: Decodable {
            var code: String
            var message: String
        }

        var ok: Bool
        var command: String
        var error: ErrorBody
    }
}

private extension UInt32 {
    init(clamping value: Int) {
        if value < 0 {
            self = 0
        } else if value > Int(UInt32.max) {
            self = UInt32.max
        } else {
            self = UInt32(value)
        }
    }
}
