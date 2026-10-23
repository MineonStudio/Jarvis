import SwiftUI

extension MahjongSettingsView {
    var recordContent: some View {
        VStack(alignment: .leading, spacing: 30) {
            HStack(spacing: 12) {
                ForEach(RecordTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { recordTab = tab }
                    } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(recordTab == tab ? MahjongSettingsPalette.accent : MahjongSettingsPalette.ivory)
                            .padding(.horizontal, 20)
                            .frame(height: 42)
                            .background(
                                recordTab == tab ? MahjongSettingsPalette.accent.opacity(0.13) : .black.opacity(0.15),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .stroke(recordTab == tab ? MahjongSettingsPalette.accent.opacity(0.75) : .clear, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            switch recordTab {
            case .mine:
                statisticsContent(for: archive.player, isAI: false)
            case .ai:
                aiStatisticsContent
            }
        }
    }

    var aiStatisticsContent: some View {
        VStack(alignment: .leading, spacing: 26) {
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(archive.aiProfiles) { profile in
                        let selected = selectedAIProfileID == profile.id
                            || (selectedAIProfileID == nil && archive.aiProfiles.first?.id == profile.id)
                        Button { selectedAIProfileID = profile.id } label: {
                            VStack(spacing: 7) {
                                MahjongArchiveAvatar(profile: profile, size: 54)
                                Text(profile.nickname)
                                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(selected ? MahjongSettingsPalette.accent : MahjongSettingsPalette.ivory)
                            .frame(width: 104, height: 94)
                            .background(
                                selected ? MahjongSettingsPalette.accent.opacity(0.13) : .black.opacity(0.15),
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                            .overlay(RoundedRectangle(cornerRadius: 10)
                                .stroke(selected ? MahjongSettingsPalette.accent.opacity(0.75) : .clear, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)

            if let profile = archive.aiProfiles.first(where: { $0.id == selectedAIProfileID }) ?? archive.aiProfiles.first {
                statisticsContent(for: profile, isAI: true)
            }
        }
    }

    func statisticsContent(for profile: MahjongPlayerArchive, isAI: Bool) -> some View {
        VStack(alignment: .leading, spacing: 30) {
            HStack(spacing: 36) {
                ZStack {
                    Circle().stroke(MahjongSettingsPalette.accent.opacity(0.18), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: CGFloat(profile.winRate) / 100)
                        .stroke(MahjongSettingsPalette.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Text("\(profile.winRate)%")
                            .font(.system(size: 39, weight: .bold, design: .rounded))
                            .foregroundStyle(MahjongSettingsPalette.accent)
                        Text("胜率").font(.system(size: 13)).foregroundStyle(MahjongSettingsPalette.muted)
                    }
                }
                .frame(width: 160, height: 160)

                VStack(alignment: .leading, spacing: 18) {
                    if isAI {
                        Text(profile.nickname)
                            .font(.system(size: 21, weight: .semibold, design: .serif))
                            .foregroundStyle(MahjongSettingsPalette.accent)
                    }
                    Text("累计对局 \(max(profile.wins + profile.losses, archive.history(for: profile.id).count)) 场")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(MahjongSettingsPalette.ivory)
                    HStack(spacing: 40) {
                        recordNumber("胜局", profile.wins, color: MahjongSettingsPalette.accent)
                        recordNumber("负局", profile.losses, color: MahjongSettingsPalette.ivory)
                    }
                }
            }
            metricRow("当前毛格子", profile.balance.formatted())
            metricRow("中途退出", profile.escapes.formatted())
            if !isAI {
                metricRow("今日击败 AI", "\(archive.eliminatedAICount) / \(archive.totalAICount)")
            }
            Text("历史对局")
                .font(.system(size: 22, weight: .semibold, design: .serif))
                .foregroundStyle(MahjongSettingsPalette.ivory)
                .padding(.top, 6)
            let history = archive.history(for: profile.id)
            if history.isEmpty {
                Text("暂无历史对局")
                    .font(.system(size: 16))
                    .foregroundStyle(MahjongSettingsPalette.muted)
                    .padding(.vertical, 16)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(history) { match in
                        matchRow(match)
                    }
                }
            }
        }
    }

    func matchRow(_ match: MahjongMatchRecord) -> some View {
        HStack(spacing: 16) {
            Text(match.outcome.title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(match.outcome == .win ? MahjongSettingsPalette.accent : MahjongSettingsPalette.ivory)
                .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 5) {
                Text("\(match.ruleset.title) · 第 \(match.roundNumber) 局")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MahjongSettingsPalette.ivory)
                Text("\(match.mode.rawValue) · \(match.playedAt.formatted(date: .abbreviated, time: .shortened))\(match.winnerNickname.map { " · \($0)胡牌" } ?? "")")
                    .font(.system(size: 12))
                    .foregroundStyle(MahjongSettingsPalette.muted)
            }
            Spacer(minLength: 8)
            Text(match.balanceChange == 0 ? "±0" : match.balanceChange > 0 ? "+\(match.balanceChange.formatted())" : match.balanceChange.formatted())
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(match.balanceChange > 0 ? MahjongSettingsPalette.accent : MahjongSettingsPalette.ivory)
        }
        .padding(16)
        .background(.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
    }
}
