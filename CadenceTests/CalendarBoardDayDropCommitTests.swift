#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// The commits the Calendar Board's **day columns** make, counted, and refusable on demand.
///
/// The same seam, and for the same reason, as `CalendarBoardUnscheduleCommitTests` one rail over
/// ([[T-1952]]) and `TasksListDropCommitRateTests` one surface over ([[T-1580]]): an in-memory
/// container cannot be made to refuse a `save()`, so every reading would come out the same whether
/// the path commits once, twice or never, and the `.refused` branch would be unreachable from any
/// test. No assertion here is worth anything unless the refusing and taking readings differ.
private final class CountingDayDropCommit {
    /// What the store answers. `true` is the refusal that cannot be provoked any other way.
    var refuses = false

    private(set) var commitCount = 0

    struct Refused: Error {}

    func commit(_ modelContext: ModelContext) throws {
        commitCount += 1
        if refuses { throw Refused() }
        try modelContext.save()
    }
}

/// **T-1980.** The Calendar Board's two **day-column** drops — a card onto a day and a whole block
/// onto a day, both private to `CalendarPageBoardView` and renamed by this change, so their old
/// spellings are deliberately not written here — were the pair left in the file [[T-1952]] closed,
/// and both ended `try? modelContext.save()`.
///
/// **Why nothing caught them, which is the half worth recording.** Both returned `Void`, so
/// `CadenceSaveCommitRule`'s report detector had no answer to read — `return true` from a `-> Bool`
/// is the spelling it was taught ([[T-636]](b)), and these answered nothing at all. The `true` the
/// drop actually reports was built one frame up and one file over, in
/// `CalendarBoardDayColumn.handleDrop`, which returned it unconditionally. So they were *invisible*
/// to the sweep rather than exempted by it, which is a worse state than the one T-1952 closed: an
/// exemption is a schedule, and a blind spot is not. The detector half is [[T-1990]].
///
/// **The two drops are not the same shape.** A card drop is `unschedule`'s shape with the do date
/// set instead of cleared — the detach from a block, the sibling renumbering, plus the default
/// estimate it materialises. A **block** drop has no task as its subject at all: it writes the
/// block's own `dateKey`/`startMin`/`durationMinutes` and then every member's `scheduledDate`,
/// `scheduledStartMin` and `calendarEventID`. That last field is why `CadenceTaskFieldSnapshot`
/// grew to nineteen in this change; it was in that type's "not carried" list by name until a
/// caller started writing it.
///
/// The test that stays green over either defect is "the drop moves the card". The discriminating
/// case is the one the store **refuses**.
@MainActor
struct CalendarBoardDayDropCommitTests {

    private func container() throws -> ModelContainer {
        try CadenceModelContainerFactory.makeInMemoryContainer()
    }

    // MARK: - Fixtures

    /// A block on 2026-06-01 holding three members in a known order, plus a second block holding
    /// one, which is the control the one-candidate trap asks for: nothing about either drop may
    /// touch a block the gesture was never aimed at.
    private struct BoardFixture {
        let modelContext: ModelContext
        let dragged: AppTask
        let siblings: [AppTask]
        let block: TaskBundle
        let bystander: AppTask
        let otherBlock: TaskBundle
        var allTasks: [AppTask] { [dragged] + siblings + [bystander] }
    }

