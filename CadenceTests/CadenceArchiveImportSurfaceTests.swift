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
/// noting that `StoredLaunchReportSuiteRule` would *not* have caught this suite: it looks for the
/// literal `migrateIfNeeded(` in a suite's own body, and here the call is one frame down.
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

    // MARK: - Helpers

    private static func one<Model: PersistentModel>(
        _ type: Model.Type,
        in modelContext: ModelContext
    ) throws -> Model? {
        try modelContext.fetch(FetchDescriptor<Model>()).first
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
