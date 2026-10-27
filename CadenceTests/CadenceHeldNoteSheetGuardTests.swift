import Foundation
import SwiftData
import Testing
@testable import Cadence

/// [[T-7540]]: **a held task closed its sheet when the model went; a held note drew a zombie.**
///
/// `CadenceDetailPanelPresentation.resolveHeldSubject` had exactly one caller, the task wrapper
/// `iOSTaskInspectorSheet`. Every iOS route that holds a `Note` in a `.sheet(item:)` or a
/// `.fullScreenCover(item:)` presented its editor directly, so a delete arriving from outside the
/// editor — a CloudKit import of a delete made on the Mac — left the editor bound to a model with no
/// context, and what the user typed next was lost silently. `iOSHeldNoteSheet` is the note half of
/// the same guard, reused by every note presenter.
///
/// Two kinds of test, for the reason `CadenceTaskInspectorHostTests` sets out: the rule's answer for
/// a real `Note` across a real delete is run against a store, and the wiring — all of it inside
/// `#if os(iOS)` — is pinned as source text, with a sweep that catches a new unguarded presenter
/// rather than only the ones that existed when this was written.
@MainActor
struct CadenceHeldNoteSheetGuardTests {

    // MARK: - The rule, about a note

    /// The task suite measured this for an `AppTask`; the guard is only the note's guard if the
    /// same two signals carry a `Note`'s delete too. Bounded, not pinned, for the toolchain reason
    /// `CadenceDetailPanelPresentation.heldSubjectIsGone` gives: each phase asserts that **at least
    /// one** signal fires and that the rule closes, and the `.stay` before the delete is what keeps
    /// "at least one" from being already true.
    @Test func deletingTheNoteUnderneathItsEditorClosesItInBothPhasesOfTheDelete() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let note = Note(kind: .permanent, title: "delete me", content: "typed before the delete")
        context.insert(note)
        try context.save()

