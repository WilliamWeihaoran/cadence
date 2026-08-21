import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Cadence

/// T-147: a cancelled task was unreachable. The decision was **show them in Completed**, struck
/// through rather than in the green done treatment.
///
/// The bug was a *pair* of filters that did not partition the set. The active lists asked
/// `!isDone && !isCancelled` and the Completed lists asked `isDone && !isCancelled` — and a
/// cancelled task satisfies neither, so it fell out of every list in the app. On iOS, where the
/// inspector's Cancel button, the swipe tray and the row's context menu can all produce that
/// status, cancelling was deleting without saying so.
///
/// **Two kinds of test here, and the second kind is the point.** Pinning `isFinishedTask` proves
/// the predicate is right and proves nothing about anybody using it: T-161 is the standing example
/// of a committed fix reverted with the whole suite green because the tests pinned a helper while
/// nothing observed the call sites. So the behavioural tests below run the real queries, and the
/// source-scanning tests read the real files with exact per-file counts. The iOS half has no other
/// option — `Cadence/iOS/` is entirely inside `#if os(iOS)` and this target builds for macOS —
/// which is why `iOSTaskRow`'s share is asserted as source text and `theSourceScanIsNotVacuous`
/// exists to stop a broken reader making the absence assertions pass silently.
@MainActor
struct CadenceCancelledTaskReachabilityTests {

    private let todayKey = "2026-08-20"

    private func task(
        _ title: String,
        status: TaskStatus = .todo,
        doDate: String = "",
        dueDate: String = "",
        area: Area? = nil,
        completedAt: Date? = nil
    ) -> AppTask {
        let task = AppTask(title: title)
        task.status = status
        task.scheduledDate = doDate
        task.dueDate = dueDate
        task.area = area
        task.completedAt = completedAt
        return task
    }

    // MARK: - The predicate

    /// "Over, however it ended." Both settled statuses, neither open one.
    @Test func finishedMeansDoneOrCancelled() {
        #expect(CadenceTaskQuerySupport.isFinishedTask(task("d", status: .done)))
        #expect(CadenceTaskQuerySupport.isFinishedTask(task("c", status: .cancelled)))
        #expect(!CadenceTaskQuerySupport.isFinishedTask(task("t", status: .todo)))
        #expect(!CadenceTaskQuerySupport.isFinishedTask(task("p", status: .inProgress)))
    }

    /// The whole bug, stated as a property: open and finished must **partition** every status, so
    /// no task can be in neither list. `.inProgress` is the reminder that the status set has grown
    /// before and can grow again.
    @Test func openAndFinishedPartitionEveryStatus() {
        for status in TaskStatus.allCases {
            let subject = task("t", status: status)
            let isOpen = CadenceTaskQuerySupport.openTasks(from: [subject]).count == 1
            let isFinished = CadenceTaskQuerySupport.isFinishedTask(subject)
            #expect(isOpen != isFinished, "\(status.rawValue) is in \(isOpen && isFinished ? "both" : "neither") half")
        }
    }

    // MARK: - The three completed queries

