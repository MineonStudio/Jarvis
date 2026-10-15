import Foundation

public enum TransferDirection: String, Codable { case upload = "接收", download = "发送" }
public enum TransferStatus: String, Codable {
    case pending = "等待接收", accepted = "等待发送", active = "传输中"
    case completed = "已完成", failed = "失败", cancelled = "已取消"
}

public struct LANConnectedDevice: Identifiable, Equatable, Sendable {
    public let id: String
    public let ipAddress: String
    public let connectedAt: Date
    public let colorHue: Double

    public init(id: String, ipAddress: String, connectedAt: Date, colorHue: Double) {
        self.id = id
        self.ipAddress = ipAddress
        self.connectedAt = connectedAt
        self.colorHue = colorHue
    }
}

public enum TransferTaskFilter: String, CaseIterable, Identifiable, Hashable {
    case all
    case received
    case sent

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .all: "全部"
        case .received: "接收"
        case .sent: "发送"
        }
    }

    public func matches(_ transfer: Transfer) -> Bool {
        switch self {
        case .all: true
        case .received: transfer.direction == .upload
        case .sent: transfer.direction == .download
        }
    }
}

enum TransferByteCount {
    private static let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()

    static func string(from bytes: Int64) -> String {
        formatter.string(fromByteCount: bytes)
    }
}

public struct Transfer: Identifiable, Codable {
    public let id: UUID
    public let name: String
    public let direction: TransferDirection
    public let total: Int64
    public var done: Int64 = 0
    public var bytesPerSecond: Double = 0
    public var status: TransferStatus = .active
    public var detail: String = ""
    public var resourceURL: URL?
    public var textContent: String?
    public var targetDeviceIP: String?
    public var isText: Bool { textContent != nil }
    public var isInProgress: Bool {
        status == .pending || status == .accepted || status == .active
    }

    public var fraction: Double {
        total > 0 ? min(1, Double(done) / Double(total)) : 0
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, direction, total, done, bytesPerSecond, status, detail, resourceURL, textContent, targetDeviceIP
    }

    public init(
        id: UUID,
        name: String,
        direction: TransferDirection,
        total: Int64,
        done: Int64 = 0,
        bytesPerSecond: Double = 0,
        status: TransferStatus = .active,
        detail: String = "",
        resourceURL: URL? = nil,
        textContent: String? = nil,
        targetDeviceIP: String? = nil
    ) {
        self.id = id
        self.name = name
        self.direction = direction
        self.total = total
        self.done = done
        self.bytesPerSecond = bytesPerSecond
        self.status = status
        self.detail = detail
        self.resourceURL = resourceURL
        self.textContent = textContent
        self.targetDeviceIP = targetDeviceIP
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        direction = try values.decode(TransferDirection.self, forKey: .direction)
        total = try values.decode(Int64.self, forKey: .total)
        done = try values.decodeIfPresent(Int64.self, forKey: .done) ?? 0
        bytesPerSecond = try values.decodeIfPresent(Double.self, forKey: .bytesPerSecond) ?? 0
        status = try values.decodeIfPresent(TransferStatus.self, forKey: .status) ?? .active
        detail = try values.decodeIfPresent(String.self, forKey: .detail) ?? ""
        resourceURL = try values.decodeIfPresent(URL.self, forKey: .resourceURL)
        textContent = try values.decodeIfPresent(String.self, forKey: .textContent)
        targetDeviceIP = try values.decodeIfPresent(String.self, forKey: .targetDeviceIP)
    }
}
