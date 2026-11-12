import Darwin
import Foundation

/// Full-tunnel proxies answer DNS with a fake address and drop TLS on the physical NIC.
/// A plain HTTP query, bound to that NIC, still reaches the ISP address.
enum HomeNetworkInterfaceQuery {
    static func lookup(interfaceName: String) -> HomeNetworkLookup? {
        guard let source = HomeNetworkRoute.ipv4(on: interfaceName) else { return nil }
        let index = if_nametoindex(interfaceName)
        guard index != 0 else { return nil }
        let addresses = resolve(index: index, source: source)
        return firstLookup(addresses, index: index, source: source)
    }

    private static func resolve(index: UInt32, source: String) -> [String] {
        let query = HomeNetworkDNS.message(for: "ifconfig.co")
        for _ in 0 ..< 2 {
            guard let packet = HomeNetworkBoundSocket.datagram(index: index, source: source, query: query) else {
                continue
            }
            let addresses = HomeNetworkDNS.addresses(in: packet)
            if !addresses.isEmpty {
                return addresses
            }
        }
        return []
    }

    private static func firstLookup(_ addresses: [String], index: UInt32, source: String) -> HomeNetworkLookup? {
        for address in addresses {
            guard let body = HomeNetworkBoundSocket.http(
                index: index, source: source, host: "ifconfig.co", address: address
            ) else { continue }
            if let found = HomeNetworkPayload.lookup(from: body) {
                return found
            }
        }
        return nil
    }
}

