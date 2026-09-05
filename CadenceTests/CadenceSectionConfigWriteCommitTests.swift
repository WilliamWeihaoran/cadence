import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **T-885: a kanban column could be created, drawn, and gone at next launch.**
///
/// A list's kanban columns are one JSON string on `Area`/`Project` (`sectionConfigsRaw`), so every
/// column write is a whole-array write through `CadenceSectionConfigContainer`.
/// `ListSectionsKanbanView.addSection` called the uncommitted `addSectionConfig(_:)`, and
/// `KanbanListSectionSupportViews.swift` contained no `save()` at all.
///
/// Same family as [[T-870]], which found the *reorder* in that state, but on a **creation**, which
/// is strictly worse: a reverted reorder still leaves every column the user made, and a reverted
/// creation takes one away. The user names a column, watches it appear on the board, and it is gone
/// at next launch — the failure [[T-614]]'s rule is about, one step past a rearrangement.
///
/// **Invisible to `CadenceSaveCommitDisciplineTests` twice over.** Half 2 needs a *swallowed* commit
/// in the frame to hang itself on, and there was no commit at all; half 3 fires on the insert or
/// delete of a `@Model`, and a `TaskSectionConfig` is a struct inside a string. It is invisible to
/// the `\.order` sweep for the same reason [[T-870]] was: a column's position and its existence are
/// both facts about one re-serialised blob.
///
/// **The behavioural half reads through a second `ModelContext`**, because "the objects hold it"
/// and "the store holds it" are exactly the two states this ticket is about. The refusal path takes
/// an injected `commit:` because a `save()` that throws cannot be provoked out of an in-memory
/// container. `addSection` itself is a `private` member of a SwiftUI view, so the call site is
/// pinned as source text under the rule in `Cadence/Shared/AGENTS.md`.
@MainActor
struct CadenceSectionConfigWriteCommitTests {

    private struct CommitRefused: Error {}

    private func container() throws -> ModelContainer {
        try CadenceTestStore.container()
    }

    /// The columns a **second** context over the same store can see — the only reading that
    /// distinguishes "committed" from "pending on one context".
    private func storedSectionNames(in modelContainer: ModelContainer) throws -> [String] {
        let reader = ModelContext(modelContainer)
        let areas = try reader.fetch(FetchDescriptor<Area>())
        return areas.first?.sectionConfigs.map(\.name) ?? []
    }

    private func seededArea(in modelContext: ModelContext) throws -> Area {
        let area = Area(name: "Work")
        area.sectionConfigs = [
            TaskSectionConfig(name: TaskSectionDefaults.defaultName),
            TaskSectionConfig(name: "Doing")
        ]
        modelContext.insert(area)
        try modelContext.save()
        return area
    }

    // MARK: - T-885: the column creation

    /// **Behavioural.** The uncommitted form is still the one the merge is written around, and it
    /// leaves the new column pending on one context. This is what the board's "+" rail did.
    @Test func theuncommittedAddLeavesTheNewColumnOutOfTheStore() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let area = try seededArea(in: modelContext)

        #expect(area.addSectionConfig(TaskSectionConfig(name: "Backlog")), "non-vacuity: the add wrote nothing at all")

        #expect(modelContext.hasChanges, "non-vacuity: the uncommitted add did not even dirty the object")
        #expect(
            try storedSectionNames(in: modelContainer) == [TaskSectionDefaults.defaultName, "Doing"],
            "the uncommitted add somehow reached the store"
        )
    }

    /// **Behavioural, and the shape T-870 gave the reorder.** The committing form answers `.added`
    /// only once a second context can see the column.
    @Test func acommittedAddPutsTheNewColumnInTheStore() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let area = try seededArea(in: modelContext)

        #expect(area.addSectionConfig(TaskSectionConfig(name: "Backlog"), in: modelContext) == .added)

        #expect(!modelContext.hasChanges, "the column creation is still pending after it answered yes")
        #expect(
            try storedSectionNames(in: modelContainer) == [TaskSectionDefaults.defaultName, "Doing", "Backlog"],
            "the store does not hold the column the board is drawing"
        )
    }

    /// **Behavioural.** A refused creation puts the whole blob back, so the board redraws the
    /// columns the store still holds rather than the one it refused.
    @Test func arefusedAddTakesTheNewColumnBackOffTheBoard() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let project = Project(name: "Launch")
        project.sectionConfigs = [
            TaskSectionConfig(name: TaskSectionDefaults.defaultName),
            TaskSectionConfig(name: "Doing")
        ]
        modelContext.insert(project)
        try modelContext.save()

        #expect(
            project.addSectionConfig(
                TaskSectionConfig(name: "Backlog"),
                in: modelContext,
                commit: { _ in throw CommitRefused() }
            ) == .refused
        )

        #expect(
            project.sectionConfigs.map(\.name) == [TaskSectionDefaults.defaultName, "Doing"],
            "the refused creation left the new column on the board"
        )
    }

    /// **Behavioural.** A name another column already holds is declined by the merge, not by the
    /// store, and must not be reported as either a creation or a refusal — there is nothing pending
    /// and nothing to put back.
    @Test func anaddOfANameAnotherColumnHoldsIsDeclinedRatherThanRefused() throws {
        let modelContainer = try container()
        let modelContext = ModelContext(modelContainer)
        let area = try seededArea(in: modelContext)

        #expect(area.addSectionConfig(TaskSectionConfig(name: "doing"), in: modelContext) == .declined)

        #expect(!modelContext.hasChanges, "a declined creation still dirtied the object")
        #expect(area.sectionConfigs.map(\.name) == [TaskSectionDefaults.defaultName, "Doing"])
    }

    /// **The call site.** `addSection` is a `private` member of a SwiftUI view, so it is pinned as
    /// source text under the rule in `Cadence/Shared/AGENTS.md`. **This is the half that was red
    /// before T-885.**
    @Test func theboardsAddColumnRailReachesACommit() throws {
        let source = try CadenceCommitSurfaceScan.scanned("Cadence/macOS/Views/KanbanListSectionSupportViews.swift")
        let body = try CadenceCommitSurfaceScan.declarationBody(named: "addSection", in: source)

        #expect(body.contains("KanbanBoardSupport.nextSectionName("), "non-vacuity: not the column-creating body")
        #expect(body.contains("addSectionConfig("), "non-vacuity: not the column-creating body")
        #expect(body.contains("in: modelContext"), "the board's add rail reaches no commit")
        #expect(!body.contains("try? modelContext.save()"), "the board's add rail swallows its save")
    }

    /// **The report.** A refused creation is named where the user is already looking — the board —
    /// and cleared by the next attempt, in one expression so the two opposite mistakes (a stale
    /// refusal left up, a refusal never shown) cannot come apart.
    @Test func arefusedCreationIsNamedOnTheBoardInOneSentence() throws {
        #expect(CadenceSectionConfigAddOutcome.refusalNotice == "Couldn't add this column. Nothing was added.")

        let source = try CadenceCommitSurfaceScan.scanned("Cadence/macOS/Views/KanbanListSectionSupportViews.swift")
        #expect(
            !source.contains("\"Couldn't add this column"),
            "the board retypes the creation sentence instead of reading it"
        )
        #expect(
            source.contains("addFailureNotice = outcome == .refused ? CadenceSectionConfigAddOutcome.refusalNotice : nil"),
            "the board does not name and clear a refused creation in one expression"
        )
    }
}
