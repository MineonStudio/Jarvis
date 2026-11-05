import SwiftUI

/// One timing curve for the shelf's native bounds and SwiftUI card layout.
enum ClipboardPanelMotion {
    static let resizeDuration: TimeInterval = 0.28
    static let showDuration: TimeInterval = 0.24
    static let hideDuration: TimeInterval = 0.18
    static let revealDistance: CGFloat = 18
    static let content = Animation.easeInOut(duration: resizeDuration)
}

/// The shelf reserves exactly two card rows, even for an empty or filtered history.
enum ClipboardPanelLayout {
    static let inset: CGFloat = 16
    static let controlSpacing: CGFloat = 12
    static let cornerRadius: CGFloat = 22
    static let controlsHeight = JarvisToolbarMetrics.nativeSurfaceHeight

    /// Match LazyVGrid.adaptive: fit as many minimum-width columns as possible,
    /// then distribute the remaining width equally across the cards.
    static func columns(availableWidth: CGFloat, zoom: HistoryGridZoomLevel) -> Int {
        let spacing = HistoryGridMetrics.clipboardGridSpacing
        return max(1, Int((availableWidth + spacing) / (zoom.cardWidth + spacing)))
    }

    static func cardWidth(availableWidth: CGFloat, zoom: HistoryGridZoomLevel) -> CGFloat {
        let count = CGFloat(columns(availableWidth: availableWidth, zoom: zoom))
        return max(1, (availableWidth - (count - 1) * HistoryGridMetrics.clipboardGridSpacing) / count)
    }

    static func galleryHeight(availableWidth: CGFloat, zoom: HistoryGridZoomLevel) -> CGFloat {
        // SwiftUI rounds each adaptive row to layout points. Reserve both
        // rounded rows so the second row is never clipped by fractional widths.
        ceil(HistoryGridLayout.cardHeight(forCardWidth: cardWidth(availableWidth: availableWidth, zoom: zoom))) * 2
            + HistoryGridMetrics.clipboardGridSpacing
    }

    static func initialHeight(for width: CGFloat) -> CGFloat {
        inset * 2 + controlsHeight + controlSpacing
            + galleryHeight(availableWidth: width - inset * 2, zoom: .regular)
    }

    static var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0, bottomLeadingRadius: ClipboardPanelLayout.cornerRadius,
            bottomTrailingRadius: ClipboardPanelLayout.cornerRadius, topTrailingRadius: 0,
            style: .continuous
        )
    }
}

struct ClipboardPanelView: View {
    @Environment(AppModel.self) private var app
    @State private var searchText = ""
    @State private var selectedTimeFilter: ClipboardTimeFilter = .threeDays
    @State private var selectedCategory: ClipboardViewFilter = .all
    @State private var selectedItemID: UUID?
    @State private var gridZoom: HistoryGridZoomLevel = .regular
    @State private var toolbarHeight = ClipboardPanelLayout.controlsHeight
    @State private var galleryWidth: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onHeightChange: (CGFloat) -> Void

    private var filteredItems: [ClipboardItem] {
        ClipboardFilterLogic.filteredItems(
            from: app.clipboardItems, searchText: searchText,
            timeFilter: selectedTimeFilter, category: selectedCategory
        )
    }

    private var selectedItem: ClipboardItem? {
        app.clipboardItems.first { $0.id == selectedItemID }
    }

    private var shelfGridZoom: Binding<HistoryGridZoomLevel> {
        Binding(get: { gridZoom }, set: { zoom in
            withAnimation(reduceMotion ? nil : ClipboardPanelMotion.content) { gridZoom = zoom }
        })
    }

