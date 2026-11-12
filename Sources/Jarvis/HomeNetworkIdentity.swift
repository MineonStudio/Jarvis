import Foundation

struct HomeNetworkLookup: Equatable, Sendable {
    var ip: String
    var place: String?
}

enum HomeNetworkBind: Equatable, Sendable {
    case route
    case interface(String)
}

struct HomeNetworkRequestPlan: Equatable, Sendable {
    var real: HomeNetworkBind
    var vpn: HomeNetworkBind?
    var regionFollowsVPN: Bool
}

struct HomeNetworkDisplay: Equatable, Sendable {
    var realAddress: String?
    var vpnAddress: String?
    var realCountry: String?
    var vpnCountry: String?
    var regionOnVPN: Bool
    var vpnActive: Bool

    static let empty = HomeNetworkDisplay(
        realAddress: nil,
        vpnAddress: nil,
        realCountry: nil,
        vpnCountry: nil,
        regionOnVPN: false,
        vpnActive: false
    )

    var lines: [String] {
        HomeNetworkFormatting.lines(self)
    }
}

enum HomeNetworkAddress {
    static func isPublic(_ address: String) -> Bool {
        if let bytes = ipv4(address) {
            return isPublicIPv4(bytes)
        }
        guard let bytes = ipv6(address) else { return false }
        return isPublicIPv6(bytes)
    }

    /// The card shows a public IPv4 address. IPv6 answers are ignored.
    static func isDisplayed(_ address: String) -> Bool {
        guard let bytes = ipv4(address) else { return false }
        return isPublicIPv4(bytes)
    }

    static func place(city: String?, region: String?, country: String? = nil) -> String? {
        let locality = trimmed(city) ?? trimmed(region)
        guard let country = countryName(country) else { return locality }
        guard let locality, !samePlace(locality, country) else { return country }
        return "\(locality), \(country)"
    }

    private static func countryName(_ value: String?) -> String? {
        guard let text = trimmed(value), text.count > 2 else { return nil }
        return text
    }

    private static func samePlace(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    private static func trimmed(_ value: String?) -> String? {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    private static func ipv4(_ address: String) -> [UInt8]? {
        var value = in_addr()
        guard inet_pton(AF_INET, address, &value) == 1 else { return nil }
        return withUnsafeBytes(of: value.s_addr) { Array($0.prefix(4)) }
    }

    private static func isPublicIPv4(_ bytes: [UInt8]) -> Bool {
        if bytes[0] == 0 || bytes[0] == 10 || bytes[0] == 127 {
            return false
        }
        if bytes[0] == 192, bytes[1] == 168 {
            return false
        }
        if bytes[0] == 169, bytes[1] == 254 {
            return false
        }
        if bytes[0] == 172, (16 ... 31).contains(Int(bytes[1])) {
            return false
        }
        if bytes[0] == 100, (64 ... 127).contains(Int(bytes[1])) {
            return false
        }
        // 198.18.0.0/15 is the TUN fake-ip range used by local proxy VPNs.
        if bytes[0] == 198, bytes[1] == 18 || bytes[1] == 19 {
            return false
        }
        return true
    }

    private static func ipv6(_ address: String) -> [UInt8]? {
        var value = in6_addr()
        guard inet_pton(AF_INET6, address, &value) == 1 else { return nil }
        return withUnsafeBytes(of: value) { Array($0.prefix(16)) }
    }

    private static func isPublicIPv6(_ bytes: [UInt8]) -> Bool {
        if bytes.allSatisfy({ $0 == 0 }) {
            return false
        }
        if bytes == [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1] {
            return false
        }
        if bytes[0] == 0xFE, bytes[1] & 0xC0 == 0x80 {
            return false
        }
        if bytes[0] & 0xFE == 0xFC {
            return false
        }
        return true
    }
}

enum HomeNetworkResolver {
    static func requestPlan(primary: String?, ethernet: [String], vpn: [String]) -> HomeNetworkRequestPlan {
        guard let tunnel = vpn.first else {
            return HomeNetworkRequestPlan(real: .route, vpn: nil, regionFollowsVPN: false)
        }
        if let primary, vpn.contains(primary) {
            let real: HomeNetworkBind = ethernet.first.map { .interface($0) } ?? .route
            return HomeNetworkRequestPlan(real: real, vpn: .route, regionFollowsVPN: true)
        }
        return HomeNetworkRequestPlan(real: .route, vpn: .interface(tunnel), regionFollowsVPN: false)
    }

    static func display(
        plan: HomeNetworkRequestPlan,
        vpnActive: Bool,
        real: HomeNetworkLookup?,
        vpn: HomeNetworkLookup?
    ) -> HomeNetworkDisplay {
        var real = accepted(real)
        var vpn = accepted(vpn)
        if real?.ip == vpn?.ip {
            if plan.regionFollowsVPN {
                real = nil
            } else {
                vpn = nil
            }
        }
        return HomeNetworkDisplay(
            realAddress: real?.ip,
            vpnAddress: vpnActive ? vpn?.ip : nil,
            realCountry: real?.place,
            vpnCountry: vpnActive ? vpn?.place : nil,
            regionOnVPN: plan.regionFollowsVPN && vpnActive,
            vpnActive: vpnActive
        )
    }

    static func publish(
        previous: HomeNetworkDisplay,
        resolved: HomeNetworkDisplay,
        primaryChanged: Bool,
        hadResult: Bool
    ) -> HomeNetworkDisplay {
        if resolved.realAddress != nil || resolved.vpnAddress != nil {
            return resolved
        }
        guard hadResult, !primaryChanged else { return .empty }
        var kept = previous
        kept.realCountry = nil
        kept.vpnCountry = nil
        kept.vpnActive = resolved.vpnActive
        kept.regionOnVPN = false
        if !resolved.vpnActive {
            kept.vpnAddress = nil
        }
        return kept
    }

    private static func accepted(_ lookup: HomeNetworkLookup?) -> HomeNetworkLookup? {
        guard let lookup, HomeNetworkAddress.isDisplayed(lookup.ip) else { return nil }
        return lookup
    }
}

enum HomeNetworkFormatting {
    static func lines(_ display: HomeNetworkDisplay) -> [String] {
        var rows = [line("真实IP", display.realAddress, place: display.realCountry)]
        if display.vpnActive {
            rows.append(line("代理IP", display.vpnAddress, place: display.vpnCountry))
        }
        return rows
    }

    /// Keeps the address shape and removes every original character.
    static func masked(_ address: String) -> String {
        if let ipv4 = maskedIPv4(address) {
            return ipv4
        }
        guard address.contains(":") else { return "•••" }
        return address.split(separator: ":", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? "" : "****" }
            .joined(separator: ":")
    }

    private static func maskedIPv4(_ address: String) -> String? {
        let parts = address.split(separator: ".")
        guard parts.count == 4, parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        return Array(repeating: "***", count: 4).joined(separator: ".")
    }

    private static func line(_ title: String, _ address: String?, place: String?) -> String {
        guard let address else { return "\(title) —" }
        guard let place else { return "\(title) \(address)" }
        return "\(title) \(address) · \(place)"
    }
}
