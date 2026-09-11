import Foundation
import SwiftData
import Testing
@testable import Cadence

/// [[T-274]]'s bar, taken literally: *"a test that imports an archive into a container and asserts
/// the graph came back — every foreign key resolved, counts equal, and a second import of the same
/// file changing nothing."*
///
/// The three halves are `theWholeGraphComesBackIntoAnEmptyStore`,
/// `everyRelationshipInTheArchiveIsWiredBackUp` and `aSecondImportOfTheSameFileChangesNothing`.
/// Everything else here exists because a restore is used exactly when something has already gone
/// wrong, so the interesting cases are the ones where the destination is not empty and the file is
/// not perfect.
///
/// **`.preservesTheStoredLaunchReports` is load-bearing and is not copied decoration.**
/// `CadenceArchiveImportService.apply` runs `NoteMigrationService` over the imported rows, which
/// writes `noteMigration.lastReport.v1` to `UserDefaults.standard` — so every test in this suite
/// leaves the app a fabricated launch report unless the trait puts the real one back. It is worth
/// It is here because the author checked; the rule could not have asked for it until [[T-1083]],
/// which taught `StoredLaunchReportSuiteRule` to follow the writer one frame down. It asks now, and
/// `theArchiveImportSuiteIsAskedForTheTraitByTheRuleRatherThanByItsAuthor` is that claim measured
/// against this file: strip the trait and the sweep names this suite.
@Suite(.preservesTheStoredLaunchReports)
@MainActor
struct CadenceArchiveImportSurfaceTests {

    // MARK: - The plan speaks the schema's vocabulary

    /// The entity names in this file and in the importer are string literals, so a typo would make
    /// a table silently invisible to the plan while everything still compiled and imported. The
    /// plan's own keys are compared to `CadenceSchema` for that reason — the same schema-driven
    /// check `CadenceDataExportSurfaceTests` applies to the export's table list.
    @Test func thePlanCountsEverySchemaEntityAndNothingElse() throws {
        let context = ModelContext(try CadenceTestStore.container())
        let archive = try CadenceDataExportService.makeArchive(in: context)

        let plan = try CadenceArchiveImportService.plan(archive, in: context)
        let schemaNames = Set(CadenceSchema.schema.entities.map(\.name))

        #expect(Set(plan.insertCountsByEntityName.keys) == schemaNames)
        #expect(Set(plan.matchedCountsByEntityName.keys) == schemaNames)
        #expect(schemaNames.count >= 20, "CadenceSchema reports only \(schemaNames.count) entities")
    }

    // MARK: - The calendar-link caveat (T-1084)

    /// The archive carries a device-local `EKCalendar.calendarIdentifier` per linked list, the plan
    /// counts them, and the preview says so before the first write.
    ///
    /// [[T-661]] kept the field and shipped no copy about it, on the ground that there was no
    /// restore for a caveat to qualify. [[T-1082]] shipped one. The identifier itself is deliberately
    /// still restored verbatim — [[T-624]]'s gate makes a foreign one inert rather than a break with
    /// a repair beside it — so what this pins is the *sentence*, and that the count behind it comes
    /// off the archive rather than off a guess.
    @Test func anArchivesCalendarLinksAreCountedAndNamedInThePreview() throws {
        let source = ModelContext(try CadenceTestStore.container())
        let linkedArea = Area(name: "Home")
        linkedArea.linkedCalendarID = "cal-home"
        let linkedProject = Project(name: "Move")
        linkedProject.linkedCalendarID = "cal-move"
        let unlinkedArea = Area(name: "Work")
        for model in [linkedArea, linkedProject, unlinkedArea] as [any PersistentModel] {
            source.insert(model)
        }
        try source.save()

        let archive = try CadenceDataExportService.makeArchive(in: source)
        let destination = ModelContext(try CadenceTestStore.container())
        let plan = try CadenceArchiveImportService.plan(archive, in: destination)

        #expect(plan.linkedCalendarCount == 2, "the unlinked list was counted, or a linked one was not")
        let note = try #require(CadenceArchiveImportPresentation.calendarLinksNote(plan))
        #expect(note.contains("2 lists are connected to"))
        #expect(note.contains("belongs to the device that made it"))

        // And the identifiers still arrive verbatim: the note is copy, not a behaviour change.
        _ = try CadenceArchiveImportService.apply(archive, in: destination)
        let areas = try destination.fetch(FetchDescriptor<Area>())
        #expect(areas.first { $0.name == "Home" }?.linkedCalendarID == "cal-home")
        #expect(areas.first { $0.name == "Work" }?.linkedCalendarID == "")
    }

    /// An archive with no linked list gets no caveat. The preview already names the kinds of record
    /// an import cannot store and says nothing when there are none; this is the same shape and must
    /// stay conditional for the same reason.
    @Test func anArchiveWithNoCalendarLinkGetsNoCaveat() throws {
        let source = ModelContext(try CadenceTestStore.container())
        source.insert(Area(name: "Work"))
        try source.save()

        let archive = try CadenceDataExportService.makeArchive(in: source)
        let plan = try CadenceArchiveImportService.plan(
            archive,
            in: ModelContext(try CadenceTestStore.container())
        )
        #expect(plan.linkedCalendarCount == 0)
        #expect(CadenceArchiveImportPresentation.calendarLinksNote(plan) == nil)
    }

    // MARK: - The restore itself

