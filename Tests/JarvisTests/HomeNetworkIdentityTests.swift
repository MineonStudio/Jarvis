import Darwin
@testable import Jarvis
import XCTest

final class HomeNetworkIdentityTests: XCTestCase {
    func testPublicAddressesExcludeLANTunnelAndLinkLocal() {
        let accepted = ["203.0.113.8", "8.8.8.8", "172.15.0.1", "172.32.0.1", "100.63.255.255", "100.128.0.1", "192.169.0.1", "2001:4860:4860::8888"]
        let rejected = [
            "192.168.1.20", "10.1.2.3", "172.16.0.1", "172.31.255.255", "100.64.0.1", "100.127.255.255",
            "127.0.0.1", "169.254.1.1", "0.1.2.3", "198.18.0.1", "198.19.255.255", "fe80::1", "fe80::1%utun0",
            "fc00::1", "fd00::1", "::1", "::",
            "", "not-an-ip"
        ]
        for address in accepted {
            XCTAssertTrue(HomeNetworkAddress.isPublic(address), address)
        }
        for address in rejected {
            XCTAssertFalse(HomeNetworkAddress.isPublic(address), address)
        }
        XCTAssertTrue(HomeNetworkAddress.isDisplayed("203.0.113.8"))
        XCTAssertFalse(HomeNetworkAddress.isDisplayed("2001:db8::1"))
    }

    func testPlacePrefersACityAndTrimsBlankText() {
        XCTAssertEqual(HomeNetworkAddress.place(city: " 上海 ", region: "Shanghai"), "上海")
        XCTAssertEqual(HomeNetworkAddress.place(city: "   ", region: " 上海 "), "上海")
        XCTAssertNil(HomeNetworkAddress.place(city: " ", region: " "))
        XCTAssertNil(HomeNetworkAddress.place(city: nil, region: nil))
        XCTAssertEqual(
            HomeNetworkAddress.place(city: "Tokyo", region: "Tokyo", country: "Japan"),
            "Tokyo, Japan"
        )
        XCTAssertEqual(HomeNetworkAddress.place(city: "Tokyo", region: "Tokyo", country: "JP"), "Tokyo")
        XCTAssertEqual(HomeNetworkAddress.place(city: nil, region: nil, country: "Japan"), "Japan")
    }

    func testRequestPlanFollowsTheDefaultRoute() {
        let idle = HomeNetworkResolver.requestPlan(primary: "en0", ethernet: ["en0"], vpn: [])
        XCTAssertEqual(idle, HomeNetworkRequestPlan(real: .route, vpn: nil, regionFollowsVPN: false))

        let full = HomeNetworkResolver.requestPlan(primary: "utun3", ethernet: ["en0", "en1"], vpn: ["utun3", "utun4"])
        XCTAssertEqual(full, HomeNetworkRequestPlan(real: .interface("en0"), vpn: .route, regionFollowsVPN: true))

        let unbound = HomeNetworkResolver.requestPlan(primary: "utun3", ethernet: [], vpn: ["utun3"])
        XCTAssertEqual(unbound, HomeNetworkRequestPlan(real: .route, vpn: .route, regionFollowsVPN: true))

        let split = HomeNetworkResolver.requestPlan(primary: "en0", ethernet: ["en0"], vpn: ["utun3", "utun4"])
        XCTAssertEqual(split, HomeNetworkRequestPlan(real: .route, vpn: .interface("utun3"), regionFollowsVPN: false))
    }

    func testTheSamePublicAddressStaysOnTheDefaultRouteOnly() {
        let shared = HomeNetworkLookup(ip: "203.0.113.8", place: "China")
        let split = HomeNetworkResolver.display(
            plan: HomeNetworkRequestPlan(real: .route, vpn: .interface("utun3"), regionFollowsVPN: false),
            vpnActive: true,
            real: shared,
            vpn: shared
        )
        XCTAssertEqual(split.realAddress, "203.0.113.8")
        XCTAssertNil(split.vpnAddress)
        XCTAssertEqual(split.realCountry, "China")
        XCTAssertNil(split.vpnCountry)
        XCTAssertFalse(split.regionOnVPN)

        let full = HomeNetworkResolver.display(
            plan: HomeNetworkRequestPlan(real: .interface("en0"), vpn: .route, regionFollowsVPN: true),
            vpnActive: true,
            real: HomeNetworkLookup(ip: "198.51.100.9", place: "China"),
            vpn: HomeNetworkLookup(ip: "198.51.100.9", place: "Japan")
        )
        XCTAssertNil(full.realAddress)
        XCTAssertEqual(full.vpnAddress, "198.51.100.9")
        XCTAssertNil(full.realCountry)
        XCTAssertEqual(full.vpnCountry, "Japan")
        XCTAssertTrue(full.regionOnVPN)
    }

