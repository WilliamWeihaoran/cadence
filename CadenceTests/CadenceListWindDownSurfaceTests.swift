// T-3244: compiled for macOS only. `CadenceTests` now also builds for an iOS destination, and
// this suite reaches macOS-only app types that do not exist there. The gate preserves exactly the
// coverage this file had before; narrowing it so any cross-platform half runs on iOS too is
// follow-up, not part of making the target iOS-capable.
#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// T-215 and T-214, which are one surface: winding a list down on iOS.
///
/// **T-215** was the archive half. macOS's archive cancelled a list's remaining active tasks and
/// iOS's archive only wrote `status = .archived`, so the same area wound down to two different sets
/// of open work depending on which device the swipe happened on. The divergence existed because
/// `TaskContainerLifecycleService` sat inside `TaskWorkflowService.swift`'s `#if os(macOS)` while
/// importing nothing platform-specific — the sixth instance of that shape after `RemindersManager`,
/// `PrivacyDataResetService`, `ListDeleteHelpers`, SchedulingActions.createBundle(from:adding:) (since removed, [[T-3170]])
/// and the list delete cascades.
///
/// **T-214** is the completion half, and it is not the same ticket with a word changed. The service
/// was already cross-platform, public and tested by then — the un-guard *was* T-215's doing — so
/// what was missing was only an affordance. What made it worth its own entry is that completing a
/// list settles its work as `.done`, which asserts the work happened: `GoalContributionSummary`
/// reads `filter(\.isDone)` over `completedTasks / totalTasks`, so bulk completion can move a
/// goal's bar where bulk cancellation cannot. Hence the same sheet, the same conditional rule and
/// different copy — and hence the tests below run both directions against the same fixtures rather
/// than trusting that "it is the archive path with an enum flipped".
///
/// **Two kinds of test here, and the second kind is the point.** Pinning the arithmetic proves the
/// confirmation counts truthfully; it proves nothing about iOS *reaching* the wind-down.
/// `Cadence/iOS/` is entirely inside `#if os(iOS)` and this target builds for macOS, so there is no
/// iOS symbol to reference and the only available tool is a source-text assertion. The helpers
/// follow `CadenceListDeletionSurfaceTests`: exact per-file counts rather than "contains",
/// comment-stripping rather than allowlisting, and a non-vacuity test so a broken scan cannot make
/// the absence assertions pass silently.
@MainActor
struct CadenceListWindDownSurfaceTests {

    private func container() throws -> ModelContainer {
        try CadenceModelContainerFactory.makeInMemoryContainer()
    }

    private func task(_ title: String, status: TaskStatus = .todo) -> AppTask {
        let task = AppTask(title: title)
        task.status = status
        if status == .done || status == .cancelled {
            task.completedAt = Date(timeIntervalSince1970: 1_700_000_000)
        }
        return task
    }

    // MARK: - What the confirmation promises

    /// The count is the settle's own array. An area rolls up its child projects — because that is
    /// what `cancelRemainingActiveTasks(in:includingChildProjects:)` walks, and a child project
    /// keeps its own `status`, so its tasks stay reachable from All Tasks after the parent is filed
    /// away — and already-settled work is excluded, because the wind-down leaves it alone.
    @Test func theArchiveSummaryCountsExactlyWhatTheWindDownWillSettle() throws {
        let modelContext = ModelContext(try container())
        let area = Area(name: "Home")
        let child = Project(name: "Kitchen", area: area)

        let open = task("open")
        open.area = area
        let inProgress = task("in progress", status: .inProgress)
        inProgress.area = area
        let alreadyDone = task("done", status: .done)
        alreadyDone.area = area
        let alreadyCancelled = task("cancelled", status: .cancelled)
        alreadyCancelled.area = area
        let openInChild = task("open in child")
        openInChild.project = child

        for model in [open, inProgress, alreadyDone, alreadyCancelled, openInChild] {
            modelContext.insert(model)
        }
        modelContext.insert(area)
        modelContext.insert(child)
        area.tasks = [open, inProgress, alreadyDone, alreadyCancelled]
        area.projects = [child]
        child.tasks = [openInChild]
        try modelContext.save()

        let summary = CadenceContainerWindDownSummary.forArea(area, outcome: .cancelled)
        #expect(summary.openTasks == 3)
        #expect(summary.requiresConfirmation)
        #expect(!summary.isEmpty)

        // And the number was a promise: exactly those three change, and nothing else does.
        TaskContainerLifecycleService.cancelRemainingActiveTasks(
            in: area,
            includingChildProjects: true,
            in: modelContext
        )
        let cancelled = [open, inProgress, openInChild].map(\.isCancelled)
        #expect(cancelled == [true, true, true])
        #expect(alreadyDone.status == .done)
        #expect(alreadyCancelled.status == .cancelled)
        #expect(CadenceContainerWindDownSummary.forArea(area, outcome: .cancelled).openTasks == 0)
    }

    /// A task carrying both an `area` and a `project` under that area appears in two of the
    /// relationship arrays the walk visits. Counting it twice would inflate the number the user is
    /// deciding on — the same trap `CadenceListDeletionSummary` documents for the delete cascade.
    @Test func aTaskFiledUnderBothAnAreaAndItsProjectIsCountedOnce() throws {
        let modelContext = ModelContext(try container())
        let area = Area(name: "Home")
        let child = Project(name: "Kitchen", area: area)
        let subject = task("filed twice")
        subject.area = area
        subject.project = child

        modelContext.insert(area)
        modelContext.insert(child)
        modelContext.insert(subject)
        area.tasks = [subject]
        area.projects = [child]
        child.tasks = [subject]
        try modelContext.save()

        #expect(CadenceContainerWindDownSummary.forArea(area, outcome: .cancelled).openTasks == 1)
    }

    /// A project's summary is its own tasks and nothing else — there is no container below it.
    @Test func aProjectSummaryCountsItsOwnOpenTasks() throws {
        let modelContext = ModelContext(try container())
        let project = Project(name: "Ship")
        let open = task("open")
        open.project = project
        let done = task("done", status: .done)
        done.project = project

        modelContext.insert(project)
        modelContext.insert(open)
        modelContext.insert(done)
        project.tasks = [open, done]
        try modelContext.save()

        #expect(CadenceContainerWindDownSummary.forProject(project, outcome: .cancelled).openTasks == 1)
    }