    var body: some View {
        let items = filteredItems
        GeometryReader { geometry in
            let availableWidth = galleryWidth ?? max(1, geometry.size.width - ClipboardPanelLayout.inset * 2)
            let galleryHeight = ClipboardPanelLayout.galleryHeight(availableWidth: availableWidth, zoom: gridZoom)
            let topInset = ClipboardPanelLayout.inset + toolbarHeight + ClipboardPanelLayout.controlSpacing
            let panelHeight = topInset + galleryHeight + ClipboardPanelLayout.inset
            GlassEffectContainer {
                ZStack(alignment: .top) {
                    ScrollView {
                        ClipboardHistoryGallery(
                            items: items,
                            gridZoom: gridZoom,
                            selectedItemID: selectedItemID,
                            hasQuery: !searchText.isEmpty || selectedTimeFilter != .all || selectedCategory != .all,
                            emptyStateHeight: galleryHeight,
                            onSelect: { selectedItemID = $0.id },
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
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                            if width > 0 {
                                galleryWidth = width
                            }
                        }
                    }
                    // Insets belong to the scroll content, allowing cards to
                    // continue behind the floating toolbar as in the main window.
                    .contentMargins(.top, topInset, for: .scrollContent)
                    .contentMargins(.horizontal, ClipboardPanelLayout.inset, for: .scrollContent)
                    .contentMargins(.top, topInset, for: .scrollIndicators)
                    .scrollEdgeEffectStyle(.soft, for: .top)
                    .padding(.bottom, ClipboardPanelLayout.inset)

                    controls
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { toolbarHeight = $0 }
                        .padding(.horizontal, ClipboardPanelLayout.inset)
                        .padding(.top, ClipboardPanelLayout.inset)
                }
                // Apply glass to the content container so the system keeps
                // its foreground sharp and toolbar glass correctly grouped.
                .glassEffect(.regular, in: ClipboardPanelLayout.shape)
                .clipShape(ClipboardPanelLayout.shape)
                .onChange(of: panelHeight, initial: true) { _, height in onHeightChange(height) }
            }
        }
        .jarvisTheme(app.themePreference, systemColorScheme: app.systemColorScheme)
        .jarvisToastOverlay(app.toastMessage)
        .onChange(of: app.clipboardItems) { _, items in
            if let selectedItemID, !items.contains(where: { $0.id == selectedItemID }) {
                self.selectedItemID = nil
            }
        }
    }

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: ClipboardPanelLayout.controlSpacing) {
                filters
                actions
                search
            }
            .fixedSize()
            VStack(spacing: ClipboardPanelLayout.controlSpacing) {
                filters
                HStack(spacing: ClipboardPanelLayout.controlSpacing) {
                    actions
                    search
                }
            }
            .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var filters: some View {
        HStack(spacing: ClipboardPanelLayout.controlSpacing) {
            JarvisToolbarGroupedPicker(
                items: ClipboardTimeFilter.allCases, selection: $selectedTimeFilter, title: \.title
            )
            JarvisToolbarGroupedPicker(
                items: ClipboardViewFilter.allCases,
                selection: $selectedCategory,
                title: { $0 == .all ? "全部类型" : $0.title }
            )
            .accessibilityLabel("内容类型筛选")
            .help("按内容类型筛选")
        }
        .fixedSize()
        .frame(height: ClipboardPanelLayout.controlsHeight)
    }

    private var actions: some View {
        HStack(spacing: ClipboardPanelLayout.controlSpacing) {
            HistoryGridZoomControl(selection: shelfGridZoom)
                .frame(height: ClipboardPanelLayout.controlsHeight)
                .glassEffect(.regular, in: Capsule())
            ClipboardHistoryActionToolbar(selectedItem: selectedItem, onClearSelection: { selectedItemID = nil })
                .frame(height: ClipboardPanelLayout.controlsHeight)
                .glassEffect(.regular, in: Capsule())
        }
        .fixedSize()
        .frame(height: ClipboardPanelLayout.controlsHeight)
    }

    private var search: some View {
        ClipboardSearchField(text: $searchText, placeholder: "搜索文本、文件名…")
            .frame(height: ClipboardPanelLayout.controlsHeight)
            .glassEffect(.regular, in: Capsule())
    }
}
