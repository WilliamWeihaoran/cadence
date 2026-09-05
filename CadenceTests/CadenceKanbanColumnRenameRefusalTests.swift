import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **T-914: a kanban column rename the editor *declines* was reported as one that landed.**
///
/// `ListSectionKanbanColumn.applySectionEdits` refuses two names outright — empty once trimmed, and
/// one another column in the same list already holds — and it refused them by returning without
/// writing and without setting anything. `commitSectionEdits()` then flushed a `ModelContext` with
/// nothing pending in it, which **succeeds**, and cleared `saveFailureNotice` on the way out. So
/// the user pressed Return over a duplicate name, the popover said nothing at all, and the column
/// kept its old title with no explanation available anywhere on screen.
///
/// **The fix is a third editor state, not a refused-commit notice**, and the two are genuinely
/// different sentences to the user. `CadenceInPlaceEditFlush.failureNotice` — "Couldn't save these
/// changes. They're still here — try again." — is an invitation to press the same key again, which
/// is exactly the wrong advice for a name that will be refused every time it is offered.
/// `arefusedRenameFlushesCleanlyWhichIsWhyTheCommitCannotReportIt` below measures the fact that
/// makes the third state necessary rather than merely tidy.
///
/// **Where the two halves are tested.** The decision moved into
/// `KanbanSectionStateSupport.renameRefusal` so it has a seam — `applySectionEdits` and
/// `commitSectionEdits` are `private` members of a SwiftUI `View`, and "a refusal was reported as a
/// save" is a behavioural claim rather than a source-text one. The wiring that carries the answer
/// to a surface the user is looking at stays a source scan, under the rule in
/// `Cadence/Shared/AGENTS.md`.
@MainActor
struct CadenceKanbanColumnRenameRefusalTests {

    private func container() throws -> ModelContainer {
        try CadenceTestStore.container()
    }

    private func board(in modelContext: ModelContext) throws -> Area {
        let area = Area(name: "Board")
        area.sectionConfigs = [
            TaskSectionConfig(name: TaskSectionDefaults.defaultName),
            TaskSectionConfig(name: "Doing"),
            TaskSectionConfig(name: "Done")
        ]
        modelContext.insert(area)
        try modelContext.save()
        return area
    }

    // MARK: - The decision

    /// **Behavioural.** The two names the editor refuses, and each one's own answer.
    @Test func thetwoNamesTheEditorRefusesAreDistinguishedFromEachOther() throws {
        let modelContext = ModelContext(try container())
        let area = try board(in: modelContext)
        let doing = try #require(area.sectionConfigs.first { $0.name == "Doing" })

        func refusal(_ typed: String) -> KanbanColumnRenameRefusal? {
            KanbanSectionStateSupport.renameRefusal(
                typedName: typed, columnUUID: doing.uuid, area: area, project: nil
            )
        }

        #expect(refusal("") == .emptyName)
        #expect(refusal("   ") == .emptyName)
        #expect(refusal("Done") == .nameAlreadyTaken, "a name another column holds was allowed through")
        #expect(refusal("done") == .nameAlreadyTaken, "the collision check became case-sensitive")
        #expect(refusal("  Done  ") == .nameAlreadyTaken, "the collision check stopped trimming")
    }

