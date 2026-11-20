import AppIntents
import SwiftData
import SwiftUI
import WidgetKit

struct TodayTasksWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: CadenceTodayWidgetSnapshot
}

/// **A `TimelineProvider`, not an `AppIntentTimelineProvider` ([[T-12334]]).** The widget shipped
/// as an `AppIntentConfiguration` over a `WidgetConfigurationIntent` that declared no `@Parameter`
/// -- the template's shape, never used for anything -- so iOS offered `Edit Widget` on every placed
/// tile and opened an editor with nothing in it. There is no setting this widget has a use for
/// (it is "today", by definition, and the Calendar widget beside it is static for the same
/// reason), so the configuration goes rather than inventing one. The `kind` string is unchanged,
/// which is what WidgetKit keys a placed tile on.
struct TodayTasksWidgetProvider: TimelineProvider {
    typealias Entry = TodayTasksWidgetEntry

    func placeholder(in context: TimelineProviderContext) -> TodayTasksWidgetEntry {
        TodayTasksWidgetEntry(
            date: Date(),
            snapshot: placeholderSnapshot(for: context.family)
        )
    }

    func getSnapshot(
        in context: TimelineProviderContext,
        completion: @escaping (TodayTasksWidgetEntry) -> Void
    ) {
        // This process's palette was read once, when it started; re-read it per request so a
        // palette picked while the extension stays alive is drawn on this reload ([[T-18461]]).
        CadenceAccentPaletteSelection.shared.adoptStoredSelection()
        // The widget gallery asks for a snapshot with `isPreview` set, and `placeholder(in:)` is
        // only the redacted loading frame. Answering the gallery from the live store meant a new
        // install advertised this widget as empty and the sample content below was shown to no
        // one (T-7125); the gallery gets the sample, the home screen still gets the store.
        completion(TodayTasksWidgetEntry(
            date: Date(),
            snapshot: context.isPreview
                ? placeholderSnapshot(for: context.family)
                : currentSnapshot(for: context.family)
        ))
    }

    func getTimeline(
        in context: TimelineProviderContext,
        completion: @escaping (Timeline<TodayTasksWidgetEntry>) -> Void
    ) {
        CadenceAccentPaletteSelection.shared.adoptStoredSelection()  // [[T-18461]], as in getSnapshot
        // [[T-18582]]: today's entry, then the next day's at its start, so the day turns on time
        // even when WidgetKit defers the reload below.
        let entries = currentDaySnapshots(for: context.family, now: Date()).map {
            TodayTasksWidgetEntry(date: $0.date, snapshot: $0.snapshot)
        }
        completion(Timeline(
            entries: entries,
            policy: .after(CadenceTodayWidgetSupport.recommendedReloadDate(for: entries[0].snapshot))
        ))
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

        // The counts and the row order come from the rows ([[T-15442]]); they were typed as
        // 1 / 2 / 5 beside rows that are 0 / 2 / 6.
        return CadenceTodayWidgetSupport.sampleSnapshot(
            rows: placeholderTasks,
            todayKey: todayKey,
            limit: snapshotLimit(for: family)
        )
    }

    /// **The catch already rendered `.unavailable`; what it did not do was leave a number behind
    /// ([[T-1366]]).** `CadenceWidgetGenerationProbe` is opt-in and inert unless
    /// `CadenceWidgetGenerationLedger.enabledDefaultsKey` is set in the app group, and when it is,
    /// this generation leaves its container-open, fetch and derive durations, the rows the fetch
    /// materialised, the rows this family actually draws, the process footprint, and — separately
    /// from an empty result — the refusal, if the store could not be read. Never empty: the first
    /// entry is today's (or the unavailable one), and a second, for the next day, follows it when
    /// the store was read ([[T-18582]]).
    private func currentDaySnapshots(
        for family: WidgetFamily,
        now: Date
    ) -> [(date: Date, snapshot: CadenceTodayWidgetSnapshot)] {
        let probe = CadenceWidgetGenerationProbe(kind: CadenceWidgetRefreshCenter.todayWidgetKind)
        do {
            let container = try CadenceStoreSupport.makePrimaryContainer(
                allowsSave: false,
                cloudKitDatabase: .none
            )
            probe.finished(.containerOpen)
            let modelContext = ModelContext(container)
            let days = try CadenceTodayWidgetSupport.daySnapshots(
                modelContext: modelContext,
                limit: snapshotLimit(for: family),
                now: now,
                probe: probe
            )
            let snapshot = days[0].snapshot
            probe.recordGeneration(
                outcome: snapshot.state == .empty ? .empty : .ready,
                renderedCount: snapshot.tasks.count,
                sourceSnapshotAt: snapshot.date
            )
            return days
        } catch {
            probe.recordRefusal(error)
            // [[T-12335]]: the family decides the sentence, because `systemSmall` has one line
            // for it and the full one stopped mid-word there.
            return [(
                date: now,
                snapshot: CadenceTodayWidgetSupport.unavailableSnapshot(
                    message: CadenceTodayWidgetSupport.unavailableMessage(for: family.cadenceLayout)
                )
            )]
        }
    }

    /// The snapshot `getSnapshot` answers with: the first, today's, of `currentDaySnapshots`.
    private func currentSnapshot(for family: WidgetFamily) -> CadenceTodayWidgetSnapshot {
        currentDaySnapshots(for: family, now: Date())[0].snapshot
    }

    private func snapshotLimit(for family: WidgetFamily) -> Int {
        family.cadenceLayout.todayTaskLimit
    }
}

struct CadenceTodayTasksWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: CadenceWidgetRefreshCenter.todayWidgetKind,
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