    /// The conditional-confirmation rule. Archiving a list with nothing open in it flips one flag
    /// and is one tap from Restore, so iOS performs it on the spot; a sheet that appears even when
    /// the answer is "nothing happens" is a sheet people learn to dismiss without reading.
    @Test func aListWithNothingStillOpenNeedsNoConfirmation() throws {
        let modelContext = ModelContext(try container())
        let area = Area(name: "Finished")
        let done = task("done", status: .done)
        done.area = area
        modelContext.insert(area)
        modelContext.insert(done)
        area.tasks = [done]
        try modelContext.save()

        let summary = CadenceContainerWindDownSummary.forArea(area, outcome: .cancelled)
        #expect(summary.isEmpty)
        #expect(!summary.requiresConfirmation)
        #expect(summary.settledLine == nil)
    }

    @Test func theSettledLineCountsAndPluralizesAndSaysNothingAtZero() {
        #expect(CadenceContainerWindDownSummary(openTasks: 1).settledLine == "1 open task will be canceled")
        #expect(CadenceContainerWindDownSummary(openTasks: 7).settledLine == "7 open tasks will be canceled")
        #expect(CadenceContainerWindDownSummary(openTasks: 0).settledLine == nil)
        #expect(CadenceContainerWindDownSummary().isEmpty)
    }

    // MARK: - The completion direction (T-214)

    /// The count is the same walk in both directions and only the sentence over it differs. Pinned
    /// against one fixture so a completion cannot come to promise a different number than the
    /// archive of the same list would — which is what a second pair of factories beside
    /// `forArea` / `forProject` would eventually have produced.
    @Test func bothDirectionsCountTheSameArrayAndNameTheirOwnOutcome() throws {
        let modelContext = ModelContext(try container())
        let area = Area(name: "Home")
        let child = Project(name: "Kitchen", area: area)
        let open = task("open")
        open.area = area
        let openInChild = task("open in child")
        openInChild.project = child
        let alreadyDone = task("done", status: .done)
        alreadyDone.area = area

        for model in [open, openInChild, alreadyDone] {
            modelContext.insert(model)
        }
        modelContext.insert(area)
        modelContext.insert(child)
        area.tasks = [open, alreadyDone]
        area.projects = [child]
        child.tasks = [openInChild]
        try modelContext.save()

        let archiving = CadenceContainerWindDownSummary.forArea(area, outcome: .cancelled)
        let completing = CadenceContainerWindDownSummary.forArea(area, outcome: .done)
        #expect(archiving.openTasks == 2)
        #expect(completing.openTasks == archiving.openTasks)
        #expect(archiving.settledLine == "2 open tasks will be canceled")
        #expect(completing.settledLine == "2 open tasks will be marked done")

        let project = CadenceContainerWindDownSummary.forProject(child, outcome: .done)
        #expect(project.openTasks == 1)
        #expect(project.settledLine == "1 open task will be marked done")
    }

    /// **The conditional-confirmation rule is deliberately identical in both directions**, and that
    /// is a decision rather than an oversight. `requiresConfirmation` is not a measure of how strong
    /// a claim the action makes — it asks whether anything irreversible happens at all. Completing a
    /// list with nothing open writes one `status` and settles nothing, and a sheet over a no-op is a
    /// sheet people learn to dismiss without reading, which is what would blunt the one that matters.
    @Test func theConditionalRuleDoesNotDependOnTheDirection() throws {
        let modelContext = ModelContext(try container())
        let empty = Area(name: "Finished")
        let done = task("done", status: .done)
        done.area = empty
        let busy = Area(name: "Busy")
        let open = task("open")
        open.area = busy

        for model in [done, open] { modelContext.insert(model) }
        modelContext.insert(empty)
        modelContext.insert(busy)
        empty.tasks = [done]
        busy.tasks = [open]
        try modelContext.save()

        for outcome in CadenceWindDownOutcome.allCases {
            #expect(!CadenceContainerWindDownSummary.forArea(empty, outcome: outcome).requiresConfirmation)
            #expect(CadenceContainerWindDownSummary.forArea(busy, outcome: outcome).requiresConfirmation)
        }
    }

    /// Completing a list settles as `.done`, not `.cancelled`, and stamps the batch — the same
    /// `completedAt` invariant T-202 states, which is what lets the settled rows reach Today's
    /// Completed section at all. Work already settled either way is left exactly as it was, because
    /// the filter reads **status alone**: a task cancelled last week must not be re-stamped to today
    /// and dragged into today's Completed section by a wind-down that never touched it.
    @Test func completingAListMarksItsRemainingWorkDoneRatherThanCancelled() throws {
        let modelContext = ModelContext(try container())
        let area = Area(name: "Home")
        let child = Project(name: "Kitchen", area: area)
        let open = task("open")
        open.area = area
        let inProgress = task("in progress", status: .inProgress)
        inProgress.area = area
        let openInChild = task("open in child")
        openInChild.project = child
        let oldCancellation = task("abandoned", status: .cancelled)
        oldCancellation.area = area
        let stamp = oldCancellation.completedAt

        for model in [open, inProgress, openInChild, oldCancellation] {
            modelContext.insert(model)
        }
        modelContext.insert(area)
        modelContext.insert(child)
        area.tasks = [open, inProgress, oldCancellation]
        area.projects = [child]
        child.tasks = [openInChild]
        try modelContext.save()

        TaskContainerLifecycleService.completeRemainingActiveTasks(
            in: area,
            includingChildProjects: true,
            in: modelContext
        )
        try modelContext.save()

        // `map` / `compactMap` are `rethrows`, and a `rethrows` call inside `#expect` does not
        // compile — the macro expansion is not a throwing context. Compute outside, assert inside.
        let settled = [open, inProgress, openInChild]
        let statuses = settled.map(\.status)
        let stamps = settled.compactMap(\.completedAt)
        #expect(statuses == [.done, .done, .done])
        #expect(stamps.count == 3)
        // One `Date()` for the batch: a single tap settling three tasks settled them at once.
        #expect(Set(stamps).count == 1)

        #expect(oldCancellation.status == .cancelled)
        #expect(oldCancellation.completedAt == stamp)
        #expect(CadenceContainerWindDownSummary.forArea(area, outcome: .done).openTasks == 0)
    }

