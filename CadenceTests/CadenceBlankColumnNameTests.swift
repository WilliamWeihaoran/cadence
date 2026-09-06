import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **T-1053: clearing a kanban column's name did not no-op — it deleted the column.**
///
/// `Area.normalizedSectionConfigs` / `Project.normalizedSectionConfigs` drop any config whose name
/// trims to empty, and the setter runs that on every write. So a write that only *renamed* a
/// column to whitespace came out of the setter one column short, and nothing anywhere said so.
///
/// **What was measured at HEAD, on a real `Area` in a real store, before the fix.** Both halves of
/// the ticket's claim, and they turned out to be two different defects on two different surfaces:
///
/// - `area.updateSectionConfig(uuid:) { $0.name = "   " }` answered `true`, removed the column
///   from the blob, and left every card in it still filed under the old name. Those cards then
///   name a column the list does not have — `CadenceTaskQuerySupport.sectionGroups` builds its
///   groups from `sectionNames`, so a card under a name no column holds is in **no group at all**
///   and vanishes from the list detail. That is the strand the ticket asked about.
/// - The iOS list editor reaches the same deletion by a different road and *does* re-point the
///   cards: `CadenceSectionEditingSupport.configs(from:)` dropped a blank draft outright, so the
///   merge read the cleared column as one this caller **removed**, and `reassignTasks` then sent
///   its cards to Default. Nothing is stranded there — but the column, its colour and its due date
///   are gone, from clearing a text field, with no confirmation and nothing said.
///
/// **The fix is the [[T-914]] shape: the refusal is returned, not swallowed.** A blank name is
/// withheld and everything else in the same edit still lands, exactly as the macOS column popover
/// already does for a duplicate name. Two guards, because there are two roads:
///
/// 1. `CadenceSectionConfigMerge.applyingChangedFields` will not apply a name that trims to empty,
///    which covers every writer that goes through the merge — `updateSectionConfig` included.
/// 2. `CadenceSectionEditingSupport.configs(from:)` keeps a column that already exists when its
///    draft's name is cleared, under the name it had, so the merge sees a refused rename rather
///    than a removal. A draft that never existed on disk is still dropped: nothing is lost by
///    declining to create a column the user never named.
@MainActor
struct CadenceBlankColumnNameTests {

    private func container() throws -> ModelContainer {
        try CadenceTestStore.container()
    }

    /// A real list with three columns and two cards filed in the middle one.
    private func board(in modelContext: ModelContext) throws -> Area {
        let area = Area(name: "Board")
        area.sectionConfigs = [
            TaskSectionConfig(name: TaskSectionDefaults.defaultName),
            TaskSectionConfig(name: "Doing", colorHex: "#FF8800", dueDate: "2026-09-30"),
            TaskSectionConfig(name: "Done")
        ]
        modelContext.insert(area)
        for title in ["Card one", "Card two"] {
            let task = AppTask(title: title)
            task.area = area
            task.sectionName = "Doing"
            modelContext.insert(task)
            area.tasks = (area.tasks ?? []) + [task]
        }
        try modelContext.save()
        return area
    }

    private func doing(in area: Area) throws -> TaskSectionConfig {
        try #require(area.sectionConfigs.first { $0.name == "Doing" })
    }

    // MARK: - The model-level write

