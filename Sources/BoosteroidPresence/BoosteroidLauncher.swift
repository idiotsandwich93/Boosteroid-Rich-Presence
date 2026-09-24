import AppKit
import Darwin
import Foundation

enum BoosteroidLauncherError: LocalizedError {
    case applicationNotFound
    case executableNotFound
    case didNotQuit

    var errorDescription: String? {
        switch self {
        case .applicationNotFound:
            "Boosteroid.app could not be found. Install Boosteroid, then try again."
        case .executableNotFound:
            "The Boosteroid application is missing its executable."
        case .didNotQuit:
            "Boosteroid did not quit, so it could not be relaunched in Presence Mode."
        }
    }
}

@MainActor
final class BoosteroidLauncher {
    private static let storedPIDKey = "PresenceModeBoosteroidPID"
    private static let activeSessionKey = "PresenceModeActiveSession"
    private static let launchDateKey = "PresenceModeLaunchDate"
    private static let runtimeVersionKey = "PresenceModeRuntimeVersion"
    private static let currentRuntimeVersion = 2
    private static let launchGraceInterval: TimeInterval = 30
    private static let processHandoffGraceInterval: TimeInterval = 10
    private var launchedProcess: Process?
    private var lastObservedRunningAt: Date?

    nonisolated static var isolatedRuntimeURL: URL {
        URL(
            fileURLWithPath: "/private/tmp/boosteroid-presence-\(getuid())",
            isDirectory: true
        )
    }

    var isPresenceModeActive: Bool {
        guard hasActiveSessionMarker else { return false }

        let applications = runningApplications
        if let application = applications.first {
            let currentPID = Int32(application.processIdentifier)
            if currentPID != storedProcessIdentifier {
                AppLogger.log("Presence Mode adopted Boosteroid process pid \(currentPID)")
                UserDefaults.standard.set(Int(currentPID), forKey: Self.storedPIDKey)
            }
            lastObservedRunningAt = Date()
            return true
        }

        if launchedProcess?.isRunning == true || hasLaunchGrace {
            return true
        }
        if let lastObservedRunningAt,
           Date().timeIntervalSince(lastObservedRunningAt) < Self.processHandoffGraceInterval {
            return true
        }

        clearSessionMarker()
        return false
    }

    var presenceModeProcessIdentifier: Int32? {
        guard isPresenceModeActive else { return nil }
        return runningApplications.first.map { Int32($0.processIdentifier) } ?? storedProcessIdentifier
    }

    var isPresenceModeLaunchPending: Bool {
        hasActiveSessionMarker && runningApplications.isEmpty && hasLaunchGrace
    }

    static func presenceModeEnvironment(
        basedOn environment: [String: String],
        runtimeURL: URL = isolatedRuntimeURL
    ) -> [String: String] {
        var result = environment
        result["XDG_RUNTIME_DIR"] = runtimeURL.path
        return result
    }

    static func shouldKeepPresenceModeSession(
        hasRunningApplication: Bool,
        launchedProcessIsRunning: Bool,
        launchAge: TimeInterval?,
        lastObservedRunningAge: TimeInterval?
    ) -> Bool {
        hasRunningApplication
            || launchedProcessIsRunning
            || launchAge.map { $0 < launchGraceInterval } == true
            || lastObservedRunningAge.map { $0 < processHandoffGraceInterval } == true
    }

    @discardableResult
    func launch() throws -> Int32 {
        let workspace = NSWorkspace.shared
        guard let applicationURL = workspace.urlForApplication(
            withBundleIdentifier: BoosteroidMonitor.bundleIdentifier
        ) else {
            throw BoosteroidLauncherError.applicationNotFound
        }
        guard let executableURL = Bundle(url: applicationURL)?.executableURL else {
            throw BoosteroidLauncherError.executableNotFound
        }

        try prepareIsolatedRuntimeDirectory()

        let process = Process()
        process.executableURL = executableURL
        process.currentDirectoryURL = executableURL.deletingLastPathComponent()
        process.environment = Self.presenceModeEnvironment(
            basedOn: ProcessInfo.processInfo.environment
        )
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()

        launchedProcess = process
        let processIdentifier = process.processIdentifier
        UserDefaults.standard.set(true, forKey: Self.activeSessionKey)
        UserDefaults.standard.set(Int(processIdentifier), forKey: Self.storedPIDKey)
        UserDefaults.standard.set(Date(), forKey: Self.launchDateKey)
        UserDefaults.standard.set(Self.currentRuntimeVersion, forKey: Self.runtimeVersionKey)
        AppLogger.log(
            "Launched Boosteroid in Presence Mode (pid \(processIdentifier), isolated XDG_RUNTIME_DIR: \(Self.isolatedRuntimeURL.path))"
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            NSRunningApplication(processIdentifier: processIdentifier)?
                .activate(options: [.activateAllWindows])
        }
        return processIdentifier
    }

    func quitAndRelaunch(_ applications: [NSRunningApplication]) async throws -> Int32 {
        AppLogger.log("Quitting Boosteroid before Presence Mode relaunch")
        applications.forEach { $0.terminate() }

        for _ in 0..<50 {
            if NSRunningApplication.runningApplications(
                withBundleIdentifier: BoosteroidMonitor.bundleIdentifier
            ).isEmpty {
                return try launch()
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        throw BoosteroidLauncherError.didNotQuit
    }

    private var storedProcessIdentifier: Int32? {
        let value = UserDefaults.standard.integer(forKey: Self.storedPIDKey)
        return value > 0 ? Int32(value) : nil
    }

    func noteBoosteroidNotRunning() {
        guard hasActiveSessionMarker else { return }
        if launchedProcess?.isRunning == true || hasLaunchGrace {
            return
        }
        if let lastObservedRunningAt,
           Date().timeIntervalSince(lastObservedRunningAt) < Self.processHandoffGraceInterval {
            return
        }
        clearSessionMarker()
    }

    private var runningApplications: [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: BoosteroidMonitor.bundleIdentifier)
    }

    private var hasActiveSessionMarker: Bool {
        UserDefaults.standard.bool(forKey: Self.activeSessionKey)
            && UserDefaults.standard.integer(forKey: Self.runtimeVersionKey) == Self.currentRuntimeVersion
    }

    private var hasLaunchGrace: Bool {
        guard let launchDate = UserDefaults.standard.object(forKey: Self.launchDateKey) as? Date else {
            return false
        }
        return Self.shouldKeepPresenceModeSession(
            hasRunningApplication: false,
            launchedProcessIsRunning: false,
            launchAge: Date().timeIntervalSince(launchDate),
            lastObservedRunningAge: nil
        )
    }

    private func clearSessionMarker() {
        guard hasActiveSessionMarker || storedProcessIdentifier != nil else { return }
        UserDefaults.standard.removeObject(forKey: Self.activeSessionKey)
        UserDefaults.standard.removeObject(forKey: Self.storedPIDKey)
        UserDefaults.standard.removeObject(forKey: Self.launchDateKey)
        UserDefaults.standard.removeObject(forKey: Self.runtimeVersionKey)
        lastObservedRunningAt = nil
        AppLogger.log("Presence Mode session ended")
    }

    private func prepareIsolatedRuntimeDirectory() throws {
        let fileManager = FileManager.default
        let runtimeURL = Self.isolatedRuntimeURL
        try fileManager.createDirectory(
            at: runtimeURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        // The activity filter owns discord-ipc-0 inside this directory. Boosteroid
        // connects to that socket instead of Discord's real socket.
    }
}