    /// **T-212/T-213's invariant, on the direction T-214 is about, and this is the direction where
    /// it bites hardest.** `markDone` spawns the next occurrence and `makeNextRecurringTask` copies
    /// `area`, `project` and `sectionName`, so a completion routed through it would mark the list
    /// done and immediately refill it with fresh open work — a list that reads finished and is not.
    /// The control at the end is the point: the same task, completed the single-task way, does mint
    /// a successor, so the first assertion cannot be passing because the recurrence was never
    /// configured.
    @Test func aListCompletionDoesNotRefillTheListItJustFinished() throws {
        let modelContext = ModelContext(try container())
        let project = Project(name: "Ship")
        let recurring = task("standup")
        recurring.recurrenceRule = .daily
        recurring.scheduledDate = DateFormatters.todayKey()
        recurring.project = project
        modelContext.insert(project)
        modelContext.insert(recurring)
        project.tasks = [recurring]
        try modelContext.save()

        TaskContainerLifecycleService.completeRemainingActiveTasks(in: project, in: modelContext)
        try modelContext.save()

        #expect(recurring.isDone)
        #expect(recurring.recurrenceSpawnedTaskID == nil)
        #expect(try modelContext.fetch(FetchDescriptor<AppTask>()).count == 1)

        // Control: the single-task transition on an identical task does spawn one.
        let control = task("standup control")
        control.recurrenceRule = .daily
        control.scheduledDate = DateFormatters.todayKey()
        control.project = project
        modelContext.insert(control)
        project.tasks = (project.tasks ?? []) + [control]
        try modelContext.save()

        CadenceTaskRecurrenceWorkflowSupport.markDone(control, in: modelContext)
        try modelContext.save()

        #expect(control.recurrenceSpawnedTaskID != nil)
        #expect(try modelContext.fetch(FetchDescriptor<AppTask>()).count == 3)
    }

    /// The outcome vocabulary itself, because both sheets read their button colour, their section
    /// label and their settled sentence off it. Two cases, and `settledPhrase` is the only place the
    /// distinction is spelled in words.
    @Test func theOutcomeNamesBothSettlementsAndNothingElse() {
        #expect(CadenceWindDownOutcome.allCases.count == 2)
        #expect(CadenceWindDownOutcome.cancelled.settledPhrase == "canceled")
        #expect(CadenceWindDownOutcome.done.settledPhrase == "marked done")
    }

    // MARK: - The wind-down is no longer macOS-only

    /// `remainingActiveTasks` is the array the settle walks, not a second walk that happens to
    /// agree — which is what lets the confirmation count without over-promising. Pinned by identity
    /// rather than by count.
    @Test func theExposedArrayIsTheOneTheSettleActuallyWalks() throws {
        let modelContext = ModelContext(try container())
        let area = Area(name: "Home")
        let open = task("open")
        open.area = area
        let done = task("done", status: .done)
        done.area = area
        modelContext.insert(area)
        modelContext.insert(open)
        modelContext.insert(done)
        area.tasks = [open, done]
        try modelContext.save()

        let promised = TaskContainerLifecycleService.remainingActiveTasks(in: area, includingChildProjects: true)
        #expect(promised.map(\.id) == [open.id])

        TaskContainerLifecycleService.cancelRemainingActiveTasks(
            in: area,
            includingChildProjects: true,
            in: modelContext
        )
        let changed = [open, done].filter(\.isCancelled)
        #expect(changed.map(\.id) == promised.map(\.id))
    }

    /// A kanban column is the third container the service winds down, and its accessor moved with
    /// the other two. Pinned so the section overload is not quietly dropped as unused: macOS's
    /// column archive is its only caller today, and it is the surface T-247 is about.
    @Test func theSectionOverloadStillScopesToItsColumn() throws {
        let modelContext = ModelContext(try container())
        let area = Area(name: "Board")
        let inColumn = task("in column")
        inColumn.sectionName = "Doing"
        inColumn.area = area
        let elsewhere = task("elsewhere")
        elsewhere.sectionName = "Later"
        elsewhere.area = area
        modelContext.insert(area)
        modelContext.insert(inColumn)
        modelContext.insert(elsewhere)
        area.tasks = [inColumn, elsewhere]
        try modelContext.save()

        let remaining = TaskContainerLifecycleService.remainingActiveTasks(
            in: TaskSectionConfig(name: "Doing"),
            area: area,
            project: nil
        )
        #expect(remaining.map(\.title) == ["in column"])
    }

    /// The type left the macOS guard whole. The new file carries no platform conditional at all —
    /// not "one documented seam" as `CadenceListDeleteHelpers` does, because there is nothing here
    /// that needs one — and the old file no longer declares it.
    @Test func theLifecycleServiceLivesInServicesWithNoPlatformConditional() throws {
        let moved = try strippingComments(sourceFile("Cadence/Services/CadenceTaskContainerLifecycleService.swift"))
        #expect(moved.contains("enum TaskContainerLifecycleService {"))
        #expect(moved.contains("struct CadenceContainerWindDownSummary"))
        #expect(moved.contains("enum CadenceWindDownOutcome"))
        #expect(moved.components(separatedBy: "#if os(").count - 1 == 0)

        let old = try strippingComments(sourceFile("Cadence/macOS/Services/TaskWorkflowService.swift"))
        #expect(old.contains("enum TaskWorkflowService {"))
        #expect(!old.contains("enum TaskContainerLifecycleService"))

        // The move is recorded where somebody would go looking for it. Read from the raw source,
        // because the tombstone is a comment and `strippingComments` blanks it.
        let raw = try sourceFile("Cadence/macOS/Services/TaskWorkflowService.swift")
        #expect(raw.contains("CadenceTaskContainerLifecycleService.swift"))
    }

    // MARK: - iOS reaches it, from one place

