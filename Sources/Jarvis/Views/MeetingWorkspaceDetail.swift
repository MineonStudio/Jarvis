import JarvisDesignSystem
import SwiftUI

private enum MeetingWorkspaceTab: String, CaseIterable, Identifiable {
    case minutes = "纪要"
    case transcript = "逐字稿"
    var id: Self {
        self
    }
}

private enum MeetingDetailTypography {
    static let title = SettingsTypography.pageTitle
    static let sectionTitle = SettingsTypography.cardTitle
    static let pointTitle = SettingsTypography.itemTitle
    static let body = SettingsTypography.itemSubtitle
}

struct MeetingWorkspaceDetail: View {
    @Environment(AppModel.self) private var app
    let record: MeetingRecord
    let search: String
    @State private var tab = MeetingWorkspaceTab.minutes
    @State private var title = ""
    @State private var titleBeforeEditing = ""
    @State private var transcriptQuery = ""
    @State private var showSpeakers = false
    let playback: MeetingPlayback
    @FocusState private var titleFocused: Bool

    private var summary: MeetingSummary? {
        app.displayedMeetingSummary(for: record)
    }

    private var recording: Bool {
        record.id == app.meetingCurrentRecordingID
    }

    private var processing: Bool {
        record.status == .transcribing || record.status == .summarizing
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: JarvisSpacing.itemGap) {
                        header
                        if recording {
                            MeetingLiveRecordingPane(record: record) {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    proxy.scrollTo("meeting-live-latest", anchor: .bottom)
                                }
                            }
                        } else {
                            HStack(spacing: 18) {
                                JarvisCapsuleFilterBar(
                                    items: MeetingWorkspaceTab.allCases, selection: $tab,
                                    accessibilityTitle: "会议视图", title: { $0.rawValue }
                                )
                                Spacer()
                            }.padding(.horizontal, JarvisSpacing.pageInset)
                            if processing {
                                processingBanner
                            }
                            if let message = record.errorMessage,
                               record.status == .failed || record.status == .summaryFailed
                            {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                                    Text(message).font(.callout).textSelection(.enabled)
                                    Spacer()
                                    Button("重试") { app.retryMeetingProcessing(record) }.disabled(
                                        app.meetingActiveProcessingID != nil
                                    )
                                }.padding(16).background(.orange.opacity(0.06))
                            }
                            switch tab {
                            case .minutes: minutes
                            case .transcript: transcript
                            }
                        }
                    }
                }
                .onChange(of: playback.seekRequestID) { _, _ in scrollToRequestedTime(proxy) }
                .onChange(of: tab) { _, _ in scrollToRequestedTime(proxy) }
            }
        }
        .onAppear {
            title = record.title
            applySearch()
        }
        .onChange(of: record.title) { _, value in
            if !titleFocused {
                title = value
            }
        }
        .onChange(of: titleFocused) { _, focused in
            if focused {
                titleBeforeEditing = title
            } else if title != titleBeforeEditing {
                app.updateMeetingTitle(recordID: record.id, title: title)
            } else {
                title = record.title
            }
        }
        .onChange(of: search) { _, _ in applySearch() }
        .sheet(isPresented: $showSpeakers) { MeetingSpeakersSheet(record: record) }
    }

    private func applySearch() {
        if search.isEmpty {
            transcriptQuery = ""
            return
        }
        if record.transcript.contains(where: { $0.text.meetingSearchContains(search) }) {
            tab = .transcript
            transcriptQuery = search
        }
    }

    private func seekEvidence(_ time: Double) {
        playback.toggleSource(at: time)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: JarvisSpacing.controlGap) {
            HStack(alignment: .top, spacing: 16) {
                TextField("会议名称", text: $title)
                    .textFieldStyle(.plain).font(MeetingDetailTypography.title)
                    .accessibilityAddTraits(.isHeader)
                    .focused($titleFocused)
                    .onSubmit {
                        titleFocused = false
                    }
                Spacer(minLength: 0)
                if !recording {
                    Menu {
                        Button("复制纪要") { app.copyMeetingMinutes(record) }.disabled(summary == nil)
                        Divider()
                        Button("导出 Markdown") { app.exportMeetingMarkdown(record) }
                        Button("导出 PDF") { app.exportMeetingPDF(record) }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.title3)
                    }.menuStyle(.borderlessButton).fixedSize()
                }
            }
            HStack(spacing: 14) {
                Text(record.createdAt.formatted(.dateTime.year().month().day().hour().minute()))
                Text(MeetingRecordingStyle.formatDuration(recording ? app.meetingElapsed : record.duration))
                    .monospacedDigit()
                Label(
                    recording ? "录音中" : record.status.title,
                    systemImage: recording ? "record.circle.fill" : "checkmark.circle"
                )
                .foregroundStyle(recording ? .red : .secondary)
            }.font(.system(size: 12)).foregroundStyle(.secondary)
            if !record.speakers.isEmpty {
                MeetingSpeakerTags(
                    speakers: record.speakers, transcript: record.transcript,
                    playbackAvailable: !recording && playback.available,
                    isPreviewing: playback.isPreviewingSpeaker,
                    onPreview: playback.toggleSpeakerPreview,
                    onEdit: { showSpeakers = true }
                )
            }
            if !recording {
                MeetingPlaybackBar(
                    playback: playback, url: app.meetingAudioURL(for: record),
                    revision: app.meetingAudioRevisions[record.id] ?? 0
                )
            }
        }
        .padding(.horizontal, JarvisSpacing.pageInset)
        .padding(.top, JarvisSpacing.panelInset)
    }

    private var processingBanner: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(
                app.meetingActiveProcessingID == record.id ? app.meetingProcessingState.title : "正在完成录音处理…"
            )
            .font(.callout)
            if case let .processing(_, progress) = app.meetingProcessingState, let progress,
               app.meetingActiveProcessingID == record.id
            {
                ProgressView(value: progress).frame(width: 100)
            }
            Spacer()
            if app.meetingActiveProcessingID == record.id {
                Button("停止处理", action: app.cancelMeetingProcessing).buttonStyle(.borderless)
            }
        }.padding(.horizontal, JarvisSpacing.pageInset).padding(.vertical, 13).background(Color.jarvisAccent.opacity(0.06))
    }

    @ViewBuilder private var minutes: some View {
        if let summary {
            VStack(alignment: .leading, spacing: JarvisSpacing.sectionGap) {
                VStack(alignment: .leading, spacing: JarvisSpacing.itemGap) {
                    HStack {
                        Label("会议纪要", systemImage: "sparkles").font(MeetingDetailTypography.sectionTitle)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        Button("重新生成") { app.summarizeMeeting(recordID: record.id, preserveUserEdits: false) }
                            .buttonStyle(.borderless).disabled(processing || app.meetingActiveProcessingID != nil)
                    }
                    MeetingOverviewEditor(recordID: record.id, overview: summary.overview)
                }
                if !summary.points.isEmpty {
                    VStack(alignment: .leading, spacing: JarvisSpacing.itemGap) {
                        Text("议题与讨论").font(MeetingDetailTypography.sectionTitle)
                            .accessibilityAddTraits(.isHeader)
                        VStack(alignment: .leading, spacing: JarvisSpacing.groupGap) {
                            ForEach(summary.points) { point in
                                VStack(alignment: .leading, spacing: JarvisSpacing.controlGap) {
                                    Text(point.title).font(MeetingDetailTypography.pointTitle)
                                        .accessibilityAddTraits(.isHeader).textSelection(.enabled)
                                    MeetingCitedText(
                                        text: point.detail,
                                        time: point.evidence.primaryAudioEvidence.map { Double($0.startMs) / 1000 },
                                        quote: point.evidence.map(\.quote).joined(separator: "\n"),
                                        font: MeetingDetailTypography.body,
                                        isPlaying: playback.isPlayingSource(
                                            at: point.evidence.primaryAudioEvidence.map { Double($0.startMs) / 1000 }
                                        ),
                                        onSeek: seekEvidence
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 820, alignment: .leading).frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, JarvisSpacing.pageInset)
            .padding(.bottom, JarvisSpacing.pageInset)
        } else if !processing {
            VStack(spacing: 16) {
                Image(systemName: "sparkles").font(.system(size: 32, weight: .light)).foregroundStyle(
                    Color.jarvisAccent
                )
                Text(record.transcript.isEmpty ? "录音已保留" : "逐字稿已准备好").font(.title3.weight(.semibold))
                Text(record.transcript.isEmpty ? "重新处理录音，生成逐字稿和会议纪要。" : "使用设置中的大模型整理要点、决议和待办。")
                    .font(.callout).foregroundStyle(.secondary)
                Button(record.transcript.isEmpty ? "处理录音" : "生成纪要") {
                    if record.transcript.isEmpty {
                        app.retryMeetingProcessing(record)
                    } else {
                        app.summarizeMeeting(recordID: record.id)
                    }
                }.buttonStyle(JarvisPrimaryButtonStyle()).disabled(app.meetingActiveProcessingID != nil)
            }.frame(maxWidth: .infinity).padding(40)
        }
    }

    private var transcript: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("在这场会议中查找", text: $transcriptQuery).textFieldStyle(.plain)
                if !transcriptQuery.isEmpty {
                    Button {
                        transcriptQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }.buttonStyle(.plain)
                }
            }.padding(12).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 9))
                .padding(.horizontal, JarvisSpacing.pageInset)
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(
                    record.transcript.filter {
                        transcriptQuery.isEmpty || $0.text.meetingSearchContains(transcriptQuery)
                    }
                ) { segment in
                    MeetingTranscriptRow(
                        segment: segment,
                        speaker: record.speakers.first { $0.id == segment.speakerID },
                        active: playback.isPlaying && playback.position >= segment.startTime
                            && playback.position < segment.endTime,
                        sourceIsPlaying: playback.isPlayingSource, onSeek: playback.toggleSource
                    )
                    .id(segment.id)
                }
            }.padding(.horizontal, JarvisSpacing.pageInset).padding(.vertical, JarvisSpacing.itemGap)
        }
    }

    private func scrollToRequestedTime(_ proxy: ScrollViewProxy) {
        guard tab == .transcript, let time = playback.requestedTime else { return }
        let row =
            record.transcript.first { $0.startTime <= time && $0.endTime > time }
                ?? record.transcript.first { $0.startTime >= time }
        if let row {
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(row.id, anchor: .center) }
        }
    }
}

