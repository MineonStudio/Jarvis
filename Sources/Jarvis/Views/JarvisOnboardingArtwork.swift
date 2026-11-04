import SwiftUI

/// Code-native illustrations explain the feature without capturing the user's
/// screen or microphone before they choose to grant access.
struct JarvisOnboardingArtwork: View {
    let step: JarvisOnboardingStep

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.jarvisAccent.opacity(0.07))
                .frame(width: 300, height: 300)
            Circle()
                .strokeBorder(Color.jarvisAccent.opacity(0.10), lineWidth: 1)
                .frame(width: 336, height: 336)

            illustration
        }
        .frame(height: 344)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(step.title)
    }

    @ViewBuilder
    private var illustration: some View {
        switch step {
        case .screenCapture: screenCapture
        case .accessibility: windowLayout
        case .microphone: microphone
        case .welcome: welcome
        }
    }

    private var screenCapture: some View {
        demoWindow(title: "留住这一刻") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.jarvisAccent.opacity(0.22))
                        .frame(width: 58, height: 58)
                        .overlay(Image(systemName: "sparkles").font(.title2).foregroundStyle(Color.jarvisAccent))
                    VStack(alignment: .leading, spacing: 8) {
                        line(width: 100)
                        line(width: 76)
                        line(width: 90)
                    }
                }
                line(width: 192)
                line(width: 156)
                HStack(spacing: 8) {
                    Image(systemName: "crop")
                    Text("框选 · 标注 · 保存")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Color.jarvisAccent)
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(Color.jarvisAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(22)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.jarvisAccent, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .padding(12)
            }
        }
        .rotationEffect(.degrees(-4))
        .overlay(alignment: .bottomTrailing) {
            badge("随手一截", icon: "checkmark")
                .offset(x: 12, y: 18)
        }
    }

    private var windowLayout: some View {
        demoWindow(title: "你的工作空间") {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(Color.jarvisAccent)
                    line(width: 62)
                    line(width: 48)
                    line(width: 60)
                    Spacer()
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(Color.jarvisAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                VStack(spacing: 8) {
                    layoutPane("safari")
                    layoutPane("note.text")
                }
                .frame(maxWidth: .infinity)
            }
            .padding(14)
            .frame(height: 190)
        }
        .overlay(alignment: .bottom) {
            badge("刚刚好的布局", icon: "rectangle.3.group")
                .offset(y: 24)
        }
    }

    private var microphone: some View {
        demoWindow(title: "会议记录") {
            VStack(spacing: 20) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Color.jarvisAccent)
                HStack(spacing: 5) {
                    ForEach(Array([12, 22, 35, 20, 42, 54, 34, 20, 44, 28, 48, 32, 18, 26, 12].enumerated()), id: \.offset) { _, height in
                        Capsule()
                            .fill(Color.jarvisAccent.opacity(0.65))
                            .frame(width: 5, height: CGFloat(height))
                    }
                }
                Text("把每个好想法，记录下来")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        }
        .rotationEffect(.degrees(-3))
    }

    private var welcome: some View {
        ZStack {
            JarvisMascotView(diameter: 190, pointerDirection: nil, promptBubble: AnyView(EmptyView()))
            Image(systemName: "sparkle")
                .font(.system(size: 32))
                .foregroundStyle(Color.jarvisAccent)
                .offset(x: 112, y: -80)
            Image(systemName: "sparkle")
                .font(.system(size: 20))
                .foregroundStyle(Color.jarvisAccent.opacity(0.5))
                .offset(x: -110, y: 34)
            badge("你好，我是 Jarvis。", icon: "hand.wave")
                .offset(x: 38, y: 104)
        }
    }

    private func demoWindow(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                ForEach(0 ..< 3) { _ in
                    Circle().fill(.secondary.opacity(0.25)).frame(width: 6, height: 6)
                }
                Spacer()
                Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(14)
            Divider().opacity(0.4)
            content()
        }
        .frame(width: 280)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.08), radius: 22, y: 14)
    }

    private func layoutPane(_ icon: String) -> some View {
        Image(systemName: icon)
            .foregroundStyle(Color.jarvisAccent.opacity(0.7))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.jarvisAccent.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
    }

    private func line(width: CGFloat) -> some View {
        Capsule().fill(.primary.opacity(0.10)).frame(width: width, height: 5)
    }

    private func badge(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: Capsule())
    }
}