    private func fixture(in modelContainer: ModelContainer) throws -> BoardFixture {
        let modelContext = ModelContext(modelContainer)
        let block = TaskBundle(title: "Morning block", dateKey: "2026-06-01", startMin: 600, durationMinutes: 30)
        let otherBlock = TaskBundle(title: "Evening block", dateKey: "2026-06-02", startMin: 1_200, durationMinutes: 30)
        modelContext.insert(block)
        modelContext.insert(otherBlock)

        let dragged = AppTask(title: "Dragged onto a day")
        let firstSibling = AppTask(title: "Stays in the block")
        let secondSibling = AppTask(title: "Also stays in the block")
        let bystander = AppTask(title: "In the other block entirely")
        for task in [dragged, firstSibling, secondSibling, bystander] {
            modelContext.insert(task)
        }
        // **The fixture builds its own membership now** ([[T-3170]], trio pass).
        // The Mac's addTask helper on SchedulingActions wrote these same fields and is deleted:
        // the canvas arm that could express "drop a task onto a block" went with
        // `TimelineBundleBlock`, leaving it callerless. (Named in prose rather than as a
        // backticked Type.member on purpose -- it resolves to nothing now, and a memorial that
        // trips the stale-claim sweep costs a ledger line to say what a sentence says for free.) The five writes are spelled here rather than through a surviving
        // helper because there is no longer a production path that forms a block, and a test
        // fixture reaching for one would be asserting against machinery the app does not have.
        // `TaskBundle` itself is still a `@Model`, which is what keeps these rows constructible.
        for (order, member) in [dragged, firstSibling, secondSibling].enumerated() {
            member.bundle = block
            member.bundleOrder = order
            member.scheduledDate = block.dateKey
            member.scheduledStartMin = -1
            member.calendarEventID = ""
        }
        block.tasks = [dragged, firstSibling, secondSibling]
        bystander.bundle = otherBlock
        bystander.bundleOrder = 0
        bystander.scheduledDate = otherBlock.dateKey
        bystander.scheduledStartMin = -1
        bystander.calendarEventID = ""
        otherBlock.tasks = [bystander]

        // The membership write above clears both of these, so they are written afterwards or they
        // are not written.
        dragged.scheduledStartMin = 600
        dragged.estimatedMinutes = 0
        for member in [dragged, firstSibling, secondSibling] {
            member.calendarEventID = "event-\(member.title)"
        }
        bystander.calendarEventID = "event-bystander"
        try modelContext.save()

        // The fixture is only a fixture if it starts where the assertions below say it does.
        #expect(dragged.bundleOrder == 0)
        #expect(firstSibling.bundleOrder == 1)
        #expect(secondSibling.bundleOrder == 2)
        #expect(dragged.estimatedMinutes == 0)

        return BoardFixture(
            modelContext: modelContext,
            dragged: dragged,
            siblings: [firstSibling, secondSibling],
            block: block,
            bystander: bystander,
            otherBlock: otherBlock
        )
    }

    // MARK: - The mobile day-drop mutation (PA-13 / T-1470)