    /// Counts equal, table for table, into a store that had nothing.
    @Test func theWholeGraphComesBackIntoAnEmptyStore() throws {
        let source = ModelContext(try CadenceTestStore.container())
        try Self.seedTheWholeSchema(into: source)
        let archive = try CadenceDataExportService.makeArchive(in: source)

        let destination = ModelContext(try CadenceTestStore.container())
        let outcome = try CadenceArchiveImportService.apply(archive, in: destination)

        #expect(outcome.insertedRecordCount == archive.totalRecordCount)
        #expect(outcome.overwrittenRecordCount == 0)
        #expect(outcome.skippedRecordCount == 0)

        let restored = try CadenceDataExportService.makeArchive(in: destination)
        for name in CadenceArchive.recordCountsByEntityName.keys.sorted() {
            #expect(
                restored.recordCount(forEntityNamed: name) == archive.recordCount(forEntityNamed: name),
                """
                \(name): archive holds \(archive.recordCount(forEntityNamed: name) ?? -1), \
                restored store holds \(restored.recordCount(forEntityNamed: name) ?? -1)
                """
            )
        }
        // Positive control: an all-zero comparison would satisfy the loop above vacuously.
        #expect(archive.totalRecordCount >= 21)
    }

    /// **A restored note's folder goes through the shared normalizer (T-1086).**
    ///
    /// `Note.folderPath` is a convention over a plain `String` — separator `/`, no leading or
    /// trailing separator, no empty components — and it holds only because exactly one place
    /// writes it. Every other writer in the app is a user action that has already been normalized;
    /// an archive is the one source of paths that has not, since it is JSON and can have been
    /// edited by hand or written by an older build. The importer copied it through verbatim, which
    /// made it the second writer, and `onlyTheSharedFilingHelperWritesAFolderPath` said so.
    ///
    /// It now calls `CadenceListNoteFiling.move(_:toFolder:)`. The un-normalized path is seeded on
    /// the *source* store deliberately: it is what a hand-edited archive looks like, and the
    /// assertion on the archive in between is what makes this a test of the import rather than of
    /// an export that had already cleaned it.
    @Test func anImportedNoteIsFiledThroughTheSharedNormalizer() throws {
        let source = ModelContext(try CadenceTestStore.container())
        let note = Note(kind: .list, title: "Kitchen notes", content: "# Kitchen")
        note.folderPath = "/Planning//Research/"
        source.insert(note)
        try source.save()

        let archive = try CadenceDataExportService.makeArchive(in: source)
        #expect(
            archive.notes.first?.folderPath == "/Planning//Research/",
            "the export normalized the path, so this says nothing about the import"
        )

        let destination = ModelContext(try CadenceTestStore.container())
        try CadenceArchiveImportService.apply(archive, in: destination)

        let restored = try #require(try destination.fetch(FetchDescriptor<Note>()).first)
        #expect(restored.folderPath == "Planning/Research")
    }

    /// Every foreign key resolved — checked on the *destination's own objects*, not on the archive,
    /// because the archive is only ids and the thing under test is whether they became references.
    @Test func everyRelationshipInTheArchiveIsWiredBackUp() throws {
        let source = ModelContext(try CadenceTestStore.container())
        try Self.seedTheWholeSchema(into: source)
        let archive = try CadenceDataExportService.makeArchive(in: source)

        let destination = ModelContext(try CadenceTestStore.container())
        try CadenceArchiveImportService.apply(archive, in: destination)

        let area = try #require(try Self.one(Area.self, in: destination))
        let project = try #require(try Self.one(Project.self, in: destination))
        let task = try #require(try Self.one(AppTask.self, in: destination))
        let subtask = try #require(try Self.one(Subtask.self, in: destination))
        // By title, not `.first`: the fixture's fold leaves six notes and fetch order is not
        // a promise.
        let note = try #require(
            try destination.fetch(FetchDescriptor<Note>()).first { $0.title == "Kitchen notes" }
        )
        let goal = try #require(try Self.one(Goal.self, in: destination))
        let link = try #require(try Self.one(GoalListLink.self, in: destination))
        let completion = try #require(try Self.one(HabitCompletion.self, in: destination))
        let session = try #require(try Self.one(FocusSessionLog.self, in: destination))
        let saved = try #require(try Self.one(SavedLink.self, in: destination))
        let bundle = try #require(try Self.one(TaskBundle.self, in: destination))

        // To-one, down every level of the graph.
        #expect(area.context?.name == "Work")
        #expect(project.area?.id == area.id)
        #expect(project.context?.id == area.context?.id)
        #expect(task.project?.id == project.id)
        #expect(task.area?.id == area.id)
        #expect(task.goal?.id == goal.id)
        #expect(task.bundle?.id == bundle.id)
        #expect(subtask.parentTask?.id == task.id)
        #expect(completion.habit?.title == "Stretch")
        #expect(session.task?.id == task.id)
        #expect(note.area?.id == area.id)
        #expect(saved.project?.id == project.id)
        #expect(goal.parentGoal == nil)
        #expect(link.goal?.id == goal.id)
        #expect(link.area?.id == area.id)

        // Many-to-many, which travels as a list of ids and is the one that silently comes back
        // empty if pass two skips a table.
        #expect(task.tags?.count == 1)
        #expect(task.tags?.first?.slug == "errand")
        #expect(note.tags?.count == 1)

        // The inverse arrays, which nothing in the importer writes: SwiftData back-populates them
        // and `Cadence/Models/AGENTS.md` (T-387) says so. If that ever stops being true, the
        // importer has to write both sides and this is what says so.
        #expect(task.subtasks?.contains { $0.id == subtask.id } == true)
        #expect(area.tasks?.contains { $0.id == task.id } == true)
    }

    /// Sub-second precision survives, so a restored store sorts its tasks the way the exported one
    /// did. `TaskOrdering.fallbackPrecedes` breaks ties on `createdAt`, which is why
    /// `CadenceArchiveTimestamp` exists at all.
    @Test func timestampsComeBackToTheMillisecond() throws {
        let source = ModelContext(try CadenceTestStore.container())
        let task = AppTask(title: "Buy milk")
        task.createdAt = CadenceArchiveTimestamp.normalized(Date(timeIntervalSince1970: 1_772_000_000.123))
        source.insert(task)
        try source.save()
        let archive = try CadenceDataExportService.makeArchive(in: source)

        let destination = ModelContext(try CadenceTestStore.container())
        try CadenceArchiveImportService.apply(archive, in: destination)

        let restored = try #require(try Self.one(AppTask.self, in: destination))
        #expect(restored.createdAt == task.createdAt)
    }

    /// The import commits rather than leaving the rows pending for an unrelated later `save()`.
    /// A second context over the same container is the only reader that can tell the difference.
    @Test func theImportCommitsRatherThanLeavingTheRowsPending() throws {
        let source = ModelContext(try CadenceTestStore.container())
        try Self.seedTheWholeSchema(into: source)
        let archive = try CadenceDataExportService.makeArchive(in: source)

        let container = try CadenceTestStore.container()
        let destination = ModelContext(container)
        try CadenceArchiveImportService.apply(archive, in: destination)

        #expect(destination.hasChanges == false)
        let observer = ModelContext(container)
        #expect(try observer.fetchCount(FetchDescriptor<AppTask>()) == 1)
    }

    // MARK: - Idempotence

    @Test func aSecondImportOfTheSameFileChangesNothing() throws {
        let source = ModelContext(try CadenceTestStore.container())
        try Self.seedTheWholeSchema(into: source)
        let archive = try CadenceDataExportService.makeArchive(in: source)

        let destination = ModelContext(try CadenceTestStore.container())
        try CadenceArchiveImportService.apply(archive, in: destination)
        // A fixed `exportedAt` on both snapshots: the header's clock is the one field that differs
        // between two exports of an unchanged store, and comparing whole archives is the point.
        let stamp = Date(timeIntervalSince1970: 1_772_000_000)
        let after = try CadenceDataExportService.makeArchive(in: destination, exportedAt: stamp)

        let plan = try CadenceArchiveImportService.plan(archive, in: destination)
        #expect(plan.changesAnything == false)
        #expect(plan.totalInsertCount == 0)
        #expect(plan.totalMatchedCount == archive.totalRecordCount)

        let second = try CadenceArchiveImportService.apply(archive, in: destination)
        #expect(second.insertedRecordCount == 0)
        #expect(second.overwrittenRecordCount == 0)
        #expect(second.skippedRecordCount == archive.totalRecordCount)
        #expect(try CadenceDataExportService.makeArchive(in: destination, exportedAt: stamp) == after)
    }

    // MARK: - The two modes

    /// Merge leaves the destination's copy of a matched row exactly as it was. This is the mode a
    /// user gets by default, and the reason: the archive's older title must not silently overwrite
    /// the edit they made this morning.
    @Test func mergeKeepsTheDestinationsCopyOfAMatchedRow() throws {
        let (archive, destination, task) = try Self.driftedStore()

        let outcome = try CadenceArchiveImportService.apply(
            archive,
            mode: .mergeKeepingExistingRows,
            in: destination
        )

        #expect(task.title == "Renamed after the backup")
        #expect(task.area == nil)
        #expect(outcome.skippedRecordCount >= 1)
        #expect(outcome.overwrittenRecordCount == 0)
    }

    /// Restore is the other answer to the same collision, and it has to move the *relationships*
    /// too — a row with the archive's fields and the store's old references is neither copy.
    @Test func restoreOverwritesAMatchedRowAndItsRelationships() throws {
        let (archive, destination, task) = try Self.driftedStore()

        let outcome = try CadenceArchiveImportService.apply(
            archive,
            mode: .restoreOverwritingExistingRows,
            in: destination
        )

        #expect(task.title == "Buy milk")
        #expect(task.area?.name == "Home")
        #expect(outcome.overwrittenRecordCount >= 1)
        #expect(outcome.skippedRecordCount == 0)
    }

    /// Neither mode deletes. A row the user made after the archive was written is still there
    /// afterwards — the single property that makes an import safe to try.
    @Test func neitherModeDeletesARowTheArchiveDoesNotContain() throws {
        for mode in CadenceArchiveImportMode.allCases {
            let source = ModelContext(try CadenceTestStore.container())
            source.insert(AppTask(title: "Buy milk"))
            try source.save()
            let archive = try CadenceDataExportService.makeArchive(in: source)

            let destination = ModelContext(try CadenceTestStore.container())
            let newer = AppTask(title: "Written after the backup")
            destination.insert(newer)
            try destination.save()

            try CadenceArchiveImportService.apply(archive, mode: mode, in: destination)

            let titles = try destination.fetch(FetchDescriptor<AppTask>()).map(\.title).sorted()
            #expect(titles == ["Buy milk", "Written after the backup"], "mode \(mode.rawValue)")
        }
    }

    // MARK: - The cached focus totals the restored sessions are about (T-1114)

    /// The audit's arithmetic witness, through the real importer and read back from a context that
    /// has never seen the import: destination task at 10 minutes with one
    /// `(previousMinutes: 0, minutes: 10)` row, archive adds `(previousMinutes: 10, minutes: 20)`,
    /// counter ends at 30 rather than at the 10 it was left holding.
    ///
    /// **A counter is not an independent field.** `actualMinutes` is a cached total of
    /// `FocusSessionLog` rows, so an import that restores a task's missing sessions and leaves the
    /// number alone has restored the minutes into the store and not into anything that shows them
    /// — including the hours-mode `Goal` progress `GoalContributionResolver` folds them into. The
    /// merge keeping the destination's *row* is right; keeping its stale derivation is not.
    @Test func aMergeThatRestoresAMissingFocusSessionRaisesTheTasksCachedTotal() throws {
        let (archive, container, taskID) = try Self.storeMissingTheArchivesSecondSession()

        try CadenceArchiveImportService.apply(
            archive,
            mode: .mergeKeepingExistingRows,
            in: ModelContext(container)
        )

        let reader = ModelContext(container)
        let task = try #require(
            try reader.fetch(FetchDescriptor<AppTask>()).first { $0.id == taskID }
        )
        #expect(task.actualMinutes == 30, "the restored session's minutes are in the store and not on the task")
        #expect(task.focusSessions?.count == 2)
        // Merge still means merge: the raise is the derived total, not permission to take the
        // archive's copy of a field the user has since edited.
        #expect(task.title == "Renamed after the backup")
    }

    /// Importing the same archive again lands on the same number. `reconcile(rows:)` is
    /// `max(counter, min(previousMinutes) + Σminutes)` and therefore idempotent — a restore is
    /// something people retry, and a second run that added the restored minutes a second time
    /// would be worse than the defect.
    @Test func reimportingTheSameArchiveLeavesTheRaisedTotalWhereItIs() throws {
        let (archive, container, taskID) = try Self.storeMissingTheArchivesSecondSession()

        for _ in 0..<3 {
            try CadenceArchiveImportService.apply(archive, in: ModelContext(container))
        }

        let reader = ModelContext(container)
        let task = try #require(
            try reader.fetch(FetchDescriptor<AppTask>()).first { $0.id == taskID }
        )
        #expect(task.actualMinutes == 30)
        #expect(task.focusSessions?.count == 2, "a repeat import duplicated the session rows")
    }

    /// The same shape one level up: a focus session against a list moves `Area.loggedMinutes` and
    /// `Project.loggedMinutes`, which are the same cached total under a different name.
    @Test func aRestoredListSessionRaisesTheListsCachedTotalTooForBothKindsOfList() throws {
        for kind in ["area", "project"] {
            let source = ModelContext(try CadenceTestStore.container())
            let area = Area(name: "Home")
            let project = Project(name: "Kitchen")
            source.insert(area)
            source.insert(project)
            for (index, row) in [(0, 10), (10, 20)].enumerated() {
                let session = FocusSessionLog(
                    minutes: row.1,
                    previousMinutes: row.0,
                    loggedAt: Date(timeIntervalSince1970: 1_772_000_000 + Double(index)),
                    dayKey: "2026-02-0\(index + 1)"
                )
                if kind == "area" { session.area = area } else { session.project = project }
                source.insert(session)
            }
            area.loggedMinutes = kind == "area" ? 30 : 0
            project.loggedMinutes = kind == "project" ? 30 : 0
            try source.save()
            let archive = try CadenceDataExportService.makeArchive(in: source)

            // The destination holds the first session only, and the counter that matched it.
            let container = try CadenceTestStore.container()
            let destination = ModelContext(container)
            let localArea = Area(name: "Home")
            localArea.id = area.id
            let localProject = Project(name: "Kitchen")
            localProject.id = project.id
            destination.insert(localArea)
            destination.insert(localProject)
            let first = try #require(archive.focusSessions.first { $0.previousMinutes == 0 })
            let localSession = FocusSessionLog(
                minutes: first.minutes,
                previousMinutes: first.previousMinutes,
                loggedAt: first.loggedAt,
                dayKey: first.dayKey
            )
            localSession.id = first.id
            if kind == "area" { localSession.area = localArea } else { localSession.project = localProject }
            destination.insert(localSession)
            localArea.loggedMinutes = kind == "area" ? 10 : 0
            localProject.loggedMinutes = kind == "project" ? 10 : 0
            try destination.save()

            try CadenceArchiveImportService.apply(archive, mode: .mergeKeepingExistingRows, in: destination)

            let reader = ModelContext(container)
            let raised = kind == "area"
                ? try #require(try Self.one(Area.self, in: reader)).loggedMinutes
                : try #require(try Self.one(Project.self, in: reader)).loggedMinutes
            #expect(raised == 30, "the \(kind)'s cached total did not follow its restored session")
        }
    }

    /// **The raise never lowers**, which is what makes it safe to run unattended on a store that
    /// may be a partial replica. A destination holding more minutes than its own rows can account
    /// for — a counter raised by a device whose rows have not arrived yet — keeps them, because
    /// the ledger's total computed from a subset is *too low* and writing it back would destroy
    /// minutes the counter already had.
    @Test func aMergeNeverLowersACounterToATotalThePresentRowsCannotAccountFor() throws {
        let source = ModelContext(try CadenceTestStore.container())
        let task = AppTask(title: "Buy milk")
        task.actualMinutes = 10
        let session = FocusSessionLog(minutes: 10, previousMinutes: 0, loggedAt: Date(), dayKey: "2026-02-02")
        session.task = task
        source.insert(task)
        source.insert(session)
        try source.save()
        let archive = try CadenceDataExportService.makeArchive(in: source)

        // This device's counter says 90 minutes more and it holds no row for them: the shape of a
        // store still receiving its rows from CloudKit.
        let container = try CadenceTestStore.container()
        let destination = ModelContext(container)
        let local = AppTask(title: "Buy milk")
        local.id = task.id
        local.actualMinutes = 100
        destination.insert(local)
        try destination.save()

        try CadenceArchiveImportService.apply(archive, mode: .mergeKeepingExistingRows, in: destination)

        let reader = ModelContext(container)
        let after = try #require(try Self.one(AppTask.self, in: reader))
        #expect(after.actualMinutes == 100, "the import lowered a counter to a partial ledger")
    }

    /// **Overwrite is where the two rules meet, and neither one is wrong.** Overwrite means the
    /// archive's copy of a matched row replaces the destination's, counter included — so the
    /// scalar does go down to the archive's. What it must not do is discard sessions only this
    /// device has: those rows are not in the archive, are not deleted by any import, and the raise
    /// puts their minutes back on top of the scalar the archive just wrote.
    ///
    /// The property is *coherence*: whatever the mode, the number on screen afterwards is the
    /// total of the session records the store actually holds. A store left showing the archive's
    /// 10 beside 100 minutes of retained history would be the "displayed total and retained
    /// history disagree" case this was asked to rule out.
    @Test func overwriteTakesTheArchivesScalarAndStillCoversTheSessionsOnlyThisDeviceHas() throws {
        let source = ModelContext(try CadenceTestStore.container())
        let task = AppTask(title: "Buy milk")
        source.insert(task)
        CadenceFocusLedger.bank(10, to: task, in: source, now: Date(timeIntervalSince1970: 1_772_000_000))
        try source.save()
        let archive = try CadenceDataExportService.makeArchive(in: source)
        #expect(task.actualMinutes == 10)

        let container = try CadenceTestStore.container()
        let destination = ModelContext(container)
        let local = AppTask(title: "Buy milk")
        local.id = task.id
        destination.insert(local)
        // The archive's own session, under its own id, so overwrite matches it…
        let shared = try #require(archive.focusSessions.first)
        let localShared = FocusSessionLog(
            minutes: shared.minutes,
            previousMinutes: shared.previousMinutes,
            loggedAt: shared.loggedAt,
            dayKey: shared.dayKey
        )
        localShared.id = shared.id
        localShared.task = local
        destination.insert(localShared)
        // …and 90 minutes this device logged afterwards, which the archive has never heard of.
        CadenceFocusLedger.bank(90, to: local, in: destination, now: Date(timeIntervalSince1970: 1_772_086_400))
        try destination.save()
        #expect(local.actualMinutes == 100)

        try CadenceArchiveImportService.apply(
            archive,
            mode: .restoreOverwritingExistingRows,
            in: destination
        )

        let reader = ModelContext(container)
        let after = try #require(try Self.one(AppTask.self, in: reader))
        #expect(after.focusSessions?.count == 2, "an import deleted a session row, which no mode may do")
        #expect(after.actualMinutes == 100, """
            overwrite left the archive's scalar standing against 100 minutes of session rows the \
            store still holds
            """)
    }

    /// A store with no focus rows at all is untouched by the pass, and so is a store whose counters
    /// already agree with their rows. The negative control: a raise that fired on everything would
    /// satisfy the tests above while being wrong.
    @Test func anImportOfAStoreWhoseCountersAlreadyAgreeMovesNothing() throws {
        let source = ModelContext(try CadenceTestStore.container())
        let banked = AppTask(title: "Buy milk")
        source.insert(banked)
        CadenceFocusLedger.bank(25, to: banked, in: source)
        let untimed = AppTask(title: "Never focused")
        untimed.actualMinutes = 7
        source.insert(untimed)
        try source.save()
        let archive = try CadenceDataExportService.makeArchive(in: source)

        let container = try CadenceTestStore.container()
        try CadenceArchiveImportService.apply(archive, in: ModelContext(container))

        let reader = ModelContext(container)
        let tasks = try reader.fetch(FetchDescriptor<AppTask>())
        #expect(tasks.first { $0.id == banked.id }?.actualMinutes == 25)
        #expect(tasks.first { $0.id == untimed.id }?.actualMinutes == 7,
                "a task with no session rows had its counter rewritten")
    }

    // MARK: - Refusals, and the store they must not touch

    /// A reference to a row in neither the archive nor the store is refused, and **nothing is
    /// written** — the claim the whole design rests on, since the store this writes through is
    /// CloudKit-backed and a half-applied import is a half-uploaded one.
    @Test func aDanglingReferenceIsRefusedBeforeAnythingIsWritten() throws {
        let source = ModelContext(try CadenceTestStore.container())
        try Self.seedTheWholeSchema(into: source)
        var archive = try CadenceDataExportService.makeArchive(in: source)
        let stranded = UUID()
        archive.tasks[0].areaID = stranded
        let taskID = archive.tasks[0].id

        let destination = ModelContext(try CadenceTestStore.container())
        #expect(throws: CadenceArchiveImportFailure.danglingReference(
            table: "AppTask",
            record: taskID,
            field: "areaID",
            missing: stranded
        )) {
            try CadenceArchiveImportService.apply(archive, in: destination)
        }

        #expect(try CadenceDataExportService.makeArchive(in: destination).totalRecordCount == 0)
        #expect(destination.hasChanges == false)
    }

    /// A reference the archive does not satisfy but the destination store does is fine: importing
    /// one list's tasks into a store that already has the list is a real thing to want, and
    /// refusing it would make an import all-or-nothing at the document level.
    @Test func aReferenceThatOnlyTheDestinationCanSatisfyIsAccepted() throws {
        let source = ModelContext(try CadenceTestStore.container())
        let area = Area(name: "Home")
        let task = AppTask(title: "Buy milk")
        task.area = area
        source.insert(area)
        source.insert(task)
        try source.save()

        var archive = try CadenceDataExportService.makeArchive(in: source)
        archive.areas = []

        let destination = ModelContext(try CadenceTestStore.container())
        let localArea = Area(name: "Home")
        localArea.id = area.id
        destination.insert(localArea)
        try destination.save()

        try CadenceArchiveImportService.apply(archive, in: destination)

        let restored = try #require(try Self.one(AppTask.self, in: destination))
        #expect(restored.area?.id == area.id)
    }

    @Test func aRepeatedRowIDIsRefused() throws {
        let source = ModelContext(try CadenceTestStore.container())
        source.insert(AppTask(title: "Buy milk"))
        try source.save()
        var archive = try CadenceDataExportService.makeArchive(in: source)
        archive.tasks.append(archive.tasks[0])
        let repeated = archive.tasks[0].id

        let destination = ModelContext(try CadenceTestStore.container())
        #expect(throws: CadenceArchiveImportFailure.duplicateRecordID(table: "AppTask", id: repeated)) {
            try CadenceArchiveImportService.apply(archive, in: destination)
        }
        #expect(try destination.fetchCount(FetchDescriptor<AppTask>()) == 0)
    }

    /// An archive from a newer build may have renamed a key or dropped a table, which this build
    /// would read as absence and import as a quietly incomplete store.
    @Test func anArchiveFromANewerBuildIsRefusedRatherThanPartlyRead() throws {
        let source = ModelContext(try CadenceTestStore.container())
        try Self.seedTheWholeSchema(into: source)
        var archive = try CadenceDataExportService.makeArchive(in: source)
        archive.formatVersion = CadenceDataExportService.formatVersion + 1

        let destination = ModelContext(try CadenceTestStore.container())
        #expect(throws: CadenceArchiveImportFailure.unsupportedFormatVersion(
            found: CadenceDataExportService.formatVersion + 1,
            readableUpTo: CadenceDataExportService.formatVersion
        )) {
            try CadenceArchiveImportService.apply(archive, in: destination)
        }
        #expect(try CadenceDataExportService.makeArchive(in: destination).totalRecordCount == 0)
    }

    /// An older archive is *read*, not refused: `formatVersion` is only bumped for changes a reader
    /// must know about, so a lower number is a document this build still understands.
    @Test func anArchiveFromAnOlderBuildIsStillRead() throws {
        let source = ModelContext(try CadenceTestStore.container())
        source.insert(AppTask(title: "Buy milk"))
        try source.save()
        var archive = try CadenceDataExportService.makeArchive(in: source)
        archive.formatVersion = CadenceDataExportService.formatVersion - 1

        let destination = ModelContext(try CadenceTestStore.container())
        let outcome = try CadenceArchiveImportService.apply(archive, in: destination)
        #expect(outcome.insertedRecordCount == 1)
    }

    /// The failure a user reads names the row. "The import failed" over a four-thousand-row
    /// document is not something anyone can act on.
    @Test func everyRefusalNamesTheRowItRefused() {
        let record = UUID()
        let missing = UUID()
        let dangling = CadenceArchiveImportFailure.danglingReference(
            table: "AppTask",
            record: record,
            field: "areaID",
            missing: missing
        )
        #expect(dangling.message.contains(record.uuidString))
        #expect(dangling.message.contains(missing.uuidString))
        #expect(dangling.message.contains("areaID"))
        #expect(dangling.errorDescription == dangling.message)

        let duplicate = CadenceArchiveImportFailure.duplicateRecordID(table: "Note", id: record)
        #expect(duplicate.message.contains("Note"))
        #expect(duplicate.message.contains(record.uuidString))

        let cycle = CadenceArchiveImportFailure.parentCycle(
            table: "Goal",
            record: record,
            field: "parentGoalID",
            cycle: [record, missing]
        )
        #expect(cycle.message.contains(record.uuidString))
        #expect(cycle.message.contains(missing.uuidString))
        #expect(cycle.message.contains("parentGoalID"))
        #expect(cycle.message.contains("Nothing was imported."))
        #expect(cycle.errorDescription == cycle.message)

        let version = CadenceArchiveImportFailure.unsupportedFormatVersion(found: 9, readableUpTo: 1)
        #expect(version.message.contains("9"))
        #expect(version.message.contains("1"))
    }

    // MARK: - The legacy note tables

    /// A **pre-migration** archive: legacy rows and no canonical `Note`. Importing it must end with
    /// the note readable in today's UI, which means the fold has to run after the insert.
    @Test func aPreMigrationArchiveEndsWithItsNotesFoldedIntoTheLiveModel() throws {
        let source = ModelContext(try CadenceTestStore.container())
        let legacy = DailyNote(date: "2026-02-02")
        legacy.content = "Notes from that day"
        source.insert(legacy)
        try source.save()
        let archive = try CadenceDataExportService.makeArchive(in: source)
        #expect(archive.notes.isEmpty)
        #expect(archive.legacyDailyNotes.count == 1)

        let destination = ModelContext(try CadenceTestStore.container())
        let outcome = try CadenceArchiveImportService.apply(archive, in: destination)

        #expect(outcome.notesFoldedFromLegacyRows == 1)
        let note = try #require(try Self.one(Note.self, in: destination))
        #expect(note.kind == .daily)
        #expect(note.content == "Notes from that day")
        #expect(note.legacySourceID == legacy.id.uuidString)
    }

    /// A **post-migration** archive carries both the legacy row and the `Note` it folded into.
    /// Importing it must not produce two notes — the duplicate-every-note failure [[T-274]] names.
    @Test func aPostMigrationArchiveDoesNotDuplicateItsNotes() throws {
        let source = ModelContext(try CadenceTestStore.container())
        let legacy = DailyNote(date: "2026-02-02")
        legacy.content = "Notes from that day"
        source.insert(legacy)
        try source.save()
        try NoteMigrationService.migrateIfNeeded(in: source, source: "test-fixture")
        #expect(try source.fetchCount(FetchDescriptor<Note>()) == 1)

        let archive = try CadenceDataExportService.makeArchive(in: source)
        #expect(archive.notes.count == 1)
        #expect(archive.legacyDailyNotes.count == 1)

        let destination = ModelContext(try CadenceTestStore.container())
        let first = try CadenceArchiveImportService.apply(archive, in: destination)
        #expect(first.notesFoldedFromLegacyRows == 0)
        #expect(try destination.fetchCount(FetchDescriptor<Note>()) == 1)

        // And again, because a fold that is idempotent only on the first pass is not idempotent.
        try CadenceArchiveImportService.apply(archive, in: destination)
        #expect(try destination.fetchCount(FetchDescriptor<Note>()) == 1)
    }

    // MARK: - The fold is a second write, and it fails on its own terms

    /// **[[T-1111]]. A failed fold must not be reported as a failed import**, because by then the
    /// archive is on disk.
    ///
    /// The fold is a second commit after the archive's own, so a throw from it used to leave `apply`
    /// via the same door as "this file is malformed" — and the caller had no way to tell a restore
    /// that wrote four thousand rows from one that wrote none. This asserts the split from both
    /// sides at once: `apply` **returns**, its committed counts are intact, `legacyNoteFoldFailure`
    /// names what is outstanding, and a *second* context over the same container — the only reader
    /// that cannot be fooled by the importing context's own memory — still finds the rows.
    @Test func aFailedFoldReturnsTheCommittedImportInsteadOfThrowingOverIt() throws {
        let source = ModelContext(try CadenceTestStore.container())
        try Self.seedTheWholeSchema(into: source)
        let archive = try CadenceDataExportService.makeArchive(in: source)

        let container = try CadenceTestStore.container()
        let destination = ModelContext(container)
        let outcome = try CadenceArchiveImportService.apply(
            archive,
            in: destination,
            foldingLegacyNotes: { _ in throw CadenceArchiveImportSurfaceTests.FoldRefusal.disk }
        )

        #expect(outcome.insertedRecordCount == archive.totalRecordCount)
        #expect(outcome.notesFoldedFromLegacyRows == 0)
        #expect(outcome.isComplete == false)
        let reason = try #require(outcome.legacyNoteFoldFailure)
        #expect(reason == CadenceArchiveImportSurfaceTests.FoldRefusal.disk.localizedDescription)

        let observer = ModelContext(container)
        #expect(try observer.fetchCount(FetchDescriptor<AppTask>()) == 1)
        #expect(try observer.fetchCount(FetchDescriptor<Context>()) == 1)
    }

    /// The other half of the same guarantee: a fold that inserted before it threw leaves **nothing**
    /// pending for the next unrelated `save()` through this context to adopt, and the rollback that
    /// achieves that does not reach back past the archive's own commit.
    @Test func aFailedFoldDiscardsItsOwnPendingWorkAndNothingEarlier() throws {
        let source = ModelContext(try CadenceTestStore.container())
        source.insert(AppTask(title: "Buy milk"))
        try source.save()
        let archive = try CadenceDataExportService.makeArchive(in: source)

        let container = try CadenceTestStore.container()
        let destination = ModelContext(container)
        let outcome = try CadenceArchiveImportService.apply(
            archive,
            in: destination,
            foldingLegacyNotes: { context in
                context.insert(Note(kind: .permanent, title: "half-folded", content: ""))
                throw CadenceArchiveImportSurfaceTests.FoldRefusal.disk
            }
        )

        #expect(outcome.legacyNoteFoldFailure != nil)
        #expect(destination.hasChanges == false)

        let observer = ModelContext(container)
        #expect(try observer.fetchCount(FetchDescriptor<AppTask>()) == 1, "the committed import was rolled back")
        #expect(try observer.fetchCount(FetchDescriptor<Note>()) == 0, "the failed fold's insert survived")
    }

    /// The seam is a seam and not a second implementation: the default argument runs the real
    /// migration, so a successful import through it still folds and still reports a clean outcome.
    /// Without this, injecting a failure everywhere would be compatible with `apply` never calling
    /// the fold at all.
    @Test func theDefaultFoldIsTheRealMigrationAndReportsACleanOutcome() throws {
        let source = ModelContext(try CadenceTestStore.container())
        let legacy = DailyNote(date: "2026-02-02")
        legacy.content = "Notes from that day"
        source.insert(legacy)
        try source.save()
        let archive = try CadenceDataExportService.makeArchive(in: source)

        let destination = ModelContext(try CadenceTestStore.container())
        let outcome = try CadenceArchiveImportService.apply(archive, in: destination)

        #expect(outcome.notesFoldedFromLegacyRows == 1)
        #expect(outcome.legacyNoteFoldFailure == nil)
        #expect(outcome.isComplete)
    }

    /// And the line the split is drawn on holds in the other direction: a refusal that happens
    /// **before** the archive's commit is still a throw, with an untouched store behind it. This is
    /// the mutation guard — collapse the two outcomes back into one and either this test or
    /// `aFailedFoldReturnsTheCommittedImportInsteadOfThrowingOverIt` goes red, whichever way the
    /// collapse runs.
    @Test func aRefusalBeforeTheCommitIsStillAThrowOverAnUntouchedStore() throws {
        let source = ModelContext(try CadenceTestStore.container())
        source.insert(AppTask(title: "Buy milk"))
        try source.save()
        var archive = try CadenceDataExportService.makeArchive(in: source)
        archive.formatVersion = CadenceArchiveImportService.readableFormatVersion + 1

        let container = try CadenceTestStore.container()
        let destination = ModelContext(container)
        var returned: CadenceArchiveImportOutcome?
        do {
            returned = try CadenceArchiveImportService.apply(archive, in: destination)
            Issue.record("a refused import returned an outcome instead of throwing")
        } catch {
            #expect(error is CadenceArchiveImportFailure)
        }
        #expect(returned == nil)

        let observer = ModelContext(container)
        #expect(try observer.fetchCount(FetchDescriptor<AppTask>()) == 0)
    }

    // MARK: - T-1109: a goal cycle the Goals page can never show

    /// **The consequence half, measured against the real grouping rather than reasoned about.**
    ///
    /// `GoalMissionGrouping.groups` — the Goals page's only source of rows — starts at
    /// `GoalAssignmentRules.topLevelGoals`, which is `parentGoal == nil`. A cycle has no member
    /// with a `nil` parent, so it contributes no group and no milestone row: the goals are in the
    /// store, on every device, and on no screen. This is why the importer has to refuse one, and it
    /// is deliberately built by hand here rather than through an import, so the invisibility claim
    /// stands on its own if the importer's guard is ever moved.
    @Test func aRootlessGoalCycleIsInTheStoreAndOnNoGoalsRow() throws {
        let modelContext = ModelContext(try CadenceTestStore.container())
        let first = Goal(title: "Ship the thing")
        let second = Goal(title: "Ship the other thing")
        modelContext.insert(first)
        modelContext.insert(second)
        first.parentGoal = second
        second.parentGoal = first
        try modelContext.save()

        let live = try modelContext.fetch(FetchDescriptor<Goal>())

        #expect(live.count == 2, "the rows are not in the store, so this measures nothing")
        #expect(GoalAssignmentRules.topLevelGoals(from: live).isEmpty, "the cycle has a root after all")
        #expect(GoalAssignmentRules.activeTopLevelGoals(from: live).isEmpty)
        #expect(
            GoalMissionGrouping.groups(from: live) { _ in true }.isEmpty,
            "the Goals page can show the cycle, so there is nothing to refuse"
        )
    }

    /// A goal that is its own parent is refused, and the store is left exactly as it was.
    ///
    /// The minimal witness: one record, no repeated id, and a `parentGoalID` that resolves. Every
    /// existence check passes and the hierarchy check is the only thing standing between it and a
    /// goal nothing can show.
    @Test func aGoalThatIsItsOwnParentIsRefused() throws {
        let source = ModelContext(try CadenceTestStore.container())
        let goal = Goal(title: "Ship the thing")
        source.insert(goal)
        try source.save()
        var archive = try CadenceDataExportService.makeArchive(in: source)
        archive.goals[0].parentGoalID = archive.goals[0].id

        let destination = ModelContext(try CadenceTestStore.container())
        #expect(throws: CadenceArchiveImportFailure.parentCycle(
            table: "Goal",
            record: goal.id,
            field: "parentGoalID",
            cycle: [goal.id]
        )) {
            try CadenceArchiveImportService.apply(archive, in: destination)
        }

        #expect(try CadenceDataExportService.makeArchive(in: destination).totalRecordCount == 0)
        #expect(destination.hasChanges == false)

        // The preview refuses it too, so no surface can offer an import that would then fail.
        #expect(throws: CadenceArchiveImportFailure.self) {
            try CadenceArchiveImportService.plan(archive, in: destination)
        }
    }

    /// Two goals pointing at each other clear every existence check as well, and are refused for
    /// the same reason: the pair has no root.
    @Test func aTwoGoalCycleIsRefused() throws {
        let source = ModelContext(try CadenceTestStore.container())
        let first = Goal(title: "Ship the thing")
        let second = Goal(title: "Ship the other thing")
        source.insert(first)
        source.insert(second)
        try source.save()
        var archive = try CadenceDataExportService.makeArchive(in: source)
        let firstID = archive.goals[0].id
        let secondID = archive.goals[1].id
        archive.goals[0].parentGoalID = secondID
        archive.goals[1].parentGoalID = firstID

        let destination = ModelContext(try CadenceTestStore.container())
        var thrown: CadenceArchiveImportFailure?
        do {
            try CadenceArchiveImportService.apply(archive, in: destination)
        } catch let failure as CadenceArchiveImportFailure {
            thrown = failure
        }

        let failure = try #require(thrown)
        guard case let .parentCycle(_, record, _, cycle) = failure else {
            Issue.record("refused with \(failure) rather than a cycle")
            return
        }
        #expect(Set(cycle) == [firstID, secondID])
        #expect(cycle.first == record, "the reported chain does not start at the row it names")
        #expect(try destination.fetchCount(FetchDescriptor<Goal>()) == 0)
    }

    /// **The cycle can close through a row the archive never carries**, which is why checking the
    /// archive's own edges in isolation would not be enough.
    ///
    /// Destination: `first` (no parent) and `second` (parent `first`). The archive holds `first`
    /// alone, with its parent set to `second`. In `.restoreOverwritingExistingRows` that edge is
    /// written and `second`'s is left alone, so the pair closes on a row that is in neither the
    /// archive nor the changed set.
    @Test func aCycleClosedThroughARowTheArchiveDoesNotCarryIsRefused() throws {
        let destination = ModelContext(try CadenceTestStore.container())
        let first = Goal(title: "Ship the thing")
        let second = Goal(title: "Ship the other thing")
        destination.insert(first)
        destination.insert(second)
        second.parentGoal = first
        try destination.save()

        let source = ModelContext(try CadenceTestStore.container())
        let incoming = Goal(title: "Ship the thing")
        incoming.id = first.id
        source.insert(incoming)
        try source.save()
        var archive = try CadenceDataExportService.makeArchive(in: source)
        archive.goals[0].parentGoalID = second.id

        #expect(throws: CadenceArchiveImportFailure.parentCycle(
            table: "Goal",
            record: first.id,
            field: "parentGoalID",
            cycle: [first.id, second.id]
        )) {
            try CadenceArchiveImportService.apply(
                archive,
                mode: .restoreOverwritingExistingRows,
                in: destination
            )
        }

        #expect(first.parentGoal == nil, "the refused edge was written anyway")
        #expect(second.parentGoal?.id == first.id)
        let live = try destination.fetch(FetchDescriptor<Goal>())
        #expect(GoalMissionGrouping.groups(from: live) { _ in true }.count == 1)
    }

    /// **The same document is accepted in merge mode**, because merge never writes the edge.
    ///
    /// A matched row keeps the destination's copy, relationships included, so the incoming parent
    /// edge is not applied and no cycle exists to refuse. Refusing here would refuse an import that
    /// does nothing wrong — the pair against which the check above is not merely "reject anything
    /// that looks circular in the file".
    @Test func aMergeIgnoresAMatchedIncomingEdgeThatWouldHaveCycled() throws {
        let destination = ModelContext(try CadenceTestStore.container())
        let first = Goal(title: "Ship the thing")
        let second = Goal(title: "Ship the other thing")
        destination.insert(first)
        destination.insert(second)
        second.parentGoal = first
        try destination.save()

        let source = ModelContext(try CadenceTestStore.container())
        let incoming = Goal(title: "Ship the thing")
        incoming.id = first.id
        source.insert(incoming)
        try source.save()
        var archive = try CadenceDataExportService.makeArchive(in: source)
        archive.goals[0].parentGoalID = second.id

        let outcome = try CadenceArchiveImportService.apply(archive, in: destination)

        #expect(outcome.skippedRecordCount == 1)
        #expect(first.parentGoal == nil, "a merge overwrote a matched row's relationship")
        let live = try destination.fetch(FetchDescriptor<Goal>())
        #expect(GoalMissionGrouping.groups(from: live) { _ in true }.count == 1)
    }

    /// A component of the destination that was already circular is not this import's to refuse.
    ///
    /// The check names edges the import *writes*. A store that is already corrupt stays importable,
    /// which is the difference between validating input and demanding the destination be clean.
    @Test func anImportIsNotBlockedByADestinationComponentThatWasAlreadyCircular() throws {
        let destination = ModelContext(try CadenceTestStore.container())
        let left = Goal(title: "Already circular")
        let right = Goal(title: "Also already circular")
        destination.insert(left)
        destination.insert(right)
        left.parentGoal = right
        right.parentGoal = left
        try destination.save()

        let source = ModelContext(try CadenceTestStore.container())
        let root = Goal(title: "A direction")
        let milestone = Goal(title: "A milestone")
        let attached = Goal(title: "Hung off the corrupt component")
        source.insert(root)
        source.insert(milestone)
        source.insert(attached)
        milestone.parentGoal = root
        try source.save()
        var archive = try CadenceDataExportService.makeArchive(in: source)

        // **The arriving row is parented straight into the pre-existing cycle.** The walk therefore
        // *reaches* that cycle from a changed edge, which is the case a check that refused any
        // cycle it could see would get wrong: the cycle is still not one this import created.
        let index = try #require(archive.goals.firstIndex { $0.id == attached.id })
        archive.goals[index].parentGoalID = left.id

        let outcome = try CadenceArchiveImportService.apply(archive, in: destination)

        #expect(outcome.insertedRecordCount == 3)
        let live = try destination.fetch(FetchDescriptor<Goal>())
        #expect(live.count == 5)
        // The one importable direction draws its group; the pre-existing cycle still draws nothing,
        // which is what T-1109 is about and not something an import can repair.
        let groups = GoalMissionGrouping.groups(from: live) { _ in true }
        #expect(groups.map(\.title) == ["A direction"])
        #expect(groups.first?.goals.map(\.title) == ["A milestone"])
    }

    /// A deep but acyclic hierarchy is untouched by the check and still arrives whole.
    ///
    /// The guard rejects cycles, not depth. macOS flattens a third level into the top group's
    /// milestones deliberately; a depth limit dressed up as referential integrity would have
    /// decided that question here instead.
    @Test func aDeepAcyclicGoalHierarchyStillImportsAndStillDraws() throws {
        let source = ModelContext(try CadenceTestStore.container())
        let root = Goal(title: "A direction")
        let mid = Goal(title: "A milestone")
        let leaf = Goal(title: "A sub-milestone")
        source.insert(root)
        source.insert(mid)
        source.insert(leaf)
        mid.parentGoal = root
        leaf.parentGoal = mid
        try source.save()
        let archive = try CadenceDataExportService.makeArchive(in: source)

        let destination = ModelContext(try CadenceTestStore.container())
        try CadenceArchiveImportService.apply(archive, in: destination)

        let live = try destination.fetch(FetchDescriptor<Goal>())
        #expect(live.count == 3)
        let groups = GoalMissionGrouping.groups(from: live) { _ in true }
        #expect(groups.map(\.title) == ["A direction"])
        #expect(Set(groups.first?.goals.map(\.title) ?? []) == ["A milestone", "A sub-milestone"])
    }

    /// The injected failure, so the tests above are not depending on some real error's wording.
    enum FoldRefusal: LocalizedError {
        case disk

        var errorDescription: String? { "the notes table could not be read" }
    }

    // MARK: - Helpers

    private static func one<Model: PersistentModel>(
        _ type: Model.Type,
        in modelContext: ModelContext
    ) throws -> Model? {
        try modelContext.fetch(FetchDescriptor<Model>()).first
    }

    /// The audit's setup, built once for the two tests that read it: a device holding the task and
    /// its first focus session, and an archive holding a second session it has never seen.
    ///
    /// Both stores are consistent with their own rows before the import — the destination's 10 is
    /// the right answer for the one row it has — so the raise afterwards can only come from the
    /// row the import restored. The task is also renamed locally, so the same fixture says whether
    /// the raise leaked into the fields merge mode must leave alone.
    ///
    /// Returns the container rather than the context: the assertions read through a second
    /// `ModelContext` over it, which is the difference between a counter that was committed and
    /// one that is only correct in the object the importer happened to be holding.
    private static func storeMissingTheArchivesSecondSession() throws -> (CadenceArchive, ModelContainer, UUID) {
        let source = ModelContext(try CadenceTestStore.container())
        let task = AppTask(title: "Buy milk")
        source.insert(task)
        CadenceFocusLedger.bank(10, to: task, in: source, now: Date(timeIntervalSince1970: 1_772_000_000))
        CadenceFocusLedger.bank(20, to: task, in: source, now: Date(timeIntervalSince1970: 1_772_086_400))
        try source.save()
        #expect(task.actualMinutes == 30, "the fixture's own source store is not what the ledger says")

        let archive = try CadenceDataExportService.makeArchive(in: source)
        let first = try #require(archive.focusSessions.min { $0.loggedAt < $1.loggedAt })
        #expect(first.previousMinutes == 0 && first.minutes == 10)

        let container = try CadenceTestStore.container()
        let destination = ModelContext(container)
        let local = AppTask(title: "Renamed after the backup")
        local.id = task.id
        local.actualMinutes = 10
        let localSession = FocusSessionLog(
            minutes: first.minutes,
            previousMinutes: first.previousMinutes,
            loggedAt: first.loggedAt,
            dayKey: first.dayKey
        )
        localSession.id = first.id
        localSession.task = local
        destination.insert(local)
        destination.insert(localSession)
        try destination.save()

        return (archive, container, task.id)
    }

    /// A store that has drifted from its archive: the same task, renamed and moved out of its list.
    /// Returned with the destination context so both modes can be pointed at the identical setup.
    private static func driftedStore() throws -> (CadenceArchive, ModelContext, AppTask) {
        let source = ModelContext(try CadenceTestStore.container())
        let area = Area(name: "Home")
        let task = AppTask(title: "Buy milk")
        task.area = area
        source.insert(area)
        source.insert(task)
        try source.save()
        let archive = try CadenceDataExportService.makeArchive(in: source)

        let destination = ModelContext(try CadenceTestStore.container())
        let drifted = AppTask(title: "Renamed after the backup")
        drifted.id = task.id
        destination.insert(drifted)
        try destination.save()

        return (archive, destination, drifted)
    }

    /// One row of every entity in `CadenceSchema`, wired into one connected graph.
    ///
    /// One row each rather than many, for the same reason `CadenceDataExportSurfaceTests` seeds
    /// that way: the property under test is that no *table* is dropped, and a table that is dropped
    /// is dropped whether it held one row or a thousand. The wiring is the part that matters here —
    /// every relationship the archive can carry is exercised by at least one of these.
    private static func seedTheWholeSchema(into modelContext: ModelContext) throws {
        let context = Context(name: "Work")
        let area = Area(name: "Home", context: context)
        let project = Project(name: "Kitchen", context: context, area: area)
        let pursuit = Pursuit(title: "Stay healthy", context: context)
        let tag = Tag(name: "errand")
        let goal = Goal(title: "Ship it", context: context)
        goal.pursuit = pursuit
        let bundle = TaskBundle(title: "Morning", dateKey: "2026-02-02", startMin: 540, durationMinutes: 30)

        let task = AppTask(title: "Buy milk")
        task.area = area
        task.project = project
        task.goal = goal
        task.context = context
        task.bundle = bundle
        task.tags = [tag]
        task.notes = "A **markdown** body"

        let subtask = Subtask(title: "Check the fridge")
        subtask.parentTask = task

        let session = FocusSessionLog(minutes: 25, previousMinutes: 0, loggedAt: Date(), dayKey: "2026-02-02")
        session.task = task

        let note = Note(kind: .list, title: "Kitchen notes", content: "# Kitchen")
        note.area = area
        note.tags = [tag]

        let saved = SavedLink(title: "Recipe", url: "https://example.com/recipe")
        saved.project = project

        let asset = MarkdownImageAsset(
            data: Data([0x89, 0x50, 0x4E, 0x47]),
            mimeType: "image/png",
            pixelWidth: 2,
            pixelHeight: 2,
            displayWidth: 520
        )

        let listLink = GoalListLink(goal: goal, area: area)

        let habit = Habit(title: "Stretch", context: context, goal: goal)
        habit.pursuit = pursuit
        let completion = HabitCompletion(date: "2026-02-02", habit: habit)

        let daily = DailyNote(date: "2026-02-03")
        let weekly = WeeklyNote(weekKey: "2026-W06")
        let perm = PermNote()
        let eventNote = EventNote(calendarEventID: "event-1", eventTitle: "Standup")
        let document = Document(title: "Old doc")
        document.area = area

        for model in [context, area, project, pursuit, tag, goal, bundle] as [any PersistentModel] {
            modelContext.insert(model)
        }
        for model in [task, subtask, session, note, saved, asset, listLink, habit, completion] as [any PersistentModel] {
            modelContext.insert(model)
        }
        for model in [daily, weekly, perm, eventNote, document] as [any PersistentModel] {
            modelContext.insert(model)
        }
        try modelContext.save()

        // **The fixture ends migrated, and that is the realistic state rather than a convenience.**
        // Every real device has run `NoteMigrationService` at launch, so a real archive carries the
        // legacy rows *and* the `Note`s they folded into. Seeding an unmigrated store instead would
        // make the import legitimately end with more notes than the archive holds — the fold doing
        // its job — and a "counts equal" assertion would then be asserting the wrong thing.
        // `aPreMigrationArchiveEndsWithItsNotesFoldedIntoTheLiveModel` covers the other state.
        try NoteMigrationService.migrateIfNeeded(in: modelContext, source: "test-fixture")

        // Positive control on the fixture itself: a seed that quietly stopped covering a table
        // would make every "counts equal" assertion below weaker without failing anything.
        let seeded = try CadenceDataExportService.makeArchive(in: modelContext)
        for name in CadenceArchive.recordCountsByEntityName.keys.sorted() {
            #expect((seeded.recordCount(forEntityNamed: name) ?? 0) >= 1, "\(name) was never seeded")
        }
        // The five legacy rows folded into notes beside the one seeded directly.
        #expect(seeded.notes.count == 6)
    }
}