    /// The wind-down is reached from exactly one iOS file, **once per container kind per
    /// direction**. A second call site would mean some surface had grown its own archive or its own
    /// completion beside the one that confirms.
    @Test func iOSWindsListsDownThroughTheSharedServiceFromOnePlaceOnly() throws {
        try expectCallSites(of: "TaskContainerLifecycleService.cancelRemainingActiveTasks", at: [
            "Cadence/iOS/iOSListWindDownSupport.swift": 2,
            "Cadence/iOS/iOSListViews.swift": 0,
            "Cadence/iOS/iOSListsRegularPane.swift": 0
        ])

        // The T-214 half. Two, for the same reason cancel is two: an area and a project.
        try expectCallSites(of: "TaskContainerLifecycleService.completeRemainingActiveTasks", at: [
            "Cadence/iOS/iOSListWindDownSupport.swift": 2,
            "Cadence/iOS/iOSListViews.swift": 0,
            "Cadence/iOS/iOSListsRegularPane.swift": 0,
            "Cadence/iOS/iOSListEditorViews.swift": 0
        ])

        // `windDownList` is declared once and called twice beside it: the immediate path in the
        // shared menu decision, and the confirmed path in the modifier.
        // [[T-11753]]: the Lists page and the sidebar region reach the immediate path through
        // `windDownListUnlessConfirmationIsNeeded`, so neither calls it directly.
        // [[T-12020]]: the list editor's Status / Archive rows ([[T-8562]]'s third host) no longer
        // call it -- they settle inside their own edit commit through `settleListWindDown`, once
        // per edit branch, which `windDownList` is the only other caller of.
        try expectOccurrences(of: "windDownList(", at: [
            "Cadence/iOS/iOSListWindDownSupport.swift": 3,
            "Cadence/iOS/iOSListViews.swift": 0,
            "Cadence/iOS/iOSRootSidebar.swift": 0,
            "Cadence/iOS/iOSListEditorViews.swift": 0
        ])
        try expectOccurrences(of: "settleListWindDown(", at: [
            "Cadence/iOS/iOSListWindDownSupport.swift": 2,
            "Cadence/iOS/iOSListViews.swift": 0,
            "Cadence/iOS/iOSRootSidebar.swift": 0,
            "Cadence/iOS/iOSListEditorViews.swift": 2
        ])

        // And nothing reroutes a bulk settle through the single-task transitions, which would
        // refill the list it just closed. This is the invariant `aListCompletionDoesNotRefillTheListItJustFinished`
        // proves behaviourally; here it is as an absence, because the shape is what a future agent
        // reaches for.
        for path in ["Cadence/iOS/iOSListWindDownSupport.swift", "Cadence/iOS/iOSListViews.swift"] {
            let code = try strippingComments(sourceFile(path))
            #expect(!code.contains("applyStatusCompletion"), "\(path) bulk-settles through the single-task transition")
            #expect(!code.contains("markDone("), "\(path) bulk-settles through the single-task transition")
            #expect(!code.contains("markCancelled("), "\(path) bulk-settles through the single-task transition")
        }
    }

