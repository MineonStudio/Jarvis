import AppKit
import SwiftUI

// MARK: - 下拉菜单

/// 工具栏上的下拉筛选控件。
///
/// 这块原本长在 `Theme.swift` 里，占了那个文件的小一半：它自带一个 NSPanel、
/// 外部点击监听和屏幕边缘定位，是个完整的组件，而不是主题的一部分。
struct JarvisDropdownOption: Identifiable, Equatable {
    let id: String
    let title: String
    let colorHex: String?

    init(id: String, title: String, colorHex: String? = nil) {
        self.id = id
        self.title = title
        self.colorHex = colorHex
    }
}

enum JarvisDropdownMetrics {
    /// 触发器贴合当前选中值，只保留一个很小的下限，避免单字标签出现过于局促的胶囊。
    /// 按"最长选项"预留宽度会让短文本的控件右侧空出一大截。
    static let minimumTriggerWidth: CGFloat = 56
    /// 弹层仍按"当前值 + 最长选项"定宽，选项胶囊继续等宽对齐。
    static let minimumMenuWidth: CGFloat = 96
    static let maximumControlWidth: CGFloat = 320
    static let optionSpacing: CGFloat = JarvisMetrics.segmentedItemSpacing
    static let triggerGap: CGFloat = JarvisMetrics.segmentedControlPadding
    static let menuEdgePadding: CGFloat = JarvisMetrics.segmentedControlPadding
    static let hoverScale: CGFloat = 1.01
    static let horizontalPadding: CGFloat = 10
    static let arrowSpacing: CGFloat = 5
    static let arrowPointSize: CGFloat = 10

    static func menuOriginY(anchor: CGRect, panelHeight: CGFloat, visibleFrame: CGRect) -> CGFloat {
        let below = anchor.minY - panelHeight - triggerGap
        let above = anchor.maxY + triggerGap
        let preferred = below >= visibleFrame.minY ? below : above
        return min(max(preferred, visibleFrame.minY), max(visibleFrame.minY, visibleFrame.maxY - panelHeight))
    }

    /// Width of the trigger's chevron at `arrowPointSize`. The trigger
    /// reserves the symbol's real width plus its spacing; a hand-picked
    /// fifteen points came up a point short, which clipped the longest title
    /// in a control — "超过 1 个月" lost its last character.
    static let arrowWidth: CGFloat = {
        let configuration = NSImage.SymbolConfiguration(
            pointSize: arrowPointSize,
            weight: .semibold
        )
        let symbolWidth = NSImage(
            systemSymbolName: "chevron.down",
            accessibilityDescription: nil
        )?
            .withSymbolConfiguration(configuration)?
            .size.width
        return symbolWidth ?? 11
    }()

    static func triggerWidth(
        for title: String,
        includesArrow: Bool = true,
        maximumWidth: CGFloat = maximumControlWidth
    ) -> CGFloat {
        width(
            for: [title],
            includesArrow: includesArrow,
            minimumWidth: minimumTriggerWidth,
            maximumWidth: maximumWidth
        )
    }

    static func menuWidth(
        for title: String,
        options: [JarvisDropdownOption],
        includesArrow: Bool = true,
        maximumWidth: CGFloat = maximumControlWidth
    ) -> CGFloat {
        width(
            for: [title] + options.map(\.title),
            includesArrow: includesArrow,
            minimumWidth: minimumMenuWidth,
            maximumWidth: maximumWidth
        )
    }

    /// 弹层和触发器左边缘对齐，和系统弹出菜单一致；贴近屏幕边缘时向内收，
    /// 保证整块弹层留在屏幕内。
    static func menuOriginX(
        anchorMinX: CGFloat,
        panelWidth: CGFloat,
        visibleFrame: CGRect
    ) -> CGFloat {
        let aligned = anchorMinX - menuEdgePadding
        let maximumX = visibleFrame.maxX - panelWidth
        return min(max(aligned, visibleFrame.minX), max(visibleFrame.minX, maximumX))
    }

