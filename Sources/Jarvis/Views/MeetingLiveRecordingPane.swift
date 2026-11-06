import SwiftUI

struct MeetingLiveRecordingPane: View {
    @Environment(AppModel.self) private var app
    let record: MeetingRecord
    let onFollowLatest: () -> Void
    @State private var followsLatest = true
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Circle().fill(.red).frame(width: 8, height: 8)
                Text(MeetingRecordingStyle.formatDuration(app.meetingElapsed)).font(
                    .system(size: 25, weight: .medium, design: .monospaced)
                )
                MeetingAudioLevelBars(levels: app.meetingLevelHistory, isPaused: app.meetingRecordingPaused)
                    .frame(width: 110)
                Spacer()
                Text(app.meetingRecordingPaused ? "已暂停" : "边录边转写").font(.callout).foregroundStyle(
                    .secondary
                )
                Button {
                    if app.meetingRecordingPaused {
                        app.resumeMeetingRecording()
                    } else {
                        app.pauseMeetingRecording()
                    }
                } label: {
                    Image(systemName: app.meetingRecordingPaused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(.borderless).help(app.meetingRecordingPaused ? "继续录音" : "暂停录音")
            }.padding(22).background(Color.red.opacity(0.04))
            HStack {
                Text("实时文字").font(.headline)
                Text("结束后统一区分说话人").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Toggle("跟随最新", isOn: $followsLatest).toggleStyle(.checkbox).font(.caption)
            }.padding(.horizontal, 28).padding(.top, 22)
            LazyVStack(alignment: .leading, spacing: 18) {
                if app.meetingLiveLines.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("正在听，文字会陆续出现在这里。")
                        Text("每段约 10–30 秒，按讲话停顿识别。")
                            .font(.callout).foregroundStyle(.secondary)
                    }.padding(.vertical, 35)
                }
                ForEach(Array(app.meetingLiveLines.enumerated()), id: \.offset) { index, line in
                    HStack(alignment: .top, spacing: 16) {
                        Text(MeetingRecordingStyle.formatTimestamp(Double(line.start_ms) / 1000))
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).frame(
                                width: 50
                            )
                        Text(line.text).font(.system(size: 15)).lineSpacing(6).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.id(index)
                }
                Color.clear.frame(height: 1).id("meeting-live-latest")
            }.padding(28)
                .onChange(of: app.meetingLiveLines.last?.start_ms) { _, _ in
                    if followsLatest {
                        onFollowLatest()
                    }
                }
            HStack {
                Label("录音保存在 Jarvis 中", systemImage: "lock.shield")
                Spacer()
                Text(record.resolvedCaptureMode == .dual ? "系统声音 + 麦克风" : record.resolvedCaptureMode.title)
            }.font(.system(size: 11)).foregroundStyle(.secondary).padding(20)
        }
    }
}
