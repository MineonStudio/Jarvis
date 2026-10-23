import SwiftUI

extension MahjongDiscardBoard {
    @ViewBuilder
    func handTileAtDrawPosition(
        _ entry: MahjongHandDisplayTile,
        seat: Int,
        viewPosition: Int,
        isVisible: Bool
    ) -> some View {
        if isVisible {
            if viewPosition == 1 || viewPosition == 3 {
                sideHandTile(entry.tile, seat: seat, viewPosition: viewPosition)
            } else {
                handTile(entry, seat: seat, animated: false, isDrawnTile: true, hoverLift: seat == game.visibleHandSeat)
            }
        } else if viewPosition == 1 || viewPosition == 3 {
            sideOrientedHandBack(upsideDown: viewPosition == 3)
        } else {
            MahjongTileBackView()
        }
    }

    @ViewBuilder
    func sideHandTile(_ tile: MahjongTile, seat: Int, viewPosition: Int) -> some View {
        let isMissingSuit = isMissingSuitTile(tile, seat: seat)
        if game.isHumanTurn {
            Button { game.discard(tile) } label: {
                sideOrientedHandTile(tile, upsideDown: viewPosition == 3, isMissingSuit: isMissingSuit)
            }
            .buttonStyle(MahjongHandTileButtonStyle())
            .transition(.scale(scale: 0.76).combined(with: .opacity))
        } else {
            sideOrientedHandTile(tile, upsideDown: viewPosition == 3, isMissingSuit: isMissingSuit)
                .transition(.scale(scale: 0.76).combined(with: .opacity))
        }
    }

    func handDisplayTiles(_ tiles: [MahjongTile]) -> [MahjongHandDisplayTile] {
        var occurrences: [String: Int] = [:]
        return tiles.map { tile in
            let occurrence = occurrences[tile.id, default: 0]
            occurrences[tile.id] = occurrence + 1
            return MahjongHandDisplayTile(id: "\(tile.id)-\(occurrence)", tile: tile)
        }
    }

