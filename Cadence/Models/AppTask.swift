import SwiftData
import Foundation

nonisolated enum TaskSectionDefaults {
    static let defaultName = "Default"
    static let defaultColorHex = "#6b7a99"
}

nonisolated struct TaskSectionConfig: Codable, Hashable, Identifiable {
    var uuid: UUID = UUID()
    var name: String
    var colorHex: String = TaskSectionDefaults.defaultColorHex
    var dueDate: String = ""
    var isCompleted: Bool = false
    var isArchived: Bool = false

    var id: UUID { uuid }

    var isDefault: Bool {
        name.caseInsensitiveCompare(TaskSectionDefaults.defaultName) == .orderedSame
    }

    /// Whether this column can carry `isCompleted` / `isArchived` at all. `false` for Default, and
    /// that is a model invariant rather than a policy choice.
    ///
    /// `Area.normalizedSectionConfigs` / `Project.normalizedSectionConfigs` force both flags false
    /// on the Default column on every read *and* every write, because Default is not a column the
    /// user made: the normalizer *synthesises* it when it is absent, `AppTask.resolvedSectionName`
    /// sends every task with no section name into it, and `sectionNames` hides archived columns —
    /// so a completed-or-archived Default would be an invisible bucket that still collects every
    /// new task in the list. The flags are refused rather than stored for that reason.
    ///
    /// **Read this before putting a wind-down control on a column.** Offering one on Default does
    /// not produce a no-op: the settle that runs beside the flag
    /// (`TaskContainerLifecycleService.completeRemainingActiveTasks` /
    /// `cancelRemainingActiveTasks`) still marks every open task in the column done or cancelled,
    /// and only the flag is discarded — so the action appears to work, the cards disappear, and
    /// the column re-renders Active (`docs/TODO.md` T-268). iOS's
    /// `iOSListEditorSheet.lifecycle(for:)` states the same rule about the same column.
    var supportsLifecycle: Bool { !isDefault }

    private enum CodingKeys: String, CodingKey {
        case uuid
        case name
        case colorHex
        case dueDate
        case isCompleted
        case isArchived
    }

    init(
        uuid: UUID = UUID(),
        name: String,
        colorHex: String = TaskSectionDefaults.defaultColorHex,
        dueDate: String = "",
        isCompleted: Bool = false,
        isArchived: Bool = false
    ) {
        self.uuid = uuid
        self.name = name
        self.colorHex = colorHex
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.isArchived = isArchived
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uuid = try container.decodeIfPresent(UUID.self, forKey: .uuid) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex) ?? TaskSectionDefaults.defaultColorHex
        dueDate = try container.decodeIfPresent(String.self, forKey: .dueDate) ?? ""
        isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
    }
}

/// Reading a list's stored column blob **without letting one unreadable column destroy the rest**
/// (T-475).
///
/// `Area.sectionConfigsRaw` / `Project.sectionConfigsRaw` hold the whole column array as one JSON
/// string, and the `sectionConfigs` getter used to read it with a single
/// `try? JSONDecoder().decode([TaskSectionConfig].self, …)`. `Array`'s synthesized decoding is
/// all-or-nothing: one element the current build cannot read throws, the `try?` swallows it, and
/// the getter falls through to `sectionNamesRaw` — which stores **names only**. Every column's
/// `uuid`, `colorHex`, `dueDate`, `isCompleted` and `isArchived` is gone from the value the app
/// then renders, and because the setter rewrites `sectionConfigsRaw` from whatever it is handed,
/// the next save writes that degraded list back over the good blob and the loss is permanent.
///
/// The decoder above already applies `decodeIfPresent(…) ?? <default>` per field, so a *field*
/// added later cannot cause this. What can is anything the decoder is entitled to reject — a
/// column with no `name`, a `null` or a number where an object belongs, a value of the wrong JSON
/// type — plus whatever a future build writes that this one has no rule for. Those are element
/// failures, and this reads them element by element so they cost one column instead of all of them.
///
/// The three outcomes are distinguished rather than collapsed because the name list is only safe
/// to consult in two of them:
///
/// - `.clean` — the blob decoded whole. `sectionNamesRaw` is a *mirror* the setter rewrites on
///   every save, so it can add nothing here, and consulting it would let a stale mirror
///   (two devices, one CloudKit merge) resurrect a column the user deleted.
/// - `.salvaged` — some columns were read and some were not. The mirror is the only surviving
///   record of the unreadable ones, so their names are recovered from it and everything the
///   readable columns carry is kept.
/// - `.empty` — nothing to read at all: no blob, or a blob that is not a JSON array. The legacy
///   name list is the whole answer, which is what a pre-config list has always done.
nonisolated extension TaskSectionConfig {
    enum StoredList {
        /// Decoded whole. An explicitly stored empty array is `.clean([])`, **not** `.empty`: a
        /// list whose columns were all deleted is not a list that never had any, and reading it as
        /// the latter would re-import the legacy name list the setter left behind.
        case clean([TaskSectionConfig])
        /// At least one element was unreadable. The payload is the columns that were readable, in
        /// stored order.
        case salvaged([TaskSectionConfig])
        /// No stored array at all.
        case empty
    }

    static func storedList(fromRaw raw: String) -> StoredList {
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let data = raw.data(using: .utf8) else {
            return .empty
        }
        let decoder = JSONDecoder()
        if let decoded = try? decoder.decode([TaskSectionConfig].self, from: data) {
            return .clean(decoded)
        }
        guard let elements = try? decoder.decode([SalvagedSectionConfig].self, from: data) else {
            return .empty
        }
        return .salvaged(elements.compactMap(\.config))
    }

    /// The pre-config `sectionNamesRaw` list, as configs, minus any name `known` already accounts
    /// for. Matched case-insensitively, because section matching is case-insensitive everywhere
    /// else.
    static func legacyConfigs(fromRaw raw: String, excluding known: [TaskSectionConfig]) -> [TaskSectionConfig] {
        let taken = Set(known.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        return raw
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !taken.contains($0.lowercased()) }
            .map { TaskSectionConfig(name: $0) }
    }
}

