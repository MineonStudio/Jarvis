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
            let days = HomeDashboardFormatting.monthDays(containing: month, calendar: calendar)
            ViewThatFits(in: .vertical) {
                monthColumn(days, rowHeight: HomeDashboardLayout.calendarPreferredRowHeight)
                flexibleMonth(days)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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

    private var monthControls: some View {
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
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { day in
                Text(day).font(.system(size: 10)).foregroundStyle(.tertiary).frame(maxWidth: .infinity)
            }
        }
    }

    private func monthColumn(_ days: [Date?], rowHeight: CGFloat) -> some View {
        VStack(spacing: 10) {
            monthControls
            VStack(spacing: 3) {
                weekdayHeader
                weekRows(days, weeks: weekCount(days), rowHeight: rowHeight)
            }
        }
    }

    /// Used only when the preferred row height does not fit. Rows then share
    /// the leftover height and stay attached to the weekday labels.
    private func flexibleMonth(_ days: [Date?]) -> some View {
        VStack(spacing: 10) {
            monthControls
            VStack(spacing: 3) {
                weekdayHeader
                monthGrid(days)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func weekCount(_ days: [Date?]) -> Int {
        max(1, (days.count + 6) / 7)
    }

    private func monthGrid(_ days: [Date?]) -> some View {
        GeometryReader { geometry in
            let weeks = weekCount(days)
            let rowHeight = HomeDashboardLayout.calendarRowHeight(
                availableHeight: geometry.size.height, weeks: weeks
            )
            weekRows(days, weeks: weeks, rowHeight: rowHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func weekRows(_ days: [Date?], weeks: Int, rowHeight: CGFloat) -> some View {
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
