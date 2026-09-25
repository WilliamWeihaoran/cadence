import Foundation
import SwiftData

nonisolated enum CadenceWriteError: Error, LocalizedError, Sendable {
    case emptyTitle
    case emptyContent
    case emptyName
    case invalidColorHex(String)
    case emptySectionName
    case duplicateSectionName(String)
    case invalidPriority(String)
    case invalidNoteKind(String)
    case invalidScheduledStartMin(Int)
    case invalidEstimatedMinutes(Int)
    case invalidCombination(String)
    case noChanges
    case cannotCompleteCancelledTask(String)
    case invalidContainerStatus(String, [String])
    case sectionNotFound(String, [String])
    case columnNotFound(String, [String])
    case invalidPosition(Int, Int, String)
    case emptyURL
    case tagsUnavailable
    /// A goal or a habit with no title. Separate from `emptyTitle`, which says "Task title", so the
    /// caller is told which of the three constructors refused rather than reading about a task it
    /// never asked for.
    case emptyTitleFor(String)
    case invalidGoalKind(String)
    case invalidGoalStatus(String)
    case invalidGoalProgressType(String)
    case invalidHabitFrequency(String)
    /// `parentGoalId` named a goal that is itself a milestone — the third level
    /// `GoalAssignmentRules.canOwnMilestones` refuses on both editors.
    case goalCannotOwnMilestones(String)
    /// A `titlePrefix` bulk cancellation whose selection is larger than the surface will execute
    /// in one call (T-1365). Carries both numbers because the refusal is only useful if the caller
    /// learns how big the blast radius actually was.
    case bulkSelectionTooBroad(matched: Int, limit: Int)

    var errorDescription: String? {
        switch self {
        case .emptyTitle:
            return "Task title must not be empty."
        case .emptyContent:
            return "Note content must not be empty."
        case .emptyName:
            return "Name must not be empty."
        case .invalidColorHex(let value):
            return "Invalid colorHex: \(value). Expected a six-digit hex colour such as #4a9eff."
        case .emptySectionName:
            return "Section names must not be empty."
        case .duplicateSectionName(let name):
            return "Duplicate section name: \(name). Section names must be unique within one list."
        case .invalidContainerStatus(let value, let allowed):
            return "Invalid status: \(value). Expected one of: \(allowed.joined(separator: ", "))."
        case .invalidPriority(let value):
            return "Invalid priority value: \(value). Expected none, low, medium, or high."
        case .invalidNoteKind(let value):
            return "Invalid note kind: \(value). Expected daily, weekly, or permanent."
        case .invalidScheduledStartMin(let value):
            return "Invalid scheduledStartMin: \(value). Expected 0...1439."
        case .invalidEstimatedMinutes(let value):
            return "Invalid estimatedMinutes: \(value). Expected 1...1440."
        case .invalidCombination(let message):
            return message
        case .noChanges:
            return "No valid changes were provided."
        case .cannotCompleteCancelledTask(let id):
            return "Cancelled task \(id) cannot be completed."
        case .sectionNotFound(let name, let available):
            guard !available.isEmpty else {
                return "Invalid sectionName: \(name). An inbox task has no sections."
            }
            return "Invalid sectionName: \(name). Expected one of: \(available.joined(separator: ", "))."
        case .columnNotFound(let name, let available):
            return "No column named \(name) on this list. Expected one of: \(available.joined(separator: ", "))."
        case .invalidPosition(let value, let upperBound, let noun):
            return "Invalid order: \(value). Expected 0...\(upperBound) — the zero-based position among the \(upperBound + 1) \(noun) this call leaves it beside."
        case .emptyURL:
            return "Link url must not be empty."
        case .tagsUnavailable:
            return "Tags could not be read, so nothing was written."
        case .emptyTitleFor(let noun):
            return "\(noun) title must not be empty."
        case .invalidGoalKind(let value):
            return "Invalid kind: \(value). Expected one of: \(GoalKind.allCases.map(\.rawValue).joined(separator: ", "))."
        case .invalidGoalStatus(let value):
            return "Invalid status: \(value). Expected one of: \(GoalStatus.allCases.map(\.rawValue).joined(separator: ", "))."
        case .invalidGoalProgressType(let value):
            return "Invalid progressType: \(value). Expected one of: \(GoalProgressType.allCases.map(\.rawValue).joined(separator: ", "))."
        case .invalidHabitFrequency(let value):
            return "Invalid frequencyType: \(value). Expected one of: \(HabitFrequency.allCases.map(\.rawValue).joined(separator: ", "))."
        case .bulkSelectionTooBroad(let matched, let limit):
            return "titlePrefix matches \(matched) tasks, above the \(limit) this call will cancel at once. Narrow the prefix, or send dryRun and pass the taskIds you mean."
        case .goalCannotOwnMilestones(let id):
            return "Goal \(id) is already a milestone of another goal, so it cannot own milestones of its own. Goals nest exactly one level: a top-level goal is a direction and its sub-goals are its milestones."
        }
    }
}

nonisolated struct CadenceCreateTaskOptions: Sendable {
    var title: String
    var notes: String? = nil
    var priority: String? = nil
    var dueDate: String? = nil
    var scheduledDate: String? = nil
    var scheduledStartMin: Int? = nil
    var estimatedMinutes: Int? = nil
    var containerKind: String? = nil
    var containerId: String? = nil
    var sectionName: String? = nil
    var subtaskTitles: [String]? = nil
    var tagNames: [String]? = nil
}

nonisolated struct CadenceUpdateTaskOptions: Sendable {
    var taskId: String
    var title: String? = nil
    var notes: String? = nil
    var priority: String? = nil
    var dueDate: String? = nil
    var clearDueDate: Bool = false
    var estimatedMinutes: Int? = nil
    var containerKind: String? = nil
    var containerId: String? = nil
    var clearContainer: Bool = false
    var sectionName: String? = nil
    var tagNames: [String]? = nil
}

nonisolated struct CadenceScheduleTaskOptions: Sendable {
    var taskId: String
    var scheduledDate: String? = nil
    var scheduledStartMin: Int? = nil
    var estimatedMinutes: Int? = nil
    var clearScheduledDate: Bool = false
}

/// **`dryRun` is the argument a headless caller needs and a UI does not** (T-1365).
///
/// Every other write arm on this surface names one entity. This one takes a *pattern*, from a
/// second process, and the app-side answer to "are you sure about 500 rows" — show a confirmation
/// sheet — is unavailable here, which is the same reasoning [[T-1122]]'s refusals are written on.
/// A dry run resolves the selection with the **executor's own matcher** and returns it without
/// cancelling anything, so the blast radius the caller is shown is the one the next call acts on
/// rather than an approximation reassembled out of `list_tasks`.
nonisolated struct CadenceBulkCancelTaskOptions: Sendable {
    var taskIds: [String]? = nil
    var titlePrefix: String? = nil
    var dryRun: Bool = false
}

nonisolated struct CadenceCreateContextOptions: Sendable {
    var name: String
    var colorHex: String? = nil
    var icon: String? = nil
}

/// **`areaId` and `dueDate` are project-only, and that is the model talking, not a policy.**
/// `Area` declares neither an owning area nor a due date — an area is an ongoing responsibility
/// with no end — so an `area` request carrying either is refused rather than quietly ignored. The
/// same argument `CadenceMCPServiceSupport.normalizedSectionName` makes about a mistyped section:
/// a caller who only ever reads the word "success" cannot notice a dropped argument.
nonisolated struct CadenceCreateContainerOptions: Sendable {
    var containerKind: String
    var name: String
    var description: String? = nil
    var contextId: String? = nil
    var areaId: String? = nil
    var colorHex: String? = nil
    var icon: String? = nil
    var dueDate: String? = nil
    var sectionNames: [String]? = nil
}

/// A change to the kanban columns of a list that already exists (T-1095).
///
/// **Columns are addressed by name, because a name is all a caller can see.**
/// `CadenceSectionSummary` — the only shape `get_container_summary`, `create_container` and this
/// tool answer columns in — carries `name`, `colorHex`, `dueDate`, `isCompleted`, `isArchived` and
/// three counts, and no `uuid`. Exposing the stored uuid so a caller could address a column by
/// identity is a response-schema change with its own version bump; until then, addressing by
/// anything else would be asking for a value this surface has never returned.
///
/// **There is no `removeColumns`, deliberately.** Archiving a column hides it from
/// `sectionNames` and is reversible from this same tool; removing one destroys its colour, due
/// date and lifecycle flags with no undo and no confirmation, on a path whose only record is
/// `mcp-audit.log`. That is the decision `docs/TODO.md` T-1095 asks be taken separately rather
/// than ridden in on a column editor.
nonisolated struct CadenceUpdateContainerColumnsOptions: Sendable {
    var containerKind: String
    var containerId: String
    /// The existing column every per-column field below applies to.
    var columnName: String? = nil
    var newName: String? = nil
    var colorHex: String? = nil
    var dueDate: String? = nil
    var clearDueDate: Bool = false
    var isCompleted: Bool? = nil
    var isArchived: Bool? = nil
    /// New columns, appended in the order given, after any rename in this same call.
    var addColumns: [String]? = nil
    /// The complete new order, by name, as the list reads *after* this call's rename and
    /// additions. A partial order is refused rather than guessed at.
    var columnOrder: [String]? = nil
}

/// A change to a `Context` that already exists (T-1120): rename, recolour, re-icon, archive.
///
/// **Archiving is what this surface offers instead of deleting, and that is the decision T-1120
/// asked be taken on its own.** `ModelContext.deleteContext` takes every area, project, pursuit,
/// goal, habit, completion, note, link, image asset and task beneath it, with no confirmation
/// step and `mcp-audit.log` for a record. Two things are true about it here that are not true in
/// the app, and either one is enough:
///
/// - **It is not reachable from this target and cannot cheaply be made so.**
///   `Cadence/Services/CadenceListDeleteHelpers.swift` is not in `CadenceMCPServer`'s explicit
///   Sources phase, and its task sweep goes through `CadenceTaskMutationSupport.deleteTasks`,
///   which calls `NotificationManager.shared`. That type lazily touches
///   `UNUserNotificationCenter.current()`, guarded only for test and Preview hosts — a
///   command-line tool has neither bundle identity nor that guard. It is the same boundary that
///   already makes `createTask` insert its subtasks by hand rather than through
///   `CadenceTaskMutationSupport.insertSubtasks`.
/// - **`deleteContext` reads this device's local relationship arrays** — `context.areas ?? []`,
///   `context.tasks ?? []` and so on. A CloudKit record that has not arrived in this store is not
///   in those arrays, so a delete arm could not honestly report what it removed: it would answer
///   "deleted" over rows it never saw, which then arrive afterwards orphaned.
///
/// So: `isArchived` hides a context everywhere `includeArchived` is not asked for, is reversible
/// from this same tool, and destroys nothing. `update_container_columns` refuses column removal on
/// the same argument one size down.
///
/// **`order` is a position, not the stored number** (T-1182) — see
/// `CadenceUpdateContainerOptions`, which spells the rule for the bucket that actually needed it.
/// Contexts are one flat sequence, so the bucket here is every context in the store.
nonisolated struct CadenceUpdateContextOptions: Sendable {
    var contextId: String
    var name: String? = nil
    var colorHex: String? = nil
    var icon: String? = nil
    var isArchived: Bool? = nil
    var order: Int? = nil
}

