import Foundation
import Network

/// A one-page HTTP server for tests that have to talk to something real.
///
/// The streaming client is the part of this app that talks to the outside world, so it is
/// tested against an actual socket rather than a stub type: connections, delays, an answer
/// that never comes, and a body that has to be read in pieces.
final class StubHTTPServer: @unchecked Sendable {
    private final class RequestBuffer: @unchecked Sendable {
        var data = Data()
    }

    struct Reply: Sendable {
        var status: Int = 200
        var contentType: String = "text/event-stream"
        var chunks: [String]
        /// Wait before the first chunk, to model a model that is slow to start.
        var initialDelay: TimeInterval = 0
        /// Wait between chunks.
        var chunkDelay: TimeInterval = 0
        /// Keep the connection open after the last chunk, to model a service that stalls.
        var holdOpen: Bool = false

        init(
            status: Int = 200,
            contentType: String = "text/event-stream",
            chunks: [String],
            initialDelay: TimeInterval = 0,
            chunkDelay: TimeInterval = 0,
            holdOpen: Bool = false
        ) {
            self.status = status
            self.contentType = contentType
            self.chunks = chunks
            self.initialDelay = initialDelay
            self.chunkDelay = chunkDelay
            self.holdOpen = holdOpen
        }
    }

    enum Failure: Error {
        case didNotStart
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "jarvis.tests.stub-server")
    private let lock = NSLock()
    private var replies: [Reply]
    private var connectionCount = 0
    private var bodies: [String] = []

    init(replies: [Reply]) throws {
        self.replies = replies
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        listener = try NWListener(using: parameters, on: .any)
    }

    var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return connectionCount
    }

    var lastRequestBody: String? {
        lock.lock()
        defer { lock.unlock() }
        return bodies.last
    }

    /// Returns once the server is listening. The port is picked by the system.
    func start() throws -> UInt16 {
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            if case .ready = state {
                ready.signal()
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 5) == .success, let port = listener.port?.rawValue else {
            listener.cancel()
            throw Failure.didNotStart
        }
        return port
    }

    func stop() {
        listener.cancel()
    }

    /// A request URL for this server, as the app would be configured with it.
    func endpointURL(port: UInt16) -> String {
        "http://127.0.0.1:\(port)/v1/chat/completions"
    }

    private func nextReply() -> Reply {
        lock.lock()
        defer { lock.unlock() }
        connectionCount += 1
        // A single reply is reused for every request, which is what a hedge needs; a longer
        // list is handed out one per request.
        if replies.count > 1 {
            return replies.removeFirst()
        }
        return replies.first ?? Reply(chunks: [])
    }

    private func accept(_ connection: NWConnection) {
        let reply = nextReply()
        connection.stateUpdateHandler = { [weak self] state in
            guard case .ready = state, let self else { return }
            self.readRequest(connection) { request in
                self.record(body: request)
                self.respond(reply, on: connection)
            }
        }
        connection.start(queue: queue)
    }

    /// Reads until the headers and, when the request announces one, the whole body arrived.
    private func readRequest(_ connection: NWConnection, then: @escaping @Sendable (String) -> Void) {
        receiveMore(connection, buffer: RequestBuffer(), then: then)
    }

    private func receiveMore(
        _ connection: NWConnection,
        buffer: RequestBuffer,
        then: @escaping @Sendable (String) -> Void
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [self] data, _, isComplete, error in
            if let data {
                buffer.data.append(data)
            }
            let text = String(decoding: buffer.data, as: UTF8.self)
            if Self.isCompleteRequest(text) || isComplete || error != nil {
                then(text)
                return
            }
            receiveMore(connection, buffer: buffer, then: then)
        }
    }

    private static func isCompleteRequest(_ text: String) -> Bool {
        guard let separator = text.range(of: "\r\n\r\n") else { return false }
        let head = text[text.startIndex ..< separator.lowerBound]
        let announced = head
            .split(separator: "\r\n")
            .first { $0.lowercased().hasPrefix("content-length:") }
            .flatMap { Int($0.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "") }
        let body = text[separator.upperBound...]
        return body.utf8.count >= (announced ?? 0)
    }

    private func record(body: String) {
        lock.lock()
        bodies.append(body)
        lock.unlock()
    }

    private func respond(_ reply: Reply, on connection: NWConnection) {
        let head = "HTTP/1.1 \(reply.status) \(Self.reason(for: reply.status))\r\n"
            + "Content-Type: \(reply.contentType)\r\n"
            + "Connection: close\r\n"
            + "\r\n"
        connection.send(content: Data(head.utf8), completion: .contentProcessed { [weak self] _ in
            self?.send(chunks: reply.chunks, index: 0, reply: reply, on: connection)
        })
    }

    private func send(chunks: [String], index: Int, reply: Reply, on connection: NWConnection) {
        guard index < chunks.count else {
            guard !reply.holdOpen else { return }
            connection.send(
                content: nil,
                contentContext: .finalMessage,
                isComplete: true,
                completion: .contentProcessed { _ in connection.cancel() }
            )
            return
        }
        let delay = index == 0 ? reply.initialDelay : reply.chunkDelay
        let write: @Sendable () -> Void = { [weak self] in
            guard let self else { return }
            connection.send(content: Data(chunks[index].utf8), completion: .contentProcessed { _ in
                self.send(chunks: chunks, index: index + 1, reply: reply, on: connection)
            })
        }
        if delay > 0 {
            queue.asyncAfter(deadline: .now() + delay, execute: write)
        } else {
            write()
        }
    }

    private static func reason(for status: Int) -> String {
        switch status {
        case 200: "OK"
        case 401: "Unauthorized"
        case 402: "Payment Required"
        case 429: "Too Many Requests"
        case 503: "Service Unavailable"
        default: "Status"
        }
    }
}

/// One server-sent event carrying a chat-completion delta.
func sseFrame(content: String) -> String {
    #"data: {"choices":[{"index":0,"delta":{"content":"\#(content)"}}]}"# + "\n\n"
}

func sseReasoningFrame(_ text: String) -> String {
    #"data: {"choices":[{"index":0,"delta":{"reasoning_content":"\#(text)"}}]}"# + "\n\n"
}

let sseDone = "data: [DONE]\n\n"
