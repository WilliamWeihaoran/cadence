#if os(iOS)
import EventKit
import SwiftData
import SwiftUI

/// One day, in sections: blocks, Apple Calendar, timed, do date, due.
///
/// It opens on an add row and then its first section heading. There used to be a bar above that
/// carrying a rounded `SUN`/`30` tile, "Sunday, August 30" at 19pt, and an add button — a fixed 63pt
/// strip naming a day that whichever surface placed this pane had already named. Month puts it under
/// or beside a grid with that day lit up; the Board, which is the other place it used to appear, is
/// a row of day columns each headed with its own date. The date was never this pane's to state — but
/// the `+` was, and it went out with the bar it happened to be sitting in. It is back as a row that
/// states no date, so nothing here repeats the grid.
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
            if !hasItems {
                iOSCalendarInspectorEmptyState(addItem: addItem)
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(Theme.bg)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        // A day that already holds something still needs a way to add to it. The
                        // empty state has always offered one; the non-empty case had the `+` in the
                        // date bar `42de745` deleted, and lost it with the bar — on the one iPad
                        // page with no floating `+` anywhere else. Same row the Board's day column
                        // uses, in the same place: under the heading, above the items.
                        iOSCalendarAddItemRow(
                            accessibilityLabel: "Add task on \(DateFormatters.longDate.string(from: date))",
                            action: addItem
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
                                    iOSTaskRow(task: task)
                                }
                            }
                        }

                        if !unscheduledTasks.isEmpty {
                            iOSCalendarInspectorSection(title: "Do Date", color: Theme.purple) {
                                ForEach(unscheduledTasks) { task in
                                    iOSTaskRow(task: task)
                                }
                            }
                        }

                        if !dueOnlyTasks.isEmpty {
                            iOSCalendarInspectorSection(title: "Due", color: Theme.red) {
                                ForEach(dueOnlyTasks) { task in
                                    iOSTaskRow(task: task)
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
/// it sits beside already offers.
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
