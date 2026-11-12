import SwiftUI

struct JarvisHomeView: View {
    let pointerTracker: JarvisHomePointerTracker
    let monitor: HomeSystemMonitor
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase

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
        // The hidden toolbar still occupies the top safe area. Drawing the
        // header through it clips the greeting and the clock.
        .background(Color.jarvisBackground.ignoresSafeArea())
        .toolbar { JarvisToolbarPlaceholder(id: "home.placeholder") }
        .onAppear { app.refreshPermissionStatus() }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await monitor.run()
        }
    }

    private func dashboard(size: CGSize) -> some View {
        let bands = HomeDashboardLayout.bands(contentHeight: size.height - 16)
        return VStack(spacing: 10) {
            HomeDashboardHeader(pointerTracker: pointerTracker)
                .background { Color.clear.contentShape(Rectangle()).gesture(WindowDragGesture()) }
                .frame(height: bands.header)
            HomeMetricsGrid(monitor: monitor, width: size.width - 32).frame(height: bands.metrics)
            HStack(spacing: 12) {
                HomeSystemOverviewCard(monitor: monitor)
                HomeCalendarCard()
                HomeTipsCard(illustrationHeight: min(96, max(52, bands.overview - 174)))
            }.frame(height: bands.overview)
            HomeQuickToolsCard().frame(height: bands.ranking)
        }
        .padding(.horizontal, 16).padding(.vertical, JarvisToolbarMetrics.leadingInset)
    }
}
