#if os(iOS)
import SwiftUI

struct iOSCompactAllTasksView: View {
    var showsHeader = true
    @Environment(\.dismiss) private var dismiss
    let activeTasks: [AppTask]
    let completedTasks: [AppTask]
    @Binding var sortMode: CadenceTaskSortMode
    @Binding var showCompleted: Bool

    private var timedCount: Int {
        activeTasks.filter { !$0.scheduledDate.isEmpty || !$0.dueDate.isEmpty }.count
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                // No subtitle: a line under "All Tasks" saying it is where you review active work
                // describes the page you are already looking at. Same rule that deleted
                // `subtitle` from `DesktopPageHeader` on macOS.
                //
                // No `count:` either — the Active stat directly below already reports it.
                if showsHeader {
                    iOSCompactPageHeader(
                        eyebrow: "Tasks",
                        title: "All Tasks",
                        systemImage: "checklist",
                        color: Theme.blue,
                        onBack: { dismiss() }
                    )
                }

                stats
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

    private var stats: some View {
        HStack(spacing: 10) {
            iOSCompactTaskCollectionStat(
                value: "\(activeTasks.count)",
                label: "Active",
                systemImage: "checklist",
                tint: Theme.blue
            )
            iOSCompactTaskCollectionStat(
                value: "\(timedCount)",
                label: "Dated",
                systemImage: "calendar.badge.clock",
                tint: Theme.purple
            )
            iOSCompactTaskCollectionStat(
                value: "\(completedTasks.count)",
                label: "Done",
                systemImage: "checkmark.circle.fill",
                tint: Theme.green
            )
        }
        .padding(4)
        .cadenceCard(background: Theme.surface.opacity(0.68), shadowRadius: 10, shadowY: 4)
    }

    /// Sort and completed-visibility only — see the note on `iOSCompactInboxView.optionsBar` for why
    /// the "Add a task…" field above these two controls is gone.
    private var optionsBar: some View {
        iOSTaskViewOptionsBar(
            sortMode: $sortMode,
            showCompleted: $showCompleted,
            completedCount: completedTasks.count
        )
        .padding(12)
        .cadenceCard()
    }

    @ViewBuilder
    private var taskSections: some View {
        if activeTasks.isEmpty && (!showCompleted || completedTasks.isEmpty) {
            iOSEmptyPanel(
                systemImage: "checklist",
                title: "No active tasks",
                subtitle: "Tasks you create on iPhone, iPad, or Mac will collect here."
            )
            .frame(minHeight: 220)
            .cadenceCard()
        } else {
            VStack(alignment: .leading, spacing: 14) {
                if !activeTasks.isEmpty {
                    iOSCompactTaskCollectionGroup(
                        title: "Active",
                        color: Theme.blue,
                        tasks: activeTasks,
                        opacity: 1
                    )
                }

                if showCompleted && !completedTasks.isEmpty {
                    iOSCompactTaskCollectionGroup(
                        title: "Completed",
                        color: Theme.green,
                        tasks: Array(completedTasks.prefix(24)),
                        opacity: 0.62
                    )
                }
            }
        }
    }
}

private struct iOSCompactTaskCollectionStat: View {
    let value: String
    let label: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.13))
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceElevated.opacity(0.36))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
    }
}

private struct iOSCompactTaskCollectionGroup: View {
    let title: String
    let color: Color
    let tasks: [AppTask]
    let opacity: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                iOSTaskSectionHeader(title: title, color: color)
                Spacer()
                Text("\(tasks.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(color.opacity(0.11))
                    .clipShape(Capsule())
            }

            VStack(spacing: 8) {
                ForEach(tasks) { task in
                    iOSTaskRow(task: task)
                        .opacity(opacity)
                }
            }
        }
    }
}
#endif
