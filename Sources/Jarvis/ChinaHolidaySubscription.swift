import Foundation

actor ChinaHolidaySubscription {
    static let shared = ChinaHolidaySubscription()
    private var snapshot: ChinaHolidaySnapshot?
    private var lastAttempt = Date.distantPast
    private let session = URLSession(configuration: .ephemeral)
    private var cacheURL: URL {
        URL.cachesDirectory.appendingPathComponent(JarvisAppIdentity.dataDirectoryName)
            .appendingPathComponent("Calendar/china-holidays-v2.json")
    }

    func cached() -> ChinaHolidaySnapshot {
        if let snapshot {
            return snapshot
        }
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("Calendar/china-holidays.json")
        for url in [cacheURL, bundled].compactMap({ $0 }) {
            if let data = try? Data(contentsOf: url),
               let decoded = try? JSONDecoder().decode(ChinaHolidaySnapshot.self, from: data),
               decoded.source == ChinaHolidayCalendar.source.absoluteString, !decoded.days.isEmpty
            {
                snapshot = decoded
                return decoded
            }
        }
        let empty = ChinaHolidaySnapshot(source: ChinaHolidayCalendar.source.absoluteString, fetchedAt: .distantPast, days: [:])
        snapshot = empty
        return empty
    }

    func refresh() async -> ChinaHolidaySnapshot {
        let current = cached()
        guard Date().timeIntervalSince(current.fetchedAt) >= 86400,
              Date().timeIntervalSince(lastAttempt) >= 900 else { return current }
        lastAttempt = Date()
        var request = URLRequest(url: ChinaHolidayCalendar.source)
        request.timeoutInterval = 15
        request.setValue("text/calendar", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                  data.count < 2_000_000 else { return current }
            let days = try ChinaHolidayCalendar.parse(data)
            let fresh = ChinaHolidaySnapshot(source: ChinaHolidayCalendar.source.absoluteString, fetchedAt: Date(), days: days)
            snapshot = fresh
            try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let encoded = try? JSONEncoder().encode(fresh) {
                try? encoded.write(to: cacheURL, options: .atomic)
            }
            return fresh
        } catch { return current }
    }
}
