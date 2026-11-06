import SwiftUI

struct MeetingLibraryPane: View {
    @Environment(AppModel.self) private var app
    let records: [MeetingRecord]
    let query: String
    let onDelete: (MeetingRecord) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("会议记录")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(JarvisSpacing.panelInset)
                    .accessibilityAddTraits(.isHeader)

                if records.isEmpty {
                    ContentUnavailableView(
                        query.isEmpty ? "还没有会议" : "没有搜索结果",
                        systemImage: query.isEmpty ? "waveform" : "magnifyingglass",
                        description: Text(query.isEmpty ? "录一场会议，或导入已有录音。" : "试试会议名称或会上说过的话。")
                    )
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    LazyVStack(spacing: JarvisMetrics.sidebarItemSpacing) {
                        ForEach(records) { record in
                            MeetingLibraryRow(record: record, isSelected: app.selectedMeetingID == record.id) {
                                app.selectedMeetingID = record.id
                            }
                            .contextMenu {
                                Button("复制纪要") { app.copyMeetingMinutes(record) }
                                Button("导出 Markdown") { app.exportMeetingMarkdown(record) }
                                Button("导出 PDF") { app.exportMeetingPDF(record) }
                                Divider()
                                Button("删除会议", role: .destructive) { onDelete(record) }
                                    .disabled(
                                        record.status == .recording || app.meetingRecorder.isStopping
                                            || app.meetingFinalizingIDs.contains(record.id)
                                    )
                            }
                        }
                    }
                    .padding(.horizontal, JarvisMetrics.sidebarContentPadding)
                    .padding(.bottom, JarvisMetrics.sidebarContentPadding)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct MeetingLibraryRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let record: MeetingRecord
    let isSelected: Bool
    let action: () -> Void
    @State private var isHighlighted = false

    var body: some View {
        let accentColor = app.accentColorPreference.resolvedColor
        Button {
            withAnimation(
                JarvisMotion.animation(JarvisMotion.sidebarSelection, reduceMotion: reduceMotion), action
            )
        } label: {
            HStack(spacing: JarvisSpacing.controlGap) {
                Text(record.title)
                    .font(isSelected ? JarvisTypography.controlEmphasis : JarvisTypography.control)
                    .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.74))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(
                    MeetingRecordingStyle.formatDuration(
                        record.id == app.meetingCurrentRecordingID ? app.meetingElapsed : record.duration
                    )
                )
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary)
                .fixedSize()
            }
            .frame(
                maxWidth: .infinity,
                minHeight: JarvisMetrics.sidebarRowHeight,
                maxHeight: JarvisMetrics.sidebarRowHeight,
                alignment: .leading
            )
            .padding(.horizontal, JarvisSpacing.controlGap)
            .background {
                Capsule()
                    .fill(
                        isSelected
                            ? accentColor.opacity(0.82) : (isHighlighted ? JarvisMotion.hoverPillTint : .clear)
                    )
                    .scaleEffect(isSelected || isHighlighted ? 1 : 0.96)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(
            maxWidth: .infinity,
            minHeight: JarvisMetrics.sidebarRowHeight,
            maxHeight: JarvisMetrics.sidebarRowHeight,
            alignment: .leading
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(JarvisMotion.animation(JarvisMotion.hover, reduceMotion: reduceMotion)) {
                isHighlighted = hovering
            }
        }
        .animation(
            JarvisMotion.animation(JarvisMotion.sidebarSelection, reduceMotion: reduceMotion),
            value: isSelected
        )
        .animation(
            JarvisMotion.animation(JarvisMotion.hover, reduceMotion: reduceMotion), value: isHighlighted
        )
        .accessibilityLabel("\(record.title)，\(MeetingRecordingStyle.formatDuration(record.duration))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(record.title)
    }
}
