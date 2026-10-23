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

private enum MahjongOverheadMetrics {
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

private struct MahjongOverheadFelt: View {
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
                    stacksTagsVertically: seat(at: view) % 2 == 1,
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

private struct MahjongBaize: View {
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

private struct MahjongDiscardMat: View {
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

private struct MahjongSeatDiscords: View {
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

private struct MahjongSeatMelds: View {
    let game: MahjongGame
    let seat: Int
    let viewPosition: Int

    var body: some View {
        let melds = orderedMelds
        let horizontal = MahjongOverheadMetrics.isHorizontal(viewPosition)
        Group {
            if horizontal {
                HStack(spacing: 12) { groups(melds) }
            } else {
                VStack(spacing: 12) { groups(melds) }
            }
        }
        .position(MahjongOverheadMetrics.meldCenter(viewPosition))
    }

    private var orderedMelds: [MahjongMeld] {
        guard game.melds.indices.contains(seat) else { return [] }
        let melds = game.melds[seat]
        return MahjongOverheadMetrics.readsReversed(viewPosition) ? Array(melds.reversed()) : melds
    }

    private func groups(_ melds: [MahjongMeld]) -> some View {
        ForEach(melds) { meld in
            meldGroup(meld)
        }
    }

    private func meldGroup(_ meld: MahjongMeld) -> some View {
        let tiles = presentedTiles(meld)
        let rotation = MahjongOverheadMetrics.rotation(for: viewPosition)
        return Group {
            if MahjongOverheadMetrics.isHorizontal(viewPosition) {
                HStack(spacing: 2) { faces(tiles, rotation: rotation) }
            } else {
                VStack(spacing: 2) { faces(tiles, rotation: rotation) }
            }
        }
        .padding(5)
        .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityLabel(meld.label)
    }

    private func faces(_ tiles: [(MahjongTile, Bool)], rotation: Double) -> some View {
        ForEach(Array(tiles.enumerated()), id: \.offset) { _, entry in
            MahjongSeatedTile(
                tile: entry.0,
                faceUp: entry.1,
                missingSuit: false,
                rotation: rotation,
                pose: .lying,
                length: MahjongOverheadMetrics.meldLength,
                breadth: MahjongOverheadMetrics.meldBreadth
            )
        }
    }

    private func presentedTiles(_ meld: MahjongMeld) -> [(MahjongTile, Bool)] {
        let sorted = meld.tiles.sorted { $0.sortKey < $1.sortKey }
        let faced: [(MahjongTile, Bool)] = if meld.kind == .concealedKong, sorted.count == 4 {
            [(sorted[0], false), (sorted[1], true), (sorted[2], true), (sorted[3], false)]
        } else {
            sorted.map { ($0, true) }
        }
        return MahjongOverheadMetrics.readsReversed(viewPosition) ? Array(faced.reversed()) : faced
    }
}

private struct MahjongHandSlot: Identifiable {
    let id: String
    let tile: MahjongTile?
}

private struct MahjongSeatHand: View {
    let game: MahjongGame
    let seat: Int
    let viewPosition: Int

    var body: some View {
        if viewPosition == 1 || viewPosition == 3 {
            sideRow
                .frame(width: 200, height: 640)
                .position(MahjongOverheadMetrics.handCenter(viewPosition))
        } else {
            let slots = handSlots
            Group {
                if MahjongOverheadMetrics.isHorizontal(viewPosition) {
                    HStack(spacing: 3) { slotViews(slots) }
                } else {
                    VStack(spacing: 3) { slotViews(slots) }
                }
            }
            .padding(7)
            .background(Color.black.opacity(slots.isEmpty ? 0 : 0.2), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .position(MahjongOverheadMetrics.handCenter(viewPosition))
        }
    }

    /// Packed wall. Index 0 is south, nearest this seat. Farther tiles are smaller and step toward the center.
    private var sideRow: some View {
        let slots = handSlots
        let centerSign: CGFloat = viewPosition == 1 ? 1 : -1
        return ZStack {
            ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                if slot.tile != nil {
                    MahjongSideStandingTile(centerSign: centerSign, scale: sideScale(index, count: slots.count))
                        .position(sidePoint(index: index, count: slots.count))
                        .zIndex(Double(slots.count - index))
                }
            }
        }
    }

