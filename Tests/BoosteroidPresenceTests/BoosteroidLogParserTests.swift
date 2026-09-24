import Foundation
import Testing
@testable import BoosteroidPresence

struct BoosteroidLogParserTests {
    @Test func parsesActiveGame() {
        let log = #"""
        [2026-07-31 19:25:34.571] [info]: History:  [{"app_id":2014,"finished_at":null,"icon":"https://example.com/gta.jpg","id":51871316,"name":"Grand Theft Auto V Enhanced (Epic)","platform":[8],"started_at":"2026-07-31 23:25:33"}]
        [2026-07-31 19:25:35.566] [info]: Video started
        """#
        let game = BoosteroidLogParser.activeGame(in: log)
        #expect(game?.name == "Grand Theft Auto V Enhanced (Epic)")
        #expect(game?.appID == 2014)
        #expect(game?.sessionID == 51871316)
        #expect(game?.platformIDs == [8])
        #expect(game?.startedAt != nil)
        #expect(game.map { NativePresenceProvider.provider(for: $0) } == .rockstar)
    }

    @Test func clearsAfterStopMarker() {
        let log = #"""
        History:  [{"app_id":23,"finished_at":null,"id":1,"name":"Fortnite","started_at":"2026-07-31 23:25:33"}]
        Sending stop session message...
        """#
        #expect(BoosteroidLogParser.activeGame(in: log) == nil)
    }

    @Test func ignoresCompletedGames() {
        let log = #"History:  [{"app_id":23,"finished_at":"2026-07-31 23:45:00","id":1,"name":"Fortnite","started_at":"2026-07-31 23:25:33"}]"#
        #expect(BoosteroidLogParser.activeGame(in: log) == nil)
    }

    @Test func normalizesStoreNames() {
        #expect(GameCatalog.normalize("Grand Theft Auto V Enhanced (Epic)") == "grand theft auto v enhanced")
        #expect(GameCatalog.displayName("The Elder Scrolls Online® (Steam)") == "The Elder Scrolls Online")
    }

    @Test func usesXboxPlatformForNativeStatusHandoff() {
        let game = BoosteroidGame(
            name: "Forza Horizon 6 (Xbox)",
            appID: 999,
            sessionID: 42,
            iconURL: nil,
            startedAt: Date(),
            platformIDs: [18]
        )
        #expect(NativePresenceProvider.provider(for: game) == .xbox)
    }

    @Test func offersNativeStatusHandoffToEveryGame() {
        let game = BoosteroidGame(
            name: "Fortnite",
            appID: 23,
            sessionID: 43,
            iconURL: nil,
            startedAt: Date()
        )
        #expect(NativePresenceProvider.provider(for: game) == .game)
    }

    @Test func catalogMatchesObservedBoosteroidNames() {
        let catalog = GameCatalog()
        #expect(catalog.match("Grand Theft Auto V Enhanced (Epic)") != nil)
        #expect(catalog.match("Red Dead Redemption 2 (Epic)") != nil)
        #expect(catalog.match("The Elder Scrolls Online (Steam)") != nil)
        #expect(catalog.match("Fortnite") != nil)
    }
}