/// A change to the fields of an `Area` or a `Project` that already exists (T-1120).
///
/// **`areaId`, `clearArea`, `dueDate` and `clearDueDate` are project-only**, refused on the
/// requested text before resolution — `CadenceCreateContainerOptions`' argument exactly, because
/// `Area` declares neither an owning area nor a due date.
///
/// **Archiving is `status: "archived"`, and there is no delete**, for the reasons written out on
/// `CadenceUpdateContextOptions` above.
///
/// **`order` is still not recomputed when `contextId` moves the list, and it is now sayable**
/// (T-1182). `createContainer` numbers a new row `max + 1` among its siblings because the model
/// default of 0 would otherwise interleave it alphabetically; an existing list already carries a
/// number the user's own ordering produced. Both app editors agree — `EditListSheet` and
/// `iOSListEditorViews` assign `context` on a move and renumber only on create — and inventing a
/// third behaviour for a caller who only asked to re-file would be worse than the gap. What T-1182
/// measured is that the gap had no exit: `CadenceMCPOrdering.precedes` breaks an `order` tie on the
/// *name*, so a list moved into a context where a sibling already holds its number interleaves
/// alphabetically, and this surface could not say where it should have gone.
///
/// `order` is that exit, and it is **a zero-based position among the lists the call leaves in the
/// destination context, not the stored number**. The stored numbers are max-plus-one allocations
/// with a gap wherever something was deleted, so a caller handed `[0, 2, 5]` cannot name "third"
/// by arithmetic; and writing a raw number is how the tie gets created rather than resolved. The
/// arm therefore renumbers the **whole destination bucket** densely from zero, which is the only
/// state in which `precedes` never reaches its name leg — after one such call, `CadenceContainerRef
/// .order` reads back exactly the position that was asked for. A position outside `0...count` is
/// refused naming the range rather than clamped, `columnOrder`'s rule for a partial order.
///
/// **The bucket the list left is not renumbered**, deliberately: the gap it leaves changes no
/// sibling's relative position, and touching rows the caller did not name is the behaviour the
/// paragraph above refuses. Areas and projects share one bucket per context and unfiled lists share
/// their own — `nil == nil`, the rule `nextListOrder` spells.
///
/// **`linkedCalendarID` is refused, and that is the decision T-1182 asked for rather than an
/// omission.** `Cadence/Models/AGENTS.md` records T-390: the field holds a bare
/// `EKCalendar.calendarIdentifier`, treated as opaque and permanent precisely so a dead link reads
/// as unlinked instead of being re-matched by name. Nothing on this surface can enumerate the
/// user's calendars — `EventKit` is in no MCP target — so a caller could only echo back an
/// identifier it read from somewhere else, and a wrong one binds a list to a stranger's calendar
/// with no picker, no title in the response, and `mcp-audit.log` for a record. That is a write
/// whose result is invisible on this surface, which is the one shape this boundary refuses.
nonisolated struct CadenceUpdateContainerOptions: Sendable {
    var containerKind: String
    var containerId: String
    var name: String? = nil
    var description: String? = nil
    var colorHex: String? = nil
    var icon: String? = nil
    var contextId: String? = nil
    var clearContext: Bool = false
    var areaId: String? = nil
    var clearArea: Bool = false
    var dueDate: String? = nil
    var clearDueDate: Bool = false
    var status: String? = nil
    /// The zero-based position among the lists this call leaves in the destination context.
    var order: Int? = nil
    var hideDueDateIfEmpty: Bool? = nil
    var hideSectionDueDateIfEmpty: Bool? = nil
}

/// A saved link on an `Area` or a `Project` (T-1122, leg (b), the first of six).
///
/// **The container is required.** `SavedLink` declares `area` and `project` and no third home, and
/// `CadenceSavedLinkSummary.container` is the only place a caller can see which one a link is on;
/// a link attached to neither is a row `list_links` returns with `container: null` and nothing in
/// the app shows at all.
///
/// **`url` goes through `CadenceSavedLinkURL.normalized`, which is why that file joined this
/// target's Sources phase.** The rule it holds is T-509: `hasPrefix` is case-sensitive and a URI
/// scheme is not, so two hand-rolled copies of trim-and-prepend both turned
/// `HTTPS://example.com` into `https://HTTPS://example.com`. A third copy here — inside a process
/// with no address bar and no user to notice — is exactly the shape that ticket exists to stop.
/// The file's other half, `CadenceSavedLinkPersistence`, is deliberately **not** used: its
/// insert-and-commit is `saveNotifyAndAudit`'s job on this surface, which additionally audits and
/// wakes the app.
/// Everything `create_goal` may set, and deliberately nothing else (T-1122).
///
/// **There is no `linkedContainerIds`, and that is a measured boundary rather than an omission.**
/// A `GoalListLink` has exactly one write path — `ModelContext.attachList` in
/// `Cadence/Shared/GoalListLinkHelpers.swift` (`Cadence/Models/AGENTS.md`) — and that file is not
/// in `CadenceMCPServer`'s Sources phase. Hand-rolling `insert(GoalListLink(...))` here is the one
/// thing that guide names as forbidden, and it would re-break the idempotence that stops a
/// duplicate row double-counting every link-counting surface. So the arm creates a link-less goal
/// and a client that wants lists attached uses the app; `update_goal` is not on this surface either.
///
/// **There is no `parentGoalId` that may name a milestone.** `GoalAssignmentRules.canOwnMilestones`
/// keeps the hierarchy two deep, and since T-1327 both editors ask that one function rather than
/// each keeping a copy. `createGoal` asks it too — a third surface that did not would be exactly
/// the way the tree came to exist the last time.
nonisolated struct CadenceCreateGoalOptions: Sendable {
    var title: String
    var description: String? = nil
    var startDate: String? = nil
    var endDate: String? = nil
    var progressType: String? = nil
    var targetHours: Double? = nil
    var icon: String? = nil
    var colorHex: String? = nil
    var kind: String? = nil
    var status: String? = nil
    var contextId: String? = nil
    var parentGoalId: String? = nil
}

/// Everything `create_habit` may set, and deliberately nothing else (T-1122).
///
/// **There is no `reminderMinuteOfDay`, and the reason is the same one that chose
/// `CadenceSavedLinkURL.normalized` over a third hand-rolled URL rule.** The reminder field has no
/// shared owner: `CadenceTrackingMutationSupport.saveHabit` — the one helper both editors go
/// through — does not write it at all, and `HabitsFormSheets` on macOS and `iOSTrackingEditorSheets`
/// on iOS each write it themselves, beside their own `hasReminder` toggle. A third copy here would
/// be the first one in a process with no picker to bound it, writing a field the model validates
/// nothing about (`Habit.reminderMinuteOfDay`'s own audit note) into a row that then schedules a
/// standing daily alarm on the owner's device the next time the app reconciles on a `scenePhase`
/// change. Neither `HabitNotificationPlanner` nor `NotificationManager` is in this target's Sources
/// phase, so this process cannot even see the range it would have to respect. A habit created here
/// has no reminder; setting one is an app action.
nonisolated struct CadenceCreateHabitOptions: Sendable {
    var title: String
    var icon: String? = nil
    var colorHex: String? = nil
    var frequencyType: String? = nil
    var frequencyDays: [Int]? = nil
    var targetCount: Int? = nil
    var contextId: String? = nil
    var goalId: String? = nil
}

nonisolated struct CadenceCreateSavedLinkOptions: Sendable {
    var containerKind: String
    var containerId: String
    var url: String
    /// Optional; a link with no title displays as its url, which is what both app editors do.
    var title: String? = nil
}

/// Every field `updateContainer` writes to an `Area` or a `Project`, captured before the write so
/// a refused commit puts all of it back (T-1121).
///
/// **Why this is not `CadenceListEditSnapshot`, which says the same sentence about the same two
/// models.** That type lives in `Cadence/Shared/CadenceListEditSnapshot.swift`, which references
/// `CadenceTaskFieldSnapshot` — declared in `CadenceTaskFieldEditCommit.swift` beside an enum that
/// reaches `CadenceWindDownReconciler`, declared in
/// `Cadence/Services/CadenceTaskContainerLifecycleService.swift`. Adding the shared snapshot to
/// `CadenceMCPServer`'s Sources phase therefore adds the notification stack to a command-line
/// tool, which is the coupling `CadenceMCPServer/AGENTS.md` warns about and the same boundary that
/// keeps `CadenceTaskMutationSupport` out. The covered set is also smaller by design: this arm
/// writes no task, so there is no `tasks:` leg, and it writes no `sectionConfigsRaw` —
/// `updateContainerColumns` owns that and has its own undo.
///
/// **Raw strings, not the computed façades**, for `CadenceListEditSnapshot`'s own reason:
/// `statusRaw` coerces an unrecognised value to `.active` on read, so restoring through `status`
/// would put a normalised value back as if the caller had chosen it.
private struct CadenceMCPContainerFieldSnapshot {
    private let area: Area?
    private let project: Project?
    private let name: String
    private let desc: String
    private let colorHex: String
    private let icon: String
    private let statusRaw: String
    private let dueDate: String
    private let hideDueDateIfEmpty: Bool
    private let hideSectionDueDateIfEmpty: Bool
    private let parentContext: Context?
    private let parentArea: Area?

    init(_ area: Area) {
        self.area = area
        project = nil
        name = area.name
        desc = area.desc
        colorHex = area.colorHex
        icon = area.icon
        statusRaw = area.statusRaw
        hideDueDateIfEmpty = area.hideDueDateIfEmpty
        hideSectionDueDateIfEmpty = area.hideSectionDueDateIfEmpty
        // An area has no due date of its own; the field is here for the project case and is put
        // back only on a project.
        dueDate = ""
        parentContext = area.context
        parentArea = nil
    }

    init(_ project: Project) {
        area = nil
        self.project = project
        name = project.name
        desc = project.desc
        colorHex = project.colorHex
        icon = project.icon
        statusRaw = project.statusRaw
        dueDate = project.dueDate
        hideDueDateIfEmpty = project.hideDueDateIfEmpty
        hideSectionDueDateIfEmpty = project.hideSectionDueDateIfEmpty
        parentContext = project.context
        parentArea = project.area
    }

    func restore() {
        if let area {
            area.name = name
            area.desc = desc
            area.colorHex = colorHex
            area.icon = icon
            area.statusRaw = statusRaw
            area.hideDueDateIfEmpty = hideDueDateIfEmpty
            area.hideSectionDueDateIfEmpty = hideSectionDueDateIfEmpty
            area.context = parentContext
        }
        if let project {
            project.name = name
            project.desc = desc
            project.colorHex = colorHex
            project.icon = icon
            project.statusRaw = statusRaw
            project.dueDate = dueDate
            project.hideDueDateIfEmpty = hideDueDateIfEmpty
            project.hideSectionDueDateIfEmpty = hideSectionDueDateIfEmpty
            project.context = parentContext
            project.area = parentArea
        }
    }
}

/// Every field the task-editing arms on this surface write, captured before the write so a
/// refused commit puts it back (T-1121).
///
/// **Why not `CadenceTaskFieldSnapshot`**, which says the same sentence about the same model: two
/// reasons, and either alone decides it.
///
/// - **The file it lives in cannot join this target.** `Cadence/Shared/CadenceTaskFieldEditCommit.swift`
///   also declares `CadenceTaskFieldEditCommit`, which reaches `CadenceWindDownReconciler` in
///   `Cadence/Services/CadenceTaskContainerLifecycleService.swift` — the notification stack a
///   command-line tool has no business linking, and the same boundary that keeps
///   `CadenceTaskMutationSupport` out of `createTask`.
/// - **It does not cover what `updateTask` writes.** Its own documented boundary excludes
///   `notes` and the to-many `tags`, and `updateTask` writes both. `tags` is restorable here where
///   `subtasks` would not be: the rows are pre-existing `Tag`s this arm only re-associated, so
///   putting the array back is an undo rather than an attempt to un-insert.
///
/// **Raw strings, not the computed façades**, for `CadenceTaskFieldSnapshot`'s own reason: the
/// computed `status` / `priority` coerce an unrecognised stored value to a default on read, so
/// restoring through them would write that default back as if the caller had chosen it.
private struct CadenceMCPTaskFieldSnapshot {
    let task: AppTask
    private let title: String
    private let notes: String
    private let priorityRaw: String
    private let statusRaw: String
    private let completedAt: Date?
    private let dueDate: String
    private let scheduledDate: String
    private let scheduledStartMin: Int
    private let estimatedMinutes: Int
    private let sectionName: String
    private let recurrenceSeriesIDRaw: String
    private let recurrenceSpawnedTaskIDRaw: String
    private let area: Area?
    private let project: Project?
    private let context: Context?
    private let tags: [Tag]?

    init(_ task: AppTask) {
        self.task = task
        title = task.title
        notes = task.notes
        priorityRaw = task.priorityRaw
        statusRaw = task.statusRaw
        completedAt = task.completedAt
        dueDate = task.dueDate
        scheduledDate = task.scheduledDate
        scheduledStartMin = task.scheduledStartMin
        estimatedMinutes = task.estimatedMinutes
        sectionName = task.sectionName
        recurrenceSeriesIDRaw = task.recurrenceSeriesIDRaw
        recurrenceSpawnedTaskIDRaw = task.recurrenceSpawnedTaskIDRaw
        area = task.area
        project = task.project
        context = task.context
        tags = task.tags
    }

    func restore() {
        task.title = title
        task.notes = notes
        task.priorityRaw = priorityRaw
        task.statusRaw = statusRaw
        task.completedAt = completedAt
        task.dueDate = dueDate
        task.scheduledDate = scheduledDate
        task.scheduledStartMin = scheduledStartMin
        task.estimatedMinutes = estimatedMinutes
        task.sectionName = sectionName
        task.recurrenceSeriesIDRaw = recurrenceSeriesIDRaw
        task.recurrenceSpawnedTaskIDRaw = recurrenceSpawnedTaskIDRaw
        task.area = area
        task.project = project
        task.context = context
        task.tags = tags
    }
}