    /// **Behavioural.** Everything that is not one of those two names is allowed through, including
    /// the three shapes that look like collisions and are not.
    @Test func anameTheListDoesNotAlreadyHoldIsAllowedThrough() throws {
        let modelContext = ModelContext(try container())
        let area = try board(in: modelContext)
        let doing = try #require(area.sectionConfigs.first { $0.name == "Doing" })

        func refusal(_ typed: String, columnUUID: UUID = UUID()) -> KanbanColumnRenameRefusal? {
            KanbanSectionStateSupport.renameRefusal(
                typedName: typed, columnUUID: columnUUID, area: area, project: nil
            )
        }

        #expect(refusal("Shipping", columnUUID: doing.uuid) == nil)
        // The column's own name is not a collision with itself, in any casing.
        #expect(refusal("Doing", columnUUID: doing.uuid) == nil, "a column collided with itself")
        #expect(refusal("doing", columnUUID: doing.uuid) == nil, "a column collided with its own name recased")
        // A column that is no longer in the list — deleted here or on another device while the
        // popover was open — is not a refusal the user can act on.
        #expect(refusal("Done") == nil, "a deleted column reported a refusal the user cannot act on")
        // No container at all: the board belongs to neither an area nor a project.
        #expect(
            KanbanSectionStateSupport.renameRefusal(
                typedName: "Done", columnUUID: doing.uuid, area: nil, project: nil
            ) == nil
        )
    }

    /// **Behavioural, and the question is asked of the *stored* column.** A rename that already
    /// landed — by Return, or by a colour press, or from another device — is in the store, and the
    /// popover's opening snapshot is not what decides whether a name collides.
    @Test func thecollisionIsMeasuredAgainstTheStoredColumnNotTheOpeningSnapshot() throws {
        let modelContext = ModelContext(try container())
        let area = try board(in: modelContext)
        let doing = try #require(area.sectionConfigs.first { $0.name == "Doing" })

        // Another device renames this column away and puts the *other* one on the name it had.
        // In that order: the containers' normaliser dedupes case-insensitively, so two columns
        // called "Doing" for even one write would silently drop one of them.
        let done = try #require(area.sectionConfigs.first { $0.name == "Done" })
        area.updateSectionConfig(uuid: doing.uuid) { $0.name = "Shipping" }
        area.updateSectionConfig(uuid: done.uuid) { $0.name = "Doing" }
        #expect(area.sectionConfigs.count == 3, "non-vacuity: a column was dropped setting this up")

        #expect(
            KanbanSectionStateSupport.renameRefusal(
                typedName: "Doing", columnUUID: doing.uuid, area: area, project: nil
            ) == .nameAlreadyTaken,
            "the name the popover opened with is now another column's, and was allowed anyway"
        )
        #expect(
            KanbanSectionStateSupport.renameRefusal(
                typedName: "Done", columnUUID: doing.uuid, area: area, project: nil
            ) == nil,
            "a name no column holds any more was refused on a stale reading"
        )
    }

    /// **The two sentences, and the one they are deliberately not.**
    ///
    /// "A column with this name already exists." is the tag editors' sentence one noun along; the
    /// app already says it for the same refusal in three places, and a user who has met it once
    /// should not have to learn a second phrasing.
    @Test func thetwoRefusalsSayDifferentThingsAndNeitherSaysTryAgain() {
        #expect(KanbanColumnRenameRefusal.emptyName.notice == "A column needs a name.")
        #expect(KanbanColumnRenameRefusal.nameAlreadyTaken.notice == "A column with this name already exists.")
        #expect(
            KanbanColumnRenameRefusal.emptyName.notice != KanbanColumnRenameRefusal.nameAlreadyTaken.notice,
            "the two refusals collapsed into one sentence"
        )
        for refusal in [KanbanColumnRenameRefusal.emptyName, .nameAlreadyTaken] {
            #expect(refusal.notice != CadenceInPlaceEditFlush.failureNotice)
            #expect(refusal.notice != CadencePendingChangePersistence.editFailureNotice)
            #expect(refusal.notice != CadenceOrderCommit.failureNotice)
            #expect(
                !refusal.notice.contains("try again"),
                "an editor refusal invites the user to repeat a gesture that will be refused again"
            )
        }
    }

    // MARK: - Why the commit point cannot be the thing that reports it

    /// **Behavioural, and this is the measurement the whole ticket rests on.** A rename the editor
    /// declined leaves *nothing pending*, so the flush at the commit point succeeds — and a
    /// succeeding flush is what used to clear `saveFailureNotice`. The store cannot report this
    /// refusal because the store was never asked to do anything.
    @Test func arefusedRenameFlushesCleanlyWhichIsWhyTheCommitCannotReportIt() throws {
        let modelContext = ModelContext(try container())
        let area = try board(in: modelContext)
        let doing = try #require(area.sectionConfigs.first { $0.name == "Doing" })

        #expect(
            KanbanSectionStateSupport.renameRefusal(
                typedName: "Done", columnUUID: doing.uuid, area: area, project: nil
            ) == .nameAlreadyTaken
        )
        #expect(!modelContext.hasChanges, "the refused rename left work pending after all")
        #expect(
            CadenceInPlaceEditFlush.flush(in: modelContext),
            "non-vacuity: the flush this ticket is about did not succeed"
        )
        #expect(
            area.sectionConfigs.first { $0.uuid == doing.uuid }?.name == "Doing",
            "the refused name reached the store"
        )
    }

    // MARK: - The wiring

    /// **The commit point names the refusal, and its answer is the refusal's.**
    ///
    /// The order matters and is asserted: the notice is set *above* the flush guard, so a rename
    /// declined by the editor and a commit refused by the store — which can both be true of one
    /// press, since the colour and the date go in either way — do not overwrite each other.
    @Test func thecommitPointReportsTheEditorsRefusalSeparatelyFromTheStores() throws {
        let column = try CadenceCommitSurfaceScan.scanned("Cadence/macOS/Views/KanbanSectionColumnView.swift")
        #expect(column.contains("struct ListSectionKanbanColumn: View"), "non-vacuity: wrong file read")

        let apply = try #require(CadenceSourceScan.functionBody(named: "applySectionEdits", in: column))
        #expect(apply.contains("KanbanSectionStateSupport.renameRefusal("), "the apply decides the refusal itself again")
        #expect(apply.contains("return refusal"), "the apply swallows the refusal again")

        let commit = try #require(CadenceSourceScan.functionBody(named: "commitSectionEdits", in: column))
        #expect(commit.contains("let refusal = applySectionEdits()"))
        #expect(commit.contains("nameRefusalNotice = refusal?.notice"),
                "the commit point does not name and clear the editor's refusal in one expression")
        #expect(commit.contains("return refusal == nil"), "a refused rename is answered as a commit that landed")

        let named = try #require(commit.range(of: "nameRefusalNotice = refusal?.notice"))
        let flushed = try #require(commit.range(of: "guard CadenceInPlaceEditFlush.flush(in: modelContext) else {"))
        #expect(
            named.upperBound < flushed.lowerBound,
            "a commit the store refuses loses the editor's refusal on its way out"
        )
    }

    /// **The refusal reaches a surface the user is looking at, and is cleared by the next attempt.**
    ///
    /// Both the popover and the column header read one funnel, which is what stops the two notices
    /// disagreeing about which of them is showing. The header's route is the T-646 one: the popover
    /// is already gone when a dismissal commits, so the column takes the sentence over.
    @Test func therefusalIsDrawnWhereTheUserIsLookingAndClearedByTheNextAttempt() throws {
        let column = try CadenceCommitSurfaceScan.scanned("Cadence/macOS/Views/KanbanSectionColumnView.swift")

        #expect(column.contains("failureNotice: editorFailureNotice"), "the popover draws a notice the refusal never reaches")
        #expect(column.contains("return showEditor ? nil : editorFailureNotice"),
                "the column header draws a notice the refusal never reaches")
        #expect(column.contains("saveFailureNotice ?? nameRefusalNotice"),
                "the two notices no longer reach one funnel")

        let open = try #require(CadenceSourceScan.functionBody(named: "openSectionEditor", in: column))
        #expect(open.contains("nameRefusalNotice = nil"), "a refusal from a previous attempt is still up")
        #expect(open.contains("saveFailureNotice = nil"), "non-vacuity: not the opening body")

        // The sentences are read, never retyped.
        #expect(!column.contains("\"A column with this name already exists"))
        #expect(!column.contains("\"A column needs a name"))
    }
}