/// One array element, decoded to `nil` rather than to a throw. `JSONDecoder`'s unkeyed container
/// advances past an element whose decoding failed, so the remaining columns are still read.
///
/// **`nonisolated` here is deliberate but, unlike T-445's, *not* load-bearing — measured both
/// ways rather than assumed.** Dropping it and rebuilding gives zero warnings and zero errors on
/// all three schemes that compile this file: `Cadence`, `CadenceWidgets`, and `CadenceMCPServer`,
/// which is on the Swift 6 language mode and would turn a real isolation mistake into an error.
/// Each of those builds recompiled this file, so the counts are not vacuous.
///
/// That is the opposite of `DataIntegrityRepairReport` and `NoteMigrationReport`, where the same
/// word *is* required, and the difference is **where the conformance is declared**. Those two add
/// `Decodable` in an `extension`, so under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` the witness
/// is main-actor isolated while the conformance is not — the crossing the compiler complains
/// about. This one declares the conformance on the type itself, so the type's isolation and its
/// witness's agree and there is nothing to cross.
///
/// It stays because `Models/` is read off the main actor by both extension targets and every other
/// value type in this file is marked the same way — not because the build would break without it.
/// Do not copy T-445's rationale onto a conformance of this shape without re-measuring it.
private nonisolated struct SalvagedSectionConfig: Decodable {
    let config: TaskSectionConfig?

    init(from decoder: Decoder) throws {
        config = try? TaskSectionConfig(from: decoder)
    }
}

/// The four ways a task's dates can make it **today's** work, in the order Today sorts them.
///
/// **This lives in `Models/` for a build reason, not a taxonomy one.** `Cadence/Shared/` — where
/// `CadenceTaskQuerySupport` draws the app's Today — is *not* compiled into `CadenceWidgets`;
/// `Cadence/Models/` is, in that target's explicit source list, alongside `TaskOrdering` which is
/// here for exactly the same reason. So a Today rule that the widget must obey cannot sit beside
/// the app's Today query, and while it had no home both targets kept their own (T-353). This is
/// that home: `AppTask.todayStanding(todayKey:)` is the definition, `CadenceTaskQuerySupport` and
/// `CadenceTodayWidgetSupport` are callers.
///
/// The raw values are the sort key. They are **not** the order the cases are decided in — see
/// `AppTask.todayStanding(todayKey:)` — and nothing persists them, so they are free to change
/// together with that sort.
nonisolated enum CadenceTodayStanding: Int, CaseIterable, Hashable {
    /// A deadline already missed.
    case pastDue = 0
    /// Planned for an earlier day and never finished — still today's work, and the case the
    /// widget's copy of this rule never had.
    case pastDo = 1
    case dueToday = 2
    case doToday = 3

    /// The rank of a task today has no claim on: one past the last real standing, so
    /// `rank < notTodayRank` is the membership test in `Int` form.
    nonisolated static let notTodayRank = 4
}

/// A concrete action item. Lives inside an Area, Project, Milestone, or as an inbox item.
@Model final class AppTask {
    var id: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    var priorityRaw: String = "none"
    var statusRaw: String = "todo"

