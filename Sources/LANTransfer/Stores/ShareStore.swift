import AppKit
import Combine
import Foundation

@MainActor public final class ShareStore: ObservableObject {
    public static let shared = ShareStore()
    nonisolated static let maxFileBytes: Int64 = 2 * 1_073_741_824

    @Published public private(set) var running = false
    @Published public private(set) var address = ""
    @Published var errorMessage = ""
    @Published public private(set) var transfers: [Transfer] = []
    @Published public private(set) var incomingOffer: Transfer?
    @Published var pairedDevices = 0
    @Published public private(set) var connectedDevices: [LANConnectedDevice] = []
    @Published public var selectedDeviceIP: String?
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
    private var deletedIDs: Set<UUID> = []
    private var outboundQueue: OutboundFileQueue?
    private var isOfferingOutbound = false
    private let importer = SharedFileImporter()
    private let historyURL: URL
    public var canStartTask: Bool {
        running && selectedDeviceIP != nil && !isImporting && !isSendingBatch
            && !transfers.contains(where: \.isInProgress)
    }

    var isSendingBatch: Bool {
        outboundQueue != nil || isOfferingOutbound
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
            errorMessage = "无法建立文件传输目录：\(error.localizedDescription)"
        }
        if let data = try? Data(contentsOf: historyURL),
           var saved = try? JSONDecoder().decode([Transfer].self, from: data)
        {
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
        else { errorMessage = "文件传输目录不可用。"; return }
        guard let ip = NetworkAddress.localIPv4() else { errorMessage = "找不到局域网 IPv4 地址。请先连接 Wi-Fi 或手机热点。"; return }
        errorMessage = ""
        guard let token = FileTransferAccessToken.generate() else { errorMessage = "无法生成访问令牌。"; return }
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
        server.onDevices = { [weak self, weak server] devices in Task { @MainActor in
            guard let self, let server, self.server === server else { return }
            self.connectedDevices = devices
            self.pairedDevices = devices.count
            if !devices.contains(where: { $0.id == self.selectedDeviceIP }) {
                self.selectedDeviceIP = devices.first?.id
            }
        }}
        self.server = server
        server.start()
    }

    public func stop() {
        discardOutboundRemainder()
        addressTimer?.invalidate(); addressTimer = nil
        server?.stop(); server = nil
        running = false; address = ""; startedAt = nil; pairedDevices = 0; lastIP = nil
        connectedDevices = []; selectedDeviceIP = nil
        incomingOffer = nil
    }

    private func checkAddress() {
        server?.reapSessions()
        guard running, let ip = NetworkAddress.localIPv4(), ip != lastIP else { return }
        stop(); start()
    }

    public func cancel(_ id: UUID) {
        if incomingOffer?.id == id {
            incomingOffer = nil
        }
        server?.cancel(id)
    }

