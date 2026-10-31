import AppKit
import SwiftUI

struct ScreenRecordingView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedRecordID: UUID?
    @State private var gridZoom: HistoryGridZoomLevel = .regular
    @State private var selectedTimeFilter: ScreenshotTimeFilter = .threeDays
    @State private var pendingDelete: ScreenRecordingRecord?
    @State private var pendingRename: ScreenRecordingRecord?
    @State private var newTitle = ""
    private var recorder: ScreenRecordingCoordinator {
        app.screenRecording
    }

    private var filteredRecords: [ScreenRecordingRecord] {
        recorder.records.filter {
            $0.completed && selectedTimeFilter.matches(date: $0.createdAt)
        }
    }

    private var selectedRecord: ScreenRecordingRecord? {
        guard let selectedRecordID else { return nil }
        return filteredRecords.first { $0.id == selectedRecordID }
    }

    var body: some View {
        JarvisContentArea(
            leadingToolbar: {
                ScreenshotTimeFilterBar(selectedFilter: $selectedTimeFilter)
            },
            trailingToolbar: {
                ToolbarSpacer(.fixed, placement: .automatic)
                ToolbarItem(id: "screen-recording.grid-zoom", placement: .automatic) {
                    HistoryGridZoomControl(selection: $gridZoom)
                }
                ToolbarSpacer(.fixed, placement: .automatic)
                ToolbarItem(id: "screen-recording.actions", placement: .automatic) {
                    actionToolbar
                }
            },
            content: { content.jarvisModulePanel() }
        )
        .onChange(of: selectedTimeFilter) { _, _ in selectedRecordID = nil }
        .onChange(of: filteredRecords.map(\.id)) { _, ids in
            if let selectedRecordID, !ids.contains(selectedRecordID) {
                self.selectedRecordID = nil
            }
        }
        .confirmationDialog("删除这段屏幕录制？", isPresented: Binding(get: { pendingDelete != nil }, set: {
            if !$0 {
                pendingDelete = nil
            }
        })) {
            Button("移到废纸篓并删除记录", role: .destructive) {
                if let record = pendingDelete {
                    recorder.delete(record)
                }; pendingDelete = nil
            }
        } message: { Text("视频会移到废纸篓，录制记录与恢复片段会被删除。") }
        .alert("重命名", isPresented: Binding(get: { pendingRename != nil }, set: {
            if !$0 {
                pendingRename = nil
            }
        })) {
            TextField("标题", text: $newTitle)
            Button("取消", role: .cancel) { pendingRename = nil }
            Button("保存") {
                if let record = pendingRename {
                    recorder.rename(record, title: newTitle)
                }; pendingRename = nil
            }
        }
    }

    private var actionToolbar: some View {
        HStack(spacing: 2) {
            JarvisToolbarIconButton(
                systemName: "eye",
                help: "查看",
                isEnabled: selectedRecord?.exists == true
            ) {
                guard let selectedRecord else { return }
                open(selectedRecord)
            }
            .accessibilityLabel("查看")
            JarvisToolbarIconButton(
                systemName: "doc.on.doc",
                help: "复制",
                isEnabled: selectedRecord?.exists == true
            ) {
                guard let selectedRecord else { return }
                copy(selectedRecord)
            }
            .accessibilityLabel("复制")
            JarvisToolbarIconButton(
                systemName: "trash",
                help: "删除",
                tint: .red.opacity(0.82),
                isEnabled: selectedRecord != nil
            ) {
                pendingDelete = selectedRecord
            }
            .accessibilityLabel("删除")
        }
        .padding(4)
        .frame(height: HistoryGridMetrics.topControlHeight)
    }

    private var content: some View {
        VStack(spacing: 12) {
            if let message = recorder.message {
                HStack(alignment: .top) {
                    Image(systemName: "info.circle")
                    Text(message).font(.callout).textSelection(.enabled)
                    Spacer()
                    Button { recorder.message = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }.padding(12).background(Color.jarvisInsetSurface, in: RoundedRectangle(cornerRadius: 10)).padding(.horizontal, 12)
            }
            if !recorder.recoverableRecords.isEmpty {
                recoverySection.padding(.horizontal, 12)
            }
            if filteredRecords.isEmpty {
                ContentUnavailableView {
                    Label(selectedTimeFilter == .all ? "屏幕录制" : "没有匹配的录制", systemImage: "record.circle")
                } description: {
                    Text(selectedTimeFilter == .all ? "录制整个屏幕、指定窗口，或自定义区域。" : "尝试更改时间筛选。")
                } actions: {
                    Button("新建录制") { recorder.present() }.buttonStyle(.borderedProminent).disabled(recorder.isActive)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                historyGrid
                    .transition(JarvisMotion.contentTransition(reduceMotion: reduceMotion))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(JarvisMotion.animation(JarvisMotion.content, reduceMotion: reduceMotion), value: selectedTimeFilter)
        .animation(JarvisMotion.animation(JarvisMotion.content, reduceMotion: reduceMotion), value: filteredRecords.map(\.id))
    }

    private var historyGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(
                    .adaptive(minimum: gridZoom.cardWidth, maximum: .infinity),
                    spacing: HistoryGridMetrics.clipboardGridSpacing
                )],
                alignment: .leading,
                spacing: HistoryGridMetrics.clipboardGridSpacing
            ) {
                ForEach(filteredRecords) { record in
                    ScreenRecordingHistoryCard(
                        record: record,
                        thumbnail: recorder.repository.thumbnail(record.id),
                        isSelected: selectedRecordID == record.id,
                        maxPixelSize: gridZoom.thumbnailPixelSize,
                        enablesHoverZoom: gridZoom.enablesHoverZoom,
                        onSelect: { selectedRecordID = record.id },
                        onPlay: { open(record) },
                        onCopy: { copy(record) }
                    )
                    .equatable()
                    .contextMenu { actions(record) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(HistoryGridMetrics.historyPanelInset)
        }
        .animation(JarvisMotion.animation(JarvisMotion.content, reduceMotion: reduceMotion), value: gridZoom)
    }

    private var recoverySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("未完成的录制 · 已保留临时片段", systemImage: "arrow.counterclockwise.circle").font(.headline)
            ForEach(recorder.recoverableRecords) { record in
                HStack {
                    Text(JarvisHistoryDateFormatting.string(from: record.createdAt)).lineLimit(1)
                    Spacer()
                    if record.exists {
                        Button("查看已输出文件") { NSWorkspace.shared.open(record.fileURL) }
                    }
                    Button("恢复") { Task { await recorder.recover(record) } }
                    Button("另存恢复…") { Task { await recorder.relocateAndRecover(record) } }
                    Button(role: .destructive) { pendingDelete = record } label: { Image(systemName: "trash") }
                }.disabled(recorder.isActive)
            }
        }.padding(12).background(Color.jarvisInsetSurface, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func actions(_ record: ScreenRecordingRecord) -> some View {
        Button("播放") { open(record) }.disabled(!record.exists)
        Button("重命名…") { newTitle = record.title; pendingRename = record }
        Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([record.fileURL]) }.disabled(!record.exists)
        if !record.exists {
            Button("重新定位文件…") { Task { await recorder.locate(record) } }
        }
        Button("复制文件") { copy(record) }.disabled(!record.exists)
        ShareLink(item: record.fileURL) { Text("分享…") }.disabled(!record.exists)
        Divider()
        Button("删除…", role: .destructive) { pendingDelete = record }
    }

    private func open(_ record: ScreenRecordingRecord) {
        if record.exists {
            recorder.videoPreviewController.show(url: record.fileURL)
        } else {
            recorder.message = "文件不存在或已被移动：\(record.filePath)"
        }
    }

    private func copy(_ record: ScreenRecordingRecord) {
        guard record.exists else {
            recorder.message = "文件不存在或已被移动：\(record.filePath)"
            return
        }
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.writeObjects([record.fileURL as NSURL]) {
            app.showToast("已复制视频")
        }
    }
}