    var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw) ?? .none }
        set { priorityRaw = newValue.rawValue }
    }
    var status: TaskStatus {
        get { TaskStatus(rawValue: statusRaw) ?? .todo }
        set { statusRaw = newValue.rawValue }
    }
    var recurrenceRule: TaskRecurrenceRule {
        get { TaskRecurrenceRule(rawValue: recurrenceRaw) ?? .none }
        set { recurrenceRaw = newValue.rawValue }
    }
    var recurrenceEndMode: TaskRecurrenceEndMode {
        get { TaskRecurrenceEndMode(rawValue: recurrenceEndModeRaw) ?? .never }
        set { recurrenceEndModeRaw = newValue.rawValue }
    }
    var dueDate: String = ""            // YYYY-MM-DD or ""
    var scheduledDate: String = ""      // YYYY-MM-DD — the day this is time-blocked
    var scheduledStartMin: Int = -1     // minutes from midnight (-1 = not scheduled)
    var estimatedMinutes: Int = 30
    var actualMinutes: Int = 0          // cumulative actual time logged
    /// EKEvent identifier for a task attached to a calendar event.
    ///
    /// **Nothing writes this a non-empty value.** Every write site clears it, and no attach UI
    /// exists on either platform — the feature is gone, whatever it once was. Do not delete the
    /// property or its readers: values written by an earlier build may still be on disk or in
    /// CloudKit, and the readers exist to handle exactly those (clearing stale identifiers in
    /// `CalendarLinkedTaskSupport`, deleting a linked event with its task in `TaskDeleteHelpers`,
    /// repairing relationships in `DataIntegrityRepairService`). There is no `SchemaMigrationPlan`,
    /// so dropping a stored property drops data rather than tidying anything.
    var calendarEventID: String = ""
    var recurrenceRaw: String = TaskRecurrenceRule.none.rawValue
    var recurrenceSpawnedTaskIDRaw: String = ""
    var recurrenceSeriesIDRaw: String = ""
    var recurrenceSourceTaskIDRaw: String = ""
    var recurrenceOccurrenceIndex: Int = 0
    // Series end condition. Every attribute is defaulted so lightweight migration can add them
    // without a SchemaMigrationPlan, and existing rows read back as ".never" (repeat forever).
    var recurrenceEndModeRaw: String = TaskRecurrenceEndMode.never.rawValue
    var recurrenceEndDate: String = ""  // YYYY-MM-DD or "" — only meaningful when mode is .onDate
    var recurrenceEndCount: Int = 0     // total occurrences allowed — only meaningful when mode is .afterCount
    var sectionName: String = TaskSectionDefaults.defaultName
    var order: Int = 0
    var createdAt: Date = Date()
    var completedAt: Date? = nil

    var area: Area? = nil
    var project: Project? = nil
    var goal: Goal? = nil
    var context: Context? = nil         // denormalized for efficient queries
    var bundle: TaskBundle? = nil
    var bundleOrder: Int = 0
    var subtasks: [Subtask]? = nil
    var tags: [Tag]? = nil
    /// Every increment this task's `actualMinutes` has taken since the ledger landed.
    ///
    /// `.nullify`, not `.cascade`: deleting a task has never decremented its list's
    /// `loggedMinutes`, and a cascade here would start doing exactly that the next time
    /// `CadenceFocusLedger.reconcile(in:)` ran. See `FocusSessionLog`.
    @Relationship(deleteRule: .nullify, inverse: \FocusSessionLog.task)
    var focusSessions: [FocusSessionLog]? = nil

    // MARK: - Computed

    var isDone: Bool { status == .done }
    var isCancelled: Bool { status == .cancelled }
    var isRecurring: Bool { recurrenceRule != .none }

    var recurrenceSpawnedTaskID: UUID? {
        get { UUID(uuidString: recurrenceSpawnedTaskIDRaw) }
        set { recurrenceSpawnedTaskIDRaw = newValue?.uuidString ?? "" }
    }

    var recurrenceSeriesID: UUID {
        UUID(uuidString: recurrenceSeriesIDRaw) ?? id
    }

    var recurrenceSourceTaskID: UUID? {
        get { UUID(uuidString: recurrenceSourceTaskIDRaw) }
        set { recurrenceSourceTaskIDRaw = newValue?.uuidString ?? "" }
    }

    var isRecurrenceSeriesMember: Bool {
        isRecurring || !recurrenceSeriesIDRaw.isEmpty || !recurrenceSourceTaskIDRaw.isEmpty
    }

    // MARK: - Recurrence end condition
    //
    // `recurrenceOccurrenceIndex` is 0-BASED: the first task of a series is index 0, the task it
    // spawns is index 1, and so on. So the number of occurrences that have existed up to and
    // including this one is `index + 1` — that's what an "after N occurrences" limit counts.

    /// 1-based position of this occurrence in its series (the first task is occurrence 1).
    var recurrenceOccurrenceNumber: Int { max(0, recurrenceOccurrenceIndex) + 1 }

    /// The end mode that actually applies, after discarding configurations that can't be honored:
    /// a task that doesn't recur at all, an `.onDate` with no end date, or an `.afterCount` with a
    /// non-positive count. Those all degrade to `.never` rather than silently killing a series.
    var effectiveRecurrenceEndMode: TaskRecurrenceEndMode {
        guard isRecurring else { return .never }
        switch recurrenceEndMode {
        case .never:
            return .never
        case .onDate:
            return recurrenceEndDate.isEmpty ? .never : .onDate
        case .afterCount:
            return recurrenceEndCount >= 1 ? .afterCount : .never
        }
    }

    /// True when the series can definitively produce nothing further from this occurrence *without*
    /// needing to know what the next occurrence's date would be — i.e. the "after N occurrences"
    /// budget is used up. Date-limited series depend on the successor's date, so ask
    /// `recurrenceAllowsNextOccurrence(on:)` for those.
    var recurrenceHasEnded: Bool {
        effectiveRecurrenceEndMode == .afterCount && recurrenceOccurrenceNumber >= recurrenceEndCount
    }

    /// Whether a successor landing on `nextDateKey` ("yyyy-MM-dd") is still inside the series' end
    /// condition. `nil`/empty means the successor carries no date at all, which no date limit can
    /// exclude. Date keys are fixed-width `yyyy-MM-dd`, so lexicographic compare == chronological.
    func recurrenceAllowsNextOccurrence(on nextDateKey: String?) -> Bool {
        switch effectiveRecurrenceEndMode {
        case .never:
            return true
        case .afterCount:
            return recurrenceOccurrenceNumber < recurrenceEndCount
        case .onDate:
            guard let nextDateKey, !nextDateKey.isEmpty else { return true }
            return nextDateKey <= recurrenceEndDate
        }
    }

    /// The full stop condition the spawn engine asks about: this task recurs, hasn't already
    /// spawned its successor, and the end condition still permits one dated `nextDateKey`.
    func shouldSpawnNextOccurrence(nextDateKey: String?) -> Bool {
        isRecurring
            && recurrenceSpawnedTaskID == nil
            && recurrenceAllowsNextOccurrence(on: nextDateKey)
    }

    /// A task with no estimate is treated as this long wherever it occupies time. Same value the
    /// stored `estimatedMinutes` defaults to, so "no estimate" and "the default estimate" draw and
    /// read identically.
    nonisolated static let defaultTimelineDurationMinutes = 30

    /// The shortest block a task can occupy. Every write path already clamps to this
    /// (`SchedulingActions`, `TaskCreationService`, `CadenceTaskMutationSupport`); the read path
    /// has to agree, because the card editors let an estimate be typed down to 0.
    nonisolated static let minimumTimelineDurationMinutes = 5

    /// How long this task's time block is, in minutes. The one answer, for every renderer, layout
    /// pass, label and exporter.
    ///
    /// There were six of these and they disagreed, so a zero-estimate task was drawn 60 minutes
    /// tall, columned against its neighbours as 30 minutes (and could therefore visually overlap a
    /// block it had been laid out beside), labelled itself "9:00 – 9:05", previewed at 30 while
    /// being dragged, and exported as 30.
    ///
    /// The rule is *not* `max(estimatedMinutes, 30)` — the spelling `scheduledEndMin` used to
    /// carry. That floor cannot tell "no estimate" from "a deliberate short estimate", so it also
    /// rounded a real 10-minute task up to half an hour, contradicting the block drawn for it, the
    /// label inside that block, and the overlap solver. Zero is the only value that means "unset";
    /// anything positive is the user's answer and is kept, down to the 5-minute floor every write
    /// path already enforces.
    ///
    /// `nonisolated` for the same reason as `TaskPriority.rank` — `Models/` compiles into the
    /// widget extension, whose timeline providers run off the main actor.
    nonisolated var timelineDurationMinutes: Int {
        guard estimatedMinutes > 0 else { return AppTask.defaultTimelineDurationMinutes }
        return max(estimatedMinutes, AppTask.minimumTimelineDurationMinutes)
    }

    /// End time in minutes from midnight, or `-1` for an unscheduled task.
    var scheduledEndMin: Int {
        guard scheduledStartMin >= 0 else { return -1 }
        return scheduledStartMin + timelineDurationMinutes
    }

    var containerName: String {
        area?.name ?? project?.name ?? ""
    }

    var containerColor: String {
        area?.colorHex ?? project?.colorHex ?? "#6b7a99"
    }

    var resolvedSectionName: String {
        let trimmed = sectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? TaskSectionDefaults.defaultName : trimmed
    }

    /// Whether this task lives somewhere the user can currently navigate to.
    ///
    /// Completed and archived lists are hidden from the sidebar, All Tasks, the kanban boards and
    /// every container picker, so a task inside one is real but unreachable. An inbox task — no
    /// area, no project — is always reachable.
    ///
    /// This existed as four independent copies of the same six lines (`SidebarView`,
    /// `TasksListView`, `KanbanBoardSupport`, and the goal resolver's Next Action filter). They
    /// agreed, which is exactly the state that precedes drift — every bug found this session came
    /// from one idea implemented more than once. `ProjectStatus` has five cases and `AreaStatus`
    /// three, so "which of them count as visible" is a real decision, made once, here.
    var isInActiveContainer: Bool {
        if let project { return project.isActive }
        if let area { return area.isActive }
        return true
    }

    /// Whether a `yyyy-MM-dd` deadline has already passed, measured against `todayKey`. Date keys
    /// are fixed-width, so a lexicographic compare is a chronological one. An empty key is never
    /// overdue: no deadline cannot be a missed one.
    ///
    /// Deliberately *not* the whole answer for a task — see `isOverdue(todayKey:)`. This spelling
    /// exists for the surfaces that only hold a due-date string (`CadenceDueUrgency`, which takes
    /// `isDone` as its own parameter, and the focus rows, which filter finished tasks out first).
    nonisolated static func isDueDateOverdue(_ dueDateKey: String, todayKey: String) -> Bool {
        !dueDateKey.isEmpty && dueDateKey < todayKey
    }

    /// The one "is this task overdue" predicate.
    ///
    /// This existed six times, and three of the copies left out the `isDone` half, so whether a
    /// finished task with a past due date rendered red depended on which view you were looking at.
    /// A completed task is not overdue — you did it — so the guard belongs *inside* the predicate
    /// rather than in a `&& !task.isDone` every call site has to remember.
    ///
    /// Cancelled tasks are deliberately still eligible: `isCancelled` is a separate status from
    /// `isDone`, and no copy of this predicate has ever excluded it.
    ///
    /// `nonisolated` for the same reason as `TaskPriority.rank` — widget timeline providers run
    /// off the main actor and this module defaults to `MainActor` isolation. `todayKey` is passed
    /// in rather than defaulted for the same reason: `DateFormatters.todayKey()` is main-actor
    /// isolated, and a caller that already knows "today" should not recompute it per row.
    nonisolated func isOverdue(todayKey: String) -> Bool {
        statusRaw != TaskStatus.done.rawValue && AppTask.isDueDateOverdue(dueDate, todayKey: todayKey)
    }

    /// Where this task's dates place it in **today's** work, or `nil` when today has no claim on
    /// it. See `CadenceTodayStanding` for why the rule lives in `Models/`.
    ///
    /// Dates only: a settled task still has a standing, because `CadenceTaskQuerySupport.todayRank`
    /// has always ranked one and macOS's Today sort calls that. Membership — which *does* exclude
    /// settled work — is `isTodayWork(todayKey:)`.
    ///
    /// **A due date outranks a do date**, so `.dueToday` is decided before `.pastDo` and a task
    /// due today and planned for yesterday reads as due-today. That is the order `todayGroups` and
    /// `dateBuckets` already had, and the one macOS's deleted local rank got backwards.
    nonisolated func todayStanding(todayKey: String) -> CadenceTodayStanding? {
        if !dueDate.isEmpty && dueDate < todayKey { return .pastDue }
        if dueDate == todayKey { return .dueToday }
        if !scheduledDate.isEmpty && scheduledDate < todayKey { return .pastDo }
        if scheduledDate == todayKey { return .doToday }
        return nil
    }

    /// **The one membership test for Today**, on every surface that draws the day.
    ///
    /// Unfinished, and dated into today by any of the four standings — including `.pastDo`, work
    /// planned for an earlier day and never done, which is still today's work. That case is the
    /// whole of T-353: the widget kept a second, narrower spelling of this rule with no past-do
    /// branch, so a task planned for yesterday with no due date sat on the app's Today page and
    /// was missing from the Today widget *and* from the Calendar widget's "Next up", which reads
    /// the same picker.
    nonisolated func isTodayWork(todayKey: String) -> Bool {
        statusRaw != TaskStatus.done.rawValue &&
            statusRaw != TaskStatus.cancelled.rawValue &&
            todayStanding(todayKey: todayKey) != nil
    }

    /// `todayStanding`'s sort key, with `CadenceTodayStanding.notTodayRank` for a task today has no
    /// claim on. The `Int` spelling is what `CadenceTaskQuerySupport.todayRank` and macOS's
    /// `TasksPanel` compare; both now come through here.
    nonisolated func todayRank(todayKey: String) -> Int {
        todayStanding(todayKey: todayKey)?.rawValue ?? CadenceTodayStanding.notTodayRank
    }

    var hidesEmptyDueDateInList: Bool {
        if let project {
            return project.hideDueDateIfEmpty
        }
        if let area {
            return area.hideDueDateIfEmpty
        }
        return false
    }

    var shouldShowDueDateField: Bool {
        !dueDate.isEmpty || !hidesEmptyDueDateInList
    }

    var sortedTags: [Tag] {
        TagSupport.sorted(tags ?? [])
    }

    init(title: String) {
        self.title = title
    }
}

