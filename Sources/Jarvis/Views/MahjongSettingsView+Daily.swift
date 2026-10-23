import SwiftUI

extension MahjongSettingsView {
    var dailyContent: some View {
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

    func signInStatistic(_ title: String, _ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(count) 天")
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .foregroundStyle(MahjongSettingsPalette.accent)
            Text(title).font(.system(size: 13)).foregroundStyle(MahjongSettingsPalette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var monthCheckInCount: Int {
        guard let interval = Calendar.current.dateInterval(of: .month, for: displayedMonth) else { return 0 }
        return archive.checkInDays.filter { day in
            guard let date = Self.dayFormatter.date(from: day) else { return false }
            return interval.contains(date)
        }.count
    }

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    var calendarView: some View {
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

    func shiftMonth(_ offset: Int) {
        if let next = Calendar.current.date(byAdding: .month, value: offset, to: displayedMonth) {
            displayedMonth = next
        }
    }

    var voiceContent: some View {
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

    func voiceChoice(_ gender: MahjongVoiceGender) -> some View {
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

    func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(MahjongSettingsPalette.muted)
    }

    func recordNumber(_ title: String, _ count: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(count.formatted())
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(MahjongSettingsPalette.muted)
        }
    }

    func metricRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(MahjongSettingsPalette.muted)
            Spacer()
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(MahjongSettingsPalette.ivory)
        }
    }

    func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
        }
        .buttonStyle(MahjongGameButtonStyle(kind: .primary))
    }

    func saveNickname() {
        archive.updatePlayerProfile(nickname: nicknameDraft)
        nicknameDraft = archive.player.nickname
    }
}
