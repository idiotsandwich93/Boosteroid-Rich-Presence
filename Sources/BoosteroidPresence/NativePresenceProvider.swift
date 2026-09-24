import Foundation

enum NativePresenceProvider: String, Equatable, Sendable {
    case rockstar = "Rockstar Games"
    case xbox = "Xbox"
    case game = "game integration"

    private static let xboxPlatformID = 18

    static func provider(for game: BoosteroidGame) -> NativePresenceProvider {
        if game.platformIDs.contains(xboxPlatformID) {
            return .xbox
        }

        let title = GameCatalog.normalize(game.name)
        let rockstarTitles: Set<String> = [
            "grand theft auto v",
            "grand theft auto v enhanced",
            "grand theft auto v legacy",
            "grand theft auto online",
            "red dead redemption 2",
            "red dead online"
        ]
        if rockstarTitles.contains(title) {
            return .rockstar
        }

        // Every game receives the same handoff opportunity. Games without a
        // native Discord integration can use the basic-card fallback from the
        // menu instead.
        return .game
    }
}

enum PresencePreferences {
    private static let nativeStatusKey = "PreferNativeInGameStatus"

    static var prefersNativeInGameStatus: Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: nativeStatusKey) != nil else { return true }
        return defaults.bool(forKey: nativeStatusKey)
    }

    static func setPrefersNativeInGameStatus(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: nativeStatusKey)
    }
}