    private func sideScale(_ index: Int, count: Int) -> CGFloat {
        let t = count <= 1 ? 0 : CGFloat(index) / CGFloat(max(count - 1, 1))
        return 1 - 0.34 * t
    }

    private func sidePoint(index: Int, count: Int) -> CGPoint {
        var traveled: CGFloat = 0
        var total: CGFloat = 0
        if count > 1 {
            for cursor in 0 ..< (count - 1) {
                let pitch = 34 * sideScale(cursor, count: count)
                total += pitch
                if cursor < index {
                    traveled += pitch
                }
            }
        }
        let t = count <= 1 ? 0 : CGFloat(index) / CGFloat(max(count - 1, 1))
        let nearX: CGFloat = viewPosition == 3 ? 96 : 104
        let farX: CGFloat = viewPosition == 3 ? 46 : 154
        return CGPoint(
            x: nearX + (farX - nearX) * t,
            y: 320 + total / 2 - traveled
        )
    }

    private var handSlots: [MahjongHandSlot] {
        let tiles = displayedTiles
        let separatesDraw = game.justDrew && seat == game.turn && tiles.count > 1
        let base = separatesDraw ? Array(tiles.dropLast()) : tiles
        var slots = base.enumerated().map { index, tile in
            MahjongHandSlot(id: "\(index)-\(tile.id)", tile: tile)
        }
        if separatesDraw, let drawn = tiles.last {
            slots.append(MahjongHandSlot(id: "gap", tile: nil))
            slots.append(MahjongHandSlot(id: "drawn-\(drawn.id)", tile: drawn))
        }
        if MahjongOverheadMetrics.readsReversed(viewPosition) {
            slots.reverse()
        }
        return slots
    }

    private var displayedTiles: [MahjongTile] {
        let reveal = game.phase == .roundEnded
        if reveal || seat != game.visibleHandSeat {
            return game.hands.indices.contains(seat) ? game.hands[seat] : []
        }
        return game.visibleHand
    }

    private var facesUp: Bool {
        game.phase == .roundEnded || seat == game.visibleHandSeat
    }

    private func slotViews(_ slots: [MahjongHandSlot]) -> some View {
        ForEach(slots) { slot in
            if let tile = slot.tile {
                handTile(tile)
            } else {
                Color.clear
                    .frame(
                        width: MahjongOverheadMetrics.isHorizontal(viewPosition) ? along : 1,
                        height: MahjongOverheadMetrics.isHorizontal(viewPosition) ? 1 : along
                    )
            }
        }
    }

    @ViewBuilder
    private func handTile(_ tile: MahjongTile) -> some View {
        let seated = MahjongSeatedTile(
            tile: tile,
            faceUp: facesUp,
            missingSuit: facesUp && isMissing(tile),
            rotation: MahjongOverheadMetrics.rotation(for: viewPosition),
            pose: .standing,
            length: viewPosition == 0 ? MahjongOverheadMetrics.localLength : MahjongOverheadMetrics.seatLength,
            breadth: viewPosition == 0 ? MahjongOverheadMetrics.localBreadth : MahjongOverheadMetrics.seatBreadth
        )
        if viewPosition == 0, game.isHumanTurn, facesUp {
            MahjongLocalDiscardButton(tile: tile, action: { game.discard(tile) }) {
                seated
            }
        } else {
            seated
        }
    }

    private var along: CGFloat {
        if viewPosition == 0 {
            return MahjongOverheadMetrics.localBreadth
        }
        if viewPosition == 1 || viewPosition == 3 {
            return MahjongOverheadMetrics.seatLength
        }
        return MahjongOverheadMetrics.seatBreadth
    }

    private func isMissing(_ tile: MahjongTile) -> Bool {
        guard game.ruleset == .sichuan,
              game.missingSuits.indices.contains(seat),
              let missing = game.missingSuits[seat],
              case let .suited(suit, _) = tile else { return false }
        return suit == missing
    }
}

/// One standing tile in the side wall, seen from the south.
/// The box is solid: white top, green back toward the table, white edge toward the player.
/// `centerSign` is +1 when the table center is screen-right.
private struct MahjongSideStandingTile: View {
    let centerSign: CGFloat
    var scale: CGFloat = 1

