import Foundation
import SwiftData

/// **The declaration site of `CadenceTaskMutationSupport`, holding the block constructor, its
/// clamps and the bundle-membership rule.** The enum's other sixty-two members live in
/// `CadenceTaskMutationSupport.swift`, which extends this enum rather than declaring it —
/// fifty-six `internal` and six `private`.
/// (T-1122's entry counted this enum at "61 static members" when five were here; it is **62**
/// now, because `assignTask(_:to:)` came across and stopped being `private` in the process.
/// Count the `internal` ones only — 49 `static func` + 12 `static let` + 1 `static var`, of which
/// six are here — or the next re-measure will disagree with the ledger for no reason. A naive
/// `static` grep returns 68: the six surviving `private` members are the discrepancy.)
///
/// **That inversion is the point of the file, and it is deliberate (T-1122).** The enum's main file
/// reaches `NotificationManager` and `CadenceWidgetRefreshCenter`, and the latter is
/// `#if canImport(WidgetKit)` — two stacks that have no business in `CadenceMCPServer`, a headless
/// command-line tool whose Sources phase compiles whole *files*. `create_task_bundle` needs
/// `insertBundle(title:…)` and the four clamps; `add_task_to_bundle` needs `assignTask(_:to:)` and
/// the snapshot that undoes it, and nothing else in the enum. So those members are declared here,
/// on `Foundation`/`SwiftData` alone, and everything they touch — `AppTask`, `TaskBundle` and
/// `CadencePendingChangePersistence` — is already in that target.
///
/// **Why the declaration moved rather than the members being renamed into a second type.** An
/// `extension CadenceTaskMutationSupport` in this file would still require the main file to
/// declare the enum, which is the whole problem; and a differently-named helper type would break
/// the spelling `CadenceTaskMutationSupport.insertBundle(` that three source-text scans pin at
/// their call sites — `CadenceCreateTaskCommitSurfaceTests` against `iOSCalendarQuickCreateSheet`,
/// `CadenceBundleCreationParityTests` against `SchedulingService`, and
/// `CadenceSaveCommitDisciplineTests` against the same file by path. Declaring the enum here and
/// extending it there costs no call site and no pin a single character.
///
/// Do not "tidy" this back into the main file, and do not add members here that reach further than
/// `Foundation`/`SwiftData`: the first one that does silently re-blocks the arm this split exists
/// to unblock.
enum CadenceTaskMutationSupport {
    /// The day a bundle has to fit inside, and the shortest slot it may occupy.
    ///
    /// macOS spells the same two numbers as `TimelineDayRange` in `macOS/Views/TimelineMetrics.swift`,
    /// which this file cannot see — `Shared/` does not compile the timeline. They are deliberately
    /// identical, and `bundleClampsMatchTheTimelineDayRange` in `TaskBundleTests` fails if one side
    /// moves. Do not re-spell either literal at a call site; that is how the timeline clamp came to
    /// exist four times with three different bounds.
    static let bundleDayEndMin = 24 * 60
    static let bundleMinimumDuration = 5

    /// Clamps a start minute so a minimum-length block still ends inside the day.
    static func clampedBundleStart(_ startMin: Int) -> Int {
        min(max(0, startMin), bundleDayEndMin - bundleMinimumDuration)
    }

    /// Minutes a bundle starting at `startMin` needs in order to hold `tasks`, clamped inside the day.
    ///
    /// Every member contributes at least `bundleMinimumDuration`, so two estimate-less tasks still
    /// get a block tall enough to see and hit rather than a zero-height sliver.
    static func bundleDuration(startingAt startMin: Int, tasks: [AppTask]) -> Int {
        let total = tasks.reduce(0) { partial, task in
            partial + max(task.estimatedMinutes, bundleMinimumDuration)
        }
        return max(bundleMinimumDuration, min(total, bundleDayEndMin - clampedBundleStart(startMin)))
    }