/// A scheduled container for small tasks that should share one calendar block.
@Model final class TaskBundle {
    var id: UUID = UUID()
    var title: String = ""
    var dateKey: String = ""
    var startMin: Int = 0
    var durationMinutes: Int = 30
    var createdAt: Date = Date()
    @Relationship(deleteRule: .nullify, inverse: \AppTask.bundle)
    var tasks: [AppTask]? = nil

    /// What an untitled block is called, and it is the word the rest of the app already uses:
    /// "Block title", "Edit Block", "Delete Block", "No tasks in this block" (T-567). The literal
    /// it replaces was "Task Bundle" — the *type's* name, which no user-facing string anywhere in
    /// Cadence says — re-typed at nine call sites across both platforms, three of which stored it
    /// rather than merely drawing it. One constant, so the noun cannot drift back apart.
    static let defaultDisplayTitle = "Block"

    /// What to store for a user-entered block title: trimmed, and never blank.
    ///
    /// The stored/display split `CadenceEventTitleSupport` already draws. `displayTitle` below is
    /// for a block already in the store, whose title may be blank because an older build wrote it
    /// that way; this is for the string a create form is about to save.
    static func storedTitle(_ raw: String) -> String {
        CadenceTitleNormalization.display(raw, fallback: defaultDisplayTitle)
    }