    /// Both outcomes, with and without a materialised estimate. The subject is still the last
    /// member of a block — it was chosen because zeroing an already-zero `bundleOrder` would not
    /// have exercised its restoration, and it is kept now for the opposite reason: [[T-3170]]
    /// removed the detach, so a non-zero `bundleOrder` is what proves nothing writes those fields
    /// in either answer.
    @Test(arguments: [true, false], [0, 45])
    func mobileDayDropRestoresEveryMutatedFieldOnlyWhenRefused(refuses: Bool, estimate: Int) throws {
        let modelContainer = try container()
        let board = try fixture(in: modelContainer)
        board.modelContext.autosaveEnabled = false
        let task = board.siblings[1]
        task.estimatedMinutes = estimate
        task.scheduledStartMin = 615
        task.dueDate = "2026-08-01"
        try board.modelContext.save()
        #expect(task.bundleOrder == 2)
        let originalMemberIDs = board.block.sortedTasks.map(\.id)
        let originalEventID = task.calendarEventID
        let bystanderTitle = board.bystander.title
        board.bystander.title = "An unrelated pending edit"

        let counter = CountingDayDropCommit()
        counter.refuses = refuses
        final class Observed { var dates: [String] = [] }
        let observed = Observed()
        let recorder = CadenceWindDownReconciler(isLive: false) { _ in
            observed.dates.append(task.scheduledDate)
        }
        let landed = CadenceTaskDateEditing.moveTaskToDate(
            task,
            dateKey: "2026-07-04",
            in: board.modelContext,
            reconciler: recorder,
            commit: counter.commit
        )

        // Read live objects before any fetch can mask a missing in-memory restore.
        #expect(landed == !refuses)
        #expect(counter.commitCount == 1)
        #expect(observed.dates == [refuses ? "2026-06-01" : "2026-07-04"], "reconcile once, after commit or restore")
        #expect(task.scheduledDate == (refuses ? "2026-06-01" : "2026-07-04"))
        #expect(task.estimatedMinutes == (refuses ? estimate : max(estimate, 30)))
        // **The detach is gone, on purpose** ([[T-3170]]). `moveTaskToDate` used to clear
        // `bundle`, zero `bundleOrder` and filter the card out of the block's `tasks`. Its one
        // caller buckets its columns through
        // `CalendarBoardPlannerSupport.tasksByBoardDateFoldingDueDates`, which excludes a bundled
        // task outright, so no card this drop can reach was ever in a block and the detach could
        // never fire. Asserted rather than dropped: the fields stay **untouched in both answers**,
        // which is the shape that fails if anything starts writing them again. The macOS board's
        // own drop still detaches and is pinned by the `CalendarPageBoardDropSupport` cases below.
        #expect(task.bundle?.id == board.block.id)
        #expect(task.bundleOrder == 2)
        #expect(board.block.sortedTasks.map(\.id) == originalMemberIDs)
        #expect(board.dragged.bundleOrder == 0)
        #expect(board.siblings[0].bundleOrder == 1)
        #expect(task.scheduledStartMin == 615)
        #expect(task.dueDate == "2026-08-01")
        #expect(task.calendarEventID == originalEventID)
        #expect(board.bystander.title == "An unrelated pending edit", "no context-wide rollback")
        #expect(board.bystander.bundle?.id == board.otherBlock.id)

        let stored = ModelContext(modelContainer)
        let storedTasks = try stored.fetch(FetchDescriptor<AppTask>())
        let storedTask = try #require(storedTasks.first { $0.id == task.id })
        #expect(storedTask.scheduledDate == task.scheduledDate)
        #expect(storedTask.estimatedMinutes == task.estimatedMinutes)
        #expect(storedTask.bundle?.id == task.bundle?.id)
        #expect(storedTask.bundleOrder == task.bundleOrder)
        let storedBystander = try #require(storedTasks.first { $0.id == board.bystander.id })
        #expect(storedBystander.title == (refuses ? bystanderTitle : "An unrelated pending edit"))
    }

