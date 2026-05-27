#if os(iOS)
import SwiftData
import SwiftUI

struct iOSCalendarTimelineGrid: View {
    let dates: [Date]
    @Binding var selectedDate: Date
    let scheduledTasksByDate: [String: [AppTask]]
    let unscheduledTasksByDate: [String: [AppTask]]
    let bundlesByDate: [String: [TaskBundle]]
    let zoomLevel: Int

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let calendar = Calendar.current
    private var baseHourHeight: CGFloat { horizontalSizeClass == .regular ? 64 : 58 }
    private var hourHeight: CGFloat { baseHourHeight + CGFloat((zoomLevel - 1) * 16) }
    private var timelineHeight: CGFloat {
        CGFloat(CadenceScheduleSupport.calendarEndHour - CadenceScheduleSupport.calendarStartHour) * hourHeight
    }

    var body: some View {
        GeometryReader { geo in
            let railWidth: CGFloat = horizontalSizeClass == .regular ? 58 : 48
            let availableWidth = max(geo.size.width - railWidth, 1)
            let minColumnWidth: CGFloat = horizontalSizeClass == .regular ? 112 : 104
            let colWidth = max(dates.count <= 7 ? availableWidth / CGFloat(max(dates.count, 1)) : 126, minColumnWidth)
            let contentWidth = colWidth * CGFloat(dates.count)

            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 0) {
                    iOSCalendarTimeRail(hourHeight: hourHeight)
                        .frame(width: railWidth)

                    ScrollView(.horizontal) {
                        VStack(spacing: 0) {
                            HStack(spacing: 0) {
                                ForEach(dates, id: \.self) { date in
                                    iOSCalendarTimelineDayHeader(
                                        date: date,
                                        isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                                        unscheduledTasks: unscheduledTasks(for: date),
                                        bundleCount: bundles(for: date).count,
                                        taskCount: scheduledTasks(for: date).count
                                    ) {
                                        selectedDate = date
                                    }
                                    .frame(width: colWidth)
                                }
                            }
                            .background(Theme.surface)

                            ZStack(alignment: .topLeading) {
                                iOSCalendarTimelineGridLines(dates: dates, colWidth: colWidth, hourHeight: hourHeight)

                                ForEach(Array(dates.enumerated()), id: \.element) { index, date in
                                    let key = DateFormatters.dateKey(from: date)
                                    iOSCalendarTimelineDayBlocks(
                                        date: date,
                                        isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                                        tasks: CadenceScheduleSupport.items(on: key, in: scheduledTasksByDate),
                                        bundles: CadenceScheduleSupport.items(on: key, in: bundlesByDate),
                                        colWidth: colWidth,
                                        hourHeight: hourHeight
                                    )
                                    .offset(x: CGFloat(index) * colWidth)
                                }
                            }
                            .frame(width: contentWidth, height: timelineHeight)
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.bg)
    }

    private func scheduledTasks(for date: Date) -> [AppTask] {
        CadenceScheduleSupport.items(on: DateFormatters.dateKey(from: date), in: scheduledTasksByDate)
    }

    private func unscheduledTasks(for date: Date) -> [AppTask] {
        CadenceScheduleSupport.items(on: DateFormatters.dateKey(from: date), in: unscheduledTasksByDate)
    }

    private func bundles(for date: Date) -> [TaskBundle] {
        CadenceScheduleSupport.items(on: DateFormatters.dateKey(from: date), in: bundlesByDate)
    }
}

private struct iOSCalendarTimelineDayHeader: View {
    let date: Date
    let isSelected: Bool
    let unscheduledTasks: [AppTask]
    let bundleCount: Int
    let taskCount: Int
    let action: () -> Void

    private let calendar = Calendar.current
    private var isToday: Bool { calendar.isDateInToday(date) }
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var headerHeight: CGFloat {
        horizontalSizeClass == .regular ? 112 : 101
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                VStack(spacing: 3) {
                    Text(DateFormatters.dayOfWeek.string(from: date).uppercased())
                        .font(.system(size: horizontalSizeClass == .regular ? 11 : 10, weight: .semibold))
                        .foregroundStyle(isToday ? Theme.blue : Theme.dim)
                    Text(DateFormatters.dayNumber.string(from: date))
                        .font(.system(size: horizontalSizeClass == .regular ? 20 : 18, weight: isToday || isSelected ? .bold : .regular))
                        .foregroundStyle(isToday ? .white : Theme.text)
                        .frame(width: horizontalSizeClass == .regular ? 36 : 32, height: horizontalSizeClass == .regular ? 36 : 32)
                        .background(isToday ? Theme.blue : isSelected ? Theme.blue.opacity(0.16) : Color.clear)
                        .clipShape(Circle())
                }
                .frame(height: horizontalSizeClass == .regular ? 66 : 58)

                VStack(alignment: .leading, spacing: 3) {
                    ForEach(unscheduledTasks.prefix(2)) { task in
                        iOSCalendarMiniChip(
                            title: task.title.isEmpty ? "Untitled" : task.title,
                            icon: "circle.fill",
                            color: Color(hex: task.containerColor)
                        )
                    }

                    if taskCount + bundleCount > 0 {
                        iOSCalendarMiniChip(
                            title: "\(taskCount + bundleCount) timed",
                            icon: "clock.fill",
                            color: Theme.blue
                        )
                    }

                    if unscheduledTasks.count > 2 {
                        Text("+ \(unscheduledTasks.count - 2) more")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Theme.dim)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 42, alignment: .topLeading)
                .padding(.horizontal, horizontalSizeClass == .regular ? 7 : 5)
                .padding(.bottom, horizontalSizeClass == .regular ? 7 : 5)
            }
            .frame(height: headerHeight)
            .background(isSelected ? Theme.blue.opacity(0.055) : isToday ? Theme.blue.opacity(0.035) : Theme.surface)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Theme.borderSubtle.opacity(0.65))
                    .frame(width: 0.5)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Theme.borderSubtle.opacity(0.65))
                    .frame(height: 0.5)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct iOSCalendarTimeRail: View {
    let hourHeight: CGFloat
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: horizontalSizeClass == .regular ? 112 : 101)
            ForEach(CadenceScheduleSupport.calendarStartHour..<CadenceScheduleSupport.calendarEndHour, id: \.self) { hour in
                Text(hourLabel(hour))
                    .font(.system(size: horizontalSizeClass == .regular ? 11 : 10, weight: .medium))
                    .foregroundStyle(Theme.dim.opacity(hour % 3 == 0 ? 0.9 : 0.45))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .frame(height: hourHeight, alignment: .top)
                    .padding(.trailing, horizontalSizeClass == .regular ? 10 : 8)
            }
        }
        .background(Theme.bg)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Theme.borderSubtle.opacity(0.75))
                .frame(width: 0.5)
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        if hour == 0 { return "12 AM" }
        if hour < 12 { return "\(hour) AM" }
        if hour == 12 { return "12 PM" }
        return "\(hour - 12) PM"
    }
}

