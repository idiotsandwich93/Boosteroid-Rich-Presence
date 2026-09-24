import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = BoosteroidMonitor()
    private let catalog = GameCatalog()
    private let discord = DiscordRPC()
    private let boosteroidActivityBridge = BoosteroidActivityBridge()
    private let fakeGameProcess = FakeGameProcess()
    private let boosteroidLauncher = BoosteroidLauncher()
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var currentSessionID: Int?
    private var lastGame: BoosteroidGame?
    private var bridgedGame: BoosteroidGame?
    private var lastRPCUpdate: Date?
    private var nativeHandoffSessionID: Int?
    private var nativeHandoffProvider: NativePresenceProvider?
    private var statusText = "Starting…"

    func applicationDidFinishLaunching(_ notification: Notification) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        AppLogger.log("Boosteroid Presence \(version) started (\(catalog.count) Discord profiles)")
        do {
            try boosteroidActivityBridge.start()
        } catch {
            AppLogger.log("Boosteroid activity filter failed to start: \(error.localizedDescription)")
        }
        buildMenuBar()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        discord.clearActivity()
        discord.closeConnection()
        fakeGameProcess.stop()
        boosteroidActivityBridge.stop()
        AppLogger.log("Boosteroid Presence stopped")
    }

    private func buildMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "gamecontroller.fill", accessibilityDescription: "Boosteroid Presence")
            button.image?.isTemplate = true
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let status = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        let presenceModeStatus = NSMenuItem(
            title: boosteroidLauncher.isPresenceModeLaunchPending
                ? "Starting Boosteroid in Presence Mode…"
                : boosteroidLauncher.isPresenceModeActive
                    ? "✓ Boosteroid activity filtered"
                    : "Presence Mode is required",
            action: nil,
            keyEquivalent: ""
        )
        presenceModeStatus.isEnabled = false
        menu.addItem(presenceModeStatus)

        let openBoosteroid = NSMenuItem(
            title: monitor.isBoosteroidRunning && !boosteroidLauncher.isPresenceModeActive
                ? "Relaunch Boosteroid in Presence Mode…"
                : "Open Boosteroid in Presence Mode",
            action: #selector(openBoosteroid),
            keyEquivalent: "b"
        )
        openBoosteroid.target = self
        menu.addItem(openBoosteroid)

        let refreshItem = NSMenuItem(title: "Update Presence Now", action: #selector(refreshNow), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let nativeStatusItem = NSMenuItem(
            title: PresencePreferences.prefersNativeInGameStatus
                ? "✓ Prefer Native In-Game Status"
                : "Prefer Native In-Game Status",
            action: #selector(toggleNativeInGameStatus),
            keyEquivalent: ""
        )
        nativeStatusItem.target = self
        menu.addItem(nativeStatusItem)

        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)

        let logsItem = NSMenuItem(title: "Open Boosteroid Log", action: #selector(openBoosteroidLog), keyEquivalent: "l")
        logsItem.target = self
        menu.addItem(logsItem)

        let diagnosticItem = NSMenuItem(title: "Open Presence Diagnostic Log", action: #selector(openDiagnosticLog), keyEquivalent: "")
        diagnosticItem.target = self
        menu.addItem(diagnosticItem)

        menu.addItem(.separator())
        let about = NSMenuItem(title: "About Boosteroid Presence", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu
    }

    @objc private func refreshNow() { refresh() }

    @objc private func toggleNativeInGameStatus() {
        let enabled = !PresencePreferences.prefersNativeInGameStatus
        PresencePreferences.setPrefersNativeInGameStatus(enabled)
        AppLogger.log("Native in-game status preference \(enabled ? "enabled" : "disabled") by user")
        rebuildMenu()
        refresh()
    }

    private func refresh() {
        guard monitor.isBoosteroidRunning else {
            boosteroidLauncher.noteBoosteroidNotRunning()
            clearPresence(
                status: boosteroidLauncher.isPresenceModeLaunchPending
                    ? "Launching Boosteroid in Presence Mode…"
                    : "Waiting for Boosteroid"
            )
            return
        }

        guard boosteroidLauncher.isPresenceModeActive else {
            clearPresence(status: "Boosteroid needs Presence Mode")
            return
        }

        do {
            guard let game = try detectedActiveGame() else {
                clearPresence(status: "Boosteroid open — waiting for a game")
                return
            }

            if PresencePreferences.prefersNativeInGameStatus {
                let provider = NativePresenceProvider.provider(for: game)
                handOffPresence(for: game, to: provider)
                return
            }

            nativeHandoffSessionID = nil
            nativeHandoffProvider = nil
            guard let match = catalog.match(game.name) else {
                clearPresence(status: "Game found, but no Discord match: \(GameCatalog.displayName(game.name))")
                return
            }

            try fakeGameProcess.ensureRunning(for: match)

            let boosteroidPID = monitor.processIdentifier
            let targetPIDs = [boosteroidPID, fakeGameProcess.processIdentifier].compactMap { $0 }
            let needsRefresh = lastRPCUpdate.map { Date().timeIntervalSince($0) >= 2 } ?? true
            if currentSessionID != game.sessionID || discord.clientID != match.clientID || needsRefresh {
                try discord.setActivity(
                    clientID: match.clientID,
                    game: game,
                    boosteroidActivity: boosteroidActivityBridge.latestActivity(for: game),
                    processIDs: targetPIDs
                )
                currentSessionID = game.sessionID
                lastGame = game
                lastRPCUpdate = Date()
                AppLogger.log("Discord presence accepted: \(game.name) -> \(match.name), client \(match.clientID), pids \(targetPIDs)")
            }
            setStatus("Playing \(GameCatalog.displayName(game.name))")
        } catch {
            AppLogger.log("Presence update failed: \(error.localizedDescription)")
            discord.closeConnection()
            currentSessionID = nil
            lastRPCUpdate = nil
            let gameText = lastGame.map { ": \(GameCatalog.displayName($0.name))" } ?? ""
            setStatus("Discord unavailable\(gameText)")
        }
    }

    private func handOffPresence(for game: BoosteroidGame, to provider: NativePresenceProvider) {
        if currentSessionID != nil || discord.clientID != nil {
            discord.clearActivity()
            discord.closeConnection()
        }
        fakeGameProcess.stop()
        currentSessionID = nil
        lastRPCUpdate = nil
        lastGame = game

        if nativeHandoffSessionID != game.sessionID || nativeHandoffProvider != provider {
            AppLogger.log(
                "Discord presence handed off: \(GameCatalog.displayName(game.name)) -> \(provider.rawValue)"
            )
        }
        nativeHandoffSessionID = game.sessionID
        nativeHandoffProvider = provider
        setStatus("\(GameCatalog.displayName(game.name)) — in-game status via \(provider.rawValue)")
    }

    private func clearPresence(status: String) {
        if currentSessionID != nil || discord.clientID != nil {
            discord.clearActivity()
            discord.closeConnection()
        }
        fakeGameProcess.stop()
        currentSessionID = nil
        lastGame = nil
        bridgedGame = nil
        lastRPCUpdate = nil
        nativeHandoffSessionID = nil
        nativeHandoffProvider = nil
        setStatus(status)
    }

    private func detectedActiveGame() throws -> BoosteroidGame? {
        if let loggedGame = try monitor.activeGame() {
            bridgedGame = loggedGame
            return loggedGame
        }

        guard let captured = boosteroidActivityBridge.latestCapturedActivity else {
            bridgedGame = nil
            return nil
        }

        if let candidate = captured.gameTitleCandidate,
           catalog.match(candidate) != nil {
            if let bridgedGame,
               GameCatalog.normalize(bridgedGame.name) == GameCatalog.normalize(candidate) {
                return bridgedGame
            }

            let fallback = BoosteroidGame(
                name: candidate,
                appID: nil,
                sessionID: Int(captured.capturedAt.timeIntervalSince1970),
                iconURL: nil,
                startedAt: captured.capturedAt
            )
            bridgedGame = fallback
            AppLogger.log("Detected game from Boosteroid activity fallback: \(candidate)")
            return fallback
        }

        // Boosteroid may replace the title with mode/state fields after its
        // first RPC update. Keep the already validated title until it clears
        // the activity at the end of the stream.
        return bridgedGame
    }

    private func setStatus(_ newValue: String) {
        guard newValue != statusText else { return }
        statusText = newValue
        AppLogger.log("Status: \(newValue)")
        statusItem.button?.toolTip = newValue
        rebuildMenu()
    }

    @objc private func openBoosteroid() {
        if boosteroidLauncher.isPresenceModeActive {
            if let processIdentifier = boosteroidLauncher.presenceModeProcessIdentifier {
                NSRunningApplication(processIdentifier: processIdentifier)?
                    .activate(options: [.activateAllWindows])
            }
            return
        }

        let runningApplications = monitor.runningApplications
        if runningApplications.isEmpty {
            launchBoosteroidInPresenceMode()
            return
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Relaunch Boosteroid in Presence Mode?"
        alert.informativeText = "Boosteroid is already running with its own Discord activity enabled. It must be quit and reopened by Boosteroid Presence so the game can take its place. Any active stream will close."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit & Relaunch")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        setStatus("Restarting Boosteroid in Presence Mode…")
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try boosteroidActivityBridge.start()
                _ = try await boosteroidLauncher.quitAndRelaunch(runningApplications)
                setStatus("Boosteroid launched in Presence Mode")
            } catch {
                AppLogger.log("Presence Mode relaunch failed: \(error.localizedDescription)")
                showAlert(title: "Couldn’t relaunch Boosteroid", message: error.localizedDescription)
                refresh()
            }
        }
    }

    private func launchBoosteroidInPresenceMode() {
        do {
            try boosteroidActivityBridge.start()
            _ = try boosteroidLauncher.launch()
            setStatus("Boosteroid launched in Presence Mode")
        } catch {
            AppLogger.log("Presence Mode launch failed: \(error.localizedDescription)")
            showAlert(title: "Couldn’t open Boosteroid", message: error.localizedDescription)
        }
    }

    @objc private func openBoosteroidLog() {
        NSWorkspace.shared.activateFileViewerSelecting([BoosteroidMonitor.logURL])
    }

    @objc private func openDiagnosticLog() {
        if !FileManager.default.fileExists(atPath: AppLogger.logURL.path) {
            AppLogger.log("Diagnostic log opened")
        }
        NSWorkspace.shared.open(AppLogger.logURL)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showAlert(title: "Couldn’t change login setting", message: error.localizedDescription)
        }
        rebuildMenu()
    }

    @objc private func showAbout() {
        showAlert(
            title: "Boosteroid Presence",
            message: "Shows the game you’re streaming through Boosteroid as your Discord activity.\n\nPresence Mode filters Boosteroid’s generic Discord identity. Native In-Game Status gives every game or launcher a chance to provide its own mode and player count without being overwritten by this app. If a game does not publish native status, turn the preference off to use Boosteroid Presence’s basic game card. Store labels are detection hints only and are never displayed.\n\nDetected \(catalog.count.formatted()) Discord game profiles."
        )
    }

    private func showAlert(title: String, message: String) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