private struct PendingAuditEntry {
    let tool: String
    let entityType: String
    let entityId: String
    let summary: String

    static func task(tool: String, id: UUID, summary: String) -> PendingAuditEntry {
        PendingAuditEntry(tool: tool, entityType: "task", entityId: id.uuidString, summary: summary)
    }

    static func coreNote(id: UUID, summary: String) -> PendingAuditEntry {
        PendingAuditEntry(tool: "append_core_note", entityType: "core_note", entityId: id.uuidString, summary: summary)
    }

    static func context(id: UUID, summary: String) -> PendingAuditEntry {
        PendingAuditEntry(tool: "create_context", entityType: "context", entityId: id.uuidString, summary: summary)
    }

    /// `entityType` is the container's own kind — `area` or `project` — rather than a flat
    /// "container", so the audit log distinguishes the two the way every other MCP surface does.
    static func container(kind: String, id: UUID, summary: String) -> PendingAuditEntry {
        PendingAuditEntry(tool: "create_container", entityType: kind, entityId: id.uuidString, summary: summary)
    }

    static func savedLink(id: UUID, summary: String) -> PendingAuditEntry {
        PendingAuditEntry(tool: "create_link", entityType: "link", entityId: id.uuidString, summary: summary)
    }

    static func goal(id: UUID, summary: String) -> PendingAuditEntry {
        PendingAuditEntry(tool: "create_goal", entityType: "goal", entityId: id.uuidString, summary: summary)
    }

    static func habit(id: UUID, summary: String) -> PendingAuditEntry {
        PendingAuditEntry(tool: "create_habit", entityType: "habit", entityId: id.uuidString, summary: summary)
    }

    static func contextFields(id: UUID, summary: String) -> PendingAuditEntry {
        PendingAuditEntry(tool: "update_context", entityType: "context", entityId: id.uuidString, summary: summary)
    }

    /// `entityType` is the container's own kind, exactly as `container(kind:id:summary:)` records
    /// it; only `tool` separates a create from an edit in `mcp-audit.log`.
    static func containerFields(kind: String, id: UUID, summary: String) -> PendingAuditEntry {
        PendingAuditEntry(tool: "update_container", entityType: kind, entityId: id.uuidString, summary: summary)
    }

    /// Same `entityType` as `container(kind:id:summary:)` — the row that changed is the area or the
    /// project, not the column, which is not a row at all (`Cadence/Models/AGENTS.md`: "Sections
    /// Are Not A Model"). Only `tool` distinguishes the two entries in `mcp-audit.log`.
    static func containerColumns(kind: String, id: UUID, summary: String) -> PendingAuditEntry {
        PendingAuditEntry(tool: "update_container_columns", entityType: kind, entityId: id.uuidString, summary: summary)
    }
}

@MainActor
final class CadenceWriteService {
    private let context: ModelContext
    private let readService: CadenceReadService
    private let notifiesExternalWrites: Bool
    private let auditLogger: CadenceMCPAuditLogger?

    /// How a write is committed. A parameter for the reason every `commit:` in this repository is
    /// one: a `save()` that throws cannot be provoked out of an in-memory container, and
    /// `updateContainerColumns`' undo — the columns and the cards put back — is an undo path no
    /// test could otherwise reach.
    private let commit: (ModelContext) throws -> Void

    /// Startup steps executed by *this* instance, plus any its private read service ran. `0` once
    /// the caller has said the container factory already prepared the store (T-309).
    private(set) var executedStartupStepCount = 0

    /// `preparesStore: false` says the caller has already run `CadenceMCPStorePreparation.prepare`
    /// over this store — which `CadenceModelContainerFactory.makeReadWriteContainer()` does, and
    /// which is why `main.swift` passes it (T-309). The private read service never migrates either
    /// way: either this initializer just did, or the caller says it was already done.
    init(
        container: ModelContainer,
        notifiesExternalWrites: Bool = false,
        auditLogger: CadenceMCPAuditLogger? = nil,
        preparesStore: Bool = true,
        commit: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) {
        let context = ModelContext(container)
        let steps = preparesStore
            ? CadenceMCPStorePreparation.prepare(in: context, source: "mcp-write-service")
            : 0
        self.context = context
        self.readService = CadenceReadService(context: context, performsMigrations: false)
        self.notifiesExternalWrites = notifiesExternalWrites
        self.auditLogger = auditLogger
        self.commit = commit
        self.executedStartupStepCount = steps + readService.executedStartupStepCount
    }

    init(
        context: ModelContext,
        notifiesExternalWrites: Bool = false,
        auditLogger: CadenceMCPAuditLogger? = nil,
        preparesStore: Bool = true,
        commit: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) {
        let steps = preparesStore
            ? CadenceMCPStorePreparation.prepare(in: context, source: "mcp-write-service-context")
            : 0
        self.context = context
        self.readService = CadenceReadService(context: context, performsMigrations: false)
        self.notifiesExternalWrites = notifiesExternalWrites
        self.auditLogger = auditLogger
        self.commit = commit
        self.executedStartupStepCount = steps + readService.executedStartupStepCount
    }

    /// Create a `Context`, the top-level grouping every area and project can be filed under.
    ///
    /// **T-799.** MCP could create a task and append to a core note and nothing else, so the one
    /// argument `create_task` needs in order to put a task anywhere — a `containerId` — could not
    /// be minted from this surface at all. Seeding a kanban board had to be clicked by hand.
    ///
    /// `order` is one past the highest among the rows the new one will sit beside, which is what
    /// `CreateListSheet.nextListOrder` and `iOSContextEditorSheet.nextContextOrder` already do.
    /// Leaving it at the model default is not neutral here: `CadenceMCPOrdering.precedes` breaks an
    /// `order` tie on the *name*, so every seeded context would interleave alphabetically with the
    /// user's own rather than landing at the end of the list where it was created.
    func createContext(options: CadenceCreateContextOptions) throws -> CadenceContextSummary {
        let name = try normalizedRequiredText(options.name, emptyError: CadenceWriteError.emptyName)
        let colorHex = try normalizedOptionalColorHex(options.colorHex)
        let icon = CadenceMCPServiceSupport.normalizedOptionalText(options.icon)

        let created = Context(name: name)
        if let colorHex { created.colorHex = colorHex }
        if let icon { created.icon = icon }
        created.order = try nextContextOrder()
        context.insert(created)

        try saveNotifyAndAudit(
            .context(id: created.id, summary: "Created context: \(created.name)"),
            inserted: [created]
        )
        return try readService.contextSummary(contextID: created.id.uuidString)
    }

    /// Rename, recolour, re-icon or archive a `Context` that already exists (T-1120).
    ///
    /// The refusals and the deletion decision are written out on `CadenceUpdateContextOptions`.
    /// What is here is the shape every editing arm on this surface now shares: validate
    /// everything, refuse a request that asks for nothing, capture what is about to be written,
    /// write, and hand the capture to the commit as the undo (T-1121).
    func updateContext(options: CadenceUpdateContextOptions) throws -> CadenceContextSummary {
        guard let target = try resolveContext(options.contextId) else {
            throw CadenceWriteError.invalidCombination("contextId is required.")
        }
        let name = try options.name.map { try normalizedRequiredText($0, emptyError: CadenceWriteError.emptyName) }
        let colorHex = try normalizedOptionalColorHex(options.colorHex)
        let icon = CadenceMCPServiceSupport.normalizedOptionalText(options.icon)

        guard name != nil || colorHex != nil || icon != nil || options.isArchived != nil
            || options.order != nil
        else {
            throw CadenceWriteError.noChanges
        }

        // Validated, and the whole new numbering computed, before anything is written — the shape
        // every editing arm here shares, so a refused position cannot leave a rename applied.
        let placement = try options.order.map { try plannedContextOrders(moving: target, to: $0) }
        // Captured here and put back by this call's own `undo`, rather than by a snapshot type of
        // its own. A renumber and the restore that answers for it belong to the frame that owns the
        // unit of work — the frame `CadenceSaveCommitDisciplineTests`' half 2b judges — and that is
        // this one: it is what reaches the commit, so it is what has to un-do the rearrangement
        // when the commit is refused.
        let previousOrders = (placement ?? []).map { (row: $0.row, order: $0.row.order) }

        let previousName = target.name
        let previousColorHex = target.colorHex
        let previousIcon = target.icon
        let previousIsArchived = target.isArchived

        if let name { target.name = name }
        if let colorHex { target.colorHex = colorHex }
        if let icon { target.icon = icon }
        if let isArchived = options.isArchived { target.isArchived = isArchived }
        if let placement {
            for entry in placement { entry.row.order = entry.order }
        }

        try saveNotifyAndAudit([.contextFields(id: target.id, summary: "Updated context: \(target.name)")]) {
            for entry in previousOrders { entry.row.order = entry.order }
            target.name = previousName
            target.colorHex = previousColorHex
            target.icon = previousIcon
            target.isArchived = previousIsArchived
        }
        return try readService.contextSummary(contextID: target.id.uuidString)
    }

    /// Create an `Area` or a `Project`, optionally carrying the kanban columns that make it a board.
    ///
    /// **The columns are written straight through `sectionConfigs`, not through
    /// `CadenceSectionConfigMerge`, and that is deliberate.** The merge exists to reconcile two
    /// editors holding stale snapshots of one list's single JSON blob; a container this call
    /// inserted a line earlier has no other holder, no `base` and no `current` to reconcile
    /// against, so the merge would degenerate to "apply the edit" — the case its own documentation
    /// names. It is also not in `CadenceMCPServer`'s explicit Sources phase, and adding a
    /// `Cadence/Shared/` file there to reach a no-op is exactly the coupling
    /// `CadenceMCPServer/AGENTS.md` warns about.
    ///
    /// **A Default column always exists.** `Area.normalizedSectionConfigs` /
    /// `Project.normalizedSectionConfigs` synthesise it when absent and force it to index 0, on
    /// every read and every write, because `AppTask.resolvedSectionName` funnels every task with no
    /// section name into it. So `sectionNames: ["Backlog", "Doing"]` produces three columns, not
    /// two, and the advertised schema says so rather than letting a caller discover it.
    func createContainer(options: CadenceCreateContainerOptions) throws -> CadenceContainerSummary {
        let kind = try normalizedContainerKind(options.containerKind)
        let name = try normalizedRequiredText(options.name, emptyError: CadenceWriteError.emptyName)
        let colorHex = try normalizedOptionalColorHex(options.colorHex)
        let icon = CadenceMCPServiceSupport.normalizedOptionalText(options.icon)
        let sectionNames = try CadenceMCPServiceSupport.normalizedSectionNames(options.sectionNames)

        // Refused on the *requested* text, before resolution: an `areaId` sent to an area is a
        // misunderstanding of the shape whether or not that id happens to name a real area, and
        // answering "no area found" instead would send the caller looking for the wrong bug.
        let requestsArea = CadenceMCPServiceSupport.normalizedOptionalText(options.areaId) != nil
        let requestsDueDate = CadenceMCPServiceSupport.normalizedOptionalText(options.dueDate) != nil
        if kind == "area" {
            if requestsArea {
                throw CadenceWriteError.invalidCombination("areaId applies to a project; an area cannot be filed inside another area.")
            }
            if requestsDueDate {
                throw CadenceWriteError.invalidCombination("dueDate applies to a project; an area is ongoing and carries no due date.")
            }
        }

        let parentContext = try resolveContext(options.contextId)
        let parentArea = try resolveArea(options.areaId)
        let dueDate = try validatedOptionalDate(options.dueDate)
        let order = try nextListOrder(inContextWithID: parentContext?.id)

        // Colour and icon are only assigned when the caller named one, so an omitted argument
        // leaves the model's own default rather than a copy of it restated here — `Area`,
        // `Project` and `Context` each declare a different pair.
        let id: UUID
        // Held as well as the id, so a refused commit can un-insert the row rather than leave it
        // pending on this service's long-lived context for the next tool call's save() (T-1121).
        let inserted: any PersistentModel
        switch kind {
        case "area":
            let area = Area(name: name, context: parentContext)
            if let colorHex { area.colorHex = colorHex }
            if let icon { area.icon = icon }
            if let description = options.description { area.desc = description }
            area.order = order
            context.insert(area)
            if let sectionNames { area.sectionConfigs = sectionNames.map { TaskSectionConfig(name: $0) } }
            id = area.id
            inserted = area
        default:
            let project = Project(name: name, context: parentContext, area: parentArea)
            if let colorHex { project.colorHex = colorHex }
            if let icon { project.icon = icon }
            if let description = options.description { project.desc = description }
            if let dueDate { project.dueDate = dueDate }
            project.order = order
            context.insert(project)
            if let sectionNames { project.sectionConfigs = sectionNames.map { TaskSectionConfig(name: $0) } }
            id = project.id
            inserted = project
        }

        try saveNotifyAndAudit(
            .container(kind: kind, id: id, summary: "Created \(kind): \(name)"),
            inserted: [inserted]
        )
        return try readService.containerSummary(kind: kind, id: id.uuidString)
    }

