import SwiftUI

struct MahjongDiscardBoard<WorkflowControls: View>: View {
    let game: MahjongGame
    let archive: MahjongArchiveStore
    @ObservedObject var lanRoomService: MahjongLANRoomService
    let onExit: () -> Void
    let roundNotice: String?
    let roundSettlement: MahjongArchiveSettlement?
    let onNextRound: () -> Void
    @ViewBuilder let workflowControls: () -> WorkflowControls

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let edgeInset: CGFloat = 8
            let infoGap = MahjongPlayerInfoCardMetrics.gap
            let handLength = MahjongSeatAreaMetrics.handLength
            let thickness = MahjongSeatAreaMetrics.areaThickness
            let zoneGap = MahjongSeatAreaMetrics.spacingBetweenAreas
            // Hands alone set the scale. Player cards are placed after the hands are centered.
            let verticalDesign = thickness + zoneGap + handLength + zoneGap + thickness * MahjongSeatAreaMetrics.localHandScale
            let horizontalDesign = thickness * 2 + zoneGap * 2 + handLength
            let boardScale = max(
                0.4,
                min(
                    min(width / 1400, height / 920),
                    min(1.22, min(width, height) / max(verticalDesign, horizontalDesign))
                )
            )
            let horizontalZoneWidth = handLength
            // Every hand area stays within the centered discard block's width.
            let discardSpan = MahjongDiscardMetrics.sideWidth * 2
                + MahjongDiscardMetrics.horizontalWidth
                + MahjongDiscardMetrics.zoneGap * 2
            let maxHandScale = discardSpan / handLength
            let seatHandScale = min(1, maxHandScale)
            let sideClearance = edgeInset + thickness * boardScale + zoneGap * boardScale
            let localMeldSize = localMeldCornerSize()
            let localMeldVisualWidth = localMeldSize.width * boardScale
            let cornerLeading = localMeldVisualWidth > 0 ? edgeInset + localMeldVisualWidth + 16 : sideClearance
            let widthFitScale = (width - cornerLeading - sideClearance - 24) / max(horizontalZoneWidth * boardScale, 1)
            let minimumLocalScale: CGFloat = localMeldVisualWidth > 0 ? 0.85 : 1
            let localHandScale = min(
                MahjongSeatAreaMetrics.localHandScale,
                maxHandScale,
                max(widthFitScale, minimumLocalScale)
            )
            let localHandVisualHalf = thickness * boardScale * localHandScale / 2
            let localHandVisualWidth = horizontalZoneWidth * boardScale * localHandScale
            let localHandMinCenterX = cornerLeading + localHandVisualWidth / 2
            let localHandMaxCenterX = width - sideClearance - localHandVisualWidth / 2
            let localHandCenterX = min(max(width / 2, localHandMinCenterX), max(localHandMaxCenterX, localHandMinCenterX))
            let infoWidth = MahjongPlayerInfoCardMetrics.compactWidth
            let infoHeight = MahjongPlayerInfoCardMetrics.compactHeight
            let sideInfoWidth = MahjongPlayerInfoCardMetrics.sideWidth
            let sideInfoHeight = MahjongPlayerInfoCardMetrics.sideHeight
            let infoVisualHalf = infoHeight * boardScale / 2
            // Main-view info stays on the bottom edge. The hand sits just above it.
            let localInfoCenterX = width / 2
            let localInfoCenterY = height - edgeInset - infoVisualHalf
            let localHandCenterY = localInfoCenterY - infoVisualHalf - infoGap * boardScale - localHandVisualHalf
            let topHandCenterX = width / 2
            let topHandCenterY = edgeInset + thickness * boardScale * seatHandScale / 2
            let opponentHandBottom = topHandCenterY + thickness * boardScale * seatHandScale / 2
            let opponentHandVisualHalf = horizontalZoneWidth * boardScale * seatHandScale / 2
            let opponentInfoHalf = infoWidth * boardScale / 2
            let topInfoCenterX = min(
                width - edgeInset - opponentInfoHalf,
                topHandCenterX + opponentHandVisualHalf + infoGap * boardScale + opponentInfoHalf
            )
            let localHandTop = localHandCenterY - localHandVisualHalf
            let localHoverLift = MahjongSeatAreaMetrics.tileHeight / 3 * boardScale * localHandScale
            let seatGap = max(24, localHoverLift)
            // Left and right hands share the table's vertical center. Fitting them
            // between the other hands does not move that center.
            let sideHandCenterY = height / 2
            let sideTopRoom = sideHandCenterY - (opponentHandBottom + zoneGap * boardScale)
            let sideBottomRoom = (localHandTop - seatGap) - sideHandCenterY
            let sideSpan = max(0, min(sideTopRoom, sideBottomRoom) * 2)
            let sideFitScale = min(seatHandScale, sideSpan / max(handLength * boardScale, 1))
            let sideHandVisualHalfWidth = thickness * boardScale * sideFitScale / 2
            let sideHandVisualHalfHeight = handLength * boardScale * sideFitScale / 2
            let leftHandCenterX = edgeInset + sideHandVisualHalfWidth
            let rightHandCenterX = width - edgeInset - sideHandVisualHalfWidth
            let sideInfoHalfWidth = sideInfoWidth * boardScale / 2
            let sideInfoHalfHeight = sideInfoHeight * boardScale / 2
            let alongTile = MahjongSeatAreaMetrics.tileWidth
            let sideTileSpan = 14 * alongTile + 13 * MahjongSeatAreaMetrics.tileSpacing
            let sideTileHalf = min(sideHandVisualHalfHeight, sideTileSpan * boardScale * sideFitScale / 2)
            let infoGapScaled = infoGap * boardScale
            // Own left sits just outside the tiles. If that spot is off the table,
            // the card slides inward instead of covering the hand.
            let preferredLeftInfoY = sideHandCenterY - sideTileHalf - infoGapScaled - sideInfoHalfHeight
            let leftInfoCenterY = max(edgeInset + sideInfoHalfHeight, preferredLeftInfoY)
            let leftInfoOverlapsHand = leftInfoCenterY + sideInfoHalfHeight > sideHandCenterY - sideTileHalf
            let leftClearX = leftHandCenterX + sideHandVisualHalfWidth + infoGapScaled + sideInfoHalfWidth
            let leftInfoCenterX = min(
                width - edgeInset - sideInfoHalfWidth,
                leftInfoOverlapsHand ? leftClearX : max(edgeInset + sideInfoHalfWidth, leftHandCenterX)
            )
            // The right seat's own left is under the column. Keep the card there
            // and line its right edge up with the hand, even when the local hand
            // occupies the same vertical band farther toward the center.
            let rightHandRight = rightHandCenterX + sideHandVisualHalfWidth
            let rightInfoCenterX = min(
                width - edgeInset - sideInfoHalfWidth,
                max(edgeInset + sideInfoHalfWidth, rightHandRight - sideInfoHalfWidth)
            )
            let preferredRightInfoY = sideHandCenterY + sideTileHalf + infoGapScaled + sideInfoHalfHeight
            let rightInfoCenterY = min(
                height - edgeInset - sideInfoHalfHeight,
                max(edgeInset + sideInfoHalfHeight, preferredRightInfoY)
            )
            let frontGap = zoneGap * boardScale
            let sideMeldShift = sideHandVisualHalfWidth + frontGap + sideHandVisualHalfWidth
            ZStack {
                seatHand(actualSeat(at: 2), viewPosition: 2, width: horizontalZoneWidth, length: MahjongSeatAreaMetrics.areaThickness)
                    .frame(width: horizontalZoneWidth, height: MahjongSeatAreaMetrics.areaThickness, alignment: .center)
                    .scaleEffect(boardScale * seatHandScale)
                    .position(x: topHandCenterX, y: topHandCenterY)
                seatHand(actualSeat(at: 0), viewPosition: 0, width: horizontalZoneWidth, length: MahjongSeatAreaMetrics.areaThickness)
                    .frame(width: horizontalZoneWidth, height: MahjongSeatAreaMetrics.areaThickness, alignment: .center)
                    .scaleEffect(boardScale * localHandScale)
                    .position(x: localHandCenterX, y: localHandCenterY)

                seatHand(actualSeat(at: 1), viewPosition: 1, width: thickness, length: handLength)
                    .frame(width: thickness, height: handLength, alignment: .center)
                    .scaleEffect(boardScale * sideFitScale)
                    .position(x: leftHandCenterX, y: sideHandCenterY)
                seatHand(actualSeat(at: 3), viewPosition: 3, width: thickness, length: handLength)
                    .frame(width: thickness, height: handLength, alignment: .center)
                    .scaleEffect(boardScale * sideFitScale)
                    .position(x: rightHandCenterX, y: sideHandCenterY)

                frontMelds(viewPosition: 2)
                    .scaleEffect(boardScale * seatHandScale)
                    .position(
                        x: topHandCenterX,
                        y: opponentHandBottom + frontGap + MahjongSeatAreaMetrics.areaThickness * boardScale / 2
                    )
                frontMelds(viewPosition: 1)
                    .scaleEffect(boardScale * sideFitScale)
                    .position(x: leftHandCenterX + sideMeldShift, y: sideHandCenterY)
                frontMelds(viewPosition: 3)
                    .scaleEffect(boardScale * sideFitScale)
                    .position(x: rightHandCenterX - sideMeldShift, y: sideHandCenterY)

                playerInfoCard(for: actualSeat(at: 0), viewPosition: 0, width: infoWidth, height: infoHeight)
                    .scaleEffect(boardScale)
                    .position(x: localInfoCenterX, y: localInfoCenterY)
                playerInfoCard(for: actualSeat(at: 2), viewPosition: 2, width: infoWidth, height: infoHeight)
                    .scaleEffect(boardScale)
                    .position(x: topInfoCenterX, y: topHandCenterY)
                playerInfoCard(for: actualSeat(at: 1), viewPosition: 1, width: sideInfoWidth, height: sideInfoHeight)
                    .scaleEffect(boardScale)
                    .position(x: leftInfoCenterX, y: leftInfoCenterY)
                playerInfoCard(for: actualSeat(at: 3), viewPosition: 3, width: sideInfoWidth, height: sideInfoHeight)
                    .scaleEffect(boardScale)
                    .position(x: rightInfoCenterX, y: rightInfoCenterY)

                discardArea(width: width, height: height)
                    .scaleEffect(boardScale)
                    .position(x: width / 2, y: height / 2)

                if game.phase == .waitingForReady {
                    preparationControls
                        .fixedSize()
                        .position(x: width / 2, y: height / 2)
                }
                if game.phase == .roundEnded {
                    settlementControls
                        .fixedSize()
                        .position(x: width / 2, y: height / 2)
                }
            }
            .overlay(alignment: .bottomLeading) {
                localMeldCorner()
                    .scaleEffect(boardScale, anchor: .bottomLeading)
                    .padding(edgeInset)
            }
            .overlay(alignment: .bottomTrailing) {
                workflowControls()
                    .padding(16)
            }
        }
    }

    func playerInfoCard(for seat: Int, viewPosition: Int, width: CGFloat, height: CGFloat) -> some View {
        let profile = playerProfile(for: seat)

        return MahjongPlayerInfoCard(
            profile: profile,
            seatName: game.seatName(seat),
            missingSuit: game.ruleset == .sichuan && game.missingSuits.indices.contains(seat)
                ? game.missingSuits[seat]
                : nil,
            countdownActive: game.isCountdownActive(for: seat),
            countdownDeadline: game.countdownDeadline(for: seat),
            stacksVertically: viewPosition == 1 || viewPosition == 3,
            detailArrowEdge: detailArrowEdge(for: viewPosition)
        )
        .frame(width: width, height: height)
        .accessibilityElement(children: .contain)
    }

    func detailArrowEdge(for viewPosition: Int) -> Edge {
        switch viewPosition {
        case 1: .top
        case 2: .trailing
        case 3: .bottom
        default: .bottom
        }
    }

    func actualSeat(at viewPosition: Int) -> Int {
        (game.localSeat + viewPosition) % 4
    }

    func playerProfile(for seat: Int) -> MahjongPlayerArchive {
        if game.mode == .lan, let profile = lanRoomService.syncedProfiles[seat] {
            if seat == game.localSeat {
                return MahjongPlayerArchive(
                    id: archive.player.id, nickname: archive.player.nickname,
                    avatarStyle: archive.player.avatarStyle, customAvatarFilename: archive.player.customAvatarFilename,
                    balance: profile.balance, wins: profile.wins, losses: profile.losses, escapes: archive.player.escapes,
                    eliminatedDay: profile.eliminatedDay
                )
            }
            return profile
        }
        if game.mode == .lan, game.humanSeats.contains(seat) {
            if seat == game.localSeat {
                return archive.player
            }
            return MahjongPlayerArchive(id: "lan-seat-\(seat)", nickname: game.seatNicknames[seat], avatarStyle: .player, balance: 0)
        }
        if seat == 0 {
            return archive.player
        }
        if game.aiProfileIDs.indices.contains(seat - 1),
           let storedProfile = archive.profile(id: game.aiProfileIDs[seat - 1])
        {
            return storedProfile
        }
        return MahjongPlayerArchive(
            id: "seat-\(seat)",
            nickname: game.seatName(seat),
            avatarStyle: .player,
            balance: 0,
            eliminatedDay: nil
        )
    }
}
