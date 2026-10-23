import Combine
import CryptoKit
import Foundation
import Network

extension MahjongLANRoomService {
    func reject(_ reason: String, connection: NWConnection) {
        guard let framed = framedData(for: MahjongLANMessage(type: "rejected", error: reason)) else {
            connection.cancel(); return
        }
        connection.send(content: framed, completion: .contentProcessed { _ in connection.cancel() })
    }

    func beginSnapshots() {
        snapshotTask?.cancel()
        snapshotTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard let self, !Task.isCancelled else { return }
                self.sendSnapshot()
            }
        }
    }

    func sendSnapshot() {
        guard isHosting, let baseSnapshot = game?.makeLANSnapshot() else { return }
        for (id, connection) in hostConnections {
            guard let localSeat = connectionSeats[id] else { continue }
            var snapshot = baseSnapshot
            if snapshot.phase != .roundEnded {
                for seat in 0 ..< snapshot.hands.count where seat != localSeat {
                    snapshot.hands[seat] = Array(repeating: .honor(6), count: snapshot.hands[seat].count)
                }
                snapshot.pendingOptions = snapshot.pendingOptions.filter { $0.key == localSeat }
                snapshot.chosenResponses = snapshot.chosenResponses.filter { $0.key == localSeat }
            }
            send(MahjongLANMessage(type: "snapshot", profiles: hostProfiles, snapshot: snapshot, settlement: hostSettlement), on: connection)
        }
    }

    func updateSyncedProfiles(_ profiles: [MahjongPlayerArchive]) {
        guard profiles.count == 4 else { return }
        syncedProfiles = Dictionary(uniqueKeysWithValues: profiles.enumerated().map { seat, profile in
            var profile = profile
            if let filename = cachedAvatarFilenames[seat] {
                profile.customAvatarFilename = filename
            }
            return (seat, profile)
        })
    }

    func avatarImages() -> [Int: Data] {
        Dictionary(uniqueKeysWithValues: hostProfiles.enumerated().compactMap { seat, profile in
            Self.avatarData(for: profile).map { (seat, $0) }
        })
    }

    func updateAvatarImages(_ images: [Int: Data]) {
        cachedAvatarFilenames.removeAll()
        for (seat, data) in images {
            cacheAvatar(data, for: seat)
        }
    }

    func cacheAvatar(_ data: Data, for seat: Int) {
        guard let filename = Self.cacheRemoteAvatar(data),
              var profile = syncedProfiles[seat] else { return }
        cachedAvatarFilenames[seat] = filename
        profile.customAvatarFilename = filename
        syncedProfiles[seat] = profile
    }

    static func avatarData(for profile: MahjongPlayerArchive) -> Data? {
        guard let filename = profile.customAvatarFilename,
              URL(fileURLWithPath: filename).lastPathComponent == filename,
              let data = try? Data(contentsOf: MahjongArchiveStore.avatarDirectoryURL.appendingPathComponent(filename)),
              data.count <= 2_000_000 else { return nil }
        return data
    }

    static func cacheRemoteAvatar(_ data: Data?) -> String? {
        guard let data, !data.isEmpty, data.count <= 2_000_000 else { return nil }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let filename = "lan-avatar-\(digest).png"
        let directory = MahjongArchiveStore.avatarDirectoryURL
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent(filename), options: .atomic)
            return filename
        } catch {
            return nil
        }
    }

    func removeGuest(connection: NWConnection, seat: Int) {
        let id = ObjectIdentifier(connection)
        guard hostConnections.removeValue(forKey: id) != nil else { return }
        connectionSeats.removeValue(forKey: id)
        restoreAISeat(seat)
        connected = !hostConnections.isEmpty
        refreshRoomAdvertisement()
        status = "玩家已退出 · 当前 \(hostConnections.count) / 3 人"
        sendSnapshot()
    }

    func restoreAISeat(_ seat: Int) {
        guestProfiles.removeValue(forKey: seat)
        guard (1 ..< 4).contains(seat), hostProfiles.indices.contains(seat) else { return }
        let aiProfile = aiSeatProfiles.indices.contains(seat - 1) ? aiSeatProfiles[seat - 1] : Self.emptySeat(seat)
        hostProfiles[seat] = aiProfile
        game?.removeLANGuest(seat: seat, aiNickname: aiProfile.nickname)
        syncedProfiles = Dictionary(uniqueKeysWithValues: hostProfiles.enumerated().map { ($0.offset, $0.element) })
        send(MahjongLANMessage(type: "avatars", avatarImages: avatarImages()), to: Array(hostConnections.values))
    }

    func sendAction(_ action: MahjongLANAction) {
        guard let connection = joinedConnection else { return }
        send(MahjongLANMessage(type: "action", seat: localSeat, action: action), on: connection)
    }

    func send(_ message: MahjongLANMessage, to connections: [NWConnection]) {
        for connection in connections {
            send(message, on: connection)
        }
    }

    func send(_ message: MahjongLANMessage, on connection: NWConnection) {
        guard let framed = framedData(for: message) else { return }
        connection.send(content: framed, completion: .contentProcessed { _ in })
    }

    func framedData(for message: MahjongLANMessage) -> Data? {
        guard var payload = try? JSONEncoder().encode(message) else { return nil }
        payload.append(10)
        return payload
    }

    static var localPlayerID: String {
        let key = "jarvis.mahjong.lan.player-id.v1"
        if let id = UserDefaults.standard.string(forKey: key) {
            return "lan-player-\(id)"
        }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return "lan-player-\(id)"
    }

    static func emptySeat(_ seat: Int) -> MahjongPlayerArchive {
        MahjongPlayerArchive(id: "empty-seat-\(seat)", nickname: "AI", avatarStyle: .player, balance: 0)
    }
}
