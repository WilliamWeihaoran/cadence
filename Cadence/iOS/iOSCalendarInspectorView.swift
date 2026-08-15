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

    private var timedTasks: [AppTask] {
        tasks.filter { $0.scheduledDate == DateFormatters.dateKey(from: date) && $0.scheduledStartMin >= 0 }
    }

    private var hasItems: Bool {
        !bundles.isEmpty || !events.isEmpty || !timedTasks.isEmpty || !unscheduledTasks.isEmpty || !dueOnlyTasks.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            iOSCalendarInspectorHeader(date: date, addItem: addItem)
            Divider().background(Theme.borderSubtle)

            if !hasItems {
                iOSCalendarInspectorEmptyState(addItem: addItem)
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(Theme.bg)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
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
                                    .buttonStyle(.iosPressable)
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
                                    .buttonStyle(.iosPressable)
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

/// The inspector's header.
///
/// The long date used to be the eyebrow over a title reading "Schedule" — a label naming the pane
/// you are already looking at, sitting above the only line that said anything. They are swapped.
/// Gone with it: a weekday pill duplicating the weekday already on the date tile, and a count badge
/// pinned to the *add* button, which counted the day's items on a control that adds one.
private struct iOSCalendarInspectorHeader: View {
    let date: Date
    let addItem: () -> Void

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
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                    .strokeBorder(Theme.blue.opacity(0.22), lineWidth: 1)
            }

            Text(DateFormatters.longDate.string(from: date))
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 0)

            Button(action: addItem) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.onColor)
                    .frame(width: 40, height: 40)
                    .background(Theme.blue)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
                    .iOSExpandedHitArea(2)
            }
            .buttonStyle(.iosPressable)
            .accessibilityLabel("Add calendar item")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 11)
        .background(Theme.surface)
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

/// One line and one action.
///
/// It was an icon tile, a heading, a three-line explanation of what a planned task, a time block and
/// an Apple Calendar event are, and a button — a card the height of a third of a phone screen, whose
/// whole content was "there is nothing here". The explanation named the three things the add control
/// it sits beside already offers, and the header's own `+` offers them too.
private struct iOSCalendarInspectorEmptyState: View {
    let addItem: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("Nothing scheduled")
                .font(.system(size: 13))
                .foregroundStyle(Theme.dim)

            Spacer(minLength: 8)

            iOSActionButton(
                title: "Add",
                systemImage: "plus",
                role: .secondary,
                size: .compact,
                action: addItem
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceElevated.opacity(0.38))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
    }
}

/// One Apple Calendar event as a list row. Shared with the compact month agenda, which lists the
/// same three kinds of thing this inspector does and should not draw a second event row to do it.
struct iOSCalendarEventSummaryRow: View {
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