    var body: some View {
        Canvas { context, size in
            let width = size.width
            let height = size.height
            let topHeight = height * 0.24
            let outerWidth = width * 0.32
            let ivory = GraphicsContext.Shading.color(Color(red: 0.98, green: 0.96, blue: 0.92))
            let ivoryEdge = GraphicsContext.Shading.color(Color(red: 0.90, green: 0.84, blue: 0.74))
            let backIsLeading = centerSign < 0
            let backRect = CGRect(
                x: backIsLeading ? 0 : outerWidth,
                y: topHeight,
                width: width - outerWidth,
                height: height - topHeight
            )
            let edgeRect = CGRect(
                x: backIsLeading ? width - outerWidth : 0,
                y: topHeight,
                width: outerWidth,
                height: height - topHeight
            )
            context.fill(Path(edgeRect), with: ivory)
            context.fill(
                Path(backRect),
                with: .linearGradient(
                    Gradient(colors: [
                        Color(red: 0.18, green: 0.50, blue: 0.32),
                        Color(red: 0.05, green: 0.25, blue: 0.16)
                    ]),
                    startPoint: CGPoint(x: backRect.midX, y: backRect.minY),
                    endPoint: CGPoint(x: backRect.midX, y: backRect.maxY)
                )
            )
            var seam = Path()
            let seamX = backIsLeading ? width - outerWidth : outerWidth
            seam.move(to: CGPoint(x: seamX, y: topHeight))
            seam.addLine(to: CGPoint(x: seamX, y: height))
            context.stroke(seam, with: ivoryEdge, lineWidth: max(1, scale))
            context.fill(Path(CGRect(x: 0, y: 0, width: width, height: topHeight)), with: ivory)
            var cap = Path()
            cap.move(to: CGPoint(x: 0, y: topHeight))
            cap.addLine(to: CGPoint(x: width, y: topHeight))
            context.stroke(cap, with: ivoryEdge, lineWidth: max(1, scale))
            let mark = min(width, height) * 0.12
            var diamond = Path()
            diamond.move(to: CGPoint(x: backRect.midX, y: backRect.midY - mark))
            diamond.addLine(to: CGPoint(x: backRect.midX + mark, y: backRect.midY))
            diamond.addLine(to: CGPoint(x: backRect.midX, y: backRect.midY + mark))
            diamond.addLine(to: CGPoint(x: backRect.midX - mark, y: backRect.midY))
            diamond.closeSubpath()
            context.fill(diamond, with: .color(Color(red: 0.86, green: 0.72, blue: 0.42).opacity(0.85)))
        }
        .frame(width: 42 * scale, height: 46 * scale)
        .accessibilityHidden(true)
    }
}

private struct MahjongLocalDiscardButton<Content: View>: View {
    let tile: MahjongTile
    let action: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            content()
                .offset(y: hovering ? -16 : 0)
                .shadow(color: .black.opacity(hovering ? 0.35 : 0), radius: 6, y: 4)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.18), value: hovering)
        .zIndex(hovering ? 2 : 0)
        .accessibilityLabel("打出\(tile.accessibilityName)")
    }
}

private struct MahjongSeatPlaque: View {
    let profile: MahjongPlayerArchive
    let missingSuit: MahjongSuit?
    let multiplier: Int?
    let showsMultiplier: Bool
    let isDealer: Bool
    /// 东家、西家一行排开；南家、北家一个标签一行。
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

private struct MahjongTurnRing: View {
    let deadline: Date?
    let duration: TimeInterval

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let remaining = deadline?.timeIntervalSince(context.date) ?? 0
            let progress = min(max(remaining / max(duration, 0.001), 0), 1)
            MahjongCountdownArc(progress: progress)
        }
        .accessibilityHidden(true)
    }
}

private struct MahjongTurnCompass: View {
    /// Wind character for each view. 0 is the bottom (local), then left, top, right.
    let winds: [String]
    let seatName: String
    let viewPosition: Int?
    let deadline: Date?
    let counting: Bool
    let countdownDuration: TimeInterval

    private let plate: CGFloat = 108
    private let activeFill = Color.white.opacity(0.18)

