import AppKit
import SwiftUI

struct ScreenshotView: View {
    @Environment(AppModel.self) private var app
    @State private var selectedTimeFilter: ScreenshotTimeFilter = .threeDays
    @State private var searchText = ""
    @State private var selection = GallerySelection<UUID>()
    @State private var gridZoom: HistoryGridZoomLevel = .regular
    @State private var toolbarAlignment = HistoryToolbarAlignment()

    var body: some View {
        JarvisContentArea(
            horizontalContentPadding: 0,
            bottomContentPadding: 0,
            leadingToolbar: {
                ScreenshotTimeFilterBar(selectedFilter: $selectedTimeFilter, alignment: toolbarAlignment)
            },
            trailingToolbar: {
                ToolbarSpacer(.fixed, placement: .automatic)
                ToolbarItem(id: "screenshot.grid-zoom", placement: .automatic) {
                    HistoryGridZoomControl(selection: $gridZoom)
                }
                ToolbarSpacer(.fixed, placement: .automatic)
                ToolbarItem(id: "screenshot.actions", placement: .automatic) {
                    ScreenshotHistoryActionToolbar(
                        selectedItem: selectedItem,
                        onClearSelection: { selection.clear() }
                    )
                }
                ToolbarSpacer(.fixed, placement: .automatic)
                ToolbarItem(id: "screenshot.search", placement: .automatic) {
                    ClipboardSearchField(
                        text: $searchText,
                        placeholder: ScreenshotTimeFilterLogic.searchPlaceholder,
                        focusesOnAppear: false
                    )
                    .background(HistoryToolbarFrameProbe(alignment: toolbarAlignment, edge: .trailing))
                }
            },
            content: {
                GeometryReader { viewport in
                    JarvisBackToTopScroll("返回截图列表顶部", id: "screenshot-scroll-top") {
                        ScreenshotHistorySection(
                            selectedTimeFilter: $selectedTimeFilter,
                            searchText: searchText,
                            selection: $selection,
                            gridZoom: gridZoom,
                            availableWidth: viewport.size.width - toolbarAlignment.leadingInset - toolbarAlignment.trailingInset
                        )
                        .padding(.leading, toolbarAlignment.leadingInset)
                        .padding(.trailing, toolbarAlignment.trailingInset)
                        .padding(.bottom, HistoryGridMetrics.historyPanelInset)
                        .galleryBackground(minHeight: viewport.size.height) { selection.clear() }
                    }
                }
                .background(HistoryToolbarFrameProbe(alignment: toolbarAlignment, edge: .content))
            }
        )
    }

    private var selectedItem: ScreenshotHistoryItem? {
        guard let selectedItemID = selection.selectedID else { return nil }
        return app.screenshotHistory.first { $0.id == selectedItemID }
    }
}

struct ScreenshotHistoryActionToolbar: View {
    @Environment(AppModel.self) private var app
    let selectedItem: ScreenshotHistoryItem?
    let onClearSelection: () -> Void
    @State private var showingDeleteConfirmation = false

    var body: some View {
        HStack(spacing: JarvisSpacing.hairline) {
            JarvisToolbarIconButton(
                systemName: "eye",
                help: "查看",
                isEnabled: selectedItem != nil
            ) {
                guard let selectedItem else { return }
                app.showScreenshotHistoryPreview(selectedItem)
            }
            JarvisToolbarIconButton(
                systemName: "pencil",
                help: "编辑",
                isEnabled: selectedItem != nil
            ) {
                guard let selectedItem else { return }
                app.editScreenshotHistory(selectedItem)
            }
            JarvisToolbarIconButton(
                systemName: "doc.on.doc",
                help: "复制",
                isEnabled: selectedItem != nil
            ) {
                guard let selectedItem else { return }
                app.copyScreenshotHistory(selectedItem)
            }
            JarvisToolbarIconButton(
                systemName: "trash",
                help: "删除",
                tint: .red.opacity(0.82),
                isEnabled: selectedItem != nil
            ) {
                showingDeleteConfirmation = true
            }
        }
        .padding(.horizontal, JarvisToolbarMetrics.iconClusterPadding)
        .frame(height: HistoryGridMetrics.topControlHeight)
        .confirmationDialog(
            "删除这张截图？",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                guard let selectedItem else { return }
                app.deleteScreenshotHistory(selectedItem)
                onClearSelection()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后无法恢复。")
        }
    }
}

enum HistoryGridZoomLevel: Int, CaseIterable, Sendable {
    case compact
    case small
    case regular
    case large
    case extraLarge

    private var widthScale: CGFloat {
        switch self {
        case .compact: 0.72
        case .small: 0.86
        case .regular: 1
        case .large: 1.16
        case .extraLarge: 1.34
        }
    }

