import SwiftUI

/// Shared by the wallpaper, screenshot, and clipboard galleries.
enum JarvisScrollToTop {
    /// How far the gallery must move before the return control appears.
    static let visibilityThreshold: CGFloat = 500

    static func shouldShow(visibleMinY: CGFloat) -> Bool {
        visibleMinY >= visibilityThreshold
    }
}

struct JarvisScrollToTopButton: View {
    let accessibilityLabel: String
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(
                JarvisMotion.animation(JarvisMotion.content, reduceMotion: reduceMotion)
            ) {
                action()
            }
        } label: {
            Label("返回顶部", systemImage: "arrow.up")
        }
        .buttonStyle(JarvisSecondaryButtonStyle())
        .accessibilityLabel(accessibilityLabel)
        .padding(.trailing, JarvisSpacing.cardInset)
        .padding(.bottom, JarvisSpacing.cardInset)
    }
}

private struct JarvisScrollToTopModifier: ViewModifier {
    let accessibilityLabel: String
    let scrollToTop: () -> Void
    @State private var isShown = false

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { geometry in
                JarvisScrollToTop.shouldShow(visibleMinY: geometry.visibleRect.minY)
            } action: { _, shouldShow in
                isShown = shouldShow
            }
            .overlay(alignment: .bottomTrailing) {
                if isShown {
                    JarvisScrollToTopButton(
                        accessibilityLabel: accessibilityLabel,
                        action: scrollToTop
                    )
                }
            }
    }
}

/// Scroll view used by the screenshot and clipboard galleries.
/// The return control matches the wallpaper gallery: same distance, label, and placement.
struct JarvisBackToTopScroll<Content: View>: View {
    private let accessibilityLabel: String
    private let topID: String
    private let content: Content

    init(_ accessibilityLabel: String, id topID: String, @ViewBuilder content: () -> Content) {
        self.accessibilityLabel = accessibilityLabel
        self.topID = topID
        self.content = content()
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                content.id(topID)
            }
            .jarvisBackToTopControl(accessibilityLabel: accessibilityLabel) {
                scrollProxy.scrollTo(topID, anchor: .top)
            }
        }
    }
}

extension View {
    /// Shows the wallpaper gallery's return control after the same scroll distance.
    func jarvisBackToTopControl(
        accessibilityLabel: String,
        scrollToTop: @escaping () -> Void
    ) -> some View {
        modifier(
            JarvisScrollToTopModifier(
                accessibilityLabel: accessibilityLabel,
                scrollToTop: scrollToTop
            )
        )
    }
}
