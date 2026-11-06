import SwiftUI

struct HomeCalendarCard: View {
    @State private var month = Date()
    @Environment(\.scenePhase) private var scenePhase
    @State private var holidays: [String: ChinaHolidayDay] = [:]
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.firstWeekday = 2
        return value
    }

    var body: some View {
        HomeDashboardCard(title: "日历", symbol: "calendar", contentSpacing: 10, contentPadding: 14) {
            HStack(spacing: 8) {
                Text(month.formatted(.dateTime.year().month())).font(.system(size: 12, weight: .medium))
                Spacer()
                monthButton("上一月", symbol: "chevron.left", offset: -1)
                Button("今天") {
                    month = Date()
                }
                .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Color.jarvisAccent)
                monthButton("下一月", symbol: "chevron.right", offset: 1)
            }
            VStack(spacing: 3) {
                HStack(spacing: 0) {
                    ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { day in
                        Text(day).font(.system(size: 10)).foregroundStyle(.tertiary).frame(maxWidth: .infinity)
                    }
                }
                let days = HomeDashboardFormatting.monthDays(containing: month, calendar: calendar)
                monthGrid(days).frame(maxHeight: .infinity)
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            holidays = await ChinaHolidaySubscription.shared.cached().days
            while !Task.isCancelled {
                let fresh = await ChinaHolidaySubscription.shared.refresh()
                guard !Task.isCancelled else { return }
                holidays = fresh.days
                do { try await Task.sleep(for: .seconds(900)) } catch { return }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            month = Date()
        }
    }

    private func monthButton(_ title: String, symbol: String, offset: Int) -> some View {
        Button {
            if let next = HomeDashboardFormatting.shiftedMonth(from: month, by: offset, calendar: calendar) {
                month = next
            }
        } label: {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).frame(width: 22, height: 22)
        }
        .buttonStyle(.plain).accessibilityLabel(title)
    }

    private func monthGrid(_ days: [Date?]) -> some View {
        GeometryReader { geometry in
            let weeks = (days.count + 6) / 7
            let rowHeight = max(1, geometry.size.height / CGFloat(max(1, weeks)))
            VStack(spacing: 0) {
                ForEach(0 ..< weeks, id: \.self) { week in
                    HStack(spacing: 0) {
                        ForEach(0 ..< 7, id: \.self) { weekday in
                            let index = week * 7 + weekday
                            if index < days.count, let date = days[index] {
                                dayCell(date, height: rowHeight)
                            } else {
                                Color.clear.frame(maxWidth: .infinity).accessibilityHidden(true)
                            }
                        }
                    }.frame(height: rowHeight)
                }
            }
        }
    }

    private func dayCell(_ date: Date, height: CGFloat) -> some View {
        let today = calendar.isDateInToday(date)
        let holiday = ChinaHolidayCalendar.entry(for: date, calendar: calendar, subscribedDays: holidays)
        let fullDate = date.formatted(.dateTime.year().month().day().weekday())
        let tint: Color = holiday?.isWorkday == true ? .orange : (holiday?.kind == .rest ? .red : .jarvisAccent)
        let scale = min(1, height / 39)
        return VStack(spacing: 3 * scale) {
            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 11, weight: today ? .semibold : .regular))
                .foregroundStyle(today ? Color.white : .primary)
                .frame(width: 22 * scale, height: 22 * scale)
                .background {
                    if today {
                        Circle().fill(Color.jarvisAccent)
                    }
                }
            Group {
                if let holiday {
                    Text(holiday.label)
                        .font(.system(size: max(6.5, 8 * scale), weight: .medium))
                        .foregroundStyle(tint)
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .padding(.horizontal, 4 * scale).frame(height: 14 * scale)
                        .background(tint.opacity(0.12), in: Capsule())
                } else {
                    Color.clear.frame(height: 14 * scale)
                }
            }.frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .help(holiday.map { "\(fullDate) · \($0.label)" } ?? fullDate)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(holiday.map { "\(fullDate)，\($0.label)" } ?? fullDate)
    }
}
