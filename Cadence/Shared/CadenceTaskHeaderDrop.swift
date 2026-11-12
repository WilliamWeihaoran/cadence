import Foundation
import SwiftData

// **A task row dropped on a group heading re-files it, on both platforms ([[T-16654]]).**
//
// This was the assign half of the Mac's `TasksPanelSupport`, `#if os(macOS)`, so the iPhone's and
// iPad's All Tasks / Inbox headings could take only the new-task `+` while the Mac re-filed a row
// dragged onto the same heading. No hardware constraint answered that split -- a touch drag is a
// system drag carrying the same `TaskDragPayload` string -- so it was drift ([[T-8201]]), and the
// logic moved here verbatim rather than being re-spelled for iOS: one parse, one resolve, one
// commit with one undo. The enum names keep their `TasksPanel` prefix because every Mac drop
// surface already answers them (`CalendarPageBoardDropSupport`, the month grid).

/// One field a drop key asks `CadenceTaskHeaderDrop.assignTask` to set.
///
/// It exists so the parse and the mutation are separable. A drop key is compound — Today's list
/// headers say `list:p_<uuid>|date:today` — and reading the whole of one as a single `list:` value
/// was a bug nothing could catch, because the only way to observe the parse was to drag a row in
/// the running app and notice it had not moved (T-591). Resolving to these first makes the parse a
/// value a test can read.
enum TasksPanelDropAssignment: Equatable {
    case inbox
    case area(UUID)
    case project(UUID)
    case scheduleToday
    case pushToScheduled
    case clearSchedule
    case priority(TaskPriority)
}

/// What a drop key did to the task, which is three answers and not two ([[T-1580]]).
///
/// `assignTask` used to answer `Bool`, and the `true` was a **report** over
/// `try? modelContext.save()`: a header that accepted the row, kept it where it was dropped, and
/// said nothing when the store refused the write — the T-566 shape, one screen over from the
/// reorder half that [[T-868]] already fixed. The two failures are not the same failure and the
/// surface draws them differently:
///
/// - `.resolvedNothing` — the key named a list that is gone, or a vocabulary this surface does not
///   speak. Nothing was written, the row springs back, and **nothing is said**: that is
///   [[T-591]]'s refusal and a sentence there would be describing the user's aim.
/// - `.refused` — the key resolved, the fields were written, and the store would not take them.
///   `CadenceTaskFieldEditCommit` has already put every field back by the time this is answered,
///   so the page and `CadencePendingChangePersistence.editFailureNotice` agree: nothing changed.
///
/// **The Calendar Board answers this too ([[T-1952]])**, rather than minting a near-copy of it:
/// `CalendarPageBoardDropSupport.unschedule` is the same three outcomes with the same two meanings
/// for the two `false`s, and both macOS drop surfaces plus the board map them identically. The name
/// stays `TasksPanel…` because that is where the vocabulary was first written down, not because it
/// is the only page that speaks it.
enum TasksPanelDropOutcome: Equatable {
    case applied
    case resolvedNothing
    case refused
}

/// A drop assignment with the row it names already looked up — or nothing, when that row is gone.
///
/// The resolution is split out of `apply` so that **one** place decides whether a key applies.
/// `assignTask` has to know that before it writes anything: a key that resolves to nothing must not
/// reach the store at all, and a `commit` over a drop that changed no field would commit whatever
/// unrelated work the app's single `ModelContext` happened to be holding.
private enum TasksPanelResolvedAssignment {
    case inbox
    case area(Area)
    case project(Project)
    case scheduleToday
    case pushToScheduled
    case clearSchedule
    case priority(TaskPriority)

    /// Whether applying this writes a date field, and therefore whether the OS notifications have
    /// to be reconciled once the commit lands. A list move or a priority change does not.
    var changesSchedule: Bool {
        switch self {
        case .scheduleToday, .pushToScheduled, .clearSchedule: return true
        case .inbox, .area, .project, .priority: return false
        }
    }
}

