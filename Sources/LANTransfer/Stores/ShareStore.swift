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
    @Published var pairedDevices = 0
    @Published var startedAt: Date?
    @Published private(set) var sharedDirectory: URL
    @Published private(set) var receivedDirectory: URL
    @Published var isImporting = false
    @Published var importMessage: String?
    @Published var importHasErrors = false

    private var server: HTTPServer?
    private var addressTimer: Timer?
    private var lastIP: String?
    private let importer = SharedFileImporter()

    init(rootDirectory: URL? = nil, fileManager: FileManager = .default) {
        let root = rootDirectory ?? LANTransferDirectories.root(fileManager: fileManager)
        sharedDirectory = root.appendingPathComponent("共享", isDirectory: true)
        receivedDirectory = root.appendingPathComponent("接收", isDirectory: true)
        do {
            try fileManager.createDirectory(at: sharedDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: receivedDirectory, withIntermediateDirectories: true)
        } catch {
            errorMessage = "无法建立局域网传输目录：\(error.localizedDescription)"
        }
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
    }

    private func checkAddress() {
        server?.reapSessions()
        guard running, let ip = NetworkAddress.localIPv4(), ip != lastIP else { return }
        stop(); start()
    }

    public func cancel(_ id: UUID) {
        server?.cancel(id)
    }

    func chooseSharedFiles() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.prompt = "上传到共享目录"
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor in self?.importSharedFiles(panel.urls) }
        }
    }

    func importSharedFiles(_ urls: [URL]) {
        guard !isImporting, !urls.isEmpty else { return }
        isImporting = true
        importMessage = nil
        importHasErrors = false
        Task {
            let result = await importer.importFiles(urls, into: sharedDirectory, maxBytes: Self.maxFileBytes)
            isImporting = false
            importHasErrors = !result.failedNames.isEmpty
            if result.failedNames.isEmpty {
                importMessage = "已添加 \(result.importedNames.count) 个文件到共享目录。"
            } else if result.importedNames.isEmpty {
                importMessage = result.failedNames.joined(separator: "\n")
            } else {
                importMessage = "已添加 \(result.importedNames.count) 个文件；\(result.failedNames.count) 个文件失败：\(result.failedNames.joined(separator: "；"))"
            }
        }
    }

    private func upsert(_ transfer: Transfer) {
        if let index = transfers.firstIndex(where: { $0.id == transfer.id }) {
            transfers[index] = transfer
        } else {
            transfers.insert(transfer, at: 0)
        }
        if transfers.count > 100 {
            transfers.removeLast(transfers.count - 100)
        }
    }
}