    /// Nothing else on iOS files a list away or marks one finished by hand. This is the assertion
    /// both tickets are about: a bare `status = .archived` *was* T-215's bug, and a bare
    /// `status = .done` on a list would be T-214's — a list that reads finished over work that is
    /// still open.
    ///
    /// The `.done` sweep is spelled against the **receiver** rather than as a bare
    /// `status = .done`, because `AppTask` legitimately carries that status and
    /// `iOSSampleDataSupport` writes it on a task. A sweep that could not tell a list from a task
    /// would either fail on correct code or be quietly relaxed until it caught nothing.
    @Test func noIOSSurfaceWindsAListDownByHand() throws {
        for path in try swiftFiles(under: "Cadence/iOS")
        where path != "Cadence/iOS/iOSListWindDownSupport.swift" {
            let code = try strippingComments(sourceFile(path))
            #expect(
                !code.contains("status = .archived"),
                "\(path) archives a list by hand instead of going through ModelContext.windDownList"
            )
            for receiver in ["area.status = .done", "project.status = .done"] {
                #expect(
                    !code.contains(receiver),
                    "\(path) completes a list by hand instead of going through ModelContext.windDownList"
                )
            }
        }
    }

    /// One confirmation, built in one place, armed by one decision, in both directions. Every
    /// affordance — the iPhone row swipe, its context menu, and the iPad pane's copies of both —
    /// routes up to `iOSListsView`, so the phone and the tablet cannot come to ask different
    /// questions.
    @Test func everyIOSListWindDownSurfaceGoesThroughTheOneDecision() throws {
        // The sheet is `iOSWindDownConfirmationSheet` since T-247 shared it with the kanban
        // column; the list surface still builds it in exactly one place, for both directions.
        try expectCallSites(of: "iOSWindDownConfirmationSheet", at: [
            "Cadence/iOS/iOSListWindDownSupport.swift": 1,
            "Cadence/iOS/iOSListViews.swift": 0,
            "Cadence/iOS/iOSListsRegularPane.swift": 0
        ])

        try expectCallSites(of: ".iOSListWindDown", at: [
            "Cadence/iOS/iOSListViews.swift": 1,
            "Cadence/iOS/iOSListsRegularPane.swift": 0,
            "Cadence/iOS/iOSRootSidebar.swift": 1,
            "Cadence/iOS/iOSListEditorViews.swift": 1
        ])

        // The conditional-confirmation test is asked once, in the shared menu decision, for both
        // directions and for every row menu ([[T-11753]]). The iPad pane calls up into
        // `archive(_:)` / `complete(_:)` instead of deciding for itself, and the Lists page and
        // the sidebar region both call the one function -- a second `requiresConfirmation` in any
        // of them is exactly how the menus would drift.
        try expectOccurrences(of: "requiresConfirmation", at: [
            "Cadence/iOS/iOSListViews.swift": 0,
            "Cadence/iOS/iOSListWindDownSupport.swift": 1,
            "Cadence/iOS/iOSRootSidebar.swift": 0,
            "Cadence/iOS/iOSListsRegularPane.swift": 0
        ])
        try expectCallSites(of: "windDownListUnlessConfirmationIsNeeded", at: [
            "Cadence/iOS/iOSListViews.swift": 1,
            "Cadence/iOS/iOSRootSidebar.swift": 1
        ])

        // Both surfaces actually *offer* completion, and the assertion is on the call sites rather
        // than on the labels: deleting the menu item while leaving the button builder behind is
        // exactly the mutation a "contains the words Complete Area" check survives.
        try expectCallSites(of: "completeAreaButton", at: ["Cadence/iOS/iOSListViews.swift": 2])
        try expectCallSites(of: "completeProjectButton", at: ["Cadence/iOS/iOSListViews.swift": 2])
        try expectCallSites(of: "completeArea", at: ["Cadence/iOS/iOSListsRegularPane.swift": 1])
        try expectCallSites(of: "completeProject", at: ["Cadence/iOS/iOSListsRegularPane.swift": 1])

        // …and the pane is handed the host's decision rather than owning one.
        try expectOccurrences(of: "completeArea:", at: ["Cadence/iOS/iOSListViews.swift": 1])
        try expectOccurrences(of: "completeProject:", at: ["Cadence/iOS/iOSListViews.swift": 1])

        // Completion is a context-menu item on both surfaces and a swipe action on neither. The
        // swipe tray is shared (`iOSListRowSwipeActions`), so the check is that it never learns the
        // word: a `.complete` flick would put "this work is finished" one mis-swipe from "file it
        // away", with no beat in which to read anything.
        let swipes = try strippingComments(sourceFile("Cadence/iOS/iOSListSupportViews.swift"))
        #expect(swipes.contains("enum iOSListRowSwipeActions"))
        #expect(swipes.contains("static func archive("))
        #expect(!swipes.contains("static func complete("))
        for path in ["Cadence/iOS/iOSListViews.swift", "Cadence/iOS/iOSListsRegularPane.swift"] {
            let code = try strippingComments(sourceFile(path))
            #expect(code.contains("iOSListRowSwipeActions.archive"))
            #expect(!code.contains("iOSListRowSwipeActions.complete"))
        }
    }

    /// **[[T-12532]] -- a refused menu wind-down keeps the target, so its alert names the kind.**
    /// Both hosts stored only the `iOSListWindDownAction`, so the title could say nothing but
    /// "Couldn't Archive List" under a control that read "Archive Project". The title is built from
    /// the target's own `list.noun`, and neither host can drop back to storing the bare action.
    @Test func aRefusedMenuWindDownIsTitledWithTheTargetsNoun() throws {
        func squeezed(_ text: String) -> String { String(text.filter { !$0.isWhitespace }) }
        let support = squeezed(try strippingComments(sourceFile("Cadence/iOS/iOSListWindDownSupport.swift")))
        #expect(support.contains(#"extensioniOSListWindDownTarget{varfailureAlertTitle:String{"Couldn't\(action.verb)\(list.noun)""#))
        #expect(support.contains("funciOSListWindDownFailureAlert(refusedtarget:Binding<iOSListWindDownTarget?>)"))
        #expect(!support.contains("List\"}"), "an alert title still ends in the generic word List")
        for path in ["Cadence/iOS/iOSListViews.swift", "Cadence/iOS/iOSRootSidebar.swift"] {
            let code = squeezed(try strippingComments(sourceFile(path)))
            #expect(code.contains("@StateprivatevarrefusedWindDown:iOSListWindDownTarget?"), "\(path) stores less than the refused target")
            #expect(code.contains("refusedWindDown=target}"), "\(path) does not record the refused target")
            #expect(code.contains(".iOSListWindDownFailureAlert(refused:$refusedWindDown)"))
        }
    }

    /// **[[T-11753]] -- the iPad sidebar row offers the Lists page's wind-down set.** A
    /// full-screen iPad has no entrance to the Lists page, so its sidebar row menu is the list's
    /// only menu there; it offered Edit / Move Up / Move Down, and completion sat only inside the
    /// editor's Status menu. Both menus must name the same wind-downs, in the same order, with
    /// the same roles: Complete plain (finishing work is not destruction), and Archive plain too
    /// ([[T-12322]]: recoverable, so never Delete's red, as the Mac's `ListEditorArchiveButton`).
    /// Whitespace is dropped so the shape, not the indentation, is what is read.
    @Test func theSidebarRowMenuOffersTheListsPageWindDownSet() throws {
        func squeezed(_ text: String) -> String { String(text.filter { !$0.isWhitespace }) }
        func order(of needles: [(String, String)], in menu: String) -> [String] {
            needles
                .compactMap { needle, verb in menu.range(of: needle).map { ($0.lowerBound, verb) } }
                .sorted { $0.0 < $1.0 }
                .map { $0.1 }
        }

        let page = try strippingComments(sourceFile("Cadence/iOS/iOSListViews.swift"))
        let areaRow = try #require(CadenceSourceScan.functionBody(named: "areaRow", in: page))
        let projectRow = try #require(CadenceSourceScan.functionBody(named: "projectRow", in: page))
        let areaMenu = try #require(CadenceSourceScan.declarationBody(".contextMenu", in: areaRow))
        let projectMenu = try #require(CadenceSourceScan.declarationBody(".contextMenu", in: projectRow))
        let pageArea = order(of: [("completeAreaButton(", "complete"), ("archiveAreaButton(", "archive")], in: areaMenu)
        let pageProject = order(of: [("completeProjectButton(", "complete"), ("archiveProjectButton(", "archive")], in: projectMenu)

        let sidebar = try strippingComments(sourceFile("Cadence/iOS/iOSRootSidebar.swift"))
        let row = try #require(CadenceSourceScan.declarationBody("struct iOSSidebarListRow: View", in: sidebar))
        let rowMenu = try #require(CadenceSourceScan.declarationBody(".contextMenu", in: row))
        let sidebarSet = order(of: [("onWindDown(.complete)", "complete"), ("onWindDown(.archive)", "archive")], in: rowMenu)

        #expect(pageArea == ["complete", "archive"], "non-vacuity: the Lists page's area menu was not read")
        #expect(pageProject == pageArea)
        #expect(sidebarSet == pageArea, "the sidebar row menu offers \(sidebarSet), the Lists page \(pageArea)")

        // Same roles and labels as the page's builders.
        let pageCode = squeezed(page)
        #expect(pageCode.contains("Button{complete(area)}label:{Label(\"CompleteArea\""))
        // [[T-12322]]: Archive is plain like Complete -- recoverable, so never Delete's red.
        #expect(pageCode.contains("Button{archive(area)}label:{Label(title,systemImage:\"archivebox\")}"))
        #expect(pageCode.contains("Button{archive(project)}label:{Label(title,systemImage:\"archivebox\")}"))
        #expect(!pageCode.contains("Button(role:.destructive){archive("))
        let pane = squeezed(try strippingComments(sourceFile("Cadence/iOS/iOSListsRegularPane.swift")))
        #expect(pane.contains("Button{archiveArea(area)}label:{Label(\"ArchiveArea\""))
        #expect(pane.contains("Button{archiveProject(project)}label:{Label(\"ArchiveProject\""))
        #expect(!pane.contains("Button(role:.destructive){archive"))
        let menu = squeezed(rowMenu)
        #expect(menu.contains("Button{onWindDown(.complete)}label:{Label(\"Complete\\(item.kind==.area?\"Area\":\"Project\")\",systemImage:iOSListWindDownAction.complete.icon)"))
        #expect(menu.contains("Button{onWindDown(.archive)}label:{Label(\"Archive\\(item.kind==.area?\"Area\":\"Project\")\",systemImage:iOSListWindDownAction.archive.icon)}"))
        #expect(!menu.contains("role:.destructive"), "the sidebar row menu's Archive is plain, as the page's ([[T-12322]])")
        // Edit first, then the wind-downs, then Move: the page's Edit-first order.
        let edit = try #require(menu.range(of: "onEdit()"))
        let complete = try #require(menu.range(of: "onWindDown(.complete)"))
        let moveUp = try #require(menu.range(of: "onMove(-1)"))
        #expect(edit.lowerBound < complete.lowerBound && complete.lowerBound < moveUp.lowerBound)

        // The region, which owns the decision for both of its hosts, resolves the row and asks
        // the page's own function -- no second `requiresConfirmation`, no hand-built settle.
        let windDown = try #require(CadenceSourceScan.functionBody(named: "windDown", in: sidebar))
        #expect(windDown.contains("SidebarListEntry.resolve(kind: item.kind, id: item.id, in: modelContext)"))
        #expect(windDown.contains("pendingWindDown = try modelContext.windDownListUnlessConfirmationIsNeeded(target)"))
        #expect(sidebar.contains("onWindDown: { action in windDown(item, action) }"))
        #expect(sidebar.contains(".iOSListWindDown(target: $pendingWindDown)"))
    }

    /// **[[T-12621]] -- the Mac sidebar row's right-click offers the iPad row's set.** It opened
    /// the Edit sheet directly (a `RightClickActionTrigger` running `onEdit`) while the iPad's
    /// long-press on the same row opened Edit / Complete / Archive / Move Up / Move Down. The Mac
    /// menu is Edit, then Complete, then Archive -- the iPad's order and glyphs -- with no
    /// `.destructive` role; Move Up / Move Down are left to the Mac's drag reorder, and Delete is
    /// in neither row menu.
    @Test func theMacSidebarRowMenuOffersTheIPadRowsSet() throws {
        func squeezed(_ text: String) -> String { String(text.filter { !$0.isWhitespace }) }

        let macFile = try strippingComments(sourceFile("Cadence/macOS/Views/SidebarSupportViews.swift"))
        let macRow = try #require(CadenceSourceScan.declarationBody("struct SidebarListRow: View", in: macFile))
        let macMenu = squeezed(try #require(CadenceSourceScan.declarationBody(".contextMenu", in: macRow)))
        #expect(!macRow.contains("RightClickActionTrigger"), "the row went back to right-click-to-edit")

        let edit = try #require(macMenu.range(of: "Button(action:onEdit){Label(kind.editActionName,systemImage:\"square.and.pencil\")}"))
        let complete = try #require(macMenu.range(of: "Button{onWindDown(.completed)}label:{Label(\"Complete\\(kind.label)\",systemImage:\"checkmark.circle\")}"))
        let archive = try #require(macMenu.range(of: "Button{onWindDown(.archived)}label:{Label(\"Archive\\(kind.label)\",systemImage:\"archivebox\")}"))
        #expect(edit.lowerBound < complete.lowerBound && complete.lowerBound < archive.lowerBound)
        #expect(!macMenu.contains("role:.destructive"), "Archive is recoverable ([[T-12322]])")
        #expect(!macMenu.contains("onMove"), "the Mac reorders by drag")

        // The iPad row's glyphs are the ones the Mac menu spells out.
        let ipad = try strippingComments(sourceFile("Cadence/iOS/iOSRootSidebar.swift"))
        let ipadRow = try #require(CadenceSourceScan.declarationBody("struct iOSSidebarListRow: View", in: ipad))
        let ipadMenu = try #require(CadenceSourceScan.declarationBody(".contextMenu", in: ipadRow))
        #expect(ipadMenu.contains("systemImage: \"square.and.pencil\""))
        let support = try strippingComments(sourceFile("Cadence/iOS/iOSListWindDownSupport.swift"))
        #expect(squeezed(support).contains("case.archive:return\"archivebox\"case.complete:return\"checkmark.circle\""))

        // Both hosts route the menu through the one wind-down target.
        let host = try strippingComments(sourceFile("Cadence/macOS/Views/SidebarComponents.swift"))
        #expect(host.contains("onWindDown: { requestWindDown(SidebarListWindDown(.area(area), choice: $0)) }"))
        #expect(host.contains("onWindDown: { requestWindDown(SidebarListWindDown(.project(project), choice: $0)) }"))
    }

    /// The Mac row menu's wind-down settles what the Edit sheet's `apply(_:)` settles, in the
    /// direction the choice names, asks only when there is something to settle, and puts the list
    /// and every settled task back when the store refuses ([[T-12621]]).
    @Test func theMacSidebarRowMenuWindDownSettlesInTheChoicesDirection() throws {
        let modelContext = ModelContext(try container())
        let area = Area(name: "Home")
        let child = Project(name: "Kitchen", area: area)
        let open = task("open")
        open.area = area
        let openInChild = task("open in child")
        openInChild.project = child
        let project = Project(name: "Ship")
        let shipOpen = task("ship open", status: .inProgress)
        shipOpen.project = project
        for model in [open, openInChild, shipOpen] { modelContext.insert(model) }
        modelContext.insert(area)
        modelContext.insert(child)
        modelContext.insert(project)
        area.tasks = [open]
        area.projects = [child]
        child.tasks = [openInChild]
        project.tasks = [shipOpen]
        try modelContext.save()

        #expect(SidebarListWindDown(.area(area), choice: .active) == nil, "reopening settles nothing")

        // A refused commit puts everything back.
        let refused = try #require(SidebarListWindDown(.area(area), choice: .completed))
        #expect(refused.summary.openTasks == 2)
        #expect(refused.summary.requiresConfirmation)
        #expect(refused.confirmationTitle == "Complete Area?")
        struct Refusal: Error {}
        #expect(throws: Refusal.self) {
            try SidebarListWindDown.windDown(refused, in: modelContext, commit: { _ in throw Refusal() })
        }
        #expect(area.status == .active)
        #expect([open.status, openInChild.status] == [.todo, .todo])

        // Complete marks the area's work done, child project included.
        try SidebarListWindDown.windDown(refused, in: modelContext)
        #expect(area.status == .done)
        #expect([open.status, openInChild.status] == [.done, .done])

        // Archive cancels the project's work.
        let archive = try #require(SidebarListWindDown(.project(project), choice: .archived))
        #expect(archive.actionTitle == "Archive Project")
        try SidebarListWindDown.windDown(archive, in: modelContext)
        #expect(project.status == .archived)
        #expect(shipOpen.status == .cancelled)
        #expect(shipOpen.completedAt != nil)

        // Nothing left open: no confirmation.
        #expect(SidebarListWindDown(.project(project), choice: .completed)?.summary.requiresConfirmation == false)
    }

    /// **[[T-12511]].** The list editor's kanban COLUMN row drew Archive with `role: .destructive`
    /// -- Delete's red -- although the same row offers Unarchive the moment it is archived, and the
    /// Mac's column popover draws "Archive Column" dim. [[T-12322]]'s ruling covers it: only Delete
    /// keeps the red, so the column's Archive takes the muted secondary treatment the Mac's
    /// `ListEditorArchiveButton` uses.
    @Test func theListEditorsColumnArchiveIsMutedNotDestructive() throws {
        func squeezed(_ text: String) -> String { String(text.filter { !$0.isWhitespace }) }
        let editor = try strippingComments(sourceFile("Cadence/iOS/iOSListEditorViews.swift"))
        let controls = squeezed(try #require(CadenceSourceScan.functionBody(named: "lifecycleControls", in: editor)))
        #expect(controls.contains("iOSActionButton(title:\"Complete\""), "non-vacuity: the column's lifecycle row was not read")
        #expect(
            controls.contains("iOSActionButton(title:\"Archive\",systemImage:\"archivebox\",size:.compact,tint:Theme.muted,action:lifecycle.archive)"),
            "the column's Archive must be the muted secondary button, as the Mac's list Archive is"
        )
        #expect(!controls.contains("role:.destructive"), "the column's Archive is recoverable -- never Delete's red ([[T-12322]])")

        let mac = squeezed(try strippingComments(sourceFile("Cadence/macOS/Sheets/ListEditorSupportViews.swift")))
        #expect(mac.contains("role:.secondary,size:.compact,tint:Theme.muted"), "the Mac's Archive this is measured against moved")
    }

    /// The other direction of the same divergence. macOS's branches are what iOS was measured
    /// against, so they are pinned too: closing either ticket by *removing* the Mac's wind-down
    /// would satisfy every assertion above and be the wrong fix.
    ///
    /// **This used to be two whole-file counts and it could not see the mutation that matters.**
    /// It asserted `cancelRemainingActiveTasks(` twice and `completeRemainingActiveTasks(` twice in
    /// `EditListSheet.swift`. *Swapping* them — so archiving a list marks its leftovers done and
    /// completing one cancels them — leaves both counts at two and every test green
    /// (`docs/TODO.md` T-161). The branch is a value now: `ListEditorLifecycleChoice.windDownOutcome`,
    /// asserted just below, and each sheet makes one call parameterised by it.
    @Test func macOSStillWindsDownOnArchiveAndOnCompletion() throws {
        let sheet = try strippingComments(sourceFile("Cadence/macOS/Sheets/EditListSheet.swift"))

        for declaration in [
            "private func apply(_ choice: ListEditorLifecycleChoice)"
        ] {
            var searched = Substring(sheet)
            var bodies: [String] = []
            while let range = searched.range(of: declaration) {
                let body = try cadenceFunctionBody(declaration, in: String(searched[range.lowerBound...]))
                bodies.append(body)
                searched = searched[range.upperBound...]
            }
            // One `apply` per sheet: `EditAreaSheet` and `EditProjectSheet`.
            #expect(bodies.count == 2)
            for body in bodies {
                #expect(body.components(separatedBy: "choice.windDownOutcome").count - 1 == 1)
                #expect(body.components(separatedBy: "settleRemainingActiveTasks(").count - 1 == 1)
                // Scoped to this body, so re-spelling the branch here rather than reading the value
                // fails even though the file as a whole would still contain both names.
                #expect(!body.contains("completeRemainingActiveTasks("))
                #expect(!body.contains("cancelRemainingActiveTasks("))
                // Non-vacuity: this really is `apply`'s body and not an empty string.
                #expect(body.contains("applyEdits()"))
            }
        }
    }

    /// The decision the two sheets now read, as a value.
    ///
    /// Archiving cancels what is left; completing marks it done. Nothing in a view body gets to
    /// have a second opinion about that, and a mutation that swaps the two arms fails here rather
    /// than shipping a list whose archive silently credits unfinished work as finished.
    @Test func theLifecycleChoiceCarriesTheOutcomeRatherThanTheSheet() {
        #expect(ListEditorLifecycleChoice.archived.windDownOutcome == .cancelled)
        #expect(ListEditorLifecycleChoice.completed.windDownOutcome == .done)
        // Reopening a list settles nothing — not "settles an empty set".
        #expect(ListEditorLifecycleChoice.active.windDownOutcome == nil)
        #expect(ListEditorLifecycleChoice.allCases.count == 3)
    }

    /// **[[T-9947]]: the stored status names the choice the Status popover ticks.** A paused or
    /// cancelled project is none of the offered choices, so it ticks nothing rather than the
    /// nearest row; an archived list maps to `.archived`, which the popover does not offer either.
    @Test func theStoredStatusNamesTheTickedChoice() {
        #expect(ListEditorLifecycleChoice(AreaStatus.active) == .active)
        #expect(ListEditorLifecycleChoice(AreaStatus.done) == .completed)
        #expect(ListEditorLifecycleChoice(AreaStatus.archived) == .archived)
        #expect(ListEditorLifecycleChoice(ProjectStatus.active) == .active)
        #expect(ListEditorLifecycleChoice(ProjectStatus.done) == .completed)
        #expect(ListEditorLifecycleChoice(ProjectStatus.archived) == .archived)
        #expect(ListEditorLifecycleChoice(ProjectStatus.paused) == nil)
        #expect(ListEditorLifecycleChoice(ProjectStatus.cancelled) == nil)
    }

    /// And the outcome-shaped entry point really dispatches, on both container kinds. Without this
    /// the value above could be right and the service could still ignore it.
    @Test func theOutcomeShapedSettleReallySettlesThatWay() throws {
        for (outcome, expected) in [
            (CadenceWindDownOutcome.cancelled, TaskStatus.cancelled),
            (CadenceWindDownOutcome.done, TaskStatus.done)
        ] {
            let modelContext = ModelContext(try container())
            let area = Area(name: "Home")
            let project = Project(name: "Kitchen")
            let inArea = task("area work")
            inArea.area = area
            let inProject = task("project work")
            inProject.project = project
            modelContext.insert(area)
            modelContext.insert(project)
            modelContext.insert(inArea)
            modelContext.insert(inProject)

            TaskContainerLifecycleService.settleRemainingActiveTasks(
                in: area,
                includingChildProjects: true,
                outcome: outcome,
                in: modelContext,
                reconciler: .inert
            )
            TaskContainerLifecycleService.settleRemainingActiveTasks(
                in: project,
                outcome: outcome,
                in: modelContext,
                reconciler: .inert
            )

            #expect(inArea.status == expected)
            #expect(inProject.status == expected)
        }
    }

    /// Without this, every zero and every absence assertion above could be passing because the
    /// reader returned an empty string.
    @Test func theSourceScanActuallyReadsTheseFilesInListWindDownSurface() throws {
        let files = try swiftFiles(under: "Cadence")
        #expect(files.count > 300)
        #expect(files.contains("Cadence/Services/CadenceTaskContainerLifecycleService.swift"))
        #expect(files.contains("Cadence/macOS/Services/TaskWorkflowService.swift"))
        #expect(files.contains("Cadence/iOS/iOSListWindDownSupport.swift"))
        #expect(files.contains("Cadence/iOS/iOSListViews.swift"))
        #expect(files.contains("Cadence/iOS/iOSListsRegularPane.swift"))
        #expect(files.contains("Cadence/iOS/iOSListSupportViews.swift"))

        // And it must be reading *code*, through the same reader the absence checks use.
        let support = try strippingComments(sourceFile("Cadence/iOS/iOSListWindDownSupport.swift"))
        #expect(support.contains("struct iOSListWindDownTarget: Identifiable"))
        #expect(support.contains("enum iOSListWindDownAction"))
        let confirmation = try strippingComments(sourceFile("Cadence/iOS/iOSWindDownConfirmation.swift"))
        #expect(confirmation.contains("struct iOSWindDownConfirmationSheet: View"))

        // The two hand-wind-down sweeps above would pass vacuously if the one file that *does*
        // spell those writes had stopped spelling them, or if the sweep were reading the wrong
        // folder.
        #expect(support.contains("status = .archived"))
        #expect(support.contains("area.status = .done"))
        #expect(support.contains("project.status = .done"))

        // Likewise the swipe-tray check: the archive flick must actually be there for its absence
        // counterpart to mean anything.
        let pane = try strippingComments(sourceFile("Cadence/iOS/iOSListsRegularPane.swift"))
        #expect(pane.contains("archiveArea(area)"))
        #expect(pane.contains("completeArea(area)"))
    }
}