enum CadenceTaskHeaderDrop {
    /// **The key a group heading hands a dropped row, the same on both platforms.** A By List or
    /// By Priority group carries its own (`list:<key>`, `priority:<raw>`); the six date buckets
    /// carry none, deliberately, and the three a task can be moved *into* are mapped by
    /// `dateDropKey(forGroupID:)`. `nil` -- the ungrouped "Tasks" group, Overdue, Leftover, Due
    /// Today -- means the heading names nothing a task can be filed under and takes no row.
    static func dropKey(forDisplayGroup group: CadenceTaskDisplayGroup) -> String? {
        group.dropKey ?? dateDropKey(forGroupID: group.id)
    }

    /// The three date buckets a task can be *moved into*.
    ///
    /// `CadenceTaskQuerySupport.dateDisplayGroups` leaves `dropKey` nil for all six -- deliberately,
    /// per `CadenceTaskDropSupport`, which says a group header that lights up and then applies
    /// nothing is noise. Overdue, Leftover and Due Today are exactly that: Overdue and Leftover are
    /// defined by a day that has already gone by, and there is no "make this late" assignment. The
    /// other three map onto the keys `assignTask` reads. Was `TasksListView.dateDropKey`, which
    /// still answers for the Mac callers that spell it.
    static func dateDropKey(forGroupID id: String) -> String? {
        switch id {
        case "do-today": return "date:today"
        case "scheduled": return "date:scheduled"
        case "unscheduled": return "date:unscheduled"
        default: return nil
        }
    }

