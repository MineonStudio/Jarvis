import AppKit
import SwiftUI

typealias ClipboardViewFilter = ClipboardCacheCategory

enum ClipboardTimeFilter: String, CaseIterable, Identifiable {
    case threeDays
    case sevenDays
    case oneMonth
    case all

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .all: "全部时间"
        case .threeDays: "3天"
        case .sevenDays: "7天"
        case .oneMonth: "1个月"
        }
    }

    func matches(
        _ item: ClipboardItem,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard let components else { return true }
        guard let startDate = calendar.date(byAdding: components, to: now) else { return false }
        return item.createdAt >= startDate
    }

    private var components: DateComponents? {
        switch self {
        case .all: nil
        case .threeDays: DateComponents(day: -3)
        case .sevenDays: DateComponents(day: -7)
        case .oneMonth: DateComponents(month: -1)
        }
    }
}

enum ClipboardTimeFilterLogic {
    static func filteredItems(
        from items: [ClipboardItem],
        filter: ClipboardTimeFilter,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ClipboardItem] {
        items.filter { filter.matches($0, now: now, calendar: calendar) }
    }

    static func count(
        for filter: ClipboardTimeFilter,
        in items: [ClipboardItem],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        filteredItems(from: items, filter: filter, now: now, calendar: calendar).count
    }
}

struct ClipboardSearchField: View {
    @Binding var text: String
    var placeholder: String
    var focusesOnAppear = false
    var onSubmit: (() -> Void)?
    var onClear: (() -> Void)?
    var help: String?
    var accessibilityTitle: String?

    var body: some View {
        JarvisToolbarSearchField(
            text: $text,
            placeholder: placeholder,
            help: help,
            accessibilityTitle: accessibilityTitle,
            focusesOnAppear: focusesOnAppear,
            onSubmit: onSubmit,
            onClear: onClear
        )
    }
}

enum ClipboardFilterLogic {
    static func filteredItems(
        from items: [ClipboardItem],
        searchText: String,
        timeFilter: ClipboardTimeFilter,
        category: ClipboardViewFilter, imageTextByHash: [String: String] = [:],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ClipboardItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { item in
            timeFilter.matches(item, now: now, calendar: calendar)
                && category.matches(item)
                && matchesSearch(item, query: query, imageTextByHash: imageTextByHash)
        }
    }

    static func filteredItems(
        from items: [ClipboardItem],
        searchText: String,
        filter: ClipboardViewFilter, imageTextByHash: [String: String] = [:]
    ) -> [ClipboardItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { item in
            filter.matches(item)
                && matchesSearch(item, query: query, imageTextByHash: imageTextByHash)
        }
    }

    static func count(for filter: ClipboardViewFilter, in items: [ClipboardItem]) -> Int {
        items.filter { filter.matches($0) }.count
    }

    static func counts(in items: [ClipboardItem]) -> [ClipboardViewFilter: Int] {
        var counts = Dictionary(
            uniqueKeysWithValues: ClipboardViewFilter.allCases.map { ($0, 0) }
        )
        for item in items {
            for filter in ClipboardViewFilter.allCases where filter.matches(item) {
                counts[filter, default: 0] += 1
            }
        }
        return counts
    }
}

/// 时间筛选：与截图模块同一枚分组容器（见 `ScreenshotTimeFilterBar`）。
struct ClipboardTimeFilterSelector: ToolbarContent {
    @Binding var selection: ClipboardTimeFilter
    var alignment: HistoryToolbarAlignment?

    var body: some ToolbarContent {
        JarvisLeadingToolbarSurface(id: "clipboard.time-filter") {
            JarvisToolbarGroupedPicker(
                items: ClipboardTimeFilter.allCases,
                selection: $selection,
                title: \.title
            )
            .background {
                if let alignment {
                    HistoryToolbarFrameProbe(alignment: alignment, edge: .leading)
                }
            }
        }
    }
}

struct ClipboardCategoryFilterSelector: View {
    @Binding var selection: ClipboardViewFilter

    private func categoryTitle(_ filter: ClipboardViewFilter) -> String {
        filter == .all ? "全部类型" : filter.title
    }

    var body: some View {
        JarvisDropdownMenu(
            title: categoryTitle(selection),
            options: ClipboardViewFilter.allCases.map {
                JarvisDropdownOption(id: $0.id, title: categoryTitle($0))
            },
            selectionID: selection.id,
            accessibilityLabel: "内容类型筛选",
            help: "按内容类型筛选",
            onSelect: { rawValue in
                guard let category = ClipboardViewFilter(rawValue: rawValue) else { return }
                selection = category
            }
        )
    }
}

struct ClipboardView: View {
    @Environment(AppModel.self) private var app
    @State private var searchText = ""
    @State private var selectedTimeFilter: ClipboardTimeFilter = .threeDays
    @State private var selectedCategory: ClipboardViewFilter = .all
    @State private var selection = GallerySelection<UUID>()
    @State private var gridZoom: HistoryGridZoomLevel = .regular
    @State private var toolbarAlignment = HistoryToolbarAlignment()

    private var filteredItems: [ClipboardItem] {
        ClipboardFilterLogic.filteredItems(
            from: app.clipboardItems,
            searchText: searchText,
            timeFilter: selectedTimeFilter,
            category: selectedCategory, imageTextByHash: app.imageTextByHash
        )
    }

    private var selectedItem: ClipboardItem? {
        guard let selectedItemID = selection.selectedID else { return nil }
        return app.clipboardItems.first { $0.id == selectedItemID }
    }

