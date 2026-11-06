// macOS only: `DeleteConfirmationManager` is a macOS type.
#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// [[T-11881]]: the Mac's two note deletes went through the non-refusable `present(…)` around a
/// bare `deleteNote`, so nothing committed the delete and a refused save was never said.
/// `presentNoteDelete` commits through `commitDelete` and holds the overlay open on a refusal,
/// the way `presentTaskDelete` does (T-376) and iOS's note sheet does (T-320).
///
/// In-memory containers only, read back from a second context: nothing here touches a store on
/// disk.
@MainActor
struct MacOSNoteDeleteCommitTests {
    private struct Refused: Error {}

    /// The app's singleton, reset first -- see `MacOSTaskDeleteNoticeTests.manager()`.
    private func manager() -> DeleteConfirmationManager {
        let confirmations = DeleteConfirmationManager.shared
        confirmations.cancel()
        return confirmations
    }

    private func seededNoteWithImage() throws -> (ModelContainer, ModelContext, Note) {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let asset = MarkdownImageAsset(
            data: Data([0x1]),
            mimeType: "image/png",
            pixelWidth: 20,
            pixelHeight: 20,
            displayWidth: 20
        )
        let note = Note(
            kind: .permanent,
            title: "Meeting",
            content: "Agenda items ![shot](cadence-image://\(asset.id.uuidString))"
        )
        context.insert(asset)
        context.insert(note)
        try context.save()
        return (container, context, note)
    }

    /// The bug: confirming commits. Read from a second context, which sees only what was saved --
    /// an uncommitted mark would still show the note and its image there.
    @Test func aConfirmedMacNoteDeleteIsCommittedAndClosesTheOverlay() throws {
        let (container, context, note) = try seededNoteWithImage()
        let confirmations = manager()
        var followedUp = 0

        confirmations.presentNoteDelete(note, in: context, resolve: { note }, didDelete: { followedUp += 1 })
        #expect(confirmations.isPresented)
        confirmations.confirm()

        #expect(!confirmations.isPresented)
        #expect(confirmations.failureNotice == nil)
        #expect(followedUp == 1)
        #expect(!context.hasChanges, "the delete is still only marked, waiting for autosave")
        #expect(try ModelContext(container).fetch(FetchDescriptor<Note>()).isEmpty)
        #expect(try ModelContext(container).fetch(FetchDescriptor<MarkdownImageAsset>()).isEmpty)
    }

    /// A refused commit: the overlay stays open saying so, the page's follow-up does not run, and
    /// "Nothing was removed" is true -- the note and its image are back in the context the page
    /// reads and never left the store.
    @Test func aRefusedMacNoteDeleteHoldsTheOverlayOpenAndRemovesNothing() throws {
        let (container, context, note) = try seededNoteWithImage()
        let confirmations = manager()
        var followedUp = 0

        confirmations.presentNoteDelete(
            note,
            in: context,
            resolve: { note },
            didDelete: { followedUp += 1 },
            commit: { _ in throw Refused() }
        )
        confirmations.confirm()

        #expect(confirmations.isPresented, "the overlay closed over a delete that never happened")
        #expect(confirmations.failureNotice == CadenceNoteDeletionSummary.deleteFailureNotice)
        #expect(followedUp == 0, "the selection moved off a note that is still there")
        #expect(!context.hasChanges, "the refused delete is still pending for the next save")
        #expect(try context.fetch(FetchDescriptor<Note>()).map(\.title) == ["Meeting"])
        #expect(try ModelContext(container).fetch(FetchDescriptor<Note>()).map(\.title) == ["Meeting"])
        #expect(try ModelContext(container).fetch(FetchDescriptor<MarkdownImageAsset>()).count == 1)
        confirmations.cancel()
    }

    /// A note gone by the time of confirming closes the overlay and deletes nothing else.
    @Test func aNoteGoneBeforeConfirmingJustClosesTheOverlay() throws {
        let (container, context, note) = try seededNoteWithImage()
        let confirmations = manager()
        var followedUp = 0

        confirmations.presentNoteDelete(note, in: context, resolve: { nil }, didDelete: { followedUp += 1 })
        confirmations.confirm()

        #expect(!confirmations.isPresented)
        #expect(followedUp == 0)
        #expect(try ModelContext(container).fetch(FetchDescriptor<Note>()).count == 1)
    }

    /// The overlay says what iOS's card says ([[T-8201]]): the note, what goes with it, and what
    /// it leaves -- built from the one summary, not typed at the page.
    @Test func theMacConfirmationStatesWhatTheDeleteTakesAndLeaves() throws {
        let (_, context, note) = try seededNoteWithImage()
        let tag = Tag(name: "work")
        context.insert(tag)
        note.tags = [tag]
        try context.save()
        let confirmations = manager()

        confirmations.presentNoteDelete(note, in: context, resolve: { note })
        let request = try #require(confirmations.request)
        let summary = CadenceNoteDeletionSummary.forNote(note, in: context)

        #expect(request.title == CadenceNoteDeletionSummary.confirmationTitle)
        #expect(summary.words == 3 && summary.images == 1 && summary.tags == 1)
        #expect(request.message == """
            This will permanently delete "Meeting".
            It takes 3 words and 1 embedded image with it.
            1 tag stays — deleting a note never deletes a tag.
            """)
        confirmations.cancel()

        let empty = CadenceNoteDeletionSummary(words: 0, images: 0, tags: 0, backlinks: 0)
        #expect(empty.confirmationMessage(noteTitle: "Blank")
                == "This will permanently delete \"Blank\".\n\(CadenceNoteDeletionSummary.emptyNoteLine)")
    }
}
#endif
