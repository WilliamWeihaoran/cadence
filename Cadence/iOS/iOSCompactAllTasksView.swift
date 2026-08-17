#if os(iOS)
import SwiftUI

struct iOSCompactAllTasksView: View {
    var showsHeader = true
    @Environment(\.dismiss) private var dismiss
    let activeTasks: [AppTask]
    let completedTasks: [AppTask]
    @Binding var sortMode: CadenceTaskSortMode
    @Binding var showCompleted: Bool

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                // No subtitle: a line under "All Tasks" saying it is where you review active work
                // describes the page you are already looking at. Same rule that deleted
                // `subtitle` from `DesktopPageHeader` on macOS.
                //
                // The active count rides in the header, as it does on the iPad panel and on Inbox
                // at both widths. It used to be the first of three tiles in a metric strip here;
                // it used to be the first of three tiles in a metric strip — Active / Dated /
                // Done — which the iPad panel has never had. Done is the options bar's
                // "Completed N" chip at both widths, so only "Dated" was unique to the phone, and
                // it is not carried anywhere now: a count of tasks holding *a* date lumps overdue
                // in with next year, and All Tasks already groups by date, which answers the same
                // question usefully — which dates, and which tasks.
                if showsHeader {
                    iOSCompactPageHeader(
                        eyebrow: "Tasks",
                        title: "All Tasks",
                        systemImage: "checklist",
                        color: Theme.blue,
                        count: activeTasks.count,
                        onBack: { dismiss() }
                    )
                }

                optionsBar
                taskSections
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            // See the note in `iOSCompactTodayView`: end-of-content padding, not bar clearance.
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        .background(Theme.bg.ignoresSafeArea())
    }

    private var optionsBar: some View {
        iOSTaskViewOptionsBar(
            sortMode: $sortMode,
            showCompleted: $showCompleted,
            completedCount: completedTasks.count
        )
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var taskSections: some View {
        if activeTasks.isEmpty && (!showCompleted || completedTasks.isEmpty) {
            iOSEmptyPanel(
                systemImage: "checklist",
                title: CadenceEmptyStateCopy.allTasksTitle,
                subtitle: CadenceEmptyStateCopy.allTasksSubtitle
            )
            .frame(minHeight: 220)
            .cadenceCard()
        } else {
            VStack(alignment: .leading, spacing: 14) {
                if !activeTasks.isEmpty {
                    iOSTaskGroupSection(
                        title: "Active",
                        color: Theme.blue,
                        tasks: activeTasks
                    )
                }

                if showCompleted && !completedTasks.isEmpty {
                    iOSTaskGroupSection(
                        title: "Completed",
                        color: Theme.green,
                        tasks: CadenceTaskSurfaceOptions.completedRows(from: completedTasks),
                        opacity: 0.62
                    )
                }
            }
        }
    }
}


#endif