    static func width(
        for titles: [String],
        includesArrow: Bool = true,
        minimumWidth: CGFloat,
        maximumWidth: CGFloat = maximumControlWidth
    ) -> CGFloat {
        let controlFont = NSFont.systemFont(ofSize: 13, weight: .medium)
        let widestTitle = titles
            .map { title in
                (title as NSString).size(withAttributes: [.font: controlFont]).width
            }
            .max() ?? 0
        let idealWidth = ceil(
            widestTitle
                + (horizontalPadding * 2)
                + (includesArrow ? arrowSpacing + arrowWidth : 0)
        )
        return min(max(idealWidth, minimumWidth), maximumWidth)
    }
}

/// Shared custom SwiftUI dropdown used by every value selector and action selector.
///
/// The toolbar trigger is an ordinary button so macOS 27 cannot collapse its
/// label into an icon-only menu trigger. Its transparent anchored panel owns
/// the independent pill options, hover state, selection highlight, animation,
/// and selection action from end to end.
struct JarvisDropdownMenu: View {
    let title: String
    let options: [JarvisDropdownOption]
    let selectionID: String?
    let accessibilityLabel: String
    let help: String
    let controlWidth: CGFloat?
    let maximumControlWidth: CGFloat
    let showsChevron: Bool
    let showsSelectedOption: Bool
    let usesLiquidGlass: Bool
    let isEnabled: Bool
    let searchThreshold: Int?
    let onSelect: (String) -> Void
    @State private var isPresented = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        title: String,
        options: [JarvisDropdownOption],
        selectionID: String? = nil,
        accessibilityLabel: String,
        help: String,
        controlWidth: CGFloat? = nil,
        maximumControlWidth: CGFloat = JarvisDropdownMetrics.maximumControlWidth,
        showsChevron: Bool = true,
        showsSelectedOption: Bool = false,
        usesLiquidGlass: Bool = false,
        isEnabled: Bool = true,
        searchThreshold: Int? = nil,
        onSelect: @escaping (String) -> Void
    ) {
        self.title = title
        self.options = options
        self.selectionID = selectionID
        self.accessibilityLabel = accessibilityLabel
        self.help = help
        self.controlWidth = controlWidth
        self.maximumControlWidth = maximumControlWidth
        self.showsChevron = showsChevron
        self.showsSelectedOption = showsSelectedOption
        self.usesLiquidGlass = usesLiquidGlass
        self.isEnabled = isEnabled
        self.searchThreshold = searchThreshold
        self.onSelect = onSelect
    }

    /// 触发器贴合当前选中值：按最长选项预留宽度会在短文本时留下大片空白。
    private var resolvedControlWidth: CGFloat {
        controlWidth ?? JarvisDropdownMetrics.triggerWidth(
            for: title,
            includesArrow: showsChevron,
            maximumWidth: maximumControlWidth
        )
    }

    /// 弹层宽度单独计算，仍然覆盖最长选项，切换选项时选项胶囊不会换宽度。
    private var resolvedMenuWidth: CGFloat {
        controlWidth ?? JarvisDropdownMetrics.menuWidth(
            for: title,
            options: options,
            includesArrow: showsChevron,
            maximumWidth: maximumControlWidth
        )
    }

    var body: some View {
        let width = resolvedControlWidth

        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: JarvisDropdownMetrics.arrowSpacing) {
                Text(title)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if showsChevron {
                    Image(systemName: "chevron.down")
                        .font(.system(size: JarvisDropdownMetrics.arrowPointSize, weight: .semibold))
                        .accessibilityHidden(true)
                }
            }
            .frame(width: width - (JarvisDropdownMetrics.horizontalPadding * 2))
        }
        .buttonStyle(JarvisToolbarButtonStyle.menu())
        .disabled(!isEnabled || options.isEmpty)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(title)
        .frame(width: width)
        .fixedSize(horizontal: true, vertical: false)
        .animation(
            JarvisMotion.animation(JarvisMotion.content, reduceMotion: reduceMotion),
            value: width
        )
        .modifier(JarvisDropdownTriggerGlassModifier(isEnabled: usesLiquidGlass))
        .background(
            JarvisDropdownMenuPanelPresenter(
                isPresented: $isPresented,
                options: options,
                selectionID: selectionID,
                showsSelectedOption: showsSelectedOption,
                controlWidth: resolvedMenuWidth,
                searchThreshold: searchThreshold,
                onSelect: { optionID in
                    onSelect(optionID)
                    isPresented = false
                }
            )
            .allowsHitTesting(false)
        )
    }
}

