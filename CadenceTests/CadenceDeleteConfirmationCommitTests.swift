import Foundation
import SwiftData
import Testing
@testable import Cadence

/// T-320: iOS destructive confirmations closed before the deletion was attempted.
///
/// Both sheets called `dismiss()` and *then* `onConfirm()`. That is not "dismissed before knowing
/// the result" — it is dismissed before the work started, so there was no instant at which a
/// failure could have been reported even in principle. The delete underneath then swallowed its
/// own save with `try?`, which meant a cascade could be marked deleted in the context, never
/// committed, and reported as done.
///
/// A confirmation is the opposite case from a creation: there is nothing to hand back to, the
/// screen that asked the question is the only one that can answer it, and so it **stays open and
/// says why**. The rollback is what makes that sentence true — "nothing was removed".
///
/// The behavioural half runs the real cascades against a real container, from a second context.
/// The source half pins the ordering inside the two `#if os(iOS)` sheets this target cannot build.
@MainActor
struct CadenceDeleteConfirmationCommitTests {

    private struct CommitRefused: Error {}

    private func refuse(_ modelContext: ModelContext) throws {
        throw CommitRefused()
    }

    // MARK: - The note delete

    /// The committed case, from a second context: `deleteNote` alone only marks the note and its
    /// orphaned image assets deleted.
    @Test func acommittedNoteDeleteLeavesTheStoreWithoutTheNote() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let note = Note(kind: .permanent, title: "Meeting")
        modelContext.insert(note)
        try modelContext.save()

        modelContext.deleteNote(note)
        try CadencePendingChangePersistence.commitDelete(in: modelContext)

