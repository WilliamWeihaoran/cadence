import Foundation
import SwiftData
import Testing
@testable import Cadence

/// Editing a list's kanban columns from iOS.
///
/// The editor used to be a newline-separated list of *names*, written back through
/// `Area.sectionNames` / `Project.sectionNames`. That setter matches configs by name, so a rename
/// was indistinguishable from "delete this column, add that one": the renamed column came back
/// with a fresh `uuid`, the default colour, no due date and `isCompleted == false`. Worse, nothing
/// re-pointed `AppTask.sectionName`, so the column's tasks were stranded on a name no column had
/// any more — which then surfaced on macOS as a phantom column via `CadenceReadService`.
@MainActor
struct SectionConfigRoundTripTests {
    private func seededConfigs() -> [TaskSectionConfig] {
        [
            TaskSectionConfig(name: TaskSectionDefaults.defaultName),
            TaskSectionConfig(name: "Research", colorHex: "#a78bfa", dueDate: "2026-09-01"),
            TaskSectionConfig(name: "Shipped", colorHex: "#4ecb71", isCompleted: true, isArchived: true)
        ]
    }

    /// Three configs, one archived, one renamed: all three survive with uuid, colour and due date
    /// intact.
    @Test func aRenamedColumnKeepsItsIdentityColourAndDueDate() {
        let original = seededConfigs()
        var drafts = CadenceSectionEditingSupport.drafts(from: original)
        drafts[1].name = "Discovery"

        let saved = CadenceSectionEditingSupport.configs(from: drafts)

        #expect(saved.map(\.uuid) == original.map(\.uuid))
        #expect(saved.map(\.name) == [TaskSectionDefaults.defaultName, "Discovery", "Shipped"])

        let renamed = saved[1]
        #expect(renamed.uuid == original[1].uuid)
        #expect(renamed.colorHex == "#a78bfa")
        #expect(renamed.dueDate == "2026-09-01")

        let archived = saved[2]
        #expect(archived.isArchived)
        #expect(archived.isCompleted)
        #expect(archived.colorHex == "#4ecb71")
    }

    /// Saving with no edits at all must be a no-op — including for the archived column, which the
    /// name-list editor used to destroy.
    @Test func savingWithNoEditsChangesNothing() {
        let original = seededConfigs()
        let saved = CadenceSectionEditingSupport.configs(
            from: CadenceSectionEditingSupport.drafts(from: original)
        )

        #expect(saved == original)
    }

    @Test func onlyGenuineRenamesAreReported() {
        let original = seededConfigs()
        var drafts = CadenceSectionEditingSupport.drafts(from: original)
        drafts[1].name = "Discovery"
        // Capitalization is not a move: section matching is case-insensitive everywhere.
        drafts[2].name = "SHIPPED"
        drafts.append(CadenceSectionDraft(name: "Backlog"))

        let renames = CadenceSectionEditingSupport.renames(in: drafts)

        #expect(renames.count == 1)
        #expect(renames.first?.from == "Research")
        #expect(renames.first?.to == "Discovery")
    }

    @Test func removedColumnsAreReportedByTheirOldName() {
        let original = seededConfigs()
        var drafts = CadenceSectionEditingSupport.drafts(from: original)
        drafts.remove(at: 1)

        #expect(CadenceSectionEditingSupport.removedNames(original: original, drafts: drafts) == ["Research"])
    }

    /// The reassignment proper: a renamed column takes its tasks with it, a removed one hands its
    /// tasks to Default, and everything else is left alone.
    @Test func tasksFollowARenameAndFallBackToDefaultOnARemoval() throws {
        let modelContext = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())

        let area = Area(name: "Ops")
        area.sectionConfigs = seededConfigs()

        func task(_ title: String, section: String) -> AppTask {
            let task = AppTask(title: title)
            task.sectionName = section
            task.area = area
            return task
        }

        let renamed = task("Read the paper", section: "Research")
        let removed = task("Announce", section: "Shipped")
        let untouched = task("Triage", section: TaskSectionDefaults.defaultName)
        area.tasks = [renamed, removed, untouched]

        for model in [area, renamed, removed, untouched] as [any PersistentModel] {
            modelContext.insert(model)
        }
        try modelContext.save()

        var drafts = CadenceSectionEditingSupport.drafts(from: area.sectionConfigs)
        drafts[1].name = "Discovery"
        drafts.remove(at: 2)

        let moved = CadenceSectionEditingSupport.applySectionNameChanges(
            renames: CadenceSectionEditingSupport.renames(in: drafts),
            removedNames: CadenceSectionEditingSupport.removedNames(original: area.sectionConfigs, drafts: drafts),
            to: area.tasks ?? []
        )
        area.sectionConfigs = CadenceSectionEditingSupport.configs(from: drafts)
        try modelContext.save()

        #expect(moved == 2)
        #expect(renamed.resolvedSectionName == "Discovery")
        #expect(removed.resolvedSectionName == TaskSectionDefaults.defaultName)
        #expect(untouched.resolvedSectionName == TaskSectionDefaults.defaultName)

        // No task is left naming a column the list no longer has — the phantom-column condition.
        let liveNames = Set(area.sectionConfigs.map { $0.name.lowercased() })
        #expect((area.tasks ?? []).allSatisfy { liveNames.contains($0.resolvedSectionName.lowercased()) })
    }

    /// An editor emptied of every column still saves a usable list rather than a list with no
    /// columns at all.
    @Test func anEmptyEditorFallsBackToTheDefaultColumn() {
        #expect(CadenceSectionEditingSupport.configs(from: []).map(\.name) == [TaskSectionDefaults.defaultName])
        #expect(
            CadenceSectionEditingSupport.configs(from: [CadenceSectionDraft(name: "   ")]).map(\.name)
                == [TaskSectionDefaults.defaultName]
        )
    }
}
