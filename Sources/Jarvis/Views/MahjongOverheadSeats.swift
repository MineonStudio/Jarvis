import SwiftUI

struct MahjongSeatMelds: View {
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

struct MahjongHandSlot: Identifiable {
    let id: String
    let tile: MahjongTile?
}

struct MahjongSeatHand: View {
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
struct MahjongSideStandingTile: View {
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

struct MahjongLocalDiscardButton<Content: View>: View {
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
