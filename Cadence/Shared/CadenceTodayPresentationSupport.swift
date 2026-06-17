import SwiftUI

struct CadenceTodaySummaryMetric: Identifiable {
    let id: String
    let value: Int
    let label: String
    let systemImage: String
    let tint: Color
}

struct CadenceTodaySummary: Hashable {
    let activeCount: Int
    let timedCount: Int
    let completedCount: Int

    var metrics: [CadenceTodaySummaryMetric] {
        [
            CadenceTodaySummaryMetric(
                id: "active",
                value: activeCount,
                label: "Active",
                systemImage: "checklist",
                tint: Theme.blue
            ),
            CadenceTodaySummaryMetric(
                id: "timed",
                value: timedCount,
                label: "Timed",
                systemImage: "clock.fill",
                tint: Theme.purple
            ),
            CadenceTodaySummaryMetric(
                id: "done",
                value: completedCount,
                label: "Done",
                systemImage: "checkmark.circle.fill",
                tint: Theme.green
            )
        ]
    }
}

enum CadenceTodayPresentationSupport {
    static func summary(
        activeTasks: [AppTask],
        timedTasks: [AppTask],
        completedTasks: [AppTask]
    ) -> CadenceTodaySummary {
        CadenceTodaySummary(
            activeCount: activeTasks.count,
            timedCount: timedTasks.count,
            completedCount: completedTasks.count
        )
    }

    static func accent(for groupKind: CadenceTodayTaskGroupKind) -> Color {
        switch groupKind {
        case .overdue:
            return Theme.red
        case .dueToday:
            return Theme.amber
        case .plannedToday:
            return Theme.blue
        }
    }

    static func symbol(for groupKind: CadenceTodayTaskGroupKind) -> String {
        switch groupKind {
        case .overdue:
            return "exclamationmark.triangle.fill"
        case .dueToday:
            return "flag.fill"
        case .plannedToday:
            return "sun.max.fill"
        }
    }

    static let emptyTitle = "Nothing planned for today"
    static let emptyCompactTitle = "Nothing planned"
    static let emptySubtitle = "Add a task above or schedule one from Inbox."
    static let emptyReviewSubtitle = "Add a task above, schedule one from Inbox, or seed review tasks to check the layout."
}
