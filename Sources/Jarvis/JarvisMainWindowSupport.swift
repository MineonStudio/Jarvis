import AppKit

@MainActor
enum JarvisWindowAppearance {
    static func configure(for window: NSWindow) {
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = .textBackgroundColor
        window.sharingType = .readOnly
    }

    static func configureTransparentTitlebar(for window: NSWindow) {
        configure(for: window)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
    }
}

enum JarvisWindowLayoutMetrics {
    /// A little extra room absorbs the split-view divider and fractional
    /// layout rounding, so the last card and its hover controls never touch
    /// the window edge.
    static let contentSafetyMargin: CGFloat = 8
    static let splitViewDividerAllowance: CGFloat = 1
    static let clipboardPanelHorizontalPadding: CGFloat = 40
    static let clipboardPanelTopPadding: CGFloat = 32
    static let clipboardPanelBottomPadding: CGFloat = 20
    static let clipboardPanelFooterHeight: CGFloat = 12
    static let clipboardPanelDividerHeight: CGFloat = 5
    static let clipboardMainCompactFilterBarHeight: CGFloat =
        HistoryGridMetrics.topControlHeight * 3
            + HistoryGridMetrics.clipboardFilterToGridSpacing * 2
    static let clipboardPanelCompactFilterBarHeight: CGFloat =
        HistoryGridMetrics.topControlHeight * 2
            + HistoryGridMetrics.clipboardFilterToGridSpacing
    static let contentBodyTopSpacing: CGFloat = JarvisMetrics.shellContentSpacing
    static let emptyStateMinimumHeight: CGFloat = 190

    private static var clipboardMinimumRowHeight: CGFloat {
        HistoryGridMetrics.clipboardCardHeight
            + HistoryGridMetrics.clipboardContentSpacing
            + HistoryGridMetrics.clipboardMetadataHeight
    }

    private static var clipboardMinimumContentHeight: CGFloat {
        max(clipboardMinimumRowHeight, emptyStateMinimumHeight)
    }

    static var mainWindowMinimumWidth: CGFloat {
        let clipboardDetailWidth = max(
            HistoryGridMetrics.clipboardCardWidth,
            HistoryGridMetrics.clipboardSearchFieldWidth
        ) + (JarvisMetrics.pageInset * 2)
        let windowLayoutDetailWidth =
            WindowLayoutDisplayMetrics.minimumGridWidth + (JarvisMetrics.pageInset * 2)
        let detailWidth = max(
            clipboardDetailWidth,
            windowLayoutDetailWidth,
            JarvisWebPlatformLayoutMetrics.minimumTopBarWidth
        )
        return ceil(
            JarvisMetrics.sidebarMinimumWidth
                + splitViewDividerAllowance
                + (JarvisMetrics.shellHorizontalPadding * 2)
                + detailWidth
                + contentSafetyMargin
        )
    }

    static var mainWindowMinimumHeight: CGFloat {
        let clipboardPageHeight = clipboardMainCompactFilterBarHeight
            + HistoryGridMetrics.imageSpacing
            + clipboardMinimumContentHeight
            + (JarvisMetrics.pageInset * 2)
        return ceil(
            contentBodyTopSpacing
                + (JarvisMetrics.shellVerticalPadding * 2)
                + clipboardPageHeight
                + contentSafetyMargin
        )
    }

    static var clipboardPanelMinimumWidth: CGFloat {
        let contentWidth = max(
            HistoryGridMetrics.clipboardCardWidth,
            HistoryGridMetrics.clipboardSearchFieldWidth
        )
        return ceil(contentWidth + clipboardPanelHorizontalPadding + contentSafetyMargin)
    }

    static var clipboardPanelMinimumHeight: CGFloat {
        let bodyHeight = clipboardPanelCompactFilterBarHeight
            + HistoryGridMetrics.imageSpacing
            + clipboardPanelDividerHeight
            + HistoryGridMetrics.imageSpacing
            + clipboardMinimumContentHeight
            + HistoryGridMetrics.imageSpacing
            + clipboardPanelFooterHeight
        return ceil(
            clipboardPanelTopPadding
                + bodyHeight
                + clipboardPanelBottomPadding
                + contentSafetyMargin
        )
    }
}

struct JarvisWindowFrameStore {
    private static let defaultsKey = "Jarvis.MainWindow.frame"

    func load() -> NSRect? {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let frame = try? JSONDecoder().decode(JarvisStoredWindowFrame.self, from: data)
        {
            return frame.rect
        }

        // Migrate the string format used by the earlier window autosave fix.
        if let legacyFrame = UserDefaults.standard.string(forKey: Self.defaultsKey) {
            let rect = NSRectFromString(legacyFrame)
            guard rect.width > 0, rect.height > 0 else { return nil }
            save(rect)
            return rect
        }

        return nil
    }

    func save(_ rect: NSRect) {
        let frame = JarvisStoredWindowFrame(rect: rect)
        guard let data = try? JSONEncoder().encode(frame) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}

private struct JarvisStoredWindowFrame: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(rect: NSRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.width
        height = rect.height
    }

    var rect: NSRect {
        NSRect(x: x, y: y, width: width, height: height)
    }
}
