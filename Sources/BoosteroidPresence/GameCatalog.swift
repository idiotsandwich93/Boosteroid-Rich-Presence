import Foundation

struct DiscordGame: Codable, Equatable, Sendable {
    let name: String
    let clientID: String
    let executablePath: String?
}

final class GameCatalog {
    private let games: [DiscordGame]
    private let exactIndex: [String: DiscordGame]
    private let executableByClientID: [String: String]
    private var cache: [String: DiscordGame?] = [:]

    init(url: URL? = Bundle.module.url(forResource: "game_catalog", withExtension: "json")) {
        if let url,
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([DiscordGame].self, from: data) {
            games = decoded
        } else {
            games = []
        }

        var index: [String: DiscordGame] = [:]
        var executableIndex: [String: String] = [:]
        for game in games {
            if let executablePath = game.executablePath, !executablePath.isEmpty,
               executableIndex[game.clientID] == nil {
                executableIndex[game.clientID] = executablePath
            }
            let normalized = Self.normalize(game.name)
            if Self.shouldPrefer(game, over: index[normalized], for: normalized) {
                index[normalized] = game
            }
            let editionless = Self.removeEditionWords(from: normalized)
            if Self.shouldPrefer(game, over: index[editionless], for: editionless) {
                index[editionless] = game
            }
        }
        exactIndex = index
        executableByClientID = executableIndex
    }

    var count: Int { games.count }

    func match(_ boosteroidName: String) -> DiscordGame? {
        if let cached = cache[boosteroidName] { return cached }

        let normalized = Self.normalize(boosteroidName)
        let editionless = Self.removeEditionWords(from: normalized)
        if let exact = exactIndex[normalized] ?? exactIndex[editionless] {
            let hydrated = withExecutableFallback(exact)
            cache[boosteroidName] = hydrated
            return hydrated
        }

        var best: (game: DiscordGame, score: Double)?
        for game in games {
            let candidate = Self.normalize(game.name)
            let score = max(
                Self.sorensenDice(normalized, candidate),
                Self.sorensenDice(editionless, Self.removeEditionWords(from: candidate))
            )
            if score > (best?.score ?? 0) {
                best = (game, score)
            }
        }

        let result = (best?.score ?? 0) >= 0.88 ? best.map { withExecutableFallback($0.game) } : nil
        cache[boosteroidName] = result
        return result
    }

    private func withExecutableFallback(_ game: DiscordGame) -> DiscordGame {
        guard game.executablePath == nil, let fallback = executableByClientID[game.clientID] else {
            return game
        }
        return DiscordGame(name: game.name, clientID: game.clientID, executablePath: fallback)
    }

    static func displayName(_ name: String) -> String {
        var result = name
        let suffix = #"\s*\((steam|epic|epic games|xbox|microsoft store|battle\.net|gog|rockstar|ubisoft connect|ea app|origin)\)\s*$"#
        result = result.replacingOccurrences(of: suffix, with: "", options: [.regularExpression, .caseInsensitive])
        return result.replacingOccurrences(of: #"[®™]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalize(_ name: String) -> String {
        displayName(name)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .split(separator: " ")
            .joined(separator: " ")
    }

    private static func removeEditionWords(from name: String) -> String {
        let removable: Set<String> = [
            "enhanced", "legacy", "remastered", "remaster", "definitive",
            "complete", "ultimate", "standard", "edition", "deluxe"
        ]
        return name.split(separator: " ").filter { !removable.contains(String($0)) }.joined(separator: " ")
    }

    private static func shouldPrefer(
        _ candidate: DiscordGame,
        over current: DiscordGame?,
        for normalizedName: String
    ) -> Bool {
        guard let current else { return true }
        if current.executablePath == nil, candidate.executablePath != nil { return true }
        if current.executablePath != nil, candidate.executablePath == nil { return false }

        // Discord's detectable catalog can contain duplicate display names
        // for different editions. Prefer the executable whose path contains
        // more of the requested title's words (for example gta5_enhanced over
        // the generic gta5 executable for Grand Theft Auto V Enhanced).
        let requestedTokens = Set(normalizedName.split(separator: " ").map(String.init))
        func affinity(_ game: DiscordGame) -> Int {
            guard let path = game.executablePath else { return 0 }
            let pathTokens = Set(normalize(path).split(separator: " ").map(String.init))
            return requestedTokens.intersection(pathTokens).count
        }
        return affinity(candidate) > affinity(current)
    }

    private static func sorensenDice(_ lhs: String, _ rhs: String) -> Double {
        if lhs == rhs { return 1 }
        guard lhs.count > 1, rhs.count > 1 else { return 0 }
        let a = bigrams(lhs)
        let b = bigrams(rhs)
        var counts: [String: Int] = [:]
        for value in a { counts[value, default: 0] += 1 }
        var overlap = 0
        for value in b where (counts[value] ?? 0) > 0 {
            overlap += 1
            counts[value, default: 0] -= 1
        }
        return 2 * Double(overlap) / Double(a.count + b.count)
    }

    private static func bigrams(_ value: String) -> [String] {
        let chars = Array(value)
        return (0..<(chars.count - 1)).map { String(chars[$0...($0 + 1)]) }
    }
}
