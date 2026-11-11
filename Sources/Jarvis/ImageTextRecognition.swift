import CoreGraphics
import Foundation
import ImageIO
import Vision

/// 把一张静图里的文字收成一段可搜索文本。
///
/// 长边收到 2000 像素再走精确识别，避免把整张视网膜截图原样送进 Vision。
/// 读不出图像时返回空字符串（没有可重试的内容）；Vision 自己失败时返回 nil，
/// 调用方不落盘，下次启动再试。这里不记录识别出的文字。
enum ImageTextRecognition {
    static let maxLongEdge = 2000

    static func recognize(_ data: Data) async -> String? {
        await Task.detached(priority: .utility) {
            recognizeSynchronously(data)
        }.value
    }

    /// 相邻片段：任一侧是 ASCII 时补一个空格，否则直接拼接。
    /// 「大」「模型」因此仍能被「大模型」搜到。
    static func joined(_ parts: [String]) -> String {
        parts.reduce(into: "") { result, part in
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if result.isEmpty {
                result = trimmed
            } else {
                result = joinedPair(result, trimmed)
            }
        }
    }

    private static func recognizeSynchronously(_ data: Data) -> String? {
        guard let image = thumbnail(from: data) else { return "" }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        request.automaticallyDetectsLanguage = true

        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            return nil
        }
        return joined(readingOrderLines(from: request))
    }

    private static func readingOrderLines(from request: VNRecognizeTextRequest) -> [String] {
        let lines: [(text: String, bounds: CGRect)] = (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !text.isEmpty
            else {
                return nil
            }
            return (text, observation.boundingBox)
        }
        return lines.sorted { lhs, rhs in
            if abs(lhs.bounds.midY - rhs.bounds.midY) > 0.012 {
                return lhs.bounds.midY > rhs.bounds.midY
            }
            return lhs.bounds.minX < rhs.bounds.minX
        }.map(\.text)
    }

    private static func joinedPair(_ left: String, _ right: String) -> String {
        let needsSpace = left.last?.isASCII == true || right.first?.isASCII == true
        return needsSpace ? "\(left) \(right)" : left + right
    }

    private static func thumbnail(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxLongEdge,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }
}