enum HomeNetworkDNS {
    static func message(for host: String) -> Data {
        var data = Data([0x4A, 0x52, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        for label in host.split(separator: ".") {
            let bytes = Array(label.utf8.prefix(63))
            guard !bytes.isEmpty else { continue }
            data.append(UInt8(bytes.count))
            data.append(contentsOf: bytes)
        }
        data.append(contentsOf: [0, 0, 1, 0, 1])
        return data
    }

    static func addresses(in packet: Data) -> [String] {
        guard packet.count >= 12, packet[3] & 0x0F == 0 else { return [] }
        guard var offset = questionEnd(packet) else { return [] }
        var found: [String] = []
        for _ in 0 ..< integer(packet, at: 6) {
            switch next(&offset, packet) {
            case let .address(value):
                found.append(value)
            case .skip:
                continue
            case .stop:
                return found
            }
        }
        return found
    }

    private static func questionEnd(_ packet: Data) -> Int? {
        var offset = 12
        for _ in 0 ..< integer(packet, at: 4) {
            guard skipName(&offset, packet), offset + 4 <= packet.count else { return nil }
            offset += 4
        }
        return offset
    }

    private static func next(_ offset: inout Int, _ packet: Data) -> HomeNetworkDNSStep {
        guard skipName(&offset, packet), offset + 10 <= packet.count else { return .stop }
        let kind = integer(packet, at: offset)
        let length = integer(packet, at: offset + 8)
        let start = offset + 10
        guard start + length <= packet.count else { return .stop }
        offset = start + length
        guard kind == 1, length == 4 else { return .skip }
        let text = (0 ..< 4).map { String(packet[start + $0]) }.joined(separator: ".")
        return .address(text)
    }

    private static func skipName(_ offset: inout Int, _ packet: Data) -> Bool {
        var hops = 0
        while offset < packet.count, hops < 20 {
            let mark = Int(packet[offset])
            if mark == 0 {
                offset += 1
                return true
            }
            if mark & 0xC0 == 0xC0, offset + 1 < packet.count {
                offset += 2
                return true
            }
            guard mark & 0xC0 == 0, offset + mark < packet.count else { return false }
            offset += 1 + mark
            hops += 1
        }
        return false
    }

    private static func integer(_ packet: Data, at offset: Int) -> Int {
        guard offset + 1 < packet.count else { return 0 }
        return Int(packet[offset]) << 8 | Int(packet[offset + 1])
    }
}

enum HomeNetworkDNSStep {
    case address(String)
    case skip
    case stop
}

enum HomeNetworkHTTP {
    static func request(host: String) -> Data {
        let lines = [
            "GET /json HTTP/1.0",
            "Host: \(host)",
            "Accept: application/json",
            "User-Agent: Jarvis macOS",
            "Connection: close",
            "",
            ""
        ]
        return Data(lines.joined(separator: "\r\n").utf8)
    }

    static func finished(_ data: Data) -> Bool {
        guard let split = data.range(of: Data("\r\n\r\n".utf8)) else { return false }
        let header = data[..<split.lowerBound]
        if let length = contentLength(header) {
            return data.count >= split.upperBound + length
        }
        return data[split.upperBound...].contains(UInt8(ascii: "}"))
    }

    private static func contentLength(_ header: Data.SubSequence) -> Int? {
        guard let text = String(bytes: header, encoding: .utf8)?.lowercased() else { return nil }
        for line in text.split(separator: "\r\n") where line.hasPrefix("content-length:") {
            let value = line.dropFirst("content-length:".count)
            return Int(value.trimmingCharacters(in: .whitespaces))
        }
        return nil
    }
}

private enum HomeNetworkBoundSocket {
    static func datagram(index: UInt32, source: String, query: Data) -> Data? {
        guard let socket = open(kind: SOCK_DGRAM, index: index, source: source) else { return nil }
        defer { socket.close() }
        guard socket.send(query, to: "1.1.1.1", port: 53), socket.wait(Int16(POLLIN), 4000) else { return nil }
        return socket.receive(512)
    }

    static func http(index: UInt32, source: String, host: String, address: String) -> Data? {
        guard let socket = open(kind: SOCK_STREAM, index: index, source: source) else { return nil }
        defer { socket.close() }
        guard socket.connect(address, port: 80) else { return nil }
        guard socket.sendAll(HomeNetworkHTTP.request(host: host)) else { return nil }
        return socket.readBody()
    }

    private static func open(kind: Int32, index: UInt32, source: String) -> Descriptor? {
        let descriptor = Darwin.socket(AF_INET, kind, 0)
        guard descriptor >= 0 else { return nil }
        let socket = Descriptor(descriptor)
        guard socket.prepare(index: index, source: source) else {
            socket.close()
            return nil
        }
        return socket
    }

    private struct Descriptor {
        var descriptor: Int32

        init(_ descriptor: Int32) {
            self.descriptor = descriptor
        }

        func close() {
            Darwin.close(descriptor)
        }

        func prepare(index: UInt32, source: String) -> Bool {
            guard apply(SOL_SOCKET, SO_NOSIGPIPE, 1), apply(IPPROTO_IP, IP_BOUND_IF, Int32(index)) else {
                return false
            }
            return nonblocking() && bind(source)
        }

        func connect(_ host: String, port: UInt16) -> Bool {
            let started = Self.invoke(Self.endpoint(host, port: port)) { pointer, length in
                Darwin.connect(self.descriptor, pointer, length)
            }
            if started != 0, errno != EINPROGRESS {
                return false
            }
            guard wait(Int16(POLLOUT), 6000) else { return false }
            return socketError() == 0
        }

        func send(_ data: Data, to host: String, port: UInt16) -> Bool {
            data.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return false }
                let sent = Self.invoke(Self.endpoint(host, port: port)) { pointer, length in
                    Darwin.sendto(self.descriptor, base, raw.count, 0, pointer, length)
                }
                return sent == raw.count
            }
        }

        func sendAll(_ data: Data) -> Bool {
            var pending = data
            while !pending.isEmpty {
                guard wait(Int16(POLLOUT), 6000) else { return false }
                let count = pending.withUnsafeBytes { raw in
                    guard let base = raw.baseAddress else { return -1 }
                    return Darwin.send(self.descriptor, base, raw.count, 0)
                }
                if count > 0 {
                    pending.removeFirst(count)
                    continue
                }
                if errno != EAGAIN, errno != EWOULDBLOCK {
                    return false
                }
            }
            return true
        }

        func readBody() -> Data? {
            var body = Data()
            let deadline = Date().addingTimeInterval(6)
            while body.count < 8192, Date() < deadline {
                let timeout = Int32(max(1, min(6000, deadline.timeIntervalSinceNow * 1000)))
                guard wait(Int16(POLLIN), timeout), let chunk = receive(2048) else { break }
                body.append(chunk)
                if HomeNetworkHTTP.finished(body) {
                    break
                }
            }
            return body.isEmpty ? nil : body
        }

        func receive(_ limit: Int) -> Data? {
            var buffer = [UInt8](repeating: 0, count: limit)
            let count = buffer.withUnsafeMutableBytes { raw in
                guard let base = raw.baseAddress else { return -1 }
                return Darwin.recv(self.descriptor, base, raw.count, 0)
            }
            guard count > 0 else { return nil }
            return Data(buffer.prefix(count))
        }

        func wait(_ events: Int16, _ milliseconds: Int32) -> Bool {
            var item = pollfd(fd: descriptor, events: events, revents: 0)
            guard Darwin.poll(&item, 1, milliseconds) > 0 else { return false }
            return item.revents & events != 0
        }

        private func apply(_ level: Int32, _ option: Int32, _ value: Int32) -> Bool {
            var stored = value
            let size = socklen_t(MemoryLayout<Int32>.size)
            return Darwin.setsockopt(descriptor, level, option, &stored, size) == 0
        }

        private func nonblocking() -> Bool {
            let flags = Darwin.fcntl(descriptor, F_GETFL, 0)
            guard flags >= 0 else { return false }
            return Darwin.fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) >= 0
        }

        private func bind(_ source: String) -> Bool {
            let bound = Self.invoke(Self.endpoint(source, port: 0)) { pointer, length in
                Darwin.bind(self.descriptor, pointer, length)
            }
            return bound == 0
        }

        private func socketError() -> Int32 {
            var error: Int32 = 0
            var length = socklen_t(MemoryLayout<Int32>.size)
            guard Darwin.getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &error, &length) == 0 else { return -1 }
            return error
        }

        private static func endpoint(_ host: String, port: UInt16) -> sockaddr_in {
            var value = sockaddr_in(
                sin_len: UInt8(MemoryLayout<sockaddr_in>.size),
                sin_family: sa_family_t(AF_INET),
                sin_port: port.bigEndian,
                sin_addr: in_addr(s_addr: 0),
                sin_zero: (0, 0, 0, 0, 0, 0, 0, 0)
            )
            _ = Darwin.inet_pton(AF_INET, host, &value.sin_addr)
            return value
        }

        private static func invoke<T>(
            _ endpoint: sockaddr_in,
            _ body: (UnsafePointer<sockaddr>, socklen_t) -> T
        ) -> T {
            var copy = endpoint
            let length = socklen_t(MemoryLayout<sockaddr_in>.size)
            return withUnsafePointer(to: &copy) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, length) }
            }
        }
    }
}