    public func delete(_ id: UUID) {
        guard let index = transfers.firstIndex(where: { $0.id == id }) else { return }
        let transfer = transfers[index]
        if let url = transfer.resourceURL, FileManager.default.fileExists(atPath: url.path), isManagedFile(url) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                importMessage = "无法删除源文件：\(error.localizedDescription)"
                importHasErrors = true
                return
            }
        }
        if incomingOffer?.id == id {
            incomingOffer = nil
        }
        if transfer.isInProgress {
            server?.cancel(id)
        }
        removeRecord(id)
    }

    public func acceptIncoming(_ id: UUID) {
        guard incomingOffer?.id == id else { return }
        incomingOffer = nil
        if let transfer = transfers.first(where: { $0.id == id }), transfer.isText {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(transfer.textContent ?? "", forType: .string)
            server?.finishText(id, direction: .upload)
            return
        }
        server?.acceptUpload(id)
    }

    public func openResource(_ transfer: Transfer) {
        guard let url = transfer.resourceURL,
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true, values.isSymbolicLink != true
        else {
            importMessage = "文件已移除"
            importHasErrors = true
            return
        }
        NSWorkspace.shared.open(url)
    }

    @discardableResult
    public func copyResource(_ transfer: Transfer, pasteboard: NSPasteboard? = nil) -> Bool {
        let destination = pasteboard ?? .general
        if let text = transfer.textContent {
            destination.clearContents()
            return destination.setString(text, forType: .string)
        }
        guard let url = transfer.resourceURL,
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true, values.isSymbolicLink != true
        else {
            return false
        }
        destination.clearContents()
        return destination.writeObjects([url as NSURL])
    }

    public func sendText(_ text: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canStartTask, let targetDeviceIP = selectedDeviceIP, !value.isEmpty else { return }
        guard value.utf8.count <= 200_000 else {
            importMessage = "文本不能超过 20 万字节"
            importHasErrors = true
            return
        }
        guard let server else { return }
        importMessage = nil
        importHasErrors = false
        isImporting = true
        Task {
            let offered = await server.offerDownloadText(value, to: targetDeviceIP)
            isImporting = false
            if !offered {
                importMessage = "当前有传输任务，请稍后发送"
                importHasErrors = true
            }
        }
    }

    public func resend(_ transfer: Transfer) {
        guard let targetDeviceIP = selectedDeviceIP else { return }
        if let text = transfer.textContent {
            sendText(text)
            return
        }
        guard canStartTask, let url = transfer.resourceURL,
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true, values.isSymbolicLink != true
        else {
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
                let offered = await server.offerDownload(name: url.lastPathComponent, to: targetDeviceIP)
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
        let targetDeviceIP = selectedDeviceIP
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.prompt = "发送"
        panel.message = "可同时选择最多 \(TransferBatchLimit.maximumCount) 个文件"
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor in self?.importSharedFiles(panel.urls, to: targetDeviceIP) }
        }
    }

    func importSharedFiles(_ urls: [URL], to selectedTargetIP: String? = nil) {
        guard canStartTask, let targetDeviceIP = selectedTargetIP ?? selectedDeviceIP, !urls.isEmpty else { return }
        let selected = Array(urls.prefix(TransferBatchLimit.maximumCount))
        let skippedCount = urls.count - selected.count
        isImporting = true
        importMessage = nil
        importHasErrors = false
        Task {
            let result = await importer.importFiles(selected, into: sharedDirectory, maxBytes: Self.maxFileBytes)
            isImporting = false
            var failures = result.failedNames
            if skippedCount > 0 {
                failures.append("一次最多发送 \(TransferBatchLimit.maximumCount) 个文件")
            }
            importHasErrors = !failures.isEmpty
            importMessage = failures.isEmpty ? nil : failures.joined(separator: "\n")
            guard !result.importedNames.isEmpty else { return }
            if result.importedNames.count == 1 {
                await offerSingleDownload(named: result.importedNames[0], to: targetDeviceIP)
            } else {
                outboundQueue = OutboundFileQueue(deviceIP: targetDeviceIP, names: result.importedNames)
                await offerNextOutboundFile()
            }
        }
    }

    private func offerSingleDownload(named name: String, to targetDeviceIP: String) async {
        guard let server, running, await server.offerDownload(name: name, to: targetDeviceIP) else {
            try? FileManager.default.removeItem(at: sharedDirectory.appendingPathComponent(name))
            importMessage = "当前有传输任务，请稍后发送"
            importHasErrors = true
            return
        }
    }

    private func offerNextOutboundFile() async {
        guard !isOfferingOutbound, outboundQueue != nil, running, server != nil else { return }
        isOfferingOutbound = true
        defer { isOfferingOutbound = false }
        while running, let server, var queue = outboundQueue {
            guard let next = queue.takeNext() else {
                outboundQueue = nil
                return
            }
            let batchID = queue.batchID
            outboundQueue = queue
            let batch = DownloadBatch(id: batchID, index: next.index, count: queue.total)
            let result = await server.prepareDownloadOffer(
                name: next.name,
                to: queue.deviceIP,
                batch: batch,
                names: queue.fileNames
            )
            guard outboundQueue?.batchID == batchID else {
                if case let .started(id) = result {
                    server.cancel(id)
                }
                return
            }
            switch result {
            case let .started(id):
                outboundQueue?.activeTransferID = id
                return
            case .busy:
                restoreOutboundFile(next.name, at: next.index, batchID: batchID)
                try? await Task.sleep(for: .milliseconds(400))
            case .unavailable:
                try? FileManager.default.removeItem(at: sharedDirectory.appendingPathComponent(next.name))
                discardOutboundRemainder()
                importMessage = "当前有传输任务，请稍后发送"
                importHasErrors = true
                return
            }
        }
    }

    private func restoreOutboundFile(_ name: String, at index: Int, batchID: UUID) {
        guard var queue = outboundQueue, queue.batchID == batchID else { return }
        queue.pendingNames.insert(name, at: 0)
        queue.nextIndex = index
        outboundQueue = queue
    }

    private func continueOutboundQueue(after transfer: Transfer) {
        guard var queue = outboundQueue, transfer.id == queue.activeTransferID, !transfer.isInProgress else { return }
        queue.activeTransferID = nil
        outboundQueue = queue
        guard transfer.status == .completed else {
            let remainder = queue.pendingNames
            discardOutboundRemainder()
            if !remainder.isEmpty {
                importMessage = "剩余文件未发送"
                importHasErrors = true
            }
            return
        }
        Task { await offerNextOutboundFile() }
    }

    private func discardOutboundRemainder() {
        guard let queue = outboundQueue else { return }
        for name in queue.pendingNames {
            try? FileManager.default.removeItem(at: sharedDirectory.appendingPathComponent(name))
        }
        outboundQueue = nil
    }

    private func upsert(_ transfer: Transfer) {
        guard !deletedIDs.contains(transfer.id) else { return }
        let previousStatus = transfers.first(where: { $0.id == transfer.id })?.status
        if let index = transfers.firstIndex(where: { $0.id == transfer.id }) {
            transfers[index] = transfer
        } else {
            transfers.insert(transfer, at: 0)
        }
        if previousStatus != transfer.status {
            onTransferEvent?(transfer)
            persistHistory()
            if transfer.direction == .download {
                continueOutboundQueue(after: transfer)
            }
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

    private func removeRecord(_ id: UUID) {
        deletedIDs.insert(id)
        transfers.removeAll { $0.id == id }
        persistHistory()
    }

    private func isManagedFile(_ url: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        return isInside(path, directory: sharedDirectory) || isInside(path, directory: receivedDirectory)
    }

    private func isInside(_ path: String, directory: URL) -> Bool {
        let root = directory.resolvingSymlinksInPath().standardizedFileURL.path
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return path.hasPrefix(prefix)
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
