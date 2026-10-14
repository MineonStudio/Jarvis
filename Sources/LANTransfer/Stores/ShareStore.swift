import AppKit
import Combine
import Foundation
import Security

@MainActor public final class ShareStore: ObservableObject {
    public static let shared = ShareStore()
    nonisolated static let maxFileBytes: Int64 = 2 * 1_073_741_824

    @Published public private(set) var running = false
    @Published public private(set) var address = ""
    @Published var errorMessage = ""
    @Published public private(set) var transfers: [Transfer] = []
    @Published public private(set) var incomingOffer: Transfer?
    @Published var pairedDevices = 0
    @Published var startedAt: Date?
    @Published private(set) var sharedDirectory: URL
    @Published private(set) var receivedDirectory: URL
    @Published var isImporting = false
    @Published var importMessage: String?
    @Published var importHasErrors = false
    public var onTransferEvent: ((Transfer) -> Void)?

    private var server: HTTPServer?
    private var addressTimer: Timer?
    private var lastIP: String?
    private let importer = SharedFileImporter()
    private let historyURL: URL
    public var canStartTask: Bool {
        running && !isImporting && !transfers.contains(where: \.isInProgress)
    }

    init(rootDirectory: URL? = nil, fileManager: FileManager = .default) {
        let root = rootDirectory ?? LANTransferDirectories.root(fileManager: fileManager)
        historyURL = root.appendingPathComponent("transfers.json")
        sharedDirectory = root.appendingPathComponent("共享", isDirectory: true)
        receivedDirectory = root.appendingPathComponent("接收", isDirectory: true)
        do {
            try fileManager.createDirectory(at: sharedDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: receivedDirectory, withIntermediateDirectories: true)
        } catch {
            errorMessage = "无法建立局域网传输目录：\(error.localizedDescription)"
        }
        if let data = try? Data(contentsOf: historyURL),
           var saved = try? JSONDecoder().decode([Transfer].self, from: data) {
            for index in saved.indices where saved[index].isInProgress {
                saved[index].status = .failed
                saved[index].detail = "传输已中断"
            }
            transfers = saved
        }
        adoptExistingFiles(fileManager: fileManager)
    }