    func baseHandWidth(_ count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count * 48 + (count - 1) * 2)
    }

    func screenAxis(_ localCenter: CGFloat, axisLength: CGFloat, growsPositive: Bool) -> CGFloat {
        growsPositive ? localCenter : axisLength - localCenter
    }

    func seatHasMelds(_ seat: Int) -> Bool {
        game.melds.indices.contains(seat) && !game.melds[seat].isEmpty
    }

    /// Other players' exposed melds sit in a strip just in front of that hand.
    @ViewBuilder
    func frontMelds(viewPosition: Int) -> some View {
        let seat = actualSeat(at: viewPosition)
        if seatHasMelds(seat) {
            handMeldRow(seat: seat, viewPosition: viewPosition)
                .fixedSize()
        }
    }

    /// Main-view melds occupy the bottom-left corner, up to two rows of two groups.
    @ViewBuilder
    func localMeldCorner() -> some View {
        let seat = actualSeat(at: 0)
        let melds = Array(meldsInSeatOrder(seat, viewPosition: 0).prefix(4))
        if !melds.isEmpty {
            let top = Array(melds.prefix(2))
            let bottom = Array(melds.dropFirst(2))
            VStack(alignment: .leading, spacing: MahjongSeatAreaMetrics.meldGroupGap) {
                meldCornerRow(top, seat: seat)
                if !bottom.isEmpty {
                    meldCornerRow(bottom, seat: seat)
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    func meldCornerRow(_ melds: [MahjongMeld], seat: Int) -> some View {
        HStack(alignment: .top, spacing: MahjongSeatAreaMetrics.meldGroupGap) {
            ForEach(melds) { meld in
                meldGroup(meld, seat: seat, viewPosition: 0, isSide: false)
            }
        }
    }

    func localMeldCornerSize() -> CGSize {
        let seat = actualSeat(at: 0)
        let melds = Array(meldsInSeatOrder(seat, viewPosition: 0).prefix(4))
        guard !melds.isEmpty else { return .zero }
        func rowWidth(_ row: ArraySlice<MahjongMeld>) -> CGFloat {
            let widths = row.map { uprightMeldWidth($0) }
            let gaps = MahjongSeatAreaMetrics.meldGroupGap * CGFloat(max(0, widths.count - 1))
            return widths.reduce(0, +) + gaps
        }
        let width = max(rowWidth(melds.prefix(2)), rowWidth(melds.dropFirst(2)))
        let rows: CGFloat = melds.count > 2 ? 2 : 1
        let height = rows * MahjongSeatAreaMetrics.tileHeight
            + (rows - 1) * MahjongSeatAreaMetrics.meldGroupGap
        return CGSize(width: width, height: height)
    }

    func uprightMeldWidth(_ meld: MahjongMeld) -> CGFloat {
        let count = max(meld.tiles.count, 1)
        return CGFloat(count) * MahjongSeatAreaMetrics.tileWidth
            + CGFloat(count - 1) * MahjongSeatAreaMetrics.tileSpacing
    }

    @ViewBuilder
    func handTile(
        _ entry: MahjongHandDisplayTile,
        seat: Int,
        animated: Bool = true,
        isDrawnTile: Bool = false,
        hoverLift: Bool = false
    ) -> some View {
        let isMissingSuit = isMissingSuitTile(entry.tile, seat: seat)
        if game.isHumanTurn {
            Button {
                if isDrawnTile {
                    game.discardDrawnTile()
                } else if animated {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) {
                        game.discard(entry.tile)
                    }
                } else {
                    game.discard(entry.tile)
                }
            } label: {
                handTileFace(entry, hoverLift: hoverLift, isMissingSuit: isMissingSuit)
            }
            .buttonStyle(MahjongHandTileButtonStyle())
            .transition(.scale(scale: 0.76).combined(with: .opacity))
        } else {
            handTileFace(entry, hoverLift: hoverLift, isMissingSuit: isMissingSuit)
                .transition(.scale(scale: 0.76).combined(with: .opacity))
        }
    }

    @ViewBuilder
    func handTileFace(_ entry: MahjongHandDisplayTile, hoverLift: Bool, isMissingSuit: Bool) -> some View {
        let tile = MahjongTileView(tile: entry.tile, isSelected: false, isMissingSuit: isMissingSuit)
        if hoverLift {
            MahjongHandTileHoverLift(lift: MahjongSeatAreaMetrics.tileHeight / 3) {
                tile
            }
        } else {
            tile
        }
    }

    func sideOrientedHandTile(_ tile: MahjongTile, upsideDown: Bool = false, isMissingSuit: Bool = false) -> some View {
        MahjongTileView(tile: tile, isSelected: false, isMissingSuit: isMissingSuit)
            .rotationEffect(.degrees(upsideDown ? 270 : 90))
            .frame(width: 68, height: 48)
    }

    func isMissingSuitTile(_ tile: MahjongTile, seat: Int) -> Bool {
        guard game.ruleset == .sichuan,
              game.missingSuits.indices.contains(seat),
              let missingSuit = game.missingSuits[seat],
              case let .suited(suit, _) = tile else { return false }
        return suit == missingSuit
    }

    func sideOrientedHandBack(upsideDown: Bool = false) -> some View {
        MahjongTileBackView()
            .rotationEffect(.degrees(upsideDown ? 270 : 90))
            .frame(width: 68, height: 48)
    }

    func orientedTile(_ tile: MahjongTile, viewPosition: Int) -> some View {
        let rotation: Double = switch viewPosition {
        case 1: 90
        case 2: 180
        case 3: 270
        default: 0
        }
        let isSideways = viewPosition == 1 || viewPosition == 3
        return MahjongTileView(tile: tile, isSelected: false)
            .rotationEffect(.degrees(rotation))
            .frame(width: isSideways ? 68 : 48, height: isSideways ? 48 : 68)
    }

    @ViewBuilder
    func handMeldRow(seat: Int, viewPosition: Int) -> some View {
        let isSide = viewPosition == 1 || viewPosition == 3
        let groups = meldsInSeatOrder(seat, viewPosition: viewPosition)
        Group {
            if isSide {
                VStack(alignment: .center, spacing: MahjongSeatAreaMetrics.meldGroupGap) {
                    ForEach(groups) { meld in
                        meldGroup(meld, seat: seat, viewPosition: viewPosition, isSide: true)
                    }
                }
            } else {
                HStack(alignment: .center, spacing: MahjongSeatAreaMetrics.meldGroupGap) {
                    ForEach(groups) { meld in
                        meldGroup(meld, seat: seat, viewPosition: viewPosition, isSide: false)
                    }
                }
            }
        }
        .accessibilityLabel("\(game.seatName(seat)) 的吃碰杠明牌")
    }

    func meldGroup(_ meld: MahjongMeld, seat _: Int, viewPosition: Int, isSide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if isSide {
                VStack(spacing: 2) {
                    ForEach(Array(meldTilesInSeatOrder(meld, viewPosition: viewPosition).enumerated()), id: \.offset) { _, tile in
                        orientedTile(tile, viewPosition: viewPosition)
                    }
                }
            } else {
                HStack(spacing: 2) {
                    ForEach(Array(meldTilesInSeatOrder(meld, viewPosition: viewPosition).enumerated()), id: \.offset) { _, tile in
                        orientedTile(tile, viewPosition: viewPosition)
                    }
                }
            }
        }
    }

    func meldTilesInSeatOrder(_ meld: MahjongMeld, viewPosition: Int) -> [MahjongTile] {
        let sorted = meld.tiles.sorted { $0.sortKey < $1.sortKey }
        // A player seated across or to the right sees screen order reversed.
        return viewPosition == 2 || viewPosition == 3 ? Array(sorted.reversed()) : sorted
    }

    func meldsInSeatOrder(_ seat: Int, viewPosition: Int) -> [MahjongMeld] {
        guard game.melds.indices.contains(seat) else { return [] }
        let melds = game.melds[seat]
        // The across and right seats have their local left edge on the screen's right/bottom.
        return viewPosition == 2 || viewPosition == 3 ? Array(melds.reversed()) : melds
    }
}
