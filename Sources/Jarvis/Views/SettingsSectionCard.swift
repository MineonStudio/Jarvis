import SwiftUI

extension EnvironmentValues {
    /// Settings and main-window content use solid controls; toolbars retain glass.
    @Entry var jarvisFlatControls = false
}

enum SettingsSurface {
    static let controlFill = Color.primary.opacity(0.07)
}

struct SettingsSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: JarvisSpacing.itemGap) {
            Text(title)
                .font(SettingsTypography.cardTitle)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)

            SettingsContentPanel {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsContentPanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(JarvisSpacing.cardInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .jarvisPanelBackground(cornerRadius: JarvisMetrics.cardRadius)
    }
}

struct SettingsCapsuleFieldModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.jarvisPanel.opacity(0.72), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
            }
            .contentShape(Capsule())
    }
}

struct SettingsFlatToggleStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: JarvisSpacing.itemGap) {
                configuration.label
                Spacer(minLength: 0)
                Capsule()
                    .fill(configuration.isOn ? Color.jarvisAccent : Color.primary.opacity(0.16))
                    .frame(width: 36, height: 22)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle()
                            .fill(.white)
                            .frame(width: 18, height: 18)
                            .padding(2)
                    }
                    .jarvisButtonShadow()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "已开启" : "已关闭")
        .accessibilityAddTraits(.isToggle)
        .opacity(isEnabled ? 1 : 0.45)
        .animation(
            JarvisMotion.animation(JarvisMotion.selection, reduceMotion: reduceMotion),
            value: configuration.isOn
        )
    }
}

/// A solid track and thumb, with pointer, keyboard, and accessibility adjustment.
struct SettingsFlatSlider: View {
    @Binding var value: Double
    let bounds: ClosedRange<Double>
    let accessibilityTitle: String
    let accessibilityValue: String
    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var isFocused: Bool

    private var fraction: CGFloat {
        CGFloat((value - bounds.lowerBound) / max(1, bounds.upperBound - bounds.lowerBound))
    }

    var body: some View {
        GeometryReader { proxy in
            let travel = max(1, proxy.size.width - 16)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12)).frame(height: 4)
                Capsule().fill(Color.jarvisAccent)
                    .frame(width: 8 + travel * fraction, height: 4)
                Circle().fill(Color.jarvisAccent)
                    .frame(width: 16, height: 16)
                    .offset(x: travel * fraction)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { event in
                guard isEnabled else { return }
                isFocused = true
                let progress = min(1, max(0, (event.location.x - 8) / travel))
                value = (bounds.lowerBound + Double(progress) * (bounds.upperBound - bounds.lowerBound)).rounded()
            })
        }
        .frame(height: 22)
        .focusable(isEnabled)
        .focused($isFocused)
        .onKeyPress(.leftArrow) { adjust(-1); return .handled }
        .onKeyPress(.rightArrow) { adjust(1); return .handled }
        .accessibilityElement()
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: adjust(1)
            case .decrement: adjust(-1)
            @unknown default: break
            }
        }
        .opacity(isEnabled ? 1 : 0.45)
    }

    private func adjust(_ delta: Double) {
        guard isEnabled else { return }
        value = min(bounds.upperBound, max(bounds.lowerBound, value + delta))
    }
}