    func testInnerTunnelAddressesAreNotShown() {
        let shown = HomeNetworkResolver.display(
            plan: HomeNetworkRequestPlan(real: .interface("en0"), vpn: .route, regionFollowsVPN: true),
            vpnActive: true,
            real: HomeNetworkLookup(ip: "10.8.0.2", place: "内网"),
            vpn: HomeNetworkLookup(ip: "198.51.100.9", place: "Japan")
        )
        XCTAssertNil(shown.realAddress)
        XCTAssertEqual(shown.vpnAddress, "198.51.100.9")
        XCTAssertEqual(shown.vpnCountry, "Japan")
        XCTAssertEqual(shown.lines, ["真实IP —", "代理IP 198.51.100.9 · Japan"])
    }

    func testAFailedRouteKeepsKnownAddressesAndClearsTheRegion() {
        let previous = HomeNetworkDisplay(
            realAddress: "203.0.113.8",
            vpnAddress: "198.51.100.9",
            realCountry: "China",
            vpnCountry: "Japan",
            regionOnVPN: true,
            vpnActive: true
        )
        let kept = HomeNetworkResolver.publish(
            previous: previous,
            resolved: HomeNetworkDisplay(
                realAddress: nil,
                vpnAddress: nil,
                realCountry: nil,
                vpnCountry: nil,
                regionOnVPN: false,
                vpnActive: true
            ),
            primaryChanged: false,
            hadResult: true
        )
        XCTAssertEqual(kept.realAddress, "203.0.113.8")
        XCTAssertEqual(kept.vpnAddress, "198.51.100.9")
        XCTAssertNil(kept.realCountry)
        XCTAssertNil(kept.vpnCountry)
        XCTAssertFalse(kept.regionOnVPN)
        XCTAssertTrue(kept.vpnActive)

        var disconnected = HomeNetworkDisplay.empty
        disconnected.vpnActive = false
        let dropped = HomeNetworkResolver.publish(
            previous: previous,
            resolved: disconnected,
            primaryChanged: false,
            hadResult: true
        )
        XCTAssertEqual(dropped.realAddress, "203.0.113.8")
        XCTAssertNil(dropped.vpnAddress)
        XCTAssertFalse(dropped.vpnActive)
    }

    func testARouteChangeOrFirstFailureClearsTheCard() {
        let previous = HomeNetworkDisplay(
            realAddress: "203.0.113.8",
            vpnAddress: nil,
            realCountry: "China",
            vpnCountry: nil,
            regionOnVPN: false,
            vpnActive: false
        )
        XCTAssertEqual(
            HomeNetworkResolver.publish(
                previous: previous, resolved: .empty, primaryChanged: true, hadResult: true
            ),
            .empty
        )
        XCTAssertEqual(
            HomeNetworkResolver.publish(
                previous: previous, resolved: .empty, primaryChanged: false, hadResult: false
            ),
            .empty
        )
        let refreshed = HomeNetworkDisplay(
            realAddress: nil,
            vpnAddress: "198.51.100.9",
            realCountry: nil,
            vpnCountry: "Japan",
            regionOnVPN: true,
            vpnActive: true
        )
        XCTAssertEqual(
            HomeNetworkResolver.publish(
                previous: previous, resolved: refreshed, primaryChanged: true, hadResult: true
            ),
            refreshed
        )
    }