        #expect(
            CadenceDetailPanelPresentation.resolveHeldSubject(heldModel: note) == .stay
        )

        context.delete(note)
        #expect(
            note.isDeleted || note.modelContext == nil,
            "a pending note delete reported through neither of the two signals the guard reads"
        )
        #expect(
            CadenceDetailPanelPresentation.resolveHeldSubject(heldModel: note) == .close
        )

        try context.save()
        #expect(
            note.isDeleted || note.modelContext == nil,
            "a committed note delete reported through neither of the two signals the guard reads"
        )
        #expect(try context.fetch(FetchDescriptor<Note>()).isEmpty)
        #expect(
            CadenceDetailPanelPresentation.resolveHeldSubject(heldModel: note) == .close
        )
    }

    // MARK: - A delete saved in another context ([[T-7561]])

    /// **The shape the two old signals cannot see.** The instance an editor holds lives in the main
    /// context; a delete saved in a second `ModelContext` over the same container — the shape a
    /// CloudKit import or another writer takes — left it reading `isDeleted == false` with its
    /// context still set, so the editor stayed up and the user's typing saved into nothing. The
    /// third signal asks the held model's context for the row, and the rule closes.
    @Test func aNoteDeletedInAnotherContextClosesItsEditor() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        try expectTheHeldNoteClosesWhenAnotherWriterDeletesIt(
            held: container.mainContext,
            writer: ModelContext(container)
        )
    }

    /// The same, with the writer in a **second container over the same store file**, in this test's
    /// own temporary directory: the cross-coordinator shape, the nearest in-harness analogue of an
    /// import that reaches the main context from outside it.
    @Test func aNoteDeletedThroughASecondContainerOverTheSameStoreClosesItsEditor() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CadenceHeldNoteSheetGuardTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("held.store")
        func container() throws -> ModelContainer {
            try ModelContainer(
                for: CadenceSchema.schema,
                configurations: [
                    ModelConfiguration(schema: CadenceSchema.schema, url: storeURL, cloudKitDatabase: .none)
                ]
            )
        }
        let heldContainer = try container()
        let writerContainer = try container()
        try expectTheHeldNoteClosesWhenAnotherWriterDeletesIt(
            held: heldContainer.mainContext,
            writer: ModelContext(writerContainer)
        )
    }

    /// The check is **by identity**, not "is there any row": a sibling deleted elsewhere leaves the
    /// held note open, and a note inserted but not yet saved — a capture in progress, under a
    /// temporary identifier — is present, not gone.
    @Test func theExistenceCheckAsksAboutTheHeldNoteAloneAndCountsAnUnsavedInsert() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let held = container.mainContext

        let unsaved = Note(kind: .permanent, title: "capturing", content: "not saved yet")
        held.insert(unsaved)
        #expect(!CadenceDetailPanelPresentation.heldRowIsMissingFromItsContext(unsaved))
        #expect(CadenceDetailPanelPresentation.resolveHeldSubject(heldModel: unsaved) == .stay)
        try held.save()

        let sibling = Note(kind: .permanent, title: "sibling", content: "")
        held.insert(sibling)
        try held.save()
        let writer = ModelContext(container)
        writer.delete(try #require(writer.model(for: sibling.persistentModelID) as? Note))
        try writer.save()

        #expect(CadenceDetailPanelPresentation.heldRowIsMissingFromItsContext(sibling))
        #expect(!CadenceDetailPanelPresentation.heldRowIsMissingFromItsContext(unsaved))
        #expect(CadenceDetailPanelPresentation.resolveHeldSubject(heldModel: unsaved) == .stay)
    }

    private func expectTheHeldNoteClosesWhenAnotherWriterDeletesIt(
        held: ModelContext,
        writer: ModelContext
    ) throws {
        let note = Note(kind: .permanent, title: "deleted elsewhere", content: "open in the editor")
        held.insert(note)
        try held.save()
        #expect(CadenceDetailPanelPresentation.resolveHeldSubject(heldModel: note) == .stay)

        let remote = try #require(writer.fetch(FetchDescriptor<Note>()).first)
        // By title, not `persistentModelID`: across two containers the identifiers do not compare
        // equal even for the same row (measured), and the store holds exactly this one note.
        #expect(remote.title == note.title)
        writer.delete(remote)
        try writer.save()

        #expect(try held.fetchCount(FetchDescriptor<Note>()) == 0, "the row did not leave the store")
        #expect(CadenceDetailPanelPresentation.heldRowIsMissingFromItsContext(note))
        #expect(
            CadenceDetailPanelPresentation.resolveHeldSubject(heldModel: note) == .close,
            "a note deleted by another writer still reads as alive to the editor holding it"
        )
    }

    // MARK: - The wrapper

    /// The wrapper asks the shared rule about both signals and draws the editor only on `.stay`.
    /// Swapping the branches, or dropping `modelContext` — the draft the task guard's measurement
    /// killed — leaves every presenter below still "going through the wrapper" while the guard
    /// guards nothing.
    @Test func theNoteWrapperDrawsTheEditorOnlyInTheStayBranchOfTheSharedRule() throws {
        let file = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSMarkdownReferenceSupport.swift")
        )
        let wrapper = try #require(
            CadenceSourceScan.declarationBody("struct iOSHeldNoteSheet<Content: View>: View", in: file)
        )

        // The model spelling, so all three signals are read in `Shared/` ([[T-7561]]).
        #expect(wrapper.contains("CadenceDetailPanelPresentation.resolveHeldSubject(heldModel: note)"))
        #expect(
            CadenceSourceScan.matchCount(#"case \.stay:\s*content\(note\)"#, in: wrapper) == 1,
            "the note editor is not drawn in the .stay branch of resolveHeldSubject"
        )
        #expect(
            CadenceSourceScan.matchCount(#"case \.close:\s*Color\.clear\.onAppear\(perform: close\)"#, in: wrapper) == 1,
            "the .close branch no longer clears the selection instead of drawing the editor"
        )
        #expect(!wrapper.contains("@Query"), "the page's filter is not the editor's lifetime")
    }

    // MARK: - Every presenter

    /// The nine presenters, each handing its note to the wrapper and clearing
    /// **its own** binding on close. Named so that losing one is a named failure.
    @Test func eachNotePresenterHandsItsNoteToTheWrapperAndClearsItsOwnBinding() throws {
        let presenters: [(path: String, binding: String)] = [
            ("Cadence/iOS/iOSMarkdownReferenceSupport.swift", "selectedReferenceNote"),
            ("Cadence/iOS/iOSNotesView.swift", "presentedNote"),
            ("Cadence/iOS/iOSNotesView.swift", "selectedMeetingNote"),
            ("Cadence/iOS/iOSListNotesView.swift", "presentedNote"),
            ("Cadence/iOS/iOSListNotesView.swift", "selectedEventNote"),
            ("Cadence/iOS/iOSCalendarEventEditSheet.swift", "presentedEventNote"),
            ("Cadence/iOS/iOSCaptureRadialMenu.swift", "noteBeingCaptured"),
            ("Cadence/iOS/iOSSearchView.swift", "selectedNote"),
            // The ninth, which the ticket's list missed and the sweep below found: the delete
            // confirmation. Its binding is the modifier's own `note`, so it clears `self.note`.
            ("Cadence/iOS/iOSNoteDeletionSupport.swift", "note")
        ]

        for (path, binding) in presenters {
            let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            #expect(
                CadenceSourceScan.matchCount(Self.guardedPresenter(binding: binding), in: code) == 1,
                "\(path) does not hand $\(binding) to iOSHeldNoteSheet and clear it on close"
            )
        }
    }

    /// **The sweep, so the ninth presenter cannot arrive unguarded.** Every `.sheet(item:)` or
    /// `.fullScreenCover(item:)` in the iOS tree whose closure takes a `note` must open with the
    /// wrapper. The list above names the known ones; this is what fails on a new one.
    @Test func noIOSSheetOrCoverHoldsANoteOutsideTheWrapper() throws {
        let anyNotePresenter = #"\.(?:sheet|fullScreenCover)\(item: \$\w+\)\s*\{\s*note in"#
        let guardedOpening = anyNotePresenter + #"\s*iOSHeldNoteSheet\(note: note\)"#

        var presenters = 0
        var offenders: [String] = []
        let files = try CadenceSourceScan.swiftFiles(under: "Cadence/iOS")
        #expect(files.count > 50, "the iOS sweep found \(files.count) files and cannot be doing its job")
        for path in files {
            let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            let all = CadenceSourceScan.matchCount(anyNotePresenter, in: code)
            let guarded = CadenceSourceScan.matchCount(guardedOpening, in: code)
            presenters += max(all, 0)
            if all != guarded { offenders.append("\(path) (\(all) presenters, \(guarded) guarded)") }
        }

        // Nine when this was written; a sweep that matched nothing would pass the offender check.
        #expect(presenters >= 9, "only \(presenters) note presenters found; the needle no longer matches the tree")
        #expect(offenders.isEmpty, "note presenters outside iOSHeldNoteSheet: \(offenders.joined(separator: ", "))")
    }

    /// Both needles above, self-checked against literals they must and must not accept: a typo in
    /// an interpolated pattern matches nothing, and every `== 1` would then be the wrong zero.
    @Test func theNotePresenterPatternsMatchWhatTheyLookLike() {
        let guarded = Self.guardedPresenter(binding: "presentedNote")
        #expect(CadenceSourceScan.matchCount(guarded, in: """
        .fullScreenCover(item: $presentedNote) { note in
            iOSHeldNoteSheet(note: note) { presentedNote = nil } content: { note in
                iOSNoteEditorCover(note: note, templateKind: nil, title: "")
            }
        }
        """) == 1)
        // The unguarded spelling this ticket removed.
        #expect(CadenceSourceScan.matchCount(guarded, in: """
        .fullScreenCover(item: $presentedNote) { note in
            iOSNoteEditorCover(note: note, templateKind: nil, title: "")
        }
        """) == 0)
        // The wrapper present, but closing a different selection.
        #expect(CadenceSourceScan.matchCount(guarded, in: """
        .fullScreenCover(item: $presentedNote) { note in
            iOSHeldNoteSheet(note: note) { selectedNote = nil } content: { note in
                iOSNoteEditorCover(note: note, templateKind: nil, title: "")
            }
        }
        """) == 0)
        // `self.` is accepted, for the presenter whose binding shares the closure parameter's name.
        #expect(CadenceSourceScan.matchCount(Self.guardedPresenter(binding: "note"), in: """
        content.sheet(item: $note) { note in
            iOSHeldNoteSheet(note: note) { self.note = nil } content: { note in
                iOSNoteDeleteConfirmationSheet(note: note, summary: summary) { try perform(note) }
            }
        }
        """) == 1)
        #expect(CadenceSourceScan.matchCount("([", in: "([") == -1, "a malformed pattern must read as a failure")
    }

    private static func guardedPresenter(binding: String) -> String {
        #"\.(?:sheet|fullScreenCover)\(item: \$\#(binding)\)\s*\{\s*note in\s*iOSHeldNoteSheet\(note: note\)\s*\{\s*(?:self\.)?\#(binding) = nil\s*\}\s*content:"#
    }
}
