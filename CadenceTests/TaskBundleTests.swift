import Foundation
import SwiftData
import Testing
@testable import Cadence

#if os(macOS)
@MainActor
struct TaskBundleTests {
    /// A commit that always refuses, the way every other save-commit suite here spells it.
    private struct CommitRefused: Error {}

    /// **T-628: the three ways a block ends now have a commit boundary.**
    ///
    /// `completeBundle` used to mark every open member done — which spawns a recurrence successor —
    /// detach them all, and `context.delete(bundle)`, with no save anywhere. Both hosts then closed
    /// their popover, which is the only signal either gesture gives. So the insert and the delete
    /// sat pending in the app's one `ModelContext` for the next unrelated `save()` to take or the
    /// next unrelated `rollback()` to throw away, and the user was told it worked either way.
    ///
    /// The commit is `CadenceTaskMutationSupport.deleteBundle`'s — T-322's fix, which iOS already
    /// used — so the refusal rolls back and the sentence the popover shows is earned: the block is
    /// still there, its members are still in it, and the successor was never created.
    @Test func aRefusedBundleCompletionLeavesTheBlockItsMembersAndTheSuccessorAlone() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let member = AppTask(title: "Repeats daily")
        member.recurrenceRule = .daily
        member.scheduledDate = "2026-05-01"
        let bundle = TaskBundle(title: "Morning block", dateKey: "2026-05-01", startMin: 600, durationMinutes: 30)
        context.insert(member)
        context.insert(bundle)
        SchedulingActions.addTask(member, to: bundle)
        try context.save()

