import AppKit

@MainActor
enum MeetingMinutesClipboard {
    static func document(for record: MeetingRecord) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        func append(_ text: String, size: CGFloat = 12, weight: NSFont.Weight = .regular, secondary: Bool = false) {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 3
            paragraph.paragraphSpacing = size >= 16 ? 12 : 7
            result.append(NSAttributedString(string: text + "\n", attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: weight),
                .foregroundColor: secondary ? NSColor.darkGray : NSColor.black,
                .paragraphStyle: paragraph
            ]))
        }
        func evidence(_ items: [MeetingEvidence]) {
            for item in items {
                let stamp = MeetingRecordingStyle.formatTimestamp(Double(item.startMs) / 1000)
                append("出处 \(stamp)  \(item.quote)", size: 10, secondary: true)
            }
        }
        append(record.title, size: 22, weight: .bold)
        append("时间：\(record.createdAt.formatted(date: .long, time: .shortened))", size: 10, secondary: true)
        append("时长：\(MeetingRecordingStyle.formatDuration(record.duration))", size: 10, secondary: true)
        append("状态：\(record.status.title)", size: 10, secondary: true)
        if !record.speakers.isEmpty {
            append("说话人：\(record.speakers.map(\.name).joined(separator: "、"))", size: 10, secondary: true)
        }
        if let summary = record.summary {
            append("会议纪要", size: 16, weight: .bold)
            if !summary.overview.isEmpty {
                append(summary.overview)
            }
            if !summary.points.isEmpty {
                append("议题与讨论", size: 16, weight: .bold)
                for point in summary.points {
                    append(point.title, size: 13, weight: .semibold)
                    if !point.detail.isEmpty {
                        append(point.detail)
                    }
                    evidence(point.evidence)
                }
            }
            if !summary.actionItems.isEmpty {
                append("待办事项", size: 16, weight: .bold)
                for item in summary.actionItems {
                    append("\(item.isCompleted ? "☑" : "☐") \(item.task)", weight: .medium)
                    append("负责人：\(item.ownerLabel)　期限：\(item.dueDisplayLabel(meetingDate: record.createdAt))", size: 10, secondary: true)
                    evidence(item.evidence)
                }
            }
        }
        return result
    }

    static func write(_ record: MeetingRecord, to pasteboard: NSPasteboard) throws -> Bool {
        let content = document(for: record)
        let range = NSRange(location: 0, length: content.length)
        let rtf = try content.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        let item = NSPasteboardItem()
        item.setData(rtf, forType: .rtf)
        if let html = try? content.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.html]) {
            item.setData(html, forType: .html)
        }
        item.setString(content.string, forType: .string)
        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }
}