    @Test func aCancelledTaskIsReturnedByTheCompletedListQueryAndNotTheActiveOne() {
        let cancelled = task("cancelled", status: .cancelled)
        let open = task("open")
        let done = task("done", status: .done)
        let all = [cancelled, open, done]

        #expect(
            CadenceTaskQuerySupport.completedTasks(from: all).map(\.title).sorted()
                == ["cancelled", "done"]
        )
        #expect(
            CadenceTaskQuerySupport.activeTasks(from: all, sortMode: .listOrder).map(\.title)
                == ["open"]
        )
    }

    @Test func aCancelledInboxTaskIsReturnedByTheCompletedInboxQuery() {
        let area = Area(name: "Filed")
        let cancelledInbox = task("cancelled-inbox", status: .cancelled)
        let cancelledFiled = task("cancelled-filed", status: .cancelled, area: area)
        let all = [cancelledInbox, cancelledFiled, task("open")]

        #expect(
            CadenceTaskQuerySupport.completedInboxTasks(from: all).map(\.title) == ["cancelled-inbox"]
        )
        #expect(
            CadenceTaskQuerySupport.activeInboxTasks(from: all, sortMode: .listOrder).map(\.title)
                == ["open"]
        )
    }

    /// Today's Completed section admits a cancelled task on the same three grounds a done one gets
    /// in: planned today, due today, or settled today.
    @Test func aCancelledTaskReachesTodaysCompletedSection() {
        let planned = task("planned", status: .cancelled, doDate: todayKey)
        let due = task("due", status: .cancelled, dueDate: todayKey)
        let settled = task(
            "settled",
            status: .cancelled,
            completedAt: DateFormatters.date(from: todayKey)
        )
        let elsewhere = task("elsewhere", status: .cancelled, doDate: "2026-08-01")
        let all = [planned, due, settled, elsewhere]

        #expect(
            CadenceTaskQuerySupport.completedTodayTasks(from: all, todayKey: todayKey)
                .map(\.title).sorted() == ["due", "planned", "settled"]
        )
        #expect(
            CadenceTaskQuerySupport.activeTodayTasks(from: all, todayKey: todayKey, sortMode: .listOrder)
                .isEmpty
        )
    }

    /// The upstream filter that was defeating the downstream one. `inboxTasks` is the whole Inbox
    /// universe `TasksListView` then splits in two; while it dropped cancelled work, macOS's Inbox
    /// hid it and macOS's All Tasks — which scopes with `isInActiveContainer` instead — showed it.
    @Test func theInboxUniverseCarriesCancelledWorkThroughToItsCompletedHalf() {
        let all = [task("cancelled", status: .cancelled), task("open"), task("done", status: .done)]
        let universe = CadenceTaskQuerySupport.inboxTasks(from: all)

        #expect(universe.count == 3)
        #expect(universe.filter { CadenceTaskQuerySupport.isFinishedTask($0) }.map(\.title).sorted()
            == ["cancelled", "done"])
    }

    /// …and no badge moved. Both `inboxTasks` callers re-filter to open work, so widening the
    /// universe must not change a count.
    @Test func wideningTheInboxUniverseDidNotChangeAnyOpenCount() {
        let all = [task("cancelled", status: .cancelled), task("open"), task("done", status: .done)]

        #expect(CadenceTaskQuerySupport.openTaskCount(from: CadenceTaskQuerySupport.inboxTasks(from: all)) == 1)
        #expect(CadenceTaskQuerySupport.openInboxTaskCount(from: all) == 1)
    }

    // MARK: - Deliberately unchanged

    /// `completedTaskCount` backs the "N done" summary and the Settings Completed tile. That is a
    /// count of work *finished*, and a cancellation is not an accomplishment — reachability is what
    /// a Completed section owes you, not credit.
    @Test func theDoneCountStillCountsOnlyDoneWork() {
        let all = [task("cancelled", status: .cancelled), task("done", status: .done), task("open")]

        #expect(CadenceTaskQuerySupport.completedTaskCount(from: all) == 1)
    }

    /// Every active list keeps excluding cancelled work — that half was never the bug.
    @Test func theActiveFiltersStillExcludeCancelledWork() {
        let all = [task("cancelled", status: .cancelled, doDate: todayKey, dueDate: todayKey)]

        #expect(CadenceTaskQuerySupport.openTasks(from: all).isEmpty)
        #expect(CadenceTaskQuerySupport.activeTasks(from: all, sortMode: .listOrder).isEmpty)
        #expect(CadenceTaskQuerySupport.activeInboxTasks(from: all, sortMode: .listOrder).isEmpty)
        #expect(CadenceTaskQuerySupport.activeTodayTasks(from: all, todayKey: todayKey, sortMode: .listOrder).isEmpty)
    }

    /// A cancelled task holds no timeline slot and is on no rail, and is not work you are late on.
    /// Three judgements this ticket deliberately left alone, pinned so the next sweep past
    /// `isCancelled` does not take them with it.
    ///
    /// The rail/day-column half is `CalendarBoardPlannerSupport`, declared in a file called
    /// `CadenceCalendarPlanningSupport.swift` — the name mismatch `Cadence/Shared/AGENTS.md` warns
    /// about, and the reason this test failed to compile the first time.
    @Test func aCancelledTaskIsStillOffTheScheduleTheRailsAndTheOverdueCount() {
        let scheduled = task("cancelled", status: .cancelled, doDate: todayKey, dueDate: "2026-08-01")
        scheduled.scheduledStartMin = 540

        #expect(
            CadenceScheduleSupport.scheduledTasks(
                on: todayKey,
                from: [scheduled],
                includeCompleted: true,
                excludeBundled: true
            ).isEmpty
        )
        #expect(CalendarBoardPlannerSupport.railTasks(from: [scheduled], todayKey: todayKey).isEmpty)
        #expect(CalendarBoardPlannerSupport.tasksByBoardDateFoldingDueDates(from: [scheduled]).isEmpty)
        #expect(CadenceSidebarLayout.overdueTaskCount(from: [scheduled], todayKey: todayKey) == 0)
    }

    // MARK: - T-202: cancelling records the time it happened

    /// Midnight of `key` — inside that calendar day for the same formatter `todayKey` came from,
    /// which is exactly what both Today filters ask about.
    private func instant(_ key: String) throws -> Date {
        try #require(DateFormatters.date(from: key))
    }

    private func cancelling(_ subject: AppTask, at moment: Date) throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        context.insert(subject)
        CadenceTaskRecurrenceWorkflowSupport.markCancelled(subject, in: context, now: moment)
    }

    /// T-202, the premise run rather than argued. `completedTodayTasks` admits finished work on
    /// three grounds — planned today, due today, or settled today — and `markCancelled` used to
    /// clear `completedAt`, which is the only one of the three a **dateless** task has left. So
    /// abandoning an unscheduled task reached All Tasks → Completed, its list's Completed and Inbox
    /// Completed, and no Today section at all.
    @Test func cancellingADatelessTaskPutsItInTodaysCompletedSection() throws {
        let subject = task("abandoned")
        try cancelling(subject, at: instant(todayKey))

        #expect(subject.isCancelled)
        #expect(subject.completedAt != nil)
        #expect(
            CadenceTaskQuerySupport.completedTodayTasks(from: [subject], todayKey: todayKey)
                .map(\.title) == ["abandoned"]
        )
    }

    /// The ticket's own case: an **overdue** task, exactly the kind you give up on. Both of its
    /// dates point at the past, so neither of the other two grounds can carry it either.
    @Test func cancellingAnOverdueTaskPutsItInTodaysCompletedSection() throws {
        let subject = task("overdue", doDate: "2026-08-01", dueDate: "2026-08-02")
        try cancelling(subject, at: instant(todayKey))

        #expect(
            CadenceTaskQuerySupport.completedTodayTasks(from: [subject], todayKey: todayKey)
                .map(\.title) == ["overdue"]
        )
    }

    /// The other half of the same predicate, and the reason this is not satisfied by recording
    /// *any* timestamp: yesterday's abandonment is not today's Completed section.
    @Test func aTaskCancelledYesterdayStaysOutOfTodaysCompletedSection() throws {
        let subject = task("abandoned yesterday")
        try cancelling(subject, at: instant("2026-08-19"))

        #expect(subject.completedAt != nil)
        #expect(
            CadenceTaskQuerySupport.completedTodayTasks(from: [subject], todayKey: todayKey).isEmpty
        )
    }

    /// macOS's Today Completed section is a **different** filter in a different file, and a
    /// stricter one: in `.todayOverview` it asks only about `completedAt`, with no do-date or
    /// due-date ground to fall back on. So on macOS *no* cancelled task reached Today's Completed,
    /// dateless or not. Pinned here because a fix verified only through
    /// `CadenceTaskQuerySupport` would be a fix for one platform.
    @Test func macOSTodayCompletedAlsoAdmitsTheCancelledTask() throws {
        let subject = task("abandoned", doDate: todayKey)
        try cancelling(subject, at: instant(todayKey))

        let state = TasksPanelDerivedState(
            allTasks: [subject],
            areas: [],
            projects: [],
            mode: .todayOverview,
            todayKey: todayKey,
            sortField: .date,
            sortDirection: .ascending
        )
        #expect(state.doneTasks.map(\.title) == ["abandoned"])
    }

    /// `TaskOrdering.completionPrecedes` sorts `completedAt ?? createdAt`, newest first. A
    /// cancelled task fell through to `createdAt`, so the logbook ordered it by when it was
    /// *made* rather than when it was settled: an old task abandoned this morning sorted below
    /// work finished days ago. Both settled statuses now sort on the same measurement.
    @Test func theLogbookOrdersACancelledTaskByWhenItWasCancelled() throws {
        let old = task("old, abandoned today")
        old.createdAt = try instant("2026-01-01")
        let recent = task("new, done last week", status: .done)
        recent.createdAt = try instant("2026-08-13")
        recent.completedAt = try instant("2026-08-13")

        try cancelling(old, at: instant(todayKey))

        #expect([recent, old].taskCompletionSorted().map(\.title) == ["old, abandoned today", "new, done last week"])
    }

    /// The timestamp is reachability, not credit. `completedTaskCount` backs the "N done" summary
    /// line and the Settings Completed tile and counts `isDone` alone, and this pins that through
    /// the real `markCancelled` rather than through a hand-set status.
    @Test func recordingTheCancellationTimeGrantedNoDoneCredit() throws {
        let done = task("finished", status: .done, completedAt: try instant(todayKey))
        let cancelled = task("abandoned")
        try cancelling(cancelled, at: instant(todayKey))

        #expect(cancelled.completedAt != nil)
        #expect(CadenceTaskQuerySupport.completedTaskCount(from: [cancelled, done]) == 1)
    }

    /// The other "N done" a user reads is a goal's **Momentum** tile, and that one is
    /// `recentCompletedCount` — every contributing task whose `completedAt` falls in the last seven
    /// days, with no `isDone` test of its own. So it looks like exactly the count this change should
    /// have leaked into, and adding an `isDone` guard there is an edit that compiles, reads
    /// plausibly and cannot be killed by any test: `GoalContributionResolver.contributingTasks`
    /// already ends in `.filter { !$0.isCancelled }`, so an abandoned task is not in the universe
    /// the momentum window is measured over in the first place. This test is what says so — mutate
    /// that upstream filter away and it fails, which an `isDone` guard downstream would then hide.
    @Test func aGoalsMomentumTileNeverSeesTheCancelledTaskAtAll() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let goal = Goal(title: "Ship it")
        context.insert(goal)
        let cancelled = task("abandoned")
        let done = task("finished", status: .done, completedAt: try instant(todayKey))
        for subject in [cancelled, done] {
            context.insert(subject)
            subject.goal = goal
        }
        CadenceTaskRecurrenceWorkflowSupport.markCancelled(cancelled, in: context, now: try instant(todayKey))

        let summary = GoalContributionResolver.summary(for: goal, now: try instant(todayKey))
        #expect(summary.totalTasks == 1)
        #expect(summary.completedTasks == 1)
        #expect(summary.recentCompletedCount == 1)
    }

    /// The iOS task sheet saves through `normalizeCompletionState`, whose job is to reconcile
    /// `completedAt` with `status`. Its `else` branch cleared the timestamp for every status that is
    /// not `.done` — and `.cancelled` is one of them, so cancelling from the sheet stamped the time
    /// and *leaving* the sheet wiped it again. That is every route out of that sheet, which made the
    /// fix invisible on the exact surface T-202 was reported from: the task appeared in Inbox →
    /// Completed, which has no date test, and not in Today's Completed, which has one.
    ///
    /// The three open/settled cases are all pinned, because "clear it unless done" is the shape the
    /// bug had and any future spelling of it must fail here.
    @Test func savingTheTaskSheetDoesNotWipeTheCancellationTimestamp() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let subject = task("abandoned")
        context.insert(subject)
        CadenceTaskRecurrenceWorkflowSupport.markCancelled(subject, in: context, now: try instant(todayKey))
        let stamp = try #require(subject.completedAt)

        CadenceTaskMutationSupport.normalizeCompletionState(for: subject, modelContext: context)

        #expect(subject.status == .cancelled)
        #expect(subject.completedAt == stamp)
        #expect(
            CadenceTaskQuerySupport.completedTodayTasks(from: [subject], todayKey: todayKey)
                .map(\.title) == ["abandoned"]
        )

        // …and it still clears the timestamp for the two statuses that contradict one.
        for open in [TaskStatus.todo, .inProgress] {
            let reopened = task("reopened", status: open, completedAt: try instant(todayKey))
            context.insert(reopened)
            CadenceTaskMutationSupport.normalizeCompletionState(for: reopened, modelContext: context)
            #expect(reopened.completedAt == nil, "\(open.rawValue) kept a completion timestamp")
        }
    }

    // MARK: - T-213: the normalizer must not re-stamp a task finished last week

    /// The `.done` branch was the `.cancelled` bug pointing the other way. It called `markDone`,
    /// which is a **transition** — it sets `completedAt = now` unconditionally — and the sheet
    /// re-saves on every change to title, priority, status, recurrence, estimate, actual minutes and
    /// section. So renaming a task finished last week rewrote its timestamp to today and dragged it
    /// into Today's Completed section, which is the one place a week-old task must not appear.
    ///
    /// The stamp is compared as a stored `Date`, deliberately. A re-stamp is invisible through a
    /// default `ISO8601DateFormatter` (second precision) and would be invisible through
    /// `DateFormatters.ymd` too if the re-stamp happened on the same day, so a formatted comparison
    /// here can pass while the bug is live.
    @Test func savingTheSheetDoesNotRestampATaskFinishedLastWeek() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let lastWeek = try instant("2026-08-13")
        let subject = task("finished last week", status: .done, completedAt: lastWeek)
        context.insert(subject)

        CadenceTaskMutationSupport.normalizeCompletionState(for: subject, modelContext: context)

        #expect(subject.status == .done)
        #expect(subject.completedAt == lastWeek)
        #expect(
            CadenceTaskQuerySupport.completedTodayTasks(from: [subject], todayKey: todayKey).isEmpty,
            "a task finished last week was pulled into Today's Completed section"
        )
    }

    /// The other polarity, so the fix cannot be satisfied by *clearing* the timestamp instead —
    /// which would break Today's Completed on both platforms rather than only for old rows. A task
    /// genuinely finished today keeps its stamp and stays in the section.
    @Test func savingTheSheetKeepsATaskFinishedTodayInTodaysCompletedSection() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let today = try instant(todayKey)
        let subject = task("finished today", status: .done, completedAt: today)
        context.insert(subject)

        CadenceTaskMutationSupport.normalizeCompletionState(for: subject, modelContext: context)

        #expect(subject.completedAt == today)
        #expect(
            CadenceTaskQuerySupport.completedTodayTasks(from: [subject], todayKey: todayKey)
                .map(\.title) == ["finished today"]
        )
    }

    /// `markDone`'s *second* side effect, and the reason routing a normalizer through a transition
    /// is wrong in principle and not just in its timestamp: it spawns the next occurrence. A done
    /// recurring task whose successor pointer is nil — an unfinished series, or one whose successor
    /// was deleted and the pointer repaired — grew a brand new task every time the sheet saved.
    /// Same hazard `docs/TODO.md` T-214 records against `applyStatusCompletion`: a bulk or
    /// incidental path must not mint work.
    @Test func theNormalizerDoesNotMintARecurrenceOccurrence() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let subject = task("water the plants", status: .done, completedAt: try instant("2026-08-13"))
        subject.recurrenceRule = .daily
        context.insert(subject)
        try context.save()
        #expect(subject.recurrenceSpawnedTaskID == nil)
        #expect(subject.shouldSpawnNextOccurrence(nextDateKey: "2026-08-14"))

        CadenceTaskMutationSupport.normalizeCompletionState(for: subject, modelContext: context)

        #expect(subject.recurrenceSpawnedTaskID == nil)
        #expect(
            try context.fetch(FetchDescriptor<AppTask>()).count == 1,
            "the normalizer spawned a recurrence occurrence"
        )
    }

    /// `markTodo` is the same line pointing the other way, and it was already right: restoring a
    /// task to `todo` clears the timestamp, so a reopened task cannot linger in Today's Completed.
    /// Pinned because it is now load-bearing in a way it was not while `markCancelled` also
    /// cleared it.
    @Test func restoringATaskClearsTheTimestampAgain() throws {
        let subject = task("abandoned")
        try cancelling(subject, at: instant(todayKey))
        #expect(subject.completedAt != nil)

        CadenceTaskRecurrenceWorkflowSupport.markTodo(subject)

        #expect(subject.completedAt == nil)
        #expect(CadenceTaskQuerySupport.completedTodayTasks(from: [subject], todayKey: todayKey).isEmpty)
    }

    // MARK: - T-212: winding a container down settles its work, and advances no series

    /// An area holding `tasks`, inserted so `TaskContainerLifecycleService` can walk it.
    private func containerArea(
        _ name: String,
        holding tasks: [AppTask],
        in context: ModelContext
    ) -> Area {
        let area = Area(name: name)
        context.insert(area)
        for task in tasks {
            context.insert(task)
        }
        area.tasks = tasks
        return area
    }

    /// The T-212 bug. `finishRemainingActiveTasks` hand-wrote the cancel transition and set
    /// `completedAt = nil`, so completing or archiving a list produced untimestamped cancellations
    /// after T-202 had made every other cancellation in the app a timestamped event. Both of these
    /// tasks are the kind that has nothing else to stand on: one overdue, one dateless.
    @Test func archivingAListTimestampsTheCancellationsItProduces() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let overdue = task("overdue", doDate: "2026-08-01", dueDate: "2026-08-02")
        let dateless = task("dateless")
        let area = containerArea("wound down", holding: [overdue, dateless], in: context)

        TaskContainerLifecycleService.cancelRemainingActiveTasks(
            in: area,
            includingChildProjects: true,
            in: context
        )

        #expect(overdue.isCancelled)
        #expect(dateless.isCancelled)
        #expect(overdue.completedAt != nil)
        #expect(dateless.completedAt != nil)

        let today = DateFormatters.todayKey()
        #expect(
            CadenceTaskQuerySupport.completedTodayTasks(from: [overdue, dateless], todayKey: today)
                .map(\.title).sorted() == ["dateless", "overdue"]
        )
    }

    /// macOS's Today Completed section is the stricter filter — in `.todayOverview` it asks about
    /// `completedAt` and has no do-date or due-date ground to fall back on — so it is the surface
    /// where an untimestamped bulk cancellation disappeared completely. Pinned separately for the
    /// same reason `macOSTodayCompletedAlsoAdmitsTheCancelledTask` is.
    @Test func macOSTodayCompletedAdmitsTheTasksAKanbanColumnArchiveCancelled() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let subject = task("in the archived column")
        subject.sectionName = "Doing"
        let area = containerArea("board", holding: [subject], in: context)
        let section = TaskSectionConfig(name: "Doing")

        TaskContainerLifecycleService.cancelRemainingActiveTasks(
            in: section,
            area: area,
            project: nil,
            in: context
        )

        #expect(subject.isCancelled)
        let state = TasksPanelDerivedState(
            allTasks: [subject],
            areas: [area],
            projects: [],
            mode: .todayOverview,
            todayKey: DateFormatters.todayKey(),
            sortField: .date,
            sortDirection: .ascending
        )
        #expect(state.doneTasks.map(\.title) == ["in the archived column"])
    }

    /// One click settling twelve tasks settled them at one moment, so they carry one timestamp
    /// rather than a scatter of them — which is also what keeps their order in the logbook stable
    /// under `completionPrecedes`.
    @Test func oneContainerActionSettlesEveryTaskAtTheSameInstant() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let first = task("first")
        let second = task("second")
        let area = containerArea("wound down", holding: [first, second], in: context)

        TaskContainerLifecycleService.cancelRemainingActiveTasks(
            in: area,
            includingChildProjects: true,
            in: context
        )

        #expect(first.completedAt != nil)
        #expect(first.completedAt == second.completedAt)
    }

    /// The other half of the ticket, and the half the ticket got backwards: it asked for this path
    /// to be routed through `markCancelled` so it *would* spawn a successor. It must not. The
    /// successor `spawnNextOccurrenceIfNeeded` builds inherits `area`, `project` and `sectionName`,
    /// so archiving a list containing a daily task would immediately refill the list it just
    /// closed — the same hazard T-213 fixed in the normalizer and T-214 records against
    /// `applyStatusCompletion`. The `shouldSpawnNextOccurrence` expectation is the non-vacuity
    /// check: without it this passes on a task that could never have spawned anything.
    @Test func archivingAListDoesNotMintTheNextRecurrenceOccurrence() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let subject = task("water the plants", doDate: DateFormatters.todayKey())
        subject.recurrenceRule = .daily
        let area = containerArea("wound down", holding: [subject], in: context)
        try context.save()
        #expect(subject.shouldSpawnNextOccurrence(nextDateKey: "2026-12-31"))

        TaskContainerLifecycleService.cancelRemainingActiveTasks(
            in: area,
            includingChildProjects: true,
            in: context
        )

        #expect(subject.isCancelled)
        #expect(subject.recurrenceSpawnedTaskID == nil)
        #expect(
            try context.fetch(FetchDescriptor<AppTask>()).count == 1,
            "archiving a list spawned a recurrence occurrence into the list it just closed"
        )
    }

    /// Completing a project is the same shape pointing the other way, and it was already right —
    /// pinned so a later "make the two branches symmetric" pass cannot make it wrong by routing
    /// both through the single-task transitions.
    @Test func completingAProjectDoesNotMintTheNextRecurrenceOccurrence() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let subject = task("weekly review", doDate: DateFormatters.todayKey())
        subject.recurrenceRule = .weekly
        let project = Project(name: "wound down")
        context.insert(project)
        context.insert(subject)
        project.tasks = [subject]
        try context.save()
        #expect(subject.shouldSpawnNextOccurrence(nextDateKey: "2026-12-31"))

        TaskContainerLifecycleService.completeRemainingActiveTasks(in: project, in: context)

        #expect(subject.isDone)
        #expect(subject.completedAt != nil)
        #expect(subject.recurrenceSpawnedTaskID == nil)
        #expect(try context.fetch(FetchDescriptor<AppTask>()).count == 1)
    }

    /// Work already settled is left exactly as it was. The guard reads **status alone**
    /// (`!isDone && !isCancelled`), which is the spelling that stayed correct once a cancelled task
    /// began carrying a `completedAt`; a guard that also asked `completedAt == nil` would have
    /// re-stamped last week's cancellation to today and dragged it into Today's Completed section.
    @Test func windingDownAContainerLeavesAlreadySettledWorkUntouched() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let lastWeek = try instant("2026-08-13")
        let doneEarlier = task("done last week", status: .done, completedAt: lastWeek)
        let cancelledEarlier = task("cancelled last week", status: .cancelled, completedAt: lastWeek)
        let area = containerArea(
            "wound down",
            holding: [doneEarlier, cancelledEarlier],
            in: context
        )

        TaskContainerLifecycleService.cancelRemainingActiveTasks(
            in: area,
            includingChildProjects: true,
            in: context
        )

        #expect(doneEarlier.status == .done)
        #expect(doneEarlier.completedAt == lastWeek)
        #expect(cancelledEarlier.status == .cancelled)
        #expect(cancelledEarlier.completedAt == lastWeek)
    }

    // MARK: - The row must not read as done

    /// Strikethrough, dim, a cross — and never `Theme.doneFill`. Both platforms resolve the row's
    /// circle through this one decision, so the ring and the title cannot disagree.
    @Test func aCancelledRowIsSettledWithoutBeingGreen() {
        let cancelled = CadenceTaskCompletionGlyph.resolve(status: .cancelled, priority: .high)
        let done = CadenceTaskCompletionGlyph.resolve(status: .done, priority: .high)

        #expect(CadenceTaskCompletionState.resolve(status: .cancelled).isSettled)
        #expect(CadenceTaskCompletionState.resolve(status: .done).isSettled)
        #expect(!CadenceTaskCompletionState.resolve(status: .todo).isSettled)

        #expect(cancelled.mark == .cross)
        #expect(cancelled.isFilled)
        #expect(cancelled.tint == Theme.dim)
        #expect(cancelled.tint != Theme.doneFill)
        #expect(done.tint == Theme.doneFill)
        #expect(cancelled.symbolName != done.symbolName)
    }

    // MARK: - Call sites

    /// The predicate is only worth one place if the three completed queries actually read it, and
    /// only three of the six filters in that file may still mention `isCancelled` — the active ones.
    @Test func theCompletedQueriesAllReadTheOnePredicate() throws {
        try expectOccurrences(
            of: "isFinishedTask(",
            at: [
                "Cadence/Shared/CadenceTaskQuerySupport.swift": 3,
                "Cadence/Shared/CadenceTaskQuerySharedSupport.swift": 2
            ]
        )
        try expectOccurrences(
            of: "isCancelled",
            at: [
                // activeTodayTasks, activeInboxTasks, activeTasks — and nothing else.
                "Cadence/Shared/CadenceTaskQuerySupport.swift": 3,
                // openTasks, isFinishedTask, isOpenTask. `inboxTasks` is no longer one of them.
                "Cadence/Shared/CadenceTaskQuerySharedSupport.swift": 3
            ]
        )
        // The three retired spellings, each chosen so it cannot also match the *active* filter it
        // sits beside — `"$0.isDone && !$0.isCancelled }"` is a substring of
        // `"!$0.isDone && !$0.isCancelled }"`, which is how a first draft of this test failed
        // against correct code.
        for retired in ["guard task.isDone", ".filter { $0.isDone", "&& $0.isDone && !"] {
            try expectOccurrences(
                of: retired,
                at: ["Cadence/Shared/CadenceTaskQuerySupport.swift": 0]
            )
        }
    }

    /// `iOSTaskRow` struck through on `task.isDone` alone, so a cancelled row drew a dim cross in
    /// its circle beside a full-contrast, un-struck title. It reads the shared settled state now —
    /// which is also what resolved that circle — and mentions `isCancelled` nowhere itself.
    ///
    /// The three surviving `task.isDone` mentions are the accessibility label, the over-do test and
    /// the due-urgency call, each of which correctly asks about *done* specifically.
    @Test func theIOSRowAndTheInspectorTitleBothReadTheSharedSettledState() throws {
        try expectOccurrences(
            of: "isSettled",
            at: [
                "Cadence/iOS/iOSTaskViews.swift": 5,
                "Cadence/iOS/iOSTaskDetailComponents.swift": 4
            ]
        )
        try expectOccurrences(
            of: "CadenceTaskCompletionState.resolve(task: task).isSettled",
            at: [
                "Cadence/iOS/iOSTaskViews.swift": 1,
                "Cadence/iOS/iOSTaskDetailComponents.swift": 1
            ]
        )
        try expectOccurrences(
            of: "strikethrough(task.isDone",
            at: ["Cadence/iOS/iOSTaskViews.swift": 0]
        )
        try expectOccurrences(
            of: "task.isDone || task.isCancelled",
            at: ["Cadence/iOS/iOSTaskDetailComponents.swift": 0]
        )
        try expectOccurrences(
            of: "task.isDone",
            at: ["Cadence/iOS/iOSTaskViews.swift": 3]
        )
    }

    /// macOS's row has spelled the settled test `isDone || isCancelled` all along, in three places
    /// in one file. It is left as it is on purpose — but if it ever loses that spelling, the two
    /// platforms are disagreeing about a cancelled row again.
    @Test func theMacRowStillTreatsCancelledAsSettled() throws {
        try expectOccurrences(
            of: "isDone || task.isCancelled",
            at: ["Cadence/macOS/Views/TasksPanelComponents.swift": 3]
        )
    }

    /// T-203: both Calendar Board day columns split their cards on `isDone`, and a cancelled task
    /// is not `isDone` — so it would have landed in the **active** half, the work you still intend
    /// to do. It never arrived, only because `CalendarBoardPlannerSupport`'s day bucketing drops
    /// cancelled work upstream as a matter of policy. The split reads `isFinishedTask` now, so the
    /// classification is right by construction rather than by what happens to reach it.
    ///
    /// This is a **no-op today by design** — `aCancelledTaskIsStillOffTheScheduleTheRailsAndTheOverdueCount`
    /// above pins that nothing moved — so no behavioural test can tell the fix from its absence.
    /// A source scan is the only thing that can.
    ///
    /// **T-227 rewrote the negative half of this scan, and shrank it.** It used to ban three
    /// substrings from two whole view files — `"tasks.filter { !$0.isDone }"`,
    /// `"tasks.filter { $0.isDone }"`, and the bare `"$0.isDone"` — and each was a trap of a
    /// different size. The bare one failed any innocent mention: a done count, a done card styled
    /// unlike a cancelled one. The positive-form literal failed a done count spelled on the same
    /// receiver, `tasks.filter { $0.isDone }.count`. What is left is:
    ///
    /// - **one regex, one polarity.** `filter { !$0.isDone }` as a whole predicate can only mean
    ///   "the work you still intend to do", which *is* the misclassification. It is receiver-
    ///   agnostic, so `dayTasks.filter { !$0.isDone }` is caught too, which the old exact literal
    ///   missed. A positive `$0.isDone` cannot be judged out of context, so it is not judged.
    /// - **the positive count, which already covered the settled half.** Two
    ///   `isFinishedTask($0)` calls per file is one per half, so a regression in *either* half
    ///   drops the count and fails — that is what the retired positive-form literal was for, said
    ///   without a needle that can hit correct code.
    @Test func neitherCalendarBoardDayColumnStillSplitsOnDoneAlone() throws {
        let columns = [
            "Cadence/macOS/Views/CalendarBoardDayColumnSupportViews.swift",
            "Cadence/iOS/iOSCalendarBoardView.swift"
        ]
        let zeroInBoth = Dictionary(uniqueKeysWithValues: columns.map { ($0, 0) })

        try expectPatternOccurrences(of: activeHalfSplitOnDoneAlone, at: zeroInBoth)
        try expectOccurrences(
            of: "CadenceTaskQuerySupport.isFinishedTask($0)",
            at: Dictionary(uniqueKeysWithValues: columns.map { ($0, 2) })
        )

        // The needle is not vacuous, and it does not reach the spellings that are fine.
        #expect("tasks.filter { !$0.isDone }".matchCount(ofPattern: activeHalfSplitOnDoneAlone) == 1)
        #expect("dayTasks.filter{!$0.isDone}".matchCount(ofPattern: activeHalfSplitOnDoneAlone) == 1)
        #expect("tasks.filter { $0.isDone }.count".matchCount(ofPattern: activeHalfSplitOnDoneAlone) == 0)
        #expect("$0.isDone ? Theme.doneFill : Theme.dim".matchCount(ofPattern: activeHalfSplitOnDoneAlone) == 0)

        // And the upstream filter stays exactly where it was: the fix was the accident, not the
        // policy. Cancelled work is still off the Board.
        try expectOccurrences(
            of: "guard !task.isCancelled, task.bundle == nil",
            at: ["Cadence/Shared/CadenceCalendarPlanningSupport.swift": 1]
        )
    }

    /// Without this, every zero above could be a scan reading an empty string — the exact failure
    /// mode a `/tmp` against `/private/tmp` path mismatch produces on an isolated build tree.
    @Test func theSourceScanIsNotVacuous() throws {
        let files = try swiftFiles(under: "Cadence")

        #expect(files.count > 300, "the source scan found \(files.count) files and cannot be doing its job")
        #expect(files.contains("Cadence/Shared/CadenceTaskQuerySupport.swift"))
        #expect(files.contains("Cadence/Shared/CadenceTaskQuerySharedSupport.swift"))
        #expect(files.contains("Cadence/iOS/iOSTaskViews.swift"))
        #expect(files.contains("Cadence/iOS/iOSTaskDetailComponents.swift"))
        #expect(files.contains("Cadence/macOS/Views/TasksPanelComponents.swift"))
        #expect(files.contains("Cadence/macOS/Views/CalendarBoardDayColumnSupportViews.swift"))
        #expect(files.contains("Cadence/iOS/iOSCalendarBoardView.swift"))

        let queries = try strippingComments(sourceFile("Cadence/Shared/CadenceTaskQuerySharedSupport.swift"))
        #expect(queries.contains("static func isFinishedTask"))

        let row = try strippingComments(sourceFile("Cadence/iOS/iOSTaskViews.swift"))
        #expect(row.contains("struct iOSTaskRow: View"))

        let macColumn = try strippingComments(sourceFile("Cadence/macOS/Views/CalendarBoardDayColumnSupportViews.swift"))
        #expect(macColumn.contains("struct CalendarBoardDayColumn: View"))

        let iosColumn = try strippingComments(sourceFile("Cadence/iOS/iOSCalendarBoardView.swift"))
        #expect(iosColumn.contains("struct iOSCalendarBoardDayColumn: View"))
    }
}