    var displayTitle: String {
        CadenceTitleNormalization.display(title, fallback: Self.defaultDisplayTitle)
    }

    var endMin: Int {
        startMin + max(durationMinutes, 5)
    }

    var sortedTasks: [AppTask] {
        (tasks ?? [])
            .filter { !$0.isCancelled && $0.bundle?.id == id }
            .sorted {
                if $0.bundleOrder != $1.bundleOrder {
                    return $0.bundleOrder < $1.bundleOrder
                }
                return $0.createdAt < $1.createdAt
            }
    }

    var activeTasks: [AppTask] {
        sortedTasks.filter { !$0.isDone }
    }

    var isCompleted: Bool {
        !sortedTasks.isEmpty && activeTasks.isEmpty
    }

    var totalEstimatedMinutes: Int {
        sortedTasks.reduce(0) { $0 + max($1.estimatedMinutes, 5) }
    }

    init(title: String, dateKey: String, startMin: Int, durationMinutes: Int) {
        self.title = title
        self.dateKey = dateKey
        self.startMin = startMin
        self.durationMinutes = max(durationMinutes, 5)
    }
}

/// One increment to a focus-time counter, recorded as its own row.
///
/// **Why the row exists.** `AppTask.actualMinutes`, `Area.loggedMinutes` and
/// `Project.loggedMinutes` are CloudKit-synced scalars written with `+=`. Two devices that each
/// bank a session read the same starting value, each write their own sum, and the record that
/// arrives second wins — so one of the two sessions is gone. Not merely a wrong stat:
/// `GoalContributionResolver.summary(for:)` folds `actualMinutes` into an hours-mode goal's
/// progress, so a dropped session is wrong goal progress. The repo already met the same shape one
/// level up — `DataIntegrityRepairService` reconciles two duplicate lists' `loggedMinutes` with
/// `max`, not `sum`, because a sum there would double-count — which is the tell that a counter is
/// the wrong carrier for something that happens on more than one device. A row per increment
/// cannot be clobbered that way: CloudKit merges *rows*, and two devices that each insert one end
/// up holding both.
///
/// **The counters stay, and that is deliberate.** Around twenty surfaces read them — duration
/// labels on task rows, timeline blocks, markdown task embeds, the inspector, the export archive,
/// the MCP task detail, goal progress — and they are what updates the instant a session is banked,
/// before any sync. So the write sites still do the `+=`; the row is recorded beside it, and the
/// rows are what turn a clobbered counter back into a correct one — `CadenceFocusLedger.bank`
/// corrects the subject it is about to write to, and `CadenceFocusLedger.reconcile(in:)` corrects
/// a whole store. Making the ledger the only reader would mean rewriting every one of those
/// surfaces in the same change, and a surface missed would show a user their logged time
/// vanishing — strictly worse than the defect being fixed.
///
/// **`previousMinutes` is the field that makes reconciliation possible.** It is the counter's value
/// immediately before this increment, on the device that wrote it. The ledger starts life with no
/// idea what the counter already held — there is no `SchemaMigrationPlan` in this project and no
/// migration hook to hang a one-time backfill on — but the *minimum* `previousMinutes` across a
/// subject's rows is exactly the counter's value at the moment the very first row was written,
/// which is that legacy total. Each device's own `previousMinutes` only ever climbs from there, so
/// the minimum is stable no matter how many devices, in what order, wrote rows.
///
/// **Exactly one of `task` / `area` / `project` is set.** A session against a task inside a project
/// moves two counters, so it writes two rows; the two counters reconcile independently.
@Model final class FocusSessionLog {
    var id: UUID = UUID()
    /// Minutes added to the subject's counter by this increment. Always positive.
    var minutes: Int = 0
    /// The subject's counter immediately before this increment, on the writing device.
    var previousMinutes: Int = 0
    var loggedAt: Date = Date()
    /// `yyyy-MM-dd` for `loggedAt`, so a per-day rollup is a string compare like every other
    /// day-scoped query in the app rather than date math over every row.
    var dayKey: String = ""

