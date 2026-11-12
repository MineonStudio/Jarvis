import Darwin
import Foundation
import SystemConfiguration

struct HomeNetworkCensus: Equatable, Sendable {
    var ethernet: [String]
    var vpn: [String]
}

enum HomeNetworkRoute {
    static func primaryInterface() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "jarvis.home.network" as CFString, nil, nil) else {
            return nil
        }
        if let name = primary(store, key: "State:/Network/Global/IPv4") {
            return name
        }
        return primary(store, key: "State:/Network/Global/IPv6")
    }

    static func ipv4(on name: String) -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let head else { return nil }
        defer { freeifaddrs(head) }
        for item in sequence(first: head, next: { $0.pointee.ifa_next }) {
            let entry = item.pointee
            guard String(cString: entry.ifa_name) == name, let address = entry.ifa_addr else { continue }
            guard Int32(address.pointee.sa_family) == AF_INET, let host = numeric(address), !isLinkLocal(host) else {
                continue
            }
            return host
        }
        return nil
    }

    static func census() -> HomeNetworkCensus {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let head else { return HomeNetworkCensus(ethernet: [], vpn: []) }
        defer { freeifaddrs(head) }
        var ethernet = Set<String>()
        var vpn = Set<String>()
        for item in sequence(first: head, next: { $0.pointee.ifa_next }) {
            record(item.pointee, ethernet: &ethernet, vpn: &vpn)
        }
        return HomeNetworkCensus(ethernet: ordered(ethernet), vpn: ordered(vpn))
    }

    private static func primary(_ store: SCDynamicStore, key: String) -> String? {
        let value = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any]
        let name = value?["PrimaryInterface"] as? String
        return name?.isEmpty == false ? name : nil
    }

    private static func record(
        _ entry: ifaddrs,
        ethernet: inout Set<String>,
        vpn: inout Set<String>
    ) {
        let flags = entry.ifa_flags
        guard flags & UInt32(IFF_UP) != 0, flags & UInt32(IFF_LOOPBACK) == 0 else { return }
        let name = String(cString: entry.ifa_name)
        guard let address = entry.ifa_addr else { return }
        let family = Int32(address.pointee.sa_family)
        let host = family == AF_INET || family == AF_INET6 ? numeric(address) : nil
        let role = classifies(name: name, family: family, host: host)
        if role.ethernet {
            ethernet.insert(name)
        }
        if role.vpn {
            vpn.insert(name)
        }
    }

    /// An inactive en interface still has a link address. Only a real unicast can carry a lookup.
    static func classifies(name: String, family: Int32, host: String?) -> (ethernet: Bool, vpn: Bool) {
        let routable = family == AF_INET || family == AF_INET6
        guard routable, let host, !isLinkLocal(host) else { return (false, false) }
        return (name.hasPrefix("en"), isTunnel(name))
    }

    private static func isTunnel(_ name: String) -> Bool {
        name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("ppp") || name.hasPrefix("gif")
    }

    private static func numeric(_ address: UnsafePointer<sockaddr>) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(
            address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST
        ) == 0 else { return nil }
        let bytes = host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        guard let text = String(bytes: bytes, encoding: .utf8), !text.isEmpty else { return nil }
        return text
    }

    private static func isLinkLocal(_ address: String) -> Bool {
        address.hasPrefix("fe80:") || address.hasPrefix("169.254.")
    }

    static func sortedNames(_ names: [String]) -> [String] {
        ordered(Set(names))
    }

    private static func ordered(_ names: Set<String>) -> [String] {
        names.sorted { rank($0) < rank($1) }
    }

    private static func rank(_ name: String) -> (Int, Int, String) {
        for prefix in ["en", "utun", "ipsec", "ppp", "gif"] where name.hasPrefix(prefix) {
            let suffix = name.dropFirst(prefix.count)
            if let number = Int(suffix), suffix.allSatisfy(\.isNumber) {
                return (0, number, name)
            }
            return (1, 0, name)
        }
        return (2, 0, name)
    }
}
