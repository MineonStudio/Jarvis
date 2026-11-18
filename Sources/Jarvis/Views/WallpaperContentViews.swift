import AppKit
import SwiftUI

private enum WallpaperScrollSpace {
    static let name = "wallpaper-scroll"
}

private enum WallpaperScrollTarget {
    static let top = "wallpaper-scroll-top"
}

private enum WallpaperScrollBehavior {
    static let backToTopThreshold = JarvisScrollToTop.visibilityThreshold
}

private enum WallpaperCustomFilterPrompt {
    case randomSeed

    var title: String {
        switch self {
        case .randomSeed: "设置随机种子"
        }
    }

    var placeholder: String {
        switch self {
        case .randomSeed: "6 位英文字母或数字"
        }
    }

    var message: String {
        switch self {
        case .randomSeed: "使用相同种子可以重复获得相同的随机结果。"
        }
    }
}

private struct WallpaperLoadMoreTriggerPreferenceKey: PreferenceKey {
    static let defaultValue = CGFloat.infinity

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct WallpaperView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var model = WallpaperViewModel()
    @StateObject private var previewController = WallpaperPreviewController()
    @State private var libraryMode: WallpaperLibraryMode = .online
    @State private var gridZoom: HistoryGridZoomLevel = .regular
    @State private var selection = GallerySelection<String>()
    @State private var toolbarAlignment = HistoryToolbarAlignment()
    @State private var deleteItem: WallpaperItem?
    @State private var tagInput = ""
    @State private var customFilterPrompt: WallpaperCustomFilterPrompt?
    @State private var customFilterInput = ""
    @State private var shouldShowScrollToTop = false
    @State private var isLoadMoreScheduled = false

