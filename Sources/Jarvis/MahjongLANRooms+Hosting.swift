import Combine
import CryptoKit
import Foundation
import Network

extension MahjongLANRoomService {
    func stop() {
        connectionTimeout?.cancel(); connectionTimeout = nil
        snapshotTask?.cancel(); snapshotTask = nil
        browser?.cancel(); browser = nil
        isSearching = false
        listener?.cancel(); listener = nil
        let clientConnection = joinedConnection
        let shouldSendLeave = !isHosting && clientConnection != nil
        joinedConnection = nil
        if let clientConnection, shouldSendLeave,
           let data = framedData(for: MahjongLANMessage(type: "action", action: .leave))
        {
            clientConnection.send(content: data, completion: .contentProcessed { _ in clientConnection.cancel() })
        } else {
            clientConnection?.cancel()
        }
        hostConnections.values.forEach { $0.cancel() }
        hostConnections.removeAll(); receiveBuffers.removeAll()
        connectionSeats.removeAll(); guestProfiles.removeAll()
        cachedAvatarFilenames.removeAll()
        hostProfiles.removeAll(); aiSeatProfiles.removeAll(); syncedProfiles.removeAll()
        localProfile = nil
        isHosting = false; isConnecting = false; connected = false; localSeat = nil
        game?.onLANAction = nil; game = nil
        roomCode = nil
    }

    func roomTXTRecord(humanCount: Int) -> NWTXTRecord {
        NWTXTRecord([
            "ruleset": roomRuleset.rawValue,
            "humans": String(humanCount),
            "host": String((localProfile?.nickname ?? "房主").prefix(16))
        ])
    }

    func refreshRoomAdvertisement() {
        guard isHosting, let code = roomCode else { return }
        listener?.service = NWListener.Service(
            name: "Jarvis-Mahjong-\(code)", type: Self.bonjourServiceType,
            txtRecord: roomTXTRecord(humanCount: 1 + connectionSeats.count)
        )
    }

    static let bonjourServiceType = "_mahjong._tcp"

    static func networkErrorMessage(_ error: NWError) -> String {
        let detail = "\(error.localizedDescription)（\(String(describing: error))）"
        let normalized = detail.lowercased()
        if normalized.contains("noauth") || normalized.contains("permission") || normalized.contains("not permitted") || normalized.contains("policy denied") {
            return "\(detail)。请在系统设置›隐私与安全性›本地网络中允许工作搭子 Jarvis 访问"
        }
        return detail
    }

    func accept(_ connection: NWConnection, roomCode _: String) {
        connection.start(queue: queue)
        receiveLoop(from: connection)
    }

