import SwiftUI

struct WindowDragLayoutSettingsCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        JarvisCard {
            HStack(spacing: JarvisSpacing.groupGap) {
                SettingsCardHeader(title: "窗口拖拽布局", systemImage: "rectangle.3.group")
                Spacer(minLength: 8)
                Toggle("窗口拖拽布局", isOn: Binding(
                    get: { app.windowDragLayoutEnabled },
                    set: { app.updateWindowDragLayoutEnabled($0) }
                ))
                .labelsHidden()
                .jarvisSwitchAccent()
            }
        }
    }
}