        #expect(throws: (any Error).self) {
            try SchedulingActions.completeBundle(bundle, in: context) { _ in
                throw CommitRefused()
            }
        }

        // Read through a **second context on the same container**, which is the only reading that
        // answers the question the notice makes a promise about: what the store holds. A live
        // object still answers the value it was assigned until something refreshes it, and
        // `rollback()` un-deletes unconditionally but does not visibly undo a field edit — both
        // halves of that are measured in `CadencePendingChangePersistence.commitEdit`'s note.
        let stored = ModelContext(container)
        let bundles = try stored.fetch(FetchDescriptor<TaskBundle>())
        #expect(bundles.count == 1, "the block is still in the store")
        #expect(bundles.first?.sortedTasks.count == 1, "and still holds its member")
        let tasks = try stored.fetch(FetchDescriptor<AppTask>())
        #expect(tasks.count == 1, "no successor was written")
        #expect(tasks.first?.isDone == false, "and the member was not completed")
    }

    /// The same boundary on `unbundle`, which `deleteBundle` forwards to — the other two of the
    /// three end actions (T-628).
    @Test func aRefusedUnbundleLeavesTheBlockAndItsMembersAlone() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let member = AppTask(title: "Stays put")
        let bundle = TaskBundle(title: "Morning block", dateKey: "2026-05-01", startMin: 600, durationMinutes: 30)
        context.insert(member)
        context.insert(bundle)
        SchedulingActions.addTask(member, to: bundle)
        try context.save()

        #expect(throws: (any Error).self) {
            try SchedulingActions.unbundle(bundle, in: context) { _ in
                throw CommitRefused()
            }
        }

        let stored = ModelContext(container)
        let bundles = try stored.fetch(FetchDescriptor<TaskBundle>())
        #expect(bundles.count == 1)
        #expect(bundles.first?.sortedTasks.count == 1)
    }

    @Test func addingTaskToBundleUsesBundleDateWithoutTaskTime() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Five minute follow-up")
        task.scheduledDate = "2026-05-02"
        task.scheduledStartMin = 540
        task.calendarEventID = "event-1"
        let bundle = TaskBundle(title: "Admin sweep", dateKey: "2026-05-01", startMin: 600, durationMinutes: 30)
        context.insert(task)
        context.insert(bundle)

        SchedulingActions.addTask(task, to: bundle)

        #expect(task.bundle?.id == bundle.id)
        #expect(task.scheduledDate == "2026-05-01")
        #expect(task.scheduledStartMin == -1)
        #expect(task.calendarEventID.isEmpty)
        #expect(bundle.sortedTasks.map(\.id) == [task.id])
    }

    @Test func reassigningTaskBetweenBundlesRemovesOldMembership() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Tiny thing")
        let first = TaskBundle(title: "First", dateKey: "2026-05-01", startMin: 600, durationMinutes: 30)
        let second = TaskBundle(title: "Second", dateKey: "2026-05-02", startMin: 900, durationMinutes: 45)
        context.insert(task)
        context.insert(first)
        context.insert(second)

        SchedulingActions.addTask(task, to: first)
        SchedulingActions.addTask(task, to: second)

        #expect(task.bundle?.id == second.id)
        #expect(task.scheduledDate == "2026-05-02")
        #expect(first.sortedTasks.isEmpty)
        #expect(second.sortedTasks.map(\.id) == [task.id])
    }

    @Test func droppingBundledTaskOntoTimelineRemovesBundleMembership() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Pull report")
        let bundle = TaskBundle(title: "Batch", dateKey: "2026-05-01", startMin: 600, durationMinutes: 30)
        context.insert(task)
        context.insert(bundle)
        SchedulingActions.addTask(task, to: bundle)

        SchedulingActions.dropTask(task, to: "2026-05-03", startMin: 720)

        #expect(task.bundle == nil)
        #expect(bundle.sortedTasks.isEmpty)
        #expect(task.scheduledDate == "2026-05-03")
        #expect(task.scheduledStartMin == 720)
    }

    @Test func deletingBundleKeepsTasksOnBundleDate() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Keep me")
        let bundle = TaskBundle(title: "Delete me", dateKey: "2026-05-01", startMin: 600, durationMinutes: 30)
        context.insert(task)
        context.insert(bundle)
        SchedulingActions.addTask(task, to: bundle)

        try SchedulingActions.deleteBundle(bundle, in: context)

        #expect(task.bundle == nil)
        #expect(task.scheduledDate == "2026-05-01")
        #expect(task.scheduledStartMin == -1)
    }

    @Test func deletingBundleAlsoDetachesCancelledHiddenMembers() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Hidden member")
        task.status = .cancelled
        let bundle = TaskBundle(title: "Delete me", dateKey: "2026-05-01", startMin: 600, durationMinutes: 30)
        context.insert(task)
        context.insert(bundle)
        SchedulingActions.addTask(task, to: bundle)

        try SchedulingActions.deleteBundle(bundle, in: context)

        #expect(task.bundle == nil)
        #expect(task.scheduledDate == "2026-05-01")
        #expect(task.scheduledStartMin == -1)
    }

    @Test func completingBundleMarksMemberTasksDoneAndRemovesBundle() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let first = AppTask(title: "First")
        let second = AppTask(title: "Second")
        let bundle = TaskBundle(title: "Finish me", dateKey: "2026-05-01", startMin: 600, durationMinutes: 30)
        [first, second].forEach(context.insert)
        context.insert(bundle)
        [first, second].forEach { SchedulingActions.addTask($0, to: bundle) }

        try SchedulingActions.completeBundle(bundle, in: context)

        #expect(first.isDone)
        #expect(second.isDone)
        #expect(first.completedAt != nil)
        #expect(second.completedAt != nil)
        #expect(first.bundle == nil)
        #expect(second.bundle == nil)
        #expect(first.scheduledDate == "2026-05-01")
        #expect(first.scheduledStartMin == -1)
        #expect(try context.fetch(FetchDescriptor<TaskBundle>()).isEmpty)
    }

    @Test func rollingOverLastActiveBundledTaskDetachesItAndRemovesOldBundle() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Carry me")
        let bundle = TaskBundle(title: "Yesterday", dateKey: "2026-05-01", startMin: 600, durationMinutes: 30)
        context.insert(task)
        context.insert(bundle)
        SchedulingActions.addTask(task, to: bundle)

        SchedulingActions.rollOverTaskToToday(task, todayKey: "2026-05-02", in: context)

        #expect(task.bundle == nil)
        #expect(task.scheduledDate == "2026-05-02")
        #expect(task.scheduledStartMin == -1)
        #expect(try context.fetch(FetchDescriptor<TaskBundle>()).isEmpty)
    }

    @Test func rollingOverOneBundledTaskKeepsBundleWhenOtherActiveTasksRemain() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let first = AppTask(title: "Carry me")
        let second = AppTask(title: "Stay bundled")
        let bundle = TaskBundle(title: "Yesterday", dateKey: "2026-05-01", startMin: 600, durationMinutes: 30)
        [first, second].forEach(context.insert)
        context.insert(bundle)
        [first, second].forEach { SchedulingActions.addTask($0, to: bundle) }

        SchedulingActions.rollOverTaskToToday(first, todayKey: "2026-05-02", in: context)

        #expect(first.bundle == nil)
        #expect(first.scheduledDate == "2026-05-02")
        #expect(first.scheduledStartMin == -1)
        #expect(second.bundle?.id == bundle.id)
        #expect(bundle.sortedTasks.map(\.id) == [second.id])
        #expect(try context.fetch(FetchDescriptor<TaskBundle>()).map(\.id) == [bundle.id])
    }

    @Test func removingTaskFromBundleKeepsItOnBundleDateWithoutCalendarSlot() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Loose item")
        let bundle = TaskBundle(title: "Batch", dateKey: "2026-05-01", startMin: 600, durationMinutes: 30)
        context.insert(task)
        context.insert(bundle)
        SchedulingActions.addTask(task, to: bundle)

        SchedulingActions.removeTaskFromBundle(task)

        #expect(task.bundle == nil)
        #expect(task.scheduledDate == "2026-05-01")
        #expect(task.scheduledStartMin == -1)
        #expect(bundle.sortedTasks.isEmpty)
    }

    @Test func bundleOrderCanBeChangedManually() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let first = AppTask(title: "First")
        let second = AppTask(title: "Second")
        let third = AppTask(title: "Third")
        let bundle = TaskBundle(title: "Batch", dateKey: "2026-05-01", startMin: 600, durationMinutes: 30)
        [first, second, third].forEach(context.insert)
        context.insert(bundle)
        [first, second, third].forEach { SchedulingActions.addTask($0, to: bundle) }

        SchedulingActions.moveTaskInBundle(third, direction: -1)

        #expect(bundle.sortedTasks.map(\.title) == ["First", "Third", "Second"])
        #expect(bundle.sortedTasks.map(\.bundleOrder) == [0, 1, 2])
    }

    @Test func creatingBundleFromTwoTimedTasksUsesTargetSlotAndMembersLoseIndividualTimes() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let target = AppTask(title: "A")
        target.scheduledDate = "2026-05-01"
        target.scheduledStartMin = 600
        target.estimatedMinutes = 25
        let dragged = AppTask(title: "B")
        dragged.scheduledDate = "2026-05-01"
        dragged.scheduledStartMin = 630
        dragged.estimatedMinutes = 10
        context.insert(target)
        context.insert(dragged)

        let bundle = try #require(SchedulingActions.createBundle(from: target, adding: dragged, in: context))

        #expect(bundle.dateKey == "2026-05-01")
        #expect(bundle.startMin == 600)
        #expect(bundle.durationMinutes == 35)
        #expect(bundle.sortedTasks.map(\.title) == ["A", "B"])
        #expect(target.scheduledDate == "2026-05-01")
        #expect(target.scheduledStartMin == -1)
        #expect(dragged.scheduledDate == "2026-05-01")
        #expect(dragged.scheduledStartMin == -1)
    }

    @Test func unbundlingKeepsTasksOnBundleDateAndPreservesListMetadata() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let area = Area(name: "General", colorHex: "#8b5cf6", icon: "globe")
        let tag = Tag(name: "enhancement", colorHex: "#22c55e")
        let task = AppTask(title: "Keep metadata")
        task.area = area
        task.sectionName = "Backlog"
        task.dueDate = "2026-05-10"
        task.notes = "Original notes"
        task.tags = [tag]
        task.order = 42
        task.priority = .high
        let bundle = TaskBundle(title: "Batch", dateKey: "2026-05-01", startMin: 600, durationMinutes: 30)
        context.insert(area)
        context.insert(tag)
        context.insert(task)
        context.insert(bundle)
        SchedulingActions.addTask(task, to: bundle)

        try SchedulingActions.unbundle(bundle, in: context)

        #expect(task.bundle == nil)
        #expect(task.scheduledDate == "2026-05-01")
        #expect(task.scheduledStartMin == -1)
        #expect(task.area?.id == area.id)
        #expect(task.sectionName == "Backlog")
        #expect(task.dueDate == "2026-05-10")
        #expect(task.notes == "Original notes")
        #expect(task.tags?.map(\.id) == [tag.id])
        #expect(task.order == 42)
        #expect(task.priority == .high)
        #expect(try context.fetch(FetchDescriptor<TaskBundle>()).isEmpty)
    }

    @Test func bundleTimesAreClampedInsideOneDay() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let bundle = SchedulingActions.createBundle(title: "", dateKey: "2026-05-01", startMin: 1438, endMin: 1510, in: context)

        #expect(bundle.title == TaskBundle.defaultDisplayTitle)
        #expect(bundle.startMin == 1435)
        #expect(bundle.durationMinutes == 5)
        #expect(bundle.endMin == 1440)
    }

    /// `AppTask.calendarEventID` is documented as write-only-empty: attaching a task to a calendar
    /// event is not a feature that exists, the readers that remain are there to *clear* values an
    /// earlier build left on disk, and the field survives only because removing a stored SwiftData
    /// property with no migration plan would drop data. That invariant was held purely by
    /// convention — nothing asserted it, so the first entry point to start writing an identifier
    /// would have reintroduced half a feature silently.
    @Test func noSchedulingEntryPointEverGivesATaskACalendarEventID() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let area = Area(name: "Ops")
        context.insert(area)

        // 1. Drag-to-create on the timeline, with no container.
        SchedulingActions.createTask(title: "Dragged out", dateKey: "2026-05-01", startMin: 600, endMin: 660, in: context)
        // 2. Drag-to-create routed into a list/section through the quick popover.
        SchedulingActions.createTask(
            title: "Dragged into a list",
            dateKey: "2026-05-01",
            startMin: 700,
            endMin: 760,
            containerSelection: .area(area.id),
            sectionName: TaskSectionDefaults.defaultName,
            areas: [area],
            projects: [],
            in: context
        )
        // 3. The shared creation sheet / quick capture path.
        TaskCreationService(areas: [area], projects: []).insertTask(
            from: TaskCreationDraft(
                title: "From the sheet",
                notes: "",
                priority: .none,
                container: .area(area.id),
                sectionName: TaskSectionDefaults.defaultName,
                dueDateKey: "",
                scheduledDateKey: "2026-05-01",
                subtaskTitles: [],
                tags: [],
                scheduledStartMin: 800
            ),
            into: context
        )
        // 4. The generic scheduled-insert helper the shared surfaces use.
        _ = try CadenceTaskMutationSupport.insertScheduledTask(
            title: "Inserted",
            allTasks: try context.fetch(FetchDescriptor<AppTask>()),
            modelContext: context,
            scheduledDate: "2026-05-01",
            scheduledStartMin: 900,
            estimatedMinutes: 30
        )

        let created = try context.fetch(FetchDescriptor<AppTask>())
        #expect(created.count == 4)
        #expect(created.allSatisfy { $0.calendarEventID.isEmpty })

        // And every path that *moves* a task must clear an identifier an older build left behind,
        // rather than carrying it onto the new slot.
        func stale(_ title: String) -> AppTask {
            let task = AppTask(title: title)
            task.scheduledDate = "2026-05-01"
            task.scheduledStartMin = 540
            task.estimatedMinutes = 30
            task.calendarEventID = "legacy-event-id"
            context.insert(task)
            return task
        }

        let rolled = stale("Rolled over")
        SchedulingActions.rollOverTaskToToday(rolled, todayKey: "2026-05-02", in: context)
        #expect(rolled.calendarEventID.isEmpty)

        let detached = stale("Detached")
        SchedulingActions.removeFromCalendar(detached)
        #expect(detached.calendarEventID.isEmpty)

        let bundled = stale("Bundled")
        let bundle = SchedulingActions.createBundle(title: "Sweep", dateKey: "2026-05-01", startMin: 600, endMin: 660, in: context)
        SchedulingActions.addTask(bundled, to: bundle)
        #expect(bundled.calendarEventID.isEmpty)

        let moved = stale("Moved with its bundle")
        moved.calendarEventID = "legacy-event-id"
        SchedulingActions.addTask(moved, to: bundle)
        moved.calendarEventID = "legacy-event-id" // re-arm: the move below is the site under test
        SchedulingActions.dropBundle(bundle, to: "2026-05-03", startMin: 660)
        #expect(moved.calendarEventID.isEmpty)

        let unbundled = stale("Unbundled")
        SchedulingActions.addTask(unbundled, to: bundle)
        unbundled.calendarEventID = "legacy-event-id"
        try SchedulingActions.unbundle(bundle, in: context)
        #expect(unbundled.calendarEventID.isEmpty)

        // Duplicating must not hand a second task the same event identifier.
        let source = stale("Original")
        let copy = try CadenceTaskMutationSupport.duplicate(
            source,
            allTasks: try context.fetch(FetchDescriptor<AppTask>()),
            modelContext: context
        )
        #expect(copy.calendarEventID.isEmpty)
    }

    @Test func bundleFocusLoggingDistributesByEstimate() throws {
        let short = AppTask(title: "Short")
        short.estimatedMinutes = 10
        let long = AppTask(title: "Long")
        long.estimatedMinutes = 20

        FocusSessionSupport.distributeBundleMinutes(30, across: [short, long])

        #expect(short.actualMinutes == 10)
        #expect(long.actualMinutes == 20)
    }
    /// **T-567.** An untitled block was called "Task Bundle" — the *type's* name, and a word the
    /// app never says to a user. Everything around it on that screen says **Block**: the segment,
    /// "Block title", "Edit Block", "Delete Block", "No tasks in this block". The literal was
    /// typed at nine sites across both platforms, three of which *stored* it rather than merely
    /// drawing it, so the noun could be renamed in one place and left behind in eight.
    ///
    /// One constant now, on the model that owns the concept, with the store/display split
    /// `CadenceEventTitleSupport` already draws: `storedTitle` for a create form about to save,
    /// `displayTitle` for a row reading a block an older build may have stored blank.
    @Test func anUntitledBlockIsNamedWithTheNounTheAppUses() throws {
        #expect(TaskBundle.defaultDisplayTitle == "Block")
        #expect(TaskBundle.storedTitle("") == TaskBundle.defaultDisplayTitle)
        // A title of spaces is not a title — the same trim `displayTitle` has always done, now on
        // the storing side too, so the blank never reaches the store in the first place.
        #expect(TaskBundle.storedTitle("   ") == TaskBundle.defaultDisplayTitle)
        #expect(TaskBundle.storedTitle("  Deep work  ") == "Deep work")

        let blank = TaskBundle(title: " \n ", dateKey: "2026-05-01", startMin: 600, durationMinutes: 30)
        #expect(blank.displayTitle == TaskBundle.defaultDisplayTitle)
        #expect(TaskBundle(title: "Admin", dateKey: "2026-05-01", startMin: 600, durationMinutes: 30).displayTitle == "Admin")

        // Both creation paths, one per platform, through the store rather than the constant.
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let dragged = SchedulingActions.createBundle(
            title: "   ",
            dateKey: "2026-05-01",
            startMin: 600,
            endMin: 660,
            in: context
        )
        #expect(dragged.title == TaskBundle.defaultDisplayTitle)
        let created = try CadenceTaskMutationSupport.insertBundle(
            title: "",
            dateKey: "2026-05-01",
            startMin: 600,
            durationMinutes: 30,
            modelContext: context
        )
        #expect(created.title == TaskBundle.defaultDisplayTitle)
    }

    /// The other seven sites, which no behavioural test can reach: they are literals inside `View`
    /// bodies and one AppKit-side service. The iOS create sheet is not in this list because it
    /// never typed the noun — its half of T-567 is `canCreate`, two tests below.
    @Test func noSurfaceStillTypesTheRetiredBundleNoun() throws {
        for path in [
            "Cadence/Models/AppTask.swift",
            "Cadence/Shared/CadenceTaskMutationSupport.swift",
            "Cadence/macOS/Services/SchedulingService.swift",
            "Cadence/macOS/Views/TimelineDayCanvas.swift",
            "Cadence/macOS/Views/QuickCreateChoicePopover.swift",
            "Cadence/macOS/Views/TimelineBundleBlockSupportViews.swift",
            "Cadence/macOS/Views/CalendarPageMonthSupportViews.swift",
        ] {
            let source = try CadenceCommitSurfaceScan.scanned(path)
            #expect(
                CadenceSourceScan.matchCount(#""Task Bundle""#, in: source) == 0,
                "\(path) still types the retired bundle noun"
            )
            #expect(
                CadenceSourceScan.matchCount(
                    #"TaskBundle\.(defaultDisplayTitle|storedTitle)|\bdisplayTitle\b"#,
                    in: source
                ) >= 1,
                "\(path) reads neither the shared constant nor the model's own display title"
            )
        }

        // Non-vacuity for the stripper these reads go through: it blanks a comment and keeps a
        // string literal, which is exactly what an assertion about a literal needs.
        let raw = try CadenceSourceScan.sourceFile("Cadence/Models/AppTask.swift")
        let stripped = CadenceSourceScan.strippingComments(raw)
        #expect(raw.contains("the *type's* name"), "the tombstone comment this pins is gone")
        #expect(!stripped.contains("the *type's* name"))
        #expect(stripped.contains(#"static let defaultDisplayTitle = "Block""#))
    }

    /// T-567's first half, and the reason the fallback was reachable from a create form at all:
    /// `canCreate` returned `true` unconditionally for `.bundle` while Task and Event both
    /// required a title, so two taps on an empty slot made a block the user had not named.
    ///
    /// Scoped to the `canCreate` body rather than the file: `showsTimedControls` twelve lines
    /// below has its own `case .bundle: return true`, which is correct and must stay — a
    /// file-wide needle would either miss this defect or condemn that line.
    @Test func theIOSQuickCreateSheetAsksForATitleForEveryKindItCreates() throws {
        let source = try CadenceCommitSurfaceScan.scanned("Cadence/iOS/iOSCalendarQuickCreateSheet.swift")
        let anchor = try #require(source.range(of: "var canCreate: Bool"))
        let body = try #require(
            CadenceSourceScan.matchedBody(after: anchor.upperBound, in: source, open: "{", close: "}")
        )

        #expect(CadenceSourceScan.matchCount(#"return true"#, in: body) == 0)
        #expect(CadenceSourceScan.matchCount(#"TaskTitleSupport\.isEmpty\(title\)"#, in: body) == 2)
        #expect(CadenceSourceScan.matchCount(#"case \.(task|bundle|event):"#, in: body) == 3)

        // The read really was one declaration's body: the sibling that still answers `true` for a
        // block is outside it.
        #expect(!body.contains("showsTimedControls"))
        #expect(
            CadenceSourceScan.matchCount(#"case \.bundle:\s*return true"#, in: source) == 1,
            "showsTimedControls no longer holds the negative this scan is discriminated against"
        )
    }
}
#endif
