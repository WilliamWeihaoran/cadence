#if os(iOS) || os(macOS)
import SwiftUI

struct CalendarBoardMonthView: View {
    let monthDate: Date
    @Binding var selectedDate: Date
    let summariesByDate: [String: CadenceCalendarBoardDaySummary]
    var horizontalPadding: CGFloat = 22
    var weekdayTopPadding: CGFloat = 18
    var weekdayBottomPadding: CGFloat = 10
    var cellSpacing: CGFloat = 10
    var minCellHeight: CGFloat = 72
    var selectedFill: Color = Theme.blue
    var surfaceFill: Color = Theme.surfaceElevated.opacity(0.36)
    var backgroundFill: Color = Theme.surface

    private let calendar = Calendar.current

    private var days: [Date] {
        CadenceScheduleSupport.monthGridDays(for: monthDate, calendar: calendar)
    }

    var body: some View {
        GeometryReader { geo in
            let headerHeight = weekdayTopPadding + weekdayBottomPadding + 14
            let availableGridHeight = max(geo.size.height - headerHeight - 16, 0)
            let computedCellHeight = max(
                (availableGridHeight - cellSpacing * 5) / 6,
                minCellHeight
            )

            VStack(spacing: 0) {
                weekdayHeader
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, weekdayTopPadding)
                    .padding(.bottom, weekdayBottomPadding)

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: cellSpacing), count: 7),
                    spacing: cellSpacing
                ) {
                    ForEach(days, id: \.self) { date in
                        let key = DateFormatters.dateKey(from: date)
                        CalendarBoardDayCell(
                            date: date,
                            summary: summariesByDate[key] ?? CadenceCalendarBoardDaySummary(
                                dateKey: key,
                                taskMarkers: [],
                                eventMarkers: [],
                                bundleCount: 0,
                                overflowCount: 0
                            ),
                            isCurrentMonth: calendar.isDate(date, equalTo: monthDate, toGranularity: .month),
                            isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                            selectedFill: selectedFill,
                            surfaceFill: surfaceFill,
                            minHeight: computedCellHeight
                        ) {
                            selectedDate = calendar.startOfDay(for: date)
                        }
                    }
                }
                .padding(.horizontal, horizontalPadding)

                Spacer(minLength: 0)
            }
        }
        .background(backgroundFill)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(calendar.shortWeekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct CalendarBoardDayCell: View {
    let date: Date
    let summary: CadenceCalendarBoardDaySummary
    let isCurrentMonth: Bool
    let isSelected: Bool
    let selectedFill: Color
    let surfaceFill: Color
    let minHeight: CGFloat
    let action: () -> Void

    private let calendar = Calendar.current
    private var isToday: Bool { calendar.isDateInToday(date) }
    private var foreground: Color {
        if isSelected { return .white }
        return isCurrentMonth ? Theme.text : Theme.dim.opacity(0.42)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 6) {
                    Text(DateFormatters.dayNumber.string(from: date))
                        .font(.system(size: 13, weight: isToday || isSelected ? .bold : .semibold))
                        .foregroundStyle(foreground)
                        .frame(width: 26, height: 26)
                        .background(dayNumberFill)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Spacer(minLength: 4)

                    if summary.overflowCount > 0 {
                        Text("+\(summary.overflowCount)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(isSelected ? .white.opacity(0.92) : Theme.dim)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(isSelected ? .white.opacity(0.18) : Theme.surfaceElevated.opacity(0.8))
                            )
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    if summary.bundleCount > 0 {
                        CalendarBoardBundleMarker(count: summary.bundleCount, isSelected: isSelected)
                    }

                    CalendarBoardEventBars(markers: summary.eventMarkers, isSelected: isSelected)

                    if !summary.taskMarkers.isEmpty {
                        CalendarBoardTaskCountBubbles(markers: summary.taskMarkers, isSelected: isSelected)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            .background(cellBackground)
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(cellStroke, lineWidth: isSelected ? 1.2 : 1)
            }
            .opacity(isCurrentMonth ? 1 : 0.46)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let itemLabel = summary.totalCount == 1 ? "item" : "items"
        return "\(DateFormatters.longDate.string(from: date)), \(summary.totalCount) \(itemLabel)"
    }

    private var dayNumberFill: Color {
        if isSelected { return .white.opacity(0.18) }
        if isToday { return selectedFill.opacity(0.18) }
        return .clear
    }

    private var cellBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? selectedFill : surfaceFill)
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isToday && !isSelected ? selectedFill.opacity(0.08) : .clear)
        }
    }

    private var cellStroke: Color {
        if isSelected { return selectedFill.opacity(0.7) }
        if isToday { return selectedFill.opacity(0.34) }
        return Theme.borderSubtle.opacity(0.24)
    }
}

private struct CalendarBoardEventBars: View {
    let markers: [CadenceCalendarBoardMarker]
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(markers) { marker in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(marker.color.opacity(isSelected ? 0.90 : 0.76))
                    .frame(height: 5)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct CalendarBoardTaskCountBubbles: View {
    let markers: [CadenceCalendarBoardMarker]
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            ForEach(markers) { marker in
                Text(countLabel(for: marker.count))
                    .font(.system(size: marker.count > 9 ? 7 : 8, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(minWidth: 18, minHeight: 18)
                    .padding(.horizontal, marker.count > 9 ? 3 : 0)
                    .background(
                        Capsule(style: .continuous)
                            .fill(marker.color.opacity(marker.isCompleted ? 0.40 : (isSelected ? 0.96 : 0.84)))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(.white.opacity(isSelected ? 0.34 : 0.16), lineWidth: 0.75)
                    )
            }
            Spacer(minLength: 0)
        }
    }

    private func countLabel(for count: Int) -> String {
        count > 99 ? "99+" : "\(count)"
    }
}

private struct CalendarBoardBundleMarker: View {
    let count: Int
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 4) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Theme.amber.opacity(isSelected ? 0.45 : 0.30))
                    .frame(width: 18, height: 8)
                    .offset(x: 5)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Theme.amber.opacity(isSelected ? 0.95 : 0.76))
                    .frame(width: 18, height: 8)
            }

            if count > 1 {
                Text("\(count)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isSelected ? .white.opacity(0.86) : Theme.amber)
            }
        }
        .frame(height: 10)
    }
}
#endif
