import AppKit
import SwiftUI

enum ScreenRecordingToolbarLayout {
    static let width: CGFloat = 320
    static let height: CGFloat = 52
    static let padding: CGFloat = 8
    static let controlHeight: CGFloat = 36
    static let modeWidth: CGFloat = 40
    static let spacing: CGFloat = 6
    /// Leave space for native glass antialiasing and refraction outside its shape.
    static let glassOverflow: CGFloat = 8
    static var windowSize: CGSize {
        CGSize(width: width + glassOverflow * 2, height: height + glassOverflow * 2)
    }
}

extension View {
    /// 截图与录屏共用原生 Liquid Glass 胶囊。
    func captureToolbarGlassSurface() -> some View {
        glassEffect(.regular.interactive(), in: Capsule())
    }

    func captureToolbarSelection(isSelected: Bool, isHovered: Bool = false) -> some View {
        background(
            Color.primary.opacity(isSelected ? 0.14 : (isHovered ? 0.07 : 0)),
            in: Capsule()
        )
    }

    func screenRecordingToolbarSurface(width: CGFloat? = ScreenRecordingToolbarLayout.width) -> some View {
        GlassEffectContainer(spacing: ScreenRecordingToolbarLayout.spacing) {
            foregroundStyle(Color.primary)
                .buttonStyle(.plain)
                .frame(
                    width: width.map { $0 - ScreenRecordingToolbarLayout.padding * 2 },
                    height: ScreenRecordingToolbarLayout.controlHeight
                )
                .fixedSize(horizontal: true, vertical: false)
                .padding(ScreenRecordingToolbarLayout.padding)
                .captureToolbarGlassSurface()
        }
        .padding(ScreenRecordingToolbarLayout.glassOverflow)
    }

    func screenRecordingPrimaryButton(width: CGFloat = 72) -> some View {
        font(.system(size: 14, weight: .semibold))
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(.accentColor)
            .frame(width: width, height: ScreenRecordingToolbarLayout.controlHeight)
    }
}
