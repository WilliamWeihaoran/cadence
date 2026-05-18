#if os(iOS)
import SwiftData
import SwiftUI

struct iOSCalendarDayInspector: View {
    let date: Date
    let tasks: [AppTask]
    let bundles: [TaskBundle]
    let unscheduledTasks: [AppTask]
    let dueOnlyTasks: [AppTask]

    private var totalCount: Int {
        Set((tasks + unscheduledTasks + dueOnlyTasks).map(\.id)).count + bundles.count
    }

    private var timedTasks: [AppTask] {
        tasks.filter { $0.scheduledDate == DateFormatters.dateKey(from: date) && $0.scheduledStartMin >= 0 }
    }

    private var hasItems: Bool {
        !bundles.isEmpty || !timedTasks.isEmpty || !unscheduledTasks.isEmpty || !dueOnlyTasks.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            iOSPanelHeader(
                eyebrow: DateFormatters.longDate.string(from: date),
                title: "Schedule",
                count: totalCount
            )
            Divider().background(Theme.borderSubtle)

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
                                iOSFeatureSummaryRow(
                                    title: bundle.displayTitle,
                                    subtitle: CadenceScheduleSupport.timeRangeLabel(startMinute: bundle.startMin, endMinute: bundle.endMin),
                                    icon: "tray.full.fill",
                                    color: Theme.amber
                                )
                            }
                        } header: {
                            iOSTaskSectionHeader(title: "Blocks", color: Theme.amber)
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
    }
}
#endif
