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
        Set((tasks + unscheduledTasks + dueOnlyTasks).map(\.id)).count + bundles.count + events.count
    }

    private var timedTasks: [AppTask] {
        tasks.filter { $0.scheduledDate == DateFormatters.dateKey(from: date) && $0.scheduledStartMin >= 0 }
    }

    private var hasItems: Bool {
        !bundles.isEmpty || !events.isEmpty || !timedTasks.isEmpty || !unscheduledTasks.isEmpty || !dueOnlyTasks.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            iOSPanelHeader(
                eyebrow: DateFormatters.longDate.string(from: date),
                title: "Schedule",
                count: totalCount
            )
            Divider().background(Theme.borderSubtle)

            iOSCalendarInspectorActionBar(addItem: addItem)

            if !hasItems {
                iOSEmptyPanel(
                    systemImage: "calendar",
                    title: "Nothing scheduled",
                    subtitle: "Tasks with due or do dates will show here."
                )
            } else {
                List {
                    if !bundles.isEmpty {
                        Section {
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
                        } header: {
                            iOSTaskSectionHeader(title: "Blocks", color: Theme.amber)
                        }
                    }

                    if !events.isEmpty {
                        Section {
                            ForEach(events, id: \.calendarItemIdentifier) { event in
                                Button {
                                    selectedEvent = iOSCalendarEventSelection(event: event)
                                } label: {
                                    iOSCalendarEventSummaryRow(event: event)
                                }
                                .buttonStyle(.plain)
                            }
                        } header: {
                            iOSTaskSectionHeader(title: "Apple Calendar", color: Theme.green)
                        }
                    }

                    if !timedTasks.isEmpty {
                        Section {
                            ForEach(timedTasks) { task in
                                iOSTaskListRow(task: task)
                            }
                        } header: {
                            iOSTaskSectionHeader(title: "Timed", color: Theme.blue)
                        }
                    }

                    if !unscheduledTasks.isEmpty {
                        Section {
                            ForEach(unscheduledTasks) { task in
                                iOSTaskListRow(task: task)
                            }
                        } header: {
                            iOSTaskSectionHeader(title: "Do Date", color: Theme.purple)
                        }
                    }

                    if !dueOnlyTasks.isEmpty {
                        Section {
                            ForEach(dueOnlyTasks) { task in
                                iOSTaskListRow(task: task)
                            }
                        } header: {
                            iOSTaskSectionHeader(title: "Due", color: Theme.red)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
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

private struct iOSCalendarInspectorActionBar: View {
    let addItem: () -> Void

    var body: some View {
        HStack {
            Button(action: addItem) {
                Label("Add", systemImage: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.blue)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.surface.opacity(0.7))
    }
}
#endif
