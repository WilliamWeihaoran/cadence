#if os(iOS)
import SwiftUI

struct iOSCompactInboxView: View {
    var showsHeader = true
    @Environment(\.dismiss) private var dismiss
    let inboxTasks: [AppTask]
    let completedInboxTasks: [AppTask]
    @Binding var sortMode: CadenceTaskSortMode
    @Binding var showCompleted: Bool

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 11) {
                // No subtitle — see the note on the All Tasks header. The count is the header's,
                // as it is on iPad: it used to be delegated to an "Active" metric tile that no
                // longer exists.
                if showsHeader {
                    iOSCompactPageHeader(
                        eyebrow: "Capture",
                        title: "Inbox",
                        systemImage: "tray.fill",
                        color: Theme.blue,
                        count: inboxTasks.count,
                        onBack: { dismiss() }
                    )
                }

                optionsBar
                taskSections
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            // See the note in `iOSCompactTodayView`: end-of-content padding, not bar clearance.
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        .background(Theme.bg.ignoresSafeArea())
    }

    /// Sort and completed-visibility only. The "Add an inbox task…" field that used to head this
    /// card is gone: the tab bar's centre `+` opens the full composer from every compact screen, so
    /// the field was a second, weaker capture affordance — title-only — a thumb's width from a
    /// better one.
    private var optionsBar: some View {
        iOSTaskViewOptionsBar(
            sortMode: $sortMode,
            showCompleted: $showCompleted,
            completedCount: completedInboxTasks.count
        )
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var taskSections: some View {
        if inboxTasks.isEmpty && (!showCompleted || completedInboxTasks.isEmpty) {
            iOSEmptyPanel(
                systemImage: "tray",
                title: CadenceEmptyStateCopy.inboxTitle,
                subtitle: CadenceEmptyStateCopy.inboxSubtitle
            )
            .frame(minHeight: 190)
            .cadenceCard()
        } else {
            VStack(alignment: .leading, spacing: 14) {
                if !inboxTasks.isEmpty {
                    iOSTaskGroupSection(
                        title: "Active",
                        color: Theme.blue,
                        tasks: inboxTasks
                    )
                }

                if showCompleted && !completedInboxTasks.isEmpty {
                    iOSTaskGroupSection(
                        title: "Completed",
                        color: Theme.green,
                        tasks: CadenceTaskSurfaceOptions.completedRows(from: completedInboxTasks),
                        opacity: 0.62
                    )
                }
            }
            .padding(12)
            .cadenceCard()
        }
    }
}

#endif
