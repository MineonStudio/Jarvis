import Foundation

public enum TransferDirection: String, Codable { case upload = "接收", download = "发送" }
public enum TransferStatus: String, Codable {
    case pending = "等待接收", accepted = "等待发送", active = "传输中"
    case completed = "已完成", failed = "失败", cancelled = "已取消"
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
    public var isInProgress: Bool {
        status == .pending || status == .accepted || status == .active
    }

    public var fraction: Double {
        total > 0 ? min(1, Double(done) / Double(total)) : 0
    }
}
