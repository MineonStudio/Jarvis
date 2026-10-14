import Foundation

public enum TransferDirection: String { case upload = "接收", download = "发送" }
public enum TransferStatus: String { case active = "传输中", completed = "已完成", failed = "失败", cancelled = "已取消" }

public struct Transfer: Identifiable {
    public let id: UUID
    public let name: String
    public let direction: TransferDirection
    public let total: Int64
    public var done: Int64 = 0
    public var bytesPerSecond: Double = 0
    public var status: TransferStatus = .active
    public var detail: String = ""
    public var fraction: Double {
        total > 0 ? min(1, Double(done) / Double(total)) : 0
    }
}
