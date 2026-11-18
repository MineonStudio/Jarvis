import SwiftUI

struct WallpaperHoverActions: View {
    let isFavorite: Bool
    let isSetting: Bool
    let setTitle: String
    let onToggleFavorite: () -> Void
    let onSet: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                actionRow(iconOnly: false)
                actionRow(iconOnly: true)
                VStack(spacing: JarvisSpacing.iconGap) {
                    favoriteButton
                    setButton(iconOnly: true)
                }
            }
        }
    }

    private func actionRow(iconOnly: Bool) -> some View {
        HStack(spacing: 0) {
            favoriteButton
            Spacer(minLength: JarvisSpacing.iconGap)
            setButton(iconOnly: iconOnly)
        }
    }

    private var favoriteButton: some View {
        Button(action: onToggleFavorite) {
            if isFavorite {
                Image(systemName: "heart.fill").foregroundStyle(.pink)
            } else {
                Image(systemName: "heart")
            }
        }
        .buttonStyle(WallpaperHoverButtonStyle(iconOnly: true))
        .accessibilityLabel(isFavorite ? "取消收藏" : "收藏")
        .help(isFavorite ? "取消收藏" : "收藏")
    }

    private func setButton(iconOnly: Bool) -> some View {
        Button(action: onSet) {
            if iconOnly {
                Image(systemName: "checkmark")
            } else {
                Text(setTitle)
                    .lineLimit(1)
            }
        }
        .buttonStyle(WallpaperHoverButtonStyle(iconOnly: iconOnly))
        .disabled(isSetting)
        .accessibilityLabel(setTitle)
        .help("设置已连接显示器的桌面壁纸。锁屏及所有空间的行为由 macOS 系统设置管理。")
    }
}

private struct WallpaperHoverButtonStyle: ButtonStyle {
    let iconOnly: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(iconOnly ? .system(size: JarvisToolbarMetrics.iconSize, weight: .semibold) : JarvisTypography.control)
            .foregroundStyle(.primary)
            .padding(.horizontal, iconOnly ? 0 : JarvisSpacing.buttonHorizontalInset)
            .frame(minWidth: JarvisToolbarMetrics.controlSize, minHeight: JarvisToolbarMetrics.controlSize)
            .glassEffect(isEnabled && !reduceMotion ? .regular.interactive() : .regular, in: Capsule())
            .opacity(isEnabled ? 1 : 0.6)
            .contentShape(Capsule())
            .fixedSize()
    }
}