// MARK: - Source-reading helpers

/// Fails unless `name` is called exactly `count` times in each listed file.
///
/// **Exact counts, not "contains".** `CadenceSharedBoardChromeTests` documents why: a mutation run
/// caught a version of that file asserting only that each file mentioned the shared component
/// somewhere, and reverting *one* of four call sites left it green.
private func expectCallSites(
    of name: String,
    at callSites: [String: Int],
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    for (path, expected) in callSites {
        let code = try strippingComments(sourceFile(path))
        let actual = code.components(separatedBy: "\(name)(").count - 1
        #expect(
            actual == expected,
            "\(path) calls \(name) \(actual) times, expected \(expected)",
            sourceLocation: sourceLocation
        )
    }
}

/// Fails unless `text` occurs exactly `count` times as live code in each listed file.
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

/// Enumerated by `enumerator(atPath:)` rather than `enumerator(at:)` on purpose: the URL variant
/// yields *absolute* paths, and `#filePath` can name the repo through a symlinked prefix
/// (`/tmp` against `/private/tmp` on an isolated build tree) that `FileManager` resolves and the
/// literal does not.
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

/// Blanks out `//` line comments and `/* */` block comments so the assertions above read code
/// rather than prose. Crude on purpose: a `//` inside a string literal is blanked too, which can
/// only ever make these checks *stricter* about what counts as a comment, never looser about live
/// code.
private func strippingComments(_ source: String) throws -> String {
    // T-1269/T-1270: one pass per pattern, in CadenceSourceScan, on the guarded
    // `(?<!:)//` that the slashes in a URL cannot trigger.
    return CadenceSourceScan.strippingComments(source)
}

#endif