// MARK: - Source-reading helpers

/// The retired active-half split, receiver-agnostic and whitespace-tolerant: any `filter` whose
/// entire predicate is `!$0.isDone`.
private let activeHalfSplitOnDoneAlone = "\\.filter\\s*\\{\\s*!\\s*\\$0\\.isDone\\s*\\}"

private extension String {
    /// Regex match count, for scans where a bare substring over-matches or under-matches.
    func matchCount(ofPattern pattern: String) -> Int {
        var count = 0
        var searchRange = startIndex..<endIndex
        while let found = range(of: pattern, options: .regularExpression, range: searchRange) {
            count += 1
            searchRange = found.upperBound..<endIndex
        }
        return count
    }
}

/// `expectOccurrences`, but the needle is a regular expression. Prefer this whenever a substring
/// would also match code that is perfectly fine — see T-227.
private func expectPatternOccurrences(
    of pattern: String,
    at files: [String: Int],
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    for (path, expected) in files {
        let code = try strippingComments(sourceFile(path))
        let actual = code.matchCount(ofPattern: pattern)
        #expect(
            actual == expected,
            "\(path) matches /\(pattern)/ \(actual) times, expected \(expected)",
            sourceLocation: sourceLocation
        )
    }
}

/// Fails unless `text` occurs exactly `count` times as live code in each listed file.
///
/// Exact counts, not "contains": a mutation run against `CadenceSharedBoardChromeTests` caught a
/// version asserting only that each file mentioned the shared decision somewhere, and reverting one
/// of four call sites left it green.
private func expectOccurrences(
    of text: String,
    at files: [String: Int],
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    for (path, expected) in files {
        let code = try strippingComments(sourceFile(path))
        let actual = code.components(separatedBy: text).count - 1
        #expect(
            actual == expected,
            "\(path) contains \(text) \(actual) times, expected \(expected)",
            sourceLocation: sourceLocation
        )
    }
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

