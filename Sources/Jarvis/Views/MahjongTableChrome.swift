import SwiftUI

/// Match-table felt and tile shell. Tags and buttons use the same semantic
/// colors as the rest of the app, so they are not listed here.
struct MahjongTablePalette {
    var scheme: ColorScheme

    var isDark: Bool {
        scheme == .dark
    }

    var felt: Color {
        isDark
            ? Color(red: 0.035, green: 0.12, blue: 0.09)
            : Color(red: 0.56, green: 0.76, blue: 0.66)
    }

    var feltAccentTop: Double {
        isDark ? 0.68 : 0.22
    }

    var feltAccentBottom: Double {
        isDark ? 0.38 : 0.08
    }

    var discardFill: Color {
        Color.black.opacity(isDark ? 0.14 : 0.08)
    }

    var discardStroke: Color {
        isDark ? Color.white.opacity(0.07) : Color(red: 0.10, green: 0.26, blue: 0.18).opacity(0.28)
    }

    var tileBackGreen: [Color] {
        isDark
            ? [Color(red: 0.20, green: 0.59, blue: 0.33), Color(red: 0.09, green: 0.39, blue: 0.23)]
            : [Color(red: 0.30, green: 0.68, blue: 0.42), Color(red: 0.16, green: 0.48, blue: 0.30)]
    }

    var tileSide: Color {
        isDark
            ? Color(red: 0.035, green: 0.22, blue: 0.12)
            : Color(red: 0.10, green: 0.34, blue: 0.20)
    }

    func tileShadowOpacity(compact: Bool) -> Double {
        if isDark {
            return compact ? 0.08 : 0.18
        }
        return compact ? 0.14 : 0.26
    }
}

extension View {
    /// Title and ready tags share one frosted capsule. Text follows the
    /// appearance; the glass itself is the system liquid glass, untinted.
    func mahjongAdaptiveTag() -> some View {
        font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .jarvisGlass(in: Capsule(), interactive: false)
    }
}

struct MahjongTableView: View {
    var model: MahjongGameWindowModel

    private var game: MahjongGame {
        model.game
    }

    private var archive: MahjongArchiveStore {
        model.archive
    }

    private var lanRoomService: MahjongLANRoomService {
        model.lanRoomService
    }

    private var roundNotice: String? {
        model.roundNotice
    }

    private var roundSettlement: MahjongArchiveSettlement? {
        model.roundSettlement
    }

    private var onNextRound: () -> Void {
        model.onNextRound
    }

    private var onExit: () -> Void {
        model.onExit
    }

    var body: some View {
        Group {
            if game.isStarted {
                MahjongOverheadTable(
                    game: game,
                    archive: archive,
                    lanRoomService: lanRoomService,
                    roundNotice: roundNotice,
                    roundSettlement: roundSettlement,
                    onNextRound: onNextRound,
                    onExit: onExit
                )
            } else {
                MahjongLaunchView(model: model)
            }
        }
        .modifier(MahjongGameAudioFeedback(model: model))
    }

