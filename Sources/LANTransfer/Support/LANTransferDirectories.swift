import Foundation

enum LANTransferDirectories {
    static func root(
        fileManager: FileManager = .default,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) -> URL {
        let support = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory
        let jarvisDirectory = switch bundleIdentifier {
        case "com.jarvis.mac.dev": "Jarvis-Dev"
        case "com.jarvis.mac": "Jarvis"
        default: "Jarvis-Test"
        }
        return support
            .appendingPathComponent(jarvisDirectory, isDirectory: true)
            .appendingPathComponent("局域网传输", isDirectory: true)
    }
}
