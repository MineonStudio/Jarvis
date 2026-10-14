import Darwin
import Foundation

enum NetworkAddress {
    static func localIPv4() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let head else { return nil }
        defer { freeifaddrs(head) }
        var candidates: [(Int, String)] = []
        for item in sequence(first: head, next: { $0.pointee.ifa_next }) {
            let entry = item.pointee
            guard let addr = entry.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  (entry.ifa_flags & UInt32(IFF_UP)) != 0,
                  (entry.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 else { continue }
            let name = String(cString: entry.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("bridge") || name.hasPrefix("ap") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: host)
            let octets = ip.split(separator: ".").compactMap { UInt8($0) }
            guard octets.count == 4 else { continue }
            let lan = octets[0] == 10 || (octets[0] == 172 && (16 ... 31).contains(octets[1])) ||
                (octets[0] == 192 && octets[1] == 168) ||
                (octets[0] == 100 && (64 ... 127).contains(octets[1]))
            guard lan else { continue }
            let priority = name == "en0" ? 0 : name.hasPrefix("en") ? 1 : name.hasPrefix("bridge") ? 2 : 3
            candidates.append((priority, ip))
        }
        return candidates.sorted { $0.0 < $1.0 }.first?.1
    }
}
