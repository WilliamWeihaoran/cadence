import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **T-17035: renaming a column in the iOS list editor to a name another column already holds
/// deleted a column on Save.**
///
/// `Area.normalizedSectionConfigs` keeps the first config of each case-insensitive name and drops
/// the rest, and the editor's drafts reached it unchecked. So renaming "Doing" to "todo" on a list
/// with a "Todo" column, or to "Default", came out of Save one column short: the renamed column's
/// colour and due date were gone and its cards were emptied into Default, with nothing said. The
/// Mac column popover refuses the same rename (`KanbanSectionStateSupport.renameRefusal`).
@MainActor
struct CadenceColumnRenameCollisionTests {

    /// A real list: Default, Todo, Doing (coloured, dated) and Done, two cards in Doing.
    private func board(in modelContext: ModelContext) throws -> Area {
        let area = Area(name: "Board")
        area.sectionConfigs = [
            TaskSectionConfig(name: TaskSectionDefaults.defaultName),
            TaskSectionConfig(name: "Todo"),
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

    /// The editor's column save: the three calls `iOSListEditorSheet.save()` makes.
    private func saveEditor(drafts: [CadenceSectionDraft], original: [TaskSectionConfig], area: Area) {
        area.applySectionConfigEdits(base: original, edited: CadenceSectionEditingSupport.configs(from: drafts))
        CadenceSectionEditingSupport.refileColumnCards(
            base: original,
            merged: area.sectionConfigs,
            area: area,
            project: nil
        )
    }

    private func renamed(_ from: String, to name: String, in drafts: [CadenceSectionDraft]) throws -> [CadenceSectionDraft] {
        var drafts = drafts
        let index = try #require(drafts.firstIndex { $0.originalName == from })
        drafts[index].name = name
        return drafts
    }

    /// **Behavioural, and red before the fix.**
    @Test(arguments: ["todo", " TODO ", "default"])
    func aRenameOntoAnotherColumnsNameKeepsEveryColumn(_ typed: String) throws {
        let modelContext = ModelContext(try CadenceTestStore.container())
        let area = try board(in: modelContext)
        let original = area.sectionConfigs

        saveEditor(drafts: try renamed("Doing", to: typed, in: CadenceSectionEditingSupport.drafts(from: original)),
                   original: original, area: area)

        #expect(area.sectionConfigs.map(\.name) == [TaskSectionDefaults.defaultName, "Todo", "Doing", "Done"])
        #expect(area.sectionConfigs.first { $0.name == "Doing" }?.colorHex == "#FF8800")
        #expect((area.tasks ?? []).allSatisfy { $0.resolvedSectionName == "Doing" })
    }

    /// **Behavioural, the non-parameterised sibling** (T-3212), and red before the fix: a rename
    /// of a column AHEAD of the one it collides with took the OTHER column: the normalizer kept the
    /// renamed one and dropped "Doing", colour, due date and all.
    @Test func aRenameOntoALaterColumnsNameDoesNotDeleteTheLaterColumn() throws {
        let modelContext = ModelContext(try CadenceTestStore.container())
        let area = try board(in: modelContext)
        let original = area.sectionConfigs
        let doing = try #require(original.first { $0.name == "Doing" })

        saveEditor(drafts: try renamed("Todo", to: "Doing", in: CadenceSectionEditingSupport.drafts(from: original)),
                   original: original, area: area)

        #expect(area.sectionConfigs.map(\.name) == [TaskSectionDefaults.defaultName, "Todo", "Doing", "Done"])
        #expect(area.sectionConfigs.first { $0.name == "Doing" }?.uuid == doing.uuid)
        #expect(area.sectionConfigs.first { $0.name == "Doing" }?.colorHex == "#FF8800")
    }

    /// **Behavioural.** The editor has the refused names to report, and only those.
    @Test func theEditorCanTellWhichNamesCollided() throws {
        let original = [
            TaskSectionConfig(name: TaskSectionDefaults.defaultName),
            TaskSectionConfig(name: "Todo"),
            TaskSectionConfig(name: "Doing")
        ]
        var drafts = CadenceSectionEditingSupport.drafts(from: original)
        #expect(CadenceSectionEditingSupport.collidingColumnNames(in: drafts).isEmpty)

        drafts = try renamed("Doing", to: "todo", in: drafts)
        #expect(CadenceSectionEditingSupport.collidingColumnNames(in: drafts) == ["todo"])

        // Two new rows with one name: both refused, neither half-saved.
        var added = CadenceSectionEditingSupport.drafts(from: original)
        added.append(CadenceSectionDraft(name: "Review"))
        added.append(CadenceSectionDraft(name: "review"))
        #expect(CadenceSectionEditingSupport.collidingColumnNames(in: added) == ["Review", "review"])
        #expect(CadenceSectionEditingSupport.configs(from: added).map(\.name) == [TaskSectionDefaults.defaultName, "Todo", "Doing"])
    }

    /// **Behavioural.** What is not a collision still lands: a swap, a case-only rename, and a
    /// rename onto a name the same save frees.
    @Test func renamesThatEndUniqueStillLand() throws {
        let original = [
            TaskSectionConfig(name: TaskSectionDefaults.defaultName),
            TaskSectionConfig(name: "Todo"),
            TaskSectionConfig(name: "Doing")
        ]
        var swap = try renamed("Todo", to: "Doing", in: CadenceSectionEditingSupport.drafts(from: original))
        swap = try renamed("Doing", to: "Todo", in: swap)
        #expect(CadenceSectionEditingSupport.configs(from: swap).map(\.name) == [TaskSectionDefaults.defaultName, "Doing", "Todo"])
        #expect(CadenceSectionEditingSupport.collidingColumnNames(in: swap).isEmpty)

        let caseOnly = try renamed("Todo", to: "TODO", in: CadenceSectionEditingSupport.drafts(from: original))
        #expect(CadenceSectionEditingSupport.configs(from: caseOnly).map(\.name) == [TaskSectionDefaults.defaultName, "TODO", "Doing"])
    }

    /// **Behavioural.** Reverting a refused rename to its saved name must not push out a third
    /// column renamed onto that saved name: that one is refused in turn.
    @Test func aRevertedRenameRefusesTheRenameOntoItsOldName() throws {
        let original = [
            TaskSectionConfig(name: TaskSectionDefaults.defaultName),
            TaskSectionConfig(name: "A"),
            TaskSectionConfig(name: "B"),
            TaskSectionConfig(name: "C")
        ]
        var drafts = try renamed("A", to: "B", in: CadenceSectionEditingSupport.drafts(from: original))
        drafts = try renamed("C", to: "A", in: drafts)

        #expect(CadenceSectionEditingSupport.configs(from: drafts).map(\.name) == [TaskSectionDefaults.defaultName, "A", "B", "C"])
        #expect(CadenceSectionEditingSupport.collidingColumnNames(in: drafts) == ["B", "A"])
    }

    /// **Source scan** (`Cadence/iOS` is invisible to this target): the editor asks the seam,
    /// says the shared sentence, and a NEW list writes nothing over the refusal.
    @Test func theListEditorReportsACollidingColumnName() throws {
        let editor = try CadenceSourceScan.strippedSourceReader()("Cadence/iOS/iOSListEditorViews.swift")
        #expect(editor.contains("CadenceSectionEditingSupport.collidingColumnNames(in: sectionDrafts)"))
        #expect(editor.contains("refusal = .nameAlreadyTaken"))
        #expect(editor.contains("guard refusal == nil || isEditing else { return }"))
    }
}