/// `enumerator(atPath:)` rather than `enumerator(at:)`: the URL variant yields absolute paths, and
/// `#filePath` can name the repo through a symlinked prefix (`/tmp` against `/private/tmp` on an
/// isolated build tree) that `FileManager` resolves and the literal does not.
private func swiftFiles(under relativeDirectory: String) throws -> [String] {
    let directory = repositoryRoot().appendingPathComponent(relativeDirectory)
    guard let enumerator = FileManager.default.enumerator(atPath: directory.path) else {
        return []
    }
    return enumerator.compactMap { element in
        guard let relativePath = element as? String, relativePath.hasSuffix(".swift") else { return nil }
        return "\(relativeDirectory)/\(relativePath)"
    }
}

private func sourceFile(_ relativePath: String) throws -> String {
    try String(contentsOf: repositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
}

/// Blanks `//` line comments and `/* */` block comments so the assertions read code rather than
/// prose. Crude on purpose: a `//` inside a string literal is blanked too, which can only make
/// these checks stricter about what counts as a comment, never looser about live code.
private func strippingComments(_ source: String) throws -> String {
    var result = source
    for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            result.replaceSubrange(range, with: String(repeating: " ", count: result.distance(from: range.lowerBound, to: range.upperBound)))
        }
    }
    return result
}
