import AppKit

/// Size the option window from its labels and native popup controls.
@MainActor
enum ScreenRecordingOptionsLayout {
    static func width(microphoneNames: [String]) -> CGFloat {
        let rowTitles = ["系统默认麦克风", "显示鼠标点按", "包括系统音频"] + microphoneNames
        let choices = ["H.264", "HEVC", "30 fps", "60 fps"] + ScreenRecordingQuality.allCases.map(\.title)
        let rows = textWidth(rowTitles) + 54
        let pickers = textWidth(["编码", "画质", "帧率"]) + textWidth(choices) + 72
        return min(280, ceil(max(rows, pickers)))
    }

    private static func textWidth(_ strings: [String]) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13)]
        return strings.map { ($0 as NSString).size(withAttributes: attributes).width }.max() ?? 0
    }
}