    func testLinesNameTheRealAddressAndTheProxyAddressSeparately() {
        XCTAssertEqual(HomeNetworkFormatting.lines(.empty), ["真实IP —"])
        var real = HomeNetworkDisplay.empty
        real.realAddress = "203.0.113.8"
        XCTAssertEqual(HomeNetworkFormatting.lines(real), ["真实IP 203.0.113.8"])
        real.realCountry = "China"
        XCTAssertEqual(HomeNetworkFormatting.lines(real), ["真实IP 203.0.113.8 · China"])

        let throughProxy = HomeNetworkDisplay(
            realAddress: "203.0.113.8",
            vpnAddress: "198.51.100.9",
            realCountry: "China",
            vpnCountry: "Japan",
            regionOnVPN: true,
            vpnActive: true
        )
        XCTAssertEqual(
            HomeNetworkFormatting.lines(throughProxy),
            ["真实IP 203.0.113.8 · China", "代理IP 198.51.100.9 · Japan"]
        )
        let split = HomeNetworkDisplay(
            realAddress: "203.0.113.8",
            vpnAddress: nil,
            realCountry: "China",
            vpnCountry: "Japan",
            regionOnVPN: false,
            vpnActive: true
        )
        XCTAssertEqual(HomeNetworkFormatting.lines(split), ["真实IP 203.0.113.8 · China", "代理IP —"])
    }

    func testIPFMPageKeepsTheCountryAndDropsTheCity() {
        let visitor = Data(
            """
            <p class="block"><span class="has-text-grey-light">IP: </span>203.0.113.8</p>
            <p class="block"><span class="has-text-grey-light">Location: </span>Tokyo, Japan</p>
            """.utf8
        )
        XCTAssertEqual(
            HomeNetworkPage.visitor(from: visitor),
            HomeNetworkLookup(ip: "203.0.113.8", place: "Japan")
        )
        let country = Data(
            #"<span class="has-text-grey-light">Location: </span>United States</p>"#.utf8
        )
        XCTAssertEqual(HomeNetworkPage.country(from: country), "United States")
        XCTAssertEqual(HomeNetworkPage.country(in: "Shinjuku, Tokyo, Japan"), "Japan")
        XCTAssertNil(HomeNetworkPage.country(in: "null"))
        XCTAssertNil(HomeNetworkPage.country(in: "  "))
        let missing = Data(
            """
            <span class="has-text-grey-light">IP: </span>1.1.1.1</p>
            <span class="has-text-grey-light">Location: </span><span class="tag is-warning">null</span>
            """.utf8
        )
        XCTAssertEqual(HomeNetworkPage.visitor(from: missing)?.ip, "1.1.1.1")
        XCTAssertNil(HomeNetworkPage.visitor(from: missing)?.place)
        let tunnel = Data(
            #"<span class="has-text-grey-light">IP: </span>198.18.0.1</p><span>Location: </span>Japan"#.utf8
        )
        XCTAssertNil(HomeNetworkPage.visitor(from: tunnel))
        let ipv6 = Data(
            #"<span class="has-text-grey-light">IP: </span>2001:db8::1</p><span>Location: </span>Japan"#.utf8
        )
        XCTAssertNil(HomeNetworkPage.visitor(from: ipv6))
    }

    func testRealAddressesMaskEveryOriginalCharacter() {
        XCTAssertEqual(HomeNetworkFormatting.masked("203.0.113.8"), "***.***.***.***")
        XCTAssertFalse(HomeNetworkFormatting.masked("203.0.113.8").contains("203"))
        XCTAssertEqual(HomeNetworkFormatting.masked("2001:db8::1"), "****:****::****")
        XCTAssertFalse(HomeNetworkFormatting.masked("2001:db8::1").contains("2001"))
        XCTAssertEqual(HomeNetworkFormatting.masked("not-an-ip"), "•••")
    }

    func testDNSAnswersReadAddressRecords() {
        var packet = HomeNetworkDNS.message(for: "ifconfig.co")
        packet[7] = 2
        packet.append(contentsOf: [
            0xC0, 0x0C, 0x00, 0x05, 0x00, 0x01, 0x00, 0x00, 0x00, 0x3C, 0x00, 0x02, 0xC0, 0x0C,
            0xC0, 0x0C, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x3C, 0x00, 0x04, 36, 32, 122, 130
        ])
        XCTAssertEqual(HomeNetworkDNS.addresses(in: packet), ["36.32.122.130"])
        XCTAssertTrue(HomeNetworkDNS.addresses(in: Data([0, 1])).isEmpty)
    }

