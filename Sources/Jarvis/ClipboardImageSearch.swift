import Foundation

extension ClipboardFilterLogic {
    static let searchPlaceholder = "搜索文本、图片文字、文件名…"

    /// 文本和文件名仍看预览。只有真正的图片项才额外匹配 OCR 文本；视频和文件不看图里的字。
    static func matchesSearch(
        _ item: ClipboardItem,
        query: String,
        imageTextByHash: [String: String]
    ) -> Bool {
        if query.isEmpty || item.preview.localizedCaseInsensitiveContains(query) {
            return true
        }
        guard item.kind == .image,
              let hash = item.fingerprintValue,
              let text = imageTextByHash[hash],
              !text.isEmpty
        else {
            return false
        }
        return text.localizedCaseInsensitiveContains(query)
    }
}
