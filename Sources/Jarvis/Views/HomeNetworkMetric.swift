import AppKit
import SwiftUI

struct HomeNetworkMetric: View {
    let upload: Double?
    let download: Double?
    let history: [Double]
    let display: HomeNetworkDisplay
    var onCopied: (String) -> Void
    @State private var showsRealAddress = false
    @State private var showsActions = false
    @State private var titleWidth: CGFloat = 0
    @State private var hideRealAddress: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                rates
                identities
            }
            HomeSparkline(values: history, color: .purple, maximum: nil, height: 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .onHover(perform: hover)
        .onDisappear {
            hideRealAddress?.cancel()
        }
    }

    private var rates: some View {
        HStack(spacing: 10) {
            rate("arrow.up", HomeDashboardFormatting.rate(upload))
            rate("arrow.down", HomeDashboardFormatting.rate(download))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("上传 \(HomeDashboardFormatting.rate(upload))，下载 \(HomeDashboardFormatting.rate(download))")
    }

    private func rate(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
            Text(text)
        }
        .font(.system(size: 13, weight: .semibold))
        .monospacedDigit()
    }

    private var identities: some View {
        VStack(alignment: .leading, spacing: 3) {
            identityRow(.real)
            if display.vpnActive {
                identityRow(.proxy)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onPreferenceChange(HomeNetworkTitleWidth.self) { width in
            guard width > titleWidth + 0.5 else { return }
            titleWidth = width
        }
    }

    private func identityRow(_ role: Role) -> some View {
        HStack(spacing: 6) {
            title(role)
            value(role)
            actionSlots(role)
        }
    }

    private func title(_ role: Role) -> some View {
        Text(role.title)
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            .overlay {
                GeometryReader { geo in
                    Color.clear.preference(key: HomeNetworkTitleWidth.self, value: geo.size.width)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(width: titleWidth > 0 ? titleWidth : nil, alignment: .leading)
    }

    private func value(_ role: Role) -> some View {
        let address = role.address(in: display)
        let revealed = role == .proxy || showsRealAddress
        return HStack(spacing: 4) {
            Text(shown(address, revealed: revealed))
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityLabel(revealed ? (address ?? "无") : "已隐藏")
            if let place = role.place(in: display) {
                Text("· \(place)")
                    .lineLimit(1)
                    .layoutPriority(1)
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actionSlots(_ role: Role) -> some View {
        let address = role.address(in: display)
        return HStack(spacing: 4) {
            actionSlot {
                if role == .real, address != nil {
                    eyeButton()
                }
            }
            actionSlot {
                if let address {
                    copyButton(address, title: role.title)
                }
            }
        }
        .opacity(actionsVisible ? 1 : 0)
        .offset(x: actionsVisible || reduceMotion ? 0 : 6)
        .animation(JarvisMotion.animation(JarvisMotion.hover, reduceMotion: reduceMotion), value: actionsVisible)
        .allowsHitTesting(actionsVisible)
        .accessibilityHidden(!actionsVisible)
    }

    private func actionSlot(@ViewBuilder content: () -> some View) -> some View {
        content().frame(width: 14, height: 14)
    }

    private func eyeButton() -> some View {
        iconButton(
            showsRealAddress ? "eye.slash" : "eye",
            help: showsRealAddress ? "隐藏真实IP" : "查看真实IP"
        ) {
            toggleRealAddress()
        }
    }

    private func copyButton(_ address: String, title: String) -> some View {
        iconButton("doc.on.doc", help: "复制\(title)") {
            copy(address, title: title)
        }
    }

    private func shown(_ address: String?, revealed: Bool) -> String {
        guard let address else { return "—" }
        return revealed ? address : HomeNetworkFormatting.masked(address)
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 14, height: 14)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private func hover(_ hovering: Bool) {
        showsActions = hovering
    }

    private func toggleRealAddress() {
        hideRealAddress?.cancel()
        showsRealAddress.toggle()
        guard showsRealAddress else { return }
        hideRealAddress = Task { @MainActor in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            showsRealAddress = false
        }
    }

    private func copy(_ address: String, title: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let copied = pasteboard.setString(address, forType: .string)
        onCopied(copied ? "已复制\(title)" : "复制失败，请重试")
    }

    private var actionsVisible: Bool {
        showsActions || voiceOver
    }

    private enum Role {
        case real
        case proxy

        var title: String {
            self == .real ? "真实IP" : "代理IP"
        }

        func address(in display: HomeNetworkDisplay) -> String? {
            self == .real ? display.realAddress : display.vpnAddress
        }

        func place(in display: HomeNetworkDisplay) -> String? {
            self == .real ? display.realCountry : display.vpnCountry
        }
    }
}

private struct HomeNetworkTitleWidth: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
