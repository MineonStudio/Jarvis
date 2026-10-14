import Foundation
import Network

final class HTTPServer: @unchecked Sendable {
    let ip: String
    let token: String
    let sharedDirectory: URL
    let receivedDirectory: URL
    let maxBytes: Int64
    var onReady: ((UInt16) -> Void)?
    var onFailure: ((String) -> Void)?
    var onTransfer: ((Transfer) -> Void)?
    var onDevices: ((Int) -> Void)?

    fileprivate let queue = DispatchQueue(label: "com.wesley.LANShare.server")
    private var listener: NWListener?
    private var clients: [UUID: HTTPConnection] = [:]
    private var sessions: [String: Date] = [:]
    private var transferRecords: [UUID: Transfer] = [:]
    private var transferOrder: [UUID] = []
    private var stopped = false

    init(ip: String, token: String, sharedDirectory: URL, receivedDirectory: URL, maxBytes: Int64) {
        self.ip = ip; self.token = token; self.sharedDirectory = sharedDirectory
        self.receivedDirectory = receivedDirectory; self.maxBytes = maxBytes
    }

    func start() {
        queue.async { self.listen(port: 53317) }
    }

    func stop() {
        queue.async {
            self.stopped = true
            self.listener?.cancel(); self.listener = nil
            for client in self.clients.values {
                client.cancel()
            }
            self.clients.removeAll(); self.sessions.removeAll()
        }
    }

    func cancel(_ id: UUID) {
        queue.async { _ = self.cancelTransfer(id) }
    }

    fileprivate func cancelTransfer(_ id: UUID) -> Bool {
        guard let client = clients.values.first(where: { $0.transferID == id }) else { return false }
        client.cancel()
        return true
    }

    fileprivate func transferRecord(_ id: UUID) -> Transfer? {
        transferRecords[id]
    }

    private func listen(port: UInt16) {
        guard !stopped else { return }
        guard port <= 53327, let nwPort = NWEndpoint.Port(rawValue: port) else {
            onFailure?("端口 53317–53327 均不可用。")
            return
        }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(ip), port: nwPort)
        parameters.allowLocalEndpointReuse = false
        do {
            let listener = try NWListener(using: parameters)
            self.listener = listener
            listener.service = NWListener.Service(name: "局域网传输", type: "_http._tcp")
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                guard let self, self.listener === listener, !self.stopped else { return }
                switch state {
                case .ready: self.onReady?(port)
                case .failed:
                    listener?.cancel(); self.listener = nil
                    self.listen(port: port + 1)
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] nwConnection in
                guard let self, !self.stopped else { nwConnection.cancel(); return }
                let client = HTTPConnection(connection: nwConnection, server: self)
                self.clients[client.id] = client
                client.start()
            }
            listener.start(queue: queue)
        } catch { listen(port: port + 1) }
    }

    fileprivate func finished(_ id: UUID) {
        clients.removeValue(forKey: id)
    }

    fileprivate func emit(_ transfer: Transfer) {
        if transferRecords[transfer.id] == nil {
            transferOrder.insert(transfer.id, at: 0)
        }
        transferRecords[transfer.id] = transfer
        if transferOrder.count > 100 {
            for id in transferOrder.dropFirst(100) {
                transferRecords.removeValue(forKey: id)
            }
            transferOrder = Array(transferOrder.prefix(100))
        }
        onTransfer?(transfer)
    }

    fileprivate func session(for headers: [String: String]) -> String? {
        let now = Date()
        sessions = sessions.filter { now.timeIntervalSince($0.value) < 1800 }
        onDevices?(sessions.count)
        guard let cookie = headers["cookie"]?.split(separator: ";").map({ $0.trimmingCharacters(in: .whitespaces) }).first(where: { $0.hasPrefix("lan_session=") }) else { return nil }
        let key = String(cookie.dropFirst("lan_session=".count))
        guard sessions[key] != nil else { return nil }
        sessions[key] = now
        return key
    }

    func reapSessions() {
        queue.async {
            let now = Date()
            self.sessions = self.sessions.filter { now.timeIntervalSince($0.value) < 1800 }
            self.onDevices?(self.sessions.count)
        }
    }

    fileprivate func newSession() -> String {
        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        sessions[id] = Date(); onDevices?(sessions.count)
        return id
    }
}

