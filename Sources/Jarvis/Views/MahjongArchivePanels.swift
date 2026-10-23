import AppKit
import SwiftUI

struct MahjongArchiveDashboardView: View {
    let archive: MahjongArchiveStore

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("欢乐麻将档案").font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("玩家战绩、毛格子余额与 AI 对手档案")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                Text("今日 AI 淘汰  \(archive.eliminatedAICount) / \(archive.totalAICount)")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }
            HStack(spacing: 14) {
                MahjongArchiveAvatar(profile: archive.player, size: 72)
                VStack(alignment: .leading, spacing: 5) {
                    Text(archive.player.nickname).font(.system(size: 17, weight: .semibold))
                    Text("\(archive.player.balance.formatted()) 毛格子")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text("胜率 \(archive.player.winRate)%  ·  胜 \(archive.player.wins)  负 \(archive.player.losses)  逃跑 \(archive.player.escapes)")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button(archive.canClaimDailyReward ? "领取每日签到 · +\(MahjongArchiveStore.dailyReward.formatted())" : "今日签到已领取") {
                    _ = archive.claimDailyReward()
                }
                .buttonStyle(JarvisSecondaryButtonStyle())
                .disabled(!archive.canClaimDailyReward)
            }
            .padding(14)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            HStack {
                Text("AI 玩家档案").font(.system(size: 16, weight: .semibold))
                Spacer()
                Text("每日首场对局时，余额低于 10,000 自动补至 10,000")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(archive.aiProfiles) { profile in
                        MahjongArchiveProfileCard(
                            profile: profile,
                            isEliminated: archive.isEliminatedToday(profile),
                            onToggleVoiceGender: {
                                archive.updateAIVoiceGender(
                                    profileID: profile.id,
                                    voiceGender: profile.voiceGender == .male ? .female : .male
                                )
                            }
                        )
                    }
                }
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
            VStack(alignment: .leading, spacing: 7) {
                Text("简化竞赛赔付 · 1 分 = 20 毛格子")
                    .font(.system(size: 12, weight: .semibold))
                ForEach(MahjongWinningHandType.allCases, id: \.rawValue) { handType in
                    let concealed = handType != .standard
                    let discarderPayment = MahjongCompetitionPayout.payment(
                        handType: handType, byDiscard: true, winnerConcealed: concealed, isDiscarder: true
                    )
                    let otherPayment = MahjongCompetitionPayout.payment(
                        handType: handType, byDiscard: true, winnerConcealed: concealed, isDiscarder: false
                    )
                    let selfDrawPayment = MahjongCompetitionPayout.payment(
                        handType: handType, byDiscard: false, winnerConcealed: concealed, isDiscarder: false
                    )
                    Text("\(handType.rawValue) \(handType.competitionPoints) 分：点炮者 \(discarderPayment.formatted())，其余两家各 \(otherPayment.formatted())；自摸三家各 \(selfDrawPayment.formatted())")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                let concealedDiscarder = MahjongCompetitionPayout.payment(
                    handType: .standard, byDiscard: true, winnerConcealed: true, isDiscarder: true
                )
                let concealedSelfDraw = MahjongCompetitionPayout.payment(
                    handType: .standard, byDiscard: false, winnerConcealed: true, isDiscarder: false
                )
                Text("普通牌门清：点炮者 \(concealedDiscarder.formatted())，自摸三家各 \(concealedSelfDraw.formatted())。余额不足时按实际余额支付。")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(22)
    }
}

struct MahjongArchiveProfileCard: View {
    let profile: MahjongPlayerArchive
    let isEliminated: Bool
    let onToggleVoiceGender: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            MahjongArchiveAvatar(profile: profile, size: 58)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(profile.nickname).font(.system(size: 14, weight: .semibold))
                    if isEliminated {
                        Text("今日淘汰").font(.system(size: 9, weight: .bold)).foregroundStyle(.red)
                    }
                }
                Text("\(profile.balance.formatted()) 毛格子")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                HStack(spacing: 7) {
                    Text("胜率 \(profile.winRate)%  ·  胜 \(profile.wins) / 负 \(profile.losses) / 逃跑 \(profile.escapes)")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    Button(profile.voiceGender.displayName, action: onToggleVoiceGender)
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .help("切换 AI 麻将语音")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct MahjongArchiveAvatar: View {
    let profile: MahjongPlayerArchive
    let size: CGFloat

    private var palette: [Color] {
        switch profile.avatarStyle {
        case .player: [Color(red: 0.12, green: 0.39, blue: 0.58), Color(red: 0.24, green: 0.68, blue: 0.71)]
        case .iron: [Color(red: 0.47, green: 0.08, blue: 0.09), Color(red: 0.91, green: 0.35, blue: 0.18)]
        case .spider: [Color(red: 0.49, green: 0.05, blue: 0.09), Color(red: 0.88, green: 0.16, blue: 0.22)]
        case .captain: [Color(red: 0.07, green: 0.16, blue: 0.40), Color(red: 0.28, green: 0.48, blue: 0.77)]
        case .thor: [Color(red: 0.14, green: 0.26, blue: 0.49), Color(red: 0.49, green: 0.69, blue: 0.88)]
        case .hulk: [Color(red: 0.15, green: 0.29, blue: 0.17), Color(red: 0.38, green: 0.65, blue: 0.34)]
        case .widow: [Color(red: 0.14, green: 0.16, blue: 0.20), Color(red: 0.53, green: 0.18, blue: 0.24)]
        case .hawkeye: [Color(red: 0.20, green: 0.15, blue: 0.36), Color(red: 0.51, green: 0.31, blue: 0.65)]
        case .panda: [Color(red: 0.10, green: 0.45, blue: 0.46), Color(red: 0.52, green: 0.78, blue: 0.68)]
        case .fox: [Color(red: 0.69, green: 0.24, blue: 0.09), Color(red: 0.98, green: 0.60, blue: 0.19)]
        case .cat: [Color(red: 0.78, green: 0.30, blue: 0.06), Color(red: 1.0, green: 0.68, blue: 0.28)]
        case .rabbit: [Color(red: 0.32, green: 0.49, blue: 0.76), Color(red: 0.72, green: 0.62, blue: 0.88)]
        case .bear: [Color(red: 0.42, green: 0.25, blue: 0.11), Color(red: 0.76, green: 0.54, blue: 0.26)]
        case .tiger: [Color(red: 0.71, green: 0.20, blue: 0.10), Color(red: 0.96, green: 0.52, blue: 0.17)]
        case .owl: [Color(red: 0.08, green: 0.17, blue: 0.40), Color(red: 0.35, green: 0.43, blue: 0.80)]
        case .dog: [Color(red: 0.95, green: 0.62, blue: 0.35), Color(red: 0.99, green: 0.80, blue: 0.55)]
        case .penguin: [Color(red: 0.35, green: 0.62, blue: 0.86), Color(red: 0.62, green: 0.82, blue: 0.95)]
        case .hamster: [Color(red: 0.93, green: 0.72, blue: 0.22), Color(red: 0.98, green: 0.86, blue: 0.42)]
        case .deer: [Color(red: 0.36, green: 0.55, blue: 0.40), Color(red: 0.62, green: 0.76, blue: 0.52)]
        case .koala: [Color(red: 0.42, green: 0.52, blue: 0.64), Color(red: 0.68, green: 0.76, blue: 0.84)]
        case .frog: [Color(red: 0.22, green: 0.58, blue: 0.28), Color(red: 0.48, green: 0.78, blue: 0.36)]
        case .lion: [Color(red: 0.86, green: 0.48, blue: 0.12), Color(red: 0.96, green: 0.72, blue: 0.28)]
        case .lamb: [Color(red: 0.58, green: 0.46, blue: 0.76), Color(red: 0.80, green: 0.70, blue: 0.90)]
        case .monkey: [Color(red: 0.90, green: 0.62, blue: 0.46), Color(red: 0.98, green: 0.78, blue: 0.62)]
        case .pig: [Color(red: 0.90, green: 0.40, blue: 0.52), Color(red: 0.98, green: 0.68, blue: 0.74)]
        }
    }

    private var generatedImage: NSImage? {
        if let filename = profile.customAvatarFilename {
            let url = MahjongArchiveStore.avatarDirectoryURL.appendingPathComponent(filename)
            if let image = NSImage(contentsOf: url) {
                return image
            }
        }
        guard let assetName = profile.avatarStyle.generatedAssetName,
              let url = Bundle.main.url(forResource: assetName, withExtension: "png", subdirectory: "GameArtwork/Avatars") else { return nil }
        return NSImage(contentsOf: url)
    }

    private var symbol: String {
        switch profile.avatarStyle {
        case .player: "person.fill"
        case .iron: "cpu.fill"
        case .spider: "ant.fill"
        case .captain: "shield.lefthalf.filled"
        case .thor: "bolt.fill"
        case .hulk: "hand.raised.fingers.spread.fill"
        case .widow: "eye.fill"
        case .hawkeye: "scope"
        case .panda, .fox, .cat, .rabbit, .bear, .tiger, .owl, .dog, .penguin, .hamster, .deer, .koala, .frog,
             .lion, .lamb, .monkey, .pig: "person.fill"
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().fill(.white.opacity(0.12)).frame(width: size * 0.72).offset(x: size * 0.32, y: -size * 0.32)
            if let generatedImage {
                Image(nsImage: generatedImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.43, weight: .black))
                    .foregroundStyle(.white.opacity(0.95))
                    .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
                VStack { Spacer(); Text(String(profile.nickname.prefix(1)))
                    .font(.system(size: size * 0.15, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.68))
                    .padding(.bottom, size * 0.055)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .accessibilityLabel("\(profile.nickname)头像")
    }
}
