import Foundation

struct HomeNetworkFetcher: Sendable {
    var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 8
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    func lookup(interfaceName: String?) async -> HomeNetworkLookup? {
        if let interfaceName {
            // The tunnel captures DNS and TLS on the physical NIC. The direct query avoids both.
            return await Task.detached(priority: .utility) {
                HomeNetworkInterfaceQuery.lookup(interfaceName: interfaceName)
            }.value
        }
        for endpoint in Self.endpoints {
            let reply = await load(endpoint)
            if let data = reply.data, let found = HomeNetworkPayload.lookup(from: data) {
                return found
            }
            if reply.failed {
                return nil
            }
        }
        return nil
    }

    /// The visitor page follows the default route. A full tunnel therefore reports the proxy exit.
    func proxy() async -> HomeNetworkLookup? {
        guard let data = await page(Self.visitorURL) else { return nil }
        return HomeNetworkPage.visitor(from: data)
    }

    /// Country for an address that was already discovered. The request stays on the default route.
    func country(of address: String) async -> String? {
        guard HomeNetworkAddress.isDisplayed(address),
              let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let data = await page("https://ip.fm/ip/\(encoded)")
        else { return nil }
        return HomeNetworkPage.country(from: data)
    }

    private func page(_ urlString: String) async -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode)
        else { return nil }
        return data
    }

    private func load(_ endpoint: Endpoint) async -> (data: Data?, failed: Bool) {
        var request = URLRequest(url: endpoint.url)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request), response is HTTPURLResponse else {
            return (nil, true)
        }
        return (data, false)
    }

    private struct Endpoint {
        var host: String
        var path: String
        var url: URL
    }

    /// ipinfo's free database has labeled this exit as the wrong locality and often returns 429.
    /// ifconfig.co is asked first. ipinfo is used only when that body has no public address.
    private static let endpoints: [Endpoint] = ["ifconfig.co", "ipinfo.io"].compactMap { host in
        guard let url = URL(string: "https://\(host)/json") else { return nil }
        return Endpoint(host: host, path: "/json", url: url)
    }

    private static let userAgent = "Jarvis macOS"
    private static let visitorURL = "https://ip.fm"
}

enum HomeNetworkPage {
    static func visitor(from data: Data) -> HomeNetworkLookup? {
        guard let html = String(data: data, encoding: .utf8),
              let ip = value(after: "IP: </span>", in: html),
              HomeNetworkAddress.isDisplayed(ip)
        else { return nil }
        let location = value(after: "Location: </span>", in: html)
        return HomeNetworkLookup(ip: ip, place: country(in: location))
    }

    static func country(from data: Data) -> String? {
        guard let html = String(data: data, encoding: .utf8) else { return nil }
        return country(in: value(after: "Location: </span>", in: html))
    }

    static func country(in location: String?) -> String? {
        guard let location else { return nil }
        let text = location.split(separator: ",").last?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty, text.compare("null", options: .caseInsensitive) != .orderedSame else {
            return nil
        }
        return text
    }

    private static func value(after marker: String, in html: String) -> String? {
        guard let range = html.range(of: marker) else { return nil }
        let raw = html[range.upperBound...].prefix { $0 != "<" }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

enum HomeNetworkPayload {
    static func lookup(from data: Data) -> HomeNetworkLookup? {
        let body = jsonBody(data)
        guard let start = body.firstIndex(of: UInt8(ascii: "{")),
              let end = body.lastIndex(of: UInt8(ascii: "}"))
        else { return nil }
        guard let payload = try? JSONDecoder().decode(Body.self, from: Data(body[start ... end])),
              let ip = payload.ip, HomeNetworkAddress.isDisplayed(ip)
        else { return nil }
        let region = payload.region ?? payload.regionName
        let place = HomeNetworkAddress.place(city: payload.city, region: region, country: payload.country)
        return HomeNetworkLookup(ip: ip, place: place)
    }

    /// Header lines from the bound query can contain braces. Only the body is JSON.
    private static func jsonBody(_ data: Data) -> Data {
        let separator = Data("\r\n\r\n".utf8)
        guard let range = data.range(of: separator) else { return data }
        return Data(data[range.upperBound...])
    }

    private struct Body: Decodable {
        let ip: String?
        let city: String?
        let region: String?
        let regionName: String?
        let country: String?

        enum CodingKeys: String, CodingKey {
            case ip
            case city
            case region
            case regionName = "region_name"
            case country
        }
    }
}

final class HomeNetworkOnce<Value: Sendable>: @unchecked Sendable {
    private struct Slot {
        var value: Value
    }

    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?
    private var slot: Slot?

    func finish(_ value: Value) {
        lock.lock()
        if slot != nil {
            lock.unlock()
            return
        }
        slot = Slot(value: value)
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }

    var value: Value {
        get async {
            await withCheckedContinuation { continuation in
                lock.lock()
                if let ready = slot?.value {
                    lock.unlock()
                    continuation.resume(returning: ready)
                    return
                }
                self.continuation = continuation
                lock.unlock()
            }
        }
    }
}
