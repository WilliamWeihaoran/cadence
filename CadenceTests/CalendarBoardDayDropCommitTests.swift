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
        SchedulingActions.addTask(dragged, to: block)
        SchedulingActions.addTask(firstSibling, to: block)
        SchedulingActions.addTask(secondSibling, to: block)
        SchedulingActions.addTask(bystander, to: otherBlock)

        // `addTask` clears both of these, so they are written afterwards or they are not written.
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

    // MARK: - The block drop, against its own control

    /// The block half, and the field that made it a different shape: `SchedulingActions.dropBundle`
    /// clears every member's `calendarEventID`, which `CadenceTaskFieldSnapshot` did not carry
    /// until this change. A refusal that restored only the two schedule fields would have left the
    /// block's members silently unlinked from their calendar events, under a notice reading
    /// "Nothing was changed".
    @Test func adayColumnBlockDropRefusedByTheStoreKeepsTheBlockAndItsMembersWhereTheyWere() throws {
        let modelContainer = try container()

        let refusing = try fixture(in: modelContainer)
        let refusingCommit = CountingDayDropCommit()
        refusingCommit.refuses = true
        let refusedOutcome = CalendarPageBoardDropSupport.move(
            refusing.block,
            to: "2026-07-04",
            modelContext: refusing.modelContext,
            commit: refusingCommit.commit
        )

        #expect(refusedOutcome == .refused)
        #expect(refusingCommit.commitCount == 1)
        #expect(refusing.block.dateKey == "2026-06-01", "the block came back to its day")
        #expect(
            refusing.block.sortedTasks.map(\.scheduledDate) == ["2026-06-01", "2026-06-01", "2026-06-01"],
            "and so did every member it dragged with it"
        )
        #expect(
            refusing.block.sortedTasks.map(\.calendarEventID).allSatisfy { !$0.isEmpty },
            "and so did the calendar links the move cleared"
        )
        #expect(refusing.otherBlock.dateKey == "2026-06-02", "a block this drop never named is untouched")
        #expect(refusing.bystander.calendarEventID == "event-bystander")

        let taking = try fixture(in: modelContainer)
        let takingCommit = CountingDayDropCommit()
        let appliedOutcome = CalendarPageBoardDropSupport.move(
            taking.block,
            to: "2026-07-04",
            modelContext: taking.modelContext,
            commit: takingCommit.commit
        )

        #expect(appliedOutcome == .applied)
        #expect(takingCommit.commitCount == 1)
        #expect(taking.block.dateKey == "2026-07-04")
        #expect(taking.block.sortedTasks.allSatisfy { $0.scheduledDate == "2026-07-04" })
        #expect(taking.block.sortedTasks.allSatisfy { $0.calendarEventID.isEmpty })
        #expect(taking.otherBlock.dateKey == "2026-06-02")

        #expect(refusingCommit.commitCount == takingCommit.commitCount)
        #expect(
            refusing.block.dateKey != taking.block.dateKey,
            "a refused move and a taken move that read the same prove nothing"
        )
        #expect(
            refusing.block.sortedTasks.map(\.calendarEventID) != taking.block.sortedTasks.map(\.calendarEventID)
        )
    }

    /// The block's own slot is three fields, not one, and `dropBundle` **clamps** two of them — so
    /// a block whose stored slot is out of range is moved *and* re-shaped by one drop. Two blocks
    /// shaped so that each clamp actually bites, because a fixture whose `startMin` and
    /// `durationMinutes` happen to survive the clamp cannot tell a restore from a no-op.
    @Test func arefusedDayColumnBlockDropRestoresTheWholeSlotTheClampReshaped() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)

        // 1430 + 60 runs past the end of the day, so `clampStart` pulls the start back to 1380.
        let lateBlock = TaskBundle(title: "Late block", dateKey: "2026-06-01", startMin: 1_430, durationMinutes: 60)
        // A duration an older build could have stored below the floor; the move raises it to 5.
        let shortBlock = TaskBundle(title: "Short block", dateKey: "2026-06-01", startMin: 60, durationMinutes: 30)
        modelContext.insert(lateBlock)
        modelContext.insert(shortBlock)
        shortBlock.durationMinutes = 2
        try modelContext.save()

        let refusing = CountingDayDropCommit()
        refusing.refuses = true

        #expect(
            CalendarPageBoardDropSupport.move(
                lateBlock,
                to: "2026-07-04",
                modelContext: modelContext,
                commit: refusing.commit
            ) == .refused
        )
        #expect(lateBlock.startMin == 1_430, "the start the clamp pulled back came back")
        #expect(lateBlock.durationMinutes == 60)
        #expect(lateBlock.dateKey == "2026-06-01")

        #expect(
            CalendarPageBoardDropSupport.move(
                shortBlock,
                to: "2026-07-04",
                modelContext: modelContext,
                commit: refusing.commit
            ) == .refused
        )
        #expect(shortBlock.durationMinutes == 2, "the duration the clamp raised came back")
        #expect(shortBlock.dateKey == "2026-06-01")
        #expect(refusing.commitCount == 2)

        // The control the refusals are worthless without: the same two moves, taken, reshape the
        // slot exactly as claimed. Two readings that differ, over fresh rows on the same container.
        let takingContext = ModelContext(modelContainer)
        let takenLate = TaskBundle(title: "Late block", dateKey: "2026-06-01", startMin: 1_430, durationMinutes: 60)
        let takenShort = TaskBundle(title: "Short block", dateKey: "2026-06-01", startMin: 60, durationMinutes: 30)
        takingContext.insert(takenLate)
        takingContext.insert(takenShort)
        takenShort.durationMinutes = 2
        try takingContext.save()

        let taking = CountingDayDropCommit()
        #expect(
            CalendarPageBoardDropSupport.move(
                takenLate,
                to: "2026-07-04",
                modelContext: takingContext,
                commit: taking.commit
            ) == .applied
        )
        #expect(
            CalendarPageBoardDropSupport.move(
                takenShort,
                to: "2026-07-04",
                modelContext: takingContext,
                commit: taking.commit
            ) == .applied
        )
        #expect(takenLate.startMin == 1_380, "the clamp does move the start, so restoring it is a claim")
        #expect(takenShort.durationMinutes == 5, "and it does raise the duration")
        #expect(lateBlock.startMin != takenLate.startMin)
        #expect(shortBlock.durationMinutes != takenShort.durationMinutes)
        #expect(refusing.commitCount == taking.commitCount)
    }

    /// The reading the next launch makes of a refused block move.
    @Test func therefusedDayColumnBlockDropIsInvisibleToASecondContext() throws {
        let modelContainer = try container()
        let board = try fixture(in: modelContainer)
        let refusingCommit = CountingDayDropCommit()
        refusingCommit.refuses = true

        #expect(
            CalendarPageBoardDropSupport.move(
                board.block,
                to: "2026-07-04",
                modelContext: board.modelContext,
                commit: refusingCommit.commit
            ) == .refused
        )

        let stored = ModelContext(modelContainer)
        let storedBlock = try #require(
            try stored.fetch(FetchDescriptor<TaskBundle>()).first { $0.title == "Morning block" }
        )
        #expect(storedBlock.dateKey == "2026-06-01", "the store never took the move")
        #expect(storedBlock.sortedTasks.count == 3)
        #expect(storedBlock.sortedTasks.allSatisfy { $0.scheduledDate == "2026-06-01" })
        #expect(storedBlock.sortedTasks.allSatisfy { !$0.calendarEventID.isEmpty })
    }

    // MARK: - Resolution happens before anything is written

    /// A day the board cannot place a drop on must never reach `commit`, because the app has one
    /// `ModelContext` and committing over a drop that moved nothing commits whatever unrelated
    /// pending work it happens to be holding — `unschedule`'s reason, asked of both day drops. The
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
        #expect(
            CalendarPageBoardDropSupport.move(
                board.block,
                to: "",
                modelContext: board.modelContext,
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
        #expect(
            CalendarPageBoardDropSupport.move(
                board.block,
                to: "2026-07-04",
                modelContext: board.modelContext,
                commit: placeable.commit
            ) == .applied
        )
        #expect(placeable.commitCount == 2)
        #expect(
            unplaceable.commitCount != placeable.commitCount,
            "two unplaceable drops and two placeable ones must not commit the same number of times"
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

        for index in 0..<6 {
            let board = try fixture(in: modelContainer)
            #expect(
                CalendarPageBoardDropSupport.move(
                    board.block,
                    to: "2026-08-0\(index + 1)",
                    modelContext: board.modelContext,
                    commit: counter.commit
                ) == .applied
            )
        }

        #expect(counter.commitCount == 12, "a block move is one commit too, however many members it drags")
    }

    // MARK: - What the surface does with the three answers

    /// The commit is only half of it. Both of these drops reported through a `Void` callback whose
    /// caller answered `.dropDestination` `true` regardless, so the defect lived in two files and
    /// the fix has to as well.
    @Test func theCalendarBoardNamesARefusedDayColumnDropOnScreen() throws {
        let source = try CadenceCommitSurfaceScan.scanned(
            "Cadence/macOS/Views/CalendarPageBoardSupportViews.swift"
        )

        // Four declarations, deliberately named apart: `schedule`/`move` are the units that commit,
        // and `handleDayColumnDrop`/`handleBlockMoveDrop` are the view's mapping of their three
        // answers onto the one `Bool` the column reads. `declarationBody(named:)` asserts there is
        // exactly one of each, so a second copy cannot hide behind a name.
        for unit in ["schedule", "move"] {
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
        #expect(
            try CadenceCommitSurfaceScan.declarationBody(named: "move", in: source)
                .contains("commitBlockMove("),
            "the block drop snapshots the block's own slot as well as its members"
        )

        for handler in ["handleDayColumnDrop", "handleBlockMoveDrop"] {
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
    /// `CadenceSaveCommitRule`'s report half could not see either drop.
    @Test func thecalendarBoardDayColumnForwardsTheDropAnswerItIsGiven() throws {
        let source = try CadenceCommitSurfaceScan.scanned(
            "Cadence/macOS/Views/CalendarBoardDayColumnSupportViews.swift"
        )

        #expect(source.contains("let onDropTaskOnDay: (AppTask) -> Bool"))
        #expect(source.contains("let onDropBundleOnDay: (TaskBundle) -> Bool"))

        let handleDrop = try CadenceCommitSurfaceScan.declarationBody(named: "handleDrop", in: source)
        #expect(handleDrop.contains("return onDropBundleOnDay(bundle)"))
        #expect(handleDrop.contains("return onDropTaskOnDay(task)"))
        // The one `return true` that survives is the deferral: the release landed on a bundle card
        // inside this column, that card's own handler owns the gesture, and the column answering
        // `false` would spring a card back that was in fact accepted.
        #expect(
            CadenceSourceScan.matchCount(#"return true"#, in: handleDrop) == 1,
            "the only unconditional accept left is the hit-test deferral"
        )
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
