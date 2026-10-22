import SwiftUI
import UniformTypeIdentifiers

private typealias MahjongSettingsPalette = MahjongVisualTheme

enum MahjongSettingsSection: String, CaseIterable, Identifiable {
    case profile = "我的资料"
    case record = "玩家数据"
    case daily = "每日签到"
    case table = "牌桌主题"
    case voice = "声音设置"

    var id: String {
        rawValue
    }
}

/// Compact settings panel displayed over the Mahjong launch scene.
struct MahjongSettingsView: View {
    let archive: MahjongArchiveStore
    let selection: MahjongSettingsSection
    let onBack: () -> Void

    private enum RecordTab: String, CaseIterable {
        case mine = "我的数据"
        case ai = "AI 玩家数据"
    }

    @State private var recordTab: RecordTab = .mine
    @State private var selectedAIProfileID: String?
    @State private var nicknameDraft = ""
    @State private var showsAvatarImporter = false
    @State private var avatarImportError: String?
    @State private var displayedMonth = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            detailPane
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.32), radius: 22, y: 10)
        .environment(\.colorScheme, .dark)
        .onAppear { nicknameDraft = archive.player.nickname }
        .onExitCommand(perform: onBack)
        .fileImporter(isPresented: $showsAvatarImporter, allowedContentTypes: [.image]) { result in
            switch result {
            case let .success(url):
                do { try archive.updatePlayerAvatar(from: url); avatarImportError = nil }
                catch { avatarImportError = "头像导入失败：\(error.localizedDescription)" }
            case let .failure(error):
                avatarImportError = "头像导入失败：\(error.localizedDescription)"
            }
        }
    }

    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(selection.rawValue)
                    .font(.system(size: 25, weight: .semibold, design: .serif))
                    .foregroundStyle(MahjongSettingsPalette.ivory)
                Spacer()
                Button(action: onBack) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MahjongSettingsPalette.ivory)
                        .frame(width: 30, height: 30)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭设置")
            }
            .padding(.bottom, 18)

            ScrollView {
                Group {
                    switch selection {
                    case .profile: profileContent
                    case .record: recordContent
                    case .daily: dailyContent
                    case .table: MahjongTableStylePicker()
                    case .voice: voiceContent
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 26)
        .padding(.top, 25)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var profileContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center, spacing: 20) {
                VStack(spacing: 12) {
                    MahjongArchiveAvatar(profile: archive.player, size: 86)
                        .padding(6)
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(MahjongSettingsPalette.accent.opacity(0.8), lineWidth: 2))
                    Button("上传头像") { showsAvatarImporter = true }
                        .buttonStyle(.plain)
                        .foregroundStyle(MahjongSettingsPalette.accent)
                }

                VStack(alignment: .leading, spacing: 14) {
                    caption("玩家昵称")
                    HStack(spacing: 12) {
                        TextField("输入昵称", text: $nicknameDraft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(MahjongSettingsPalette.ivory)
                            .padding(.horizontal, 15)
                            .frame(height: 45)
                            .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(MahjongSettingsPalette.accent.opacity(0.35), lineWidth: 1))
                            .onSubmit(saveNickname)
                        primaryButton("保存", action: saveNickname)
                    }
                    Text("最多 16 个字符")
                        .font(.system(size: 12))
                        .foregroundStyle(MahjongSettingsPalette.muted)
                }
                .frame(maxWidth: 430)
            }

            if let avatarImportError {
                Text(avatarImportError).foregroundStyle(.red)
            }
            caption("选择头像")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 125), spacing: 12)], alignment: .leading, spacing: 12) {
                ForEach(MahjongArchiveAvatarStyle.playerChoices, id: \.self) { style in
                    avatarChoice(style)
                }
            }
        }
    }

    private func avatarChoice(_ style: MahjongArchiveAvatarStyle) -> some View {
        var preview = archive.player
        preview.avatarStyle = style
        preview.customAvatarFilename = nil
        let isSelected = archive.player.customAvatarFilename == nil && archive.player.avatarStyle == style
        return Button {
            archive.updatePlayerProfile(avatarStyle: style)
        } label: {
            VStack(spacing: 7) {
                MahjongArchiveAvatar(profile: preview, size: 54)
                    .accessibilityHidden(true)
                Text(style.displayName)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? MahjongSettingsPalette.accent : MahjongSettingsPalette.ivory)
            .frame(maxWidth: .infinity)
            .frame(height: 86)
            .background(isSelected ? MahjongSettingsPalette.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSelected ? MahjongSettingsPalette.accent : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(style.displayName)
    }

    private var recordContent: some View {
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

    private var aiStatisticsContent: some View {
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

    private func statisticsContent(for profile: MahjongPlayerArchive, isAI: Bool) -> some View {
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

    private func matchRow(_ match: MahjongMatchRecord) -> some View {
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

    private var dailyContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .firstTextBaseline) {
                Text(archive.canClaimDailyReward ? "今日签到待领取" : "今日已签到")
                    .font(.system(size: 27, weight: .semibold, design: .serif))
                    .foregroundStyle(MahjongSettingsPalette.ivory)
                Spacer()
                Text("每日 +\(MahjongArchiveStore.dailyReward.formatted()) 毛格子")
                    .font(.system(size: 16))
                    .foregroundStyle(MahjongSettingsPalette.accent)
            }
            if archive.canClaimDailyReward {
                primaryButton("领取今日奖励") {
                    _ = archive.claimDailyReward()
                }
            } else {
                Label("今日奖励已领取", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(MahjongSettingsPalette.accent)
                    .padding(.horizontal, 20)
                    .frame(height: 45)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(MahjongSettingsPalette.accent.opacity(0.7), lineWidth: 1))
            }
            HStack(spacing: 28) {
                signInStatistic("累计签到", archive.checkInDays.count)
                signInStatistic("本月签到", monthCheckInCount)
                signInStatistic("连续签到", archive.currentCheckInStreak)
            }
            .padding(.vertical, 9)
            calendarView
        }
        .frame(maxWidth: .infinity)
    }

    private func signInStatistic(_ title: String, _ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(count) 天")
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .foregroundStyle(MahjongSettingsPalette.accent)
            Text(title).font(.system(size: 13)).foregroundStyle(MahjongSettingsPalette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var monthCheckInCount: Int {
        guard let interval = Calendar.current.dateInterval(of: .month, for: displayedMonth) else { return 0 }
        return archive.checkInDays.filter { day in
            guard let date = Self.dayFormatter.date(from: day) else { return false }
            return interval.contains(date)
        }.count
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private var calendarView: some View {
        let calendar = Calendar.current
        let first = calendar.dateInterval(of: .month, for: displayedMonth)?.start ?? displayedMonth
        let weekdayOffset = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let daysInMonth = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        return VStack(spacing: 15) {
            HStack {
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("上个月")
                Spacer()
                Text(displayedMonth.formatted(.dateTime.year().month(.wide)))
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                Spacer()
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("下个月")
            }
            .foregroundStyle(MahjongSettingsPalette.ivory)
            let weekdays = ["日", "一", "二", "三", "四", "五", "六"]
            HStack(spacing: 8) {
                ForEach(0 ..< 7, id: \.self) { index in
                    Text(weekdays[(index + calendar.firstWeekday - 1) % 7])
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(MahjongSettingsPalette.muted)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                ForEach(0 ..< 42, id: \.self) { cell in
                    let day = cell - weekdayOffset + 1
                    if (1 ... daysInMonth).contains(day), let date = calendar.date(byAdding: .day, value: day - 1, to: first) {
                        let checked = archive.hasCheckedIn(on: date)
                        let today = calendar.isDateInToday(date)
                        VStack(spacing: 3) {
                            Text("\(day)")
                                .font(.system(size: 15, weight: checked || today ? .semibold : .regular))
                            Text(checked ? "✓" : " ")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(MahjongSettingsPalette.ivory)
                        .frame(maxWidth: .infinity)
                        .frame(height: 43)
                        .glassEffect(checked ? .regular : .identity, in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(today ? MahjongSettingsPalette.accent : .clear, lineWidth: 1))
                        .accessibilityLabel("\(day)日\(checked ? "已签到" : "未签到")")
                    } else {
                        Color.clear.frame(height: 43)
                    }
                }
            }
            .mahjongGlassGroup(spacing: 8)
        }
        .padding(22)
        .background(.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
    }

    private func shiftMonth(_ offset: Int) {
        if let next = Calendar.current.date(byAdding: .month, value: offset, to: displayedMonth) {
            displayedMonth = next
        }
    }

    private var voiceContent: some View {
        VStack(alignment: .leading, spacing: 26) {
            MahjongAudioControls(settings: MahjongAudioPlayer.shared.settings)
            Text("报牌音色")
                .font(.system(size: 16))
                .foregroundStyle(MahjongSettingsPalette.muted)
            HStack(spacing: 20) {
                ForEach(MahjongVoiceGender.allCases) { gender in
                    voiceChoice(gender)
                }
            }
            Text("选择后立即生效，试听会播放“胡了”。")
                .font(.system(size: 13))
                .foregroundStyle(MahjongSettingsPalette.muted)
        }
    }

    private func voiceChoice(_ gender: MahjongVoiceGender) -> some View {
        let isSelected = archive.player.voiceGender == gender
        return VStack(spacing: 0) {
            Button {
                archive.updatePlayerProfile(voiceGender: gender)
            } label: {
                VStack(spacing: 16) {
                    Image(systemName: gender == .male ? "person.fill" : "person.fill")
                        .font(.system(size: 48, weight: .ultraLight))
                    Text(gender.displayName)
                        .font(.system(size: 25, weight: .semibold, design: .serif))
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .foregroundStyle(isSelected ? MahjongSettingsPalette.accent : MahjongSettingsPalette.ivory)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                MahjongVoicePlayer.shared.preview(gender: gender)
            } label: {
                Label("试听", systemImage: "play.fill")
                    .font(.system(size: 15, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .foregroundStyle(MahjongSettingsPalette.ivory)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .background(isSelected ? MahjongSettingsPalette.accent.opacity(0.11) : .black.opacity(0.13))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected ? MahjongSettingsPalette.accent : MahjongSettingsPalette.accent.opacity(0.2), lineWidth: isSelected ? 2 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(MahjongSettingsPalette.muted)
    }

    private func recordNumber(_ title: String, _ count: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(count.formatted())
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(MahjongSettingsPalette.muted)
        }
    }

    private func metricRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(MahjongSettingsPalette.muted)
            Spacer()
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(MahjongSettingsPalette.ivory)
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
        }
        .buttonStyle(MahjongGameButtonStyle(kind: .primary))
    }

    private func saveNickname() {
        archive.updatePlayerProfile(nickname: nicknameDraft)
        nicknameDraft = archive.player.nickname
    }
}
