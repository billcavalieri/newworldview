import Foundation

enum GrokBuildRunner {
    struct Result: Sendable {
        var stdout: String
        var stderr: String
        var exitCode: Int32
    }

    static func run(
        outputDirectory: URL,
        macemuRepoURL: URL?,
        grokPath: String?
    ) throws -> String {
        guard let binary = resolveGrokPath(customPath: grokPath) else {
            throw MillAnalysisServiceError.grokBinaryMissing
        }

        let promptURL = outputDirectory.appendingPathComponent("grok-prompt.md")
        guard FileManager.default.fileExists(atPath: promptURL.path) else {
            throw MillAnalysisServiceError.exportFailed("Missing grok-prompt.md in output directory.")
        }

        let cwd = macemuRepoURL?.path ?? outputDirectory.path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        process.arguments = [
            "--permission-mode", "bypassPermissions",
            "--output-format", "json",
            "--max-turns", "24",
            "--cwd", cwd,
            "--no-plan",
            "--disable-web-search",
            "--no-alt-screen",
            "--tools", "read_file,search_replace,grep,list_dir",
            "--prompt-file", promptURL.path
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw MillAnalysisServiceError.exportFailed(
                stderr.isEmpty ? "Grok Build exited with code \(process.terminationStatus)." : stderr
            )
        }
        return stdout
    }

    static func resolveGrokPath(customPath: String?) -> String? {
        if let customPath, !customPath.isEmpty {
            let url = URL(fileURLWithPath: customPath)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url.path
            }
        }
        if let env = ProcessInfo.processInfo.environment["G3_GROK_BIN"], !env.isEmpty {
            if FileManager.default.isExecutableFile(atPath: env) {
                return env
            }
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".grok/bin/grok")
        if FileManager.default.isExecutableFile(atPath: home.path) {
            return home.path
        }
        return nil
    }
}
