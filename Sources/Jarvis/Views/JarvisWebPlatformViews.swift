import AppKit
import SwiftUI
import WebKit

/// 工具栏里的分段选择器：一枚自绘的胶囊容器，里面是等宽内边距的选中胶囊。
///
/// 容器自己画，不用系统给工具栏 item 铺的那层底：那层的内边距由 AppKit 决定，
/// 和我们的胶囊对不齐（会多出一圈），也给不出「参考图」那种嵌合感。
/// 调用点要配 `JarvisToolbarSurface`，把系统那层关掉，否则会叠成双层。
struct JarvisToolbarGroupedPicker<Item: Identifiable & Hashable, Icon: View>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String
    /// 可选项的图标。文字型的分段控件（截图/剪贴板的时间筛选）不传。
    @ViewBuilder var icon: (Item, Bool) -> Icon

    var body: some View {
        toolbarContainer
            .jarvisGlass(in: Capsule(), interactive: false)
    }

    /// 容器那一层（内边距 + 行高），不带玻璃。
    ///
    /// 离屏渲染看不到 glass，测试要量「选中胶囊到容器四边等距」就得拿到这一层——
    /// 内边距的表达式只有这一处，测试量的和生产用的是同一个。
    var toolbarContainer: some View {
        selectionRow
            .padding(JarvisSegmentedMetrics.toolbarGroupPadding)
            .frame(height: JarvisToolbarMetrics.nativeSurfaceHeight)
    }

    private var selectionRow: some View {
        HStack(spacing: JarvisSegmentedMetrics.itemSpacing) {
            ForEach(items) { item in
                let isSelected = selection == item
                Button {
                    selection = item
                } label: {
                    HStack(spacing: JarvisSpacing.iconGap) {
                        icon(item, isSelected)
                            .frame(width: 16, height: 16)
                        Text(title(item))
                            .font(isSelected ? JarvisTypography.controlEmphasis : JarvisTypography.control)
                            .foregroundStyle(isSelected ? Color.white : Color.secondary)
                    }
                    .padding(.horizontal, JarvisSpacing.controlGap)
                    .frame(height: JarvisSegmentedMetrics.compactItemHeight)
                    .jarvisSelectionPill(isSelected: isSelected)
                    .overlay {
                        Capsule()
                            .strokeBorder(
                                Color.jarvisAccent.opacity(isSelected ? 0.42 : 0),
                                lineWidth: 0.75
                            )
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.97, pressedOpacity: 0.84))
                // Pre-select on hover, matching the toolbar chips the other
                // modules use.
                .jarvisHoverFeedback(in: Capsule(), scale: 1.02)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

extension JarvisToolbarGroupedPicker where Icon == EmptyView {
    /// 纯文字的分段控件（时间筛选、图库来源这类）。
    init(items: [Item], selection: Binding<Item>, title: @escaping (Item) -> String) {
        self.init(items: items, selection: selection, title: title) { _, _ in EmptyView() }
    }
}

struct JarvisWebPlatformActionCluster: View {
    @ObservedObject var controller: JarvisWebPlatformController

    var body: some View {
        HStack(spacing: JarvisSpacing.hairline) {
            JarvisToolbarIconButton(
                systemName: "house",
                help: "主页",
                hoverScale: 1,
                action: controller.goHome
            )
            JarvisToolbarIconButton(
                systemName: "chevron.left",
                help: "后退",
                isEnabled: controller.canGoBack,
                hoverScale: 1,
                action: controller.goBack
            )
            JarvisToolbarIconButton(
                systemName: "chevron.right",
                help: "前进",
                isEnabled: controller.canGoForward,
                hoverScale: 1,
                action: controller.goForward
            )
            JarvisToolbarIconButton(
                systemName: controller.isLoading ? "xmark" : "arrow.clockwise",
                help: controller.isLoading ? "停止加载" : "刷新",
                hoverScale: 1,
                action: controller.reloadOrStop
            )
        }
        .padding(.horizontal, JarvisToolbarMetrics.iconClusterPadding)
        .frame(height: JarvisToolbarMetrics.controlSize)
        // The enclosing ToolbarItem supplies the native toolbar group surface.
        // Do not add a second custom glass capsule inside it.
    }
}

struct JarvisWebPlatformBrowserPage: View {
    let controller: JarvisWebPlatformController

    var body: some View {
        ZStack {
            JarvisWebPlatformWebView(controller: controller)

            // Only the status overlay subscribes to the controller. The page
            // itself must not: a site that rewrites its URL or back-history as
            // you type (every search box that updates the address bar) would
            // otherwise re-render this host view on every keystroke.
            JarvisWebPlatformPageStatusOverlay(controller: controller)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Keep the page unmasked to avoid compositing every keystroke and video frame.
        .jarvisPanelBackground(cornerRadius: 0)
    }
}

private struct JarvisWebPlatformPageStatusOverlay: View {
    @ObservedObject var controller: JarvisWebPlatformController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if case .loading = controller.loadState {
                JarvisInlineLoadingState()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(JarvisMotion.contentTransition(reduceMotion: reduceMotion))
            }

            if case let .failed(loadError) = controller.loadState {
                VStack(spacing: JarvisSpacing.itemGap) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(Color.jarvisAccent)
                    Text("\(controller.platform.title) 页面加载失败")
                        .font(JarvisTypography.cardTitle)
                    Text(loadError)
                        .font(JarvisTypography.secondary)
                        .foregroundStyle(Color.jarvisTextSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                    Button("重新加载") {
                        controller.reloadOrStop()
                    }
                    .buttonStyle(JarvisPrimaryButtonStyle())
                }
                .padding(JarvisSpacing.pageInset)
                .frame(maxWidth: 420)
                .jarvisContentSurface(cornerRadius: JarvisMetrics.cardRadius)
                .transition(JarvisMotion.contentTransition(reduceMotion: reduceMotion))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(
            JarvisMotion.animation(JarvisMotion.content, reduceMotion: reduceMotion),
            value: controller.loadState
        )
    }
}

private struct JarvisWebPlatformWebView: NSViewRepresentable {
    let controller: JarvisWebPlatformController

    func makeNSView(context _: Context) -> JarvisWebPlatformViewContainer {
        let container = controller.webViewContainer
        container.embed(controller.webView)
        return container
    }

    func updateNSView(_ container: JarvisWebPlatformViewContainer, context _: Context) {
        // `embed` also synchronizes the fullscreen corner cover. Keep that
        // synchronization, while making the no-op path inside the container
        // cheap enough for SwiftUI's frequent representable updates.
        container.embed(controller.webView)
    }
}
