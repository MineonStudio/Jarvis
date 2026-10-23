import SwiftUI

// Orthographic top-down table. Tiles are 3D boxes on the felt. HUD stays in SwiftUI.

struct MahjongOverheadTable: View {
    let game: MahjongGame
    let archive: MahjongArchiveStore
    @ObservedObject var lanRoomService: MahjongLANRoomService
    let roundNotice: String?
    let roundSettlement: MahjongArchiveSettlement?
    let onNextRound: () -> Void
    let onExit: () -> Void

    var body: some View {
        MahjongOverheadFelt(
            game: game,
            archive: archive,
            lanRoomService: lanRoomService,
            roundNotice: roundNotice,
            roundSettlement: roundSettlement,
            onNextRound: onNextRound,
            onExit: onExit
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, .dark)
        .overlay(alignment: .top) {
            MahjongWindowTitlebarView(game: game, onExit: onExit)
                .environment(\.colorScheme, .dark)
                .frame(height: MahjongOverheadMetrics.titlebarHeight)
                .background {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(WindowDragGesture())
                        .allowsWindowActivationEvents(true)
                }
        }
        .ignoresSafeArea()
    }
}

struct MahjongWindowTitlebarView: View {
    let game: MahjongGame
    let onExit: () -> Void

    var body: some View {
        ZStack {
            HStack {
                Spacer(minLength: 12)
                MahjongAudioMuteButton()
                Button("退出游戏", action: onExit)
                    .buttonStyle(MahjongGameButtonStyle())
                    .help("退出游戏")
            }
            .padding(.horizontal, 12)
            // Center against the entire window, independent of the side content.
            clockAndWall
                .fixedSize()
                .allowsHitTesting(false)
        }
        .mahjongGlassGroup()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var clockAndWall: some View {
        HStack(spacing: 16) {
            if let endedAt = game.roundEndedAt {
                Text(Self.duration(from: game.roundStartedAt, to: endedAt))
            } else if game.roundStartedAt != nil {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Self.duration(from: game.roundStartedAt, to: context.date))
                }
            } else {
                Text("00:00")
            }
            Text("剩余 \(game.wall.count) 张")
        }
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .foregroundStyle(MahjongVisualTheme.muted)
        .monospacedDigit()
    }

    private static func duration(from start: Date?, to date: Date) -> String {
        guard let start else { return "00:00" }
        let seconds = max(0, Int(date.timeIntervalSince(start)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

enum MahjongOverheadMetrics {
    static let canvas = CGSize(width: 1280, height: 1000)
    static let compass = CGPoint(x: 640, y: 488)
    static let titlebarHeight: CGFloat = 40
    static let playerEdgeInset: CGFloat = 16
    static let horizontalPlayerSize = CGSize(width: 320, height: 76)
    static let verticalPlayerSize = CGSize(width: 132, height: 208)
    static let riverBreadth: CGFloat = 30
    static let riverLength: CGFloat = 42
    static let meldBreadth: CGFloat = 36
    static let meldLength: CGFloat = 50
    static let seatBreadth: CGFloat = 36
    static let seatLength: CGFloat = 50
    static let localBreadth: CGFloat = 52
    static let localLength: CGFloat = 72

    static func rotation(for view: Int) -> Double {
        switch view {
        case 1: 90
        case 2: 180
        case 3: 270
        default: 0
        }
    }

    static func readsReversed(_ view: Int) -> Bool {
        view == 1 || view == 2
    }

    static func isHorizontal(_ view: Int) -> Bool {
        view == 0 || view == 2
    }

    static func plaqueCenter(_ view: Int, titlebarInset: CGFloat) -> CGPoint {
        switch view {
        case 0:
            CGPoint(x: canvas.width / 2, y: canvas.height - playerEdgeInset - horizontalPlayerSize.height / 2)
        case 1:
            CGPoint(x: playerEdgeInset + verticalPlayerSize.width / 2, y: 512)
        case 2:
            CGPoint(x: canvas.width / 2, y: titlebarInset + playerEdgeInset + horizontalPlayerSize.height / 2)
        default:
            CGPoint(x: canvas.width - playerEdgeInset - verticalPlayerSize.width / 2, y: 512)
        }
    }

    static func handCenter(_ view: Int) -> CGPoint {
        switch view {
        case 0: CGPoint(x: 640, y: 856)
        case 1: CGPoint(x: 187, y: 488)
        case 2: CGPoint(x: 640, y: 131)
        default: CGPoint(x: 1093, y: 488)
        }
    }

    static func meldCenter(_ view: Int) -> CGPoint {
        switch view {
        case 0: CGPoint(x: 640, y: 783)
        case 1: CGPoint(x: 247, y: 488)
        case 2: CGPoint(x: 640, y: 193)
        default: CGPoint(x: 1033, y: 488)
        }
    }

    static func discardCenter(view: Int, index: Int) -> CGPoint {
        let column = CGFloat(index % 6)
        let row = CGFloat(index / 6)
        let along: CGFloat = riverBreadth + 3
        let depth: CGFloat = riverLength + 4
        switch view {
        case 0:
            return CGPoint(x: 640 + (column - 2.5) * along, y: 721 - row * depth)
        case 2:
            return CGPoint(x: 640 - (column - 2.5) * along, y: 255 + row * depth)
        case 1:
            return CGPoint(x: 309 + row * depth, y: 488 + (2.5 - column) * along)
        default:
            return CGPoint(x: 971 - row * depth, y: 488 + (column - 2.5) * along)
        }
    }

    static func discardMat(view: Int) -> (CGPoint, CGSize) {
        let first = discardCenter(view: view, index: 0)
        let last = discardCenter(view: view, index: 23)
        let center = CGPoint(x: (first.x + last.x) / 2, y: (first.y + last.y) / 2)
        let pad: CGFloat = 16
        let spanX = abs(last.x - first.x)
        let spanY = abs(last.y - first.y)
        if isHorizontal(view) {
            return (center, CGSize(width: spanX + riverBreadth + pad, height: spanY + riverLength + pad))
        }
        return (center, CGSize(width: spanX + riverLength + pad, height: spanY + riverBreadth + pad))
    }

    static func viewPosition(of seat: Int, localSeat: Int) -> Int {
        (seat - localSeat + 4) % 4
    }
}

/// Tag direction follows the on-screen seat. The local player stays at the bottom, including a LAN guest who is not 东.
enum MahjongPlaqueTags {
    static func stacksVertically(viewPosition: Int) -> Bool {
        viewPosition % 2 == 1
    }
}

struct MahjongOverheadFelt: View {
    let game: MahjongGame
    let archive: MahjongArchiveStore
    @ObservedObject var lanRoomService: MahjongLANRoomService
    let roundNotice: String?
    let roundSettlement: MahjongArchiveSettlement?
    let onNextRound: () -> Void
    let onExit: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let scale = min(
                proxy.size.width / MahjongOverheadMetrics.canvas.width,
                proxy.size.height / MahjongOverheadMetrics.canvas.height
            )
            ZStack {
                MahjongSceneTable(game: game)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                table(titlebarInset: MahjongOverheadMetrics.titlebarHeight / max(scale, 0.01))
                    .frame(
                        width: MahjongOverheadMetrics.canvas.width,
                        height: MahjongOverheadMetrics.canvas.height
                    )
                    .scaleEffect(max(scale, 0.01))
                    .frame(
                        width: MahjongOverheadMetrics.canvas.width * scale,
                        height: MahjongOverheadMetrics.canvas.height * scale
                    )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func table(titlebarInset: CGFloat) -> some View {
        ZStack {
            ForEach(0 ..< 4, id: \.self) { view in
                MahjongSeatPlaque(
                    profile: profile(for: seat(at: view)),
                    missingSuit: missingSuit(for: seat(at: view)),
                    multiplier: game.multipliers[seat(at: view)],
                    showsMultiplier: game.phase == .choosingMultiplier
                        || game.phase == .playing
                        || game.phase == .responding
                        || game.phase == .roundEnded,
                    isDealer: game.dealer == seat(at: view),
                    stacksTagsVertically: MahjongPlaqueTags.stacksVertically(viewPosition: view),
                    viewPosition: view,
                    titlebarInset: titlebarInset
                )
            }
            if showsCompass {
                turnCompass
            }
            ceremony
            MahjongActionTray(game: game)
                .frame(width: 560, height: 52)
                .position(x: 640, y: 600)
        }
        .frame(width: MahjongOverheadMetrics.canvas.width, height: MahjongOverheadMetrics.canvas.height)
        .mahjongGlassGroup(spacing: 6)
    }

    private var showsCompass: Bool {
        switch game.phase {
        case .choosingMissingSuit, .choosingMultiplier, .playing, .responding: true
        default: false
        }
    }

    private var turnCompass: some View {
        MahjongTurnCompass(
            winds: (0 ..< 4).map { game.seatName(seat(at: $0)).replacingOccurrences(of: "家", with: "") },
            seatName: game.phase == .choosingMultiplier
                ? "加倍"
                : (game.phase == .choosingMissingSuit
                    ? "定缺"
                    : (game.phase == .responding ? "吃碰杠" : (indicatedSeat.map { game.seatName($0) } ?? ""))),
            viewPosition: indicatedSeat.map { MahjongOverheadMetrics.viewPosition(of: $0, localSeat: game.localSeat) },
            deadline: game.phase == .choosingMultiplier || game.phase == .choosingMissingSuit
                ? game.multiplierDeadline
                : (game.phase == .responding
                    ? game.responseDecisionDeadline
                    : indicatedSeat.flatMap { game.countdownDeadline(for: $0) }),
            counting: game.phase == .choosingMultiplier
                ? game.multiplierDeadline != nil && game.multipliers.contains(where: { $0 == nil })
                : (game.phase == .choosingMissingSuit
                    ? game.multiplierDeadline != nil
                    : (game.phase == .responding
                        ? game.responseDecisionDeadline != nil
                        : (indicatedSeat.map { game.isCountdownActive(for: $0) } ?? false))),
            countdownDuration: game.phase == .choosingMultiplier || game.phase == .choosingMissingSuit
                ? MahjongDoubling.duration
                : (game.phase == .responding ? game.responseDecisionDuration : 20)
        )
    }

    @ViewBuilder
    private var ceremony: some View {
        if game.phase == .waitingForReady {
            MahjongReadyCard(game: game, archive: archive, lanRoomService: lanRoomService)
        } else if game.phase == .choosingMultiplier {
            MahjongMultiplierCeremony(game: game)
        } else if game.phase == .roundEnded {
            MahjongSettlementCard(
                game: game,
                archive: archive,
                lanRoomService: lanRoomService,
                roundNotice: roundNotice,
                roundSettlement: roundSettlement,
                onNextRound: onNextRound,
                onExit: onExit
            )
        }
    }

    private var indicatedSeat: Int? {
        switch game.phase {
        case .playing, .dealing:
            game.activeSeat
        default:
            nil
        }
    }

    private func seat(at view: Int) -> Int {
        (game.localSeat + view) % 4
    }

    private func missingSuit(for seat: Int) -> MahjongSuit? {
        guard game.ruleset == .sichuan, game.missingSuits.indices.contains(seat) else { return nil }
        return game.missingSuits[seat]
    }

    private func profile(for seat: Int) -> MahjongPlayerArchive {
        mahjongSeatProfile(seat: seat, game: game, archive: archive, lanRoomService: lanRoomService)
    }
}

struct MahjongBaize: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.36, green: 0.20, blue: 0.10),
                            Color(red: 0.16, green: 0.08, blue: 0.04)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.11, green: 0.42, blue: 0.28),
                            Color(red: 0.04, green: 0.22, blue: 0.15),
                            Color(red: 0.02, green: 0.11, blue: 0.08)
                        ],
                        center: .center,
                        startRadius: 40,
                        endRadius: 620
                    )
                )
                .padding(18)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color(red: 0.78, green: 0.64, blue: 0.36).opacity(0.55), lineWidth: 1.2)
                        .padding(18)
                }
                .overlay {
                    RadialGradient(
                        colors: [Color.white.opacity(0.14), Color.clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 280
                    )
                    .padding(18)
                    .allowsHitTesting(false)
                }
        }
    }
}

struct MahjongDiscardMat: View {
    let viewPosition: Int

    var body: some View {
        let mat = MahjongOverheadMetrics.discardMat(view: viewPosition)
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.black.opacity(0.18))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            }
            .frame(width: mat.1.width, height: mat.1.height)
            .position(mat.0)
            .allowsHitTesting(false)
    }
}

struct MahjongSeatDiscords: View {
    let game: MahjongGame
    let seat: Int
    let viewPosition: Int

    var body: some View {
        let tiles = game.discards.indices.contains(seat) ? game.discards[seat] : []
        let rotation = MahjongOverheadMetrics.rotation(for: viewPosition)
        ForEach(Array(tiles.enumerated()), id: \.offset) { index, tile in
            MahjongSeatedTile(
                tile: tile,
                faceUp: true,
                missingSuit: false,
                rotation: rotation,
                pose: .lying,
                length: MahjongOverheadMetrics.riverLength,
                breadth: MahjongOverheadMetrics.riverBreadth
            )
            .position(MahjongOverheadMetrics.discardCenter(view: viewPosition, index: index))
        }
    }
}
