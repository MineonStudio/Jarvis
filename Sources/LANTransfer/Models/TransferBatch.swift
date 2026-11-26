import Foundation

enum TransferBatchLimit {
    static let maximumCount = 50
}

struct DownloadBatch: Sendable, Equatable {
    var id: UUID
    var index: Int
    var count: Int
}

enum DownloadOfferResult: Equatable {
    case started(UUID)
    case busy
    case unavailable
}

struct OutboundFileQueue: Equatable {
    let deviceIP: String
    let batchID: UUID
    let total: Int
    let fileNames: [String]
    var pendingNames: [String]
    var nextIndex: Int
    var activeTransferID: UUID?

    init(deviceIP: String, names: [String]) {
        self.deviceIP = deviceIP
        batchID = UUID()
        total = names.count
        fileNames = names
        pendingNames = names
        nextIndex = 1
        activeTransferID = nil
    }

    mutating func takeNext() -> (name: String, index: Int)? {
        guard !pendingNames.isEmpty, nextIndex <= total else { return nil }
        let name = pendingNames.removeFirst()
        let index = nextIndex
        nextIndex += 1
        return (name, index)
    }
}