    var body: some View {
        ZStack {
            plateBody
            Circle()
                .fill(.white.opacity(0.06))
                .overlay {
                    if counting, let deadline {
                        MahjongTurnRing(deadline: deadline, duration: countdownDuration)
                            .padding(4)
                    }
                }
                .overlay {
                    if counting {
                        TimelineView(.periodic(from: .now, by: 0.2)) { context in
                            let remaining = deadline?.timeIntervalSince(context.date) ?? 0
                            Text("\(max(0, Int(ceil(remaining))))")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(MahjongVisualTheme.ivory)
                                .monospacedDigit()
                        }
                    }
                }
                .frame(width: 52, height: 52)
        }
        .frame(width: plate, height: plate)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .position(MahjongOverheadMetrics.compass)
        .animation(.easeInOut(duration: 0.25), value: viewPosition)
        .allowsHitTesting(false)
        .accessibilityLabel(counting ? "\(seatName) 倒计时" : (viewPosition == nil ? "方位指示器" : "\(seatName) 当前"))
    }

    private var plateBody: some View {
        let wedges: [(view: Int, a: UnitPoint, b: UnitPoint)] = [
            (2, .topLeading, .topTrailing),
            (3, .topTrailing, .bottomTrailing),
            (0, .bottomTrailing, .bottomLeading),
            (1, .bottomLeading, .topLeading)
        ]
        return ZStack {
            ZStack {
                ForEach(wedges, id: \.view) { wedge in
                    CompassWedge(a: wedge.a, b: wedge.b)
                        .fill(wedge.view == viewPosition ? activeFill : .clear)
                }
            }
            .mask(CompassOuterRegion().fill(style: FillStyle(eoFill: true)))
            DiagonalSeam()
                .stroke(.white.opacity(0.12), lineWidth: 1)
            windMarks
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var windMarks: some View {
        ZStack {
            wind(2).offset(y: -39)
            wind(3).offset(x: 39)
            wind(0).offset(y: 39)
            wind(1).offset(x: -39)
        }
    }

    private func wind(_ view: Int) -> some View {
        Text(winds.indices.contains(view) ? winds[view] : "")
            .font(.custom("Kaiti SC", size: 15))
            .foregroundStyle(
                view == viewPosition
                    ? MahjongVisualTheme.accent
                    : MahjongVisualTheme.ivory.opacity(0.85)
            )
    }
}

/// One corner of the direction square. The two outer corners and the center form the triangle.
private struct CompassWedge: Shape {
    var a: UnitPoint
    var b: UnitPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + a.x * rect.width, y: rect.minY + a.y * rect.height))
        path.addLine(to: CGPoint(x: rect.minX + b.x * rect.width, y: rect.minY + b.y * rect.height))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

private struct DiagonalSeam: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ]
        for corner in corners {
            let dx = corner.x - center.x
            let dy = corner.y - center.y
            let distance = hypot(dx, dy)
            guard distance > 32 else { continue }
            path.move(to: corner)
            path.addLine(to: CGPoint(x: center.x + dx / distance * 32, y: center.y + dy / distance * 32))
        }
        return path
    }
}

private struct CompassOuterRegion: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addEllipse(in: CGRect(x: rect.midX - 32, y: rect.midY - 32, width: 64, height: 64))
        return path
    }
}

private struct MahjongActionTray: View {
    let game: MahjongGame

    var body: some View {
        if actionsVisible {
            tray
        }
    }

    private var actionsVisible: Bool {
        switch game.phase {
        case .choosingMissingSuit:
            game.currentResponderSeat == game.localSeat
        case .responding:
            !game.humanResponseOptions.isEmpty
        case .playing where game.isHumanTurn:
            game.canSelfDraw || !game.availableKongTiles.isEmpty
        default:
            false
        }
    }

    @ViewBuilder
    private var tray: some View {
        switch game.phase {
        case .choosingMissingSuit where game.currentResponderSeat == game.localSeat:
            HStack(spacing: 8) {
                ForEach(MahjongSuit.allCases, id: \.self) { suit in
                    Button(suit.shortName) { game.chooseMissingSuit(suit) }
                        .buttonStyle(MahjongGameButtonStyle())
                }
            }
        case .responding:
            HStack(spacing: 8) {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(game.humanResponseOptions.filter { $0.kind != .pass }) { option in
                            Button(callTitle(option)) { game.respond(to: option) }
                                .buttonStyle(MahjongGameButtonStyle(kind: option.kind == .win ? .primary : .secondary))
                        }
                    }
                }
                .scrollIndicators(.automatic)
                Button("过") { game.respond(to: MahjongCallOption(kind: .pass, heldTiles: [])) }
                    .buttonStyle(MahjongGameButtonStyle())
            }
        case .playing where game.isHumanTurn && (game.canSelfDraw || !game.availableKongTiles.isEmpty):
            HStack(spacing: 8) {
                if game.canSelfDraw {
                    Button("自摸") { game.claimSelfDraw() }
                        .buttonStyle(MahjongGameButtonStyle(kind: .primary))
                }
                ForEach(game.availableKongTiles) { tile in
                    Button("杠 \(tile.accessibilityName)") { game.declareKong(tile) }
                        .buttonStyle(MahjongGameButtonStyle())
                }
            }
        default:
            EmptyView()
        }
    }

    private func callTitle(_ option: MahjongCallOption) -> String {
        guard !option.heldTiles.isEmpty else { return option.kind.rawValue }
        let names = option.heldTiles.map(\.accessibilityName).joined(separator: " ")
        return "\(option.kind.rawValue) \(names)"
    }
}