    var body: some View {
        JarvisContentArea(
            horizontalContentPadding: 0,
            bottomContentPadding: 0,
            leadingToolbar: {
                wallpaperLeadingToolbar
            },
            trailingToolbar: {
                ToolbarItem(id: "wallpaper.grid-zoom", placement: .primaryAction) {
                    HistoryGridZoomControl(selection: $gridZoom)
                }
                ToolbarSpacer(.fixed, placement: .primaryAction)
                WallpaperLibraryToolbar(libraryMode: $libraryMode)
                ToolbarSpacer(.fixed, placement: .primaryAction)
                ToolbarItem(id: "wallpaper.tag-search", placement: .primaryAction) {
                    ClipboardSearchField(
                        text: $tagInput,
                        placeholder: "搜索关键词或语法",
                        onSubmit: submitTag,
                        onClear: clearTag,
                        help: "输入关键词或 Wallhaven 高级条件：+标签表示必须包含，-标签表示排除，@用户名搜索上传者，type:jpg/png 筛选文件类型，id:数字搜索标签 ID，like:图片 ID 查找相似壁纸。",
                        accessibilityTitle: "壁纸搜索"
                    )
                    .background(HistoryToolbarFrameProbe(alignment: toolbarAlignment, edge: .trailing))
                }
            },
            content: {
                GeometryReader { viewport in
                    ScrollViewReader { scrollProxy in
                        galleryScrollView(viewport: viewport, scrollProxy: scrollProxy)
                    }
                }
                .background(HistoryToolbarFrameProbe(alignment: toolbarAlignment, edge: .content))
            }
        )
        .confirmationDialog(
            "删除这张已下载壁纸？",
            isPresented: deleteDialogPresented,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                guard let deleteItem else { return }
                deleteWallpaper(deleteItem)
                self.deleteItem = nil
            }
            Button("取消", role: .cancel) {
                deleteItem = nil
            }
        } message: {
            Text("删除后无法恢复。")
        }
        .task {
            await model.refresh()
        }
        .onChange(of: libraryMode) { _, newMode in
            selection.clear()
            if newMode == .online {
                refreshOnline()
            } else {
                model.refreshLibrary()
            }
        }
        .alert(
            customFilterPrompt?.title ?? "自定义筛选",
            isPresented: Binding(
                get: { customFilterPrompt != nil },
                set: {
                    if !$0 {
                        customFilterPrompt = nil
                    }
                }
            )
        ) {
            TextField(customFilterPrompt?.placeholder ?? "", text: $customFilterInput)
            Button("应用", action: applyCustomFilterPrompt)
                .disabled(!isCustomFilterInputValid)
            Button("取消", role: .cancel) { customFilterPrompt = nil }
        } message: {
            Text(customFilterPrompt?.message ?? "")
        }
        .onDisappear {
            previewController.dismiss()
        }
    }

    // MARK: - 工具栏

    /// 所有壁纸筛选器共用同一种工具栏下拉控件。
    @ToolbarContentBuilder
    private func filterItem(
        id: String,
        title: String,
        options: [JarvisDropdownOption],
        selectionID: String,
        accessibilityLabel: String,
        help: String,
        showsSelectedOption: Bool = false,
        onSelect: @escaping (String) -> Void
    ) -> some ToolbarContent {
        let control = JarvisDropdownMenu(
            title: title,
            options: options,
            selectionID: selectionID,
            accessibilityLabel: accessibilityLabel,
            help: help,
            showsSelectedOption: showsSelectedOption,
            onSelect: onSelect
        )
        .id(selectionID)

        if id == "wallpaper.filter.purity" {
            JarvisLeadingToolbarItem(id: id, alignment: toolbarAlignment) {
                control
            }
        } else {
            ToolbarItem(id: id, placement: .automatic) {
                control
            }
        }
    }

    @ToolbarContentBuilder
    private var wallpaperLeadingToolbar: some ToolbarContent {
        wallhavenCoreFilters
        wallhavenAppearanceAndSortFilters
    }

    @ToolbarContentBuilder
    private var wallhavenCoreFilters: some ToolbarContent {
        purityFilterItem
        ToolbarSpacer(.fixed, placement: .automatic)
        resolutionFilterItem
        ToolbarSpacer(.fixed, placement: .automatic)
        ratioFilterItem
    }

    @ToolbarContentBuilder
    private var wallhavenAppearanceAndSortFilters: some ToolbarContent {
        ToolbarSpacer(.fixed, placement: .automatic)
        colorFilterItem
        ToolbarSpacer(.fixed, placement: .automatic)
        sortingFilterItem
        if model.selectedSorting == .toplist {
            ToolbarSpacer(.fixed, placement: .automatic)
            topRangeFilterItem
        }
        if model.selectedSorting == .random {
            ToolbarSpacer(.fixed, placement: .automatic)
            randomSeedFilterItem
        }
    }

    private var purityFilterItem: some ToolbarContent {
        filterItem(
            id: "wallpaper.filter.purity",
            title: model.selectedPurityPreset.title,
            options: WallpaperPurityPreset.allCases.map {
                JarvisDropdownOption(id: $0.rawValue, title: $0.title)
            },
            selectionID: model.selectedPurityPreset.rawValue,
            accessibilityLabel: "内容纯度",
            help: "NSFW 内容需要填写 Wallhaven API Key"
        ) { rawValue in
            guard let preset = WallpaperPurityPreset(rawValue: rawValue) else { return }
            model.selectedPurityPreset = preset
            applyOnlineFilters()
        }
    }

    private var resolutionFilterItem: some ToolbarContent {
        filterItem(
            id: "wallpaper.filter.resolution",
            title: model.selectedResolution.title,
            options: WallpaperResolution.galleryCases.map {
                JarvisDropdownOption(id: $0.rawValue, title: $0.title)
            },
            selectionID: model.selectedResolution.rawValue,
            accessibilityLabel: "分辨率筛选",
            help: "按最低分辨率筛选"
        ) { rawValue in
            guard let resolution = WallpaperResolution(rawValue: rawValue) else { return }
            model.selectedResolution = resolution
            applyOnlineFilters()
        }
    }

    private var ratioFilterItem: some ToolbarContent {
        filterItem(
            id: "wallpaper.filter.ratio",
            title: model.selectedRatio.title,
            options: WallpaperRatio.galleryCases.map {
                JarvisDropdownOption(id: $0.rawValue, title: $0.title)
            },
            selectionID: model.selectedRatio.rawValue,
            accessibilityLabel: "比例筛选",
            help: "按画面比例筛选"
        ) { rawValue in
            guard let ratio = WallpaperRatio(rawValue: rawValue) else { return }
            model.selectedRatio = ratio
            applyOnlineFilters()
        }
    }

    private var colorFilterItem: some ToolbarContent {
        filterItem(
            id: "wallpaper.filter.color",
            title: model.selectedColor?.title ?? "不限颜色",
            options: [JarvisDropdownOption(id: "none", title: "不限颜色")]
                + WallpaperColor.galleryCases.map {
                    JarvisDropdownOption(id: $0.rawValue, title: $0.title, colorHex: $0.rawValue)
                },
            selectionID: model.selectedColor?.rawValue ?? "none",
            accessibilityLabel: "主色调",
            help: "按壁纸主色调筛选"
        ) { rawValue in
            model.selectedColor = WallpaperColor(rawValue: rawValue)
            applyOnlineFilters()
        }
    }

    private var sortingFilterItem: some ToolbarContent {
        filterItem(
            id: "wallpaper.filter.sorting",
            title: model.selectedSorting.title,
            options: WallpaperSorting.allCases.map {
                JarvisDropdownOption(id: $0.rawValue, title: $0.title)
            },
            selectionID: model.selectedSorting.rawValue,
            accessibilityLabel: "排序方式",
            help: "选择 Wallhaven 排序方式"
        ) { rawValue in
            guard let sorting = WallpaperSorting(rawValue: rawValue) else { return }
            model.selectedSorting = sorting
            applyOnlineFilters()
        }
    }

    private var topRangeFilterItem: some ToolbarContent {
        filterItem(
            id: "wallpaper.filter.top-range",
            title: model.selectedTopRange.title,
            options: WallpaperTopRange.allCases.map {
                JarvisDropdownOption(id: $0.rawValue, title: $0.title)
            },
            selectionID: model.selectedTopRange.rawValue,
            accessibilityLabel: "热门榜时间范围",
            help: "选择热门榜的统计时间范围"
        ) { rawValue in
            guard let range = WallpaperTopRange(rawValue: rawValue) else { return }
            model.selectedTopRange = range
            applyOnlineFilters()
        }
    }

    private var randomSeedFilterItem: some ToolbarContent {
        filterItem(
            id: "wallpaper.filter.random-seed",
            title: model.randomSeed.isEmpty ? "随机种子" : "已设种子",
            options: [
                JarvisDropdownOption(id: "none", title: "不指定种子"),
                JarvisDropdownOption(id: "editCustom", title: "设置种子…")
            ],
            selectionID: model.randomSeed.isEmpty ? "none" : model.randomSeed,
            accessibilityLabel: "随机种子",
            help: "随机排序时，可设置种子以重复结果"
        ) { rawValue in
            if rawValue == "none" {
                model.randomSeed = ""
                applyOnlineFilters()
            } else if rawValue == "editCustom" {
                customFilterInput = model.randomSeed
                customFilterPrompt = .randomSeed
            }
        }
    }

    // MARK: - 画廊

    private func galleryScrollView(
        viewport: GeometryProxy,
        scrollProxy: ScrollViewProxy
    ) -> some View {
        let availableWidth = max(1, viewport.size.width - toolbarAlignment.leadingInset - toolbarAlignment.trailingInset)
        return ScrollView {
            VStack(spacing: 0) {
                galleryList(availableWidth: availableWidth)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, toolbarAlignment.leadingInset)
            .padding(.trailing, toolbarAlignment.trailingInset)
            .padding(.bottom, HistoryGridMetrics.historyPanelInset)
            .galleryBackground(minHeight: viewport.size.height) { selection.clear() }
            .id(WallpaperScrollTarget.top)
        }
        .coordinateSpace(name: WallpaperScrollSpace.name)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.visibleRect.minY >= WallpaperScrollBehavior.backToTopThreshold
        } action: { _, shouldShow in
            shouldShowScrollToTop = shouldShow
        }
        .onPreferenceChange(WallpaperLoadMoreTriggerPreferenceKey.self) { triggerY in
            guard model.hasNextPage,
                  !model.isLoadingMore,
                  !isLoadMoreScheduled,
                  triggerY.isFinite,
                  triggerY <= viewport.size.height + 160
            else {
                return
            }
            loadMore()
        }
        .overlay(alignment: .bottomTrailing) {
            if shouldShowScrollToTop {
                scrollToTopButton(scrollProxy: scrollProxy)
            }
        }
    }

    @ViewBuilder
    private func galleryList(availableWidth: CGFloat) -> some View {
        switch libraryMode {
        case .online:
            onlineGallery(availableWidth: availableWidth)
        case .downloaded:
            gallery(
                items: model.library,
                availableWidth: availableWidth,
                emptyTitle: "还没有已下载壁纸",
                emptyMessage: "从在线图库下载壁纸后，会在这里长期保留。",
                showsDelete: true,
                onDelete: { deleteItem = $0 }
            )
        case .favorites:
            gallery(
                items: model.favorites,
                availableWidth: availableWidth,
                emptyTitle: "还没有收藏壁纸",
                emptyMessage: "将指针移到壁纸卡片上，点击心形按钮即可收藏。"
            )
        }
    }

    private func scrollToTopButton(scrollProxy: ScrollViewProxy) -> some View {
        Button {
            withAnimation(
                JarvisMotion.animation(
                    JarvisMotion.content,
                    reduceMotion: reduceMotion
                )
            ) {
                scrollProxy.scrollTo(WallpaperScrollTarget.top, anchor: .top)
            }
        } label: {
            Label("返回顶部", systemImage: "arrow.up")
        }
        .buttonStyle(JarvisSecondaryButtonStyle())
        .accessibilityLabel("返回壁纸列表顶部")
        .padding(.trailing, JarvisSpacing.cardInset)
        .padding(.bottom, JarvisSpacing.cardInset)
    }

    @ViewBuilder
    private func onlineGallery(availableWidth: CGFloat) -> some View {
        if model.isLoading, model.items.isEmpty {
            JarvisInlineLoadingState()
                .frame(maxWidth: .infinity, minHeight: 250)
        } else if let errorMessage = model.errorMessage, model.items.isEmpty {
            WallpaperErrorState(message: errorMessage, retry: refreshOnline)
        } else {
            gallery(
                items: model.items,
                availableWidth: availableWidth,
                emptyTitle: "没有找到壁纸",
                emptyMessage: "换一个分辨率、比例或标签试试。"
            )

            if model.hasNextPage {
                GeometryReader { proxy in
                    Color.clear
                        .preference(
                            key: WallpaperLoadMoreTriggerPreferenceKey.self,
                            value: proxy.frame(in: .named(WallpaperScrollSpace.name)).minY
                        )
                }
                .frame(height: 1)
                .id("wallpaper-load-more-trigger-\(model.items.count)")
                .accessibilityHidden(true)

                WallpaperLoadMoreButton(
                    isLoading: model.isLoadingMore,
                    errorMessage: model.loadMoreErrorMessage,
                    action: loadMore
                )
            }
        }
    }

    @ViewBuilder
    private func gallery(
        items: [WallpaperItem],
        availableWidth: CGFloat,
        emptyTitle: String,
        emptyMessage: String,
        showsDelete: Bool = false,
        onDelete: @escaping (WallpaperItem) -> Void = { _ in }
    ) -> some View {
        if items.isEmpty {
            JarvisEmptyState(
                icon: "photo.on.rectangle.angled",
                title: emptyTitle,
                message: emptyMessage
            )
        } else {
            WallpaperGrid(
                items: items,
                availableWidth: availableWidth,
                gridZoom: gridZoom,
                selection: $selection,
                imageURL: { model.localURL(for: $0) ?? $0.previewURL },
                isDownloading: { model.isDownloading($0) },
                isPreviewLoading: { previewController.isLoading(itemID: $0.id) },
                onDoubleClick: { item in
                    previewController.show(
                        imageURL: model.localURL(for: item) ?? item.originalURL,
                        itemID: item.id,
                        onFailure: { app.showToast(JarvisFeedbackCopy.originalImageLoadFailed) }
                    )
                },
                onSet: setWallpaper,
                isApplied: { model.isApplied($0) },
                onToggleFavorite: toggleFavorite,
                showsDelete: showsDelete,
                onDelete: onDelete
            )
        }
    }

    private var deleteDialogPresented: Binding<Bool> {
        Binding(
            get: { deleteItem != nil },
            set: { isPresented in
                if !isPresented {
                    deleteItem = nil
                }
            }
        )
    }

    private func refreshOnline() {
        guard libraryMode == .online else { return }
        Task {
            await model.refresh()
        }
    }

    private func loadMore() {
        guard libraryMode == .online,
              !model.isLoadingMore,
              !isLoadMoreScheduled
        else {
            return
        }
        isLoadMoreScheduled = true
        Task {
            await model.loadMore()
            isLoadMoreScheduled = false
        }
    }

    private func applyOnlineFilters() {
        guard libraryMode == .online else { return }
        refreshOnline()
    }

    private func submitTag() {
        let tag = tagInput.trimmingCharacters(in: .whitespacesAndNewlines)
        tagInput = tag
        model.selectedTag = tag
        if libraryMode == .online {
            applyOnlineFilters()
        } else {
            libraryMode = .online
        }
    }

    private func clearTag() {
        tagInput = ""
        model.selectedTag = ""
        applyOnlineFilters()
    }

    private var isCustomFilterInputValid: Bool {
        guard let customFilterPrompt else { return false }
        let value = customFilterInput.trimmingCharacters(in: .whitespacesAndNewlines)
        switch customFilterPrompt {
        case .randomSeed:
            return value.count == 6 && value.utf8.allSatisfy {
                (48 ... 57).contains($0) || (65 ... 90).contains($0) || (97 ... 122).contains($0)
            }
        }
    }

    private func applyCustomFilterPrompt() {
        guard let customFilterPrompt, isCustomFilterInputValid else { return }
        let value = customFilterInput.trimmingCharacters(in: .whitespacesAndNewlines)
        switch customFilterPrompt {
        case .randomSeed:
            model.randomSeed = value
        }
        self.customFilterPrompt = nil
        applyOnlineFilters()
    }

    private func setWallpaper(_ item: WallpaperItem) {
        Task {
            let message = await model.downloadAndApply(item, target: .desktop)
            app.showToast(message)
        }
    }

    private func toggleFavorite(_ item: WallpaperItem) {
        guard let updatedItem = model.toggleFavorite(item) else {
            app.showToast(JarvisFeedbackCopy.favoriteFailed)
            return
        }
        app.showToast(updatedItem.isFavorite ? JarvisFeedbackCopy.favorited : JarvisFeedbackCopy.unfavorited)
    }

    private func deleteWallpaper(_ item: WallpaperItem) {
        guard model.delete(item) else {
            app.showToast(JarvisFeedbackCopy.deleteFailed)
            return
        }
        app.showToast(JarvisFeedbackCopy.deleted)
    }
}