    /// Mints an empty block from four explicit fields — the drag-out-a-range gesture's constructor.
    ///
    /// **It takes a `commit:` now ([[T-1122]]), and the default keeps every existing call site
    /// character-identical.** It was the one member of the `insertBundle` family without one, which
    /// was fine while the only caller was a sheet that commits on its own behalf. `create_task_bundle`
    /// is not: `CadenceWriteService` hands every arm's insert to `saveNotifyAndAudit`, so the row has
    /// to be able to travel there pending rather than arriving already saved — otherwise a refused
    /// audit-and-notify commit leaves a block in the store that `mcp-audit.log` never heard of, which
    /// is exactly the shape T-1181 removed from `appendCoreNote`.
    ///
    /// - Parameter commit: See `CadencePendingChangePersistence.commitInsert(of:in:commit:)`.
    @discardableResult
    static func insertBundle(
        title: String,
        dateKey: String,
        startMin: Int,
        durationMinutes: Int,
        modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> TaskBundle {
        let clampedStart = clampedBundleStart(startMin)
        let duration = min(max(bundleMinimumDuration, durationMinutes), bundleDayEndMin - clampedStart)
        let bundle = TaskBundle(
            title: TaskBundle.storedTitle(title),
            dateKey: dateKey,
            startMin: clampedStart,
            durationMinutes: duration
        )

        modelContext.insert(bundle)
        // See `duplicate(_:allTasks:modelContext:)` (T-1299): the same three lines, said once.
        try CadencePendingChangePersistence.commitInsert(of: bundle, in: modelContext, commit: commit)
        return bundle
    }

    /// The five-field write `addTask(_:to:modelContext:commit:)` and
    /// `insertBundle(from:adding:modelContext:commit:)` both need — pending only, no commit,
    /// because `insertBundle` credits two tasks under one commit and cannot call the committing
    /// `addTask` twice without saving twice for a single gesture (T-760).
    ///
    /// **It lives here, and it is `internal` rather than `private`, for the reason this file
    /// exists ([[T-1122]]).** This is the membership rule — five fields, one of them the
    /// `calendarEventID` clear the two platforms used to disagree on — and `add_task_to_bundle`
    /// is a headless caller with no timeline in front of it. A second copy of these five lines
    /// inside `CadenceWriteService` is the exact failure T-1122 exists to refuse, so the rule
    /// moved to the file `CadenceMCPServer`'s Sources phase can compile and opened up just far
    /// enough for the extension file's two callers and that arm to ask it. Do not re-spell it
    /// anywhere; call it.
    static func assignTask(_ task: AppTask, to bundle: TaskBundle) {
        let nextOrder = ((bundle.tasks ?? []).map(\.bundleOrder).max() ?? -1) + 1
        task.bundle = bundle
        task.bundleOrder = nextOrder
        task.scheduledDate = bundle.dateKey
        task.scheduledStartMin = -1
        // The task's own slot is gone — the bundle owns the block now — so any stale calendar link
        // it still carries has to go with it. `SchedulingActions.addTask` has always cleared this;
        // this copy did not, which was the one field on which the two platforms' add-to-bundle
        // paths disagreed. See "Calendar / Events" in `docs/CLAUDE_REFERENCE.md`: nothing writes
        // this field a non-empty value any more, and every write site clears it.
        task.calendarEventID = ""
        if !(bundle.tasks ?? []).contains(where: { $0.id == task.id }) {
            bundle.tasks = (bundle.tasks ?? []) + [task]
        }
    }

    /// The fields `assignTask(_:to:)` writes on a task it moves into a bundle, captured before the
    /// write — the shared-mutation twin of `SchedulingActions.BundleMembership` on macOS (T-760).
    ///
    /// The bundle itself is un-inserted by `commitInsert`, but that does not put either task back:
    /// both were detached from whatever block they were in, given a `bundleOrder`, moved onto the
    /// new block's day, stripped of their time slot and of any calendar-event link. A refusal that
    /// restored only the block would leave both tasks scheduled somewhere the store never agreed to.
    ///
    /// **It came here with `assignTask` and is `internal` for the same reason ([[T-1122]]).** An
    /// undo is half of what the MCP write path owes a caller, and `add_task_to_bundle` writes into
    /// a block that already exists — so unlike `insertBundle(from:adding:)` it cannot lean on the
    /// bundle's own un-insert to put the task back. It restores the task's five fields; a caller
    /// writing into a surviving block restores that block's own `tasks` edge beside it, which is
    /// the one thing this type deliberately does not know about.
    struct BundleMembership {
        private let task: AppTask
        private let bundle: TaskBundle?
        private let bundleOrder: Int
        private let scheduledDate: String
        private let scheduledStartMin: Int
        private let calendarEventID: String

        init(_ task: AppTask) {
            self.task = task
            bundle = task.bundle
            bundleOrder = task.bundleOrder
            scheduledDate = task.scheduledDate
            scheduledStartMin = task.scheduledStartMin
            calendarEventID = task.calendarEventID
        }

        func restore() {
            task.bundle = bundle
            task.bundleOrder = bundleOrder
            task.scheduledDate = scheduledDate
            task.scheduledStartMin = scheduledStartMin
            task.calendarEventID = calendarEventID
        }
    }
}
