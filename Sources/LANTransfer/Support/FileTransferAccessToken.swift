import Foundation
import Security

enum FileTransferAccessToken {
    static func generate() -> String? {
        var bytes = [UInt8](repeating: 0, count: 2)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
