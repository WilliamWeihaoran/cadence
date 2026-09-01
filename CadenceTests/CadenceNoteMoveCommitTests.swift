import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **T-630: macOS Move Note closed the picker before the move, and swallowed the failure.**
///
/// `NoteActionSupport.move(_:toArea:modelContext:)` and its `toProject:` sibling repointed the note
/// and ran `try? modelContext?.save()`. One frame up, the three destination rows in
/// `NoteActionMenu` called `dismissPicker()` **first** and then moved — so the popover closing was
/// the only success signal the user ever got, and it closed whether or not the store took the move.
/// A refused commit left the note repointed in the app's single `ModelContext`, for the next
/// unrelated `save()` to finish or the next `rollback()` to discard, with the picker already gone.
///
/// The rule (`AGENTS.md`, "The `try? save()` rule") calls that half 2, **report**, and the detector
/// missed it for three independent reasons the rule has since grown to cover: the rows live in
/// non-`body` computed vars, the dismissal precedes the call, and `dismissPicker()` was outside the
/// success-report vocabulary. `CadenceSaveCommitDisciplineTests`' `indirectReportExemptions` held
/// the entry; fixing it deletes the entry.
///
/// **Two halves.** `NoteActionSupport.move` is a static helper a test can call, so the undo is
/// pinned behaviourally against a real container with a `commit` that throws — a `save()` that
/// throws cannot be provoked out of an in-memory container, and an undo path no test can reach is
/// an undo path no test can prove. The rows are `private var`s on a SwiftUI view that nothing can
/// call, so their ordering is a source scan.
@MainActor
struct CadenceNoteMoveCommitTests {

    private struct CommitRefused: Error {}

    private func container() throws -> ModelContainer {
        try CadenceModelContainerFactory.makeInMemoryContainer()
    }

    private static let path = "Cadence/macOS/Views/AIActionsSupportViews.swift"

    // MARK: - Behavioural: the move itself

    /// The success path: the note is filed under the area **in the store**, read back through a
    /// second context so the creating context's own memory cannot satisfy the assertion, and
    /// nothing is left pending for some other screen's save to commit later.
    @Test func acommittedNoteMoveIsInTheStoreBeforeThePickerCouldClose() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let area = Area(name: "Work")
        let note = Note(kind: .list, title: "Retro")
        modelContext.insert(area)
        modelContext.insert(note)
        try modelContext.save()

        try NoteActionSupport.move(note, toArea: area, modelContext: modelContext)

