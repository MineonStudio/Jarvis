import Combine
import CryptoKit
import Foundation
import Network

struct MahjongLANRoom: Identifiable {
    let code: String
    let endpoint: NWEndpoint
    let serviceName: String
    var id: String {
        code
    }
}

enum MahjongLANAction: Codable {
    case start, ready, missingSuit(MahjongSuit), discard(MahjongTile, drawnTile: Bool), discardDrawn
    case respond(MahjongCallOption), selfDraw, kong(MahjongTile), nextRound, leave
}

private struct MahjongLANMessage: Codable {
    var type: String
    var seat: Int?
    var nickname: String?
    var profile: MahjongPlayerArchive?
    var profiles: [MahjongPlayerArchive]?
    var avatarData: Data?
    var avatarImages: [Int: Data]?
    var action: MahjongLANAction?
    var snapshot: MahjongGameSnapshot?
    var settlement: MahjongArchiveSettlement?
    var voiceCue: MahjongVoiceCue?
    var error: String?
}

@MainActor
final class MahjongLANRoomService: ObservableObject {
    @Published private(set) var rooms: [MahjongLANRoom] = []
    @Published private(set) var roomCode: String?
    @Published private(set) var status = "正在搜索局域网房间…"
    @Published private(set) var isHosting = false
    @Published private(set) var isConnecting = false
    @Published private(set) var connected = false
    @Published private(set) var isSearching = false
    @Published private(set) var localSeat: Int?
    @Published private(set) var remoteNickname = "局域网玩家"
    @Published private(set) var syncedProfiles: [Int: MahjongPlayerArchive] = [:]
    @Published private(set) var settlement: MahjongArchiveSettlement?
    @Published private(set) var lastVoiceCue: MahjongVoiceCue?
    @Published private(set) var hostLeft = false

    private let queue = DispatchQueue(label: "com.jarvis.mahjong.lan")
    private var browser: NWBrowser?
    private var listener: NWListener?
    private var hostConnections: [ObjectIdentifier: NWConnection] = [:]
    private var connectionSeats: [ObjectIdentifier: Int] = [:]
    private var joinedConnection: NWConnection?
    private var receiveBuffers: [ObjectIdentifier: Data] = [:]
    private weak var game: MahjongGame?
    private var snapshotTask: Task<Void, Never>?
    private var localProfile: MahjongPlayerArchive?
    private var hostProfiles: [MahjongPlayerArchive] = []
    private var aiSeatProfiles: [MahjongPlayerArchive] = []
    private var guestProfiles: [Int: MahjongPlayerArchive] = [:]
    private var cachedAvatarFilenames: [Int: String] = [:]
    private var hostSettlement: MahjongArchiveSettlement?