    func testHTTPBodyIsCompleteAtContentLengthOrJSON() {
        let headers = Data("HTTP/1.0 200 OK\r\nContent-Length: 2\r\n\r\n{}".utf8)
        XCTAssertTrue(HomeNetworkHTTP.finished(headers))
        let short = Data("HTTP/1.0 200 OK\r\nContent-Length: 4\r\n\r\n{}".utf8)
        XCTAssertFalse(HomeNetworkHTTP.finished(short))
        let json = Data("HTTP/1.0 200 OK\r\n\r\n{\"ip\":\"203.0.113.8\"}".utf8)
        XCTAssertTrue(HomeNetworkHTTP.finished(json))
        XCTAssertFalse(HomeNetworkHTTP.finished(Data("HTTP/1.0 200 OK\r\n".utf8)))
    }

    func testPayloadReadsTheJSONObjectAndRejectsPrivateAddresses() {
        let framed = Data(
            "HTTP/1.1 200 OK\r\n\r\n{\"ip\":\"203.0.113.8\",\"city\":\" 上海 \",\"region\":\"Shanghai\",\"org\":\"Example\"}"
                .utf8
        )
        XCTAssertEqual(HomeNetworkPayload.lookup(from: framed), HomeNetworkLookup(ip: "203.0.113.8", place: "上海"))
        let region = Data("{\"ip\":\"203.0.113.8\",\"city\":\"  \",\"region\":\"上海\"}".utf8)
        XCTAssertEqual(HomeNetworkPayload.lookup(from: region)?.place, "上海")
        XCTAssertNil(HomeNetworkPayload.lookup(from: Data("{\"ip\":\"10.1.2.3\",\"city\":\"上海\"}".utf8)))
        XCTAssertNil(HomeNetworkPayload.lookup(from: Data("{\"ip\":\"2001:db8::1\",\"country\":\"Japan\"}".utf8)))
        let headers = Data(
            "HTTP/1.1 200 OK\r\nNel: {\"a\":1}\r\n\r\n{\"ip\":\"203.0.113.8\",\"city\":\"上海\"}".utf8
        )
        XCTAssertEqual(HomeNetworkPayload.lookup(from: headers)?.ip, "203.0.113.8")
        XCTAssertNil(HomeNetworkPayload.lookup(from: Data("not json".utf8)))
        XCTAssertNil(HomeNetworkPayload.lookup(from: Data("{\"status\":429,\"error\":{\"title\":\"Rate limit hit\"}}".utf8)))
        let fallback = Data(
            "{\"ip\":\"203.0.113.9\",\"city\":\"Tokyo\",\"region_name\":\"Tokyo\",\"country\":\"Japan\"}".utf8
        )
        XCTAssertEqual(HomeNetworkPayload.lookup(from: fallback), HomeNetworkLookup(ip: "203.0.113.9", place: "Tokyo, Japan"))
    }

    func testOnlyInterfacesWithARoutableAddressAreUsed() {
        XCTAssertTrue(HomeNetworkRoute.classifies(name: "en1", family: AF_INET, host: "192.168.31.39").ethernet)
        XCTAssertFalse(HomeNetworkRoute.classifies(name: "en0", family: AF_LINK, host: nil).ethernet)
        XCTAssertFalse(HomeNetworkRoute.classifies(name: "en0", family: AF_INET, host: "169.254.1.1").ethernet)
        XCTAssertTrue(HomeNetworkRoute.classifies(name: "utun4", family: AF_INET, host: "198.18.0.1").vpn)
        XCTAssertFalse(HomeNetworkRoute.classifies(name: "utun0", family: AF_INET6, host: "fe80::1%utun0").vpn)
    }

    func testOnceResumesWhenTheStoredValueIsNil() async {
        let finished = HomeNetworkOnce<String?>()
        finished.finish(nil)
        let immediate = await finished.value
        XCTAssertNil(immediate)

        let waiting = HomeNetworkOnce<String?>()
        let task = Task { await waiting.value }
        waiting.finish(nil)
        let later = await task.value
        XCTAssertNil(later)

        let text = HomeNetworkOnce<String?>()
        text.finish("203.0.113.8")
        let stored = await text.value
        XCTAssertEqual(stored, "203.0.113.8")
    }

    func testInterfaceNamesSortByNumericSuffix() {
        XCTAssertEqual(HomeNetworkRoute.sortedNames(["en10", "enc0", "en2"]), ["en2", "en10", "enc0"])
        XCTAssertEqual(HomeNetworkRoute.sortedNames(["utun10", "ppp2", "utun2"]), ["ppp2", "utun2", "utun10"])
    }
}