    public func start() {
        guard !running, server == nil else { return }
        guard FileManager.default.fileExists(atPath: sharedDirectory.path),
              FileManager.default.fileExists(atPath: receivedDirectory.path)
        else { errorMessage = "局域网传输目录不可用。"; return }
        guard let ip = NetworkAddress.localIPv4() else { errorMessage = "找不到局域网 IPv4 地址。请先连接 Wi-Fi 或手机热点。"; return }
        errorMessage = ""
        var tokenBytes = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, tokenBytes.count, &tokenBytes) == errSecSuccess else { errorMessage = "无法生成访问令牌。"; return }
        let token = tokenBytes.map { String(format: "%02x", $0) }.joined()
        let server = HTTPServer(ip: ip, token: token, sharedDirectory: sharedDirectory, receivedDirectory: receivedDirectory, maxBytes: Self.maxFileBytes)
        server.onReady = { [weak self, weak server] port in Task { @MainActor in
            guard let self, let server, self.server === server else { return }
            self.running = true
            self.lastIP = ip
            self.startedAt = Date()
            self.address = "http://\(ip):\(port)/?t=\(token)"
            self.addressTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in Task { @MainActor in self?.checkAddress() } }
        }}
        server.onFailure = { [weak self, weak server] message in Task { @MainActor in
            guard let self, let server, self.server === server else { return }; self.errorMessage = message; self.stop()
        }}
        server.onTransfer = { [weak self] transfer in Task { @MainActor in self?.upsert(transfer) } }
        server.onDevices = { [weak self] count in Task { @MainActor in self?.pairedDevices = count } }
        self.server = server
        server.start()
    }

    public func stop() {
        addressTimer?.invalidate(); addressTimer = nil
        server?.stop(); server = nil
        running = false; address = ""; startedAt = nil; pairedDevices = 0; lastIP = nil
        incomingOffer = nil
    }

    private func checkAddress() {
        server?.reapSessions()
        guard running, let ip = NetworkAddress.localIPv4(), ip != lastIP else { return }
        stop(); start()
    }

    public func cancel(_ id: UUID) {
        if incomingOffer?.id == id { incomingOffer = nil }
        server?.cancel(id)
    }

    public func acceptIncoming(_ id: UUID) {
        guard incomingOffer?.id == id else { return }
        incomingOffer = nil
        server?.acceptUpload(id)
    }

    public func openResource(_ transfer: Transfer) {
        guard let url = transfer.resourceURL,
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true, values.isSymbolicLink != true else {
            importMessage = "文件已移除"
            importHasErrors = true
            return
        }
        NSWorkspace.shared.open(url)
    }

    public func resend(_ transfer: Transfer) {
        guard canStartTask, let url = transfer.resourceURL,
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true, values.isSymbolicLink != true else {
            importMessage = "文件已移除或当前无法发送"
            importHasErrors = true
            return
        }
        importMessage = nil
        importHasErrors = false
        if url.deletingLastPathComponent().resolvingSymlinksInPath() == sharedDirectory.resolvingSymlinksInPath() {
            guard let server else { return }
            isImporting = true
            Task {
                let offered = await server.offerDownload(name: url.lastPathComponent)
                isImporting = false
                if !offered {
                    importMessage = "重新发送失败"
                    importHasErrors = true
                }
            }
        } else {
            importSharedFiles([url])
        }
    }

    func chooseSharedFiles() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "发送"
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor in self?.importSharedFiles(panel.urls) }
        }
    }

    func importSharedFiles(_ urls: [URL]) {
        guard canStartTask, let url = urls.first else { return }
        isImporting = true
        importMessage = nil
        importHasErrors = false
        Task {
            let result = await importer.importFiles([url], into: sharedDirectory, maxBytes: Self.maxFileBytes)
            isImporting = false
            importHasErrors = !result.failedNames.isEmpty
            if let name = result.importedNames.first {
                guard let server, running, await server.offerDownload(name: name) else {
                    try? FileManager.default.removeItem(at: sharedDirectory.appendingPathComponent(name))
                    importMessage = "当前有传输任务，请稍后发送"
                    importHasErrors = true
                    return
                }
                importMessage = nil
            } else {
                importMessage = result.failedNames.joined(separator: "\n")
            }
        }
    }

    private func upsert(_ transfer: Transfer) {
        let previousStatus = transfers.first(where: { $0.id == transfer.id })?.status
        if let index = transfers.firstIndex(where: { $0.id == transfer.id }) {
            transfers[index] = transfer
        } else {
            transfers.insert(transfer, at: 0)
        }
        if previousStatus != transfer.status {
            onTransferEvent?(transfer)
            persistHistory()
        }
        if transfer.direction == .upload, transfer.status == .pending {
            incomingOffer = transfer
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first(where: { $0.canBecomeKey })?.makeKeyAndOrderFront(nil)
        } else if incomingOffer?.id == transfer.id {
            incomingOffer = nil
        }
    }

    private func persistHistory() {
        guard let data = try? JSONEncoder().encode(transfers) else { return }
        try? data.write(to: historyURL, options: .atomic)
    }

    private func adoptExistingFiles(fileManager: FileManager) {
        let knownPaths = Set(transfers.compactMap { $0.resourceURL?.resolvingSymlinksInPath().path })
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        var found: [(Transfer, Date)] = []
        for (directory, direction) in [(sharedDirectory, TransferDirection.download), (receivedDirectory, .upload)] {
            let urls = (try? fileManager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]
            )) ?? []
            for url in urls where !knownPaths.contains(url.resolvingSymlinksInPath().path) {
                guard let values = try? url.resourceValues(forKeys: keys),
                      values.isRegularFile == true, values.isSymbolicLink != true,
                      let size = values.fileSize else { continue }
                var task = Transfer(id: UUID(), name: url.lastPathComponent, direction: direction, total: Int64(size))
                task.done = Int64(size)
                task.status = .completed
                task.detail = "历史文件"
                task.resourceURL = url
                found.append((task, values.contentModificationDate ?? .distantPast))
            }
        }
        guard !found.isEmpty else { return }
        transfers.insert(contentsOf: found.sorted { $0.1 > $1.1 }.map(\.0), at: 0)
        persistHistory()
    }
}
