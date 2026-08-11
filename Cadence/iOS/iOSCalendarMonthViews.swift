#if os(iOS)
import EventKit
import SwiftData
import SwiftUI

struct iOSCalendarMonthGrid: View {
    let monthDate: Date
    @Binding var selectedDate: Date
    let monthTasksByDate: [String: [AppTask]]
    let bundlesByDate: [String: [TaskBundle]]
    let eventsByDate: [String: [EKEvent]]

    private let calendar = Calendar.current
    private var monthDays: [Date] {
        CadenceScheduleSupport.monthGridDays(for: monthDate, calendar: calendar)
    }

    var body: some View {
        GeometryReader { proxy in
            let headerHeight: CGFloat = 36
            let cellHeight = max(104, (proxy.size.height - headerHeight) / 6)

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(CadenceScheduleSupport.weekdaySymbols(calendar: calendar), id: \.self) { symbol in
                        Text(symbol)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.dim)
                            .frame(maxWidth: .infinity)
                            .frame(height: headerHeight)
                    }
                }
                .background(Theme.surface)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                    ForEach(monthDays, id: \.self) { date in
                        let key = DateFormatters.dateKey(from: date)
                        iOSCalendarMonthDayCell(
                            date: date,
                            displayMonth: monthDate,
                            isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                            tasks: CadenceScheduleSupport.items(on: key, in: monthTasksByDate),
                            bundles: CadenceScheduleSupport.items(on: key, in: bundlesByDate),
                            events: CadenceScheduleSupport.items(on: key, in: eventsByDate),
                            minHeight: cellHeight
                        ) {
                            selectedDate = date
                        }
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .background(Theme.bg)
    }
}

private struct iOSCalendarMonthDayCell: View {
    let date: Date
    let displayMonth: Date
    let isSelected: Bool
    let tasks: [AppTask]
    let bundles: [TaskBundle]
    let events: [EKEvent]
    let minHeight: CGFloat
    let action: () -> Void

    private let calendar = Calendar.current
    private var isToday: Bool { calendar.isDateInToday(date) }
    private var isCurrentMonth: Bool { calendar.isDate(date, equalTo: displayMonth, toGranularity: .month) }
    private var isFirstDayOfMonth: Bool { calendar.component(.day, from: date) == 1 }
    private var visibleBundles: [TaskBundle] { Array(bundles.prefix(3)) }
    private var visibleEvents: [EKEvent] { Array(events.prefix(max(0, 4 - visibleBundles.count))) }
    private var visibleTasks: [AppTask] { Array(tasks.prefix(max(0, 5 - visibleBundles.count - visibleEvents.count))) }
    private var overflow: Int { max(0, tasks.count + bundles.count + events.count - visibleTasks.count - visibleBundles.count - visibleEvents.count) }

    private var dateLabelColor: Color {
        if isToday { return Theme.onColor }
        if isSelected { return Theme.blue }
        return isCurrentMonth ? Theme.text : Theme.dim.opacity(0.58)
    }

    private var dateLabelWeight: Font.Weight {
        if isToday || isSelected { return .bold }
        return isCurrentMonth ? .medium : .regular
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    if isFirstDayOfMonth {
                        Text(DateFormatters.monthAbbrev.string(from: date))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(dateLabelColor)
                            .lineLimit(1)
                    }

                    Text(DateFormatters.dayNumber.string(from: date))
                        .font(.system(size: 12, weight: dateLabelWeight))
                        .foregroundStyle(dateLabelColor)
                        .frame(width: 25, height: 25)
                        .background(dateBadgeFill)
                        .clipShape(Circle())

                    Spacer(minLength: 0)

                    if !tasks.isEmpty || !bundles.isEmpty || !events.isEmpty {
                        Text("\(tasks.count + bundles.count + events.count)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.dim)
                            .monospacedDigit()
                            .padding(.horizontal, 6)
                            .frame(height: 18)
                            .background(Theme.surfaceElevated.opacity(0.52))
                            .clipShape(Capsule())
                    }
                }
                .padding(.top, 6)
                .padding(.horizontal, 7)

                VStack(alignment: .leading, spacing: 3) {
                    ForEach(visibleBundles) { bundle in
                        iOSCalendarMiniChip(
                            title: bundle.displayTitle,
                            icon: "tray.full.fill",
                            color: Theme.amber
                        )
                    }
                    ForEach(visibleEvents, id: \.calendarItemIdentifier) { event in
                        iOSCalendarMiniChip(
                            title: iOSCalendarEventSupport.title(for: event),
                            icon: event.isAllDay ? "calendar" : "calendar.badge.clock",
                            color: iOSCalendarEventSupport.color(for: event.calendar)
                        )
                    }
                    ForEach(visibleTasks) { task in
                        iOSCalendarMiniChip(
                            title: task.title.isEmpty ? "Untitled" : task.title,
                            icon: task.isDone ? "checkmark.circle.fill" : "circle.fill",
                            color: Color(hex: task.containerColor)
                        )
                    }
                    if overflow > 0 {
                        Text("+ \(overflow) more")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.dim)
                            .padding(.horizontal, 5)
                    }
                }
                .padding(.horizontal, 6)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            .background(cellBackground)
            .opacity(isCurrentMonth ? 1 : 0.52)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.blue.opacity(0.65), lineWidth: 1.5)
                        .padding(4)
                }
            }
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Theme.borderSubtle.opacity(0.30))
                    .frame(width: 0.5)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Theme.borderSubtle.opacity(0.42))
                    .frame(height: 0.5)
            }
        }
        .buttonStyle(.plain)
    }

    private var cellBackground: Color {
        if isSelected { return Theme.blue.opacity(0.075) }
        if isToday { return Theme.blue.opacity(0.045) }
        return Theme.bg
    }

    private var dateBadgeFill: Color {
        if isToday { return Theme.blue }
        if isSelected { return Theme.blue.opacity(0.16) }
        return Theme.surfaceElevated.opacity(isCurrentMonth ? 0.18 : 0.08)
    }
}

struct iOSCalendarMiniChip: View {
    let title: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2.5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                    .fill(Theme.surfaceElevated.opacity(0.82))
                RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                    .fill(color.opacity(0.16))
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
    }
}
#endif
