import SwiftUI

struct WindowDragLayoutSettingsCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        SettingsContentPanel {
            HStack(spacing: JarvisSpacing.groupGap) {
                Toggle("窗口拖拽布局", isOn: Binding(
                    get: { app.windowDragLayoutEnabled },
                    set: { app.updateWindowDragLayoutEnabled($0) }
                ))
                .font(SettingsTypography.itemTitle)
                .jarvisSwitchAccent()
            }
        }
    }
}