/// 图库来源（在线图库 / 已下载 / 我的收藏）：与截图模块同一枚分组容器。
private struct WallpaperLibraryToolbar: ToolbarContent {
    @Binding var libraryMode: WallpaperLibraryMode

    var body: some ToolbarContent {
        JarvisToolbarSurface(id: "wallpaper.library", placement: .primaryAction) {
            JarvisToolbarGroupedPicker(
                items: WallpaperLibraryMode.allCases,
                selection: $libraryMode,
                title: \.title
            )
        }
    }
}

private struct WallpaperLoadMoreButton: View {
    let isLoading: Bool
    let errorMessage: String?
    let action: () -> Void

    var body: some View {
        if isLoading {
            JarvisInlineLoadingState()
                .frame(maxWidth: .infinity)
                .padding(.top, HistoryGridMetrics.clipboardGridSpacing)
        } else {
            Button(action: action) {
                if errorMessage != nil {
                    Label("重试", systemImage: "arrow.clockwise")
                } else {
                    Label("加载更多", systemImage: "arrow.down.circle")
                }
            }
            .buttonStyle(JarvisSecondaryButtonStyle())
            .frame(maxWidth: .infinity)
            .padding(.top, HistoryGridMetrics.clipboardGridSpacing)
        }
    }
}

