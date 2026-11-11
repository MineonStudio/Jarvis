import CryptoKit
import Foundation

/// 图片像素的稳定身份。截图历史和剪贴板图片用同一份 PNG 字节算出同一个值，
/// 这样同一张图只做一次 OCR。
enum ImageContentHash {
    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