    /// **A dragged row let go over a heading keyed `dropKey`** -- the iOS heading's whole drop, and
    /// the Mac's `TasksPanelDropCoordinator.handleSectionDrop` with the page's lookups filled in.
    ///
    /// The row must be one of `tasks`, the page's own universe, which is the Mac's membership
    /// check: a payload naming a task this page does not hold -- text dragged in from another app,
    /// a task from another surface -- resolves to nothing and writes nothing. The lists are read
    /// from the store at drop time, so a list made since the page last rendered still resolves.
    @discardableResult
    static func dropTask(
        payload: String,
        onHeaderKeyed dropKey: String,
        among tasks: [AppTask],
        todayKey: String,
        modelContext: ModelContext,
        reconciler: CadenceWindDownReconciler? = nil,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> TasksPanelDropOutcome {
        guard let droppedID = TaskDragPayload.taskID(from: payload),
              let task = tasks.first(where: { $0.id == droppedID }) else { return .resolvedNothing }
        return assignTask(
            task,
            for: dropKey,
            todayKey: todayKey,
            areas: (try? modelContext.fetch(FetchDescriptor<Area>())) ?? [],
            projects: (try? modelContext.fetch(FetchDescriptor<Project>())) ?? [],
            modelContext: modelContext,
            reconciler: reconciler,
            commit: commit
        )
    }

    /// Moves `task` to everything `dropKey` names, and reports whether any of it landed.
    ///
    /// **A drop key is compound.** Today's group headers hand out `list:p_<uuid>|date:today` — the
    /// list *and* the day, because a task dropped on a Today list group has to be filed in that
    /// list without vanishing off the page it was dropped on
    /// (`CadenceTaskDropSupport.dropKey(forGroup:)` explains why the header says both). This read
    /// the whole string as one `list:` value, hunted for a project whose `uuidString` was
    /// `"<uuid>|date:today"`, found none, and fell out of every branch — every Today list header
    /// accepted drops and moved nothing (T-591). Parts are split on
    /// `CadenceTaskDropSupport.separator` and applied one at a time now, the same way
    /// `CadenceTaskDropSupport.seed(forDropKey:)` has always read them for the *seed* path.
    ///
    /// **The return value is what stops that going quiet again.** A key that resolves to nothing —
    /// an unknown vocabulary, or a list id no longer in `areas`/`projects` — must not be reported
    /// as a drop that happened; see `TasksPanelDropCoordinator.handleSectionDrop`, which used to
    /// answer `true` unconditionally and is the reason this was invisible for so long.
    ///
    /// **It answers three things and not two, because it used to report success over a commit it
    /// could not see refused ([[T-1580]]).** The body was `try? modelContext.save(); return true` —
    /// the swallowed commit and the success report in the same four lines, which is the half-2
    /// shape `AGENTS.md` names and which `CadenceSaveCommitDisciplineTests` reads one frame down at
    /// every caller. The reorder half of this very coordinator was fixed for it in [[T-868]]; the
    /// assign half was not, and a list move the store refused left the row sitting in its new
    /// section until the next launch put it back with nothing to retry. See
    /// `TasksPanelDropOutcome`, and `TasksListDropCommitRateTests` for the counts.
    /// - Parameter commit: How to commit. Defaults to `ModelContext.save()`; it is a parameter
    ///   because a `save()` that throws cannot be provoked out of an in-memory container, and an
    ///   undo path no test can reach is an undo path no test can prove.
    @discardableResult
    static func assignTask(
        _ task: AppTask,
        for dropKey: String,
        todayKey: String,
        areas: [Area],
        projects: [Project],
        modelContext: ModelContext,
        reconciler: CadenceWindDownReconciler? = nil,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> TasksPanelDropOutcome {
        // Resolved before anything is written, which is what keeps the three outcomes apart: a key
        // that applies to nothing must not reach `commit` at all, or a drop that moved no field
        // would commit whatever unrelated pending work the app's single context is holding.
        let resolved = dropAssignments(forDropKey: dropKey)
            .compactMap { resolve($0, areas: areas, projects: projects) }
        guard !resolved.isEmpty else { return .resolvedNothing }

        // **One commit for the whole drop, with the undo that makes `.refused` honest.** A compound
        // key writes a list *and* a date; the date half used to commit itself through a swallowed
        // save inside `apply`, so half the drop landed in the store before anybody could ask
        // whether the other half would. Every write below is handed `commit: { _ in }` and this
        // frame owns the single commit.
        let landed = CadenceTaskFieldEditCommit.commit(
            task,
            in: modelContext,
            reconciler: reconciler,
            commit: commit
        ) {
            for assignment in resolved {
                apply(assignment, to: task, todayKey: todayKey, modelContext: modelContext)
            }
        }
        guard landed else { return .refused }
        // After the commit and not inside the write, which is `CadenceTaskDateEditing`'s own
        // contract: the reconcile fetches, and it must read the arrangement the store took.
        if resolved.contains(where: \.changesSchedule) {
            (reconciler ?? .default).run(in: modelContext)
        }
        return .applied
    }

    /// What a drop key asks for, resolved before anything is touched.
    ///
    /// Pure on purpose: the parse is the whole of T-591 and it needs to be pinnable without a
    /// `ModelContext`, a task, or a live store. Parts the macOS assign vocabulary does not speak —
    /// `section:`, `due:` — are dropped rather than failing the key, so a compound key that also
    /// names something this surface *can* apply still applies it.
    static func dropAssignments(forDropKey dropKey: String) -> [TasksPanelDropAssignment] {
        dropKey
            .split(separator: CadenceTaskDropSupport.separator)
            .map(String.init)
            .compactMap { assignment(fromDropKeyPart: $0) }
    }

    private static func assignment(fromDropKeyPart part: String) -> TasksPanelDropAssignment? {
        if part.hasPrefix("list:") {
            let listID = String(part.dropFirst(5))
            if listID == "inbox" { return .inbox }
            if listID.hasPrefix("a_"), let id = UUID(uuidString: String(listID.dropFirst(2))) {
                return .area(id)
            }
            if listID.hasPrefix("p_"), let id = UUID(uuidString: String(listID.dropFirst(2))) {
                return .project(id)
            }
            return nil
        }
        switch part {
        case "date:today": return .scheduleToday
        case "date:scheduled": return .pushToScheduled
        case "date:unscheduled": return .clearSchedule
        default: break
        }
        if part.hasPrefix("priority:"), let priority = TaskPriority(rawValue: String(part.dropFirst(9))) {
            return .priority(priority)
        }
        return nil
    }

    /// `nil` means the assignment named a list that is not here any more — the one case the parse
    /// cannot see and the caller still needs to know about, and the only reason `areas`/`projects`
    /// reach this far at all.
    private static func resolve(
        _ assignment: TasksPanelDropAssignment,
        areas: [Area],
        projects: [Project]
    ) -> TasksPanelResolvedAssignment? {
        switch assignment {
        case .inbox: return .inbox
        case .area(let areaID):
            guard let target = areas.first(where: { $0.id == areaID }) else { return nil }
            return .area(target)
        case .project(let projectID):
            guard let target = projects.first(where: { $0.id == projectID }) else { return nil }
            return .project(target)
        case .scheduleToday: return .scheduleToday
        case .pushToScheduled: return .pushToScheduled
        case .clearSchedule: return .clearSchedule
        case .priority(let priority): return .priority(priority)
        }
    }

    /// T-5353: a list drop's container write — `CadenceTaskMutationSupport.assignContainer`, the
    /// write the context menu's Move to List commits, so the task takes the end of the new list
    /// and a section that list has. Commits nothing; `assignTask` owns the commit.
    private static func assignContainer(_ task: AppTask, area: Area?, project: Project?, in modelContext: ModelContext) {
        CadenceTaskMutationSupport.assignContainer(
            task,
            area: area,
            project: project,
            sectionName: task.resolvedSectionName,
            allTasks: (try? modelContext.fetch(FetchDescriptor<AppTask>())) ?? []
        )
    }

    /// **The do date a drop on a By Date "Scheduled" header writes, or `nil` to leave it alone
    /// ([[T-16652]]).** Tomorrow for a task with no do date, a do date of today, **or one already
    /// gone by**; `nil` only for a do date after today, which already reads as Scheduled.
    ///
    /// The guard was `isEmpty || == todayKey`. That was complete while a past do date filed under
    /// Scheduled too, and [[T-12323]] moved those rows into their own Leftover group without
    /// touching this, so a Leftover row dropped on Scheduled answered `.applied`, wrote nothing and
    /// stayed in Leftover. Tomorrow is counted from `todayKey`, the page's observed day, not from
    /// `Date()`, so the write agrees with the buckets the page drew.
    static func pushedToScheduledDateKey(
        from scheduledDate: String,
        todayKey: String,
        calendar: Calendar = .current
    ) -> String? {
        guard scheduledDate.isEmpty || scheduledDate <= todayKey else { return nil }
        guard let today = DateFormatters.date(from: todayKey),
              let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return nil }
        return DateFormatters.dateKey(from: tomorrow)
    }

    /// Writes the assignment and **commits nothing** — `assignTask` owns the one commit, which is
    /// why every date edit here is handed `commit: { _ in }` and `reconciler: .inert`. Still routed
    /// through `CadenceTaskDateEditing` rather than writing `task.scheduledDate` by hand: T-362's
    /// rule is that a user surface never touches the three date fields directly, and the reconcile
    /// it would otherwise perform is simply moved to after the commit.
    private static func apply(
        _ assignment: TasksPanelResolvedAssignment,
        to task: AppTask,
        todayKey: String,
        modelContext: ModelContext
    ) {
        // T-5353: a list drop is a move like the context menu's, so it goes through
        // `assignContainer` — end of the new list, a section that list has — rather than keeping
        // the old list's `order` and a `sectionName` the new list may not have. The commit is
        // still `assignTask`'s one, whose snapshot puts all five fields back on a refusal.
        switch assignment {
        case .inbox:
            assignContainer(task, area: nil, project: nil, in: modelContext)
        case .area(let target):
            assignContainer(task, area: target, project: nil, in: modelContext)
        case .project(let target):
            assignContainer(task, area: nil, project: target, in: modelContext)
        case .scheduleToday:
            CadenceTaskDateEditing.setScheduledDate(
                todayKey,
                for: task,
                in: modelContext,
                reconciler: .inert,
                commit: { _ in }
            )
        case .pushToScheduled:
            // Already scheduled past today: the drop resolved, and leaving the later date alone is
            // the assignment, not a failure to make one — see `assignTask`.
            if let pushed = pushedToScheduledDateKey(from: task.scheduledDate, todayKey: todayKey) {
                CadenceTaskDateEditing.setScheduledDate(
                    pushed,
                    for: task,
                    in: modelContext,
                    reconciler: .inert,
                    commit: { _ in }
                )
            }
        case .clearSchedule:
            CadenceTaskDateEditing.clearScheduledDate(
                task,
                in: modelContext,
                reconciler: .inert,
                commit: { _ in }
            )
        case .priority(let priority):
            task.priority = priority
        }
    }
}
