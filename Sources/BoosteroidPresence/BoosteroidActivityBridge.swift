import Darwin
import Foundation

struct BoosteroidCapturedActivity: Equatable, Sendable {
    let details: String?
    let state: String?
    let partyID: String?
    let partyCurrent: Int?
    let partyMaximum: Int?
    let capturedAt: Date

    func isRelevant(to game: BoosteroidGame) -> Bool {
        guard let startedAt = game.startedAt else { return true }
        return capturedAt >= startedAt.addingTimeInterval(-15)
    }

    var gameTitleCandidate: String? {
        guard let details else { return nil }
        let normalized = details.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let boilerplate = ["playing on boosteroid", "playing boosteroid", "boosteroid"]
        return boilerplate.contains(normalized) ? nil : details
    }
}

enum BoosteroidActivityBridgeError: LocalizedError {
    case socketCreationFailed
    case socketPathTooLong
    case bindFailed
    case listenFailed

    var errorDescription: String? {
        switch self {
        case .socketCreationFailed: "Could not create the Boosteroid activity filter socket"
        case .socketPathTooLong: "The Boosteroid activity filter socket path is too long"
        case .bindFailed: "Could not bind the Boosteroid activity filter socket"
        case .listenFailed: "Could not listen for Boosteroid activity updates"
        }
    }
}

final class BoosteroidActivityBridge: @unchecked Sendable {
    private let queue = DispatchQueue(
        label: "dev.karmadevz.boosteroid-presence.activity-filter",
        attributes: .concurrent
    )
    private let lock = NSLock()
    private var listener: Int32 = -1
    private var clients: Set<Int32> = []
    private var capturedActivity: BoosteroidCapturedActivity?

    private let boosteroidClientID = "1170028348756471908"

    var socketURL: URL {
        BoosteroidLauncher.isolatedRuntimeURL.appendingPathComponent("discord-ipc-0")
    }

    func start() throws {
        lock.lock()
        if listener >= 0 {
            lock.unlock()
            return
        }
        lock.unlock()

        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: BoosteroidLauncher.isolatedRuntimeURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        unlink(socketURL.path)

        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw BoosteroidActivityBridgeError.socketCreationFailed }

