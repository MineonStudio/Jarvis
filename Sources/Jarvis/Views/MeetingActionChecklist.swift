import SwiftUI

struct MeetingActionChecklist: View {
    @Environment(AppModel.self) private var app
    let record: MeetingRecord
    let items: [MeetingActionItem]
    let sourceIsPlaying: (Double?) -> Bool
    let onSeek: (Double) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(items) { item in
                HStack(alignment: .top, spacing: 12) {
                    Button {
                        app.setMeetingActionItemCompleted(recordID: record.id, actionItemID: item.id, isCompleted: !item.isCompleted)
                    } label: {
                        Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 19)).foregroundStyle(item.isCompleted ? Color.jarvisAccent : .secondary)
                    }.buttonStyle(.plain).accessibilityLabel(item.isCompleted ? "标为未完成" : "标为已完成")
                    VStack(alignment: .leading, spacing: 8) {
                        MeetingCitedText(
                            text: item.task,
                            time: item.evidence.primaryAudioEvidence.map { Double($0.startMs) / 1000 },
                            quote: item.evidence.map(\.quote).joined(separator: "\n"),
                            secondary: false,
                            isPlaying: sourceIsPlaying(item.evidence.primaryAudioEvidence.map { Double($0.startMs) / 1000 }),
                            isStrikethrough: item.isCompleted,
                            onSeek: onSeek
                        )
                        Text("\(item.ownerLabel) · \(item.dueDisplayLabel(meetingDate: record.createdAt))")
                            .font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Spacer(minLength: 0)
                }.padding(14).background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MeetingSpeakersSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let record: MeetingRecord
    @State private var names: [String: String] = [:]
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("说话人").font(.title2.weight(.semibold))
            Text("根据声音自动分组。填写姓名后，逐字稿和待办中的对应称呼会一同更新。")
                .font(.callout).foregroundStyle(.secondary)
            ForEach(record.speakers) { speaker in
                HStack {
                    Image(systemName: "person.crop.circle").foregroundStyle(.secondary)
                    TextField(speaker.name, text: Binding(get: { names[speaker.id] ?? speaker.name }, set: { names[speaker.id] = $0 }))
                    Menu("合并") {
                        ForEach(record.speakers.filter { $0.id != speaker.id }) { target in
                            Button("合并到 \(target.name)") {
                                app.mergeMeetingSpeakers(recordID: record.id, sourceSpeakerID: speaker.id, into: target.id)
                                dismiss()
                            }
                        }
                    }.fixedSize().disabled(record.speakers.count < 2)
                }
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") {
                    for (id, name) in names {
                        app.renameMeetingSpeaker(recordID: record.id, speakerID: id, name: name)
                    }
                    dismiss()
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 450)
    }
}
