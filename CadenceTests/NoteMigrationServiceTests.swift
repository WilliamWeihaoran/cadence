import Foundation
import SwiftData
import Testing
@testable import Cadence

@Suite(.preservesTheStoredLaunchReports)
@MainActor
struct NoteMigrationServiceTests {
    /// The guard itself, both ways round, on every key it claims to cover: a key that was there
    /// goes back with its original bytes, and a key that was absent goes back to absent rather
    /// than to whatever the body wrote.
    ///
    /// This test runs inside the guard too, so the sentinels it writes are themselves cleaned up.
    @Test func theStoredLaunchReportGuardPutsEveryKeyBackBothWaysRound() throws {
        #expect(
            StoredLaunchReports.keys.count == 2,
            "the key list changed; this test covers whatever is in it, but say so out loud"
        )
        let fabricated = Data("a report a test wrote".utf8)

        for key in StoredLaunchReports.keys {
            let sentinel = Data("a report the app wrote for \(key)".utf8)

            CadenceDefaults.store.set(sentinel, forKey: key)
            withStoredLaunchReportsPreserved {
                CadenceDefaults.store.set(fabricated, forKey: key)
                #expect(
                    CadenceDefaults.store.data(forKey: key) == fabricated,
                    "the guard blocked the body's write to \(key)"
                )
            }
            #expect(
                CadenceDefaults.store.data(forKey: key) == sentinel,
                "a fabricated report outlived the guard on \(key)"
            )

            CadenceDefaults.store.removeObject(forKey: key)
            withStoredLaunchReportsPreserved {
                CadenceDefaults.store.set(fabricated, forKey: key)
            }
            #expect(
                CadenceDefaults.store.data(forKey: key) == nil,
                "the guard invented a stored report on \(key) for an app that had none"
            )
        }
    }

    @Test func migrationCopiesLegacyNotesOnceAndPreservesMetadata() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let area = Area(name: "Area")
        let project = Project(name: "Project")
        let daily = DailyNote(date: "2026-04-29")
        daily.content = "Daily content"
        let weekly = WeeklyNote(weekKey: "2026-W18")
        weekly.content = "Weekly content"
        let permanent = PermNote()
        permanent.content = "Permanent content"
        let document = Document(title: "List note")
        document.content = "List content"
        document.order = 7
        document.project = project
        let eventNote = EventNote(
            calendarEventID: "event-1",
            eventTitle: "Meeting",
            calendarID: "calendar-1",
            eventDateKey: "2026-04-29",
            eventStartMin: 600,
            eventEndMin: 630
        )
        eventNote.content = "Meeting content"

        context.insert(area)
        context.insert(project)
        context.insert(daily)
        context.insert(weekly)
        context.insert(permanent)
        context.insert(document)
        context.insert(eventNote)
        try context.save()

        let firstReport = try NoteMigrationService.migrateIfNeeded(in: context, source: "test-first")
        let secondReport = try NoteMigrationService.migrateIfNeeded(in: context, source: "test-second")

        let notes = try context.fetch(FetchDescriptor<Note>())
        #expect(notes.count == 5)
        #expect(firstReport.success)
        #expect(firstReport.insertedTotal == 5)
        #expect(firstReport.legacyScannedTotal == 5)
        #expect(secondReport.success)
        #expect(secondReport.insertedTotal == 0)
        #expect(secondReport.skippedAlreadyMigrated == 5)
        #expect(notes.first { $0.kind == .daily }?.id == daily.id)
        #expect(notes.first { $0.kind == .daily }?.content == "Daily content")
        #expect(notes.first { $0.kind == .weekly }?.weekKey == "2026-W18")
        #expect(notes.first { $0.kind == .permanent }?.title == "Notepad")
        #expect(notes.first { $0.kind == .list }?.project?.id == project.id)
        #expect(notes.first { $0.kind == .list }?.order == 7)
        let migratedMeeting = notes.first { $0.kind == .meeting }
        #expect(migratedMeeting?.id == eventNote.id)
        #expect(migratedMeeting?.calendarID == "calendar-1")
        #expect(migratedMeeting?.eventStartMin == 600)
    }

    @Test func keyedCoreNoteLookupCreatesAndReusesNotes() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let dailyA = try NoteMigrationService.dailyNote(for: "2026-04-29", in: context)
        let dailyB = try NoteMigrationService.dailyNote(for: "2026-04-29", in: context)
        let weeklyA = try NoteMigrationService.weeklyNote(for: "2026-W18", in: context)
        let weeklyB = try NoteMigrationService.weeklyNote(for: "2026-W18", in: context)
        let permanentA = try NoteMigrationService.permanentNote(in: context)
        let permanentB = try NoteMigrationService.permanentNote(in: context)

        #expect(dailyA.id == dailyB.id)
        #expect(weeklyA.id == weeklyB.id)
        #expect(permanentA.id == permanentB.id)
        #expect(try context.fetch(FetchDescriptor<Note>()).count == 3)
    }

    /// **A refused core-note commit leaves no note behind, and nothing pending** ([[T-1181]]).
    ///
    /// All four accessors used to end a fresh insert with a bare `try context.save()`. The error
    /// reached the caller, but the `Note` stayed pending in the app's single `ModelContext` — for
    /// the next unrelated `save()` from any other screen to commit, or the next `rollback()` to
    /// discard. They route through `CadencePendingChangePersistence.commitInsert` now, which
    /// un-inserts before it rethrows.
    ///
    /// **The `commit:` seam is the fix, not scaffolding** (the T-1295 argument): an in-memory
    /// `save()` cannot be made to throw, so without it there is no way to provoke the refusal and
    /// the undo path is one no test can reach.
    ///
    /// **Toolchain-neutral by construction** ([[T-1296]]): nothing here reads a relationship
    /// between the undo and the assertion. Each case runs the *next* unrelated `save()` forwards
    /// and asks the store, which is the defect the ticket is about and depends on no framework
    /// timing.
    @Test func arefusedCoreNoteInsertUninsertsTheNoteRatherThanLeavingItPending() throws {
        struct CommitRefused: Error {}

        for (label, create) in coreNoteAccessorsUnderTest {
            let container = try CadenceModelContainerFactory.makeInMemoryContainer()
            let context = ModelContext(container)

            #expect(throws: CommitRefused.self) {
                try create(context) { _ in throw CommitRefused() }
            }

            // The assertion: the next unrelated commit takes nothing with it.
            try context.save()
            let notes = try context.fetch(FetchDescriptor<Note>())
            #expect(notes.isEmpty, "\(label) left \(notes.count) note(s) pending after a refused commit")
        }
    }

    /// The other half of the seam: the **default** commit is a real `save()`, not the test's
    /// closure — so the tests above prove something about the code that ships.
    @Test func theDefaultCoreNoteCommitIsARealSaveAndNotTheTestSeam() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        try NoteMigrationService.dailyNote(for: "2026-04-30", in: context)
        try NoteMigrationService.weeklyNote(for: "2026-W19", in: context)
        try NoteMigrationService.permanentNote(in: context)
        try NoteMigrationService.createPermanentNote(in: context, title: "Reading list")

        // Committed by the accessors themselves: a second context over the same store sees them
        // without anything here having saved.
        let reader = ModelContext(container)
        #expect(try reader.fetch(FetchDescriptor<Note>()).count == 4)
    }

    /// The four accessors, each closed over so the refusal test can run one body against all of
    /// them — the alternative is four near-copies of the same six lines.
    private var coreNoteAccessorsUnderTest: [(String, (ModelContext, @escaping (ModelContext) throws -> Void) throws -> Void)] {
        [
            ("dailyNote", { context, commit in
                try NoteMigrationService.dailyNote(for: "2026-04-29", in: context, commit: commit)
            }),
            ("weeklyNote", { context, commit in
                try NoteMigrationService.weeklyNote(for: "2026-W18", in: context, commit: commit)
            }),
            ("permanentNote", { context, commit in
                try NoteMigrationService.permanentNote(in: context, commit: commit)
            }),
            ("createPermanentNote", { context, commit in
                try NoteMigrationService.createPermanentNote(in: context, title: "Reading list", commit: commit)
            }),
        ]
    }

    /// Notepad holds many notes now, but the single-note surfaces (the Today panel's Notepad tab,
    /// iOS, the MCP write service) still go through `permanentNote(in:)` and must keep landing on
    /// the *same* note every time. An unordered `first` would hand them a different one run to run
    /// once more than one exists.
    @Test func permanentNoteKeepsReturningTheOldestNotepadNote() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        // The note an upgrading user already had.
        let original = try NoteMigrationService.permanentNote(in: context)
        original.content = "Everything I already wrote down"
        try context.save()

        let second = try NoteMigrationService.createPermanentNote(in: context)
        let third = try NoteMigrationService.createPermanentNote(in: context, title: "Reading list")

        #expect(try NoteMigrationService.permanentNote(in: context).id == original.id)
        #expect(try NoteMigrationService.permanentNotes(in: context).map(\.id) == [original.id, second.id, third.id])
        #expect(try NoteMigrationService.permanentNotes(in: context).first?.content == "Everything I already wrote down")
    }

    /// A new notepad note is seeded with its title as an H1, because that heading is the rename
    /// control — `NoteEditorPane` syncs it back to `note.title` for `.permanent` the same way it
    /// always has for `.list`.
    @Test func createPermanentNoteSeedsItsTitleHeading() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let note = try NoteMigrationService.createPermanentNote(in: context, title: "Reading list")

        #expect(note.kind == .permanent)
        #expect(note.title == "Reading list")
        #expect(note.content == "# Reading list\n\n")
    }

    /// The legacy `PermNote` is a singleton, so its migration guard must survive Notepad becoming
    /// plural: the user's one legacy note lands once, appears first, and is not duplicated by the
    /// notes they made afterwards. And a store full of notepad notes is not a store full of
    /// canonical duplicates.
    @Test func legacyPermanentNoteMigratesOnceAlongsideNewNotepadNotes() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let legacy = PermNote()
        legacy.content = "Legacy notepad content"
        context.insert(legacy)
        try context.save()

        try NoteMigrationService.migrateIfNeeded(in: context, source: "test-first")
        try NoteMigrationService.createPermanentNote(in: context)
        try NoteMigrationService.createPermanentNote(in: context)
        let report = try NoteMigrationService.migrateIfNeeded(in: context, source: "test-second")

        let notepadNotes = try NoteMigrationService.permanentNotes(in: context)
        #expect(notepadNotes.count == 3)
        #expect(notepadNotes.first?.id == legacy.id)
        #expect(notepadNotes.first?.content == "Legacy notepad content")
        #expect(report.insertedPermanent == 0)
        #expect(report.canonicalDuplicateCount == 0)
        #expect(try NoteMigrationService.healthCheck(in: context).canonicalDuplicateCount == 0)
    }

    @Test func migrationSkipsCanonicalDuplicateWithoutCreatingSecondCoreNote() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let existing = Note(kind: .daily, title: "2026-04-29", content: "Existing", dateKey: "2026-04-29")
        let legacy = DailyNote(date: "2026-04-29")
        legacy.content = "Legacy"

        context.insert(existing)
        context.insert(legacy)
        try context.save()

        let report = try NoteMigrationService.migrateIfNeeded(in: context, source: "canonical-duplicate-test")
        let notes = try context.fetch(FetchDescriptor<Note>())

        #expect(notes.count == 1)
        #expect(notes.first?.id == existing.id)
        #expect(notes.first?.content == "Existing")
        #expect(report.insertedTotal == 0)
        #expect(report.skippedCanonicalDuplicate == 1)
    }

    /// **The duplicate diagnostic is a measurement of the pass that took it ([[T-1341]]).**
    ///
    /// It used to be taken on every launch, from a full `Note` fetch this migration performed
    /// whether or not it had anything to migrate — 0.0245s / 0.0481s / 0.0939s at 1k / 2k / 4k
    /// notes, linear, forever, on a store that has held no legacy row since whichever launch first
    /// migrated them. A pass that skips now says so through `noteTableScanned` rather than
    /// reporting the `Int`'s default as a count, and `healthCheck` is the scan that answers the
    /// same question on demand, off the launch path.
    @Test func migrationReportDetectsExistingCanonicalNoteDuplicatesWhenItScansAtAll() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        context.insert(Note(kind: .meeting, title: "A", calendarEventID: "event-1"))
        context.insert(Note(kind: .meeting, title: "B", calendarEventID: "event-1"))
        try context.save()

        // No legacy row: the pass has provably nothing to do, so it does not read the note table
        // and does not pretend to have counted it.
        let skipped = try NoteMigrationService.migrateIfNeeded(in: context, source: "duplicate-skip-test")
        #expect(skipped.success)
        #expect(skipped.noteTableScanned == false)
        #expect(skipped.canonicalDuplicateCount == 0)
        // The duplicate is still there, and the pass that does scan still finds it.
        #expect(try NoteMigrationService.healthCheck(in: context).canonicalDuplicateCount == 1)

        context.insert(EventNote(
            calendarEventID: "event-2",
            eventTitle: "Meeting",
            calendarID: "calendar-1",
            eventDateKey: "2026-04-29",
            eventStartMin: 600,
            eventEndMin: 630
        ))
        try context.save()

        let report = try NoteMigrationService.migrateIfNeeded(in: context, source: "duplicate-diagnostic-test")

        #expect(report.noteTableScanned)
        #expect(report.insertedTotal == 1)
        #expect(report.canonicalDuplicateCount == 1)
        #expect(NoteMigrationService.lastReport()?.source == "duplicate-diagnostic-test")
        #expect(NoteMigrationService.lastReport()?.canonicalDuplicateCount == 1)
        #expect(NoteMigrationService.lastReport()?.noteTableScanned == true)
    }

    // MARK: - The legacy-row probe ([[T-1341]])
    //
    // `migrate` opened with a fetch of every `Note` and then fetched all five legacy tables in
    // full, on every launch, permanently. The five `fetchLimit = 1` probes decide first: with
    // every legacy table empty the five loops below them have nothing to iterate, `inserted`
    // stays false and nothing is saved, so the only thing the full pass could still produce is
    // the two report fields — and `noteTableScanned` is what keeps those honest.

    /// The common store — every legacy row migrated long ago, or never present — does no store-
    /// wide read at all, and says which figures it therefore did not measure.
    @Test func aStoreWithNoLegacyRowsIsNotReadEndToEndOnEveryLaunch() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        for index in 0..<8 {
            context.insert(Note(kind: .list, title: "Note \(index)"))
        }
        try context.save()

        let report = try NoteMigrationService.migrateIfNeeded(in: context, source: "probe-test")

        #expect(report.success)
        #expect(report.noteTableScanned == false)
        #expect(report.insertedTotal == 0)
        #expect(report.legacyScannedTotal == 0)
        #expect(report.existingNoteCount == 0, "the note table was not read, so this is a placeholder")
        #expect(report.canonicalDuplicateCount == 0)
        // The skip changed nothing about the store it skipped.
        #expect(try context.fetch(FetchDescriptor<Note>()).count == 8)
    }

    /// **All five tables are probed, and each one on its own is enough to bring the full pass
    /// back.** A probe that dropped a table would leave that table's rows unmigrated forever on
    /// any store where the other four are empty, which is every store that ever migrated.
    @Test func everyLegacyTableOnItsOwnBringsTheFullPassBack() throws {
        let seeds: [(String, (ModelContext) -> Void)] = [
            ("DailyNote", { $0.insert(DailyNote(date: "2026-04-29")) }),
            ("WeeklyNote", { $0.insert(WeeklyNote(weekKey: "2026-W18")) }),
            ("PermNote", { $0.insert(PermNote()) }),
            ("Document", { $0.insert(Document(title: "List note")) }),
            ("EventNote", { $0.insert(EventNote(
                calendarEventID: "event-1",
                eventTitle: "Meeting",
                calendarID: "calendar-1",
                eventDateKey: "2026-04-29",
                eventStartMin: 600,
                eventEndMin: 630
            )) })
        ]
        #expect(seeds.count == 5, "the legacy table list changed; this test covers whatever is in it")

        for (name, seed) in seeds {
            let container = try CadenceModelContainerFactory.makeInMemoryContainer()
            let context = ModelContext(container)
            seed(context)
            try context.save()

            let report = try NoteMigrationService.migrateIfNeeded(in: context, source: "probe-\(name)")

            #expect(report.noteTableScanned, "\(name) rows no longer wake the migration")
            #expect(report.legacyScannedTotal == 1, "\(name) was not scanned")
            #expect(report.insertedTotal == 1, "\(name) was not migrated")
        }
    }

    /// **The late-arrival case, which is the whole reason nothing may be latched ([[T-528]]).**
    ///
    /// A half-synced store answers "no legacy rows" correctly for the moment it is asked. The rows
    /// that arrive from CloudKit afterwards land in a store the next launch probes again from
    /// scratch — there is no completion flag to consult, and a skipped pass writes nothing that
    /// could make the next one skip. A "probe once, skip forever" guard would turn this migration
    /// into a permanent no-op for exactly those rows.
    @Test func legacyRowsArrivingAfterASkippedPassAreStillMigrated() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        context.insert(Note(kind: .list, title: "Made on this device"))
        try context.save()

        let skipped = try NoteMigrationService.migrateIfNeeded(in: context, source: "half-synced-launch")
        #expect(skipped.noteTableScanned == false)
        #expect(skipped.insertedTotal == 0)

        // The rest of the sync arrives.
        let arrived = DailyNote(date: "2026-04-29")
        arrived.content = "Written on the Mac"
        context.insert(arrived)
        try context.save()

        let next = try NoteMigrationService.migrateIfNeeded(in: context, source: "next-launch")
        #expect(next.noteTableScanned)
        #expect(next.insertedDaily == 1)
        let migrated = try #require(
            try context.fetch(FetchDescriptor<Note>()).first { $0.kind == .daily }
        )
        #expect(migrated.id == arrived.id)
        #expect(migrated.content == "Written on the Mac")

        // And a third launch, with the legacy row still present, skips it rather than copying it
        // again — the probe is a fast path, never a substitute for the guard below it.
        let third = try NoteMigrationService.migrateIfNeeded(in: context, source: "third-launch")
        #expect(third.noteTableScanned)
        #expect(third.insertedTotal == 0)
        #expect(third.skippedAlreadyMigrated == 1)
    }

    /// A report written before `noteTableScanned` existed came from a pass that did scan, so it has
    /// to decode as `true` — `false` would retroactively brand every stored report a placeholder.
    @Test func aStoredReportWithoutTheScannedFlagReadsAsScanned() throws {
        let legacy = """
        {
          "source": "app-startup",
          "startedAt": 1000,
          "finishedAt": 1001,
          "success": true,
          "existingNoteCount": 12,
          "canonicalDuplicateCount": 3
        }
        """

        let report = try JSONDecoder().decode(NoteMigrationReport.self, from: Data(legacy.utf8))

        #expect(report.noteTableScanned)
        #expect(report.existingNoteCount == 12)
        #expect(report.canonicalDuplicateCount == 3)
    }

    @Test func healthCheckReportsLegacyGapsAndBadRelationships() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let area = Area(name: "Area")
        let project = Project(name: "Project")
        let orphanedListNote = Note(kind: .list, title: "Orphan")
        let doubleOwnedListNote = Note(kind: .list, title: "Double owned", area: area, project: project)
        let firstDaily = Note(kind: .daily, title: "Daily A", dateKey: "2026-04-29")
        let secondDaily = Note(kind: .daily, title: "Daily B", dateKey: "2026-04-29")
        let missingEventID = Note(kind: .meeting, title: "Meeting", calendarID: "calendar-1")
        let missingCalendarID = Note(kind: .meeting, title: "Meeting", calendarEventID: "event-1")
        let unmigratedLegacy = WeeklyNote(weekKey: "2026-W18")

        context.insert(area)
        context.insert(project)
        context.insert(orphanedListNote)
        context.insert(doubleOwnedListNote)
        context.insert(firstDaily)
        context.insert(secondDaily)
        context.insert(missingEventID)
        context.insert(missingCalendarID)
        context.insert(unmigratedLegacy)
        try context.save()

        let health = try NoteMigrationService.healthCheck(in: context)

        #expect(health.canonicalDuplicateCount == 1)
        #expect(health.legacyWithoutCanonicalCount == 1)
        #expect(health.orphanedListNoteCount == 1)
        #expect(health.listNoteWithMultipleOwnersCount == 1)
        #expect(health.meetingNoteMissingEventIDCount == 1)
        #expect(health.meetingNoteMissingCalendarIDCount == 1)
        // Six defects counted, six defects summed. See
        // `issueCountCountsEveryDefectTheHealthReportItselfCounts` for why the sum has to include
        // the last one.
        #expect(health.issueCount == 6)
    }

    // MARK: - Deferred-save / partial-failure safety
    //
    // `PersistenceController.performStartupMaintenance` deliberately calls
    // `NoteMigrationService.migrateIfNeeded(..., saveChanges: false)` and only issues a single
    // `context.save()` afterward (batched together with tag seeding and integrity repair). These
    // tests lock in the resulting crash-safety contract: if the process dies before that final save,
    // no partially-migrated `Note` data should have leaked into the persistent store, the legacy
    // records must still be intact for a retry, and a subsequent migration attempt must converge to
    // exactly one `Note` per legacy record with no duplicates.
    @Test func deferredSaveMigrationLeavesNoPartialStateIfNeverSaved() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let writerContext = ModelContext(container)
        let daily = DailyNote(date: "2026-05-01")
        daily.content = "Daily content"
        let weekly = WeeklyNote(weekKey: "2026-W19")
        let permanent = PermNote()
        let document = Document(title: "List note")
        let eventNote = EventNote(calendarEventID: "event-9", eventTitle: "Standup")
        writerContext.insert(daily)
        writerContext.insert(weekly)
        writerContext.insert(permanent)
        writerContext.insert(document)
        writerContext.insert(eventNote)
        try writerContext.save()

        // Simulate an app-startup migration pass that never reaches the final save (e.g. the
        // process is killed immediately after this call, before `context.save()` runs).
        let deferredReport = try NoteMigrationService.migrateIfNeeded(
            in: writerContext,
            source: "startup-sim-crash",
            saveChanges: false
        )
        #expect(deferredReport.insertedTotal == 5)

        // A brand-new context against the same underlying store models the next launch after the
        // crash: it must see none of the unsaved `Note` inserts, and all legacy records must still
        // be present so the next migration attempt can retry cleanly.
        let relaunchContext = ModelContext(container)
        #expect(try relaunchContext.fetch(FetchDescriptor<Note>()).isEmpty)
        #expect(try relaunchContext.fetch(FetchDescriptor<DailyNote>()).count == 1)
        #expect(try relaunchContext.fetch(FetchDescriptor<WeeklyNote>()).count == 1)
        #expect(try relaunchContext.fetch(FetchDescriptor<PermNote>()).count == 1)
        #expect(try relaunchContext.fetch(FetchDescriptor<Document>()).count == 1)
        #expect(try relaunchContext.fetch(FetchDescriptor<EventNote>()).count == 1)

        // The retried migration (this time saved, as a real relaunch would do) must fully recover
        // with no duplicates and no data loss.
        let retryReport = try NoteMigrationService.migrateIfNeeded(in: relaunchContext, source: "startup-sim-retry")
        #expect(retryReport.insertedTotal == 5)
        #expect(retryReport.skippedAlreadyMigrated == 0)

        let verifyContext = ModelContext(container)
        let notes = try verifyContext.fetch(FetchDescriptor<Note>())
        #expect(notes.count == 5)
        #expect(notes.first { $0.kind == .daily }?.content == "Daily content")
    }

    @Test func repeatedDeferredSaveCallsBeforeAnyCommitDoNotDuplicatePendingNotes() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let daily = DailyNote(date: "2026-05-02")
        let weekly = WeeklyNote(weekKey: "2026-W20")
        context.insert(daily)
        context.insert(weekly)
        try context.save()

        // Mirrors `PersistenceController.performStartupMaintenance`, which can invoke multiple
        // maintenance passes against the same context with `saveChanges: false` before a single
        // trailing `context.save()`. Calling the migration step twice back-to-back without an
        // intervening save must not create duplicate pending `Note` inserts.
        let firstPass = try NoteMigrationService.migrateIfNeeded(in: context, source: "pass-1", saveChanges: false)
        let secondPass = try NoteMigrationService.migrateIfNeeded(in: context, source: "pass-2", saveChanges: false)
        #expect(firstPass.insertedTotal == 2)
        #expect(secondPass.insertedTotal == 0)
        #expect(secondPass.skippedAlreadyMigrated == 2)

        #expect(try context.fetch(FetchDescriptor<Note>()).count == 2)

        try context.save()

        let verifyContext = ModelContext(container)
        #expect(try verifyContext.fetch(FetchDescriptor<Note>()).count == 2)
    }

    // MARK: - Canonical key agreement
    //
    // The migration and the repair pass both ask "are these the same note", and they used to ask
    // two different functions. `NoteMigrationService` keyed every dateless daily note as `"daily:"`
    // and never trimmed; `DataIntegrityRepairService` gave each one a per-UUID key and trimmed
    // both sides. Nothing tested them together, so the store could be walked twice and reach
    // opposite conclusions: health check calls the notes duplicates, repair refuses to merge them.

    /// Notes with no date key have no shared identity to collide on. Two dateless daily notes are
    /// two notes — the health check must not call them duplicates, and the repair pass must not
    /// merge them. Before consolidation the first half of this failed.
    @Test func datelessNotesAreDistinctToBothTheHealthCheckAndTheRepairPass() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let first = Note(kind: .daily, title: "Scratch A", content: "One")
        let second = Note(kind: .daily, title: "Scratch B", content: "Two")
        let firstWeekly = Note(kind: .weekly, title: "Week A", content: "Three")
        let secondWeekly = Note(kind: .weekly, title: "Week B", content: "Four")

        context.insert(first)
        context.insert(second)
        context.insert(firstWeekly)
        context.insert(secondWeekly)
        try context.save()

        #expect(try NoteMigrationService.healthCheck(in: context).canonicalDuplicateCount == 0)

        let report = try DataIntegrityRepairService.repairIfNeeded(in: context, source: "test")
        #expect(report.duplicateNotesMerged == 0)
        #expect(try context.fetch(FetchDescriptor<Note>()).count == 4)
    }

    /// A key that differs only by surrounding whitespace is the same key. The migration copy did
    /// not trim, so `"daily: 2026-04-29"` and `"daily:2026-04-29"` were different notes to it and
    /// the same note to the repair pass.
    @Test func whitespacePaddedKeysAreTheSameKeyToEveryPass() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let clean = Note(kind: .daily, title: "Clean", content: "One", dateKey: "2026-04-29")
        let padded = Note(kind: .daily, title: "Padded", content: "Two", dateKey: " 2026-04-29 ")

        context.insert(clean)
        context.insert(padded)
        try context.save()

        #expect(clean.canonicalKey == padded.canonicalKey)
        #expect(try NoteMigrationService.healthCheck(in: context).canonicalDuplicateCount == 1)

        let report = try DataIntegrityRepairService.repairIfNeeded(in: context, source: "test")
        #expect(report.duplicateNotesMerged == 1)
        #expect(try context.fetch(FetchDescriptor<Note>()).count == 1)
    }

    /// A legacy event note with no calendar event ID was keyed `"event_note:<uuid>"` by the
    /// migration but reported `"meeting-note:<uuid>"` by the note it produced, so the health check
    /// went on reporting it as unmigrated forever after it had in fact been migrated.
    @Test func migratedEventNotesWithoutACalendarIDStopReadingAsUnmigrated() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let legacy = EventNote(calendarEventID: "", eventTitle: "Standup", calendarID: "calendar-1")
        legacy.content = "Notes"
        context.insert(legacy)
        try context.save()

        _ = try NoteMigrationService.migrateIfNeeded(in: context, source: "test")

        let notes = try context.fetch(FetchDescriptor<Note>())
        #expect(notes.count == 1)
        #expect(try NoteMigrationService.healthCheck(in: context).legacyWithoutCanonicalCount == 0)
    }

    /// The migration and the repair pass have to agree about what makes two notes the same note,
    /// because they run one after the other over the same rows on every launch. They did not:
    /// the migration keyed *every* dateless daily note as `"daily:"` — so the second one was
    /// skipped as "already migrated" and its content was lost — while the repair pass gave each
    /// one a per-UUID key and refused to merge them. Neither side's own tests could see it;
    /// running both is what makes the disagreement observable.
    @Test func datelessLegacyNotesSurviveAMigrationFollowedByARepairWithoutMerging() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let firstDaily = DailyNote(date: "")
        firstDaily.content = "First orphan"
        let secondDaily = DailyNote(date: "")
        secondDaily.content = "Second orphan"
        let firstWeekly = WeeklyNote(weekKey: "")
        firstWeekly.content = "First weekly orphan"
        let secondWeekly = WeeklyNote(weekKey: "")
        secondWeekly.content = "Second weekly orphan"
        context.insert(firstDaily)
        context.insert(secondDaily)
        context.insert(firstWeekly)
        context.insert(secondWeekly)
        try context.save()

        let migration = try NoteMigrationService.migrateIfNeeded(in: context, source: "test")
        #expect(migration.insertedTotal == 4)
        #expect(try context.fetch(FetchDescriptor<Note>()).count == 4)

        // The migration must not have invented duplicates for the repair pass to find...
        #expect(try NoteMigrationService.healthCheck(in: context).canonicalDuplicateCount == 0)

        // ...and the repair pass must not merge notes the migration deliberately kept apart.
        let repair = try DataIntegrityRepairService.repairIfNeeded(in: context, source: "test")
        #expect(repair.duplicateNotesMerged == 0)

        let contents = Set(try context.fetch(FetchDescriptor<Note>()).map(\.content))
        #expect(contents == ["First orphan", "Second orphan", "First weekly orphan", "Second weekly orphan"])

        // Running the whole sequence again is a no-op, which is what "on every launch" requires.
        _ = try NoteMigrationService.migrateIfNeeded(in: context, source: "test-again")
        _ = try DataIntegrityRepairService.repairIfNeeded(in: context, source: "test-again")
        #expect(try context.fetch(FetchDescriptor<Note>()).count == 4)
    }

    /// `issueCount` is the single number `CadenceReadService` reports, and it used to omit
    /// `meetingNoteMissingCalendarIDCount` — so a store whose *only* defect was event notes that
    /// had lost their calendar ID read as healthy. The existing side-by-side assertions blessed
    /// the gap by asserting both figures without ever asserting they agreed.
    @Test func issueCountCountsEveryDefectTheHealthReportItselfCounts() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let missingCalendarID = Note(kind: .meeting, title: "Meeting", calendarEventID: "event-1")
        context.insert(missingCalendarID)
        try context.save()

        let health = try NoteMigrationService.healthCheck(in: context)

        #expect(health.meetingNoteMissingCalendarIDCount == 1)
        #expect(health.issueCount == 1)

        // A store with nothing wrong still reports zero, so the sum is not just "some notes".
        let cleanContainer = try CadenceModelContainerFactory.makeInMemoryContainer()
        let cleanContext = ModelContext(cleanContainer)
        cleanContext.insert(Note(kind: .meeting, title: "Meeting", calendarEventID: "event-1", calendarID: "calendar-1"))
        try cleanContext.save()
        #expect(try NoteMigrationService.healthCheck(in: cleanContext).issueCount == 0)
    }

    /// `migrateAndRecordFailure` is the app's actual startup entry point — `CadenceApp` calls it,
    /// not `migrateIfNeeded` — and it had no test at all. It has to return the same report on the
    /// happy path and, on a throw, hand back the last recorded report rather than propagating.
    @Test func migrateAndRecordFailureReturnsTheReportAndRecordsIt() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let legacy = DailyNote(date: "2026-04-29")
        legacy.content = "Daily content"
        context.insert(legacy)
        try context.save()

        let report = try #require(NoteMigrationService.migrateAndRecordFailure(in: context, source: "startup-test"))

        #expect(report.success)
        #expect(report.source == "startup-test")
        #expect(report.insertedTotal == 1)
        #expect(try context.fetch(FetchDescriptor<Note>()).count == 1)

        // The report it returned is the one it persisted, which is what the `catch` path falls
        // back to reading.
        let recorded = try #require(NoteMigrationService.lastReport())
        #expect(recorded == report)

        // Second pass: still non-nil, still successful, and inserts nothing.
        let second = try #require(NoteMigrationService.migrateAndRecordFailure(in: context, source: "startup-test-2"))
        #expect(second.success)
        #expect(second.insertedTotal == 0)
        #expect(second.skippedAlreadyMigrated == 1)
        #expect(try context.fetch(FetchDescriptor<Note>()).count == 1)
    }

    /// **T-466: the same synthesized-`Codable` defect T-445 fixed in `DataIntegrityRepairReport`.**
    /// Every counter above carries an `= 0` default, which reads as "an older blob missing this key
    /// still decodes" and is not what `Codable` synthesis does — the generated `init(from:)` calls
    /// `decode(Int.self, forKey:)` and throws `keyNotFound`. `lastReport()` swallows that with
    /// `try?`, so the whole stored history reads as `nil` the day a counter is added.
    ///
    /// This is the guard that does not need editing when a fifteenth counter lands: it encodes a
    /// live report and removes each key in turn, so the counter list is re-derived from the struct
    /// rather than restated here.
    ///
    /// The four head fields are the deliberate exception: they carry no defaults, they have been
    /// written by every version of this key, and a blob missing `success` is not an older report.
    @Test func aStoredNoteMigrationReportSurvivesEveryCounterThisStructWillEverGain() throws {
        var report = NoteMigrationReport(
            source: "app-startup",
            startedAt: Date(timeIntervalSince1970: 1_000),
            finishedAt: Date(timeIntervalSince1970: 1_001),
            success: true
        )
        report.existingNoteCount = 1
        report.legacyEventNoteScanned = 1
        report.insertedMeeting = 1
        report.skippedCanonicalDuplicate = 1

        let encoded = try JSONEncoder().encode(report)
        let object = try #require(
            try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        let required: Set<String> = ["source", "startedAt", "finishedAt", "success"]
        let optionalKeys = object.keys.filter { !required.contains($0) }

        // Non-vacuity: the loop below is worthless if the encode produced a handful of keys.
        #expect(optionalKeys.count >= 14, "expected every counter in the encoded report, got \(optionalKeys.count)")
        #expect(optionalKeys.contains("insertedMeeting"))
        #expect(optionalKeys.contains("skippedCanonicalDuplicate"))
        #expect(optionalKeys.contains("legacyEventNoteScanned"))

        for key in optionalKeys {
            var trimmed = object
            trimmed.removeValue(forKey: key)
            let data = try JSONSerialization.data(withJSONObject: trimmed)
            #expect(
                (try? JSONDecoder().decode(NoteMigrationReport.self, from: data)) != nil,
                "NoteMigrationReport stops decoding when \(key) is missing, so every report stored before that key existed is lost"
            )
        }
    }

    /// The counters that *were* written still read back as themselves. Without this, a fix that
    /// defaulted the whole struct on any missing key would pass the loop above while throwing the
    /// stored numbers away.
    @Test func aNoteMigrationReportMissingOneCounterKeepsTheOthers() throws {
        let legacy = """
        {
          "source": "app-startup",
          "startedAt": 1000,
          "finishedAt": 1001,
          "success": true,
          "existingNoteCount": 2,
          "legacyDailyScanned": 5,
          "insertedDaily": 3,
          "skippedAlreadyMigrated": 4
        }
        """

        let report = try JSONDecoder().decode(
            NoteMigrationReport.self,
            from: Data(legacy.utf8)
        )

        #expect(report.source == "app-startup")
        #expect(report.success)
        #expect(report.errorMessage == nil)
        // The counters that were written are read back, not defaulted along with the missing ones.
        #expect(report.existingNoteCount == 2)
        #expect(report.legacyDailyScanned == 5)
        #expect(report.insertedDaily == 3)
        #expect(report.skippedAlreadyMigrated == 4)
        // The keys that did not exist yet read as their defaults rather than as a decoding failure.
        #expect(report.insertedMeeting == 0)
        #expect(report.skippedCanonicalDuplicate == 0)
        #expect(report.insertedTotal == 3)
        #expect(report.legacyScannedTotal == 5)
    }

    /// The other half of the same failure: `lastReport()` is the reader that swallows it, and it is
    /// the value `migrateAndRecordFailure` falls back to on a throw. Asserted through the real
    /// `UserDefaults` key so the archive round trip — encoder, key, decoder — is what is measured.
    ///
    /// The save-and-restore this test used to carry itself is now
    /// `.preservesTheStoredLaunchReports` on the suite: it was never only this test that
    /// wrote the key (T-480).
    @Test func noteMigrationLastReportReadsBackAReportStoredWithoutTheNewestCounter() throws {
        let key = "noteMigration.lastReport.v1"

        var report = NoteMigrationReport(
            source: "previous-launch",
            startedAt: Date(timeIntervalSince1970: 2_000),
            finishedAt: Date(timeIntervalSince1970: 2_002),
            success: false
        )
        report.errorMessage = "store unavailable"
        report.insertedDaily = 4
        var object = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as? [String: Any]
        )
        object.removeValue(forKey: "skippedCanonicalDuplicate")
        CadenceDefaults.store.set(try JSONSerialization.data(withJSONObject: object), forKey: key)

        let read = try #require(NoteMigrationService.lastReport())
        #expect(read.source == "previous-launch")
        #expect(read.errorMessage == "store unavailable")
        #expect(read.insertedDaily == 4)
        #expect(read.skippedCanonicalDuplicate == 0)
    }
}
