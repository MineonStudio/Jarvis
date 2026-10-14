import Foundation

public enum TransferDirection: String, Codable { case upload = "接收", download = "发送" }
public enum TransferStatus: String, Codable {
    case pending = "等待接收", accepted = "等待发送", active = "传输中"
    case completed = "已完成", failed = "失败", cancelled = "已取消"
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