        #expect(!modelContext.hasChanges)
        let reader = ModelContext(modelContainer)
        let stored = try reader.fetch(FetchDescriptor<Note>())
        #expect(stored.count == 1)
        #expect(stored.first?.area?.name == "Work")
        #expect(stored.first?.project == nil)
    }

    /// A refused commit puts the note back where it was — area, project **and** `updatedAt` — and
    /// throws, so the row above has something to report instead of a popover that closed anyway.
    ///
    /// The undo is a field snapshot rather than `rollback()`, for the reason
    /// `CadencePendingChangePersistence.commitEdit` documents: one `ModelContext` app-wide, so a
    /// refused move must not take the note somebody is typing behind the popover with it.
    @Test func arefusedNoteMoveRestoresTheNotesOriginalFiling() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let home = Project(name: "Home")
        let work = Area(name: "Work")
        let note = Note(kind: .list, title: "Retro")
        modelContext.insert(home)
        modelContext.insert(work)
        modelContext.insert(note)
        note.project = home
        try modelContext.save()
        let filedAt = note.updatedAt

        #expect(throws: CommitRefused.self) {
            try NoteActionSupport.move(note, toArea: work, modelContext: modelContext) { _ in
                throw CommitRefused()
            }
        }

        #expect(note.area == nil)
        #expect(note.project?.name == "Home")
        #expect(note.updatedAt == filedAt, "the undo left a timestamp the store never took")
    }

    /// The `toProject:` sibling, and the "No List" row's own spelling — `toArea: nil` — which is
    /// the one move that clears both ends. Both undo the same way.
    @Test func arefusedMoveToAProjectAndArefusedMoveToNoListBothUndo() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let work = Area(name: "Work")
        let launch = Project(name: "Launch")
        let note = Note(kind: .list, title: "Retro")
        modelContext.insert(work)
        modelContext.insert(launch)
        modelContext.insert(note)
        note.area = work
        try modelContext.save()

        #expect(throws: CommitRefused.self) {
            try NoteActionSupport.move(note, toProject: launch, modelContext: modelContext) { _ in
                throw CommitRefused()
            }
        }
        #expect(note.area?.name == "Work")
        #expect(note.project == nil)

        #expect(throws: CommitRefused.self) {
            try NoteActionSupport.move(note, toArea: nil, modelContext: modelContext) { _ in
                throw CommitRefused()
            }
        }
        #expect(note.area?.name == "Work", "the No List row's refusal unfiled the note anyway")
        #expect(note.project == nil)
    }

    // MARK: - Source shape: the helper

    /// Neither `move` swallows anything any more, and both commit through the shared unit rather
    /// than a second spelling of it.
    ///
    /// The context is non-optional now. It was `ModelContext?`, which is the shape half 3 of the
    /// rule exempts — "handed a context" — while the body did the thing half 2 forbids; both call
    /// sites already pass a non-optional `@Environment` context, so the optionality only ever
    /// bought a silent no-op.
    @Test func neitherNoteMoveHelperSwallowsItsCommit() throws {
        let source = try CadenceCommitSurfaceScan.scanned(Self.path)

        #expect(CadenceSourceScan.matchCount(#"try\?\s*modelContext"#, in: source) == 0)
        #expect(
            CadenceSourceScan.matchCount(
                #"CadencePendingChangePersistence\.commitEdit\(in: modelContext, commit: commit\)"#,
                in: source
            ) == 2,
            "both move helpers commit through commitEdit"
        )
        #expect(source.contains("modelContext: ModelContext,"), "the context is no longer optional")
        #expect(!source.contains("modelContext: ModelContext?"))

        // The stripper's own discrimination, pinned on a literal: the file's `#if os(macOS)` is
        // code and survives, so a reader that had quietly blanked everything cannot pass the
        // assertions above by returning nothing.
        #expect(source.contains("#if os(macOS)"))
    }

    // MARK: - Source shape: the three destination rows

    /// **The ordering that was the whole ticket.** No destination row dismisses on its own any
    /// more; each hands its move to `moveNote`, which dismisses only below the `catch`.
    @Test func noMoveDestinationRowClosesThePickerBeforeItsMoveCommits() throws {
        let source = try CadenceCommitSurfaceScan.scanned(Self.path)

        for row in ["noListDestination", "areaDestinations", "projectDestinations"] {
            let body = try CadenceCommitSurfaceScan.declarationBody(named: row, in: source)
            #expect(
                CadenceSourceScan.matchCount(#"dismissPicker\(\)"#, in: body) == 0,
                "\(row) still closes the picker itself"
            )
            #expect(body.contains("moveNote {"), "\(row) does not route its move through moveNote")
        }

        let move = try CadenceCommitSurfaceScan.declarationBody(named: "moveNote", in: source)
        #expect(move.contains("moveFailureNotice = CadencePendingChangePersistence.editFailureNotice"))
        #expect(
            CadenceCommitSurfaceScan.reportFollowsTheCatch("dismissPicker()", in: move),
            "the picker closes above the failure branch"
        )
        // The reader discriminates: the same helper with the two lines swapped is not this shape.
        #expect(!CadenceCommitSurfaceScan.reportFollowsTheCatch("try apply()", in: move))
    }

    /// A notice nothing draws is not a report. The Move page renders `moveFailureNotice`, so the
    /// popover the row no longer closes has the refusal in it.
    @Test func themovePageDrawsTheNoticeThatARefusedMoveSets() throws {
        let source = try CadenceCommitSurfaceScan.scanned(Self.path)
        let page = try CadenceCommitSurfaceScan.declarationBody(named: "movePage", in: source)

        #expect(page.contains("CadenceInlineFailureNotice(text: moveFailureNotice)"))
        #expect(source.contains("@State private var moveFailureNotice: String?"))
    }
}