    var cardWidth: CGFloat {
        HistoryGridMetrics.clipboardCardWidth * widthScale
    }

    var cardHeight: CGFloat {
        cardWidth * 9 / 16
    }

    /// 2× 屏上刚好盖住卡片；最小值一屏格子多，用更小的解码尺寸。
    var thumbnailPixelSize: Int {
        Int(min(512, max(160, (cardWidth * 2).rounded())))
    }

    var enablesHoverZoom: Bool {
        rawValue >= Self.regular.rawValue
    }

    var canZoomOut: Bool {
        rawValue > Self.compact.rawValue
    }

    var canZoomIn: Bool {
        rawValue < Self.extraLarge.rawValue
    }

    var zoomedOut: Self {
        Self(rawValue: rawValue - 1) ?? self
    }

    var zoomedIn: Self {
        Self(rawValue: rawValue + 1) ?? self
    }
}

struct HistoryGridZoomControl: View {
    @Binding var selection: HistoryGridZoomLevel

    var body: some View {
        JarvisToolbarZoomControl(
            canZoomOut: selection.canZoomOut,
            canZoomIn: selection.canZoomIn,
            zoomOutLabel: "缩小宫格",
            zoomInLabel: "放大宫格",
            onZoomOut: { selection = selection.zoomedOut },
            onZoomIn: { selection = selection.zoomedIn }
        )
    }
}

enum HistoryGridMetrics {
    static let imageSpacing = JarvisSpacing.controlGap
    static let historyPanelInset = JarvisSpacing.gridGap
    static let historyFilterToGridSpacing = JarvisSpacing.gridGap

    // Both history galleries use the same 16:9 landscape panel and controls.
    //
    // 基准宽度（用户定的 200；壁纸模块那边一格约 282×190，这里比它小一档，
    // 一屏能多放一张）。想换大小改这一个数，缩放档位按它成比例走。
    static let historyCardBaseWidth: CGFloat = 200
    static let historyCardBasePadding = JarvisSpacing.rowInset
    static let clipboardCardWidth: CGFloat = historyCardBaseWidth * 1.1
    static let clipboardCardHeight: CGFloat = clipboardCardWidth * 9 / 16
    static let clipboardCardPadding = JarvisSpacing.iconGap
    static let clipboardPreviewHeight: CGFloat = clipboardCardHeight
    static let clipboardContentSpacing = JarvisSpacing.textGap
    static let clipboardMetadataHeight: CGFloat = 16
    static let clipboardSearchFieldWidth = JarvisToolbarMetrics.searchFieldWidth
    static let clipboardActionButtonSize = JarvisToolbarMetrics.controlSize
    static let clipboardPreviewHoverScale: CGFloat = 1.08
    static let clipboardCornerRadius: CGFloat = 12
    static let clipboardGridSpacing = JarvisSpacing.gridGap
    static let topControlHeight = JarvisToolbarMetrics.controlSize
    static let clipboardSearchFieldHeight: CGFloat = topControlHeight
    static let clipboardFilterToGridSpacing = JarvisSpacing.gridGap
    static let screenshotFilterBarHeight: CGFloat = topControlHeight
}

struct ScreenshotHistorySection: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selectedTimeFilter: ScreenshotTimeFilter
    let searchText: String
    @Binding var selection: GallerySelection<UUID>
    let gridZoom: HistoryGridZoomLevel
    let availableWidth: CGFloat

    private var filteredItems: [ScreenshotHistoryItem] {
        ScreenshotTimeFilterLogic.filteredItems(
            from: app.screenshotHistory,
            filter: selectedTimeFilter,
            searchText: searchText,
            imageTextByHash: app.imageTextByHash
        )
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HistoryGridMetrics.historyFilterToGridSpacing) {
            if filteredItems.isEmpty {
                JarvisEmptyState(
                    icon: "photo.on.rectangle",
                    title: emptyTitle,
                    message: emptyMessage
                )
                .transition(JarvisMotion.contentTransition(reduceMotion: reduceMotion))
            } else {
                FixedRatioGallery(
                    items: filteredItems, availableWidth: availableWidth, targetWidth: gridZoom.cardWidth,
                    card: { item, size in
                        ScreenshotHistoryCard(
                            item: item,
                            fileURL: app.screenshotHistoryFileURL(for: item),
                            isSelected: selection.selectedID == item.id,
                            cardSize: size,
                            maxPixelSize: gridZoom.thumbnailPixelSize,
                            enablesHoverZoom: gridZoom.enablesHoverZoom,
                            onClick: { count in
                                GallerySelection.handleClick(count, on: item.id, selection: $selection) {
                                    app.showScreenshotHistoryPreview(item)
                                }
                            },
                            onSelect: { selection.toggle(item.id) },
                            onCopy: { app.copyScreenshotHistory(item) },
                            onPreview: { app.showScreenshotHistoryPreview(item) },
                            onEdit: { app.editScreenshotHistory(item) },
                            onDelete: { app.deleteScreenshotHistory(item) },
                            onDragData: { app.screenshotHistoryData(for: item) },
                            onClearSelection: { selection.clear() }
                        )
                        .equatable()
                    }
                )
            }
        }
        .onChange(of: filteredItems.map(\.id)) { _, ids in selection.retain(ids.contains) }
        .animation(
            JarvisMotion.animation(JarvisMotion.content, reduceMotion: reduceMotion),
            value: selectedTimeFilter
        )
        .animation(
            JarvisMotion.animation(JarvisMotion.content, reduceMotion: reduceMotion),
            value: searchText
        )
    }

    private var emptyTitle: String {
        if app.screenshotHistory.isEmpty {
            return "还没有截图"
        }
        if isSearching {
            return "没有匹配的截图"
        }
        return "该时间范围暂无截图"
    }

    private var emptyMessage: String {
        if app.screenshotHistory.isEmpty {
            return "框选截图后，历史记录会显示在这里"
        }
        if isSearching {
            return "换个关键词或时间范围。新图片里的文字要等后台识别完成后才能搜到。"
        }
        return "切换其他时间范围查看截图"
    }
}

