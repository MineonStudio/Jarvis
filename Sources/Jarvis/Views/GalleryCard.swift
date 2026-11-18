import AppKit
import SwiftUI

struct GalleryCard<Preview: View, HoverContent: View>: View {
    let size: CGSize
    let isSelected: Bool
    var enablesHoverZoom = true
    let onClick: (Int) -> Void
    @ViewBuilder let preview: () -> Preview
    @ViewBuilder let hoverContent: () -> HoverContent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: HistoryGridMetrics.clipboardCornerRadius, style: .continuous)
    }

    var body: some View {
        let showsAccentBorder = isHovered || isSelected
        preview()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scaleEffect(
                enablesHoverZoom && isHovered && !reduceMotion ? HistoryGridMetrics.clipboardPreviewHoverScale : 1
            )
            .animation(JarvisMotion.animation(JarvisMotion.hover, reduceMotion: reduceMotion), value: isHovered)
            .frame(width: size.width, height: size.height)
            .clipShape(shape)
            .jarvisContentSurface(cornerRadius: HistoryGridMetrics.clipboardCornerRadius)
            .contentShape(shape)
            .gesture(GalleryCardClick(onClick: onClick))
            .overlay(alignment: .bottomLeading) {
                if isHovered {
                    hoverContent()
                        .padding(min(10, min(size.width, size.height) * 0.08))
                        .transition(.opacity)
                }
            }
            .overlay {
                shape.strokeBorder(
                    showsAccentBorder ? Color.jarvisAccent : Color.primary.opacity(0.12),
                    lineWidth: showsAccentBorder ? 2 : 1
                )
                .allowsHitTesting(false)
            }
            .animation(JarvisMotion.animation(.easeOut(duration: 0.12), reduceMotion: reduceMotion), value: isSelected)
            .clipShape(shape)
            .jarvisGridCardShadow()
            .onHover { hovering in
                guard hovering != isHovered else { return }
                withAnimation(JarvisMotion.animation(JarvisMotion.content, reduceMotion: reduceMotion)) {
                    isHovered = hovering
                }
            }
    }
}

extension GalleryCard {
    init<Leading: View, Trailing: View>(
        size: CGSize, isSelected: Bool, enablesHoverZoom: Bool = true,
        onClick: @escaping (Int) -> Void,
        @ViewBuilder preview: @escaping () -> Preview,
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) where HoverContent == GalleryCardMetadata<Leading, Trailing> {
        self.init(size: size, isSelected: isSelected, enablesHoverZoom: enablesHoverZoom, onClick: onClick, preview: preview) {
            GalleryCardMetadata(size: size, leading: leading, trailing: trailing)
        }
    }
}

struct GalleryCardMetadata<Leading: View, Trailing: View>: View {
    let size: CGSize
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    badge(leading).fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 6)
                    badge(trailing).fixedSize(horizontal: true, vertical: false)
                }

                if size.height >= 145 {
                    VStack(alignment: .leading, spacing: 4) {
                        badge(leading)
                        badge(trailing)
                    }
                } else {
                    HStack(spacing: 4) {
                        badge(leading)
                        Spacer(minLength: 0)
                        badge(trailing)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func badge(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .font(JarvisTypography.captionEmphasis)
            .monospacedDigit()
            .foregroundStyle(.primary.opacity(0.78))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .glassEffect(.regular, in: Capsule())
    }
}

private struct GalleryCardClick: NSGestureRecognizerRepresentable {
    let onClick: (Int) -> Void

    func makeNSGestureRecognizer(context _: Context) -> ClickRecognizer {
        ClickRecognizer()
    }

    func handleNSGestureRecognizerAction(_ recognizer: ClickRecognizer, context _: Context) {
        onClick(recognizer.clickCount)
    }

    final class ClickRecognizer: NSClickGestureRecognizer {
        private(set) var clickCount = 1

        override func mouseUp(with event: NSEvent) {
            // Recognize each release immediately and use the system's click sequence.
            clickCount = event.clickCount
            super.mouseUp(with: event)
        }
    }
}
