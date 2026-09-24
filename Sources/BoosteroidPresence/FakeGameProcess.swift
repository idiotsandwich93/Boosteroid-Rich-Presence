import Foundation

final class FakeGameProcess {
    private var process: Process?
    private var currentExecutablePath: String?

    var isRunning: Bool { process?.isRunning == true }
    var processIdentifier: Int32? {
        guard let process, process.isRunning else { return nil }
        return process.processIdentifier
    }

    func ensureRunning(for game: DiscordGame) throws {
        let relativePath = sanitizedPath(game.executablePath ?? fallbackName(for: game.name))
        if currentExecutablePath == relativePath, process?.isRunning == true {
            return
        }

        stop()
        guard let sourceExecutable = Bundle.main.executableURL else {
            throw CocoaError(.fileNoSuchFile)
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("boosteroid-presence", isDirectory: true)
            .appendingPathComponent("discord-game", isDirectory: true)
        let destination = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: sourceExecutable, to: destination)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)

        let process = Process()
        process.executableURL = destination
        process.arguments = ["--fake-game"]
        process.currentDirectoryURL = destination.deletingLastPathComponent()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()

        self.process = process
        currentExecutablePath = relativePath
        AppLogger.log("Started Discord game placeholder: \(relativePath) (pid \(process.processIdentifier))")
    }

    func stop() {
        if let process, process.isRunning {
            AppLogger.log("Stopped Discord game placeholder (pid \(process.processIdentifier))")
            process.terminate()
        }
        process = nil
        currentExecutablePath = nil
    }

    private func fallbackName(for gameName: String) -> String {
        let normalized = GameCatalog.normalize(gameName).replacingOccurrences(of: " ", with: "-")
        return normalized.isEmpty ? "streamed-game" : normalized
    }

    private func sanitizedPath(_ input: String) -> String {
        let components = input.replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." }
            .map { component in
                component.replacingOccurrences(
                    of: #"[^A-Za-z0-9 ._()\-]"#,
                    with: "_",
                    options: .regularExpression
                )
            }
        return components.isEmpty ? "streamed-game" : components.joined(separator: "/")
    }
}