    func receiveLoop(from connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak connection] data, _, complete, error in
            guard let self, let connection else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let data, !data.isEmpty {
                    guard self.consume(data, from: connection, id: id) else { return }
                }
                if error != nil || complete {
                    self.receiveBuffers.removeValue(forKey: id)
                    if let hostConnection = self.hostConnections.removeValue(forKey: id) {
                        let seat = self.connectionSeats.removeValue(forKey: id)
                        self.connected = !self.hostConnections.isEmpty
                        self.status = "玩家已断开 · 当前 \(self.hostConnections.count) / 3 人"
                        if let seat {
                            self.restoreAISeat(seat)
                        }
                        self.refreshRoomAdvertisement()
                        hostConnection.cancel()
                        self.sendSnapshot()
                    }
                    if self.joinedConnection === connection {
                        let wasConnecting = self.isConnecting
                        self.joinedConnection = nil; self.connected = false
                        self.isConnecting = false
                        self.connectionTimeout?.cancel(); self.connectionTimeout = nil
                        self.status = wasConnecting
                            ? "连接被房主关闭，请确认房间仍可加入"
                            : "与房主的连接已断开"
                        if self.game != nil {
                            self.hostLeft = true
                            self.game?.leaveTableLocally()
                        }
                    }
                    return
                }
                self.receiveLoop(from: connection)
            }
        }
    }

    func consume(_ data: Data, from connection: NWConnection, id: ObjectIdentifier) -> Bool {
        var buffer = receiveBuffers[id, default: Data()]
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 10) {
            let line = buffer.prefix(upTo: newline)
            buffer.removeSubrange(...newline)
            guard line.count <= 16_000_000 else { connection.cancel(); return false }
            handle(line: Data(line), from: connection)
        }
        guard buffer.count <= 16_000_000 else { connection.cancel(); return false }
        receiveBuffers[id] = buffer
        return true
    }

    func handle(line: Data, from connection: NWConnection) {
        guard let message = try? JSONDecoder().decode(MahjongLANMessage.self, from: line) else { return }
        if isHosting {
            switch message.type {
            case "join":
                let id = ObjectIdentifier(connection)
                let occupiedSeats = Set(connectionSeats.values)
                guard let seat = (1 ..< 4).first(where: { !occupiedSeats.contains($0) }) else {
                    reject("房间已满，最多支持四位真人玩家", connection: connection)
                    return
                }
                hostConnections[id] = connection
                connectionSeats[id] = seat
                remoteNickname = String((message.nickname ?? "玩家").prefix(16))
                var guestProfile: MahjongPlayerArchive = if let profile = message.profile {
                    profile
                } else {
                    MahjongPlayerArchive(id: Self.localPlayerID, nickname: remoteNickname, avatarStyle: .player, balance: MahjongArchiveStore.initialBalance)
                }
                guestProfile.nickname = remoteNickname
                guestProfile.customAvatarFilename = Self.cacheRemoteAvatar(message.avatarData)
                guestProfiles[seat] = guestProfile
                if hostProfiles.count != 4 {
                    hostProfiles = (0 ..< 4).map { seat in Self.emptySeat(seat) }
                }
                hostProfiles[seat] = guestProfile
                game?.addLANGuest(seat: seat, nickname: remoteNickname)
                syncedProfiles = Dictionary(uniqueKeysWithValues: hostProfiles.enumerated().map { ($0.offset, $0.element) })
                connected = true
                refreshRoomAdvertisement()
                status = "已连接 \(hostConnections.count) / 3 位玩家"
                send(MahjongLANMessage(
                    type: "joined",
                    seat: seat,
                    nickname: hostProfiles[0].nickname,
                    profiles: hostProfiles,
                    avatarImages: avatarImages(),
                    ruleset: roomRuleset
                ), on: connection)
                if let avatarData = message.avatarData {
                    send(
                        MahjongLANMessage(type: "avatar", seat: seat, avatarData: avatarData),
                        to: hostConnections.filter { $0.key != id }.map(\.value)
                    )
                }
                sendSnapshot()
            case "action":
                if let action = message.action {
                    let seat = connectionSeats[ObjectIdentifier(connection)]
                    if case .leave = action {
                        if let seat {
                            removeGuest(connection: connection, seat: seat)
                        }
                        connection.cancel()
                    } else {
                        if let seat {
                            game?.performRemoteAction(action, seat: seat)
                        }
                    }
                }
            default: break
            }
        } else {
            switch message.type {
            case "joined":
                localSeat = message.seat ?? 1
                remoteNickname = message.nickname ?? "房主"
                if let ruleset = message.ruleset {
                    roomRuleset = ruleset
                }
                if let profiles = message.profiles {
                    updateSyncedProfiles(profiles)
                }
                if let images = message.avatarImages {
                    updateAvatarImages(images)
                }
                isConnecting = false; connected = true
                connectionTimeout?.cancel(); connectionTimeout = nil
                status = "已加入房间，正在同步牌局…"
            case "snapshot":
                if let snapshot = message.snapshot {
                    game?.applyLANSnapshot(snapshot)
                }
                if let profiles = message.profiles {
                    updateSyncedProfiles(profiles)
                }
                settlement = message.settlement
                isConnecting = false; connected = true
            case "voice":
                lastVoiceCue = message.voiceCue
            case "avatar":
                if let seat = message.seat, let data = message.avatarData {
                    cacheAvatar(data, for: seat)
                }
            case "avatars":
                if let images = message.avatarImages {
                    updateAvatarImages(images)
                }
            case "rejected":
                isConnecting = false; connected = false
                connectionTimeout?.cancel(); connectionTimeout = nil
                status = message.error ?? "房间已满"
                joinedConnection = nil
                connection.cancel()
            default: break
            }
        }
    }
}
