import AppKit
import SwiftUI

enum ScreenRecordingToolbarLayout {
    static let width: CGFloat = 320
    static let height: CGFloat = 52
    static let padding: CGFloat = 8
    static let controlHeight: CGFloat = 36
    static let modeWidth: CGFloat = 40
    static let spacing: CGFloat = 6
}

extension View {
    /// 截图与录屏共用原生 Liquid Glass 胶囊。
    func captureToolbarGlassSurface() -> some View {
        glassEffect(.clear.interactive(), in: Capsule())
    }

    func captureToolbarSelection(isSelected: Bool, isHovered: Bool = false) -> some View {
        background(
            Color.primary.opacity(isSelected ? 0.14 : (isHovered ? 0.07 : 0)),
            in: Capsule()
        )
    }

    func screenRecordingToolbarSurface(width: CGFloat? = ScreenRecordingToolbarLayout.width) -> some View {
        GlassEffectContainer(spacing: ScreenRecordingToolbarLayout.spacing) {
            foregroundStyle(Color.jarvisTextSecondary)
                .buttonStyle(.plain)
                .frame(
                    width: width.map { $0 - ScreenRecordingToolbarLayout.padding * 2 },
                    height: ScreenRecordingToolbarLayout.controlHeight
                )
                .fixedSize(horizontal: true, vertical: false)
                .padding(ScreenRecordingToolbarLayout.padding)
                .captureToolbarGlassSurface()
        }
    }

    func screenRecordingPrimaryButton(width: CGFloat = 72) -> some View {
        font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(.accentColor)
            .frame(width: width, height: ScreenRecordingToolbarLayout.controlHeight)
    }
}