    func startBrowsing() {
        browser?.cancel()
        isSearching = true
        rooms = []
        if !isHosting, !isConnecting {
            status = "正在搜索局域网房间…"
        }
        let browser = NWBrowser(for: .bonjour(type: Self.bonjourServiceType, domain: nil), using: .tcp)
        self.browser = browser
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let foundRooms = results.compactMap { result -> MahjongLANRoom? in
                guard case let .service(name, _, _, _) = result.endpoint,
                      let code = name.split(separator: "-").last.map(String.init),
                      code.count == 6, code.allSatisfy(\.isNumber) else { return nil }
                return MahjongLANRoom(code: code, endpoint: result.endpoint, serviceName: name)
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.rooms = foundRooms.filter { $0.code != self.roomCode }.sorted { $0.code < $1.code }
                if !self.isHosting, !self.isConnecting {
                    self.status = foundRooms.isEmpty ? "搜索中，确认双方已连接同一局域网" : "发现 \(foundRooms.count) 个可加入的房间"
                }
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch state {
                case .ready:
                    self.isSearching = true
                case let .waiting(error):
                    self.status = "局域网搜索等待中：\(Self.networkErrorMessage(error))"
                case let .failed(error):
                    self.isSearching = false
                    self.status = "局域网搜索失败：\(Self.networkErrorMessage(error))"
                case .cancelled:
                    self.isSearching = false
                default: break
                }
            }
        }
        browser.start(queue: queue)
    }

    func createRoom(profile: MahjongPlayerArchive) {
        guard listener == nil else { return }
        localProfile = profile
        hostProfiles = [profile] + (1 ..< 4).map(Self.emptySeat)
        syncedProfiles = Dictionary(uniqueKeysWithValues: hostProfiles.enumerated().map { ($0.offset, $0.element) })
        do {
            let code = String(format: "%06d", Int.random(in: 0 ... 999_999))
            let listener = try NWListener(using: .tcp)
            self.listener = listener
            roomCode = code
            listener.service = NWListener.Service(name: "Jarvis-Mahjong-\(code)", type: Self.bonjourServiceType)
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.isHosting = true
                        self.status = "房间已创建，匹配码：\(code)"
                    case let .waiting(error): self.status = "房间启动等待中：\(Self.networkErrorMessage(error))"
                    case let .failed(error):
                        self.status = "创建房间失败：\(Self.networkErrorMessage(error))"
                        self.isHosting = false
                        self.listener?.cancel(); self.listener = nil; self.roomCode = nil
                    default: break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor [weak self] in
                    guard let self else { connection.cancel(); return }
                    self.accept(connection, roomCode: code)
                }
            }
            listener.start(queue: queue)
        } catch {
            listener = nil; roomCode = nil
            status = "创建房间失败：\(error.localizedDescription)"
        }
    }

    func joinRoom(code: String, profile: MahjongPlayerArchive) {
        guard !isConnecting else { return }
        let normalized = String(code.filter(\.isNumber).suffix(6))
        guard normalized.count == 6,
              let room = rooms.first(where: { $0.code == normalized })
        else {
            status = rooms.isEmpty ? "未发现匹配码对应的房间，请确认双方处于同一局域网" : "没有找到匹配码 \(normalized) 的房间"
            return
        }
        isConnecting = true; status = "正在加入房间…"
        roomCode = normalized
        var profile = profile
        profile.id = Self.localPlayerID
        localProfile = profile
        let wireProfile = profile
        let connection = NWConnection(to: room.endpoint, using: .tcp)
        joinedConnection = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            Task { @MainActor [weak self, weak connection] in
                guard let self, let connection else { return }
                if case .ready = state {
                    self.send(MahjongLANMessage(type: "join", nickname: wireProfile.nickname, profile: wireProfile,
                                                avatarData: Self.avatarData(for: wireProfile)), on: connection)
                    self.receiveLoop(from: connection)
                } else if case let .failed(error) = state {
                    self.isConnecting = false
                    self.status = "连接失败：\(Self.networkErrorMessage(error))"
                }
            }
        }
        connection.start(queue: queue)
    }

    func startHostGame(_ game: MahjongGame, profile: MahjongPlayerArchive, aiProfiles: [MahjongPlayerArchive]) {
        self.game = game
        aiSeatProfiles = (0 ..< 3).map { index in
            aiProfiles.indices.contains(index) ? aiProfiles[index] : Self.emptySeat(index + 1)
        }
        hostProfiles = [profile] + aiSeatProfiles
        for (seat, guest) in guestProfiles {
            hostProfiles[seat] = guest
        }
        syncedProfiles = Dictionary(uniqueKeysWithValues: hostProfiles.enumerated().map { ($0.offset, $0.element) })
        game.configureLAN(humanSeats: [0] + Array(connectionSeats.values), localSeat: 0, authority: true)
        game.setLANNickname(profile.nickname, for: 0)
        for (seat, guest) in guestProfiles {
            game.setLANNickname(guest.nickname, for: seat)
        }
        game.onLANAction = nil
        beginSnapshots()
        send(MahjongLANMessage(type: "avatars", avatarImages: avatarImages()), to: Array(hostConnections.values))
    }

    func startJoinedGame(_ game: MahjongGame, profile: MahjongPlayerArchive) {
        self.game = game
        let seat = localSeat ?? 1
        game.configureLAN(humanSeats: [0, seat], localSeat: seat, authority: false)
        game.setLANNickname(profile.nickname, for: seat)
        game.onLANAction = { [weak self] action in self?.sendAction(action) }
        status = "已加入对局 · 你是\(game.seatName(seat))"
    }

    func publishSettlement(_ settlement: MahjongArchiveSettlement, profiles: [MahjongPlayerArchive]) {
        guard isHosting else { return }
        hostSettlement = settlement
        hostProfiles = profiles
        for seat in 1 ..< 4 where !(game?.humanSeats.contains(seat) ?? false) {
            aiSeatProfiles[seat - 1] = profiles[seat]
        }
        self.settlement = settlement
        syncedProfiles = Dictionary(uniqueKeysWithValues: profiles.enumerated().map { ($0.offset, $0.element) })
        sendSnapshot()
    }

    func clearSettlement() {
        guard isHosting else { return }
        hostSettlement = nil
        settlement = nil
        sendSnapshot()
    }

    func broadcastVoiceCue(_ cue: MahjongVoiceCue) {
        guard isHosting else { return }
        send(MahjongLANMessage(type: "voice", seat: cue.seat, voiceCue: cue), to: Array(hostConnections.values))
    }

    func stop() {
        snapshotTask?.cancel(); snapshotTask = nil
        browser?.cancel(); browser = nil
        isSearching = false
        listener?.cancel(); listener = nil
        let clientConnection = joinedConnection
        let shouldSendLeave = !isHosting && clientConnection != nil
        joinedConnection = nil
        if let clientConnection, shouldSendLeave,
           var data = try? JSONEncoder().encode(MahjongLANMessage(type: "action", action: .leave))
        {
            data.append(10)
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

    private static let bonjourServiceType = "_mahjong._tcp"

    private static func networkErrorMessage(_ error: NWError) -> String {
        let detail = "\(error.localizedDescription)（\(String(describing: error))）"
        let normalized = detail.lowercased()
        if normalized.contains("noauth") || normalized.contains("permission") || normalized.contains("not permitted") || normalized.contains("policy denied") {
            return "\(detail)。请在系统设置›隐私与安全性›本地网络中允许贾维斯访问"
        }
        return detail
    }

    private func accept(_ connection: NWConnection, roomCode _: String) {
        connection.start(queue: queue)
        receiveLoop(from: connection)
    }

    private func receiveLoop(from connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak connection] data, _, complete, error in
            guard let self, let connection else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let data, !data.isEmpty {
                    var buffer = self.receiveBuffers[id, default: Data()]
                    buffer.append(data)
                    while let newline = buffer.firstIndex(of: 10) {
                        let line = buffer.prefix(upTo: newline)
                        buffer.removeSubrange(...newline)
                        self.handle(line: Data(line), from: connection)
                    }
                    self.receiveBuffers[id] = buffer
                }
                if error != nil || complete {
                    self.receiveBuffers.removeValue(forKey: id)
                    if let hostConnection = self.hostConnections.removeValue(forKey: id) {
                        let seat = self.connectionSeats.removeValue(forKey: id)
                        self.connected = !self.hostConnections.isEmpty
                        self.status = "局域网玩家已断开 · 当前 \(self.hostConnections.count) / 3 人"
                        if let seat {
                            self.restoreAISeat(seat)
                        }
                        hostConnection.cancel()
                        self.sendSnapshot()
                    }
                    if self.joinedConnection === connection {
                        self.joinedConnection = nil; self.connected = false
                        self.status = "与房主的连接已断开"
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

    private func handle(line: Data, from connection: NWConnection) {
        guard let message = try? JSONDecoder().decode(MahjongLANMessage.self, from: line) else { return }
        if isHosting {
            switch message.type {
            case "join":
                let id = ObjectIdentifier(connection)
                let occupiedSeats = Set(connectionSeats.values)
                guard let seat = (1 ..< 4).first(where: { !occupiedSeats.contains($0) }) else {
                    send(MahjongLANMessage(type: "rejected", error: "房间已满，最多支持四位真人玩家"), on: connection)
                    connection.cancel(); return
                }
                hostConnections[id] = connection
                connectionSeats[id] = seat
                remoteNickname = String((message.nickname ?? "局域网玩家").prefix(16))
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
                status = "已连接 \(hostConnections.count) / 3 位局域网玩家"
                send(MahjongLANMessage(type: "joined", seat: seat, nickname: hostProfiles[0].nickname,
                                       profiles: hostProfiles, avatarImages: avatarImages()), on: connection)
                if let avatarData = message.avatarData {
                    send(MahjongLANMessage(type: "avatar", seat: seat, avatarData: avatarData),
                         to: hostConnections.filter { $0.key != id }.map(\.value))
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
                if let profiles = message.profiles {
                    updateSyncedProfiles(profiles)
                }
                if let images = message.avatarImages {
                    updateAvatarImages(images)
                }
                isConnecting = false; connected = true
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
                status = message.error ?? "房间已满"
                connection.cancel()
            default: break
            }
        }
    }

    private func beginSnapshots() {
        snapshotTask?.cancel()
        snapshotTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard let self, !Task.isCancelled else { return }
                self.sendSnapshot()
            }
        }
    }

    private func sendSnapshot() {
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

    private func updateSyncedProfiles(_ profiles: [MahjongPlayerArchive]) {
        guard profiles.count == 4 else { return }
        syncedProfiles = Dictionary(uniqueKeysWithValues: profiles.enumerated().map { seat, profile in
            var profile = profile
            if let filename = cachedAvatarFilenames[seat] {
                profile.customAvatarFilename = filename
            }
            return (seat, profile)
        })
    }

    private func avatarImages() -> [Int: Data] {
        Dictionary(uniqueKeysWithValues: hostProfiles.enumerated().compactMap { seat, profile in
            Self.avatarData(for: profile).map { (seat, $0) }
        })
    }

    private func updateAvatarImages(_ images: [Int: Data]) {
        cachedAvatarFilenames.removeAll()
        for (seat, data) in images { cacheAvatar(data, for: seat) }
    }

    private func cacheAvatar(_ data: Data, for seat: Int) {
        guard let filename = Self.cacheRemoteAvatar(data),
              var profile = syncedProfiles[seat] else { return }
        cachedAvatarFilenames[seat] = filename
        profile.customAvatarFilename = filename
        syncedProfiles[seat] = profile
    }

    private static func avatarData(for profile: MahjongPlayerArchive) -> Data? {
        guard let filename = profile.customAvatarFilename,
              URL(fileURLWithPath: filename).lastPathComponent == filename,
              let data = try? Data(contentsOf: MahjongArchiveStore.avatarDirectoryURL.appendingPathComponent(filename)),
              data.count <= 2_000_000 else { return nil }
        return data
    }

    private static func cacheRemoteAvatar(_ data: Data?) -> String? {
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

    private func removeGuest(connection: NWConnection, seat: Int) {
        let id = ObjectIdentifier(connection)
        guard hostConnections.removeValue(forKey: id) != nil else { return }
        connectionSeats.removeValue(forKey: id)
        restoreAISeat(seat)
        connected = !hostConnections.isEmpty
        status = "局域网玩家已退出 · 当前 \(hostConnections.count) / 3 人"
        sendSnapshot()
    }

    private func restoreAISeat(_ seat: Int) {
        guestProfiles.removeValue(forKey: seat)
        guard (1 ..< 4).contains(seat), hostProfiles.indices.contains(seat) else { return }
        let aiProfile = aiSeatProfiles.indices.contains(seat - 1) ? aiSeatProfiles[seat - 1] : Self.emptySeat(seat)
        hostProfiles[seat] = aiProfile
        game?.removeLANGuest(seat: seat, aiNickname: aiProfile.nickname)
        syncedProfiles = Dictionary(uniqueKeysWithValues: hostProfiles.enumerated().map { ($0.offset, $0.element) })
        send(MahjongLANMessage(type: "avatars", avatarImages: avatarImages()), to: Array(hostConnections.values))
    }

    private func sendAction(_ action: MahjongLANAction) {
        guard let connection = joinedConnection else { return }
        send(MahjongLANMessage(type: "action", seat: localSeat, action: action), on: connection)
    }

    private func send(_ message: MahjongLANMessage, to connections: [NWConnection]) {
        for connection in connections {
            send(message, on: connection)
        }
    }

    private func send(_ message: MahjongLANMessage, on connection: NWConnection) {
        guard let data = try? JSONEncoder().encode(message) else { return }
        var framed = data; framed.append(10)
        connection.send(content: framed, completion: .contentProcessed { _ in })
    }

    private static var localPlayerID: String {
        let key = "jarvis.mahjong.lan.player-id.v1"
        if let id = UserDefaults.standard.string(forKey: key) {
            return "lan-player-\(id)"
        }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return "lan-player-\(id)"
    }

    private static func emptySeat(_ seat: Int) -> MahjongPlayerArchive {
        MahjongPlayerArchive(id: "empty-seat-\(seat)", nickname: "AI", avatarStyle: .player, balance: 0)
    }
}
