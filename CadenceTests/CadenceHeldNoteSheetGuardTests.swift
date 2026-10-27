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
            CadenceDetailPanelPresentation.resolveHeldSubject(
                isDeleted: note.isDeleted,
                hasNoModelContext: note.modelContext == nil
            ) == .stay
        )

        context.delete(note)
        #expect(
            note.isDeleted || note.modelContext == nil,
            "a pending note delete reported through neither of the two signals the guard reads"
        )
        #expect(
            CadenceDetailPanelPresentation.resolveHeldSubject(
                isDeleted: note.isDeleted,
                hasNoModelContext: note.modelContext == nil
            ) == .close
        )

        try context.save()
        #expect(
            note.isDeleted || note.modelContext == nil,
            "a committed note delete reported through neither of the two signals the guard reads"
        )
        #expect(try context.fetch(FetchDescriptor<Note>()).isEmpty)
        #expect(
            CadenceDetailPanelPresentation.resolveHeldSubject(
                isDeleted: note.isDeleted,
                hasNoModelContext: note.modelContext == nil
            ) == .close
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

        #expect(wrapper.contains("CadenceDetailPanelPresentation.resolveHeldSubject("))
        #expect(wrapper.contains("isDeleted: note.isDeleted"))
        #expect(wrapper.contains("hasNoModelContext: note.modelContext == nil"))
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