    /// The original failure could escape twice: first as a success answer, then as pending fields
    /// committed by somebody else's save. A second context checks both persistence boundaries.
    @Test func aRefusedMobileDayDropCannotLeakThroughALaterUnrelatedSave() throws {
        let modelContainer = try container()
        let board = try fixture(in: modelContainer)
        board.modelContext.autosaveEnabled = false
        board.dragged.bundleOrder = 7
        try board.modelContext.save()
        let taskID = board.dragged.id
        let blockID = board.block.id
        let originalMemberIDs = Set((board.block.tasks ?? []).map(\.id))
        let counter = CountingDayDropCommit()
        counter.refuses = true

        #expect(!CadenceTaskDateEditing.moveTaskToDate(
            board.dragged,
            dateKey: "2026-07-04",
            in: board.modelContext,
            reconciler: .inert,
            commit: counter.commit
        ))
        #expect(board.dragged.scheduledDate == "2026-06-01")
        #expect(board.dragged.estimatedMinutes == 0)
        #expect(board.dragged.bundle?.id == blockID)
        #expect(board.dragged.bundleOrder == 7)
        #expect(Set((board.block.tasks ?? []).map(\.id)) == originalMemberIDs)

        for saveUnrelatedEdit in [false, true] {
            if saveUnrelatedEdit {
                board.bystander.title = "A later committed edit"
                try board.modelContext.save()
            }
            let stored = ModelContext(modelContainer)
            let task = try #require(try stored.fetch(FetchDescriptor<AppTask>()).first { $0.id == taskID })
            #expect(task.scheduledDate == "2026-06-01")
            #expect(task.estimatedMinutes == 0)
            #expect(task.bundle?.id == blockID)
            #expect(task.bundleOrder == 7)
            let block = try #require(task.bundle)
            #expect(Set((block.tasks ?? []).map(\.id)) == originalMemberIDs)
            let bystander = try #require(try stored.fetch(FetchDescriptor<AppTask>()).first {
                $0.id == board.bystander.id
            })
            #expect(bystander.title == (saveUnrelatedEdit ? "A later committed edit" : "In the other block entirely"))
        }
    }

    // MARK: - The card drop, against its own control

    /// The card half of the ticket in one test, and it needs both readings: a refused drop and a
    /// taken drop over **identical** fixtures, each the other's control. A suite that only asserted
    /// the taken one passes with `try? modelContext.save()` still in the file.
    @Test func adayColumnCardDropRefusedByTheStoreKeepsTheCardOnItsOldDayAndInItsBlock() throws {
        let modelContainer = try container()

        let refusing = try fixture(in: modelContainer)
        let refusingCommit = CountingDayDropCommit()
        refusingCommit.refuses = true
        let refusedOutcome = CalendarPageBoardDropSupport.schedule(
            refusing.dragged,
            on: "2026-07-04",
            modelContext: refusing.modelContext,
            reconciler: .inert,
            commit: refusingCommit.commit
        )

        #expect(refusedOutcome == .refused)
        #expect(refusingCommit.commitCount == 1, "the target resolved, so the drop must have been offered")
        #expect(refusing.dragged.scheduledDate == "2026-06-01", "the do date came back")
        #expect(refusing.dragged.scheduledStartMin == 600, "and so did the timeline slot")
        #expect(refusing.dragged.estimatedMinutes == 0, "and so did the estimate the drop materialised")
        #expect(refusing.dragged.bundle?.id == refusing.block.id, "and so did the block membership")
        #expect(refusing.dragged.bundleOrder == 0)
        #expect(
            refusing.block.sortedTasks.count == 3,
            "the block still holds all three, so the card is drawn where the notice says it is"
        )
        #expect(
            refusing.siblings.map(\.bundleOrder) == [1, 2],
            "the detach renumbered the members that stayed; the undo put the numbering back"
        )
        #expect(refusing.bystander.bundle?.id == refusing.otherBlock.id)
        #expect(refusing.bystander.bundleOrder == 0, "a block this drop never touched is untouched")

        let taking = try fixture(in: modelContainer)
        let takingCommit = CountingDayDropCommit()
        let appliedOutcome = CalendarPageBoardDropSupport.schedule(
            taking.dragged,
            on: "2026-07-04",
            modelContext: taking.modelContext,
            reconciler: .inert,
            commit: takingCommit.commit
        )

        #expect(appliedOutcome == .applied)
        #expect(takingCommit.commitCount == 1)
        #expect(taking.dragged.scheduledDate == "2026-07-04")
        #expect(taking.dragged.bundle == nil)
        #expect(
            taking.dragged.estimatedMinutes == AppTask.defaultTimelineDurationMinutes,
            "a card with no estimate lands as long as the board already draws it"
        )
        #expect(taking.block.sortedTasks.count == 2)

        // The same number of commits over identical fixtures, and the two stores do not agree —
        // which is the shape a count assertion needs to be worth anything.
        #expect(refusingCommit.commitCount == takingCommit.commitCount)
        #expect(
            refusing.dragged.scheduledDate != taking.dragged.scheduledDate,
            "a refused drop and a taken drop that read the same prove nothing"
        )
        #expect(refusing.dragged.estimatedMinutes != taking.dragged.estimatedMinutes)
        #expect((refusing.dragged.bundle == nil) != (taking.dragged.bundle == nil))
    }

    /// The reading the user's next launch makes, taken from a **second `ModelContext` on the same
    /// container**: a live object answers whatever was last assigned to it, so only the store can
    /// say whether a refused drop left anything behind.
    @Test func therefusedDayColumnCardDropIsInvisibleToASecondContext() throws {
        let modelContainer = try container()
        let board = try fixture(in: modelContainer)
        let refusingCommit = CountingDayDropCommit()
        refusingCommit.refuses = true

        let outcome = CalendarPageBoardDropSupport.schedule(
            board.dragged,
            on: "2026-07-04",
            modelContext: board.modelContext,
            reconciler: .inert,
            commit: refusingCommit.commit
        )
        #expect(outcome == .refused)

        let draggedID = board.dragged.id
        let stored = ModelContext(modelContainer)
        let storedTask = try #require(
            try stored.fetch(FetchDescriptor<AppTask>()).first { $0.id == draggedID }
        )
        #expect(storedTask.scheduledDate == "2026-06-01", "the store never took the new day")
        #expect(storedTask.scheduledStartMin == 600)
        #expect(storedTask.estimatedMinutes == 0)
        #expect(storedTask.bundle != nil, "nor the detach")

        let storedBlocks = try stored.fetch(FetchDescriptor<TaskBundle>())
        let storedBlock = try #require(storedBlocks.first { $0.dateKey == "2026-06-01" })
        #expect(storedBlock.sortedTasks.count == 3)
        #expect(storedBlock.sortedTasks.map(\.bundleOrder) == [0, 1, 2])
    }

    // T-3170 retired the three Block-move refusal/slot/store tests with the move chain.
    // Card-drop refusal, sibling restoration and second-context checks above remain live.

    // MARK: - Resolution happens before anything is written

    /// A day the board cannot place a drop on must never reach `commit`, because the app has one
    /// `ModelContext` and committing over a drop that moved nothing commits whatever unrelated
    /// pending work it happens to be holding — the same reason the rail drop guards it. The
    /// two readings are asserted to **differ**, so a path that simply never commits cannot pass.
    @Test func adayColumnDropWithNoDayNeverReachesTheCommit() throws {
        let modelContainer = try container()
        let board = try fixture(in: modelContainer)

        let unplaceable = CountingDayDropCommit()
        #expect(
            CalendarPageBoardDropSupport.schedule(
                board.dragged,
                on: "",
                modelContext: board.modelContext,
                reconciler: .inert,
                commit: unplaceable.commit
            ) == .resolvedNothing
        )
        #expect(unplaceable.commitCount == 0)
        #expect(board.dragged.scheduledDate == "2026-06-01", "and nothing was written on the way out")
        #expect(board.block.dateKey == "2026-06-01")

        let placeable = CountingDayDropCommit()
        #expect(
            CalendarPageBoardDropSupport.schedule(
                board.dragged,
                on: "2026-07-04",
                modelContext: board.modelContext,
                reconciler: .inert,
                commit: placeable.commit
            ) == .applied
        )
        #expect(placeable.commitCount == 1)
        #expect(
            unplaceable.commitCount != placeable.commitCount,
            "an unplaceable drop and a placeable one must not commit the same number of times"
        )
    }

    /// One drop is one commit, and six drops are six: the detach, the date and the estimate are one
    /// unit of work, not three. The shipping defect one surface over ([[T-1580]]) was exactly a
    /// gesture that committed twice with no undo between the halves.
    @Test func onedayColumnDropIsOneCommitAndSixAreSix() throws {
        let modelContainer = try container()
        let counter = CountingDayDropCommit()

        for index in 0..<6 {
            let board = try fixture(in: modelContainer)
            #expect(
                CalendarPageBoardDropSupport.schedule(
                    board.dragged,
                    on: "2026-07-0\(index + 1)",
                    modelContext: board.modelContext,
                    reconciler: .inert,
                    commit: counter.commit
                ) == .applied
            )
        }

        #expect(counter.commitCount == 6)


    }

    // MARK: - What the surface does with the three answers

    /// The commit is only half of it: the task callback must carry a refusal to the column.
    @Test func theCalendarBoardNamesARefusedDayColumnDropOnScreen() throws {
        let source = try CadenceCommitSurfaceScan.scanned(
            "Cadence/macOS/Views/CalendarPageBoardSupportViews.swift"
        )

        // The task drop is the one day-column mutation left after T-3170.
        for unit in ["schedule"] {
            let body = try CadenceCommitSurfaceScan.declarationBody(named: unit, in: source)
            #expect(!body.contains("try? "), "\(unit): the swallowed commit is gone")
            #expect(
                body.contains("CadenceTaskFieldEditCommit."),
                "\(unit): and the one commit is the undoing one"
            )
        }
        #expect(
            try CadenceCommitSurfaceScan.declarationBody(named: "schedule", in: source)
                .contains("alsoRestoring: blockSiblings"),
            "the card drop snapshots the block members its detach renumbers"
        )

        for handler in ["handleDayColumnDrop"] {
            let body = try CadenceCommitSurfaceScan.declarationBody(named: handler, in: source)
            #expect(!body.contains("try? modelContext.save()"), "\(handler): no swallow left in the view")
            #expect(
                body.contains(
                    "dropFailureNotice = outcome == .refused ? CadencePendingChangePersistence.editFailureNotice : nil"
                ),
                "\(handler): maps .refused onto the board's notice slot"
            )
            #expect(
                body.contains("return outcome == .applied"),
                "\(handler): and only .applied is an accepted drop"
            )
        }
    }

    /// The other file, and the half no amount of work inside `CalendarPageBoardView` could have
    /// fixed: `CalendarBoardDayColumn.handleDrop` answered `.dropDestination` `true` whatever the
    /// store did, because the callbacks it forwards to returned `Void`. That `Void` is also why
    /// `CadenceSaveCommitRule`'s report half could not see either drop. One callback remains since
    /// [[T-3170]]; the rule it proves is unchanged.
    @Test func thecalendarBoardDayColumnForwardsTheDropAnswerItIsGiven() throws {
        let source = try CadenceCommitSurfaceScan.scanned(
            "Cadence/macOS/Views/CalendarBoardDayColumnSupportViews.swift"
        )

        #expect(source.contains("let onDropTaskOnDay: (AppTask) -> Bool"))
        // [[T-3170]] removed `onDropBundleOnDay` with the Block card, so the `Bool` this test is
        // about is now carried by the one remaining callback.
        #expect(source.contains("onDropBundleOnDay") == false)

        let handleDrop = try CadenceCommitSurfaceScan.declarationBody(named: "handleDrop", in: source)
        #expect(handleDrop.contains("return onDropTaskOnDay(task)"))
        // No unconditional accept left at all. There used to be exactly one — the hit-test
        // deferral to a Block card that had claimed the release — and with no card to claim one
        // the column answers only what the store told it.
        #expect(
            CadenceSourceScan.matchCount(#"return true"#, in: handleDrop) == 0,
            "the column accepts a drop only by forwarding the store's answer"
        )
    }

    /// The mobile callback must carry the same refusal as Mac, all the way to dropDestination.
    @Test func theMobileCalendarBoardColumnForwardsTheDropAnswerItIsGiven() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarBoardView.swift")
        let source = CadenceSourceScan.codeOnly(raw)
        #expect(source.contains("let onDropTaskOnDay: (AppTask) -> Bool"))
        let handleDrop = try CadenceCommitSurfaceScan.declarationBody(named: "handleDrop", in: source)
        #expect(handleDrop.contains("guard let payload = items.first"))
        #expect(handleDrop.contains("return onDropTaskOnDay(task)"))
        #expect(!handleDrop.contains("return true"))
        #expect(source.contains("onDropTaskOnDay: { task in schedule(task, on: dateKey) }"))
    }

    /// The sweep still exempts nothing in either file, which is the state [[T-1952]] reached and
    /// this ticket had to avoid regressing: a `Void` swallow the detector cannot see must not be
    /// paid for with an exemption it can.
    @Test func thesaveDisciplineSweepStillExemptsNeitherCalendarBoardFile() throws {
        for path in [
            "Cadence/macOS/Views/CalendarPageBoardSupportViews.swift",
            "Cadence/macOS/Views/CalendarBoardDayColumnSupportViews.swift"
        ] {
            #expect(CadenceSaveCommitRule.reportExemptions[path] == nil)
            #expect(CadenceSaveCommitRule.indirectReportExemptions[path] == nil)
            #expect(CadenceSaveCommitRule.existenceExemptions[path] == nil)
            #expect(CadenceSaveCommitRule.commitReachExemptions[path] == nil)
        }
        #expect(CadenceSaveCommitRule.reportExemptions.isEmpty, "and the report list is still empty")

        // Non-vacuity: the tables are read from the same type the sweep reads, and they are not
        // empty of everything — a lookup that always answered `nil` could not pass this.
        #expect(!CadenceSaveCommitRule.existenceExemptions.isEmpty)
    }
}
#endif
