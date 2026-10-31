import AppKit
import SwiftUI

struct ScreenRecordingHistoryCard: View, Equatable {
    let record: ScreenRecordingRecord
    let thumbnail: URL
    let isSelected: Bool
    let maxPixelSize: Int
    let enablesHoverZoom: Bool
    let onSelect: () -> Void
    let onPlay: () -> Void
    let onCopy: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: NSImage?
    @State private var isHovered = false

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.record == rhs.record && lhs.thumbnail == rhs.thumbnail && lhs.isSelected == rhs.isSelected
            && lhs.maxPixelSize == rhs.maxPixelSize && lhs.enablesHoverZoom == rhs.enablesHoverZoom
    }

    private var thumbnailCacheKey: String {
        "\(record.id.uuidString)|\(record.filePath)|\(record.byteCount)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HistoryGridMetrics.clipboardContentSpacing) {
            cardBody
            metadataRow
        }
        .contentShape(RoundedRectangle(cornerRadius: HistoryGridMetrics.clipboardCornerRadius, style: .continuous))
        .onTapGesture(count: 2, perform: onPlay)
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            guard hovering != isHovered else { return }
            withAnimation(JarvisMotion.animation(JarvisMotion.content, reduceMotion: reduceMotion)) {
                isHovered = hovering
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("屏幕录制，\(MeetingRecordingStyle.formatDuration(record.duration))，\(JarvisHistoryDateFormatting.string(from: record.createdAt))")
        .accessibilityValue(isSelected ? "已选中" : "未选中")
        .accessibilityHint("点击选择，双击播放；可以拖到 Finder 或其他应用导出视频")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "播放", onPlay)
        .accessibilityAction(named: "复制", onCopy)
        .task(id: "\(thumbnailCacheKey)|\(maxPixelSize)") { await loadThumbnail() }
    }

    private var previewArea: some View {
        Color.clear
            .aspectRatio(HistoryGridLayout.aspectRatio, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                ZStack {
                    Rectangle().fill(Color.jarvisInsetSurface)
                    if let image {
                        Image(nsImage: image).interpolation(.medium).resizable().scaledToFit()
                    } else {
                        Image(systemName: "video")
                            .font(.largeTitle)
                            .foregroundStyle(Color.jarvisTextSecondary)
                    }
                }
            }
            .clipped()
            .onDrag {
                record.exists ? NSItemProvider(object: record.fileURL as NSURL) : NSItemProvider()
            }
    }

    private var cardBody: some View {
        HistoryCardChrome(preview: previewArea, isSelected: isSelected, enablesHoverZoom: enablesHoverZoom)
            .overlay(alignment: .bottomTrailing) { actionOverlay }
            .clipShape(RoundedRectangle(cornerRadius: HistoryGridMetrics.clipboardCornerRadius, style: .continuous))
    }

    @ViewBuilder
    private var actionOverlay: some View {
        if isHovered {
            HStack(spacing: 6) {
                Button(action: onPlay) { Text("播放").lineLimit(1).fixedSize(horizontal: true, vertical: false) }
                    .buttonStyle(JarvisCardActionPillButtonStyle())
                    .accessibilityLabel("播放视频")
                Button(action: onCopy) { Text("复制").lineLimit(1).fixedSize(horizontal: true, vertical: false) }
                    .buttonStyle(JarvisCardActionPillButtonStyle())
                    .accessibilityLabel("复制视频")
            }
            .disabled(!record.exists)
            .padding(8)
            .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: 8)))
        }
    }

    private var metadataRow: some View {
        HStack(spacing: 6) {
            Text(MeetingRecordingStyle.formatDuration(record.duration))
                .font(JarvisTypography.captionEmphasis)
                .foregroundStyle(Color.jarvisTextSecondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(JarvisHistoryDateFormatting.string(from: record.createdAt))
                .font(JarvisTypography.caption)
                .foregroundStyle(Color.jarvisTextSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: HistoryGridMetrics.clipboardMetadataHeight)
    }

    private func loadThumbnail() async {
        if let cached = JarvisThumbnailCache.cached(fileURL: thumbnail, maxPixelSize: maxPixelSize, token: thumbnailCacheKey) {
            image = cached
        }
        // 导出后缩略图异步生成；缓存不记录失败，等待时仍可再次读取。
        for _ in 0 ..< 8 {
            let loaded = await JarvisThumbnailCache.loadAsync(fileURL: thumbnail, maxPixelSize: maxPixelSize, token: thumbnailCacheKey)
            guard !Task.isCancelled else { return }
            if let loaded {
                image = loaded
                return
            }
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
        }
    }
}
