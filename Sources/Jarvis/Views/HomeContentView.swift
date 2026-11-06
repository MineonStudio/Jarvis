import SwiftUI

struct JarvisHomeView: View {
    let pointerTracker: JarvisHomePointerTracker
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var monitor = HomeSystemMonitor()

    var body: some View {
        GeometryReader { geometry in
            let layout = HomeDashboardLayout(size: geometry.size)
            dashboard(size: layout.canvas)
                .frame(width: layout.canvas.width, height: layout.canvas.height)
                .scaleEffect(layout.scale, anchor: .topLeading)
        }
        .buttonStyle(JarvisSecondaryButtonStyle())
        .environment(\.jarvisFlatControls, true)
        .environment(\.jarvisContentButtonShadows, true)
        .background(Color.jarvisBackground)
        .ignoresSafeArea(.container, edges: .top)
        .toolbar { JarvisToolbarPlaceholder(id: "home.placeholder") }
        .onAppear { app.refreshPermissionStatus() }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await monitor.run()
        }
    }

    private func dashboard(size: CGSize) -> some View {
        let contentHeight = size.height - 16
        let headerHeight: CGFloat = 64
        let metricsHeight = min(160, max(134, contentHeight * 0.215))
        let rankingHeight = min(128, contentHeight * 0.19)
        let overviewHeight = contentHeight - headerHeight - metricsHeight - rankingHeight - 30
        return VStack(spacing: 10) {
            HomeDashboardHeader(pointerTracker: pointerTracker)
                .background { Color.clear.contentShape(Rectangle()).gesture(WindowDragGesture()) }
                .frame(height: headerHeight)
            HomeMetricsGrid(monitor: monitor, width: size.width - 32).frame(height: metricsHeight)
            HStack(spacing: 12) {
                HomeSystemOverviewCard(monitor: monitor)
                HomeCalendarCard()
                HomeTipsCard(illustrationHeight: min(96, max(52, overviewHeight - 174)))
            }.frame(height: overviewHeight)
            HomeQuickToolsCard().frame(height: rankingHeight)
        }
        .padding(.horizontal, 16).padding(.vertical, JarvisToolbarMetrics.leadingInset)
    }
}