private struct MahjongMultiplierCeremony: View {
    let game: MahjongGame

    @State private var submittedValue: Int?

    private var localChoice: Int? {
        game.multipliers[game.localSeat] ?? submittedValue
    }

    var body: some View {
        ZStack {
            ForEach(0 ..< 4, id: \.self) { view in
                let seat = (game.localSeat + view) % 4
                let choice = game.multipliers[seat] ?? (view == 0 ? submittedValue : nil)
                if let choice {
                    announcement(for: seat, choice: choice)
                        .position(announcementPosition(for: view))
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                        .allowsHitTesting(false)
                }
            }
            if localChoice == nil, !game.localMultiplierOptions.isEmpty {
                choiceTray
                    .position(x: 640, y: 625)
            }
        }
        .frame(width: MahjongOverheadMetrics.canvas.width, height: MahjongOverheadMetrics.canvas.height)
        .animation(.easeOut(duration: 0.25), value: game.multipliers)
        .animation(.easeOut(duration: 0.25), value: submittedValue)
        .onChange(of: game.multiplierDeadline) { _, _ in submittedValue = nil }
    }

    private func announcement(for seat: Int, choice: Int) -> some View {
        HStack(spacing: 7) {
            Text(game.seatName(seat))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MahjongVisualTheme.muted)
            Text(choice == 1 ? "不加倍" : "加倍 ×\(choice)")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(MahjongVisualTheme.accent)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: Capsule())
        .accessibilityLabel("\(game.seatName(seat))\(choice == 1 ? "不加倍" : "加倍 \(choice) 倍")")
    }

    private func announcementPosition(for view: Int) -> CGPoint {
        switch view {
        case 0: CGPoint(x: 640, y: 744)
        case 1: CGPoint(x: 315, y: 488)
        case 2: CGPoint(x: 640, y: 235)
        default: CGPoint(x: 965, y: 488)
        }
    }

    private var choiceTray: some View {
        VStack(spacing: 10) {
            Text("请选择本局倍数")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(MahjongVisualTheme.ivory)
                .shadow(color: .black.opacity(0.6), radius: 3)
            HStack(spacing: 10) {
                ForEach(game.localMultiplierOptions, id: \.self) { value in
                    Button(value == 1 ? "不加倍" : "加倍 ×\(value)") {
                        submittedValue = value
                        game.chooseMultiplier(value)
                    }
                    .buttonStyle(MahjongGameButtonStyle(kind: value == 1 ? .secondary : .primary))
                }
            }
            Text("超时默认不加倍")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MahjongVisualTheme.muted)
                .shadow(color: .black.opacity(0.6), radius: 3)
        }
    }
}

private struct MahjongReadyCard: View {
    let game: MahjongGame
    let archive: MahjongArchiveStore
    @ObservedObject var lanRoomService: MahjongLANRoomService

