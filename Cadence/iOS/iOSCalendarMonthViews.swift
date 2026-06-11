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
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(calendar.shortWeekdaySymbols, id: \.self) { symbol in
                    Text(symbol.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
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
                        events: CadenceScheduleSupport.items(on: key, in: eventsByDate)
                    ) {
                        selectedDate = date
                    }
                }
            }
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
    let action: () -> Void

    private let calendar = Calendar.current
    private var isToday: Bool { calendar.isDateInToday(date) }
    private var isCurrentMonth: Bool { calendar.isDate(date, equalTo: displayMonth, toGranularity: .month) }
    private var visibleBundles: [TaskBundle] { Array(bundles.prefix(2)) }
    private var visibleEvents: [EKEvent] { Array(events.prefix(max(0, 2 - visibleBundles.count))) }
    private var visibleTasks: [AppTask] { Array(tasks.prefix(max(0, 4 - visibleBundles.count - visibleEvents.count))) }
    private var overflow: Int { max(0, tasks.count + bundles.count + events.count - visibleTasks.count - visibleBundles.count - visibleEvents.count) }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(DateFormatters.dayNumber.string(from: date))
                        .font(.system(size: 12, weight: isToday || isSelected ? .bold : .regular))
                        .foregroundStyle(isToday ? .white : isCurrentMonth ? Theme.text : Theme.dim.opacity(0.55))
                        .frame(width: 24, height: 24)
                        .background(isToday ? Theme.blue : isSelected ? Theme.blue.opacity(0.18) : Color.clear)
                        .clipShape(Circle())
                    Spacer()
                }

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
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Theme.dim)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(7)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .background(isSelected ? Theme.blue.opacity(0.055) : isToday ? Theme.blue.opacity(0.035) : Theme.bg)
            .opacity(isCurrentMonth ? 1 : 0.52)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Theme.borderSubtle.opacity(0.48))
                    .frame(width: 0.5)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Theme.borderSubtle.opacity(0.48))
                    .frame(height: 0.5)
            }
        }
        .buttonStyle(.plain)
    }
}

struct iOSCalendarMiniChip: View {
    let title: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Theme.surfaceElevated)
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(color.opacity(0.12))
            }
        )
        .overlay {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(color.opacity(0.18), lineWidth: 1)
        }
    }
}
#endif
