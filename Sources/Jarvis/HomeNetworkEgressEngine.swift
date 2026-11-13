import Foundation
import Network

/// One homepage visit looks up immediately. A success waits for the next visit or a path change.
enum HomeNetworkLookupPlan {
    static func beginVisit() -> Date {
        .distantPast
    }

    static func isDue(now: Date, nextLookup: Date, generation: Int, handledGeneration: Int) -> Bool {
        now >= nextLookup || generation != handledGeneration
    }

    static func afterSuccess() -> Date {
        .distantFuture
    }

    /// Only an address from this lookup counts. A card that keeps the previous address is a miss.
    static func succeeded(_ resolved: HomeNetworkDisplay) -> Bool {
        resolved.realAddress != nil || resolved.vpnAddress != nil
    }

    static func afterFailure(now: Date, attempt: Int) -> (date: Date, attempt: Int) {
        let index = min(attempt, backoff.count - 1)
        return (now.addingTimeInterval(backoff[index]), min(attempt + 1, backoff.count - 1))
    }

    private static let backoff: [TimeInterval] = [60, 120, 240, 30 * 60]
}

@MainActor
final class HomeNetworkEgressEngine {
    var onUpdate: (@MainActor (HomeNetworkDisplay) -> Void)?
    var fetcher: @Sendable (String?) async -> HomeNetworkLookup?
    var proxyFetcher: @Sendable () async -> HomeNetworkLookup?
    var countryFetcher: @Sendable (String) async -> String?

    init() {
        let client = HomeNetworkFetcher()
        fetcher = { name in
            await client.lookup(interfaceName: name)
        }
        proxyFetcher = {
            await client.proxy()
        }
        countryFetcher = { address in
            await client.country(of: address)
        }
    }

    private var display = HomeNetworkDisplay.empty
    private var nextLookup = Date.distantPast
    private var failureStep = 0
    private var lastPrimary: String?
    private var hasResult = false
    private var sawPath = false
    private var satisfied = false
    private var generation = 0
    private var handledGeneration = 0
    private var runToken = 0
    private var monitor: NWPathMonitor?

