import AppKit
import SwiftUI

struct ScreenRecordingHistoryCard: View, Equatable {
    let record: ScreenRecordingRecord
    let thumbnail: URL
    let isSelected: Bool
    let cardSize: CGSize
    let enablesHoverZoom: Bool
    let onClick: (Int) -> Void
    let onSelect: () -> Void
    let onPlay: () -> Void
    let onCopy: () -> Void
    @State private var image: NSImage?

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.record == rhs.record && lhs.thumbnail == rhs.thumbnail && lhs.isSelected == rhs.isSelected
            && lhs.cardSize == rhs.cardSize && lhs.enablesHoverZoom == rhs.enablesHoverZoom
    }

    private var thumbnailCacheKey: String {
        "\(record.id.uuidString)|\(record.filePath)|\(record.byteCount)"
    }

    private var maxPixelSize: Int {
        // Group nearby sizes so dragging the window does not repeatedly reload thumbnails.
        let longestEdge = max(cardSize.width, cardSize.height)
        let pixels = (longestEdge * 2 / 64).rounded(.up) * 64
        return Int(min(640, max(160, pixels)))
    }

    private var duration: String {
        MeetingRecordingStyle.formatDuration(record.duration)
    }

    private var timestamp: String {
        JarvisHistoryDateFormatting.string(from: record.createdAt)
    }

    var body: some View {
        GalleryCard(
            size: cardSize,
            isSelected: isSelected,
            enablesHoverZoom: enablesHoverZoom,
            onClick: onClick,
            preview: { previewArea },
            leading: {
                Label {
                    Text(duration)
                } icon: {
                    Image(systemName: "video.fill").font(.system(size: 9, weight: .semibold))
                }
            },
            trailing: { Text(timestamp) }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("屏幕录制，\(duration)，\(timestamp)")
        .accessibilityHint(isSelected ? "再次点击取消选择，双击播放" : "点击选择，双击播放")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, onSelect)
        .accessibilityAction(named: "播放", onPlay)
        .accessibilityAction(named: "复制", onCopy)
        .task(id: "\(thumbnailCacheKey)|\(maxPixelSize)") { await loadThumbnail() }
    }

    private var previewArea: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                ZStack {
                    Color.clear.jarvisPanelBackground(cornerRadius: 0)
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
