import Foundation

enum HomeMacModelYear {
    struct Record: Decodable, Sendable {
        let years: [Int]
        let parts: [String: [Int]]
    }

    struct Catalog: Decodable, Sendable {
        let sources: [String: String]
        let models: [String: Record]
    }

    private static let catalog: Catalog? = {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("MacModels/model-years.json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Catalog.self, from: data)
    }()

    static func label(identifier: String, modelNumber: String?) -> String? {
        guard let catalog else { return nil }
        return label(identifier: identifier, modelNumber: modelNumber, catalog: catalog)
    }

    static func label(identifier: String, modelNumber: String?, catalog: Catalog) -> String? {
        guard let record = catalog.models[identifier] else { return nil }
        var years = record.years
        if let number = modelNumber?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
            let matches = record.parts.filter { number.hasPrefix($0.key) }.flatMap(\.value)
            if !matches.isEmpty {
                years = Array(Set(matches)).sorted()
            }
        }
        guard !years.isEmpty else { return nil }
        return years.sorted().map(String.init).joined(separator: "／") + " 年款"
    }
}