    /// Rename, recolour, re-icon, re-file, redate or archive an `Area` or a `Project` that already
    /// exists (T-1120).
    ///
    /// The project-only refusals, the archive-instead-of-delete decision, the position `order`
    /// takes (rather than the stored number) and the refusal of `linkedCalendarID` are written out
    /// on `CadenceUpdateContainerOptions`.
    ///
    /// **Everything is validated before the model is touched**, `updateContainerColumns`' shape:
    /// a refusal in the status leg cannot leave a rename half-applied in the context.
    func updateContainer(options: CadenceUpdateContainerOptions) throws -> CadenceContainerSummary {
        let kind = try normalizedContainerKind(options.containerKind)

        // Refused on the *requested* text, before resolution, for `createContainer`'s reason: an
        // areaId sent to an area is a misunderstanding of the shape whether or not that id names a
        // real area, and answering "no area found" would send the caller looking for the wrong bug.
        let requestedAreaID = CadenceMCPServiceSupport.normalizedOptionalText(options.areaId)
        let requestedContextID = CadenceMCPServiceSupport.normalizedOptionalText(options.contextId)
        let requestedDueDate = CadenceMCPServiceSupport.normalizedOptionalText(options.dueDate)
        if kind == "area" {
            if requestedAreaID != nil || options.clearArea {
                throw CadenceWriteError.invalidCombination("areaId applies to a project; an area cannot be filed inside another area.")
            }
            if requestedDueDate != nil || options.clearDueDate {
                throw CadenceWriteError.invalidCombination("dueDate applies to a project; an area is ongoing and carries no due date.")
            }
        }
        if options.clearContext && requestedContextID != nil {
            throw CadenceWriteError.invalidCombination("clearContext cannot be combined with contextId.")
        }
        if options.clearArea && requestedAreaID != nil {
            throw CadenceWriteError.invalidCombination("clearArea cannot be combined with areaId.")
        }
        if options.clearDueDate && requestedDueDate != nil {
            throw CadenceWriteError.invalidCombination("clearDueDate cannot be combined with dueDate.")
        }

        guard let resolved = try resolveContainer(kind: kind, id: options.containerId) else {
            throw CadenceWriteError.invalidCombination("containerId is required.")
        }

        let name = try options.name.map { try normalizedRequiredText($0, emptyError: CadenceWriteError.emptyName) }
        let colorHex = try normalizedOptionalColorHex(options.colorHex)
        let icon = CadenceMCPServiceSupport.normalizedOptionalText(options.icon)
        let newContext = try resolveContext(options.contextId)
        let newArea = try resolveArea(options.areaId)
        let dueDate = try validatedOptionalDate(options.dueDate)
        let statusRaw = try options.status.map { try validatedContainerStatus($0, kind: kind) }

        guard name != nil || options.description != nil || colorHex != nil || icon != nil
            || newContext != nil || options.clearContext
            || newArea != nil || options.clearArea
            || dueDate != nil || options.clearDueDate
            || statusRaw != nil || options.order != nil
            || options.hideDueDateIfEmpty != nil || options.hideSectionDueDateIfEmpty != nil
        else {
            throw CadenceWriteError.noChanges
        }

        // The bucket a position is measured in is the one this call *leaves* the list in, so the
        // move is resolved here — before anything is written — rather than read back off the model
        // afterwards. `nil` is the unfiled bucket, not the absence of one.
        let destinationContextID: UUID?
        if options.clearContext {
            destinationContextID = nil
        } else if let newContext {
            destinationContextID = newContext.id
        } else {
            destinationContextID = contextID(of: resolved)
        }
        let placement = try options.order.map {
            try plannedListOrders(moving: resolved, into: destinationContextID, to: $0)
        }
        // The whole bucket, not the one list the caller named: a placement renumbers the siblings
        // it displaced, and no response of this call reports their new numbers. Restoring only the
        // named list would leave the bucket half-renumbered — the *visible* half, on every surface
        // that sorts on `order`. It is captured and restored here rather than in a snapshot type
        // for `updateContext`'s reason: the frame that reaches the commit is the frame that has to
        // answer for the rearrangement.
        let previousOrders = (placement ?? []).map { (row: $0.row, order: currentOrder(of: $0.row)) }

        let containerID: UUID
        let snapshot: CadenceMCPContainerFieldSnapshot
        let finalName: String
        switch resolved {
        case .area(let area):
            containerID = area.id
            snapshot = CadenceMCPContainerFieldSnapshot(area)
            if let name { area.name = name }
            if let description = options.description { area.desc = description }
            if let colorHex { area.colorHex = colorHex }
            if let icon { area.icon = icon }
            if options.clearContext {
                area.context = nil
            } else if let newContext {
                area.context = newContext
            }
            if let statusRaw { area.statusRaw = statusRaw }
            if let hide = options.hideDueDateIfEmpty { area.hideDueDateIfEmpty = hide }
            if let hide = options.hideSectionDueDateIfEmpty { area.hideSectionDueDateIfEmpty = hide }
            finalName = area.name
        case .project(let project):
            containerID = project.id
            snapshot = CadenceMCPContainerFieldSnapshot(project)
            if let name { project.name = name }
            if let description = options.description { project.desc = description }
            if let colorHex { project.colorHex = colorHex }
            if let icon { project.icon = icon }
            if options.clearContext {
                project.context = nil
            } else if let newContext {
                project.context = newContext
            }
            if options.clearArea {
                project.area = nil
            } else if let newArea {
                project.area = newArea
            }
            if options.clearDueDate {
                project.dueDate = ""
            } else if let dueDate {
                project.dueDate = dueDate
            }
            if let statusRaw { project.statusRaw = statusRaw }
            if let hide = options.hideDueDateIfEmpty { project.hideDueDateIfEmpty = hide }
            if let hide = options.hideSectionDueDateIfEmpty { project.hideSectionDueDateIfEmpty = hide }
            finalName = project.name
        }

        if let placement {
            for entry in placement {
                switch entry.row {
                case .area(let area): area.order = entry.order
                case .project(let project): project.order = entry.order
                }
            }
        }

        try saveNotifyAndAudit([.containerFields(kind: kind, id: containerID, summary: "Updated \(kind): \(finalName)")]) {
            for entry in previousOrders {
                switch entry.row {
                case .area(let area): area.order = entry.order
                case .project(let project): project.order = entry.order
                }
            }
            snapshot.restore()
        }
        return try readService.containerSummary(kind: kind, id: containerID.uuidString)
    }

    /// The status values this kind of list actually has, or a refusal naming them.
    ///
    /// `Area` and `Project` do not share a status enum — `AreaStatus` has three cases and
    /// `ProjectStatus` five — and **both models coerce an unrecognised `statusRaw` to `.active` on
    /// read**. So `status: "paused"` on an area would be stored verbatim and then read back as
    /// `active`: a write the caller was told succeeded whose value the very next read replaces.
    /// That is `create_container`'s argument about a silently dropped argument, one field along.
    private func validatedContainerStatus(_ value: String, kind: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allowed = kind == "area"
            ? AreaStatus.allCases.map(\.rawValue)
            : ProjectStatus.allCases.map(\.rawValue)
        guard allowed.contains(trimmed) else {
            throw CadenceWriteError.invalidContainerStatus(value, allowed)
        }
        return trimmed
    }

    /// Change the kanban columns of a list that already exists: add, rename, recolour, redate,
    /// archive and reorder (T-1095).
    ///
    /// **Why three `Cadence/Shared/` files joined this target's Sources phase for it.**
    /// `docs/TODO.md` T-1095 predicted one — `CadenceSectionConfigMerge` — on the grounds that
    /// mutating an existing list "genuinely needs `base`/`edited`/`current`". **That reason is
    /// wrong, and it is worth writing down why**, because the correct reasons are different and
    /// stronger. This call reads the columns and writes them inside one synchronous frame, so
    /// `base == current` and the merge degenerates to "apply this edit" exactly as it does for
    /// `createContainer` — the case `mutateSectionConfigs`' own comment names. A caller cannot
    /// supply a real `base` either: `CadenceSectionSummary` has never carried a column `uuid`, so
    /// an MCP caller addresses a column by name and holds no snapshot this surface could reconcile.
    ///
    /// What does justify the coupling:
    ///
    /// - **`CadenceSectionEditingSupport.applySectionNameChanges` is not optional.**
    ///   `AppTask.sectionName` is a plain string, so nothing re-points a card when its column is
    ///   renamed. Without it a rename here would strand every card in the column on a name no
    ///   column has — which `CadenceTaskQuerySupport.sectionGroups` draws nowhere at all. That is
    ///   the defect T-1053 fixed on iOS, and it is not a thing a hand-rolled column editor at this
    ///   boundary would have remembered.
    /// - **`mutateSectionConfigs` carries the T-915 guard**: it compares what the *setter would
    ///   store* against what is stored, so a write whose only effect the container's normaliser
    ///   discards does not re-serialise `sectionConfigsRaw` and push a CloudKit record. This
    ///   process writes the store the running app has open; a spurious record here is not free.
    /// - **`CadencePendingChangePersistence.commitEdit` gives the undo this side of the boundary
    ///   has never had.** The MCP write path's equivalent of the app's "name the failure on
    ///   screen" is a thrown error rendered as an `isError` tool response, which it already had.
    ///   What it lacked is the other half: a refused `save()` used to leave the mutation *pending*
    ///   on a long-lived `ModelContext` for the next tool call's `save()` to commit. The columns go
    ///   back, and the cards go back with them, before the caller is told.
    ///
    /// **Everything is validated before the model is touched.** `plannedSectionConfigs` builds the
    /// whole resulting array and throws out of a pure function, so a refusal in the reorder leg
    /// cannot leave a rename half-applied in the context — the single-write shape the per-operation
    /// helpers (`addSectionConfig`, `updateSectionConfig`) could not give, since each writes
    /// separately.
    ///
    /// **The refusals are `create_container`'s argument one door along.** The container's
    /// normaliser silently drops a blank name, a case-insensitive duplicate, and `isCompleted` /
    /// `isArchived` on Default; every one of those is refused here instead, because a caller who
    /// only ever reads the word "success" cannot notice a dropped argument.
    func updateContainerColumns(options: CadenceUpdateContainerColumnsOptions) throws -> CadenceContainerSummary {
        let kind = try normalizedContainerKind(options.containerKind)
        guard let resolved = try resolveContainer(kind: kind, id: options.containerId) else {
            throw CadenceReadError.incompleteContainerFilter
        }
        let container: any CadenceSectionConfigContainer
        let containerID: UUID
        let containerName: String
        // The list's own `tasks` edge rather than a filtered fetch of the whole table: a card can
        // only name a column of the list it is in, and walking the edge is the read this target's
        // guide asks for (`CadenceMCPServer/AGENTS.md`, "Reads go through fetchAll / fetchFirst").
        let tasks: [AppTask]
        switch resolved {
        case .area(let area):
            container = area
            containerID = area.id
            containerName = area.name
            tasks = area.tasks ?? []
        case .project(let project):
            container = project
            containerID = project.id
            containerName = project.name
            tasks = project.tasks ?? []
        }

        let previous = container.sectionConfigs
        let planned = try plannedSectionConfigs(from: previous, options: options)

        container.mutateSectionConfigs { _ in planned }
        // `mutateSectionConfigs` declines a write that would store what is already stored, so this
        // is the answer to "you asked for the colour it already has": nothing changed, said as a
        // refusal rather than as a success with no effect.
        let stored = container.sectionConfigs
        guard stored != previous else { throw CadenceWriteError.noChanges }

        let moves = CadenceSectionConfigMerge.sectionNameMoves(base: previous, merged: stored)
        let movedTaskCount = CadenceSectionEditingSupport.applySectionNameChanges(
            renames: moves.renames,
            removedNames: moves.removedNames,
            to: tasks
        )

        var summary = "Updated \(kind) columns: \(containerName) — \(stored.map(\.name).joined(separator: ", "))"
        if movedTaskCount > 0 {
            summary += " (\(movedTaskCount) re-filed)"
        }
        try saveNotifyAndAudit([.containerColumns(kind: kind, id: containerID, summary: summary)]) {
            container.sectionConfigs = previous
            _ = CadenceSectionEditingSupport.applySectionNameChanges(
                renames: moves.renames.map { (from: $0.to, to: $0.from) },
                removedNames: [],
                to: tasks
            )
        }
        return try readService.containerSummary(kind: kind, id: containerID.uuidString)
    }

