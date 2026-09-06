import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **T-1093: filing a note into a folder committed nothing at all, on either platform.**
///
/// `CadenceListNoteFiling.move(_:toFolder:)` set `note.folderPath` and stopped — no `save()`, no
/// `try?`, no persistence helper. **Not one half of the `try? save()` rule could see it**, and that
/// is the interesting part: half 1 wants an insert or a delete, half 2 wants a swallowed commit to
/// hang a report on, and half 3 wants a function that inserts or deletes and reaches no commit.
/// This function does none of those things. It writes one field and returns, and the row then
/// visibly changes folder on the strength of whatever unrelated `save()` came next — the autosave
/// cost [[T-327]] measured, with a rearrangement the user can see (T-614) sitting on top of it.
///
/// The fix is a committing door and a non-committing one, named apart:
///
/// - `move(_:toFolder:in:commit:)` throws and commits through
///   `CadencePendingChangePersistence.commitEdit`, restoring the previous path when the store
///   refuses. Its shape is `NoteActionSupport.move(_:toArea:modelContext:commit:)`'s, which is the
///   same sentence about the same model, and `createNote`'s `commit:` parameter in the same enum.
/// - `fileWithoutCommitting(_:toFolder:)` is the archive importer's, and only the importer's. An
///   import restores hundreds of notes and commits **once** for the whole document (T-1086); a
///   per-note `save()` there would be hundreds of commits and a half-written store on the first
///   refusal. `noNoteFolderMoveSkipsTheCommitOutsideTheImporter` pins it to that one caller, which
///   is the whole reason the non-committing spelling is safe to keep at all.
///
/// **Behaviour first, source scans only where nothing else can see.** The helper is a static
/// function a test can call, so the commit and the undo are proved against a real container with a
/// `commit` that throws — a `save()` cannot be provoked into throwing out of an in-memory store,
/// and an undo path no test can reach is an undo path no test can prove. The two `moveNote`
/// helpers are `private func`s on SwiftUI views that nothing can call, so their shape is a scan.
///
/// `@Suite(.preservesTheStoredLaunchReports)` because
/// `animportedArchiveIsFiledThroughTheNonCommittingDoorAndStillLands` runs the real importer, and
/// `CadenceArchiveImportService.apply` finishes by running `NoteMigrationService.migrateIfNeeded`,
/// which writes a launch report the app reads back (T-1083).
@Suite(.preservesTheStoredLaunchReports)
@MainActor
struct CadenceNoteFolderMoveCommitTests {