        var noSignal: Int32 = 1
        _ = setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSignal,
            socklen_t(MemoryLayout<Int32>.size)
        )

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let maximumPathLength = MemoryLayout.size(ofValue: address.sun_path)
        guard socketURL.path.utf8.count < maximumPathLength else {
            Darwin.close(descriptor)
            throw BoosteroidActivityBridgeError.socketPathTooLong
        }
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: maximumPathLength) {
                _ = strncpy($0, socketURL.path, maximumPathLength - 1)
            }
        }

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            Darwin.close(descriptor)
            throw BoosteroidActivityBridgeError.bindFailed
        }
        guard Darwin.listen(descriptor, 8) == 0 else {
            Darwin.close(descriptor)
            unlink(socketURL.path)
            throw BoosteroidActivityBridgeError.listenFailed
        }

        lock.lock()
        listener = descriptor
        lock.unlock()
        AppLogger.log("Boosteroid Discord activity filter listening at \(socketURL.path)")

        queue.async { [weak self] in
            self?.acceptLoop(descriptor: descriptor)
        }
    }

    func stop() {
        lock.lock()
        let listenerToClose = listener
        listener = -1
        let clientsToClose = clients
        clients.removeAll()
        lock.unlock()

        if listenerToClose >= 0 { Darwin.close(listenerToClose) }
        for client in clientsToClose { Darwin.close(client) }
        unlink(socketURL.path)
    }

    func latestActivity(for game: BoosteroidGame) -> BoosteroidCapturedActivity? {
        lock.lock()
        defer { lock.unlock() }
        guard let capturedActivity, capturedActivity.isRelevant(to: game) else { return nil }
        return capturedActivity
    }

    var latestCapturedActivity: BoosteroidCapturedActivity? {
        lock.lock()
        defer { lock.unlock() }
        return capturedActivity
    }

    private func acceptLoop(descriptor: Int32) {
        while true {
            let client = Darwin.accept(descriptor, nil, nil)
            guard client >= 0 else { return }

            lock.lock()
            guard listener == descriptor else {
                lock.unlock()
                Darwin.close(client)
                return
            }
            clients.insert(client)
            lock.unlock()

            queue.async { [weak self] in
                self?.handleClient(client)
            }
        }
    }

    private func handleClient(_ descriptor: Int32) {
        defer {
            lock.lock()
            clients.remove(descriptor)
            lock.unlock()
            Darwin.close(descriptor)
        }

        var clientID: String?
        while let frame = Self.receiveFrame(from: descriptor) {
            switch frame.opcode {
            case 0:
                clientID = frame.payload["client_id"] as? String
                guard Self.sendJSON(
                    Self.readyPayload,
                    opcode: 1,
                    to: descriptor
                ) else { return }
                AppLogger.log("Captured Boosteroid Discord RPC connection (client \(clientID ?? "unknown"))")

            case 1:
                if (frame.payload["cmd"] as? String) == "SET_ACTIVITY",
                   clientID == boosteroidClientID {
                    captureActivity(from: frame.payload)
                }
                let response: [String: Any] = [
                    "cmd": frame.payload["cmd"] as? String ?? "SET_ACTIVITY",
                    "data": frame.payload["args"] ?? [:],
                    "evt": NSNull(),
                    "nonce": frame.payload["nonce"] ?? NSNull()
                ]
                guard Self.sendJSON(response, opcode: 1, to: descriptor) else { return }

            case 2:
                return

            case 3:
                guard Self.sendJSON(frame.payload, opcode: 4, to: descriptor) else { return }

            default:
                continue
            }
        }
    }

    private func captureActivity(from payload: [String: Any]) {
        let arguments = payload["args"] as? [String: Any]
        guard let activity = arguments?["activity"] as? [String: Any] else {
            lock.lock()
            capturedActivity = nil
            lock.unlock()
            AppLogger.log("Boosteroid cleared its captured Discord activity")
            return
        }

        let party = activity["party"] as? [String: Any]
        let partySize = party?["size"] as? [Any]
        let captured = BoosteroidCapturedActivity(
            details: Self.nonemptyString(activity["details"]),
            state: Self.nonemptyString(activity["state"]),
            partyID: Self.nonemptyString(party?["id"]),
            partyCurrent: Self.integer(partySize?.first),
            partyMaximum: Self.integer(partySize?.dropFirst().first),
            capturedAt: Date()
        )

        lock.lock()
        let changed = captured.details != capturedActivity?.details
            || captured.state != capturedActivity?.state
            || captured.partyID != capturedActivity?.partyID
            || captured.partyCurrent != capturedActivity?.partyCurrent
            || captured.partyMaximum != capturedActivity?.partyMaximum
        capturedActivity = captured
        lock.unlock()

        if changed {
            let partyDescription: String
            if let current = captured.partyCurrent, let maximum = captured.partyMaximum {
                partyDescription = ", party \(current)/\(maximum)"
            } else {
                partyDescription = ""
            }
            AppLogger.log(
                "Captured Boosteroid activity: details=\(captured.details ?? "none"), state=\(captured.state ?? "none")\(partyDescription)"
            )
        }
    }

    private static func nonemptyString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private static var readyPayload: [String: Any] {
        [
            "cmd": "DISPATCH",
            "data": [
                "v": 1,
                "config": [
                    "cdn_host": "cdn.discordapp.com",
                    "api_endpoint": "//discord.com/api",
                    "environment": "production"
                ],
                "user": [
                    "id": "0",
                    "username": "Boosteroid Presence",
                    "discriminator": "0000",
                    "avatar": NSNull(),
                    "flags": 0,
                    "premium_type": 0
                ]
            ],
            "evt": "READY",
            "nonce": NSNull()
        ]
    }

    private static func receiveFrame(from descriptor: Int32) -> (opcode: UInt32, payload: [String: Any])? {
        guard let header = readExactly(8, from: descriptor) else { return nil }
        let opcode = header.withUnsafeBytes {
            UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))
        }
        let length = header.withUnsafeBytes {
            UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self))
        }
        guard length < 4_000_000,
              let data = readExactly(Int(length), from: descriptor),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return (opcode, payload)
    }

    private static func readExactly(_ count: Int, from descriptor: Int32) -> Data? {
        var data = Data(count: count)
        let complete = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress else { return count == 0 }
            var received = 0
            while received < count {
                let result = Darwin.read(descriptor, base.advanced(by: received), count - received)
                guard result > 0 else { return false }
                received += result
            }
            return true
        }
        return complete ? data : nil
    }

    private static func sendJSON(
        _ payload: [String: Any],
        opcode: UInt32,
        to descriptor: Int32
    ) -> Bool {
        guard let json = try? JSONSerialization.data(withJSONObject: payload) else { return false }
        var data = Data()
        var littleOpcode = opcode.littleEndian
        var littleLength = UInt32(json.count).littleEndian
        withUnsafeBytes(of: &littleOpcode) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &littleLength) { data.append(contentsOf: $0) }
        data.append(json)

        return data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return true }
            var sent = 0
            while sent < data.count {
                let result = Darwin.write(descriptor, base.advanced(by: sent), data.count - sent)
                guard result > 0 else { return false }
                sent += result
            }
            return true
        }
    }
}