struct iOSCalendarTimelineGridLines: View {
    let dates: [Date]
    let colWidth: CGFloat
    let hourHeight: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0...dates.count, id: \.self) { index in
                Rectangle()
                    .fill(Theme.borderSubtle.opacity(0.34))
                    .frame(width: 0.5)
                    .offset(x: CGFloat(index) * colWidth)
            }

            ForEach(0...(CadenceScheduleSupport.calendarEndHour - CadenceScheduleSupport.calendarStartHour), id: \.self) { index in
                Rectangle()
                    .fill(Theme.borderSubtle.opacity(index % 3 == 0 ? 0.46 : 0.20))
                    .frame(height: 0.5)
                    .offset(y: CGFloat(index) * hourHeight)
            }
        }
    }
}

private struct iOSCalendarTimelineDayBlocks: View {
    let date: Date
    let isSelected: Bool
    let tasks: [AppTask]
    let bundles: [TaskBundle]
    let colWidth: CGFloat
    let hourHeight: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            if Calendar.current.isDateInToday(date) {
                Rectangle()
                    .fill(Theme.blue.opacity(0.025))
                    .frame(width: colWidth, height: timelineHeight)
            } else if isSelected {
                Rectangle()
                    .fill(Theme.blue.opacity(0.04))
                    .frame(width: colWidth, height: timelineHeight)
            }

            ForEach(bundles) { bundle in
                iOSCalendarBundleBlock(bundle: bundle)
                    .frame(width: colWidth - 14, height: blockHeight(start: bundle.startMin, end: bundle.endMin))
                    .offset(x: 7, y: yOffset(for: bundle.startMin))
            }

            ForEach(tasks) { task in
                let range = CadenceScheduleSupport.blockRange(
                    startMinute: task.scheduledStartMin,
                    fallbackDuration: task.estimatedMinutes
                )
                iOSCalendarTaskBlock(task: task, startMin: range.start, endMin: range.end)
                    .frame(width: colWidth - 18, height: blockHeight(start: range.start, end: range.end))
                    .offset(x: 9, y: yOffset(for: range.start))
            }
        }
        .frame(width: colWidth, height: timelineHeight, alignment: .topLeading)
    }

    private var timelineHeight: CGFloat {
        CGFloat(CadenceScheduleSupport.calendarEndHour - CadenceScheduleSupport.calendarStartHour) * hourHeight
    }

    private func yOffset(for minute: Int) -> CGFloat {
        CGFloat(minute - CadenceScheduleSupport.calendarStartHour * 60) / 60.0 * hourHeight
    }

    private func blockHeight(start: Int, end: Int) -> CGFloat {
        max(24, CGFloat(end - start) / 60.0 * hourHeight - 4)
    }
}

private struct iOSCalendarTaskBlock: View {
    @Bindable var task: AppTask
    let startMin: Int
    let endMin: Int
    @State private var showDetail = false

    private var color: Color {
        Color(hex: task.containerColor)
    }

    var body: some View {
        Button {
            showDetail = true
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title.isEmpty ? "Untitled" : task.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                Text(CadenceScheduleSupport.timeRangeLabel(startMinute: startMin, endMinute: endMin))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Theme.surfaceElevated)
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(color.opacity(task.isDone ? 0.06 : 0.16))
                }
            )
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color)
                    .frame(width: 3)
                    .padding(.vertical, 5)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(color.opacity(0.24), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            iOSTaskDetailSheet(task: task)
        }
    }
}

private struct iOSCalendarBundleBlock: View {
    let bundle: TaskBundle

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 9, weight: .semibold))
                Text(bundle.displayTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(2)
            }
            .foregroundStyle(Theme.text)

            Text(CadenceScheduleSupport.timeRangeLabel(startMinute: bundle.startMin, endMinute: bundle.endMin))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Theme.surfaceElevated)
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Theme.amber.opacity(0.14))
            }
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Theme.amber.opacity(0.28), lineWidth: 1)
        }
    }
}
#endif
