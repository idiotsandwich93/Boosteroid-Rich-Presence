import Foundation

enum SelfTest {
    @MainActor
    static func run() -> Int32 {
        var failures: [String] = []
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() { failures.append(message) }
        }

        let activeLog = #"""
        [2026-07-31 19:25:34.571] [info]: History:  [{"app_id":2014,"finished_at":null,"icon":"https://example.com/gta.jpg","id":51871316,"name":"Grand Theft Auto V Enhanced (Epic)","platform":[8],"started_at":"2026-07-31 23:25:33"}]
        [2026-07-31 19:25:35.566] [info]: Video started
        """#
        let game = BoosteroidLogParser.activeGame(in: activeLog)
        expect(game?.name == "Grand Theft Auto V Enhanced (Epic)", "active game name")
        expect(game?.appID == 2014, "Boosteroid app ID")
        expect(game?.sessionID == 51871316, "session ID")
        expect(game?.platformIDs == [8], "store platform ID")
        expect(game?.startedAt != nil, "start timestamp")
        if let game {
            let activity = DiscordRPC.activityPayload(for: game)
            expect(activity["details"] == nil, "Discord activity omits Boosteroid details")
            expect(activity["state"] as? String == "Grand Theft Auto V Enhanced", "Discord activity keeps the lower state line")
            expect(activity["timestamps"] != nil, "Discord activity keeps elapsed time")

            let captured = BoosteroidCapturedActivity(
                details: "GTA Online",
                state: "Public Session",
                partyID: "gta-session",
                partyCurrent: 7,
                partyMaximum: 30,
                capturedAt: Date()
            )
            let dynamicActivity = DiscordRPC.activityPayload(
                for: game,
                boosteroidActivity: captured
            )
            expect(dynamicActivity["details"] as? String == "GTA Online", "Boosteroid game mode is preserved")
            expect(dynamicActivity["state"] as? String == "Public Session", "Boosteroid dynamic state is preserved")
            let party = dynamicActivity["party"] as? [String: Any]
            expect(party?["size"] as? [Int] == [7, 30], "Boosteroid player count is preserved")

            let boilerplate = BoosteroidCapturedActivity(
                details: "Playing on Boosteroid",
                state: "GTA Online",
                partyID: nil,
                partyCurrent: nil,
                partyMaximum: nil,
                capturedAt: Date()
            )
            let filteredActivity = DiscordRPC.activityPayload(
                for: game,
                boosteroidActivity: boilerplate
            )
            expect(filteredActivity["details"] == nil, "Boosteroid boilerplate is filtered")
            expect(filteredActivity["state"] as? String == "GTA Online", "Useful Boosteroid state survives filtering")
        }

        let xboxGame = BoosteroidGame(
            name: "Forza Horizon 6 (Xbox)",
            appID: 999,
            sessionID: 42,
            iconURL: nil,
            startedAt: Date(),
            platformIDs: [18]
        )
        expect(NativePresenceProvider.provider(for: xboxGame) == .xbox, "Xbox native status handoff")
        if let game {
            expect(NativePresenceProvider.provider(for: game) == .rockstar, "Rockstar native status handoff")
        }
        let genericStoreActivity = BoosteroidCapturedActivity(
            details: "Forza Horizon 6 (Xbox)",
            state: nil,
            partyID: nil,
            partyCurrent: nil,
            partyMaximum: nil,
            capturedAt: Date()
        )
        let cleanStoreActivity = DiscordRPC.activityPayload(
            for: xboxGame,
            boosteroidActivity: genericStoreActivity
        )
        expect(cleanStoreActivity["details"] == nil, "generic store-tagged details are suppressed")
        expect(cleanStoreActivity["state"] as? String == "Forza Horizon 6", "store label is removed from fallback state")
        expect(genericStoreActivity.gameTitleCandidate == "Forza Horizon 6 (Xbox)", "captured game title fallback")

        let boosteroidOnlyActivity = BoosteroidCapturedActivity(
            details: "Playing on Boosteroid",
            state: "GTA Online",
            partyID: nil,
            partyCurrent: nil,
            partyMaximum: nil,
            capturedAt: Date()
        )
        expect(boosteroidOnlyActivity.gameTitleCandidate == nil, "mode text is not mistaken for a game title")

        let genericGame = BoosteroidGame(
            name: "Fortnite",
            appID: 23,
            sessionID: 43,
            iconURL: nil,
            startedAt: Date()
        )
        expect(NativePresenceProvider.provider(for: genericGame) == .game, "generic native status handoff")

        let stoppedLog = activeLog + "\nSending stop session message...\n"
        expect(BoosteroidLogParser.activeGame(in: stoppedLog) == nil, "stop detection")

        let completedLog = #"History:  [{"app_id":23,"finished_at":"2026-07-31 23:45:00","id":1,"name":"Fortnite","started_at":"2026-07-31 23:25:33"}]"#
        expect(BoosteroidLogParser.activeGame(in: completedLog) == nil, "completed session filtering")
        expect(GameCatalog.normalize("Grand Theft Auto V Enhanced (Epic)") == "grand theft auto v enhanced", "name normalization")
        expect(GameCatalog.displayName("The Elder Scrolls Online® (Steam)") == "The Elder Scrolls Online", "display name cleanup")

        let catalog = GameCatalog()
        expect(catalog.count > 10_000, "catalog load")
        expect(catalog.match("Grand Theft Auto V Enhanced (Epic)")?.clientID == "1421192030440263791", "GTA V Enhanced catalog match")
        expect(catalog.match("Grand Theft Auto V Enhanced (Epic)")?.executablePath == "grand theft auto v enhanced/gta5_enhanced.exe", "GTA V Enhanced executable match")
        expect(catalog.match("Grand Theft Auto V (Epic)")?.clientID == "1402418714716143646", "generic GTA V catalog match")
        expect(catalog.match("Red Dead Redemption 2 (Epic)")?.clientID == "1402418648332898466", "RDR2 catalog match")
        expect(catalog.match("The Elder Scrolls Online (Steam)")?.clientID == "363413894602948608", "ESO catalog match")
        expect(catalog.match("Fortnite")?.clientID == "1402418703554842694", "Fortnite catalog match")
        expect(catalog.match("Fortnite")?.executablePath == "fortniteclient-win64-shipping.exe", "Fortnite executable match")
        expect(catalog.match("Halo: Campaign Evolved (Xbox)")?.clientID == "1530787122695508019", "Halo: Campaign Evolved catalog match")

        let normalEnvironment = ["TMPDIR": "/real/discord/runtime", "EXAMPLE": "preserved"]
        let isolatedRuntime = URL(fileURLWithPath: "/isolated/boosteroid/runtime")
        let presenceEnvironment = BoosteroidLauncher.presenceModeEnvironment(
            basedOn: normalEnvironment,
            runtimeURL: isolatedRuntime
        )
        expect(presenceEnvironment["XDG_RUNTIME_DIR"] == isolatedRuntime.path, "Presence Mode isolates Discord runtime")
        expect(presenceEnvironment["TMPDIR"] == normalEnvironment["TMPDIR"], "Presence Mode preserves Boosteroid temporary directory")
        expect(presenceEnvironment["EXAMPLE"] == "preserved", "Presence Mode preserves process environment")
        expect(
            BoosteroidLauncher.shouldKeepPresenceModeSession(
                hasRunningApplication: false,
                launchedProcessIsRunning: false,
                launchAge: 2,
                lastObservedRunningAge: nil
            ),
            "Presence Mode survives macOS application-registration delay"
        )
        expect(
            BoosteroidLauncher.shouldKeepPresenceModeSession(
                hasRunningApplication: true,
                launchedProcessIsRunning: false,
                launchAge: 60,
                lastObservedRunningAge: nil
            ),
            "Presence Mode adopts the registered Boosteroid process"
        )
        expect(
            !BoosteroidLauncher.shouldKeepPresenceModeSession(
                hasRunningApplication: false,
                launchedProcessIsRunning: false,
                launchAge: 60,
                lastObservedRunningAge: nil
            ),
            "Presence Mode expires a stale launch marker"
        )

        do {
            let placeholder = FakeGameProcess()
            guard let fortnite = catalog.match("Fortnite") else {
                failures.append("placeholder catalog input")
                return 1
            }
            try placeholder.ensureRunning(for: fortnite)
            expect(placeholder.isRunning, "game placeholder launch")
            placeholder.stop()
        } catch {
            failures.append("game placeholder launch: \(error.localizedDescription)")
        }

        if failures.isEmpty {
            print("Self-test passed (\(catalog.count) Discord game profiles)")
            return 0
        }
        for failure in failures { print("FAIL: \(failure)") }
        return 1
    }

    static func probeLive() -> Int32 {
        do {
            let log = try String(contentsOf: BoosteroidMonitor.logURL, encoding: .utf8)
            guard let game = BoosteroidLogParser.activeGame(in: log) else {
                print("No active Boosteroid session found")
                return 2
            }
            let catalog = GameCatalog()
            guard let match = catalog.match(game.name) else {
                print("No Discord profile matched: \(game.name)")
                return 3
            }
            let discord = DiscordRPC()
            try discord.setActivity(clientID: match.clientID, game: game)
            print("Discord RPC accepted: \(game.name) -> \(match.name) [\(match.clientID)]")
            discord.clearActivity()
            discord.closeConnection()
            return 0
        } catch {
            print("Live probe failed: \(error.localizedDescription)")
            return 4
        }
    }

    static func probeDiscord() -> Int32 {
        let discord = DiscordRPC()
        let game = BoosteroidGame(
            name: "Fortnite",
            appID: 23,
            sessionID: -1,
            iconURL: nil,
            startedAt: Date()
        )
        do {
            try discord.setActivity(clientID: "1402418703554842694", game: game)
            print("Discord RPC handshake and activity update passed")
            discord.clearActivity()
            discord.closeConnection()
            return 0
        } catch {
            print("Discord probe failed: \(error.localizedDescription)")
            return 4
        }
    }

    static func probeOverride() -> Int32 {
        let monitor = BoosteroidMonitor()
        guard let boosteroidPID = monitor.processIdentifier else {
            print("Boosteroid is not running")
            return 5
        }

        let catalog = GameCatalog()
        let detectedGame: BoosteroidGame? = {
            guard let log = try? String(contentsOf: BoosteroidMonitor.logURL, encoding: .utf8) else { return nil }
            return BoosteroidLogParser.activeGame(in: log)
        }()
        let game = detectedGame ?? BoosteroidGame(
            name: "Halo: Campaign Evolved (Xbox)",
            appID: nil,
            sessionID: -2,
            iconURL: nil,
            startedAt: Date()
        )
        guard let match = catalog.match(game.name) else {
            print("No Discord profile matched \(game.name)")
            return 3
        }

        let placeholder = FakeGameProcess()
        let boosteroidRPC = DiscordRPC()
        let gameRPC = DiscordRPC()
        var step = "starting placeholder"
        do {
            try placeholder.ensureRunning(for: match)
            print("Placeholder running as \(match.executablePath ?? match.name)")
            step = "clearing Boosteroid RPC"
            try boosteroidRPC.clearActivity(
                clientID: "1170028348756471908",
                processIDs: [boosteroidPID]
            )
            print("Boosteroid RPC activity cleared")
            let targets = [boosteroidPID, placeholder.processIdentifier].compactMap { $0 }
            step = "publishing game RPC"
            try gameRPC.setActivity(clientID: match.clientID, game: game, processIDs: targets)
            print("Override accepted: \(game.name) -> \(match.name), pids \(targets)")
            Thread.sleep(forTimeInterval: 8)
            gameRPC.clearActivity()
            gameRPC.closeConnection()
            boosteroidRPC.closeConnection()
            placeholder.stop()
            return 0
        } catch {
            print("Override probe failed while \(step): \(error.localizedDescription)")
            gameRPC.clearActivity()
            gameRPC.closeConnection()
            boosteroidRPC.closeConnection()
            placeholder.stop()
            return 6
        }
    }

    @MainActor
    static func launchBoosteroidInPresenceMode() -> Int32 {
        let monitor = BoosteroidMonitor()
        guard !monitor.isBoosteroidRunning else {
            print("Boosteroid is already running")
            return 5
        }

        do {
            let launcher = BoosteroidLauncher()
            let processIdentifier = try launcher.launch()
            for _ in 0..<25 {
                if monitor.runningApplications.contains(where: {
                    Int32($0.processIdentifier) == processIdentifier
                }) {
                    print(
                        "Boosteroid launched in Presence Mode: pid \(processIdentifier), XDG_RUNTIME_DIR=\(BoosteroidLauncher.isolatedRuntimeURL.path)"
                    )
                    return 0
                }
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            }
            print("Boosteroid launched as pid \(processIdentifier), but macOS did not register the application")
            return 6
        } catch {
            print("Presence Mode launch failed: \(error.localizedDescription)")
            return 7
        }
    }

    static func probeBoosteroidActivityFilter() -> Int32 {
        let bridge = BoosteroidActivityBridge()
        do {
            try bridge.start()
            print("Boosteroid activity filter listening at \(bridge.socketURL.path)")
            for _ in 0..<150 {
                if let activity = bridge.latestCapturedActivity {
                    let party: String
                    if let current = activity.partyCurrent, let maximum = activity.partyMaximum {
                        party = ", party \(current)/\(maximum)"
                    } else {
                        party = ""
                    }
                    print("Captured: details=\(activity.details ?? "none"), state=\(activity.state ?? "none")\(party)")
                    bridge.stop()
                    return 0
                }
                Thread.sleep(forTimeInterval: 0.2)
            }
            print("No Boosteroid activity arrived within 30 seconds")
            bridge.stop()
            return 8
        } catch {
            print("Activity filter probe failed: \(error.localizedDescription)")
            bridge.stop()
            return 9
        }
    }

}
