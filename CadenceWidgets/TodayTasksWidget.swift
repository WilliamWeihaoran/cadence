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
        // The widget gallery asks for a snapshot with `isPreview` set, and `placeholder(in:)` is
        // only the redacted loading frame. Answering the gallery from the live store meant a new
        // install advertised this widget as empty and the sample content below was shown to no
        // one (T-7125); the gallery gets the sample, the home screen still gets the store.
        TodayTasksWidgetEntry(
            date: Date(),
            snapshot: context.isPreview
                ? placeholderSnapshot(for: context.family)
                : currentSnapshot(for: context.family)
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
                title: "Book dentist appointment",
                priorityRaw: TaskPriority.high.rawValue,
                dueDate: todayKey,
                scheduledDate: todayKey,
                containerName: "Personal"
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
                title: "Draft weekly update",
                priorityRaw: TaskPriority.low.rawValue,
                dueDate: "",
                scheduledDate: todayKey,
                containerName: "Projects"
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
                title: "Pick up groceries",
                priorityRaw: TaskPriority.medium.rawValue,
                dueDate: "",
                scheduledDate: todayKey,
                containerName: "Errands"
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

    /// **The catch already rendered `.unavailable`; what it did not do was leave a number behind
    /// ([[T-1366]]).** `CadenceWidgetGenerationProbe` is opt-in and inert unless
    /// `CadenceWidgetGenerationLedger.enabledDefaultsKey` is set in the app group, and when it is,
    /// this generation leaves its container-open, fetch and derive durations, the rows the fetch
    /// materialised, the rows this family actually draws, the process footprint, and — separately
    /// from an empty result — the refusal, if the store could not be read.
    private func currentSnapshot(for family: WidgetFamily) -> CadenceTodayWidgetSnapshot {
        let probe = CadenceWidgetGenerationProbe(kind: CadenceWidgetRefreshCenter.todayWidgetKind)
        do {
            let container = try CadenceStoreSupport.makePrimaryContainer(
                allowsSave: false,
                cloudKitDatabase: .none
            )
            probe.finished(.containerOpen)
            let modelContext = ModelContext(container)
            let snapshot = try CadenceTodayWidgetSupport.snapshot(
                modelContext: modelContext,
                limit: snapshotLimit(for: family),
                probe: probe
            )
            probe.recordGeneration(
                outcome: snapshot.state == .empty ? .empty : .ready,
                renderedCount: snapshot.tasks.count,
                sourceSnapshotAt: snapshot.date
            )
            return snapshot
        } catch {
            probe.recordRefusal(error)
            return CadenceTodayWidgetSupport.unavailableSnapshot()
        }
    }

    private func snapshotLimit(for family: WidgetFamily) -> Int {
        family.cadenceLayout.todayTaskLimit
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
        // WidgetKit insets widget content by ~16pt a side unless a configuration opts out, and
        // `TodayTasksWidgetView` already draws `scale.outerPadding` inside that. Both together
        // took 32pt off the height of the 158pt `systemMedium` tile, which is what pushed the
        // `Today` title and its count off the top edge and sliced the last task row in half at the
        // bottom (T-7121). The padding the view already carries IS the margin.
        .contentMarginsDisabled()
    }
}
