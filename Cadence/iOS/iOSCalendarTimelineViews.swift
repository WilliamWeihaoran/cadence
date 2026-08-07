#if os(iOS)
import EventKit
import SwiftData
import SwiftUI

struct iOSCalendarTimelineGrid: View {
    let dates: [Date]
    @Binding var selectedDate: Date
    let scheduledTasksByDate: [String: [AppTask]]
    let unscheduledTasksByDate: [String: [AppTask]]
    let bundlesByDate: [String: [TaskBundle]]
    let eventsByDate: [String: [EKEvent]]
    let zoomLevel: Int
    let onCreateAt: (String, Int) -> Void

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
                                        eventCount: events(for: date).count,
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
                                        events: CadenceScheduleSupport.items(on: key, in: eventsByDate),
                                        colWidth: colWidth,
                                        hourHeight: hourHeight,
                                        onCreateAt: onCreateAt
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

    private func events(for date: Date) -> [EKEvent] {
        CadenceScheduleSupport.items(on: DateFormatters.dateKey(from: date), in: eventsByDate)
    }
}

private struct iOSCalendarTimelineDayHeader: View {
    let date: Date
    let isSelected: Bool
    let unscheduledTasks: [AppTask]
    let eventCount: Int
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

                    if taskCount + bundleCount + eventCount > 0 {
                        iOSCalendarMiniChip(
                            title: "\(taskCount + bundleCount + eventCount) timed",
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
    let events: [EKEvent]
    let colWidth: CGFloat
    let hourHeight: CGFloat
    let onCreateAt: (String, Int) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            onCreateAt(DateFormatters.dateKey(from: date), minute(for: value.location.y))
                        }
                )

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

            ForEach(timedEvents, id: \.calendarItemIdentifier) { event in
                let range = iOSCalendarEventSupport.minuteRange(for: event)
                iOSCalendarEventBlock(event: event, startMin: range.start, endMin: range.end)
                    .frame(width: colWidth - 18, height: blockHeight(start: range.start, end: range.end))
                    .offset(x: 9, y: yOffset(for: range.start))
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

    private var timedEvents: [EKEvent] {
        events.filter { !$0.isAllDay }
    }

    private func yOffset(for minute: Int) -> CGFloat {
        CGFloat(minute - CadenceScheduleSupport.calendarStartHour * 60) / 60.0 * hourHeight
    }

    private func blockHeight(start: Int, end: Int) -> CGFloat {
        max(24, CGFloat(end - start) / 60.0 * hourHeight - 4)
    }

    private func minute(for yPosition: CGFloat) -> Int {
        let rawMinute = CadenceScheduleSupport.calendarStartHour * 60 + Int((max(0, yPosition) / hourHeight) * 60)
        let snapped = (rawMinute / 15) * 15
        let minimum = CadenceScheduleSupport.calendarStartHour * 60
        let maximum = CadenceScheduleSupport.calendarEndHour * 60 - 15
        return min(max(snapped, minimum), maximum)
    }
}

private struct iOSCalendarEventBlock: View {
    let event: EKEvent
    let startMin: Int
    let endMin: Int

    private var fill: Color {
        iOSCalendarEventSupport.fillColor(for: event.calendar)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "calendar")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.text.opacity(0.82))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(iOSCalendarEventSupport.title(for: event))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)

                Text(CadenceScheduleSupport.timeRangeLabel(startMinute: startMin, endMinute: endMin))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.text.opacity(0.7))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(fill)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
    }
}

private struct iOSCalendarTaskBlock: View {
    @Bindable var task: AppTask
    let startMin: Int
    let endMin: Int
    @State private var showDetail = false

    private var listColor: Color {
        Color(hex: task.containerColor)
    }

    private var priorityColor: Color {
        Theme.priorityColor(task.priority)
    }

    var body: some View {
        Button {
            showDetail = true
        } label: {
            HStack(alignment: .top, spacing: 6) {
                iOSTaskCompletionCircle(isDone: task.isDone, tint: priorityColor)
                    .frame(width: 11, height: 11)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title.isEmpty ? "Untitled" : task.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(task.isDone ? Theme.dim : Theme.text)
                        .strikethrough(task.isDone, color: Theme.dim)
                        .lineLimit(2)
                    Text(CadenceScheduleSupport.timeRangeLabel(startMinute: startMin, endMinute: endMin))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(listColor.opacity(task.isDone ? 0.05 : 0.10))
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: Theme.radiusControl,
                    topTrailingRadius: Theme.radiusControl
                )
            )
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(listColor)
                    .frame(width: 2)
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
    @State private var showDetail = false

    private var tasks: [AppTask] {
        bundle.sortedTasks
    }

    private var allDone: Bool {
        !tasks.isEmpty && tasks.allSatisfy(\.isDone)
    }

    var body: some View {
        Button {
            showDetail = true
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "tray.full.fill")
                        .font(.system(size: 9, weight: .semibold))
                    Text(bundle.displayTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("×\(tasks.count)")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(allDone ? Theme.dim : Theme.text)
                .strikethrough(allDone, color: Theme.dim)

                ForEach(tasks.prefix(2)) { task in
                    HStack(spacing: 4) {
                        iOSTaskCompletionCircle(isDone: task.isDone, tint: Theme.priorityColor(task.priority))
                            .frame(width: 9, height: 9)
                        Text(task.title.isEmpty ? "Untitled" : task.title)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(task.isDone ? Theme.dim : Theme.text.opacity(0.85))
                            .strikethrough(task.isDone, color: Theme.dim)
                            .lineLimit(1)
                    }
                }

                if tasks.count > 2 {
                    Text("+\(tasks.count - 2) more")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.dim)
                }

                Text(CadenceScheduleSupport.timeRangeLabel(startMinute: bundle.startMin, endMinute: bundle.endMin))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(allDone ? Theme.doneFill.opacity(0.12) : Theme.amber.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                    .stroke(allDone ? Theme.doneFill.opacity(0.4) : Theme.amber.opacity(0.2), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                showDetail = true
            } label: {
                Label("Edit Block", systemImage: "square.and.pencil")
            }
        }
        .sheet(isPresented: $showDetail) {
            iOSCalendarBundleDetailSheet(bundle: bundle)
        }
    }
}
#endif