    var task: AppTask? = nil
    var area: Area? = nil
    var project: Project? = nil

    init(minutes: Int, previousMinutes: Int, loggedAt: Date, dayKey: String) {
        self.minutes = minutes
        self.previousMinutes = previousMinutes
        self.loggedAt = loggedAt
        self.dayKey = dayKey
    }
}

/// The one place focus minutes are banked, and the one place they are reconciled.
///
/// `nonisolated` for the reason `TaskOrdering` is: `Cadence/Models/` compiles straight into
/// `CadenceWidgets` and into `CadenceMCPServer`, which is on Swift 6 where main-actor inference
/// on a shared helper is an error rather than a warning.
nonisolated enum CadenceFocusLedger {
    /// Bank `minutes` against a task **and the list that owns it** — the three counters a focus
    /// session moves, in one spelling.
    ///
    /// **The context is a parameter, not `task.modelContext`, and that is the rule rather than a
    /// preference** (`AGENTS.md`, "The `try? save()` rule", half 3). Banking a session now *inserts*
    /// — it used to be nothing but field edits — so it is a pending change, and a declaration that
    /// reaches for an ambient context to insert into has to commit. Taking the context says the
    /// caller owns the unit of work, which is true here: every focus path already commits after
    /// banking. `CadenceSaveCommitDisciplineTests` caught the first spelling of this, which read
    /// `task.modelContext` and committed nothing on the macOS timer's path.
    ///
    /// The project-before-area precedence is the one the three former increment sites already had
    /// (`CadenceFocusSupport.logElapsedSeconds(_:to:)`, `CadenceFocusSupport.distributeMinutes`,
    /// `FocusSessionSupport.logSession`): a task in a project rolls up to the project only, because
    /// the project rolls up to the area itself.
    static func bank(
        _ minutes: Int,
        forTaskAndItsList task: AppTask,
        in modelContext: ModelContext,
        now: Date = Date()
    ) {
        guard minutes > 0 else { return }
        bank(minutes, to: task, in: modelContext, now: now)
        if let project = task.project {
            bank(minutes, to: project, in: modelContext, now: now)
        } else if let area = task.area {
            bank(minutes, to: area, in: modelContext, now: now)
        }
    }

    static func bank(_ minutes: Int, to task: AppTask, in modelContext: ModelContext, now: Date = Date()) {
        guard minutes > 0 else { return }
        task.actualMinutes = raised(task.actualMinutes, by: task.focusSessions)
        let previous = task.actualMinutes
        task.actualMinutes = previous + minutes
        let row = row(minutes: minutes, previousMinutes: previous, now: now)
        modelContext.insert(row)
        row.task = task
        task.focusSessions = (task.focusSessions ?? []) + [row]
    }

    static func bank(_ minutes: Int, to area: Area, in modelContext: ModelContext, now: Date = Date()) {
        guard minutes > 0 else { return }
        area.loggedMinutes = raised(area.loggedMinutes, by: area.focusSessions)
        let previous = area.loggedMinutes
        area.loggedMinutes = previous + minutes
        let row = row(minutes: minutes, previousMinutes: previous, now: now)
        modelContext.insert(row)
        row.area = area
        area.focusSessions = (area.focusSessions ?? []) + [row]
    }

    static func bank(_ minutes: Int, to project: Project, in modelContext: ModelContext, now: Date = Date()) {
        guard minutes > 0 else { return }
        project.loggedMinutes = raised(project.loggedMinutes, by: project.focusSessions)
        let previous = project.loggedMinutes
        project.loggedMinutes = previous + minutes
        let row = row(minutes: minutes, previousMinutes: previous, now: now)
        modelContext.insert(row)
        row.project = project
        project.focusSessions = (project.focusSessions ?? []) + [row]
    }

    /// The counter a subject's rows say it should hold: the legacy total the ledger inherited, plus
    /// every increment recorded since.
    ///
    /// The legacy total is `min(previousMinutes)` — see `FocusSessionLog`. Rows are summed, so two
    /// devices' concurrent sessions both count; the baseline is a minimum, so two devices that both
    /// started from the same legacy value count it once.
    static func reconciledTotal(of rows: [FocusSessionLog]) -> Int? {
        guard let baseline = rows.map(\.previousMinutes).min() else { return nil }
        return rows.reduce(baseline) { $0 + max(0, $1.minutes) }
    }

    /// Raise every focus counter in a store to what its rows say it should hold. Answers whether
    /// anything moved.
    ///
    /// `bank` already does this for the subject it touches, so a task you focus again heals itself.
    /// This is the pass for the ones you do not — a goal reading `actualMinutes` on a task nobody
    /// opens again stays wrong until something sweeps the store. Its intended home is
    /// `PersistenceController.performStartupMaintenance`, beside `DataIntegrityRepairService`; that
    /// one line is not landed yet (`docs/TODO.md` T-742), so today this is reachable and tested but
    /// not scheduled.
    ///
    /// **Only ever raises**, which is what makes it safe to run at startup with no gate on sync
    /// state — the property `DataIntegrityRepairService`'s doc comment argues every unattended pass
    /// must have. A half-synced store holds a subset of the rows and therefore computes a total
    /// that is too low; writing that back would destroy minutes the counter already had. `max`
    /// makes a partial store a no-op instead, and the total climbs to the truth as the remaining
    /// rows arrive. It is also the merge rule this repository already chose for this very field.
    ///
    /// **Idempotent by construction, and that is the whole reason the ledger needs no backfill
    /// pass.** `max(counter, min(previousMinutes) + Σminutes)` is a pure function of the counter and
    /// the rows, so running it twice lands on the same number: the second run recomputes the same
    /// right-hand side and `max` leaves an already-equal counter alone. A row written *after* a
    /// reconcile carries the reconciled counter as its `previousMinutes`, which is at or above the
    /// existing minimum, so it cannot move the baseline either. There is no "run once" flag to
    /// hang on a migration that does not exist, and none is needed.
    @discardableResult
    static func reconcile(in context: ModelContext) -> Bool {
        guard let rows = try? context.fetch(FetchDescriptor<FocusSessionLog>()), !rows.isEmpty else {
            return false
        }

        var tasks: [ObjectIdentifier: (subject: AppTask, rows: [FocusSessionLog])] = [:]
        var areas: [ObjectIdentifier: (subject: Area, rows: [FocusSessionLog])] = [:]
        var projects: [ObjectIdentifier: (subject: Project, rows: [FocusSessionLog])] = [:]

        for row in rows {
            if let task = row.task {
                tasks[ObjectIdentifier(task), default: (task, [])].rows.append(row)
            } else if let project = row.project {
                projects[ObjectIdentifier(project), default: (project, [])].rows.append(row)
            } else if let area = row.area {
                areas[ObjectIdentifier(area), default: (area, [])].rows.append(row)
            }
        }

        var changed = false
        for entry in tasks.values {
            guard let total = reconciledTotal(of: entry.rows), total > entry.subject.actualMinutes else { continue }
            entry.subject.actualMinutes = total
            changed = true
        }
        for entry in areas.values {
            guard let total = reconciledTotal(of: entry.rows), total > entry.subject.loggedMinutes else { continue }
            entry.subject.loggedMinutes = total
            changed = true
        }
        for entry in projects.values {
            guard let total = reconciledTotal(of: entry.rows), total > entry.subject.loggedMinutes else { continue }
            entry.subject.loggedMinutes = total
            changed = true
        }
        return changed
    }

    /// One subject's half of `reconcile(in:)`, applied by `bank` before it adds to a counter.
    ///
    /// **This is what makes the ledger self-healing without a launch hook.** Banking a session is
    /// the moment the app is already holding the subject and already writing to it, so correcting
    /// the counter there costs nothing and needs no store-wide pass. After it, the counter equals
    /// the ledger's own total exactly: the raise lands on `baseline + Σ existing`, the increment
    /// adds `minutes`, and the new row's `previousMinutes` is the raised value — at or above the
    /// baseline, so it cannot move the minimum. `reconcile(in:)` is then a no-op on this subject.
    ///
    /// Same `max` as the store-wide pass, for the same reason: a store that has received only some
    /// of CloudKit's rows computes a total that is too low, and lowering a counter would destroy
    /// minutes it already has.
    private static func raised(_ counter: Int, by rows: [FocusSessionLog]?) -> Int {
        guard let total = reconciledTotal(of: rows ?? []) else { return counter }
        return max(counter, total)
    }

    private static func row(minutes: Int, previousMinutes: Int, now: Date) -> FocusSessionLog {
        FocusSessionLog(
            minutes: minutes,
            previousMinutes: previousMinutes,
            loggedAt: now,
            dayKey: DateFormatters.dateKey(from: now)
        )
    }
}