    var body: some View {
        VStack(spacing: 17) {
            VStack(spacing: 4) {
                Text("准备开始")
                    .font(.custom("Kaiti SC", size: 26))
                    .foregroundStyle(MahjongVisualTheme.ivory)
                Text("第 \(game.roundNumber) 局 · \(game.readySeats.filter { $0 }.count)/4 人已就绪")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(MahjongVisualTheme.muted)
            }
            LazyVGrid(columns: [GridItem(.fixed(206)), GridItem(.fixed(206))], spacing: 10) {
                ForEach(0 ..< 4, id: \.self) { seat in
                    playerReadyStatus(for: seat)
                }
            }
            if game.readySeats.indices.contains(game.localSeat), game.readySeats[game.localSeat] {
                Text("已就绪，等待其他玩家")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MahjongVisualTheme.muted)
                    .frame(height: 32)
            } else {
                Button("准备") { game.markReady() }
                    .buttonStyle(MahjongGameButtonStyle(kind: .primary))
            }
        }
        .padding(22)
        .frame(width: 466)
        .mahjongGamePanel(cornerRadius: 22)
        .position(MahjongOverheadMetrics.compass)
    }

    private func playerReadyStatus(for seat: Int) -> some View {
        let profile = mahjongSeatProfile(
            seat: seat,
            game: game,
            archive: archive,
            lanRoomService: lanRoomService
        )
        let isReady = game.readySeats.indices.contains(seat) && game.readySeats[seat]
        return HStack(spacing: 10) {
            MahjongArchiveAvatar(profile: profile, size: 46)
            VStack(alignment: .leading, spacing: 5) {
                Text(profile.nickname)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MahjongVisualTheme.ivory)
                    .lineLimit(1)
                Label(isReady ? "已就绪" : "等待准备", systemImage: isReady ? "checkmark.circle.fill" : "clock")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isReady ? MahjongVisualTheme.success : MahjongVisualTheme.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: 206, height: 68)
        .background(MahjongVisualTheme.raisedSurface.opacity(0.62), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

private struct MahjongSettlementCard: View {
    let game: MahjongGame
    let archive: MahjongArchiveStore
    @ObservedObject var lanRoomService: MahjongLANRoomService
    let roundNotice: String?
    let roundSettlement: MahjongArchiveSettlement?
    let onNextRound: () -> Void
    let onExit: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.custom("Kaiti SC", size: 24))
                .foregroundStyle(MahjongVisualTheme.ivory)
            Text(game.roundResult)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(MahjongVisualTheme.muted)
                .multilineTextAlignment(.center)
            results
            HStack(spacing: 10) {
                Button("离开对局", action: onExit)
                    .buttonStyle(MahjongGameButtonStyle())
                Button("再来一局", action: onNextRound)
                    .buttonStyle(MahjongGameButtonStyle(kind: .primary))
                    .disabled(roundSettlement?.campaignComplete == true || roundSettlement?.playerNeedsExit == true)
                    .help(roundSettlement?.campaignComplete == true ? "今日挑战已完成" : "进入下一局准备")
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 20)
        .frame(maxWidth: 360)
        .mahjongGamePanel(cornerRadius: 22)
        .position(MahjongOverheadMetrics.compass)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("牌局结算")
    }

    private var title: String {
        guard let winner = game.winner else { return "流局" }
        let profile = mahjongSeatProfile(
            seat: winner,
            game: game,
            archive: archive,
            lanRoomService: lanRoomService
        )
        return "\(profile.nickname) 胡牌"
    }

    @ViewBuilder
    private var results: some View {
        if let playerResults = roundSettlement?.playerResults, !playerResults.isEmpty {
            VStack(spacing: 4) {
                ForEach(playerResults) { result in
                    HStack {
                        Text(result.nickname).lineLimit(1)
                            .foregroundStyle(MahjongVisualTheme.ivory)
                        Spacer(minLength: 8)
                        Text(signed(result.balanceChange))
                            .fontWeight(.semibold)
                            .foregroundStyle(result.balanceChange > 0 ? MahjongVisualTheme.success : (result.balanceChange < 0 ? MahjongVisualTheme.danger : MahjongVisualTheme.muted))
                    }
                    .font(.system(size: 12, design: .rounded))
                }
            }
            .frame(maxWidth: 280)
        }
    }

    private func signed(_ value: Int) -> String {
        if value > 0 {
            return "+\(value.formatted()) 毛格子"
        }
        if value < 0 {
            return "−\(abs(value).formatted()) 毛格子"
        }
        return "0 毛格子"
    }
}

private struct MahjongSeatedTile: View {
    enum Pose {
        /// Thickness peeks above the face, the way a standing tile is seen from this seat.
        case standing
        /// Thickness peeks on the near edge, toward the camera at the bottom of the screen.
        case lying
    }

    let tile: MahjongTile?
    let faceUp: Bool
    let missingSuit: Bool
    let rotation: Double
    var pose: Pose = .lying
    /// Screen-space shift of the ivory wall, in the 48-point tile. Standing side hands use a negative value so the edge is on that player's outer side.
    var lateral: CGFloat = 3
    let length: CGFloat
    let breadth: CGFloat