    func run() async {
        runToken += 1
        let token = runToken
        failureStep = 0
        nextLookup = HomeNetworkLookupPlan.beginVisit()
        let pathMonitor = NWPathMonitor()
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let ok = path.status == .satisfied
            Task { @MainActor in
                guard let self, self.runToken == token else { return }
                self.note(satisfied: ok)
            }
        }
        monitor?.cancel()
        pathMonitor.start(queue: DispatchQueue(label: "jarvis.home.network.path"))
        monitor = pathMonitor
        defer {
            if runToken == token {
                pathMonitor.cancel()
                monitor = nil
            }
        }
        while !Task.isCancelled, runToken == token {
            if !sawPath {
                try? await Task.sleep(for: .milliseconds(200))
                continue
            }
            guard satisfied else {
                clearRegion()
                await waitForChange()
                continue
            }
            let due = HomeNetworkLookupPlan.isDue(
                now: Date(),
                nextLookup: nextLookup,
                generation: generation,
                handledGeneration: handledGeneration
            )
            if !due {
                try? await Task.sleep(for: .milliseconds(400))
                continue
            }
            let stamp = generation
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, runToken == token, satisfied, generation == stamp else { continue }
            handledGeneration = generation
            await query(token: token)
        }
    }

    private func note(satisfied: Bool) {
        sawPath = true
        self.satisfied = satisfied
        generation += 1
    }

    private func waitForChange() async {
        let seen = generation
        while !Task.isCancelled, generation == seen {
            try? await Task.sleep(for: .milliseconds(300))
        }
    }

    private func clearRegion() {
        guard hasResult, display.realCountry != nil || display.vpnCountry != nil else { return }
        display.realCountry = nil
        display.vpnCountry = nil
        onUpdate?(display)
    }

    private func query(token: Int) async {
        let census = HomeNetworkRoute.census()
        let primary = HomeNetworkRoute.primaryInterface()
        let plan = HomeNetworkResolver.requestPlan(
            primary: primary, ethernet: census.ethernet, vpn: census.vpn
        )
        let state = begin(primary: primary, plan: plan, vpnActive: !census.vpn.isEmpty)
        async let proxyTask: HomeNetworkLookup? = loadProxy(plan)
        async let realTask: HomeNetworkLookup? = loadReal(plan)
        let proxy = await proxyTask
        guard current(token) else { return }
        // The physical lookup can take longer than the tunnel page. Show the proxy exit first.
        if plan.vpn == .route, proxy != nil {
            reveal(state, real: nil, vpn: proxy)
        }
        let real = await located(realTask, state: state, vpn: proxy, token: token)
        guard current(token) else { return }
        let refreshed = reveal(state, real: real, vpn: proxy)
        finish(refreshed: refreshed)
    }

    private func current(_ token: Int) -> Bool {
        runToken == token && !Task.isCancelled
    }

    private func located(
        _ lookup: HomeNetworkLookup?,
        state: RevealState,
        vpn: HomeNetworkLookup?,
        token: Int
    ) async -> HomeNetworkLookup? {
        guard var lookup else { return nil }
        lookup.place = nil
        reveal(state, real: lookup, vpn: vpn)
        guard current(token) else { return lookup }
        lookup.place = await countryFetcher(lookup.ip)
        return lookup
    }

    private func finish(refreshed: Bool) {
        hasResult = display.realAddress != nil || display.vpnAddress != nil
        schedule(failed: !refreshed)
        log(found: hasResult)
    }

    private func begin(primary: String?, plan: HomeNetworkRequestPlan, vpnActive: Bool) -> RevealState {
        let changed = hasResult && primary != lastPrimary
        let had = hasResult
        lastPrimary = primary
        if changed {
            display = .empty
            onUpdate?(display)
        }
        return RevealState(plan: plan, vpnActive: vpnActive, changed: changed, hadResult: had)
    }

    private func loadProxy(_ plan: HomeNetworkRequestPlan) async -> HomeNetworkLookup? {
        guard plan.vpn != nil else { return nil }
        return await proxyFetcher()
    }

    private func loadReal(_ plan: HomeNetworkRequestPlan) async -> HomeNetworkLookup? {
        switch plan.real {
        case .route:
            await fetcher(nil)
        case let .interface(name):
            await fetcher(name)
        }
    }

    private struct RevealState {
        var plan: HomeNetworkRequestPlan
        var vpnActive: Bool
        var changed: Bool
        var hadResult: Bool
    }

    @discardableResult
    private func reveal(_ state: RevealState, real: HomeNetworkLookup?, vpn: HomeNetworkLookup?) -> Bool {
        let resolved = HomeNetworkResolver.display(
            plan: state.plan, vpnActive: state.vpnActive, real: real, vpn: vpn
        )
        display = HomeNetworkResolver.publish(
            previous: display, resolved: resolved, primaryChanged: state.changed, hadResult: state.hadResult
        )
        onUpdate?(display)
        return HomeNetworkLookupPlan.succeeded(resolved)
    }

    private func schedule(failed: Bool) {
        if failed {
            let scheduled = HomeNetworkLookupPlan.afterFailure(now: Date(), attempt: failureStep)
            failureStep = scheduled.attempt
            nextLookup = scheduled.date
            return
        }
        failureStep = 0
        nextLookup = HomeNetworkLookupPlan.afterSuccess()
    }

    private func log(found: Bool) {
        let hasCountry = display.realCountry != nil || display.vpnCountry != nil
        let result = if !found {
            "empty"
        } else if !hasCountry {
            "address-only"
        } else {
            "hit"
        }
        let vpn = if !display.vpnActive {
            "off"
        } else if display.vpnAddress == nil {
            "missing"
        } else {
            "shown"
        }
        JarvisLog.info(
            category: .network,
            event: "home.network.egress.updated",
            result: result,
            fields: ["viaVPN": display.regionOnVPN ? "true" : "false", "vpn": vpn]
        )
    }
}
