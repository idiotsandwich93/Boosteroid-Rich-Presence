import AppKit
import Foundation

struct BoosteroidGame: Equatable, Sendable {
    let name: String
    let appID: Int?
    let sessionID: Int?
    let iconURL: URL?
    let startedAt: Date?
    let platformIDs: [Int]

    init(
        name: String,
        appID: Int?,
        sessionID: Int?,
        iconURL: URL?,
        startedAt: Date?,
        platformIDs: [Int] = []
    ) {
        self.name = name
        self.appID = appID
        self.sessionID = sessionID
        self.iconURL = iconURL
        self.startedAt = startedAt
        self.platformIDs = Array(Set(platformIDs)).sorted()
    }
}

enum BoosteroidLogParser {
    private static let historyMarker = "History:  "
    private static let stopMarkers = [
        "Sending stop session message",
        "THANK YOU FOR THE GAME!",
        "Starting  \"Boosteroid\""
    ]

    static func activeGame(in log: String) -> BoosteroidGame? {
        guard let markerRange = log.range(of: historyMarker, options: .backwards) else {
            return nil
        }

        let trailingLog = log[markerRange.upperBound...]
        guard let lineEnd = trailingLog.firstIndex(of: "\n") else {
            return parseHistory(String(trailingLog))
        }

        let json = String(trailingLog[..<lineEnd])
        let eventsAfterHistory = String(trailingLog[lineEnd...])
        if stopMarkers.contains(where: eventsAfterHistory.contains) {
            return nil
        }
        return parseHistory(json)
    }

    private static func parseHistory(_ json: String) -> BoosteroidGame? {
        guard let data = json.data(using: .utf8),
              let history = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let active = history.first(where: { $0["finished_at"] is NSNull }) else {
            return nil
        }

        let name = (active["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        return BoosteroidGame(
            name: name,
            appID: active["app_id"] as? Int,
            sessionID: active["id"] as? Int,
            iconURL: (active["icon"] as? String).flatMap(URL.init(string:)),
            startedAt: (active["started_at"] as? String).flatMap(formatter.date(from:)),
            platformIDs: platformIDs(from: active["platform"])
        )
    }

    private static func platformIDs(from value: Any?) -> [Int] {
        guard let values = value as? [Any] else { return [] }
        return values.compactMap { value in
            if let integer = value as? Int { return integer }
            if let number = value as? NSNumber { return number.intValue }
            return nil
        }
    }
}

final class BoosteroidMonitor {
    static let bundleIdentifier = "com.boosteroid.macclient"
    static let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Boosteroid Games S.R.L./bstr_client.log")

    var runningApplications: [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier)
    }

    var isBoosteroidRunning: Bool {
        !runningApplications.isEmpty
    }

    var processIdentifier: Int32? {
        runningApplications.first.map { Int32($0.processIdentifier) }
    }

    func activeGame() throws -> BoosteroidGame? {
        guard isBoosteroidRunning else { return nil }
        let data = try readTail(of: Self.logURL, maximumBytes: 8 * 1_024 * 1_024)
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return BoosteroidLogParser.activeGame(in: text)
    }

    private func readTail(of url: URL, maximumBytes: UInt64) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        if size > maximumBytes {
            try handle.seek(toOffset: size - maximumBytes)
        } else {
            try handle.seek(toOffset: 0)
        }
        return try handle.readToEnd() ?? Data()
    }
}
