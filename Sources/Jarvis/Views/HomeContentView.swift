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
        // Home has no toolbar actions. Extend only its detail content into
        // the transparent titlebar area, leaving the native sidebar controls
        // and the window's minimum-size constraints intact.
        .ignoresSafeArea(.container, edges: .top)
        .buttonStyle(JarvisSecondaryButtonStyle())
        .environment(\.jarvisFlatControls, true)
        .environment(\.jarvisContentButtonShadows, true)
        .background(Color.jarvisBackground.ignoresSafeArea())
        .toolbar { JarvisToolbarPlaceholder(id: "home.placeholder") }
        .onAppear {
            app.refreshPermissionStatus()
            monitor.refreshThermalStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
            monitor.refreshThermalStatus()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await monitor.run()
        }
    }

    private func dashboard(size: CGSize) -> some View {
        let bands = HomeDashboardLayout.bands(
            contentHeight: size.height - HomeDashboardLayout.topPadding - HomeDashboardLayout.bottomPadding,
            showsThermalGuidance: monitor.snapshot.thermalStatus.guidance != nil
        )
        return VStack(spacing: HomeDashboardLayout.rowSpacing) {
            HomeDashboardHeader(pointerTracker: pointerTracker)
                .background { Color.clear.contentShape(Rectangle()).gesture(WindowDragGesture()) }
                .allowsWindowActivationEvents(true)
                .frame(height: bands.header)
            HomeMetricsGrid(monitor: monitor, width: size.width - HomeDashboardLayout.horizontalPadding * 2)
                .frame(height: bands.metrics)
            HStack(spacing: 12) {
                HomeSystemOverviewCard(monitor: monitor)
                HomeCalendarCard()
                HomeTipsCard(illustrationHeight: min(96, max(52, bands.overview - 174)))
            }.frame(height: bands.overview)
            HomeQuickToolsCard().frame(height: bands.ranking)
        }
        .padding(.horizontal, HomeDashboardLayout.horizontalPadding)
        .padding(.top, HomeDashboardLayout.topPadding)
        .padding(.bottom, HomeDashboardLayout.bottomPadding)
    }
}
