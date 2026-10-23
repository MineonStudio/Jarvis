import SwiftUI

struct MahjongReadyCard: View {
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

struct MahjongSettlementCard: View {
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

struct MahjongSeatedTile: View {
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

struct MahjongOverheadTile: View {
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
func mahjongSeatProfile(
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