private struct JarvisDropdownTriggerGlassModifier: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.jarvisGlass(
                in: Capsule(),
                interactive: true
            )
        } else {
            content
        }
    }
}

/// 玻璃胶囊选项。主窗口工具栏和截图里的目标语言菜单共用选中、悬浮和依次展开。
struct JarvisDropdownPillMenuList: View {
    let options: [JarvisDropdownOption]
    let selectionID: String?
    let showsSelectedOption: Bool
    let controlWidth: CGFloat
    var searchThreshold: Int?
    var maximumHeight: CGFloat = 400
    let onSelect: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealsOptions = false
    @State private var highlightedOptionID: String?
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool

    private var showsSearch: Bool {
        searchThreshold.map { options.count > $0 } ?? false
    }

    private var visibleOptions: [JarvisDropdownOption] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return options.filter { option in
            (showsSelectedOption || option.id != selectionID)
                && (query.isEmpty || option.title.localizedStandardContains(query))
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            if showsSearch {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索模型", text: $searchText)
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                        .accessibilityLabel("搜索模型")
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("清除搜索")
                    }
                }
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                Text("\(visibleOptions.count) / \(options.count) 个模型")
                    .font(JarvisTypography.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if options.count > 10 {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        LazyVStack(alignment: .leading, spacing: JarvisDropdownMetrics.optionSpacing) {
                            if visibleOptions.isEmpty {
                                Text("没有匹配的模型")
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, minHeight: 48)
                            } else {
                                optionButtons
                            }
                        }
                    }
                    .scrollIndicators(.visible)
                    .frame(height: min(
                        CGFloat(options.count) * (JarvisToolbarMetrics.controlSize
                            + JarvisDropdownMetrics.optionSpacing),
                        max(48, maximumHeight - (showsSearch ? 86 : 8))
                    ))
                    .onAppear {
                        if let selectionID {
                            proxy.scrollTo(selectionID, anchor: .center)
                        }
                    }
                    .onChange(of: searchText) { _, _ in
                        if let first = visibleOptions.first {
                            proxy.scrollTo(first.id, anchor: .top)
                        }
                    }
                }
            } else {
                optionRows
            }
        }
        .frame(width: controlWidth, alignment: .leading)
        .padding(JarvisDropdownMetrics.menuEdgePadding)
        .task {
            await Task.yield()
            revealsOptions = true
            searchFocused = showsSearch
        }
        .onDisappear { highlightedOptionID = nil }
    }

    private var optionRows: some View {
        VStack(alignment: .leading, spacing: JarvisDropdownMetrics.optionSpacing) {
            optionButtons
        }
        .frame(width: controlWidth, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var optionButtons: some View {
        ForEach(visibleOptions) { option in
            let isSelected = selectionID == option.id
            let isHighlighted = highlightedOptionID == option.id

            Button {
                onSelect(option.id)
            } label: {
                HStack(spacing: 8) {
                    if let colorHex = option.colorHex,
                       let color = Self.color(fromHex: colorHex)
                    {
                        Circle()
                            .fill(color)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(Color.primary.opacity(0.22), lineWidth: 0.7))
                            .accessibilityHidden(true)
                    }
                    Text(option.title)
                }
            }
            .buttonStyle(
                JarvisDropdownPillButtonStyle(
                    controlWidth: controlWidth,
                    isSelected: isSelected,
                    isHighlighted: isHighlighted
                )
            )
            .accessibilityLabel(option.title)
            .opacity(revealsOptions ? 1 : 0)
            .offset(y: revealsOptions ? 0 : -8)
            .animation(
                JarvisMotion.animation(
                    JarvisMotion.content.delay(
                        options.count > 10 ? 0 : Double(visibleOptions.firstIndex(of: option) ?? 0) * 0.045
                    ),
                    reduceMotion: reduceMotion
                ),
                value: revealsOptions
            )
            .id(option.id)
            .onHover { isHovering in
                withAnimation(
                    JarvisMotion.animation(
                        JarvisMotion.hover,
                        reduceMotion: reduceMotion
                    )
                ) {
                    highlightedOptionID = isHovering ? option.id : nil
                }
            }
        }
    }

    private static func color(fromHex hex: String) -> Color? {
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        return Color(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}

private struct JarvisDropdownPillButtonStyle: ButtonStyle {
    let controlWidth: CGFloat
    let isSelected: Bool
    let isHighlighted: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(isSelected ? JarvisTypography.controlEmphasis : JarvisTypography.control)
            .foregroundStyle(
                isSelected
                    ? Color.white
                    : Color.primary
            )
            .lineLimit(1)
            .padding(.horizontal, JarvisDropdownMetrics.horizontalPadding)
            .frame(
                width: controlWidth,
                height: JarvisToolbarMetrics.controlSize,
                alignment: .leading
            )
            .contentShape(Capsule())
            .jarvisGlass(
                // Keep the material identity stable while the pointer
                // moves between options. Changing a glass tint on every
                // hover asks macOS to rebuild the material and briefly
                // exposes the transparent intermediate state.
                tint: isSelected ? Color.jarvisAccent : nil,
                in: Capsule(),
                interactive: false
            )
            .overlay {
                if isHighlighted, !isSelected {
                    Capsule()
                        .fill(JarvisMotion.hoverPillTint)
                        .allowsHitTesting(false)
                }
            }
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(
                reduceMotion
                    ? 1
                    : (isHighlighted ? JarvisDropdownMetrics.hoverScale : (configuration.isPressed ? 0.98 : 1)),
                anchor: .center
            )
            .animation(
                JarvisMotion.animation(
                    JarvisMotion.buttonPress,
                    reduceMotion: reduceMotion
                ),
                value: configuration.isPressed
            )
            .animation(
                JarvisMotion.animation(
                    JarvisMotion.hover,
                    reduceMotion: reduceMotion
                ),
                value: isHighlighted
            )
    }
}

private struct JarvisDropdownMenuPanelPresenter: NSViewRepresentable {
    @Binding var isPresented: Bool
    let options: [JarvisDropdownOption]
    let selectionID: String?
    let showsSelectedOption: Bool
    let controlWidth: CGFloat
    let searchThreshold: Int?
    let onSelect: (String) -> Void

    func makeNSView(context: Context) -> NSView {
        let anchorView = NSView(frame: .zero)
        context.coordinator.anchorView = anchorView
        return anchorView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(
            anchorView: nsView,
            isPresented: isPresented,
            options: options,
            selectionID: selectionID,
            showsSelectedOption: showsSelectedOption,
            controlWidth: controlWidth,
            searchThreshold: searchThreshold,
            onSelect: onSelect,
            dismiss: { isPresented = false }
        )
    }

    static func dismantleNSView(
        _: NSView,
        coordinator: Coordinator
    ) {
        coordinator.dismiss()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator {
        weak var anchorView: NSView?
        private var panel: NSPanel?
        private var outsideClickMonitor: Any?
        private var dismissAction: (() -> Void)?

        func update(
            anchorView: NSView,
            isPresented: Bool,
            options: [JarvisDropdownOption],
            selectionID: String?,
            showsSelectedOption: Bool,
            controlWidth: CGFloat,
            searchThreshold: Int?,
            onSelect: @escaping (String) -> Void,
            dismiss: @escaping () -> Void
        ) {
            self.anchorView = anchorView
            dismissAction = dismiss

            guard isPresented else {
                dismiss()
                return
            }

            if panel == nil {
                present(
                    options: options,
                    selectionID: selectionID,
                    showsSelectedOption: showsSelectedOption,
                    controlWidth: controlWidth,
                    searchThreshold: searchThreshold,
                    onSelect: onSelect,
                    dismiss: dismiss
                )
            } else {
                positionPanel()
            }
        }

        func dismiss() {
            if let outsideClickMonitor {
                NSEvent.removeMonitor(outsideClickMonitor)
                self.outsideClickMonitor = nil
            }

            guard let panel else { return }
            if let parentWindow = panel.parent {
                parentWindow.removeChildWindow(panel)
            }
            panel.orderOut(nil)
            panel.close()
            self.panel = nil
        }

        private func present(
            options: [JarvisDropdownOption],
            selectionID: String?,
            showsSelectedOption: Bool,
            controlWidth: CGFloat,
            searchThreshold: Int?,
            onSelect: @escaping (String) -> Void,
            dismiss: @escaping () -> Void
        ) {
            guard let anchorView, let parentWindow = anchorView.window else { return }

            let panel = JarvisDropdownMenuPanel(
                contentRect: .zero,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            let menu = JarvisDropdownPillMenuList(
                options: options,
                selectionID: selectionID,
                showsSelectedOption: showsSelectedOption,
                controlWidth: controlWidth,
                searchThreshold: searchThreshold,
                maximumHeight: min(400, (parentWindow.screen?.visibleFrame.height ?? 800) - 16),
                onSelect: { [weak self] optionID in
                    // 先提交外部选择；它可能触发父视图重绘。最后再写入关闭状态，
                    // 避免父视图因选择变化重绘时覆盖关闭状态并让面板保持打开。
                    onSelect(optionID)
                    dismiss()
                    self?.dismiss()
                    Task { @MainActor [weak self] in
                        await Task.yield()
                        dismiss()
                        self?.dismiss()
                    }
                }
            )
            let hostingView = NSHostingView(rootView: menu.jarvisAccentAware())
            let fittingSize = hostingView.fittingSize
            hostingView.frame = NSRect(origin: .zero, size: fittingSize)

            panel.setContentSize(fittingSize)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.isFloatingPanel = true
            panel.level = .popUpMenu
            panel.hidesOnDeactivate = true
            panel.isReleasedWhenClosed = false
            panel.becomesKeyOnlyIfNeeded = false
            panel.ignoresMouseEvents = false
            panel.collectionBehavior = [.transient, .fullScreenAuxiliary]
            panel.contentView = hostingView

            self.panel = panel
            parentWindow.addChildWindow(panel, ordered: .above)
            positionPanel()
            panel.makeKeyAndOrderFront(nil)
            installOutsideClickMonitor()
        }

        private func positionPanel() {
            guard
                let panel,
                let anchorView,
                let parentWindow = anchorView.window
            else {
                return
            }

            let anchorRect = parentWindow.convertToScreen(
                anchorView.convert(anchorView.bounds, to: nil)
            )
            let visibleFrame = parentWindow.screen?.visibleFrame
                ?? NSScreen.main?.visibleFrame
                ?? .zero
            let panelSize = panel.frame.size
            let originX = JarvisDropdownMetrics.menuOriginX(
                anchorMinX: anchorRect.minX,
                panelWidth: panelSize.width,
                visibleFrame: visibleFrame
            )
            let originY = JarvisDropdownMetrics.menuOriginY(
                anchor: anchorRect,
                panelHeight: panelSize.height,
                visibleFrame: visibleFrame
            )

            panel.setFrameOrigin(NSPoint(x: originX, y: originY))
        }

        private func installOutsideClickMonitor() {
            outsideClickMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .keyDown]
            ) { [weak self] event in
                guard let self, let panel = self.panel else { return event }

                if event.type == .keyDown {
                    if event.keyCode == 53 {
                        self.dismiss()
                        self.dismissAction?()
                        return nil
                    }
                    return event
                }

                if event.window === panel {
                    return event
                }

                // The trigger is also the close affordance. Consume the
                // second click after dismissing the panel so the button does
                // not toggle the binding back to `true` in the same event.
                if self.isAnchorClick(event) {
                    self.dismiss()
                    self.dismissAction?()
                    return nil
                }

                self.dismiss()
                self.dismissAction?()
                return event
            }
        }

        private func isAnchorClick(_ event: NSEvent) -> Bool {
            guard
                let eventWindow = event.window,
                let anchorView,
                let anchorWindow = anchorView.window
            else {
                return false
            }

            let pointOnScreen = eventWindow.convertToScreen(
                NSRect(origin: event.locationInWindow, size: .zero)
            ).origin
            let anchorRect = anchorWindow.convertToScreen(
                anchorView.convert(anchorView.bounds, to: nil)
            )
            return anchorRect.contains(pointOnScreen)
        }
    }
}

@MainActor
private final class JarvisDropdownMenuPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}