    /// Rules, duration, wall count, and exit. Its own rounded panel, above the felt.
    private var matchInfoBar: some View {
        ZStack {
            HStack(spacing: 8) {
                titleTag(game.ruleset.title)
                titleTag(game.mode.rawValue)
                if game.mode == .lan, let code = lanRoomService.roomCode {
                    titleTag("房间码 \(code)")
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                if let endedAt = game.roundEndedAt {
                    titleTag("对局时长  \(formattedRoundDuration(at: endedAt))")
                } else if game.roundStartedAt != nil {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        titleTag("对局时长  \(formattedRoundDuration(at: context.date))")
                    }
                } else {
                    titleTag("对局时长 00:00")
                }
                titleTag("牌组剩余  \(game.wall.count) 张")
            }
            .frame(maxWidth: .infinity, alignment: .center)

            HStack {
                Spacer(minLength: 0)
                Button("退出游戏", action: onExit)
                    .buttonStyle(JarvisSecondaryButtonStyle())
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(minHeight: 36)
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
    }

    private func feltBackground(_ palette: MahjongTablePalette) -> some View {
        palette.felt
            .overlay {
                LinearGradient(
                    colors: [
                        Color.jarvisAccent.opacity(palette.feltAccentTop),
                        Color.jarvisAccent.opacity(palette.feltAccentBottom)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
    }

    private func titleTag(_ text: String) -> some View {
        Text(text)
            .mahjongAdaptiveTag()
    }

    private func formattedRoundDuration(at date: Date) -> String {
        guard let start = game.roundStartedAt else { return "00:00" }
        let totalSeconds = max(0, Int(date.timeIntervalSince(start)))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    @ViewBuilder
    private var workflowControls: some View {
        switch game.phase {
        case .waitingForReady:
            EmptyView()

        case .dealing:
            EmptyView()

        case .choosingMissingSuit:
            if game.currentResponderSeat == game.localSeat {
                HStack(spacing: 10) {
                    ForEach(MahjongSuit.allCases, id: \.self) { suit in
                        Button(suit.shortName) { game.chooseMissingSuit(suit) }
                            .buttonStyle(JarvisSecondaryButtonStyle())
                    }
                }
                .padding(12)
            }

        case .choosingMultiplier:
            HStack(spacing: 8) {
                ForEach(game.localMultiplierOptions, id: \.self) { value in
                    Button(value == 1 ? "不加倍" : "×\(value)") { game.chooseMultiplier(value) }
                        .buttonStyle(JarvisSecondaryButtonStyle())
                }
            }
            .padding(12)

        case .responding:
            HStack(spacing: 8) {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(game.humanResponseOptions.filter { $0.kind != .pass }) { option in
                            Button(callTitle(option)) { game.respond(to: option) }
                                .buttonStyle(JarvisSecondaryButtonStyle(tint: option.kind == .win ? .orange : nil))
                        }
                    }
                }
                .scrollIndicators(.automatic)
                Button("过") { game.respond(to: MahjongCallOption(kind: .pass, heldTiles: [])) }
                    .buttonStyle(JarvisSecondaryButtonStyle())
            }
            .padding(12)
            .frame(maxWidth: 560)

        case .playing where game.isHumanTurn:
            if game.canSelfDraw || !game.availableKongTiles.isEmpty {
                HStack(spacing: 8) {
                    if game.canSelfDraw {
                        Button("自摸") { game.claimSelfDraw() }
                            .buttonStyle(JarvisSecondaryButtonStyle(tint: .orange))
                    }
                    ForEach(game.availableKongTiles) { tile in
                        Button("杠【\(tile.accessibilityName)】") { game.declareKong(tile) }
                            .buttonStyle(JarvisSecondaryButtonStyle())
                    }
                }
                .padding(10)
            }

        case .roundEnded:
            EmptyView()

        default:
            EmptyView()
        }
    }

    private func callTitle(_ option: MahjongCallOption) -> String {
        guard !option.heldTiles.isEmpty else { return option.kind.rawValue }
        let tiles = option.heldTiles.map(\.accessibilityName).joined(separator: "、")
        return "\(option.kind.rawValue)【\(tiles)】"
    }
}

enum MahjongDiscardMetrics {
    static let tileSpacing: CGFloat = 2
    static let safetyInset: CGFloat = 12
    static let zoneGap: CGFloat = MahjongSeatAreaMetrics.spacingBetweenAreas
    static let horizontalWidth: CGFloat = 7 * 48 + 6 * tileSpacing + 2 * safetyInset
    static let horizontalHeight: CGFloat = 4 * 68 + 3 * tileSpacing + 2 * safetyInset
    static let sideWidth: CGFloat = 4 * 68 + 3 * tileSpacing + 2 * safetyInset
    static let sideHeight: CGFloat = 7 * 48 + 6 * tileSpacing + 2 * safetyInset
    static let sideAreaHeight: CGFloat = 2 * horizontalHeight + zoneGap

    static func center(for seat: Int, width: CGFloat, height: CGFloat) -> CGPoint {
        let totalWidth = sideWidth * 2 + horizontalWidth + zoneGap * 2
        let leftCenterX = width / 2 - totalWidth / 2 + sideWidth / 2
        let middleCenterX = leftCenterX + sideWidth / 2 + zoneGap + horizontalWidth / 2
        let rightCenterX = middleCenterX + horizontalWidth / 2 + zoneGap + sideWidth / 2
        let topCenterY = height / 2 - (horizontalHeight / 2 + zoneGap / 2)
        let bottomCenterY = height / 2 + (horizontalHeight / 2 + zoneGap / 2)
        switch seat {
        case 2:
            return CGPoint(x: middleCenterX, y: topCenterY)
        case 3:
            return CGPoint(x: rightCenterX, y: height / 2)
        case 1:
            return CGPoint(x: leftCenterX, y: height / 2)
        default:
            return CGPoint(x: middleCenterX, y: bottomCenterY)
        }
    }

    static func scaledCenter(for seat: Int, width: CGFloat, height: CGFloat, scale: CGFloat) -> CGPoint {
        let center = center(for: seat, width: width, height: height)
        return CGPoint(
            x: width / 2 + (center.x - width / 2) * scale,
            y: height / 2 + (center.y - height / 2) * scale
        )
    }
}

struct MahjongHandDisplayTile: Identifiable {
    let id: String
    let tile: MahjongTile
}

enum MahjongSeatAreaMetrics {
    static let tileWidth: CGFloat = 48
    static let tileHeight: CGFloat = 68
    static let tileSpacing: CGFloat = 2
    static let safeInset: CGFloat = 12
    static let drawGap: CGFloat = tileWidth
    static let meldGroupGap: CGFloat = 8
    // Fifteen slots: thirteen base tiles, one tile-width draw gap, and the drawn tile.
    // Keep the safety inset on both ends; side seats use these same dimensions rotated.
    static let handLength: CGFloat = 15 * tileWidth + 12 * tileSpacing + 2 * safeInset
    static let areaThickness: CGFloat = tileHeight + 2 * safeInset
    static let spacingBetweenAreas: CGFloat = 12
    static let operationHeight: CGFloat = 64
    static let operationMaxWidth: CGFloat = 620
    /// Main-view hand tiles draw larger than the other three seats.
    static let localHandScale: CGFloat = 1.5

    static func operationCenterY(in boardHeight: CGFloat) -> CGFloat {
        boardHeight - 55 - areaThickness / 2 - spacingBetweenAreas
            - areaThickness - spacingBetweenAreas - operationHeight / 2
    }
}

enum MahjongPlayerInfoCardMetrics {
    static let gap: CGFloat = 12
    /// Compact slot: avatar, nickname, and balance. The detail popover holds the rest.
    static let compactWidth: CGFloat = 252
    static let compactHeight: CGFloat = 100
    /// Left and right seats stack avatar, nickname, and balance on separate rows.
    static let sideWidth: CGFloat = 136
    static let sideHeight: CGFloat = 180

    static func height(areaThickness: CGFloat) -> CGFloat {
        areaThickness + gap + areaThickness
    }

    static func width(areaThickness: CGFloat) -> CGFloat {
        height(areaThickness: areaThickness) + 56
    }
}

struct MahjongPlayerInfoCard: View {
    let profile: MahjongPlayerArchive
    let seatName: String
    let missingSuit: MahjongSuit?
    let countdownActive: Bool
    let countdownDeadline: Date?
    var stacksVertically = false
    var detailArrowEdge: Edge = .bottom

    @State private var showsDetail = false
    @State private var isAvatarHovered = false

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var content: some View {
        if stacksVertically {
            VStack(spacing: 8) {
                avatarButton
                nicknameText
                balanceRow
            }
        } else {
            HStack(alignment: .center, spacing: 12) {
                avatarButton
                VStack(alignment: .leading, spacing: 4) {
                    nicknameText
                    balanceRow
                }
                .frame(maxWidth: 140, alignment: .leading)
            }
        }
    }

    private var nicknameText: some View {
        Text(profile.nickname)
            .font(.system(size: 19, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private var balanceRow: some View {
        HStack(spacing: 4) {
            Image(systemName: "centsign.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(red: 0.96, green: 0.76, blue: 0.22))
                .accessibilityHidden(true)
            Text(profile.balance.formatted())
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary.opacity(0.88))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("余额\(profile.balance.formatted())毛格子")
    }

    private var avatarButton: some View {
        Button {
            showsDetail = true
        } label: {
            avatar
        }
        .buttonStyle(.plain)
        .onHover { isAvatarHovered = $0 }
        .scaleEffect(isAvatarHovered ? 1.06 : 1)
        .animation(.easeInOut(duration: 0.15), value: isAvatarHovered)
        .help("查看\(profile.nickname)的资料")
        .accessibilityLabel("查看\(profile.nickname)的资料")
        .popover(isPresented: $showsDetail, arrowEdge: detailArrowEdge) {
            MahjongPlayerDetailPanel(
                profile: profile,
                missingSuit: missingSuit
            )
        }
    }

    private var avatar: some View {
        ZStack {
            let avatarSize: CGFloat = countdownActive ? 72 : 64
            let avatarFrameSize = avatarSize + 8
            MahjongArchiveAvatar(profile: profile, size: avatarSize)
                .frame(width: avatarSize, height: avatarSize)
            if countdownActive {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
                    let remaining = countdownDeadline?.timeIntervalSince(context.date) ?? 20
                    MahjongCountdownRing(
                        progress: CGFloat(min(max(remaining / 20, 0), 1)),
                        size: avatarFrameSize
                    )
                }
            }
        }
        .frame(width: 72, height: 72)
        .accessibilityHidden(true)
    }
}

struct MahjongPlayerDetailPanel: View {
    let profile: MahjongPlayerArchive
    let missingSuit: MahjongSuit?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                MahjongArchiveAvatar(profile: profile, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.nickname)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("毛格子：\(profile.balance.formatted())")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let missingSuit {
                Text("缺门：\(missingSuit.shortName)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            HStack(spacing: 0) {
                metric("胜率", "\(profile.winRate)%")
                metric("胜场", "\(profile.wins)")
                metric("败场", "\(profile.losses)")
                metric("逃跑", "\(profile.escapes)")
            }
            Text("语音：\(profile.voiceGender.displayName)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 300, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        var parts = [
            profile.nickname,
            "余额\(profile.balance)毛格子",
            "胜率\(profile.winRate)%",
            "胜场\(profile.wins)",
            "败场\(profile.losses)",
            "逃跑\(profile.escapes)",
            "语音\(profile.voiceGender.displayName)"
        ]
        if let missingSuit {
            parts.insert("缺门\(missingSuit.shortName)", at: 2)
        }
        return parts.joined(separator: "，")
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MahjongCountdownRing: View {
    let progress: CGFloat
    let size: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let trackColor = colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.3)
        Canvas { context, size in
            let bounds = CGRect(x: 2, y: 2, width: size.width - 4, height: size.height - 4)
            let track = Path(roundedRect: bounds, cornerSize: CGSize(width: 14, height: 14))
            context.stroke(track, with: .color(trackColor), lineWidth: 3)

            let boundedProgress = min(max(progress, 0), 1)
            let segmentCount = Int((boundedProgress * 120).rounded(.up))
            guard segmentCount > 0 else { return }
            let activeColor = countdownColor(at: 1 - Double(boundedProgress))
            for index in 0 ..< segmentCount {
                let start = Double(index) / 120
                let end = min(Double(index + 1) / 120, Double(boundedProgress))
                let segment = track.trimmedPath(from: start, to: end)
                context.stroke(segment, with: .color(activeColor), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
        .frame(width: size, height: size)
    }

    private func countdownColor(at fraction: Double) -> Color {
        let green = (red: 0.20, green: 0.82, blue: 0.36)
        let yellow = (red: 1.0, green: 0.78, blue: 0.10)
        let red = (red: 0.96, green: 0.22, blue: 0.18)
        let start = fraction < 0.5 ? green : yellow
        let end = fraction < 0.5 ? yellow : red
        let amount = fraction < 0.5 ? fraction * 2 : (fraction - 0.5) * 2
        return Color(
            red: start.red + (end.red - start.red) * amount,
            green: start.green + (end.green - start.green) * amount,
            blue: start.blue + (end.blue - start.blue) * amount
        )
    }
}

struct MahjongHandTileHoverLift<Content: View>: View {
    let lift: CGFloat
    let content: Content
    @State private var isHovered = false

    init(lift: CGFloat, @ViewBuilder content: () -> Content) {
        self.lift = lift
        self.content = content()
    }

    var body: some View {
        content
            .offset(y: isHovered ? -lift : 0)
            .zIndex(isHovered ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

struct MahjongHandTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