    /// The columns this request resolves to, or the first refusal it hits. Touches no model.
    private func plannedSectionConfigs(
        from current: [TaskSectionConfig],
        options: CadenceUpdateContainerColumnsOptions
    ) throws -> [TaskSectionConfig] {
        let requestedColumn = CadenceMCPServiceSupport.normalizedOptionalText(options.columnName)
        let newName = try requiredColumnName(options.newName)
        let colorHex = try normalizedOptionalColorHex(options.colorHex)
        let dueDate = try validatedOptionalDate(options.dueDate)
        let addColumns = try CadenceMCPServiceSupport.normalizedSectionNames(options.addColumns)
        let columnOrder = try CadenceMCPServiceSupport.normalizedSectionNames(options.columnOrder)

        if options.clearDueDate, dueDate != nil {
            throw CadenceWriteError.invalidCombination(
                "dueDate and clearDueDate cannot both be sent for one column."
            )
        }

        let editsOneColumn = newName != nil || colorHex != nil || dueDate != nil || options.clearDueDate
            || options.isCompleted != nil || options.isArchived != nil
        guard editsOneColumn || addColumns != nil || columnOrder != nil else {
            throw CadenceWriteError.noChanges
        }
        if editsOneColumn, requestedColumn == nil {
            throw CadenceWriteError.invalidCombination(
                "columnName names the column newName, colorHex, dueDate, clearDueDate, isCompleted and isArchived apply to, and is required whenever one of them is sent."
            )
        }
        if requestedColumn != nil, !editsOneColumn {
            throw CadenceWriteError.invalidCombination(
                "columnName was sent with nothing to change on it. Send one of newName, colorHex, dueDate, clearDueDate, isCompleted or isArchived beside it."
            )
        }

        var planned = current
        if let requestedColumn {
            guard let index = planned.firstIndex(where: {
                $0.name.caseInsensitiveCompare(requestedColumn) == .orderedSame
            }) else {
                // Every column, archived ones included: `sectionNames` hides an archived column,
                // and un-archiving one is a thing this tool is for.
                throw CadenceWriteError.columnNotFound(requestedColumn, planned.map(\.name))
            }
            var config = planned[index]
            if config.isDefault {
                if newName != nil {
                    throw CadenceWriteError.invalidCombination(
                        "The \(TaskSectionDefaults.defaultName) column cannot be renamed: every task with no section name lands in it, and the list re-creates it under that name on the very next read, so a rename leaves two columns rather than one."
                    )
                }
                if options.isCompleted != nil || options.isArchived != nil {
                    throw CadenceWriteError.invalidCombination(
                        "The \(TaskSectionDefaults.defaultName) column carries no isCompleted or isArchived: it is the bucket every task with no section name falls into, so the list forces both false on every read and every write. See TaskSectionConfig.supportsLifecycle."
                    )
                }
            }
            if let newName {
                let taken = planned.contains {
                    $0.uuid != config.uuid && $0.name.caseInsensitiveCompare(newName) == .orderedSame
                }
                guard !taken else { throw CadenceWriteError.duplicateSectionName(newName) }
                config.name = newName
            }
            if let colorHex { config.colorHex = colorHex }
            if options.clearDueDate {
                config.dueDate = ""
            } else if let dueDate {
                config.dueDate = dueDate
            }
            if let isCompleted = options.isCompleted { config.isCompleted = isCompleted }
            if let isArchived = options.isArchived { config.isArchived = isArchived }
            planned[index] = config
        }

        for name in addColumns ?? [] {
            guard !planned.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                throw CadenceWriteError.duplicateSectionName(name)
            }
            planned.append(TaskSectionConfig(name: name))
        }

