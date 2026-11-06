import Combine
import SwiftUI

/// Both content panels address the same player, so a source link never starts a
/// second recording or loses the playback position when the content tab changes.
struct MeetingSelectedWorkspace: View {
    @Environment(AppModel.self) private var app
    let record: MeetingRecord
    let search: String
    @State private var playback = MeetingPlayback()
    private let timer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geometry in
            let sideBySide = geometry.size.width >= 680
            let layout =
                sideBySide
                    ? AnyLayout(HStackLayout(spacing: JarvisSpacing.columnGap))
                    : AnyLayout(VStackLayout(spacing: JarvisSpacing.columnGap))
            layout {
                MeetingWorkspaceDetail(record: record, search: search, playback: playback)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .jarvisModulePanel()
                MeetingTasksPanel(
                    record: record, items: app.displayedMeetingSummary(for: record)?.actionItems ?? [],
                    sourceIsPlaying: playback.isPlayingSource, onSeek: playback.toggleSource
                )
                .frame(width: sideBySide ? 276 : nil, height: sideBySide ? nil : 210)
                .frame(maxWidth: sideBySide ? nil : .infinity, maxHeight: sideBySide ? .infinity : nil)
                .jarvisModulePanel()
            }
        }
        .task(
            id:
            "\(app.meetingAudioURL(for: record)?.path ?? ""):\(app.meetingAudioRevisions[record.id] ?? 0)"
        ) {
            playback.load(app.meetingAudioURL(for: record))
        }
        .onReceive(timer) { _ in
            if playback.isPlaying {
                playback.refresh()
            }
        }
        .onDisappear { playback.stop() }
    }
}

struct MeetingTasksPanel: View {
    let record: MeetingRecord?
    let items: [MeetingActionItem]
    var sourceIsPlaying: (Double?) -> Bool = { _ in false }
    let onSeek: (Double) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Text("待办事项").font(.system(size: 17, weight: .semibold))
                    if !items.isEmpty {
                        Text("\(items.filter(\.isCompleted).count) / \(items.count)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(JarvisSpacing.panelInset)
                .accessibilityAddTraits(.isHeader)
                if let record, !items.isEmpty {
                    MeetingActionChecklist(
                        record: record, items: items, sourceIsPlaying: sourceIsPlaying, onSeek: onSeek
                    )
                    .padding(.horizontal, JarvisSpacing.panelInset)
                    .padding(.bottom, JarvisSpacing.panelInset)
                } else {
                    ContentUnavailableView(
                        "暂无待办", systemImage: "checklist",
                        description: Text(record == nil ? "选择一场会议查看待办。" : "生成纪要后，会议中的行动项会显示在这里。")
                    )
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