struct MeetingOverviewEditor: View {
    @Environment(AppModel.self) private var app
    let recordID: UUID
    let overview: String
    @State private var draft = ""
    @FocusState private var focused: Bool
    var body: some View {
        TextField("会议概要", text: $draft, axis: .vertical)
            .textFieldStyle(.plain).font(MeetingDetailTypography.body).lineSpacing(5)
            .focused($focused)
            .onAppear { draft = overview }
            .onChange(of: overview) { _, value in
                if !focused {
                    draft = value
                }
            }
            .onChange(of: focused) { _, value in
                if !value, draft != overview {
                    app.updateMeetingOverview(recordID: recordID, overview: draft)
                }
            }
    }
}

struct MeetingTranscriptRow: View {
    let segment: MeetingTranscriptSegment
    let speaker: MeetingSpeaker?
    let active: Bool
    let sourceIsPlaying: (Double?) -> Bool
    let onSeek: (Double) -> Void
    private var color: Color {
        MeetingSpeakerColors.color(for: speaker?.colorIndex ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(speaker?.name ?? "未标注")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(color)
            MeetingCitedText(
                text: segment.text, time: segment.startTime, secondary: false,
                font: MeetingDetailTypography.body,
                isPlaying: sourceIsPlaying(segment.startTime), onSeek: onSeek
            )
        }
        .padding(12)
        .background(
            active ? Color.jarvisAccent.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 10)
        )
    }
}