        guard let columnOrder else { return planned }
        let plannedNames = planned.map(\.name)
        var remaining = planned
        var ordered: [TaskSectionConfig] = []
        for name in columnOrder {
            guard let index = remaining.firstIndex(where: {
                $0.name.caseInsensitiveCompare(name) == .orderedSame
            }) else {
                throw CadenceWriteError.invalidCombination(
                    "columnOrder names \(name), which this list has no column for once this call's rename and additions are applied. It must name every column exactly once: \(plannedNames.joined(separator: ", "))."
                )
            }
            ordered.append(remaining.remove(at: index))
        }
        guard remaining.isEmpty else {
            throw CadenceWriteError.invalidCombination(
                "columnOrder left out \(remaining.map(\.name).joined(separator: ", ")). It must name every column exactly once: \(plannedNames.joined(separator: ", "))."
            )
        }
        // A partial order is refused above rather than guessed at, and Default is pinned here for
        // the same reason: the container's normaliser moves it to index 0 on every write, so any
        // other position the caller asked for would not be what got stored.
        guard ordered.first?.isDefault == true else {
            throw CadenceWriteError.invalidCombination(
                "columnOrder must start with \(TaskSectionDefaults.defaultName): the list forces that column to the front on every read and every write, so any other position for it would not be stored."
            )
        }
        return ordered
    }

    /// A column name the caller sent, refused rather than dropped when it trims to nothing.
    ///
    /// `Area.normalizedSectionConfigs` discards a blank name, which on iOS used to make
    /// `updateSectionConfig(uuid:) { $0.name = "   " }` a *delete* (T-1053). `CadenceSectionConfigMerge`
    /// withholds it instead. Neither is the right answer to a request: this surface says so.
    private func requiredColumnName(_ value: String?) throws -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CadenceWriteError.emptySectionName }
        return trimmed
    }

    /// Attach a saved link to an `Area` or a `Project` (T-1122).
    ///
    /// **Why this one of the six, and not the other five.** T-1122 names six model types the write
    /// surface cannot mint — goal, habit, tag, saved link, list note and task bundle — and says
    /// doing even one turns a list tool from a source scan into an execution, which is the argument
    /// for starting with the cheapest. `SavedLink` is the cheapest by a distance: five stored
    /// fields, one of which is the owning list, no lifecycle, no completion history, no cascade and
    /// no helper it has to go through.
    ///
    /// **The ranking was applied again and two more of the six followed** — `createGoal` and
    /// `createHabit`, below, which share one four-file dependency closure. The remaining three are
    /// refused with a measurement each in `docs/TODO.md`, not left undecided: a tag, a list note
    /// and a task bundle each need a helper whose *file* carries something a headless tool must not
    /// compile, or a create rule that has no owner to go through. Read the entry before reopening
    /// any of the three.
    ///
    /// The URL rule, the required container and the unused persistence half are on
    /// `CadenceCreateSavedLinkOptions`.
    func createSavedLink(options: CadenceCreateSavedLinkOptions) throws -> CadenceSavedLinkSummary {
        let kind = try normalizedContainerKind(options.containerKind)
        guard let resolved = try resolveContainer(kind: kind, id: options.containerId) else {
            throw CadenceWriteError.invalidCombination("containerId is required.")
        }
        guard let url = CadenceSavedLinkURL.normalized(options.url) else {
            throw CadenceWriteError.emptyURL
        }
        let title = CadenceTitleNormalization.display(options.title ?? "", fallback: url)

        // **The order is read before the relationship is assigned, and the order of these two
        // lines is load-bearing.** SwiftData back-populates the inverse synchronously inside the
        // owning context — the measurement `Cadence/Models/AGENTS.md` records for `Subtask`
        // (T-387) — so `project.links` already contains this link if it is assigned first, and
        // max-plus-one over a list that includes the row being numbered allocates 1, then 2, and
        // never 0. Measured here, not assumed: the first spelling of this arm did exactly that.
        let link = SavedLink(title: title, url: url)
        switch resolved {
        case .area(let area):
            link.order = nextLinkOrder(among: area.links)
            link.area = area
        case .project(let project):
            link.order = nextLinkOrder(among: project.links)
            link.project = project
        }
        context.insert(link)

        try saveNotifyAndAudit(
            .savedLink(id: link.id, summary: "Created link on \(kind): \(title)"),
            inserted: [link]
        )
        return try readService.savedLinkSummary(linkID: link.id.uuidString)
    }

    /// Mint a goal — a top-level direction, or a milestone of one (T-1122).
    ///
    /// **Why goal and habit, and not the other three.** T-1122's method is to rank what is left by
    /// cost and build outward from the cheapest, stopping at the first whose blocker can be
    /// *measured*. These two share one helper file and one dependency closure, so the second is
    /// nearly free once the first is paid for; the three that remain each have a blocker recorded
    /// in `docs/TODO.md` with the measurement behind it, rather than an assertion that they are
    /// hard.
    ///
    /// **The write goes through `CadenceTrackingMutationSupport.saveGoal`, not a second copy of
    /// it.** That function owns four rules no reader of this file would guess: `endDate` is pulled
    /// forward to `startDate` when it precedes it, `targetHours` floors at zero, an omitted context
    /// is inherited from the parent goal, and a goal handed itself as a parent is silently
    /// un-parented rather than left to make `GoalContributionResolver` walk a cycle. Re-spelling
    /// any of those here is what T-1122 pulled `CadenceSavedLinkURL.normalized` in to stop.
    ///
    /// **`commit: { _ in }`, exactly as `appendCoreNote` defers `NoteMigrationService` (T-1181).**
    /// The helper would otherwise commit on its own behalf, and `saveNotifyAndAudit` owns the
    /// commit on this surface because it also audits, wakes the app, and un-inserts a refused row.
    /// The goal therefore travels to `saveNotifyAndAudit` as a pending insert in this call's own
    /// `inserted:` list; no `undo` is needed because a create has nothing to put back.
    func createGoal(options: CadenceCreateGoalOptions) throws -> CadenceGoalDetail {
        let title = try normalizedRequiredText(options.title, emptyError: CadenceWriteError.emptyTitleFor("Goal"))
        let kind = try validateGoalKind(options.kind)
        let status = try validateGoalStatus(options.status)
        let progressType = try validateGoalProgressType(options.progressType)
        let startDate = try validatedOptionalDate(options.startDate) ?? ""
        let endDate = try validatedOptionalDate(options.endDate) ?? ""
        let colorHex = try normalizedOptionalColorHex(options.colorHex)
        let icon = CadenceMCPServiceSupport.normalizedOptionalText(options.icon)
        let parentContext = try resolveContext(options.contextId)
        let parentGoal = try resolveGoal(options.parentGoalId)

        // Asked of `GoalAssignmentRules` rather than of `parentGoal.parentGoal == nil` here, because
        // that is the one function both editors ask since T-1327 — and a third surface spelling the
        // same test itself is precisely how the goal → milestone → sub-milestone trees that T-1337
        // had to flatten came to exist. `saveGoal` guards only the self-parenting cycle, never depth.
        if let parentGoal, !GoalAssignmentRules.canOwnMilestones(parentGoal) {
            throw CadenceWriteError.goalCannotOwnMilestones(parentGoal.id.uuidString)
        }

        // `saveGoal` writes every field unconditionally, so an omitted `icon`/`colorHex` still needs
        // a value to hand it. It is read off an uninserted `Goal` rather than restated: a hex
        // literal here would be both a second copy of the model's declared default and a hardcoded
        // colour outside `Theme.swift`, which the root `AGENTS.md` forbids outright.
        let modelDefaults = Goal(title: "")

        guard let goal = try CadenceTrackingMutationSupport.saveGoal(
            nil,
            title: title,
            desc: options.description ?? "",
            startDate: startDate,
            endDate: endDate,
            progressType: progressType,
            targetHours: options.targetHours ?? 0,
            icon: icon ?? modelDefaults.icon,
            colorHex: colorHex ?? modelDefaults.colorHex,
            kind: kind,
            status: status,
            context: parentContext,
            parentGoal: parentGoal,
            allGoals: try fetchGoals(),
            modelContext: context,
            commit: { _ in }
        ) else {
            // Unreachable while `normalizedRequiredText` runs first — `nil` is the helper's only
            // other answer and it means the title trimmed to nothing. Said again rather than
            // force-unwrapped, so the arm stays total if either half of that pairing moves.
            throw CadenceWriteError.emptyTitleFor("Goal")
        }

        try saveNotifyAndAudit(
            .goal(id: goal.id, summary: "Created goal: \(title)"),
            inserted: [goal]
        )
        return try readService.getGoal(goalID: goal.id.uuidString)
    }

    /// Mint a habit (T-1122). `createGoal`'s sibling, and every sentence on it applies here:
    /// `CadenceTrackingMutationSupport.saveHabit` owns the rules — `targetCount` floors at one, an
    /// omitted context is inherited from the goal — and its commit is deferred so
    /// `saveNotifyAndAudit` remains the only commit on this surface.
    ///
    /// **No notification is scheduled above the commit, or below it, because none is scheduled at
    /// all.** T-1348 found reminder *cancellations* running before the commit that would justify
    /// them; the mirrored hazard for a create is a reminder scheduled for a row the store then
    /// refuses. This arm cannot hit it: a habit's reminder lives in `reminderMinuteOfDay`, which
    /// `CadenceCreateHabitOptions` does not carry and `saveHabit` does not write, so a habit made
    /// here is reminder-less and `HabitNotificationPlanner.reminder(for:now:)` returns `nil` for it
    /// the next time the app reconciles. The reasoning for leaving that field off is on the options
    /// type.
    func createHabit(options: CadenceCreateHabitOptions) throws -> CadenceHabitSummary {
        let title = try normalizedRequiredText(options.title, emptyError: CadenceWriteError.emptyTitleFor("Habit"))
        let frequencyType = try validateHabitFrequency(options.frequencyType)
        let colorHex = try normalizedOptionalColorHex(options.colorHex)
        let icon = CadenceMCPServiceSupport.normalizedOptionalText(options.icon)
        let parentContext = try resolveContext(options.contextId)
        let goal = try resolveGoal(options.goalId)
        let modelDefaults = Habit(title: "")

        guard let habit = try CadenceTrackingMutationSupport.saveHabit(
            nil,
            title: title,
            icon: icon ?? modelDefaults.icon,
            colorHex: colorHex ?? modelDefaults.colorHex,
            frequencyType: frequencyType,
            frequencyDays: options.frequencyDays ?? modelDefaults.frequencyDays,
            targetCount: options.targetCount ?? modelDefaults.targetCount,
            context: parentContext,
            goal: goal,
            allHabits: try fetchHabits(),
            modelContext: context,
            commit: { _ in }
        ) else {
            throw CadenceWriteError.emptyTitleFor("Habit")
        }

        try saveNotifyAndAudit(
            .habit(id: habit.id, summary: "Created habit: \(title)"),
            inserted: [habit]
        )
        return try readService.habitSummary(habitID: habit.id.uuidString)
    }

    func createTask(options: CadenceCreateTaskOptions) throws -> CadenceTaskDetail {
        let title = try normalizedRequiredText(options.title, emptyError: CadenceWriteError.emptyTitle)
        let priority = try options.priority.map(validatePriority) ?? .none
        let dueDate = try validatedOptionalDate(options.dueDate)
        let scheduledDate = try validatedOptionalDate(options.scheduledDate)
        let scheduledStartMin = try validateOptionalScheduledStart(options.scheduledStartMin)
        let estimatedMinutes = try validateEstimatedMinutes(options.estimatedMinutes ?? 30)
        let container = try resolveContainer(kind: options.containerKind, id: options.containerId)
        let sectionName = try normalizedSectionName(options.sectionName, container: container)
        let subtaskTitles = normalizedSubtaskTitles(options.subtaskTitles ?? [])

        if scheduledStartMin != nil && scheduledDate == nil {
            throw CadenceWriteError.invalidCombination("scheduledDate is required when scheduledStartMin is provided.")
        }

        // Resolved before anything is built, so an unreadable tag table fails the call rather than
        // producing an untagged task the caller is told it tagged (T-307).
        let tags = try resolvedTags(named: options.tagNames ?? [])

        let task = AppTask(title: title)
        task.notes = options.notes ?? ""
        task.priority = priority
        task.dueDate = dueDate ?? ""
        task.scheduledDate = scheduledDate ?? ""
        task.scheduledStartMin = scheduledStartMin ?? -1
        task.estimatedMinutes = estimatedMinutes
        task.sectionName = sectionName
        apply(container: container, to: task)
        task.tags = tags

        context.insert(task)
        // NOT `CadenceTaskMutationSupport.insertSubtasks` — that file is not in this target's
        // Sources phase and cannot be, because it reaches `NotificationManager`, which reads
        // `UserDefaults.standard` and so cannot exist in a command-line target. Routing this call
        // through it broke the `CadenceMCPServer` build in aaa0064 while `-scheme Cadence` stayed
        // green, which is the silence `CadenceMCPServer/AGENTS.md` warns about. Both sides of the
        // relationship are still written here by hand; see T-401 for why that is a convention
        // rather than a repair.
        var insertedSubtasks: [Subtask] = []
        for (index, subtaskTitle) in subtaskTitles.enumerated() {
            let subtask = Subtask(title: subtaskTitle)
            subtask.parentTask = task
            subtask.order = index
            context.insert(subtask)
            task.subtasks = (task.subtasks ?? []) + [subtask]
            insertedSubtasks.append(subtask)
        }

        // The subtasks go in the list too, not just the task: `commitInsert` takes a list for
        // exactly this case, and un-inserting only the root would strand the rest as orphans in a
        // context that outlives the call (T-1121).
        try saveNotifyAndAudit(
            .task(tool: "create_task", id: task.id, summary: "Created task: \(task.title)"),
            inserted: [task] + insertedSubtasks
        )
        return try readService.getTask(taskID: task.id.uuidString)
    }

    func updateTask(options: CadenceUpdateTaskOptions) throws -> CadenceTaskDetail {
        let task = try findTask(options.taskId)

        let title = try options.title.map { try normalizedRequiredText($0, emptyError: CadenceWriteError.emptyTitle) }
        let priority = try options.priority.map(validatePriority)
        let dueDate = try validatedOptionalDate(options.dueDate)
        let estimatedMinutes = try options.estimatedMinutes.map(validateEstimatedMinutes)
        let container = try resolveContainer(kind: options.containerKind, id: options.containerId)

        if options.clearDueDate && dueDate != nil {
            throw CadenceWriteError.invalidCombination("clearDueDate cannot be combined with dueDate.")
        }
        if options.clearContainer && container != nil {
            throw CadenceWriteError.invalidCombination("clearContainer cannot be combined with containerKind/containerId.")
        }

        let finalContainer: CadenceResolvedContainer?
        if options.clearContainer {
            finalContainer = nil
        } else if let container {
            finalContainer = container
        } else {
            finalContainer = currentContainer(for: task)
        }
        let sectionName = try options.sectionName.map { try normalizedSectionName($0, container: finalContainer) }

        guard title != nil || options.notes != nil || priority != nil || dueDate != nil || options.clearDueDate || estimatedMinutes != nil || container != nil || options.clearContainer || sectionName != nil || options.tagNames != nil else {
            throw CadenceWriteError.noChanges
        }

        // Same reason as createTask: the throw has to happen while the task is still untouched.
        let tags = try options.tagNames.map { try resolvedTags(named: $0) }

        let snapshot = CadenceMCPTaskFieldSnapshot(task)
        if let title { task.title = title }
        if let notes = options.notes { task.notes = notes }
        if let priority { task.priority = priority }
        if options.clearDueDate {
            task.dueDate = ""
        } else if let dueDate {
            task.dueDate = dueDate
        }
        if let estimatedMinutes { task.estimatedMinutes = estimatedMinutes }
        if options.clearContainer {
            apply(container: nil, to: task)
        } else if let container {
            apply(container: container, to: task)
        }
        if let sectionName {
            task.sectionName = sectionName
        } else if options.clearContainer {
            task.sectionName = TaskSectionDefaults.defaultName
        }
        if let tags {
            task.tags = tags
        }

        try saveNotifyAndAudit([.task(tool: "update_task", id: task.id, summary: "Updated task: \(task.title)")]) {
            snapshot.restore()
        }
        return try readService.getTask(taskID: task.id.uuidString)
    }

    func scheduleTask(options: CadenceScheduleTaskOptions) throws -> CadenceTaskDetail {
        let task = try findTask(options.taskId)
        let scheduledDate = try validatedOptionalDate(options.scheduledDate)
        let scheduledStartMin = try validateOptionalScheduledStart(options.scheduledStartMin)
        let estimatedMinutes = try options.estimatedMinutes.map(validateEstimatedMinutes)

        if options.clearScheduledDate && (scheduledDate != nil || scheduledStartMin != nil || estimatedMinutes != nil) {
            throw CadenceWriteError.invalidCombination("clearScheduledDate cannot be combined with scheduledDate, scheduledStartMin, or estimatedMinutes.")
        }
        if scheduledStartMin != nil && scheduledDate == nil {
            throw CadenceWriteError.invalidCombination("scheduledDate is required when scheduledStartMin is provided.")
        }
        guard options.clearScheduledDate || scheduledDate != nil || scheduledStartMin != nil || estimatedMinutes != nil else {
            throw CadenceWriteError.noChanges
        }

        let snapshot = CadenceMCPTaskFieldSnapshot(task)
        if options.clearScheduledDate {
            task.scheduledDate = ""
            task.scheduledStartMin = -1
        } else {
            if let scheduledDate {
                task.scheduledDate = scheduledDate
            }
            if let scheduledStartMin {
                task.scheduledStartMin = scheduledStartMin
            }
            if let estimatedMinutes {
                task.estimatedMinutes = estimatedMinutes
            }
        }

        try saveNotifyAndAudit([.task(tool: "schedule_task", id: task.id, summary: "Scheduled task: \(task.title)")]) {
            snapshot.restore()
        }
        return try readService.getTask(taskID: task.id.uuidString)
    }

    func completeTask(taskID: String) throws -> CadenceCompleteTaskResult {
        let task = try findTask(taskID)
        guard !task.isCancelled else {
            throw CadenceWriteError.cannotCompleteCancelledTask(taskID)
        }

        var spawnedTaskID: UUID?
        var didChange = false
        // The successor is taken from `markDone`'s return value rather than re-derived from the
        // pointer, because a refused commit has to un-insert the object and only the object can be
        // handed to `commitInsert` (T-628, T-1121).
        var spawnedTask: AppTask?
        var snapshot: CadenceMCPTaskFieldSnapshot?
        if !task.isDone {
            snapshot = CadenceMCPTaskFieldSnapshot(task)
            spawnedTask = CadenceTaskRecurrenceWorkflowSupport.markDone(task, in: context)
            didChange = true
            spawnedTaskID = spawnedTask?.id
        }

        if didChange {
            var auditEntries: [PendingAuditEntry] = [
                .task(tool: "complete_task", id: task.id, summary: "Completed task: \(task.title)")
            ]
            if let spawnedTaskID {
                auditEntries.append(.task(tool: "complete_task", id: spawnedTaskID, summary: "Spawned recurring task from: \(task.title)"))
            }
            try saveNotifyAndAudit(auditEntries, inserted: spawnedTask.map { [$0] } ?? []) {
                snapshot?.restore()
            }
        }
        return CadenceCompleteTaskResult(
            task: try readService.getTask(taskID: task.id.uuidString),
            spawnedRecurringTask: try spawnedTaskID.map { try readService.getTask(taskID: $0.uuidString) }
        )
    }

    func reopenTask(taskID: String) throws -> CadenceTaskDetail {
        let task = try findTask(taskID)
        if task.completedAt != nil || task.status != .todo {
            let snapshot = CadenceMCPTaskFieldSnapshot(task)
            task.completedAt = nil
            task.status = .todo
            try saveNotifyAndAudit([.task(tool: "reopen_task", id: task.id, summary: "Reopened task: \(task.title)")]) {
                snapshot.restore()
            }
        }
        return try readService.getTask(taskID: task.id.uuidString)
    }

    func cancelTask(taskID: String) throws -> CadenceTaskDetail {
        let task = try findTask(taskID)
        // `status` alone, not `status != .cancelled || completedAt != nil`: since T-202 a cancelled
        // task *carries* a `completedAt`, so the old spelling was true of every already-cancelled
        // task and re-cancelling one would re-stamp its timestamp and write a second audit entry.
        if task.status != .cancelled {
            let snapshot = CadenceMCPTaskFieldSnapshot(task)
            // Cancelling a single occurrence still advances a recurring series (mirrors completeTask),
            // otherwise cancelling instead of completing one occurrence would silently kill all future ones.
            // The returned successor is what a refused commit un-inserts; see completeTask.
            let spawnedTask = CadenceTaskRecurrenceWorkflowSupport.markCancelled(task, in: context)

            var auditEntries: [PendingAuditEntry] = [
                .task(tool: "cancel_task", id: task.id, summary: "Cancelled task: \(task.title)")
            ]
            if let spawnedTask {
                auditEntries.append(.task(tool: "cancel_task", id: spawnedTask.id, summary: "Spawned recurring task from: \(task.title)"))
            }
            try saveNotifyAndAudit(auditEntries, inserted: spawnedTask.map { [$0] } ?? []) {
                snapshot.restore()
            }
        }
        return try readService.getTask(taskID: task.id.uuidString)
    }

    /// Cancel a named set of tasks, or every task whose title starts with a prefix.
    ///
    /// **This is the only arm on the surface that takes a pattern, and until T-1365 the only thing
    /// standing between a prefix and the whole table was `prefix.count >= 8`.** That floor was
    /// chosen against *typos* — it stops `MCP` matching everything with an `MCP` in front — and a
    /// longer prefix is not a smaller selection, so raising it would not have made it a breadth
    /// control. Nothing capped the count; `CadenceBulkCancelResult` reported it afterwards.
    ///
    /// Two halves, and they are not alternatives:
    ///
    /// - **The prefix branch refuses above `CadenceMCPServiceSupport.maximumPageSize`, naming the
    ///   number it matched.** Structural refusal, the way `updateContainerColumns` refuses rather
    ///   than half-applies. The bound is the read surface's own page ceiling on purpose: an
    ///   executed pattern cancellation may not exceed what the caller could have read back in one
    ///   look. The **`taskIds` branch stays uncapped** — there the caller named every entity, which
    ///   is the standard every other write arm here is held to.
    /// - **`dryRun` resolves the selection and cancels nothing**, and is *not* capped, because a
    ///   preview that refuses to describe a large selection withholds exactly the measurement the
    ///   cap exists to make actionable. That is what turns the prefix into a finder above the cap:
    ///   dry-run it, then send the `taskIds` you meant. A cap alone leaves a headless caller
    ///   guessing at a selection it has no UI to inspect; a dry run alone is advisory and nothing
    ///   makes a caller use it. Neither half is sufficient, which is why both are here.
    ///
    /// A dry run over an empty selection answers with an empty selection rather than `noChanges`:
    /// "your prefix matches nothing" is the question it was asked, and turning it into `isError`
    /// makes a typo'd prefix indistinguishable from a malformed request.
    ///
    /// Its cost is proportional to what it is asked to show, which is the one place on this surface
    /// that is not bounded. It is deliberate: the unbounded read lives on the branch that mutates
    /// nothing, and truncating it silently is the failure T-385 was filed about.
    func bulkCancelTasks(options: CadenceBulkCancelTaskOptions) throws -> CadenceBulkCancelResult {
        let tasks = try fetchTasks()
        let ids = options.taskIds?.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } ?? []
        let prefix = options.titlePrefix?.trimmingCharacters(in: .whitespacesAndNewlines)

        if !ids.isEmpty && prefix?.isEmpty == false {
            throw CadenceWriteError.invalidCombination("taskIds and titlePrefix cannot be combined.")
        }
        if ids.isEmpty && prefix?.isEmpty != false {
            throw CadenceWriteError.invalidCombination("Provide taskIds or titlePrefix.")
        }

        let selectedTasks: [AppTask]
        if !ids.isEmpty {
            var seen = Set<UUID>()
            let requestedIDs = try ids.map(uuid).filter { seen.insert($0).inserted }
            selectedTasks = try requestedIDs.map { id in
                guard let task = tasks.first(where: { $0.id == id }) else {
                    throw CadenceReadError.taskNotFound(id.uuidString)
                }
                return task
            }
        } else {
            guard let prefix else { throw CadenceWriteError.invalidCombination("Provide taskIds or titlePrefix.") }
            guard prefix.count >= 8 else {
                throw CadenceWriteError.invalidCombination("titlePrefix must be at least 8 characters for bulk cancellation.")
            }
            let normalizedPrefix = prefix.lowercased()
            selectedTasks = tasks.filter {
                !$0.isCancelled && $0.title.lowercased().hasPrefix(normalizedPrefix)
            }
            // The breadth control, and only on the branch that executes: see this function's note.
            let limit = CadenceMCPServiceSupport.maximumPageSize
            if !options.dryRun, selectedTasks.count > limit {
                throw CadenceWriteError.bulkSelectionTooBroad(matched: selectedTasks.count, limit: limit)
            }
        }

        if options.dryRun {
            // Resolved by the executor's own matcher and returned without a commit, an audit entry
            // or a spawned successor. The empty selection is an answer here, not a refusal.
            return CadenceBulkCancelResult(
                dryRun: true,
                matchedTasks: try selectedTasks.map { try readService.getTask(taskID: $0.id.uuidString).summary },
                cancelledTasks: []
            )
        }

        guard !selectedTasks.isEmpty else {
            throw CadenceWriteError.noChanges
        }

        var changed: [AppTask] = []
        var snapshots: [CadenceMCPTaskFieldSnapshot] = []
        var spawnedTasks: [AppTask] = []
        var auditEntries: [PendingAuditEntry] = []
        // `status` alone, for the same reason as `cancelTask` above (T-202): a cancelled task now
        // has a non-nil `completedAt`, so `|| task.completedAt != nil` matched every one of them.
        for task in selectedTasks where task.status != .cancelled {
            // Mirror cancelTask's single-task behavior: route through the shared recurrence
            // workflow instead of setting status/completedAt directly, otherwise bulk-cancelling
            // a recurring task silently kills the rest of its series (it never spawns the next
            // occurrence the way completeTask/cancelTask do).
            snapshots.append(CadenceMCPTaskFieldSnapshot(task))
            let spawnedTask = CadenceTaskRecurrenceWorkflowSupport.markCancelled(task, in: context)
            changed.append(task)
            auditEntries.append(.task(tool: "bulk_cancel_tasks", id: task.id, summary: "Bulk cancelled task: \(task.title)"))
            if let spawnedTask {
                spawnedTasks.append(spawnedTask)
                auditEntries.append(.task(tool: "bulk_cancel_tasks", id: spawnedTask.id, summary: "Spawned recurring task from: \(task.title)"))
            }
        }

        if !changed.isEmpty {
            // One commit for the whole batch, so one undo for the whole batch: every cancellation
            // goes back and every successor is un-inserted, rather than the store keeping whichever
            // prefix of a refused bulk call happened to be pending (T-1121).
            try saveNotifyAndAudit(auditEntries, inserted: spawnedTasks) {
                for snapshot in snapshots {
                    snapshot.restore()
                }
            }
        }

        let summaries = try selectedTasks.map { try readService.getTask(taskID: $0.id.uuidString).summary }
        return CadenceBulkCancelResult(dryRun: false, matchedTasks: summaries, cancelledTasks: summaries)
    }

    /// Append to a daily, weekly or permanent core note.
    ///
    /// **This arm used to have a half it could not undo, and now it has none (T-1121, T-1181).**
    /// The *append* is an ordinary in-place edit and is restored exactly like every other one here.
    /// The note **row** was not: `NoteMigrationService.dailyNote` / `weeklyNote` / `permanentNote`
    /// created a missing core note and `try context.save()`d it themselves before this function saw
    /// it, so by the time the append's commit was refused that row was already in the store and no
    /// undo here could take it back. The caller got `coreNoteCreatedButNotAppended` instead of a
    /// plain failure — honest about the residue, but still a residue.
    ///
    /// **The fix is one commit for the whole unit, not a better sentence about two.** Those three
    /// accessors take a `commit:` now, so this arm hands them `{ _ in }` — the note is *inserted*
    /// and left pending — and then carries it in `saveNotifyAndAudit`'s own `inserted:` list. One
    /// refusal, one undo: `commitInsert` un-inserts the note this call created and `commitEdit`
    /// restores the text of one it did not. Nothing is left in the store and nothing is left
    /// pending, so the error case that named the residue is gone rather than reworded.
    ///
    /// The note's own fields need no `undo` when this call created it — the row ceases to exist —
    /// and restoring them would be writing through a reference `commitInsert` has just deleted.
    func appendCoreNote(kind: String, content: String, dateKey: String? = nil, separator: String? = nil) throws -> CadenceCoreNotesSnapshot {
        let normalizedKind = try normalizeNoteKind(kind)
        let text = try normalizedRequiredText(content, emptyError: CadenceWriteError.emptyContent)
        let resolvedDateKey = try resolvedDateKey(dateKey)
        let separator = separator ?? "\n\n"
        let now = Date()
        let auditEntry: PendingAuditEntry
        let note: Note

        // `{ _ in }` rather than this service's own `commit`: the accessor is only being asked
        // which note today's is, and a commit it made on its own behalf would land the row before
        // the append below has been written, which is the state T-1181 removed.
        let deferCommit: (ModelContext) throws -> Void = { _ in }

        switch normalizedKind {
        case "daily":
            note = try NoteMigrationService.dailyNote(for: resolvedDateKey, in: context, commit: deferCommit)
            auditEntry = .coreNote(id: note.id, summary: "Appended daily core note: \(resolvedDateKey)")
        case "weekly":
            let resolvedWeekKey = try weekKey(for: resolvedDateKey)
            note = try NoteMigrationService.weeklyNote(for: resolvedWeekKey, in: context, commit: deferCommit)
            auditEntry = .coreNote(id: note.id, summary: "Appended weekly core note: \(resolvedWeekKey)")
        case "permanent":
            note = try NoteMigrationService.permanentNote(in: context, commit: deferCommit)
            auditEntry = .coreNote(id: note.id, summary: "Appended permanent core note")
        default:
            throw CadenceWriteError.invalidNoteKind(kind)
        }

        // Asked of the context's pending inserts rather than by counting rows either side of the
        // accessor, and for the same reason `CadenceTaskFieldEditCommit.pendingInsertedTask` does:
        // with the commit deferred, a row this call created is *only* a pending insert, and a
        // count over the store could not see it at all.
        let createdTheNote = context.insertedModelsArray.contains { ($0 as? Note)?.id == note.id }

        let previousContent = note.content
        let previousUpdatedAt = note.updatedAt
        var content = note.content
        append(text, separator: separator, to: &content)
        note.content = content
        note.updatedAt = now

        try saveNotifyAndAudit(
            [auditEntry],
            inserted: createdTheNote ? [note] : [],
            undo: createdTheNote ? {} : {
                note.content = previousContent
                note.updatedAt = previousUpdatedAt
            }
        )
        return try readService.coreNotes(dateKey: resolvedDateKey)
    }

    private func saveNotifyAndAudit(_ entry: PendingAuditEntry, inserted: [any PersistentModel] = []) throws {
        try saveNotifyAndAudit([entry], inserted: inserted)
    }

    /// Commit, wake the app, and record what was written.
    ///
    /// **Both halves of an undo, because an arm here can do both (T-1121).** `inserted` is every
    /// row this call added and `undo` is what it changed in place; a refused commit un-inserts the
    /// first and restores the second, in that order, before the caller is told anything. Nothing on
    /// this surface is allowed to leave a change *pending*: this service holds one long-lived
    /// `ModelContext` per server process, so an abandoned insert waits for the next unrelated tool
    /// call's `save()` — a write the caller was told had failed, arriving later under another
    /// call's name in `mcp-audit.log`.
    ///
    /// **The two `CadencePendingChangePersistence` primitives are composed, not re-spelled.**
    /// `commitInsert` deletes the models it was given and rethrows; `commitEdit` then runs `undo`
    /// and rethrows. Nesting them is what lets `completeTask` — an in-place status change *and* a
    /// spawned successor — have one undo covering both, without a third copy of either sentence.
    /// Neither defaults to a `rollback()`, for the reason `commitEdit` gives: it would discard
    /// whatever else is pending in the same context.
    ///
    /// **There is no longer an effect this misses** (T-1181). The one exception used to be the
    /// core-note row `NoteMigrationService` committed on its own behalf; those accessors take a
    /// `commit:` now, so `appendCoreNote` defers that insert into this call's own `inserted:` list
    /// and every arm on this surface fails clean.
    private func saveNotifyAndAudit(
        _ entries: [PendingAuditEntry],
        inserted: [any PersistentModel] = [],
        undo: () -> Void = {}
    ) throws {
        try CadencePendingChangePersistence.commitEdit(
            in: context,
            commit: { try CadencePendingChangePersistence.commitInsert(of: inserted, in: $0, commit: commit) },
            undo: undo
        )
        if notifiesExternalWrites {
            CadenceModelContainerFactory.notifyExternalWrite()
        }
        for entry in entries {
            recordAudit(entry)
        }
    }

    private func recordAudit(_ entry: PendingAuditEntry) {
        guard let auditLogger else { return }
        do {
            try auditLogger.record(
                tool: entry.tool,
                entityType: entry.entityType,
                entityId: entry.entityId,
                summary: entry.summary
            )
        } catch {
            let message = "Cadence MCP audit log failed: \(error.localizedDescription)\n"
            FileHandle.standardError.write(Data(message.utf8))
        }
    }

    private func findTask(_ taskID: String) throws -> AppTask {
        let id = try uuid(from: taskID)
        guard let task = try fetchTasks().first(where: { $0.id == id }) else {
            throw CadenceReadError.taskNotFound(taskID)
        }
        return task
    }

    private func fetchTasks() throws -> [AppTask] {
        try context.fetch(FetchDescriptor<AppTask>())
    }

    private func fetchAreas() throws -> [Area] {
        try context.fetch(FetchDescriptor<Area>())
    }

    private func fetchProjects() throws -> [Project] {
        try context.fetch(FetchDescriptor<Project>())
    }

    private func fetchContexts() throws -> [Context] {
        try context.fetch(FetchDescriptor<Context>())
    }

    private func fetchGoals() throws -> [Goal] {
        try context.fetch(FetchDescriptor<Goal>())
    }

    private func fetchHabits() throws -> [Habit] {
        try context.fetch(FetchDescriptor<Habit>())
    }

    private func resolveGoal(_ id: String?) throws -> Goal? {
        guard let requested = CadenceMCPServiceSupport.normalizedOptionalText(id) else { return nil }
        let uuid = try uuid(from: requested)
        guard let match = try fetchGoals().first(where: { $0.id == uuid }) else {
            throw CadenceReadError.goalNotFound(requested)
        }
        return match
    }

    /// The four tracking enums, each refused by name rather than coerced.
    ///
    /// `Goal` and `Habit` store these as raw strings and their computed façades fall back to a
    /// default on an unrecognised value — `GoalKind(rawValue:) ?? .completable` and the three like
    /// it. That fallback exists so a row written by an older build still reads; applying it to a
    /// *request* would turn a caller's typo into a silently different goal, which is the shape
    /// `validatePriority` already refuses for tasks.
    private func validateGoalKind(_ value: String?) throws -> GoalKind {
        guard let raw = CadenceMCPServiceSupport.normalizedOptionalText(value) else { return .completable }
        guard let kind = GoalKind(rawValue: raw) else { throw CadenceWriteError.invalidGoalKind(raw) }
        return kind
    }

    private func validateGoalStatus(_ value: String?) throws -> GoalStatus {
        guard let raw = CadenceMCPServiceSupport.normalizedOptionalText(value) else { return .active }
        guard let status = GoalStatus(rawValue: raw) else { throw CadenceWriteError.invalidGoalStatus(raw) }
        return status
    }

    private func validateGoalProgressType(_ value: String?) throws -> GoalProgressType {
        guard let raw = CadenceMCPServiceSupport.normalizedOptionalText(value) else { return .subtasks }
        guard let type = GoalProgressType(rawValue: raw) else { throw CadenceWriteError.invalidGoalProgressType(raw) }
        return type
    }

    private func validateHabitFrequency(_ value: String?) throws -> HabitFrequency {
        guard let raw = CadenceMCPServiceSupport.normalizedOptionalText(value) else { return .daily }
        guard let frequency = HabitFrequency(rawValue: raw) else { throw CadenceWriteError.invalidHabitFrequency(raw) }
        return frequency
    }

    private func nextContextOrder() throws -> Int {
        (try fetchContexts().map(\.order).max() ?? -1) + 1
    }

    /// One past the highest `order` among the lists the new one will sit beside.
    ///
    /// Areas and projects share one sequence per context, and the comparison is
    /// **optional-to-optional** on purpose — `nil == nil` is the unfiled bucket, numbered exactly
    /// like a filed one. `CreateListSheet.nextListOrder` spells the same rule for the same reason:
    /// walking `context.areas` instead would leave every context-less list created at 0.
    private func nextListOrder(inContextWithID id: UUID?) throws -> Int {
        var orders = try fetchAreas().filter { $0.context?.id == id }.map(\.order)
        orders += try fetchProjects().filter { $0.context?.id == id }.map(\.order)
        return (orders.max() ?? -1) + 1
    }

    /// One past the highest `order` among the links already on this list, max-plus-one for
    /// `nextListOrder`'s reason: `count` re-uses a number as soon as anything has been deleted.
    private func nextLinkOrder(among links: [SavedLink]?) -> Int {
        ((links ?? []).map(\.order).max() ?? -1) + 1
    }

    /// The whole destination bucket, renumbered densely from zero with `target` at `position`.
    ///
    /// Computed and returned rather than applied, so the caller can refuse before it writes and can
    /// snapshot exactly the rows it is about to change. The siblings are put in
    /// `CadenceMCPOrdering.precedes` order first — the same total order every read of this surface
    /// answers in — so "position 2" means the third row the caller last saw, and the result is
    /// independent of the order the store handed the rows over in.
    ///
    /// `target` is excluded from the sibling scan and re-inserted, which is what makes a move and a
    /// re-position one operation: a list already in this bucket is not counted twice, and one
    /// arriving from elsewhere is counted once.
    private func plannedListOrders(
        moving target: CadenceResolvedContainer,
        into contextID: UUID?,
        to position: Int
    ) throws -> [(row: CadenceResolvedContainer, order: Int)] {
        let targetID = identifier(of: target)
        var siblings: [(row: CadenceResolvedContainer, key: CadenceMCPOrdering.SortKey)] = []
        for area in try fetchAreas() where area.context?.id == contextID && area.id != targetID {
            siblings.append((.area(area), CadenceMCPOrdering.sortKey(area)))
        }
        for project in try fetchProjects() where project.context?.id == contextID && project.id != targetID {
            siblings.append((.project(project), CadenceMCPOrdering.sortKey(project)))
        }
        siblings.sort { CadenceMCPOrdering.precedes($0.key, $1.key) }

        guard position >= 0, position <= siblings.count else {
            throw CadenceWriteError.invalidPosition(position, siblings.count, "lists filed there")
        }
        var rows = siblings.map(\.row)
        rows.insert(target, at: position)
        return rows.enumerated().map { (row: $0.element, order: $0.offset) }
    }

    /// `plannedListOrders` over the one flat sequence every context shares.
    private func plannedContextOrders(
        moving target: Context,
        to position: Int
    ) throws -> [(row: Context, order: Int)] {
        var siblings = try fetchContexts().filter { $0.id != target.id }
        siblings.sort(by: CadenceMCPOrdering.precedes)

        guard position >= 0, position <= siblings.count else {
            throw CadenceWriteError.invalidPosition(position, siblings.count, "contexts")
        }
        siblings.insert(target, at: position)
        return siblings.enumerated().map { (row: $0.element, order: $0.offset) }
    }

    private func identifier(of container: CadenceResolvedContainer) -> UUID {
        switch container {
        case .area(let area): return area.id
        case .project(let project): return project.id
        }
    }

    private func currentOrder(of container: CadenceResolvedContainer) -> Int {
        switch container {
        case .area(let area): return area.order
        case .project(let project): return project.order
        }
    }

    private func contextID(of container: CadenceResolvedContainer) -> UUID? {
        switch container {
        case .area(let area): return area.context?.id
        case .project(let project): return project.context?.id
        }
    }

    private func resolveContext(_ id: String?) throws -> Context? {
        guard let requested = CadenceMCPServiceSupport.normalizedOptionalText(id) else { return nil }
        let uuid = try uuid(from: requested)
        guard let match = try fetchContexts().first(where: { $0.id == uuid }) else {
            throw CadenceReadError.contextNotFound(requested)
        }
        return match
    }

    private func resolveArea(_ id: String?) throws -> Area? {
        guard let requested = CadenceMCPServiceSupport.normalizedOptionalText(id) else { return nil }
        let uuid = try uuid(from: requested)
        guard let match = try fetchAreas().first(where: { $0.id == uuid }) else {
            throw CadenceReadError.containerNotFound("area", requested)
        }
        return match
    }

    private func normalizedOptionalColorHex(_ value: String?) throws -> String? {
        try CadenceMCPServiceSupport.normalizedOptionalColorHex(value)
    }

    private func normalizedRequiredText(_ value: String, emptyError: Error) throws -> String {
        try CadenceMCPServiceSupport.normalizedRequiredText(value, emptyError: emptyError)
    }

    private func validatedOptionalDate(_ dateKey: String?) throws -> String? {
        try CadenceMCPServiceSupport.validatedOptionalDate(dateKey)
    }

    private func resolvedDateKey(_ dateKey: String?) throws -> String {
        try CadenceMCPServiceSupport.resolvedDateKey(dateKey)
    }

    private func weekKey(for dateKey: String) throws -> String {
        try CadenceMCPServiceSupport.weekKey(for: dateKey)
    }

    private func parsedDate(_ dateKey: String) throws -> Date {
        try CadenceMCPServiceSupport.parsedDate(dateKey)
    }

    private func uuid(from id: String) throws -> UUID {
        try CadenceMCPServiceSupport.uuid(from: id)
    }

    private func validatePriority(_ value: String) throws -> TaskPriority {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let priority = TaskPriority(rawValue: normalized) else {
            throw CadenceWriteError.invalidPriority(value)
        }
        return priority
    }

    private func validateOptionalScheduledStart(_ value: Int?) throws -> Int? {
        guard let value else { return nil }
        guard (0...1439).contains(value) else {
            throw CadenceWriteError.invalidScheduledStartMin(value)
        }
        return value
    }

    private func validateEstimatedMinutes(_ value: Int) throws -> Int {
        guard (1...1440).contains(value) else {
            throw CadenceWriteError.invalidEstimatedMinutes(value)
        }
        return value
    }

    private func normalizeNoteKind(_ value: String) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard ["daily", "weekly", "permanent"].contains(normalized) else {
            throw CadenceWriteError.invalidNoteKind(value)
        }
        return normalized
    }

    private func normalizedContainerKind(_ value: String) throws -> String {
        try CadenceMCPServiceSupport.normalizeContainerKind(value)
    }

    private func resolveContainer(kind: String?, id: String?) throws -> CadenceResolvedContainer? {
        let normalizedKind = kind?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedID = id?.trimmingCharacters(in: .whitespacesAndNewlines)

        switch (normalizedKind?.isEmpty == false ? normalizedKind : nil, normalizedID?.isEmpty == false ? normalizedID : nil) {
        case (.none, .none):
            return nil
        case (.some(let kind), .some(let id)):
            let uuid = try uuid(from: id)
            switch try normalizedContainerKind(kind) {
            case "area":
                guard let area = try fetchAreas().first(where: { $0.id == uuid }) else {
                    throw CadenceReadError.containerNotFound(kind, id)
                }
                return .area(area)
            case "project":
                guard let project = try fetchProjects().first(where: { $0.id == uuid }) else {
                    throw CadenceReadError.containerNotFound(kind, id)
                }
                return .project(project)
            default:
                throw CadenceReadError.invalidContainerKind(kind)
            }
        default:
            throw CadenceReadError.incompleteContainerFilter
        }
    }

    private func currentContainer(for task: AppTask) -> CadenceResolvedContainer? {
        if let area = task.area { return .area(area) }
        if let project = task.project { return .project(project) }
        return nil
    }

    private func apply(container: CadenceResolvedContainer?, to task: AppTask) {
        switch container {
        case .area(let area):
            task.area = area
            task.project = nil
            task.context = area.context
        case .project(let project):
            task.project = project
            task.area = nil
            task.context = project.resolvedContext
        case nil:
            task.area = nil
            task.project = nil
            task.context = nil
        }
    }

    private func normalizedSectionName(_ value: String?, container: CadenceResolvedContainer?) throws -> String {
        try CadenceMCPServiceSupport.normalizedSectionName(value, container: container)
    }

    private func resolvedTags(named names: [String]) throws -> [Tag] {
        try CadenceMCPServiceSupport.requiredTags(TagSupport.resolveTags(named: names, in: context))
    }

    private func normalizedSubtaskTitles(_ values: [String]) -> [String] {
        CadenceMCPServiceSupport.normalizedSubtaskTitles(values)
    }

    private func append(_ text: String, separator: String, to content: inout String) {
        CadenceMCPServiceSupport.append(text, separator: separator, to: &content)
    }
}