struct ScreenshotHistoryCard: View, Equatable {
    @State private var showingDeleteConfirmation = false
    let item: ScreenshotHistoryItem
    let fileURL: URL
    let isSelected: Bool
    let cardSize: CGSize
    let maxPixelSize: Int
    let enablesHoverZoom: Bool
    let onClick: (Int) -> Void
    let onSelect: () -> Void
    let onCopy: () -> Void
    let onPreview: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onDragData: () -> Data?
    let onClearSelection: () -> Void

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.item == rhs.item
            && lhs.fileURL == rhs.fileURL
            && lhs.isSelected == rhs.isSelected
            && lhs.cardSize == rhs.cardSize
            && lhs.maxPixelSize == rhs.maxPixelSize
            && lhs.enablesHoverZoom == rhs.enablesHoverZoom
    }

    private var thumbnailCacheKey: String {
        "\(item.id.uuidString)|\(item.updatedAt.timeIntervalSince1970)|\(maxPixelSize)"
    }

    private var timestamp: String {
        JarvisHistoryDateFormatting.string(from: item.updatedAt)
    }

    private var previewArea: some View {
        Color.clear
            .overlay {
                ScreenshotHistoryThumbnail(fileURL: fileURL, cacheKey: thumbnailCacheKey, maxPixelSize: maxPixelSize)
            }
            .clipped()
            .onDrag {
                guard let data = onDragData() else { return NSItemProvider() }
                return ScreenshotSharing.itemProvider(for: item, data: data)
            }
    }

    var body: some View {
        GalleryCard(
            size: cardSize, isSelected: isSelected, enablesHoverZoom: enablesHoverZoom,
            onClick: onClick, preview: { previewArea },
            leading: { Label("PNG", systemImage: "photo") },
            trailing: { Text(timestamp) }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("截图，PNG，\(JarvisHistoryDateFormatting.string(from: item.updatedAt))")
        .accessibilityValue(isSelected ? "已选中" : "未选中")
        .accessibilityHint("点击选择，双击预览；可以拖到 Finder 或其他应用导出 PNG")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, onSelect)
        .accessibilityAction(named: "查看", onPreview)
        .accessibilityAction(named: "复制") {
            onCopy()
        }
        .contextMenu {
            Button {
                onPreview()
            } label: {
                Label("查看", systemImage: "eye")
            }
            Button {
                onEdit()
            } label: {
                Label("编辑", systemImage: "pencil")
            }
            Button {
                onCopy()
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
            Divider()
            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
        .confirmationDialog(
            "删除这张截图？",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                onDelete()
                if isSelected {
                    onClearSelection()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后无法恢复。")
        }
    }
}

struct ScreenshotHistoryThumbnail: View {
    let fileURL: URL
    let cacheKey: String
    let maxPixelSize: Int
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .interpolation(.medium)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.jarvisTextSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: cacheKey) {
            if image == nil {
                image = JarvisThumbnailCache.cached(
                    fileURL: fileURL,
                    maxPixelSize: maxPixelSize,
                    token: cacheKey
                )
            }
            let loaded = await JarvisThumbnailCache.loadAsync(
                fileURL: fileURL,
                maxPixelSize: maxPixelSize,
                token: cacheKey
            )
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }
}