    private struct CommitRefused: Error {}

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
    }

    private func makeNote(in modelContext: ModelContext, folder: String = "") throws -> Note {
        let project = Project(name: "Launch")
        let note = Note(kind: .list, title: "Spec", content: "# Spec\n\n")
        note.project = project
        note.folderPath = folder
        modelContext.insert(project)
        modelContext.insert(note)
        try modelContext.save()
        return note
    }

    // MARK: - Behavioural: the move itself

    /// The success path, read back through a **second** context so the writing context's own memory
    /// cannot satisfy the assertion — which is exactly the difference the ticket is about, since
    /// the old code passed every in-memory reading of "the note moved" while the store held nothing.
    @Test func acommittedFolderMoveIsInTheStoreRatherThanPendingInTheContext() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let project = Project(name: "Launch")
        let note = Note(kind: .list, title: "Spec", content: "# Spec\n\n")
        note.project = project
        modelContext.insert(project)
        modelContext.insert(note)
        try modelContext.save()

        try CadenceListNoteFiling.move(note, toFolder: " /Planning/ Research/ ", in: modelContext)

        // Normalized on the way in, by the one normalizer.
        #expect(note.folderPath == "Planning/Research")
        // Nothing left pending for some other screen's `save()` to finish or `rollback()` to throw
        // away. This is the assertion that fails against HEAD before the fix.
        #expect(!modelContext.hasChanges)

        let reader = ModelContext(container)
        let stored = try reader.fetch(FetchDescriptor<Note>())
        #expect(stored.count == 1)
        #expect(stored.first?.folderPath == "Planning/Research")
    }

    /// Moving out of every folder is the same call with something that normalizes to the root, and
    /// it commits too — emptying a folder is how a folder is deleted, so this is the destructive
    /// direction of the same control.
    @Test func acommittedMoveToTheRootIsInTheStoreToo() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let project = Project(name: "Launch")
        let note = Note(kind: .list, title: "Spec", content: "# Spec\n\n")
        note.project = project
        note.folderPath = "Planning"
        modelContext.insert(project)
        modelContext.insert(note)
        try modelContext.save()

        try CadenceListNoteFiling.move(note, toFolder: "  /  ", in: modelContext)

        #expect(note.folderPath == CadenceNoteFolderPath.root)
        #expect(!modelContext.hasChanges)
        let reader = ModelContext(container)
        #expect(try reader.fetch(FetchDescriptor<Note>()).first?.folderPath == "")
    }

    /// **A refused commit puts the note back and throws.** The caller is told, and the field holds
    /// what it held — so the column's "Nothing was changed" is true rather than a sentence printed
    /// over a change still sitting in the app's single `ModelContext`.
    ///
    /// The previous path is deliberately **un-normalized**, which is the case the undo can get
    /// wrong: `"/Planning//Research/"` can arrive from a merge, from CloudKit or from a build older
    /// than the convention (see `CadenceNoteFolderSupport.swift`'s header), and an undo written as
    /// `fileWithoutCommitting(note, toFolder: previous)` would silently tidy it to
    /// `"Planning/Research"` while claiming nothing changed.
    @Test func arefusedFolderMovePutsTheRawPreviousPathBackAndThrows() throws {
        let modelContext = try makeContext()
        let note = try makeNote(in: modelContext, folder: "/Planning//Research/")

        #expect(throws: CommitRefused.self) {
            try CadenceListNoteFiling.move(note, toFolder: "Admin", in: modelContext) { _ in
                throw CommitRefused()
            }
        }

        #expect(note.folderPath == "/Planning//Research/")
        // And not the tidied spelling, which is what a re-normalizing undo would leave.
        #expect(note.folderPath != "Planning/Research")
    }

    /// The undo is a field restore, not `modelContext.rollback()`, for the reason
    /// `CadencePendingChangePersistence.commitEdit` documents: one context app-wide, so a refused
    /// filing must not take the note somebody is typing in the pane beside the column with it.
    @Test func arefusedFolderMoveLeavesUnrelatedPendingWorkAlone() throws {
        let modelContext = try makeContext()
        let note = try makeNote(in: modelContext, folder: "Planning")

        let unrelated = Note(kind: .list, title: "Draft", content: "# Draft\n\n")
        modelContext.insert(unrelated)

        #expect(throws: CommitRefused.self) {
            try CadenceListNoteFiling.move(note, toFolder: "Admin", in: modelContext) { _ in
                throw CommitRefused()
            }
        }

        #expect(note.folderPath == "Planning")
        // Still pending rather than discarded — a rollback would have thrown it away.
        #expect(modelContext.hasChanges)
        #expect(!unrelated.isDeleted)
    }

    // MARK: - Behavioural: the importer still commits once

    /// The importer files restored notes through the non-committing door and saves **once**, in
    /// `apply`. Behaviourally this shows the import lands and leaves nothing pending; that it is
    /// one commit rather than many is `theImporterHoldsExactlyOneCommitForTheWholeArchive` below,
    /// because a count of `save()` calls is not something a value can be asked for.
    @Test func animportedArchiveIsFiledThroughTheNonCommittingDoorAndStillLands() throws {
        let source = ModelContext(try CadenceTestStore.container())
        for (index, raw) in ["/Planning//Research/", "Admin", "  /  "].enumerated() {
            let note = Note(kind: .list, title: "Note \(index)", content: "# Note\n\n")
            note.folderPath = raw
            source.insert(note)
        }
        try source.save()

        let archive = try CadenceDataExportService.makeArchive(in: source)
        #expect(archive.notes.count == 3)

        let destinationContainer = try CadenceTestStore.container()
        let destination = ModelContext(destinationContainer)
        try CadenceArchiveImportService.apply(archive, in: destination)

        #expect(!destination.hasChanges, "the import left rows pending")
        let reader = ModelContext(destinationContainer)
        let stored = try reader.fetch(FetchDescriptor<Note>())
        #expect(Set(stored.map(\.folderPath)) == ["Planning/Research", "Admin", ""])
    }

    // MARK: - Source shape: the two columns

    /// **Both columns commit their move and both say when it was refused**, in the same place and
    /// for the same reason: the folder sheet is already dismissed by the time the answer is applied,
    /// and at compact width the context menu is gone too, so the column is the only surface left
    /// standing. A notice written onto the sheet would be a sentence on nothing.
    @Test func bothNoteColumnsCommitTheFolderMoveAndNameARefusedOne() throws {
        for path in [
            "Cadence/macOS/Views/ListNotesView.swift",
            "Cadence/iOS/iOSListNotesView.swift"
        ] {
            let source = try CadenceCommitSurfaceScan.scanned(path)
            let move = try CadenceCommitSurfaceScan.declarationBody(named: "moveNote", in: source)

            #expect(
                move.contains("try CadenceListNoteFiling.move(note, toFolder: folderPath, in: modelContext)"),
                "\(path) does not commit its folder move"
            )
            #expect(
                move.contains("moveFailureNotice = CadencePendingChangePersistence.editFailureNotice"),
                "\(path) swallows a refused folder move"
            )
            // The clear runs only past the `catch`, so a refusal cannot blank its own sentence.
            #expect(
                CadenceCommitSurfaceScan.reportFollowsTheCatch("moveFailureNotice = nil", in: move),
                "\(path) clears the notice above the failure branch"
            )
            // A notice nothing draws is not a report.
            #expect(source.contains("@State private var moveFailureNotice: String?"))
            #expect(source.contains("CadenceInlineFailureNotice(text: moveFailureNotice)"))
            // The undo is the field, never the whole context.
            #expect(CadenceSourceScan.matchCount(#"\.rollback\(\)"#, in: source) == 0)
        }
    }

    /// **The non-committing door has exactly one caller, and it is the importer.**
    ///
    /// This is the assertion that keeps the two spellings honest. `move` committing is worth
    /// nothing if a fifth surface can reach past it to the door that does not, and the old defect
    /// was precisely four surfaces holding a helper that looked like it filed a note and did not.
    /// The count is exact rather than "at least one": a second call site is a second surface that
    /// has quietly re-acquired the bug.
    @Test func noNoteFolderMoveSkipsTheCommitOutsideTheImporter() throws {
        let needle = "CadenceListNoteFiling.fileWithoutCommitting("
        var callSites: [String: Int] = [:]
        for path in try CadenceSourceScan.swiftFiles(under: "Cadence") {
            let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            let count = code.components(separatedBy: needle).count - 1
            guard count > 0 else { continue }
            callSites[path] = count
        }

        #expect(callSites == ["Cadence/Services/CadenceArchiveImportService.swift": 1])

        // Non-vacuity: the declaration is where the sweep says it is, so a needle that matched
        // nothing anywhere cannot pass the exactness above by reading an empty tree.
        let helper = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Shared/CadenceNoteFolderSupport.swift")
        )
        #expect(helper.contains("static func fileWithoutCommitting(_ note: Note, toFolder rawPath: String)"))
    }

    /// The importer holds **one** commit for the whole document, which is the constraint that kept
    /// T-1093 out of T-1071: the fix could not be "make the write commit", because one of its
    /// callers must not.
    @Test func theImporterHoldsExactlyOneCommitForTheWholeArchive() throws {
        let importer = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Services/CadenceArchiveImportService.swift")
        )
        #expect(CadenceSourceScan.matchCount(#"modelContext\.save\(\)"#, in: importer) == 1)
        // And it is the one `apply` rolls back around, not a stray save inside the row loop.
        #expect(importer.contains("try modelContext.save()"))
        #expect(importer.contains("modelContext.rollback()"))
    }
}
