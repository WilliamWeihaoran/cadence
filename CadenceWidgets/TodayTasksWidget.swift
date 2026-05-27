import AppIntents
import SwiftData
import SwiftUI
import WidgetKit

struct TodayTasksWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: CadenceTodayWidgetSnapshot
}

struct TodayTasksWidgetProvider: AppIntentTimelineProvider {
    typealias Intent = CadenceTodayWidgetConfigurationIntent
    typealias Entry = TodayTasksWidgetEntry

    func placeholder(in context: TimelineProviderContext) -> TodayTasksWidgetEntry {
        TodayTasksWidgetEntry(
            date: Date(),
            snapshot: placeholderSnapshot(for: context.family)
        )
    }

    func snapshot(
        for configuration: CadenceTodayWidgetConfigurationIntent,
        in context: TimelineProviderContext
    ) async -> TodayTasksWidgetEntry {
        TodayTasksWidgetEntry(
            date: Date(),
            snapshot: currentSnapshot(for: context.family)
        )
    }

    func timeline(
        for configuration: CadenceTodayWidgetConfigurationIntent,
        in context: TimelineProviderContext
    ) async -> Timeline<TodayTasksWidgetEntry> {
        let entry = TodayTasksWidgetEntry(
            date: Date(),
            snapshot: currentSnapshot(for: context.family)
        )
        return Timeline(
            entries: [entry],
            policy: .after(CadenceTodayWidgetSupport.recommendedReloadDate(for: entry.snapshot))
        )
    }

    private func placeholderSnapshot(for family: WidgetFamily) -> CadenceTodayWidgetSnapshot {
        let todayKey = CadenceWidgetDateSupport.dateKey(from: Date())
        let placeholderTasks = [
            CadenceTodayWidgetTask(
                id: UUID(),
                title: "Finish widget pass",
                priorityRaw: TaskPriority.high.rawValue,
                dueDate: todayKey,
                scheduledDate: todayKey,
                containerName: "Cadence"
            ),
            CadenceTodayWidgetTask(
                id: UUID(),
                title: "Plan today timeline",
                priorityRaw: TaskPriority.medium.rawValue,
                dueDate: "",
                scheduledDate: todayKey,
                containerName: "Work"
            ),
            CadenceTodayWidgetTask(
                id: UUID(),
                title: "Clean up inbox",
                priorityRaw: TaskPriority.low.rawValue,
                dueDate: "",
                scheduledDate: todayKey,
                containerName: ""
            ),
            CadenceTodayWidgetTask(
                id: UUID(),
                title: "Review upcoming priorities",
                priorityRaw: TaskPriority.medium.rawValue,
                dueDate: todayKey,
                scheduledDate: "",
                containerName: "Planning"
            ),
            CadenceTodayWidgetTask(
                id: UUID(),
                title: "Prep notes for standup",
                priorityRaw: TaskPriority.none.rawValue,
                dueDate: "",
                scheduledDate: todayKey,
                containerName: "Team"
            ),
            CadenceTodayWidgetTask(
                id: UUID(),
                title: "Refine backlog cuts",
                priorityRaw: TaskPriority.low.rawValue,
                dueDate: "",
                scheduledDate: todayKey,
                containerName: "Roadmap"
            ),
            CadenceTodayWidgetTask(
                id: UUID(),
                title: "Capture follow-up ideas",
                priorityRaw: TaskPriority.none.rawValue,
                dueDate: "",
                scheduledDate: todayKey,
                containerName: "Inbox"
            ),
            CadenceTodayWidgetTask(
                id: UUID(),
                title: "Close remaining loose ends",
                priorityRaw: TaskPriority.medium.rawValue,
                dueDate: "",
                scheduledDate: todayKey,
                containerName: "Ops"
            ),
        ]

        return CadenceTodayWidgetSnapshot(
            date: Date(),
            dateKey: todayKey,
            state: .ready,
            statusMessage: nil,
            totalCount: placeholderTasks.count,
            overdueCount: 1,
            dueTodayCount: 2,
            scheduledTodayCount: 5,
            tasks: Array(placeholderTasks.prefix(snapshotLimit(for: family)))
        )
    }

    private func currentSnapshot(for family: WidgetFamily) -> CadenceTodayWidgetSnapshot {
        do {
            let container = try CadenceStoreSupport.makePrimaryContainer(
                allowsSave: false,
                cloudKitDatabase: .none
            )
            let modelContext = ModelContext(container)
            return try CadenceTodayWidgetSupport.snapshot(
                modelContext: modelContext,
                limit: snapshotLimit(for: family)
            )
        } catch {
            return CadenceTodayWidgetSupport.unavailableSnapshot()
        }
    }

    private func snapshotLimit(for family: WidgetFamily) -> Int {
        switch family {
        case .systemSmall:
            return 1
        case .systemMedium:
            return 3
        case .systemLarge:
            return 6
        case .systemExtraLarge:
            return 8
        default:
            return 3
        }
    }
}

struct CadenceTodayTasksWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: CadenceWidgetRefreshCenter.todayWidgetKind,
            intent: CadenceTodayWidgetConfigurationIntent.self,
            provider: TodayTasksWidgetProvider()
        ) { entry in
            TodayTasksWidgetView(entry: entry)
        }
        .configurationDisplayName("Today Tasks")
        .description("See and complete today's Cadence tasks.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}
