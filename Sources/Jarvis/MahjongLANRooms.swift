import Combine
import CryptoKit
import Foundation
import Network

struct MahjongLANRoom: Identifiable {
    let code: String
    let endpoint: NWEndpoint
    let serviceName: String
    let ruleset: MahjongRuleset
    let humanCount: Int
    let hostNickname: String
    var id: String {
        code
    }

    var displayName: String {
        "\(ruleset.title) · \(humanCount)/4 · \(hostNickname)的房间"
    }

    static func discovered(
        code: String,
        endpoint: NWEndpoint,
        serviceName: String,
        txtRecord: NWTXTRecord?
    ) -> MahjongLANRoom {
        let ruleset = MahjongRuleset(rawValue: txtRecord?["ruleset"] ?? "") ?? .national
        let humanCount = min(4, max(1, Int(txtRecord?["humans"] ?? "1") ?? 1))
        let advertisedHost = txtRecord?["host"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hostNickname = String((advertisedHost.isEmpty ? "房主" : advertisedHost).prefix(16))
        return MahjongLANRoom(
            code: code,
            endpoint: endpoint,
            serviceName: serviceName,
            ruleset: ruleset,
            humanCount: humanCount,
            hostNickname: hostNickname
        )
    }
}

enum MahjongLANAction: Codable {
    case start, ready, missingSuit(MahjongSuit), multiplier(Int), discard(MahjongTile, drawnTile: Bool), discardDrawn
    case respond(MahjongCallOption), selfDraw, kong(MahjongTile), nextRound, leave
}

struct MahjongLANMessage: Codable {
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
    var ruleset: MahjongRuleset?
}

@MainActor
final class MahjongLANRoomService: ObservableObject {
    @Published var rooms: [MahjongLANRoom] = []
    @Published var roomCode: String?
    @Published var roomRuleset: MahjongRuleset = .national
    @Published var status = "正在搜索局域网房间…"
    @Published var isHosting = false
    @Published var isConnecting = false
    @Published var connected = false
    @Published var isSearching = false
    @Published var localSeat: Int?
    @Published var remoteNickname = "局域网玩家"
    @Published var syncedProfiles: [Int: MahjongPlayerArchive] = [:]
    @Published var settlement: MahjongArchiveSettlement?
    @Published var lastVoiceCue: MahjongVoiceCue?
    @Published var hostLeft = false

    var humanCount: Int {
        isHosting ? 1 + connectionSeats.count : 1
    }

    let queue = DispatchQueue(label: "com.jarvis.mahjong.lan")
    var browser: NWBrowser?
    var listener: NWListener?
    var hostConnections: [ObjectIdentifier: NWConnection] = [:]
    var connectionSeats: [ObjectIdentifier: Int] = [:]
    var joinedConnection: NWConnection?
    var receiveBuffers: [ObjectIdentifier: Data] = [:]
    weak var game: MahjongGame?
    var snapshotTask: Task<Void, Never>?
    var localProfile: MahjongPlayerArchive?
    var hostProfiles: [MahjongPlayerArchive] = []
    var aiSeatProfiles: [MahjongPlayerArchive] = []
    var guestProfiles: [Int: MahjongPlayerArchive] = [:]
    var cachedAvatarFilenames: [Int: String] = [:]
    var hostSettlement: MahjongArchiveSettlement?
    var connectionTimeout: Task<Void, Never>?

    func startBrowsing() {
        browser?.cancel()
        isSearching = true
        rooms = []
        if !isHosting, !isConnecting {
            status = "正在搜索局域网房间…"
        }
        // The plain Bonjour descriptor omits TXT records, so the join list never sees the host nickname.
        let browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: Self.bonjourServiceType, domain: nil),
            using: .tcp
        )
        self.browser = browser
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let foundRooms = results.compactMap { result -> MahjongLANRoom? in
                guard case let .service(name, _, _, _) = result.endpoint,
                      let code = name.split(separator: "-").last.map(String.init),
                      code.count == 6, code.allSatisfy(\.isNumber) else { return nil }
                let record: NWTXTRecord? = if case let .bonjour(txt) = result.metadata {
                    txt
                } else {
                    nil
                }
                return MahjongLANRoom.discovered(
                    code: code,
                    endpoint: result.endpoint,
                    serviceName: name,
                    txtRecord: record
                )
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

    func createRoom(profile: MahjongPlayerArchive, ruleset: MahjongRuleset = .national) {
        guard listener == nil else { return }
        roomRuleset = ruleset
        localProfile = profile
        hostProfiles = [profile] + (1 ..< 4).map(Self.emptySeat)
        syncedProfiles = Dictionary(uniqueKeysWithValues: hostProfiles.enumerated().map { ($0.offset, $0.element) })
        do {
            let code = String(format: "%06d", Int.random(in: 0 ... 999_999))
            let listener = try NWListener(using: .tcp)
            self.listener = listener
            roomCode = code
            listener.service = NWListener.Service(
                name: "Jarvis-Mahjong-\(code)", type: Self.bonjourServiceType,
                txtRecord: roomTXTRecord(humanCount: 1)
            )
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
        connect(to: room.endpoint, code: normalized, ruleset: room.ruleset, profile: profile)
    }

    func connect(
        to endpoint: NWEndpoint,
        code: String,
        ruleset: MahjongRuleset,
        profile: MahjongPlayerArchive
    ) {
        guard !isConnecting, joinedConnection == nil else { return }
        isConnecting = true; status = "正在加入房间…"
        roomCode = code
        roomRuleset = ruleset
        var profile = profile
        profile.id = Self.localPlayerID
        localProfile = profile
        let wireProfile = profile
        let connection = NWConnection(to: endpoint, using: .tcp)
        joinedConnection = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            Task { @MainActor [weak self, weak connection] in
                guard let self, let connection else { return }
                if case .ready = state {
                    self.send(MahjongLANMessage(
                        type: "join",
                        nickname: wireProfile.nickname,
                        profile: wireProfile,
                        avatarData: Self.avatarData(for: wireProfile)
                    ), on: connection)
                    self.receiveLoop(from: connection)
                } else if case let .failed(error) = state {
                    self.isConnecting = false
                    self.joinedConnection = nil
                    self.connectionTimeout?.cancel(); self.connectionTimeout = nil
                    self.status = "连接失败：\(Self.networkErrorMessage(error))"
                }
            }
        }
        connection.start(queue: queue)
        connectionTimeout?.cancel()
        connectionTimeout = Task { [weak self, weak connection] in
            try? await Task.sleep(for: .seconds(12))
            guard let self, let connection, !Task.isCancelled,
                  self.isConnecting, self.joinedConnection === connection else { return }
            self.isConnecting = false
            self.joinedConnection = nil
            self.status = "连接超时，请确认房主在线且双方位于同一局域网"
            connection.cancel()
        }
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
        game.onRoundBalancesRequested = { [weak self] in
            self?.hostProfiles.map(\.balance) ?? []
        }
        beginSnapshots()
        send(MahjongLANMessage(type: "avatars", avatarImages: avatarImages()), to: Array(hostConnections.values))
    }

    func startJoinedGame(_ game: MahjongGame, profile: MahjongPlayerArchive) {
        self.game = game
        let seat = localSeat ?? 1
        game.configureLAN(humanSeats: [0, seat], localSeat: seat, authority: false)
        game.setLANNickname(profile.nickname, for: seat)
        game.onLANAction = { [weak self] action in self?.sendAction(action) }
        game.onRoundBalancesRequested = nil
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
}
