#if os(iOS)
import EventKit
import SwiftData
import SwiftUI

struct iOSCalendarDayInspector: View {
    let date: Date
    let tasks: [AppTask]
    let bundles: [TaskBundle]
    let events: [EKEvent]
    let unscheduledTasks: [AppTask]
    let dueOnlyTasks: [AppTask]
    let addItem: () -> Void
    @State private var selectedBundle: TaskBundle?
    @State private var selectedEvent: iOSCalendarEventSelection?

    private var totalCount: Int {
        uniqueTaskCount + bundles.count + events.count
    }

    private var uniqueTaskCount: Int {
        Set((tasks + unscheduledTasks + dueOnlyTasks).map(\.id)).count
    }

    private var timedTasks: [AppTask] {
        tasks.filter { $0.scheduledDate == DateFormatters.dateKey(from: date) && $0.scheduledStartMin >= 0 }
    }

    private var hasItems: Bool {
        !bundles.isEmpty || !events.isEmpty || !timedTasks.isEmpty || !unscheduledTasks.isEmpty || !dueOnlyTasks.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            iOSCalendarInspectorHeader(
                date: date,
                count: totalCount,
                addItem: addItem
            )
            Divider().background(Theme.borderSubtle)

            if !hasItems {
                VStack(alignment: .leading, spacing: 12) {
                    iOSCalendarInspectorSummaryStrip(
                        blockCount: bundles.count,
                        eventCount: events.count,
                        taskCount: uniqueTaskCount
                    )

                    iOSCalendarInspectorEmptyState(addItem: addItem)
                }
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Theme.bg)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        iOSCalendarInspectorSummaryStrip(
                            blockCount: bundles.count,
                            eventCount: events.count,
                            taskCount: uniqueTaskCount
                        )

                        if !bundles.isEmpty {
                            iOSCalendarInspectorSection(title: "Blocks", color: Theme.amber) {
                                ForEach(bundles) { bundle in
                                    Button {
                                        selectedBundle = bundle
                                    } label: {
                                        iOSFeatureSummaryRow(
                                            title: bundle.displayTitle,
                                            subtitle: CadenceScheduleSupport.timeRangeLabel(startMinute: bundle.startMin, endMinute: bundle.endMin),
                                            detail: "\(bundle.sortedTasks.count) task\(bundle.sortedTasks.count == 1 ? "" : "s")",
                                            icon: "tray.full.fill",
                                            color: Theme.amber
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        if !events.isEmpty {
                            iOSCalendarInspectorSection(title: "Apple Calendar", color: Theme.green) {
                                ForEach(events, id: \.calendarItemIdentifier) { event in
                                    Button {
                                        selectedEvent = iOSCalendarEventSelection(event: event)
                                    } label: {
                                        iOSCalendarEventSummaryRow(event: event)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        if !timedTasks.isEmpty {
                            iOSCalendarInspectorSection(title: "Timed", color: Theme.blue) {
                                ForEach(timedTasks) { task in
                                    iOSTaskRow(task: task, density: .compact)
                                }
                            }
                        }

                        if !unscheduledTasks.isEmpty {
                            iOSCalendarInspectorSection(title: "Do Date", color: Theme.purple) {
                                ForEach(unscheduledTasks) { task in
                                    iOSTaskRow(task: task, density: .compact)
                                }
                            }
                        }

                        if !dueOnlyTasks.isEmpty {
                            iOSCalendarInspectorSection(title: "Due", color: Theme.red) {
                                ForEach(dueOnlyTasks) { task in
                                    iOSTaskRow(task: task, density: .compact)
                                }
                            }
                        }
                    }
                    .padding(14)
                }
                .scrollIndicators(.hidden)
                .background(Theme.bg)
            }
        }
        .background(Theme.bg)
        .sheet(item: $selectedBundle) { bundle in
            iOSCalendarBundleDetailSheet(bundle: bundle)
        }
        .sheet(item: $selectedEvent) { selection in
            iOSCalendarEventEditSheet(event: selection.event)
        }
    }
}

private struct iOSCalendarInspectorHeader: View {
    let date: Date
    let count: Int
    let addItem: () -> Void

    private var dayLabel: String {
        DateFormatters.dayOfWeek.string(from: date)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(spacing: 1) {
                Text(DateFormatters.dayOfWeek.string(from: date).prefix(3).uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.blue)
                    .lineLimit(1)

                Text(DateFormatters.dayNumber.string(from: date))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .monospacedDigit()
            }
            .frame(width: 38, height: 38)
            .background(Theme.blue.opacity(0.13))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.blue.opacity(0.22), lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(DateFormatters.longDate.string(from: date))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .textCase(.uppercase)
                    .kerning(0.8)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Schedule")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)

                    Text(dayLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.blue.opacity(0.10))
                        .clipShape(Capsule())
                }
            }

            Spacer(minLength: 0)

            Button(action: addItem) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Theme.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        if count > 0 {
                            Text("\(count)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .monospacedDigit()
                                .padding(.horizontal, 5)
                                .frame(minWidth: 18)
                                .frame(height: 17)
                                .background(Theme.green)
                                .clipShape(Capsule())
                                .offset(x: 6, y: -6)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add calendar item")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 11)
        .background(Theme.surface)
    }
}

private struct iOSCalendarInspectorSummaryStrip: View {
    let blockCount: Int
    let eventCount: Int
    let taskCount: Int

    var body: some View {
        HStack(spacing: 6) {
            iOSCalendarInspectorMetric(
                value: blockCount,
                label: "Blocks",
                systemImage: "tray.full.fill",
                tint: Theme.amber
            )
            iOSCalendarInspectorMetric(
                value: eventCount,
                label: "Events",
                systemImage: "calendar",
                tint: Theme.green
            )
            iOSCalendarInspectorMetric(
                value: taskCount,
                label: "Tasks",
                systemImage: "checklist",
                tint: Theme.blue
            )
        }
    }
}

private struct iOSCalendarInspectorMetric: View {
    let value: Int
    let label: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(value)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .monospacedDigit()
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(tint.opacity(0.15), lineWidth: 1)
        }
    }
}

private struct iOSCalendarInspectorSection<Content: View>: View {
    let title: String
    let color: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            iOSTaskSectionHeader(title: title, color: color)
            content()
        }
    }
}

private struct iOSCalendarInspectorEmptyState: View {
    let addItem: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.blue)
                .frame(width: 38, height: 38)
                .background(Theme.blue.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("Nothing scheduled")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("Add a planned task, time block, or Apple Calendar event for this date.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button(action: addItem) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Theme.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add calendar item")
        }
        .padding(14)
        .background(Theme.surfaceElevated.opacity(0.34))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.borderSubtle.opacity(0.5), lineWidth: 1)
        }
    }
}

private struct iOSCalendarEventSummaryRow: View {
    let event: EKEvent

    private var color: Color {
        iOSCalendarEventSupport.color(for: event.calendar)
    }

    private var subtitle: String {
        iOSCalendarEventSupport.timeRangeLabel(for: event)
    }

    var body: some View {
        iOSFeatureSummaryRow(
            title: iOSCalendarEventSupport.title(for: event),
            subtitle: subtitle,
            detail: event.calendar.title,
            icon: event.isAllDay ? "calendar" : "calendar.badge.clock",
            color: color
        )
    }
}
#endif