    /// **Behavioural, and red before the fix.** The ticket's own reproduction, one line of it.
    @Test func renamingAColumnToWhitespaceLeavesTheColumnWhereItWas() throws {
        let modelContext = ModelContext(try container())
        let area = try board(in: modelContext)
        let column = try doing(in: area)

        area.updateSectionConfig(uuid: column.uuid) { $0.name = "   " }

        #expect(
            area.sectionConfigs.map(\.name) == [TaskSectionDefaults.defaultName, "Doing", "Done"],
            "a name that trims to empty deleted the column instead of being refused"
        )
        let survivor = try doing(in: area)
        #expect(survivor.uuid == column.uuid, "the column came back as a different column")
        #expect(survivor.colorHex == "#FF8800", "the column's colour did not survive")
        #expect(survivor.dueDate == "2026-09-30", "the column's due date did not survive")
    }

    /// **Behavioural, and red before the fix.** What happened to the tasks, which is the half the
    /// ticket left open. At HEAD they were left naming a column the list no longer had, and
    /// `sectionGroups` builds groups from the column names — so they were in no group at all.
    @Test func theCardsOfAColumnRenamedToWhitespaceAreStillInAGroup() throws {
        let modelContext = ModelContext(try container())
        let area = try board(in: modelContext)
        let column = try doing(in: area)

        area.updateSectionConfig(uuid: column.uuid) { $0.name = "   " }

        let cards = area.tasks ?? []
        #expect(cards.count == 2)
        let liveNames = Set(area.sectionConfigs.map { $0.name.lowercased() })
        #expect(
            cards.allSatisfy { liveNames.contains($0.resolvedSectionName.lowercased()) },
            "a card is filed under a name no column holds"
        )
        let groups = CadenceTaskQuerySupport.sectionGroups(
            from: cards,
            sectionNames: area.sectionNames
        )
        #expect(
            groups.flatMap(\.tasks).count == 2,
            "a card dropped out of every section group and is drawn nowhere"
        )
    }

    /// **Behavioural.** The refusal is not a veto on the rest of the write: a colour pressed in the
    /// same edit still lands, and only the blank name is withheld. This is the [[T-914]] rule one
    /// layer down, at the merge rather than at the macOS popover.
    @Test func aRefusedNameDoesNotTakeTheRestOfTheEditWithIt() throws {
        let modelContext = ModelContext(try container())
        let area = try board(in: modelContext)
        let column = try doing(in: area)

        area.updateSectionConfig(uuid: column.uuid) { config in
            config.name = "  "
            config.colorHex = "#123456"
            config.dueDate = "2026-10-01"
        }

        let survivor = try doing(in: area)
        #expect(survivor.name == "Doing", "the blank name was stored")
        #expect(survivor.colorHex == "#123456", "the colour was refused along with the name")
        #expect(survivor.dueDate == "2026-10-01", "the due date was refused along with the name")
    }

    /// **Behavioural.** A real rename still renames. The guard is about *blank*, and a mutation
    /// that widens it to every name has to fail somewhere.
    @Test func anOrdinaryRenameStillReachesTheStore() throws {
        let modelContext = ModelContext(try container())
        let area = try board(in: modelContext)
        let column = try doing(in: area)

        area.updateSectionConfig(uuid: column.uuid) { $0.name = "  Shipping  " }

        #expect(area.sectionConfigs.map(\.name) == [TaskSectionDefaults.defaultName, "Shipping", "Done"])
    }

    // MARK: - The iOS list editor

    /// The editor's save, as far as the columns are concerned: drafts in, merged blob out, cards
    /// re-pointed from the merge's own result. `iOSListEditorSheet.save()` spells exactly these
    /// three calls, and they are the only ones that touch a column.
    private func saveEditor(
        drafts: [CadenceSectionDraft],
        original: [TaskSectionConfig],
        area: Area
    ) {
        area.applySectionConfigEdits(
            base: original,
            edited: CadenceSectionEditingSupport.configs(from: drafts)
        )
        let moves = CadenceSectionConfigMerge.sectionNameMoves(base: original, merged: area.sectionConfigs)
        CadenceSectionEditingSupport.applySectionNameChanges(
            renames: moves.renames,
            removedNames: moves.removedNames,
            to: area.tasks ?? []
        )
    }

    /// **Behavioural, and red before the fix.** Clearing an existing column's name in the iOS list
    /// editor and pressing Save deleted the column and emptied it into Default. The cards were not
    /// stranded — that road re-points them — but the column, its colour and its due date were gone
    /// from a cleared text field, with no confirmation.
    @Test func clearingAnExistingColumnsNameInTheListEditorDoesNotDeleteIt() throws {
        let modelContext = ModelContext(try container())
        let area = try board(in: modelContext)
        let original = area.sectionConfigs

        var drafts = CadenceSectionEditingSupport.drafts(from: original)
        let index = try #require(drafts.firstIndex { $0.originalName == "Doing" })
        drafts[index].name = "   "
        saveEditor(drafts: drafts, original: original, area: area)

        #expect(
            (area.tasks ?? []).allSatisfy { $0.resolvedSectionName == "Doing" },
            "the cards were emptied into Default by a rename the editor should have refused"
        )
        #expect(area.sectionConfigs.map(\.name) == [TaskSectionDefaults.defaultName, "Doing", "Done"])
        #expect(area.sectionConfigs.first { $0.name == "Doing" }?.colorHex == "#FF8800")
    }

    /// **Behavioural.** The editor says so rather than silently keeping the old name. The seam is
    /// the list of names, so the sheet has one thing to ask and one sentence to draw.
    @Test func theEditorCanTellWhichColumnNamesTheUserCleared() throws {
        let modelContext = ModelContext(try container())
        let area = try board(in: modelContext)

        var drafts = CadenceSectionEditingSupport.drafts(from: area.sectionConfigs)
        #expect(CadenceSectionEditingSupport.clearedColumnNames(in: drafts).isEmpty)

        let index = try #require(drafts.firstIndex { $0.originalName == "Doing" })
        drafts[index].name = "\n  "
        #expect(CadenceSectionEditingSupport.clearedColumnNames(in: drafts) == ["Doing"])

        drafts.append(CadenceSectionDraft(name: "   "))
        #expect(
            CadenceSectionEditingSupport.clearedColumnNames(in: drafts) == ["Doing"],
            "a column that never existed is not a column the user cleared"
        )
    }

    /// **Behavioural.** The line the fix deliberately draws. A row added during this edit and left
    /// blank is still dropped without a word: there is no column, no colour and no card to lose,
    /// and refusing the whole save over an empty row the user never typed in would be worse than
    /// the silence.
    @Test func aBlankRowThatNeverExistedIsStillDropped() throws {
        let modelContext = ModelContext(try container())
        let area = try board(in: modelContext)
        let original = area.sectionConfigs

        var drafts = CadenceSectionEditingSupport.drafts(from: original)
        drafts.append(CadenceSectionDraft(name: "  "))
        saveEditor(drafts: drafts, original: original, area: area)

        #expect(area.sectionConfigs.map(\.name) == [TaskSectionDefaults.defaultName, "Doing", "Done"])
        #expect(
            CadenceSectionEditingSupport.configs(from: [CadenceSectionDraft(name: "  ")]).map(\.name)
                == [TaskSectionDefaults.defaultName],
            "a blank row that never existed reached the blob as an unnameable column"
        )
    }

    /// **Behavioural.** Deleting a column is still deleting a column — the swipe removes the draft
    /// rather than blanking it, and that must keep working, cards and all.
    @Test func removingTheDraftEntirelyStillDeletesTheColumnAndItsCardsGoToDefault() throws {
        let modelContext = ModelContext(try container())
        let area = try board(in: modelContext)
        let original = area.sectionConfigs

        var drafts = CadenceSectionEditingSupport.drafts(from: original)
        drafts.removeAll { $0.originalName == "Doing" }
        saveEditor(drafts: drafts, original: original, area: area)

        #expect(area.sectionConfigs.map(\.name) == [TaskSectionDefaults.defaultName, "Done"])
        #expect((area.tasks ?? []).allSatisfy { $0.resolvedSectionName == TaskSectionDefaults.defaultName })
    }

    // MARK: - The report

    /// **Source scan**, under the rule in `Cadence/Shared/AGENTS.md`: the sheet's `save()` and its
    /// notice are `private` members of a SwiftUI `View`, so "the user is told" is not reachable
    /// behaviourally. What is checked is that the editor asks the seam, uses the shared refusal,
    /// and does not close over it.
    @Test func theListEditorReportsARefusedColumnNameAndStaysOpen() throws {
        let editor = try CadenceSourceScan.strippedSourceReader()("Cadence/iOS/iOSListEditorViews.swift")
        #expect(
            editor.contains("CadenceSectionEditingSupport.clearedColumnNames("),
            "the editor no longer asks which column names were cleared"
        )
        #expect(
            editor.contains("KanbanColumnRenameRefusal"),
            "the editor does not use the shared refusal, so it has its own sentence or none"
        )
        #expect(
            editor.contains("nameRefusalNotice"),
            "there is nowhere for the refusal to be shown"
        )
        #expect(
            editor.contains("guard refusal == nil else { return }"),
            "the sheet dismisses over the refusal, and a notice on a sheet that is gone is not a report"
        )
    }

    /// **Source scan.** One sentence for one refusal. `KanbanColumnRenameRefusal` was macOS-only
    /// while the same refusal is now reachable from iOS, and a second copy of the empty-name
    /// sentence is exactly the near-copy this repository's rules forbid.
    ///
    /// **Comments are stripped first, and that is not tidiness.** The first cut of this read raw
    /// text, and a mutation that reworded the `return` survived it — the sentence is also *quoted*
    /// in the enum's own doc comment, one line up, so the file still matched and the scan answered
    /// "declared here" over prose. `CadenceSourceScan.strippedSourceReader()` is the shared reader
    /// that exists for this, rather than a fourth hand-rolled walker in this file.
    @Test func theRefusalSentenceIsDeclaredOnceAndSharedByBothPlatforms() throws {
        let readStripped = CadenceSourceScan.strippedSourceReader()
        var declarations: [String] = []
        for root in ["Cadence/Shared", "Cadence/macOS", "Cadence/iOS"] {
            for path in try CadenceSourceScan.swiftFiles(under: root) {
                if try readStripped(path).contains("\"A column needs a name.\"") {
                    declarations.append(path)
                }
            }
        }
        #expect(declarations == ["Cadence/Shared/CadenceSectionConfigMerge.swift"])
    }
}

