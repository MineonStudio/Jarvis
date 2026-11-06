import SwiftUI

/// Stable three-panel workspace; recording never replaces navigation or the selected detail.
struct MeetingView: View {
    @Environment(AppModel.self) private var app
    @State private var query = ""
    @State private var matches: Set<UUID>?
    @State private var deleteTarget: MeetingRecord?

    private var records: [MeetingRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return app.meetingRecords.filter { trimmed.isEmpty || $0.matchesSearch(trimmed) || matches?.contains($0.id) == true }
    }

    private var selected: MeetingRecord? {
        app.meetingRecords.first { $0.id == app.selectedMeetingID }
    }

    var body: some View {
        JarvisContentArea(
            leadingToolbar: {
                JarvisLeadingToolbarItem(id: "meeting.record") {
                    Button(action: app.toggleMeetingRecording) {
                        HStack(spacing: JarvisSpacing.iconGap) {
                            Image(systemName: app.meetingCurrentRecordingID == nil ? "record.circle" : "stop.fill")
                            Text(app.meetingCurrentRecordingID == nil ? "开始录音" : "结束录音")
                        }
                    }
                    .buttonStyle(JarvisToolbarButtonStyle.menu(tint: app.meetingCurrentRecordingID == nil ? nil : .red))
                    .disabled(!app.meetingModelsReady || app.isStartingMeetingRecording || app.meetingRecorder.isStopping)
                }
            },
            trailingToolbar: {
                ToolbarItem(id: "meeting.import", placement: .automatic) {
                    Button(action: app.importMeetingAudio) {
                        HStack(spacing: JarvisSpacing.iconGap) {
                            Image(systemName: "square.and.arrow.down")
                            Text(app.meetingImportInProgress ? "正在导入…" : "导入音频")
                        }
                    }
                    .buttonStyle(JarvisToolbarButtonStyle.menu())
                    .disabled(!app.meetingModelsReady || app.meetingImportInProgress)
                }
                ToolbarSpacer(.fixed, placement: .automatic)
                ToolbarItem(id: "meeting.search", placement: .automatic) {
                    ClipboardSearchField(text: $query, placeholder: "搜索会议和逐字稿", focusesOnAppear: false)
                }
            },
            content: {
                VStack(spacing: JarvisSpacing.columnGap) {
                    if let error = app.meetingStorageError {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).padding(12)
                    }
                    HStack(spacing: JarvisSpacing.columnGap) {
                        MeetingLibraryPane(records: records, query: query, onDelete: { deleteTarget = $0 })
                            .frame(width: 248)
                            .frame(maxHeight: .infinity)
                            .jarvisModulePanel()
                        Group {
                            if let selected {
                                MeetingSelectedWorkspace(record: selected, search: query)
                                    .id(selected.id)
                            } else {
                                HStack(spacing: JarvisSpacing.columnGap) {
                                    MeetingWelcomePane()
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .jarvisModulePanel()
                                    MeetingTasksPanel(record: nil, items: [], onSeek: { _ in })
                                        .frame(width: 276)
                                        .jarvisModulePanel()
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        )
        .onAppear {
            if app.selectedMeetingID == nil {
                app.selectedMeetingID = app.meetingRecords.first?.id
            }
            loadSelection()
            app.refreshMeetingModelState()
        }
        .onChange(of: app.selectedMeetingID) { _, _ in loadSelection() }
        .task(id: query) {
            matches = nil
            guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            let found = await app.matchingMeetingIDs(searchText: query)
            guard !Task.isCancelled else { return }
            matches = found
        }
        .confirmationDialog("删除这场会议？", isPresented: Binding(get: { deleteTarget != nil }, set: {
            if !$0 {
                deleteTarget = nil
            }
        })) {
            Button("删除会议", role: .destructive) {
                if let deleteTarget {
                    app.deleteMeeting(deleteTarget)
                }; deleteTarget = nil
            }
            Button("取消", role: .cancel) { deleteTarget = nil }
        } message: { Text("录音、逐字稿和纪要将一起移到废纸篓。") }
        .confirmationDialog("把逐字稿发给已配置的 AI 服务？", isPresented: Binding(
            get: { app.meetingTranscriptConsentRecordID != nil },
            set: {
                if !$0 {
                    app.cancelMeetingTranscriptConsent()
                }
            }
        )) {
            Button("生成纪要") { app.confirmMeetingTranscriptConsent() }
            Button("取消", role: .cancel) { app.cancelMeetingTranscriptConsent() }
        } message: { Text("只发送逐字稿文本，录音保留在 Jarvis 中。使用设置中的 \(app.apiProvider.title) · \(app.providerModel)。") }
    }

    private func loadSelection() {
        if let id = app.selectedMeetingID {
            app.ensureMeetingDetailLoaded(id)
        }
    }
}

struct MeetingWelcomePane: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Image(systemName: "waveform.badge.mic").font(.system(size: 42, weight: .light)).foregroundStyle(Color.jarvisAccent)
                VStack(alignment: .leading, spacing: 12) {
                    Text("专心开会，\n把记录交给 Jarvis。")
                        .font(.system(size: 32, weight: .semibold)).lineSpacing(5)
                    Text("边录边转写，分清谁说了什么。会后整理要点与待办，点击原话随时回听。")
                        .font(.system(size: 14)).foregroundStyle(.secondary).lineSpacing(5)
                }
                if !app.meetingModelsReady {
                    MeetingModelSetupCard()
                } else {
                    HStack(spacing: 12) {
                        Button("开始录音", systemImage: "record.circle", action: app.toggleMeetingRecording)
                            .buttonStyle(JarvisPrimaryButtonStyle())
                            .disabled(app.isStartingMeetingRecording || app.meetingRecorder.isStopping)
                        Button("导入录音", systemImage: "square.and.arrow.down", action: app.importMeetingAudio)
                            .buttonStyle(JarvisSecondaryButtonStyle())
                    }
                    Text("快捷键 \(app.meetingShortcut.displayString)").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 520, alignment: .leading)
            .padding(44)
            .frame(maxWidth: .infinity, minHeight: 500, alignment: .center)
        }
    }
}
