#if os(iOS)
import SwiftUI

struct iOSCompactInboxView: View {
    var showsHeader = true
    @Environment(\.dismiss) private var dismiss
    let inboxTasks: [AppTask]
    let completedInboxTasks: [AppTask]
    @Binding var sortMode: CadenceTaskSortMode
    @Binding var showCompleted: Bool
    @Binding var newTitle: String
    @Binding var saveError: String?
    let captureInboxTask: () -> Void

    private var oldestLabel: String {
        guard let oldestTask = inboxTasks.min(by: { $0.createdAt < $1.createdAt }) else {
            return "Clear"
        }
        return DateFormatters.relativeDate(from: DateFormatters.dateKey(from: oldestTask.createdAt))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 11) {
                // No subtitle — see the note on the All Tasks header. No count either: the Active
                // metric below reports it.
                if showsHeader {
                    iOSCompactPageHeader(
                        eyebrow: "Capture",
                        title: "Inbox",
                        systemImage: "tray.fill",
                        color: Theme.blue,
                        onBack: { dismiss() }
                    )
                }

                stats
                captureCard
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

    private var stats: some View {
        HStack(spacing: 10) {
            iOSCompactInboxMetric(
                value: "\(inboxTasks.count)",
                label: "Active",
                systemImage: "tray.full.fill",
                tint: Theme.blue
            )
            Divider()
                .frame(height: 22)
                .overlay(Theme.borderSubtle.opacity(0.6))
            iOSCompactInboxMetric(
                value: "\(completedInboxTasks.count)",
                label: "Done",
                systemImage: "checkmark.circle.fill",
                tint: Theme.green
            )
            Divider()
                .frame(height: 22)
                .overlay(Theme.borderSubtle.opacity(0.6))
            iOSCompactInboxMetric(
                value: oldestLabel,
                label: "Oldest",
                systemImage: "clock.fill",
                tint: Theme.purple
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .cadenceCard(shadowRadius: 10, shadowY: 4)
    }

    private var captureCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            iOSTaskCaptureBar(
                placeholder: "Add an inbox task...",
                title: $newTitle,
                action: captureInboxTask
            )

            if let saveError {
                iOSInlineErrorBanner(message: saveError) {
                    self.saveError = nil
                }
            }

            iOSTaskViewOptionsBar(
                sortMode: $sortMode,
                showCompleted: $showCompleted,
                completedCount: completedInboxTasks.count
            )
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var taskSections: some View {
        if inboxTasks.isEmpty && (!showCompleted || completedInboxTasks.isEmpty) {
            iOSEmptyPanel(
                systemImage: "tray",
                title: "Inbox is clear",
                subtitle: "Capture tasks here before scheduling or filing them."
            )
            .frame(minHeight: 190)
            .cadenceCard()
        } else {
            VStack(alignment: .leading, spacing: 14) {
                if !inboxTasks.isEmpty {
                    iOSCompactInboxTaskGroup(
                        title: "Active",
                        color: Theme.blue,
                        tasks: inboxTasks,
                        opacity: 1
                    )
                }

                if showCompleted && !completedInboxTasks.isEmpty {
                    iOSCompactInboxTaskGroup(
                        title: "Completed",
                        color: Theme.green,
                        tasks: Array(completedInboxTasks.prefix(12)),
                        opacity: 0.62
                    )
                }
            }
            .padding(12)
            .cadenceCard()
        }
    }
}

private struct iOSCompactInboxMetric: View {
    let value: String
    let label: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 14, weight: .bold))
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct iOSCompactInboxTaskGroup: View {
    let title: String
    let color: Color
    let tasks: [AppTask]
    let opacity: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
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

            VStack(spacing: 7) {
                ForEach(tasks) { task in
                    iOSTaskRow(task: task)
                        .opacity(opacity)
                }
            }
        }
    }
}
#endif