    var body: some View {
        let scaleX = breadth / 48
        let scaleY = length / 68
        let shift = CGSize(
            width: lateral * scaleX,
            height: (pose == .standing ? -4 : 4) * scaleY
        )
        ZStack {
            layer(wall(ivory), offset: shift)
            layer(wall(gold), offset: CGSize(width: shift.width * 0.5, height: shift.height * 0.5))
            layer(
                MahjongOverheadTile(tile: tile, faceUp: faceUp, missingSuit: missingSuit),
                offset: .zero
            )
        }
        .shadow(
            color: .black.opacity(0.2),
            radius: 1.2 * scaleY,
            x: shift.width * 0.45,
            y: shift.height * 0.35
        )
    }

    private var ivory: Color {
        Color(red: 0.95, green: 0.91, blue: 0.82)
    }

    private var gold: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.88, green: 0.74, blue: 0.48), Color(red: 0.67, green: 0.50, blue: 0.28)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func wall(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color)
    }

    private func wall(_ gradient: LinearGradient) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(gradient)
    }

    /// Same two-step offset as the main-branch tile: the wall sits behind the face.
    /// The shift is in screen space, so every seat shares this camera.
    private func layer(_ content: some View, offset: CGSize) -> some View {
        let sideways = rotation == 90 || rotation == 270
        return content
            .frame(width: 48, height: 68)
            .scaleEffect(x: breadth / 48, y: length / 68)
            .frame(width: breadth, height: length)
            .rotationEffect(.degrees(rotation))
            .offset(offset)
            .frame(width: sideways ? length : breadth, height: sideways ? breadth : length)
    }
}

private struct MahjongOverheadTile: View {
    let tile: MahjongTile?
    let faceUp: Bool
    var missingSuit = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(faceFill)
            if faceUp, let tile {
                MahjongTileFace(tile: tile, compact: false)
                    .padding(4)
            } else {
                backMotif
                    .padding(5)
            }
            if faceUp, missingSuit {
                MahjongMissingSuitFold(leg: 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .accessibilityHidden(true)
    }

    private var faceFill: LinearGradient {
        let colors: [Color] = if !faceUp {
            [Color(red: 0.10, green: 0.40, blue: 0.26), Color(red: 0.04, green: 0.22, blue: 0.14)]
        } else {
            [Color(red: 0.99, green: 0.98, blue: 0.94), Color(red: 0.93, green: 0.88, blue: 0.78)]
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    private var backMotif: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Color(red: 0.86, green: 0.72, blue: 0.42).opacity(0.85), lineWidth: 1)
                .padding(8)
            Rectangle()
                .fill(Color(red: 0.86, green: 0.72, blue: 0.42).opacity(0.9))
                .frame(width: 7, height: 7)
                .rotationEffect(.degrees(45))
        }
    }
}

@MainActor
private func mahjongSeatProfile(
    seat: Int,
    game: MahjongGame,
    archive: MahjongArchiveStore,
    lanRoomService: MahjongLANRoomService
) -> MahjongPlayerArchive {
    if game.mode == .lan, let profile = lanRoomService.syncedProfiles[seat] {
        if seat == game.localSeat {
            return MahjongPlayerArchive(
                id: archive.player.id,
                nickname: archive.player.nickname,
                avatarStyle: archive.player.avatarStyle,
                customAvatarFilename: archive.player.customAvatarFilename,
                balance: profile.balance,
                wins: profile.wins,
                losses: profile.losses,
                escapes: archive.player.escapes,
                eliminatedDay: profile.eliminatedDay
            )
        }
        return profile
    }
    if game.mode == .lan, game.humanSeats.contains(seat) {
        if seat == game.localSeat {
            return archive.player
        }
        return MahjongPlayerArchive(
            id: "lan-seat-\(seat)",
            nickname: game.seatNicknames[seat],
            avatarStyle: .player,
            balance: 0
        )
    }
    if seat == 0 {
        return archive.player
    }
    if game.aiProfileIDs.indices.contains(seat - 1),
       let stored = archive.profile(id: game.aiProfileIDs[seat - 1])
    {
        return stored
    }
    return MahjongPlayerArchive(
        id: "seat-\(seat)",
        nickname: game.seatName(seat),
        avatarStyle: .player,
        balance: 0,
        eliminatedDay: nil
    )
}
