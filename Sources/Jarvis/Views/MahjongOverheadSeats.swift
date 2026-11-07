import SwiftUI

struct MahjongSeatPlaque: View {
    let profile: MahjongPlayerArchive
    let missingSuit: MahjongSuit?
    let multiplier: Int?
    let showsMultiplier: Bool
    let isDealer: Bool
    /// 画面上下一行排开；左右两侧一个标签一行。
    let stacksTagsVertically: Bool
    let viewPosition: Int
    let titlebarInset: CGFloat

    @State private var showsDetail = false

    var body: some View {
        plaque
            .frame(
                width: sideSeat ? MahjongOverheadMetrics.verticalPlayerSize.width : MahjongOverheadMetrics.horizontalPlayerSize.width,
                height: sideSeat ? MahjongOverheadMetrics.verticalPlayerSize.height : MahjongOverheadMetrics.horizontalPlayerSize.height,
                alignment: edgeAlignment
            )
            .position(MahjongOverheadMetrics.plaqueCenter(viewPosition, titlebarInset: titlebarInset))
    }

    private var sideSeat: Bool {
        viewPosition == 1 || viewPosition == 3
    }

    private var edgeAlignment: Alignment {
        switch viewPosition {
        case 0: .bottom
        case 1: .leading
        case 2: .top
        default: .trailing
        }
    }

    @ViewBuilder
    private var plaque: some View {
        if sideSeat {
            VStack(spacing: 6) {
                avatar
                nickname
                tags
            }
        } else {
            HStack(alignment: .center, spacing: 8) {
                avatar
                VStack(alignment: .leading, spacing: 3) {
                    nickname
                    tags
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var nickname: some View {
        Text(profile.nickname)
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(MahjongVisualTheme.ivory)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private var tags: some View {
        Group {
            if stacksTagsVertically {
                VStack(alignment: sideSeat ? .center : .leading, spacing: 4) {
                    tagLabels
                }
            } else {
                HStack(spacing: 4) {
                    tagLabels
                }
            }
        }
        .font(.system(size: 11, weight: .bold, design: .rounded))
        .foregroundStyle(MahjongVisualTheme.ivory)
    }

    @ViewBuilder
    private var tagLabels: some View {
        tag {
            HStack(spacing: 3) {
                Image(systemName: "centsign.circle.fill")
                    .foregroundStyle(Color(red: 0.96, green: 0.76, blue: 0.22))
                    .accessibilityHidden(true)
                Text(profile.balance.formatted())
            }
        }
        .accessibilityLabel("余额\(profile.balance.formatted())毛格子")
        if isDealer {
            tag { Text("庄") }
                .accessibilityLabel("庄家")
        }
        if showsMultiplier {
            tag { Text(multiplier.map { "×\($0)" } ?? "待加倍") }
                .accessibilityLabel(multiplier.map { "加倍 ×\($0)" } ?? "等待加倍")
        }
        if let missingSuit {
            tag { Text("缺\(missingSuit.shortName)") }
                .accessibilityLabel("缺\(missingSuit.shortName)")
        }
    }

    private func tag(@ViewBuilder content: () -> some View) -> some View {
        content()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .glassEffect(.regular, in: Capsule())
    }

    private var avatar: some View {
        Button {
            showsDetail = true
        } label: {
            MahjongArchiveAvatar(profile: profile, size: 60)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showsDetail, arrowEdge: popoverEdge) {
            MahjongPlayerDetailPanel(
                profile: profile,
                missingSuit: missingSuit
            )
        }
        .accessibilityLabel("查看\(profile.nickname)的资料")
    }

    private var popoverEdge: Edge {
        switch viewPosition {
        case 0: .top
        case 1: .trailing
        case 2: .bottom
        default: .leading
        }
    }
}

struct MahjongCountdownTint: Equatable {
    var red: Double
    var green: Double
    var blue: Double

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    static let green = Self(red: 0.22, green: 0.78, blue: 0.34)
    static let yellow = Self(red: 0.98, green: 0.80, blue: 0.16)
    static let red = Self(red: 0.91, green: 0.20, blue: 0.16)

    /// Remaining time: 1 is green, 0.5 is yellow, 0 is red.
    static func color(progress: Double) -> Self {
        let t = min(max(progress, 0), 1)
        if t >= 1 {
            return .green
        }
        if t <= 0 {
            return .red
        }
        if t == 0.5 {
            return .yellow
        }
        if t > 0.5 {
            return mix(.yellow, .green, (t - 0.5) / 0.5)
        }
        return mix(.red, .yellow, t / 0.5)
    }

    private static func mix(_ from: Self, _ to: Self, _ amount: Double) -> Self {
        Self(
            red: from.red + (to.red - from.red) * amount,
            green: from.green + (to.green - from.green) * amount,
            blue: from.blue + (to.blue - from.blue) * amount
        )
    }
}

struct MahjongCountdownArc: View {
    var progress: Double

    var body: some View {
        let span = min(max(progress, 0), 1)
        Circle()
            // The gap opens at 12 o'clock and grows clockwise as time runs out.
            .trim(from: 1 - span, to: 1)
            .stroke(
                MahjongCountdownTint.color(progress: span).color,
                style: StrokeStyle(lineWidth: 3, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
            .padding(1)
    }
}