    var body: some View {
        JarvisContentArea(
            horizontalContentPadding: 0,
            bottomContentPadding: 0,
            leadingToolbar: {
                ClipboardTimeFilterSelector(selection: $selectedTimeFilter, alignment: toolbarAlignment)
            },
            trailingToolbar: {
                ToolbarItem(id: "clipboard.category", placement: .automatic) {
                    ClipboardCategoryFilterSelector(selection: $selectedCategory)
                }
                ToolbarSpacer(.fixed, placement: .automatic)
                ToolbarItem(id: "clipboard.grid-zoom", placement: .automatic) {
                    HistoryGridZoomControl(selection: $gridZoom)
                }
                ToolbarSpacer(.fixed, placement: .automatic)
                ToolbarItem(id: "clipboard.actions", placement: .automatic) {
                    ClipboardHistoryActionToolbar(
                        selectedItem: selectedItem,
                        onClearSelection: { selection.clear() }
                    )
                }
                ToolbarSpacer(.fixed, placement: .automatic)
                ToolbarItem(id: "clipboard.search", placement: .automatic) {
                    ClipboardSearchField(
                        text: $searchText,
                        placeholder: ClipboardFilterLogic.searchPlaceholder,
                        focusesOnAppear: false
                    )
                    .background(HistoryToolbarFrameProbe(alignment: toolbarAlignment, edge: .trailing))
                }
            },
            content: {
                GeometryReader { viewport in
                    JarvisBackToTopScroll("返回剪贴板列表顶部", id: "clipboard-scroll-top") {
                        ClipboardHistoryGallery(
                            items: filteredItems,
                            gridZoom: gridZoom,
                            selection: $selection,
                            availableWidth: viewport.size.width - toolbarAlignment.leadingInset - toolbarAlignment.trailingInset,
                            hasQuery: !searchText.isEmpty || selectedTimeFilter != .all || selectedCategory != .all,
                            onDoubleClick: { item in
                                if item.canFullscreenPreview {
                                    app.showClipboardMediaPreview(item)
                                }
                            },
                            onCopy: { app.copyClipboard($0) },
                            onPreview: { app.showClipboardMediaPreview($0) },
                            onPin: { app.toggleClipboardPin($0) },
                            onDelete: { app.deleteClipboardItem($0) }
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
        .onChange(of: filteredItems.map(\.id)) { _, ids in selection.retain(ids.contains) }
    }
}

struct ClipboardHistoryActionToolbar: View {
    @Environment(AppModel.self) private var app
    let selectedItem: ClipboardItem?
    let onClearSelection: () -> Void
    @State private var showingDeleteConfirmation = false
    @State private var showingSensitiveCopyConfirmation = false
    @State private var showingSensitivePreviewConfirmation = false

    private var canPreview: Bool {
        selectedItem?.canFullscreenPreview == true
    }

    var body: some View {
        HStack(spacing: JarvisSpacing.hairline) {
            JarvisToolbarIconButton(
                systemName: "eye",
                help: "查看",
                isEnabled: canPreview
            ) {
                guard let selectedItem else { return }
                if selectedItem.isSensitive {
                    showingSensitivePreviewConfirmation = true
                } else {
                    app.showClipboardMediaPreview(selectedItem)
                }
            }
            JarvisToolbarIconButton(
                systemName: "doc.on.doc",
                help: "复制",
                isEnabled: selectedItem != nil
            ) {
                guard let selectedItem else { return }
                if selectedItem.isSensitive {
                    showingSensitiveCopyConfirmation = true
                } else {
                    app.copyClipboard(selectedItem)
                }
            }
            JarvisToolbarIconButton(
                systemName: selectedItem?.isPinned == true ? "star.slash" : "star",
                help: selectedItem?.isPinned == true ? "取消收藏" : "收藏",
                tint: selectedItem?.isPinned == true ? .yellow : .secondary,
                isEnabled: selectedItem != nil
            ) {
                guard let selectedItem else { return }
                app.toggleClipboardPin(selectedItem)
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
        // The enclosing ToolbarItem supplies the native toolbar group surface.
        // Do not add a second custom glass capsule inside it.
        .confirmationDialog(
            "删除这条剪贴板记录？",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                guard let selectedItem else { return }
                app.deleteClipboardItem(selectedItem)
                onClearSelection()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后无法恢复。")
        }
        .confirmationDialog(
            "这段内容疑似包含敏感信息",
            isPresented: $showingSensitiveCopyConfirmation,
            titleVisibility: .visible
        ) {
            Button("显示并复制") {
                guard let selectedItem else { return }
                app.copyClipboard(selectedItem)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只有在你主动确认后，才会显示并复制原始内容。")
        }
        .confirmationDialog(
            "这段内容疑似包含敏感信息",
            isPresented: $showingSensitivePreviewConfirmation,
            titleVisibility: .visible
        ) {
            Button("显示并查看") {
                guard let selectedItem else { return }
                app.showClipboardMediaPreview(selectedItem)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只有在你主动确认后，才会打开原始内容预览。")
        }
    }
}

struct ClipboardEmptyState: View {
    let hasQuery: Bool

    var body: some View {
        JarvisEmptyState(
            icon: hasQuery ? "line.3.horizontal.decrease.circle" : "clipboard",
            title: hasQuery ? "没有找到匹配内容" : "还没有剪贴板记录",
            message: hasQuery ? "换个关键词或切换内容类型试试" : "复制一些内容，历史会自动出现在这里"
        )
    }
}
