import Combine
import Foundation
import Network

struct MahjongLANRoom: Identifiable {
    let code: String
    let endpoint: NWEndpoint
    let serviceName: String

    var id: String { code }
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

    private let queue = DispatchQueue(label: "com.jarvis.mahjong.lan")
    private var browser: NWBrowser?
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var joinedConnection: NWConnection?

    func startBrowsing() {
        browser?.cancel()
        isSearching = true
        rooms = []
        if !isHosting && !isConnecting { status = "正在搜索局域网房间…" }
        let browser = NWBrowser(for: .bonjour(type: Self.bonjourServiceType, domain: nil), using: .tcp)
        self.browser = browser
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let foundRooms = results.compactMap { result -> MahjongLANRoom? in
                guard case let .service(name, _, _, _) = result.endpoint,
                      let code = name.split(separator: "-").last.map(String.init),
                      code.count == 6,
                      code.allSatisfy(\.isNumber) else { return nil }
                return MahjongLANRoom(code: code, endpoint: result.endpoint, serviceName: name)
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.rooms = foundRooms.filter { $0.code != self.roomCode }.sorted { $0.code < $1.code }
                if !self.isHosting && !self.isConnecting && self.listener == nil {
                    if !foundRooms.isEmpty {
                        self.status = "发现 \(foundRooms.count) 个可加入的房间"
                    } else if self.isSearching {
                        self.status = "搜索中，确认双方已连接同一局域网"
                    }
                }
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch state {
                case .ready:
                    self.isSearching = true
                    if !self.listenerIsActiveForHosting && !self.isConnecting { self.status = "正在搜索局域网房间…" }
                case let .waiting(error):
                    self.isSearching = true
                    if !self.listenerIsActiveForHosting && !self.isConnecting {
                        self.status = "局域网搜索等待中：\(Self.networkErrorMessage(error))"
                    }
                case let .failed(error):
                    self.isSearching = false
                    if !self.listenerIsActiveForHosting && !self.isConnecting {
                        self.status = "局域网搜索失败：\(Self.networkErrorMessage(error))"
                    }
                case .cancelled:
                    self.isSearching = false
                default:
                    break
                }
            }
        }
        browser.start(queue: queue)
    }

    func createRoom() {
        guard listener == nil else { return }
        do {
            let code = String(format: "%06d", Int.random(in: 0...999_999))
            let listener = try NWListener(using: .tcp)
            self.listener = listener
            roomCode = code
            // Keep the Bonjour instance name ASCII so discovery works consistently
            // across macOS versions and local network implementations.
            listener.service = NWListener.Service(name: "Jarvis-Mahjong-\(code)", type: Self.bonjourServiceType)
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.isHosting = true
                        self.status = "房间已创建，匹配码：\(code)"
                    case let .waiting(error):
                        self.status = "房间启动等待中：\(Self.networkErrorMessage(error))"
                    case let .failed(error):
                        self.status = "创建房间失败：\(Self.networkErrorMessage(error))"
                        self.isHosting = false
                        self.listener?.cancel()
                        self.listener = nil
                        self.roomCode = nil
                    default:
                        break
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
            listener = nil
            roomCode = nil
            status = "创建房间失败：\(error.localizedDescription)"
        }
    }

    func joinRoom(code: String) {
        guard !isConnecting else { return }
        let normalized = String(code.filter(\.isNumber).suffix(6))
        guard normalized.count == 6,
              let room = rooms.first(where: { $0.code == normalized }) else {
            status = rooms.isEmpty ? "未发现匹配码对应的房间，请确认双方处于同一局域网" : "没有找到匹配码 \(normalized) 的房间"
            return
        }
        isConnecting = true
        status = "正在加入房间…"
        let connection = NWConnection(to: room.endpoint, using: .tcp)
        joinedConnection = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let connection, let service = self else { return }
            if case .ready = state {
                let request = Data("JOIN \(normalized)\n".utf8)
                connection.send(content: request, completion: .contentProcessed { error in
                    Task { @MainActor [service] in
                        if let error {
                            service.isConnecting = false
                            service.status = "加入失败：\(error.localizedDescription)"
                            return
                        }
                        service.receiveJoinResponse(from: connection)
                    }
                })
            } else if case let .failed(error) = state {
                Task { @MainActor [weak self] in
                    self?.isConnecting = false
                    self?.status = "连接失败：\(error.localizedDescription)"
                }
            }
        }
        connection.start(queue: queue)
    }

    func stop() {
        browser?.cancel(); browser = nil
        isSearching = false
        listener?.cancel(); listener = nil
        joinedConnection?.cancel(); joinedConnection = nil
        connections.forEach { $0.cancel() }
        connections.removeAll()
        isHosting = false
        isConnecting = false
        connected = false
        roomCode = nil
    }

    private static func networkErrorMessage(_ error: NWError) -> String {
        let detail = "\(error.localizedDescription)（\(String(describing: error))）"
        let normalized = detail.lowercased()
        if normalized.contains("noauth") || normalized.contains("permission") || normalized.contains("not permitted") || normalized.contains("policy denied") {
            return "\(detail)。请在系统设置›隐私与安全性›本地网络中允许贾维斯访问"
        }
        return detail
    }

    private static let bonjourServiceType = "_mahjong._tcp"

    private var listenerIsActiveForHosting: Bool {
        listener != nil || isHosting
    }

    private func accept(_ connection: NWConnection, roomCode: String) {
        connections.append(connection)
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256) { [weak self, weak connection] data, _, _, error in
            guard let self, let connection, error == nil,
                  let line = data.flatMap({ String(data: $0, encoding: .utf8) }),
                  line.trimmingCharacters(in: .whitespacesAndNewlines) == "JOIN \(roomCode)" else {
                connection?.cancel()
                return
            }
            connection.send(content: Data("OK\n".utf8), completion: .contentProcessed { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.connected = true
                    self.status = "有玩家已通过匹配码加入"
                }
            })
        }
    }

    private func receiveJoinResponse(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64) { [weak self, weak connection] data, _, _, error in
            guard let self, let connection else { return }
            let accepted = error == nil && data.flatMap { String(data: $0, encoding: .utf8) }?.hasPrefix("OK") == true
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isConnecting = false
                self.connected = accepted
                self.status = accepted ? "已加入房间" : "房间拒绝了连接，请重新尝试"
            }
            if !accepted { connection.cancel() }
        }
    }
}