private struct WallpaperGrid: View {
    let items: [WallpaperItem]
    let availableWidth: CGFloat
    let gridZoom: HistoryGridZoomLevel
    @Binding var selection: GallerySelection<String>
    let imageURL: (WallpaperItem) -> URL
    let isDownloading: (WallpaperItem) -> Bool
    let isPreviewLoading: (WallpaperItem) -> Bool
    let onDoubleClick: (WallpaperItem) -> Void
    let onSet: (WallpaperItem) -> Void
    let isApplied: (WallpaperItem) -> Bool
    let onToggleFavorite: (WallpaperItem) -> Void
    let showsDelete: Bool
    let onDelete: (WallpaperItem) -> Void

    var body: some View {
        JustifiedGallery(
            items: items, availableWidth: availableWidth,
            scale: gridZoom.cardWidth / HistoryGridZoomLevel.regular.cardWidth,
            aspectRatio: { JustifiedGalleryLayout.aspectRatio(width: $0.width, height: $0.height) },
            card: card
        )
        .onChange(of: items.map(\.id)) { _, ids in selection.retain(ids.contains) }
    }

    private func card(_ item: WallpaperItem, _ size: CGSize) -> some View {
        let isSelected = selection.selectedID == item.id
        return GalleryCard(
            size: size, isSelected: isSelected, enablesHoverZoom: gridZoom.enablesHoverZoom,
            onClick: { count in
                GallerySelection.handleClick(count, on: item.id, selection: $selection) { onDoubleClick(item) }
            },
            preview: {
                WallpaperThumbnail(url: imageURL(item))
                    .overlay {
                        if isPreviewLoading(item) {
                            ProgressView()
                                .controlSize(.large)
                                .padding(12)
                                .glassEffect(.regular, in: Circle())
                                .allowsHitTesting(false)
                                .accessibilityLabel("正在加载原图")
                        }
                    }
            },
            hoverContent: {
                WallpaperHoverActions(
                    isFavorite: item.isFavorite, isSetting: isDownloading(item), setTitle: setWallpaperTitle(item),
                    onToggleFavorite: { onToggleFavorite(item) }, onSet: { onSet(item) }
                )
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.title)，\(item.resolutionDescription)")
        .accessibilityHint("点击切换选中，双击查看原图")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { selection.toggle(item.id) }
        .accessibilityAction(named: "查看原图") { onDoubleClick(item) }
        .contextMenu {
            Button("查看原图") { onDoubleClick(item) }
            Button(setWallpaperTitle(item)) { onSet(item) }
                .disabled(isDownloading(item))
            Button(item.isFavorite ? "取消收藏" : "收藏") { onToggleFavorite(item) }
            if showsDelete {
                Divider()
                Button("删除", role: .destructive) { onDelete(item) }
            }
        }
    }

    private func setWallpaperTitle(_ item: WallpaperItem) -> String {
        if isDownloading(item) {
            return "正在设置…"
        }
        return isApplied(item) ? "已设为桌面壁纸" : "设为桌面壁纸"
    }
}

private struct WallpaperThumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Color.clear.jarvisPanelBackground(cornerRadius: 0)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    // The row layout already derives the card width from the
                    // wallpaper's aspect ratio. Fit the bitmap inside that
                    // exact frame so the thumbnail never crops its edges.
                    .scaledToFit()
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: url, priority: .utility) {
            image = await WallpaperImageLoader.load(url: url)
        }
    }
}

private struct WallpaperErrorState: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: JarvisSpacing.itemGap) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Color.orange)
            Text(message)
                .font(JarvisTypography.secondary)
                .foregroundStyle(Color.jarvisTextSecondary)
                .multilineTextAlignment(.center)
            Button("重试", action: retry)
                .buttonStyle(JarvisSecondaryButtonStyle())
        }
        .frame(maxWidth: .infinity, minHeight: 250)
    }
}
