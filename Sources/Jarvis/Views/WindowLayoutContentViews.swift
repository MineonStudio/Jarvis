import SwiftUI

enum WindowLayoutDisplayMetrics {
    static let minimumContentWidth: CGFloat = 520
}

struct WindowLayoutView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        JarvisContentArea(
            leadingToolbar: {
                JarvisToolbarPlaceholder(id: "window-layout.placeholder")
            },
            trailingToolbar: {
                ToolbarItem(placement: .automatic) { EmptyView() }
            },
            content: {
                ScrollView {
                    VStack(alignment: .leading, spacing: JarvisSpacing.sectionGap) {
                        JarvisCard {
                            VStack(alignment: .leading, spacing: JarvisSpacing.groupGap) {
                                SettingsCardHeader(title: "窗口布局", systemImage: "rectangle.3.group")
                                Text("按 F5 打开顶部布局面板，点击布局块，调整当前激活的窗口。")
                                    .font(JarvisTypography.body)
                                Text("支持左右分屏、上下分屏和四角分屏。按 Esc、再次按 F5 或点击面板外取消。")
                                    .font(JarvisTypography.secondary)
                                    .foregroundStyle(Color.jarvisTextSecondary)
                                Button("选择窗口布局 · F5") { app.showWindowLayoutPicker() }
                                    .buttonStyle(JarvisPrimaryButtonStyle())
                            }
                        }
                        WindowDragLayoutSettingsCard()
                    }
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, JarvisMetrics.pageInset)
                }
            }
        )
    }
}