final class HTTPConnection: @unchecked Sendable {
    let id = UUID()
    private let connection: NWConnection
    private unowned let server: HTTPServer
    private var headerBuffer = Data()
    private var requestHandled = false
    private var file: FileHandle?
    private var temporaryURL: URL?
    private var finalURL: URL?
    private var transfer: Transfer?
    private var received: Int64 = 0
    private var expected: Int64 = 0
    private var lastProgressDate = Date()
    private var lastProgressBytes: Int64 = 0
    private var timeoutGeneration = 0
    private var closed = false
    private var rejectedRemaining: Int64?
    private var rejectionResponseSent = false
    fileprivate var transferID: UUID? {
        transfer?.id
    }

    init(connection: NWConnection, server: HTTPServer) {
        self.connection = connection; self.server = server
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            if case .failed = state {
                self.fail("连接中断")
            }
            if case .cancelled = state {
                self.fail("连接已取消")
            }
        }
        connection.start(queue: server.queue)
        armTimeout()
        read()
    }

    func cancel() {
        fail("已取消")
    }

    private func armTimeout() {
        timeoutGeneration += 1
        let generation = timeoutGeneration
        server.queue.asyncAfter(deadline: .now() + 60) { [weak self] in
            guard let self, !self.closed, self.timeoutGeneration == generation else { return }
            self.fail("连接超时")
        }
    }

    private func read() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 262_144) { [weak self] data, _, complete, error in
            guard let self, !self.closed else { return }
            if let error {
                self.fail(error.localizedDescription); return
            }
            if let data, !data.isEmpty {
                self.armTimeout()
                if self.requestHandled {
                    if let remaining = self.rejectedRemaining {
                        self.rejectedRemaining = max(0, remaining - Int64(data.count))
                        if self.rejectedRemaining == 0, self.rejectionResponseSent {
                            self.close()
                        }
                    } else {
                        self.acceptBody(data)
                    }
                } else {
                    self.headerBuffer.append(data); self.parseHeaderIfReady()
                }
            }
            if complete {
                if self.rejectedRemaining != nil {
                    if self.rejectionResponseSent {
                        self.close()
                    }; return
                }
                if self.transfer?.direction == .upload, self.received != self.expected {
                    self.fail("接收字节数与 Content-Length 不符")
                } else if !self.requestHandled {
                    self.close()
                }
                return
            }
            if !self.closed, self.transfer?.direction == .upload || !self.requestHandled || (self.rejectedRemaining ?? 0) > 0 {
                self.read()
            }
        }
    }

    private func parseHeaderIfReady() {
        let separator = Data([13, 10, 13, 10])
        guard let range = headerBuffer.range(of: separator) else {
            if headerBuffer.count > 16384 {
                respond(431, "请求头过大")
            }
            return
        }
        let headData = headerBuffer.subdata(in: 0 ..< range.lowerBound)
        let body = headerBuffer.subdata(in: range.upperBound ..< headerBuffer.count)
        headerBuffer.removeAll(keepingCapacity: false)
        guard let head = String(data: headData, encoding: .utf8) else { respond(400, "无效请求"); return }
        let lines = head.components(separatedBy: "\r\n")
        let first = lines[0].split(separator: " ")
        guard first.count == 3, first[2].hasPrefix("HTTP/1."),
              let components = URLComponents(string: "http://localhost" + first[1]) else { respond(400, "无效请求"); return }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { respond(400, "无效请求头"); return }
            let name = line[..<colon].lowercased()
            if headers[name] != nil {
                respond(400, "重复请求头"); return
            }
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        requestHandled = true
        let method = String(first[0])
        let query = Dictionary((components.queryItems ?? []).compactMap { item -> (String, String)? in item.value.map { (item.name, $0) } }, uniquingKeysWith: { first, _ in first })
        if method == "GET", components.path == "/" {
            guard query["t"] == server.token else { respond(403, "链接缺少有效访问令牌"); return }
            let session = server.session(for: headers) ?? server.newSession()
            let html = WebPage.html.data(using: .utf8)!
            sendHeaders(200, extra: ["Content-Type: text/html; charset=utf-8", "Set-Cookie: lan_session=\(session); HttpOnly; SameSite=Strict; Path=/", "Cache-Control: no-store"], length: Int64(html.count)) { [weak self] in self?.send(html) }
            return
        }
        let session = server.session(for: headers)
        let downloadTokenIsValid = (method == "GET" || method == "HEAD")
            && components.path == "/api/file" && query["t"] == server.token
        guard session != nil || downloadTokenIsValid else {
            respond(401, "会话已过期，请重新扫描二维码")
            return
        }
        switch (method, components.path) {
        case ("GET", "/api/files"): listFiles()
        case ("GET", "/api/transfer"):
            guard let value = query["id"], let id = UUID(uuidString: value) else { respond(400, "无效任务"); return }
            transferStatus(id)
        case ("POST", "/api/cancel"):
            guard let value = query["id"], let id = UUID(uuidString: value) else { respond(400, "无效任务"); return }
            guard server.cancelTransfer(id) else { respond(404, "任务不存在"); return }
            respond(200, "已取消")
        case ("GET", "/api/file"), ("HEAD", "/api/file"):
            guard let name = query["name"] else { respond(400, "缺少文件名"); return }
            download(
                name: name,
                range: headers["range"],
                headOnly: method == "HEAD",
                requestedID: query["id"].flatMap(UUID.init(uuidString:))
            )
        case ("PUT", "/api/upload"):
            guard let name = query["name"] else { respond(400, "缺少文件名"); return }
            guard headers["transfer-encoding"] == nil, let lengthString = headers["content-length"],
                  let length = Int64(lengthString), length >= 0 else { respond(411, "需要 Content-Length"); return }
            beginUpload(name: name, length: length, initial: body)
        default: respond(404, "找不到请求的内容")
        }
    }

    private func validName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && name == (name as NSString).lastPathComponent && !name.contains("\\") && !name.hasPrefix(".") && name.unicodeScalars.allSatisfy { $0.value >= 32 && $0.value != 127 }
    }

    private func listFiles() {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: server.sharedDirectory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]
        )) ?? []
        let files = urls.compactMap { url -> (name: String, size: Int, modified: Date)? in
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true, values.isSymbolicLink != true else { return nil }
            return (url.lastPathComponent, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.modified > $1.modified }
            .prefix(10)
            .map { ["name": $0.name, "size": $0.size] as [String: Any] }
        let data = (try? JSONSerialization.data(withJSONObject: files)) ?? Data("[]".utf8)
        sendHeaders(200, extra: ["Content-Type: application/json; charset=utf-8", "Cache-Control: no-store"], length: Int64(data.count)) { [weak self] in self?.send(data) }
    }

    private func transferStatus(_ id: UUID) {
        guard let task = server.transferRecord(id) else { respond(404, "任务不存在"); return }
        let data = (try? JSONSerialization.data(withJSONObject: [
            "status": task.status.rawValue,
            "done": task.done,
            "total": task.total
        ])) ?? Data("{}".utf8)
        sendHeaders(200, extra: ["Content-Type: application/json; charset=utf-8", "Cache-Control: no-store"], length: Int64(data.count)) { [weak self] in self?.send(data) }
    }

    private func beginUpload(name: String, length: Int64, initial: Data) {
        guard validName(name) else { rejectUpload(400, "无效文件名", length: length, initial: initial.count); return }
        guard length <= server.maxBytes else { rejectUpload(413, "文件超过单文件上限", length: length, initial: initial.count); return }
        let free = ((try? FileManager.default.attributesOfFileSystem(forPath: server.receivedDirectory.path))?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        guard free > length + 16_777_216 else { rejectUpload(507, "接收目录磁盘空间不足", length: length, initial: initial.count); return }
        let temp = server.receivedDirectory.appendingPathComponent(".lanshare-\(id.uuidString).part")
        guard FileManager.default.createFile(atPath: temp.path, contents: nil), let handle = try? FileHandle(forWritingTo: temp) else { rejectUpload(500, "无法创建接收文件", length: length, initial: initial.count); return }
        file = handle; temporaryURL = temp; finalURL = server.receivedDirectory.appendingPathComponent(name)
        expected = length
        transfer = Transfer(id: id, name: name, direction: .upload, total: length)
        server.emit(transfer!)
        if !initial.isEmpty {
            acceptBody(initial)
        } else if length == 0 {
            finishUpload()
        }
    }

    private func uniqueDestination(for name: String) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = server.receivedDirectory.appendingPathComponent(name)
        var index = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            let suffix = "\(base)(\(index))" + (ext.isEmpty ? "" : ".\(ext)")
            candidate = server.receivedDirectory.appendingPathComponent(suffix)
            index += 1
        }
        return candidate
    }

    private func acceptBody(_ data: Data) {
        guard transfer?.direction == .upload, !closed else { return }
        guard received + Int64(data.count) <= expected else { fail("接收数据超过 Content-Length"); return }
        do { try file?.write(contentsOf: data) }
        catch { fail("写入失败：\(error.localizedDescription)"); return }
        received += Int64(data.count)
        updateProgress(received)
        if received == expected {
            finishUpload()
        }
    }

    private func finishUpload() {
        guard let temp = temporaryURL, let final = finalURL else { fail("接收文件不可用"); return }
        do {
            try file?.close(); file = nil
            let destination = uniqueDestination(for: final.lastPathComponent)
            try FileManager.default.moveItem(at: temp, to: destination)
            temporaryURL = nil
            var completed = transfer!; completed.done = expected; completed.status = .completed
            completed.detail = "已保存到 \(destination.path)"; server.emit(completed)
            let json = try JSONSerialization.data(withJSONObject: ["name": destination.lastPathComponent])
            sendHeaders(201, extra: ["Content-Type: application/json; charset=utf-8"], length: Int64(json.count)) { [weak self] in self?.send(json) }
        } catch { fail("保存失败：\(error.localizedDescription)") }
    }

    private func download(name: String, range: String?, headOnly: Bool, requestedID: UUID?) {
        guard validName(name) else { respond(400, "无效文件名"); return }
        let url = server.sharedDirectory.appendingPathComponent(name)
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]), values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, let handle = try? FileHandle(forReadingFrom: url) else { respond(404, "文件不存在"); return }
        let total = Int64(size)
        var start: Int64 = 0, end: Int64 = max(0, total - 1), status = 200
        if let range {
            guard range.hasPrefix("bytes="), !range.contains(",") else { try? handle.close(); respond(416, "无效 Range"); return }
            let parts = range.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
            guard parts.count == 2 else { try? handle.close(); respond(416, "无效 Range"); return }
            if parts[0].isEmpty, let suffix = Int64(parts[1]), suffix > 0 {
                start = max(0, total - suffix)
            } else if let value = Int64(parts[0]), value >= 0 {
                start = value
            } else {
                try? handle.close(); respond(416, "无效 Range"); return
            }
            if !parts[1].isEmpty, !parts[0].isEmpty {
                guard let value = Int64(parts[1]), value >= start else { try? handle.close(); respond(416, "无效 Range"); return }
                end = min(value, total - 1)
            }
            guard start < total else { try? handle.close(); sendHeaders(416, extra: ["Content-Range: bytes */\(total)"], length: 0) { [weak self] in self?.close() }; return }
            status = 206
        }
        let length = total == 0 ? 0 : end - start + 1
        let rfc5987Safe = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#$&+-.^_|~")
        let encoded = name.addingPercentEncoding(withAllowedCharacters: rfc5987Safe) ?? "file"
        var extra = [
            "Content-Type: application/octet-stream",
            "Content-Disposition: attachment; filename=\"download\"; filename*=UTF-8''\(encoded)",
            "Accept-Ranges: bytes",
            "Cache-Control: no-store"
        ]
        if status == 206 {
            extra.append("Content-Range: bytes \(start)-\(end)/\(total)")
        }
        if headOnly {
            try? handle.close(); sendHeaders(status, extra: extra, length: length) { [weak self] in self?.finishOutput() }; return
        }
        file = handle
        transfer = Transfer(id: requestedID ?? id, name: name, direction: .download, total: length)
        server.emit(transfer!)
        do { try handle.seek(toOffset: UInt64(start)) }
        catch { fail("读取失败"); return }
        sendHeaders(status, extra: extra, length: length) { [weak self] in self?.sendFile(remaining: length) }
    }

    private func sendFile(remaining: Int64) {
        guard !closed else { return }
        if remaining == 0 {
            guard var completed = transfer else { return }
            completed.done = completed.total
            completed.status = .completed
            transfer = completed
            server.emit(completed)
            finishOutput()
            return
        }
        do {
            let data = try file!.read(upToCount: Int(min(262_144, remaining))) ?? Data()
            guard !data.isEmpty else { fail("源文件读取提前结束"); return }
            connection.send(content: data, completion: .contentProcessed { [weak self] error in
                guard let self else { return }
                if let error {
                    self.fail(error.localizedDescription); return
                }
                self.received += Int64(data.count)
                self.updateProgress(self.received)
                self.armTimeout()
                self.sendFile(remaining: remaining - Int64(data.count))
            })
        } catch { fail("读取失败：\(error.localizedDescription)") }
    }

    private func updateProgress(_ count: Int64) {
        guard var task = transfer else { return }
        task.done = count
        let elapsed = Date().timeIntervalSince(lastProgressDate)
        if elapsed >= 0.25 || count == task.total {
            task.bytesPerSecond = Double(count - lastProgressBytes) / max(0.001, elapsed)
            lastProgressDate = Date(); lastProgressBytes = count
            transfer = task; server.emit(task)
        }
    }

    private func rejectUpload(_ status: Int, _ message: String, length: Int64, initial: Int) {
        rejectedRemaining = max(0, length - Int64(initial))
        let data = Data(message.utf8)
        sendHeaders(status, extra: ["Content-Type: text/plain; charset=utf-8"], length: Int64(data.count)) { [weak self] in
            guard let self else { return }
            self.connection.send(content: data, completion: .contentProcessed { [weak self] error in
                guard let self else { return }
                if let error {
                    self.fail(error.localizedDescription); return
                }
                self.rejectionResponseSent = true
                if self.rejectedRemaining == 0 {
                    self.close()
                }
            })
        }
    }

    private func respond(_ status: Int, _ message: String) {
        let data = Data(message.utf8)
        sendHeaders(status, extra: ["Content-Type: text/plain; charset=utf-8"], length: Int64(data.count)) { [weak self] in self?.send(data) }
    }

    private func sendHeaders(_ status: Int, extra: [String], length: Int64, then action: @escaping @Sendable () -> Void) {
        let reason: [Int: String] = [200: "OK", 201: "Created", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found", 411: "Length Required", 413: "Payload Too Large", 416: "Range Not Satisfiable", 431: "Request Header Fields Too Large", 500: "Internal Server Error", 507: "Insufficient Storage"]
        let lines = ["HTTP/1.1 \(status) \(reason[status] ?? "Error")", "Content-Length: \(length)", "Connection: close", "X-Content-Type-Options: nosniff"] + extra
        connection.send(content: Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8), completion: .contentProcessed { [weak self] error in
            if let error {
                self?.fail(error.localizedDescription)
            } else {
                action()
            }
        })
    }

    private func send(_ data: Data) {
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error {
                self?.fail(error.localizedDescription)
            } else {
                self?.finishOutput()
            }
        })
    }

    private func finishOutput() {
        connection.send(
            content: nil,
            contentContext: .finalMessage,
            isComplete: true,
            completion: .contentProcessed { [weak self] error in
                guard let self else { return }
                if let error {
                    self.fail(error.localizedDescription)
                    return
                }
                self.server.queue.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.close() }
            }
        )
    }

    private func fail(_ reason: String) {
        guard !closed else { return }
        if var task = transfer, task.status == .active {
            task.status = reason == "已取消" || reason == "连接已取消" ? .cancelled : .failed
            task.detail = reason; server.emit(task)
        }
        close()
    }

    private func close() {
        guard !closed else { return }
        closed = true; timeoutGeneration += 1
        try? file?.close(); file = nil
        if let temporaryURL {
            try? FileManager.default.removeItem(at: temporaryURL)
        }
        connection.cancel(); server.finished(id)
    }
}
