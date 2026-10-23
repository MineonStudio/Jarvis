import SwiftUI

extension MahjongDiscardBoard {
    var preparationControls: some View {
        VStack(spacing: 10) {
            readyPlayerBadges
            Button("准备") { game.markReady() }
                .buttonStyle(JarvisSecondaryButtonStyle())
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .jarvisGlass(cornerRadius: 22, interactive: false)
    }

    var settlementControls: some View {
        VStack(spacing: 14) {
            Text(game.winner.map { "恭喜【\(playerProfile(for: $0).nickname)】获得本局胜利" } ?? "本局流局")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(game.roundResult)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            if let playerResults = roundSettlement?.playerResults, !playerResults.isEmpty {
                VStack(spacing: 5) {
                    ForEach(playerResults) { result in
                        HStack(spacing: 12) {
                            Text(result.nickname)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(signedBalanceChange(result.balanceChange))
                                .fontWeight(.semibold)
                                .foregroundStyle(result.balanceChange > 0 ? Color.green : (result.balanceChange < 0 ? Color.red : Color.secondary))
                                .frame(width: 112, alignment: .trailing)
                        }
                        .font(.system(size: 11, design: .rounded))
                    }
                }
                .frame(maxWidth: 300)
            }

            readyPlayerBadges

            if roundNotice?.contains("挑战获胜") == true || roundNotice?.contains("挑战已完成") == true {
                Button("返回档案") { onNextRound() }
                    .buttonStyle(JarvisSecondaryButtonStyle())
            } else {
                Button("再来一局") { onNextRound() }
                    .buttonStyle(JarvisSecondaryButtonStyle())
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .jarvisGlass(cornerRadius: 22, interactive: false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("牌局结算")
    }

    var readyPlayerBadges: some View {
        HStack(spacing: 6) {
            ForEach(0 ..< 4, id: \.self) { seat in
                if game.readySeats.indices.contains(seat), game.readySeats[seat] {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("\(playerProfile(for: seat).nickname)已就绪")
                    }
                    .mahjongAdaptiveTag()
                }
            }
        }
    }

    func signedBalanceChange(_ value: Int) -> String {
        if value > 0 {
            return "+\(value.formatted()) 毛格子"
        }
        if value < 0 {
            return "−\(abs(value).formatted()) 毛格子"
        }
        return "0 毛格子"
    }

    func discardArea(width: CGFloat, height: CGFloat) -> some View {
        let palette = MahjongTablePalette(scheme: colorScheme)
        return ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(palette.discardFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(palette.discardStroke, lineWidth: 1)
                }
                .frame(
                    width: MahjongDiscardMetrics.sideWidth * 2
                        + MahjongDiscardMetrics.horizontalWidth + MahjongDiscardMetrics.zoneGap * 2,
                    height: MahjongDiscardMetrics.sideAreaHeight
                )
                .position(x: width / 2, y: height / 2)

            discardSeatZone(actualSeat(at: 1), viewPosition: 1)
                .frame(width: MahjongDiscardMetrics.sideWidth, height: MahjongDiscardMetrics.sideAreaHeight)
                .position(MahjongDiscardMetrics.center(for: 1, width: width, height: height))
            discardSeatZone(actualSeat(at: 3), viewPosition: 3)
                .frame(width: MahjongDiscardMetrics.sideWidth, height: MahjongDiscardMetrics.sideAreaHeight)
                .position(MahjongDiscardMetrics.center(for: 3, width: width, height: height))
            discardSeatZone(actualSeat(at: 2), viewPosition: 2)
                .frame(width: MahjongDiscardMetrics.horizontalWidth, height: MahjongDiscardMetrics.horizontalHeight)
                .position(MahjongDiscardMetrics.center(for: 2, width: width, height: height))
            discardSeatZone(actualSeat(at: 0), viewPosition: 0)
                .frame(width: MahjongDiscardMetrics.horizontalWidth, height: MahjongDiscardMetrics.horizontalHeight)
                .position(MahjongDiscardMetrics.center(for: 0, width: width, height: height))
        }
        .frame(width: width, height: height)
        .accessibilityLabel("四家已出牌区")
    }

    func discardSeatZone(_ seat: Int, viewPosition: Int) -> some View {
        let isSide = viewPosition == 1 || viewPosition == 3
        let columnCount = isSide ? 4 : 7
        let cellWidth: CGFloat = isSide ? 68 : 48
        let cellHeight: CGFloat = isSide ? 48 : 68
        let tiles = discardGridCells(seat, viewPosition: viewPosition)
        let columns = Array(repeating: GridItem(.fixed(cellWidth), spacing: MahjongDiscardMetrics.tileSpacing), count: columnCount)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: MahjongDiscardMetrics.tileSpacing) {
            ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                if let tile {
                    orientedTile(tile, viewPosition: viewPosition)
                } else {
                    Color.clear
                        .frame(width: cellWidth, height: cellHeight)
                }
            }
        }
        .padding(MahjongDiscardMetrics.safetyInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    func discardGridCells(_ seat: Int, viewPosition: Int) -> [MahjongTile?] {
        let localTiles = Array((game.discards.indices.contains(seat) ? game.discards[seat] : []).prefix(28))
        let columns = viewPosition == 1 || viewPosition == 3 ? 4 : 7
        let rows = viewPosition == 1 || viewPosition == 3 ? 7 : 4
        var cells = [MahjongTile?](repeating: nil, count: columns * rows)

        for (index, tile) in localTiles.enumerated() {
            let localRow = index / 7
            let localColumn = index % 7
            let (screenRow, screenColumn): (Int, Int) = switch viewPosition {
            case 1: (localColumn, 3 - localRow)
            case 2: (3 - localRow, 6 - localColumn)
            case 3: (6 - localColumn, localRow)
            default: (localRow, localColumn)
            }
            cells[screenRow * columns + screenColumn] = tile
        }

        return cells
    }

    func seatHand(_ seat: Int, viewPosition: Int, width: CGFloat, length: CGFloat) -> some View {
        let revealWinningHands = game.phase == .roundEnded && game.winner != nil
        let isVisible = revealWinningHands || seat == game.visibleHandSeat
        let isSideSeat = viewPosition == 1 || viewPosition == 3
        let visibleTiles = revealWinningHands || seat != game.visibleHandSeat
            ? (game.hands.indices.contains(seat) ? game.hands[seat] : [])
            : game.visibleHand
        let displayedTiles = handDisplayTiles(visibleTiles)
        let drawsSeparateTile = game.justDrew && seat == game.turn && displayedTiles.count > 1
        let baseTiles = drawsSeparateTile ? Array(displayedTiles.dropLast()) : displayedTiles
        let drawnTile = drawsSeparateTile ? displayedTiles.last : nil
        let drawDirection: CGFloat = viewPosition == 0 || viewPosition == 1 ? 1 : -1
        let baseWidth = baseHandWidth(baseTiles.count)
        let axisLength = isSideSeat ? length : width
        let hasReducedHand = baseTiles.count < 13
        // The local hand starts at local left when full, and centers when short.
        // The other three hands stay centered on their own side.
        let centersOnSide = viewPosition != 0
        let trailingSpan: CGFloat = drawnTile == nil
            ? 0
            : MahjongSeatAreaMetrics.drawGap + MahjongSeatAreaMetrics.tileWidth
        let handLeft: CGFloat = centersOnSide || hasReducedHand
            ? max(0, (axisLength - baseWidth - trailingSpan) / 2)
            : MahjongSeatAreaMetrics.safeInset
        let baseAxisPosition = screenAxis(handLeft + baseWidth / 2, axisLength: axisLength, growsPositive: drawDirection > 0)
        let drawnAxisPosition = screenAxis(
            handLeft + baseWidth + MahjongSeatAreaMetrics.drawGap + MahjongSeatAreaMetrics.tileWidth / 2,
            axisLength: axisLength,
            growsPositive: drawDirection > 0
        )

        return GeometryReader { geometry in
            ZStack {
                handRow(baseTiles, seat: seat, viewPosition: viewPosition, isVisible: isVisible, isSideSeat: isSideSeat)
                    .fixedSize()
                    .position(
                        x: isSideSeat ? geometry.size.width / 2 : baseAxisPosition,
                        y: isSideSeat ? baseAxisPosition : geometry.size.height / 2
                    )

                if let drawnTile {
                    handTileAtDrawPosition(drawnTile, seat: seat, viewPosition: viewPosition, isVisible: isVisible)
                        .position(
                            x: isSideSeat ? geometry.size.width / 2 : drawnAxisPosition,
                            y: isSideSeat ? drawnAxisPosition : geometry.size.height / 2
                        )
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(width: width, height: length, alignment: .center)
    }

    @ViewBuilder
    func handRow(
        _ tiles: [MahjongHandDisplayTile],
        seat: Int,
        viewPosition: Int,
        isVisible: Bool,
        isSideSeat: Bool
    ) -> some View {
        if isSideSeat {
            VStack(spacing: MahjongSeatAreaMetrics.tileSpacing) {
                ForEach(tiles) { entry in
                    if isVisible {
                        sideHandTile(entry.tile, seat: seat, viewPosition: viewPosition)
                    } else {
                        sideOrientedHandBack(upsideDown: viewPosition == 3)
                    }
                }
            }
        } else {
            HStack(spacing: MahjongSeatAreaMetrics.tileSpacing) {
                ForEach(tiles) { entry in
                    if isVisible {
                        handTile(entry, seat: seat, hoverLift: seat == game.visibleHandSeat)
                    } else {
                        MahjongTileBackView()
                    }
                }
            }
        }
    }
}
