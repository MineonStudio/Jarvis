import SwiftUI

/// A single source link flows after the secondary text instead of repeating a row
/// of timestamps. Additional references remain part of the stored minutes.
struct MeetingCitedText: View {
    let text: String
    var time: Double?
    var quote: String = ""
    var secondary = true
    var font: Font = .system(size: 14)
    var isPlaying = false
    var isStrikethrough = false
    let onSeek: (Double) -> Void

    var body: some View {
        Text(attributedText)
            .font(font)
            .foregroundStyle(secondary ? Color.secondary : Color.primary)
            .lineSpacing(5)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .tint(Color.jarvisAccent)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "jarvis-meeting-audio", let time else { return .discarded }
                onSeek(time)
                return .handled
            })
            .help([quote, isPlaying ? "再次点击停止回听" : "点击时间戳回听原话，再次点击停止"].filter { !$0.isEmpty }.joined(separator: "\n"))
    }

    private var attributedText: AttributedString {
        var content = AttributedString(text)
        if isStrikethrough {
            content.strikethroughStyle = .single
        }
        if let time {
            var link = AttributedString("  \(isPlaying ? "■" : "▶") \(MeetingRecordingStyle.formatTimestamp(time))")
            link.link = URL(string: "jarvis-meeting-audio://seek/\(time)")
            link.font = .system(size: 11, weight: .medium, design: .monospaced)
            content.append(link)
        }
        return content
    }
}

extension [MeetingEvidence] {
    /// One deterministic entry point per point/task, at the first cited passage.
    var primaryAudioEvidence: MeetingEvidence? {
        filter { $0.startMs >= 0 && $0.endMs >= $0.startMs }.min { $0.startMs < $1.startMs }
    }
}