        #expect(!modelContext.hasChanges)
        #expect(try ModelContext(container).fetch(FetchDescriptor<Note>()).isEmpty)
    }

    /// The refused case. The note is back — in the store it never left, and in the context the
    /// list reads from, which is what "nothing was removed" has to mean before the sheet says it.
    ///
    /// The image asset is the whole reason this can be promised at all: `deleteNote` marks the
    /// note *and* the assets only it referenced, and neither `deleteNote` nor the image sweep
    /// commits on its own, so one rollback undoes the entire delete. Compare
    /// `arefusedContextDeleteRestoresEverythingExceptTheTasksItAlreadyCommitted`, where it does
    /// not.
    @Test func arefusedNoteDeleteLeavesTheNoteAndItsImagesWhereTheyWere() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
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
            content: "![shot](cadence-image://\(asset.id.uuidString))"
        )
        modelContext.insert(asset)
        modelContext.insert(note)
        try modelContext.save()

        modelContext.deleteNote(note)
        #expect(throws: CommitRefused.self) {
            try CadencePendingChangePersistence.commitDelete(in: modelContext, commit: refuse)
        }

        #expect(!modelContext.hasChanges, "the delete is still pending behind a closed sheet")
        #expect(try modelContext.fetch(FetchDescriptor<Note>()).map(\.title) == ["Meeting"])
        #expect(try ModelContext(container).fetch(FetchDescriptor<Note>()).map(\.title) == ["Meeting"])
        #expect(
            try ModelContext(container).fetch(FetchDescriptor<MarkdownImageAsset>()).count == 1,
            "the image the note referenced was reclaimed by a delete that never committed"
        )
    }

    // MARK: - The list cascade

    /// The cascade is where a swallowed commit costs most: `deleteContext` marks a whole tree
    /// deleted in one pass. Committed, all of it goes.
    @Test func acommittedContextDeleteEmptiesTheWholeTreeFromTheStore() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let context = Context(name: "Work")
        let area = Area(name: "Operations", context: context)
        let task = AppTask(title: "Inside the area")
        task.area = area
        task.context = context
        modelContext.insert(context)
        modelContext.insert(area)
        modelContext.insert(task)
        try modelContext.save()

        modelContext.deleteContext(context)
        try CadencePendingChangePersistence.commitDelete(in: modelContext)

        let store = ModelContext(container)
        #expect(try store.fetch(FetchDescriptor<Context>()).isEmpty)
        #expect(try store.fetch(FetchDescriptor<Area>()).isEmpty)
        #expect(try store.fetch(FetchDescriptor<AppTask>()).isEmpty)
    }

    /// Refused, the rows the cascade had only *marked* come back — and the tasks do not.
    ///
    /// **This is the finding that words the two notices differently.**
    /// `CadenceTaskMutationSupport.deleteTasks` ends with `try? modelContext.save()`, part-way
    /// through the cascade, so the list's tasks are committed as deleted before the outer commit
    /// is ever asked for. A rollback cannot reach them. Everything else the cascade marked — the
    /// context, its areas, notes, links and nested projects — does come back.
    ///
    /// So the note confirmation is allowed to say "Nothing was removed" and the list confirmation
    /// is not, and that asymmetry is a measured fact rather than a wording preference. The last
    /// assertion pins where the mid-cascade commit lives: when [[T-322]] takes it out, this test
    /// goes red and tells whoever did it that
    /// `CadenceListDeletionKind.deleteFailureNotice` can now promise more.
    @Test func arefusedContextDeleteRestoresEverythingExceptTheTasksItAlreadyCommitted() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let context = Context(name: "Work")
        let area = Area(name: "Operations", context: context)
        let task = AppTask(title: "Inside the area")
        task.area = area
        task.context = context
        modelContext.insert(context)
        modelContext.insert(area)
        modelContext.insert(task)
        try modelContext.save()

        modelContext.deleteContext(context)
        #expect(throws: CommitRefused.self) {
            try CadencePendingChangePersistence.commitDelete(in: modelContext, commit: refuse)
        }

        let store = ModelContext(container)
        #expect(try store.fetch(FetchDescriptor<Context>()).map(\.name) == ["Work"])
        #expect(try store.fetch(FetchDescriptor<Area>()).map(\.name) == ["Operations"])
        #expect(try modelContext.fetch(FetchDescriptor<Area>()).map(\.name) == ["Operations"])

        #expect(
            try store.fetch(FetchDescriptor<AppTask>()).isEmpty,
            "the task deletion no longer commits mid-cascade — the list notice can promise more"
        )

        // Where that commit is. Scoped by its neighbour rather than by
        // `CadenceSourceScan.functionBody(named:)`, which cannot read this particular function:
        // `deleteTasks` declares `willDelete: (Set<UUID>) -> Void = { _ in }`, and the helper takes
        // the first `{` after the signature — so it returns the *default closure* and not the body.
        let core = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Shared/CadenceTaskMutationSupport.swift")
        )
        #expect(core.contains("static func deleteTasks("), "the shared task-deletion core moved")
        let midCascadeCommit = #"processPendingChanges\(\)\s*try\? modelContext\.save\(\)"#
        #expect(
            CadenceSourceScan.matchCount(midCascadeCommit, in: core) == 1,
            "the mid-cascade commit moved; re-derive what a refused list delete leaves behind"
        )
        #expect(
            CadenceSourceScan.matchCount(
                midCascadeCommit,
                in: "modelContext.processPendingChanges()\n        try? modelContext.save()"
            ) == 1,
            "the needle does not match the spelling it is hunting"
        )
        #expect(
            CadenceSourceScan.matchCount(
                midCascadeCommit,
                in: "modelContext.processPendingChanges()\n        try modelContext.save()"
            ) == 0,
            "the needle matches a commit that does not swallow"
        )
    }

    // MARK: - What the sheets say

    /// Three deletes share one sheet, so the notice names the kind rather than saying "list",
    /// which is not a word the app uses for any of them. The second sentence is the one the
    /// rollback earns.
    @Test func eachDeleteFailureNoticeNamesItsOwnKind() {
        #expect(CadenceListDeletionKind.area.deleteFailureNotice
                == "Couldn't finish deleting this area. Some of it may already be gone.")
        #expect(CadenceListDeletionKind.project.deleteFailureNotice
                == "Couldn't finish deleting this project. Some of it may already be gone.")
        #expect(CadenceListDeletionKind.context.deleteFailureNotice
                == "Couldn't finish deleting this context. Some of it may already be gone.")
        #expect(CadenceNoteDeletionSummary.deleteFailureNotice
                == "Couldn't delete this note. Nothing was removed.")

        // Four sentences, four kinds — a shared constant would name the wrong object on three
        // of the four screens.
        let notices = CadenceListDeletionKind.allCases.map(\.deleteFailureNotice)
            + [CadenceNoteDeletionSummary.deleteFailureNotice]
        #expect(Set(notices).count == notices.count)

        // Only the delete that really does restore everything is allowed to say so. See
        // `arefusedContextDeleteRestoresEverythingExceptTheTasksItAlreadyCommitted`.
        #expect(CadenceNoteDeletionSummary.deleteFailureNotice.contains("Nothing was removed"))
        for kind in CadenceListDeletionKind.allCases {
            #expect(
                !kind.deleteFailureNotice.contains("Nothing was removed"),
                "the \(kind.noun) cascade promises an undo it cannot perform"
            )
        }
    }

    // MARK: - The two sheets

    /// The confirmation attempts, then decides. Asserted as positions inside `confirm()`, because
    /// the bug was purely one of order: both spellings contain `dismiss()` and `onConfirm()`.
    @Test func bothConfirmationsDismissOnlyAfterTheDeleteSucceeded() throws {
        for path in [
            "Cadence/iOS/iOSNoteDeletionSupport.swift",
            "Cadence/iOS/iOSListDeletionSupport.swift"
        ] {
            let raw = try CadenceSourceScan.sourceFile(path)
            #expect(raw.count > 400, "\(path) read as \(raw.count) characters")

            let stripped = CadenceSourceScan.strippingComments(raw)
            #expect(stripped != raw, "\(path): the comment stripper removed nothing")
            #expect(stripped.count == raw.count, "\(path): the stripper changed the length")

            // The closure the sheet is handed can fail, and the sheet's parameter says so.
            #expect(
                stripped.contains("let onConfirm: () throws -> Void"),
                "\(path) still takes a confirmation that cannot report anything"
            )

            let confirm = try #require(
                CadenceSourceScan.functionBody(named: "confirm", in: stripped),
                "\(path) has no confirm()"
            )
            let attempt = try #require(
                confirm.range(of: "try onConfirm()"),
                "\(path): confirm() does not attempt the delete"
            )
            let dismissal = try #require(
                confirm.range(of: "dismiss()"),
                "\(path): confirm() never closes the sheet"
            )
            #expect(
                dismissal.lowerBound > attempt.upperBound,
                "\(path): the sheet closes before the delete has been attempted"
            )
            #expect(
                confirm.contains("catch"),
                "\(path): confirm() has no failure branch"
            )
            #expect(
                confirm.contains("failureNotice ="),
                "\(path): a failed delete leaves the sheet saying nothing"
            )

            // And the destructive button no longer dismisses on its own — one dismissal in
            // confirm(), and the only other one in the file is Cancel.
            #expect(
                CadenceSourceScan.matchCount(#"dismiss\(\)"#, in: confirm) == 1,
                "\(path): confirm() dismisses more than once"
            )
            #expect(
                CadenceSourceScan.matchCount(#"dismiss\(\)"#, in: stripped) == 2,
                "\(path): a dismissal exists outside confirm() and Cancel"
            )

            // The delete underneath commits, and no longer swallows.
            let perform = try #require(
                CadenceSourceScan.functionBody(named: "perform", in: stripped),
                "\(path) has no perform()"
            )
            #expect(perform.contains("CadencePendingChangePersistence.commitDelete("))
            #expect(
                CadenceSourceScan.matchCount(#"try\?"#, in: perform) == 0,
                "\(path): perform() still swallows its save"
            )
        }
    }

    /// Non-vacuity, and the one thing that would make every assertion above pass for the wrong
    /// reason: a reader returning an empty string, which is what a `/tmp` against `/private/tmp`
    /// path mismatch produces on an isolated build tree.
    @Test func theSourceScanActuallyReadsTheseFiles() throws {
        let note = try CadenceSourceScan.strippingComments(
            CadenceSourceScan.sourceFile("Cadence/iOS/iOSNoteDeletionSupport.swift")
        )
        #expect(note.contains("struct iOSNoteDeleteConfirmationSheet: View"))
        #expect(note.contains("modelContext.deleteNote(note)"))

        let list = try CadenceSourceScan.strippingComments(
            CadenceSourceScan.sourceFile("Cadence/iOS/iOSListDeletionSupport.swift")
        )
        #expect(list.contains("struct iOSListDeleteConfirmationSheet: View"))
        #expect(list.contains("modelContext.deleteContext(context)"))

        // The needle that carries the ordering assertion matches what it hunts and nothing else.
        #expect(CadenceSourceScan.matchCount(#"dismiss\(\)"#, in: "dismiss()") == 1)
        #expect(CadenceSourceScan.matchCount(#"dismiss\(\)"#, in: "dismissed") == 0)
        #expect(CadenceSourceScan.matchCount(#"try\?"#, in: "try? modelContext.save()") == 1)
        #expect(CadenceSourceScan.matchCount(#"try\?"#, in: "try onConfirm()") == 0)
    }
}
