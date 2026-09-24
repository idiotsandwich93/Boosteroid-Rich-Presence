import Darwin
import Foundation

enum DiscordRPCError: LocalizedError {
    case notRunning
    case connectionFailed
    case invalidResponse
    case remoteError(String)

    var errorDescription: String? {
        switch self {
        case .notRunning: "Discord Desktop is not running"
        case .connectionFailed: "Could not connect to Discord"
        case .invalidResponse: "Discord returned an invalid response"
        case .remoteError(let message): message
        }
    }
}

final class DiscordRPC {
    private var descriptor: Int32 = -1
    private(set) var clientID: String?
    private var activityProcessIDs: [Int32] = []

    deinit { closeConnection() }

    func setActivity(
        clientID: String,
        game: BoosteroidGame,
        boosteroidActivity: BoosteroidCapturedActivity? = nil,
        processIDs: [Int32] = [getpid()]
    ) throws {
        if self.clientID != clientID || descriptor < 0 {
            try connect(clientID: clientID)
        }

        let activity = Self.activityPayload(
            for: game,
            boosteroidActivity: boosteroidActivity
        )

        let targets = processIDs.isEmpty ? [getpid()] : Array(Set(processIDs))
        for processID in targets {
            try sendActivity(activity, processID: processID)
        }
        activityProcessIDs = targets
    }

    static func activityPayload(
        for game: BoosteroidGame,
        boosteroidActivity: BoosteroidCapturedActivity? = nil
    ) -> [String: Any] {
        var activity: [String: Any] = ["instance": false]

        if let boosteroidActivity, boosteroidActivity.isRelevant(to: game) {
            if let details = sanitizedBoosteroidText(boosteroidActivity.details, for: game) {
                activity["details"] = details
            }
            if let state = sanitizedBoosteroidText(boosteroidActivity.state, for: game) {
                activity["state"] = state
            }
            if let current = boosteroidActivity.partyCurrent,
               let maximum = boosteroidActivity.partyMaximum,
               current >= 0, maximum > 0, current <= maximum {
                var party: [String: Any] = ["size": [current, maximum]]
                if let partyID = boosteroidActivity.partyID { party["id"] = partyID }
                activity["party"] = party
            }
        }

        if activity["details"] == nil, activity["state"] == nil {
            activity["state"] = GameCatalog.displayName(game.name)
        }
        if let startedAt = game.startedAt {
            activity["timestamps"] = ["start": Int(startedAt.timeIntervalSince1970)]
        }
        return activity
    }

    private static func sanitizedBoosteroidText(_ value: String?, for game: BoosteroidGame) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let boilerplate = ["playing on boosteroid", "playing boosteroid", "boosteroid"]
        guard !boilerplate.contains(normalized) else { return nil }

        let cleaned = cleanDisplayText(value)
        guard GameCatalog.normalize(cleaned) != GameCatalog.normalize(game.name) else { return nil }
        return cleaned
    }

    private static func cleanDisplayText(_ value: String) -> String {
        GameCatalog.displayName(value)
    }

    func clearActivity() {
        guard descriptor >= 0 else { return }
        let targets = activityProcessIDs.isEmpty ? [getpid()] : activityProcessIDs
        for processID in targets {
            try? sendActivity(NSNull(), processID: processID)
        }
        activityProcessIDs = []
    }

    func clearActivity(clientID: String, processIDs: [Int32]) throws {
        if self.clientID != clientID || descriptor < 0 {
            try connect(clientID: clientID)
        }
        for processID in Array(Set(processIDs)) {
            try sendActivity(NSNull(), processID: processID)
        }
    }

    func closeConnection() {
        if descriptor >= 0 {
            Darwin.close(descriptor)
        }
        descriptor = -1
        clientID = nil
        activityProcessIDs = []
    }

    private func sendActivity(_ activity: Any, processID: Int32) throws {
        let payload: [String: Any] = [
            "cmd": "SET_ACTIVITY",
            "args": ["pid": Int(processID), "activity": activity],
            "nonce": UUID().uuidString
        ]
        try send(opcode: 1, payload: payload)
        let response = try receiveFrame()
        try validate(response)
    }

    private func connect(clientID: String) throws {
        closeConnection()
        guard let socketPath = Self.socketPaths().first(where: FileManager.default.fileExists(atPath:)) else {
            throw DiscordRPCError.notRunning
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw DiscordRPCError.connectionFailed }

        var noSignal: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let maxPathLength = MemoryLayout.size(ofValue: address.sun_path)
        guard socketPath.utf8.count < maxPathLength else {
            Darwin.close(fd)
            throw DiscordRPCError.connectionFailed
        }
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: maxPathLength) {
                _ = strncpy($0, socketPath, maxPathLength - 1)
            }
        }

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            Darwin.close(fd)
            throw DiscordRPCError.connectionFailed
        }

        descriptor = fd
        try send(opcode: 0, payload: ["v": 1, "client_id": clientID])
        let ready = try receiveFrame()
        try validate(ready)
        self.clientID = clientID
    }

    private func send(opcode: UInt32, payload: [String: Any]) throws {
        let json = try JSONSerialization.data(withJSONObject: payload)
        var frame = Data()
        var littleOpcode = opcode.littleEndian
        var littleLength = UInt32(json.count).littleEndian
        withUnsafeBytes(of: &littleOpcode) { frame.append(contentsOf: $0) }
        withUnsafeBytes(of: &littleLength) { frame.append(contentsOf: $0) }
        frame.append(json)
        try writeAll(frame)
    }

    private func receiveFrame() throws -> [String: Any] {
        let header = try readExactly(8)
        let length = header.withUnsafeBytes { raw in
            UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: 4, as: UInt32.self))
        }
        guard length < 4_000_000 else { throw DiscordRPCError.invalidResponse }
        let payload = try readExactly(Int(length))
        guard let object = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            throw DiscordRPCError.invalidResponse
        }
        return object
    }

    private func validate(_ response: [String: Any]) throws {
        if (response["evt"] as? String) == "ERROR" {
            let data = response["data"] as? [String: Any]
            throw DiscordRPCError.remoteError(data?["message"] as? String ?? "Discord RPC error")
        }
    }

    private func writeAll(_ data: Data) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var sent = 0
            while sent < data.count {
                let count = Darwin.write(descriptor, base.advanced(by: sent), data.count - sent)
                guard count > 0 else { throw DiscordRPCError.connectionFailed }
                sent += count
            }
        }
    }

    private func readExactly(_ count: Int) throws -> Data {
        var data = Data(count: count)
        let received = try data.withUnsafeMutableBytes { rawBuffer -> Int in
            guard let base = rawBuffer.baseAddress else { return 0 }
            var total = 0
            while total < count {
                let amount = Darwin.read(descriptor, base.advanced(by: total), count - total)
                guard amount > 0 else { throw DiscordRPCError.connectionFailed }
                total += amount
            }
            return total
        }
        guard received == count else { throw DiscordRPCError.invalidResponse }
        return data
    }

    private static func socketPaths() -> [String] {
        let environment = ProcessInfo.processInfo.environment
        let roots = [
            environment["XDG_RUNTIME_DIR"], environment["TMPDIR"],
            environment["TMP"], environment["TEMP"], NSTemporaryDirectory(), "/tmp"
        ].compactMap { $0 }
        var paths: [String] = []
        for root in roots {
            for index in 0...9 {
                let path = (root as NSString).appendingPathComponent("discord-ipc-\(index)")
                if !paths.contains(path) { paths.append(path) }
            }
        }
        return paths
    }
}
