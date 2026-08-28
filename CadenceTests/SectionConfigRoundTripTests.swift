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
    /// Bounds-safe, because a merge that drops a column must fail an expectation rather than trap:
    /// a crashing test takes the rest of the suite down with it.
    private func column(_ configs: [TaskSectionConfig], _ index: Int) -> TaskSectionConfig? {
        configs.indices.contains(index) ? configs[index] : nil
    }

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

    // MARK: - Two devices, one blob (T-358)

    /// **The ticket in one test.** A list's whole section array is a single JSON string
    /// (`Area.sectionConfigsRaw`), so it is also the sync unit: two devices that open the same
    /// list, edit *different* columns and save each write the entire array, and the second write
    /// used to put the first device's column back to whatever its own editor opened with.
    ///
    /// The control at the bottom is the write this replaced. Without it every assertion above
    /// could be passing because the fixture never reproduced the defect in the first place.
    @Test func twoStaleEditsToDifferentColumnsBothSurviveOneSave() {
        let area = Area(name: "Ops")
        area.sectionConfigs = seededConfigs()

        // Both sheets open on the same array.
        let snapshot = area.sectionConfigs

        // The Mac renames "Research" and saves.
        var mac = snapshot
        mac[1].name = "Discovery"
        area.applySectionConfigEdits(base: snapshot, edited: mac)

        // The iPhone, still holding the pre-rename snapshot, recolours "Shipped" and saves.
        var phone = snapshot
        phone[2].colorHex = "#ff5a5a"
        area.applySectionConfigEdits(base: snapshot, edited: phone)

        let merged = area.sectionConfigs
        #expect(merged.map(\.uuid) == snapshot.map(\.uuid))
        #expect(column(merged, 1)?.name == "Discovery", "the iPhone's stale array undid the Mac's rename")
        #expect(column(merged, 2)?.colorHex == "#ff5a5a", "the iPhone's recolour did not land")

        // Fields neither device touched are still what they were.
        #expect(column(merged, 1)?.colorHex == "#a78bfa")
        #expect(column(merged, 1)?.dueDate == "2026-09-01")
        #expect(column(merged, 2)?.isArchived == true)
        #expect(column(merged, 2)?.isCompleted == true)

        // Control: the same two saves written the old way, whole array each time.
        let control = Area(name: "Ops")
        control.sectionConfigs = seededConfigs()
        let controlSnapshot = control.sectionConfigs
        var controlMac = controlSnapshot
        controlMac[1].name = "Discovery"
        control.sectionConfigs = controlMac
        var controlPhone = controlSnapshot
        controlPhone[2].colorHex = "#ff5a5a"
        control.sectionConfigs = controlPhone

        #expect(column(control.sectionConfigs, 1)?.name == "Research", "the control no longer reproduces T-358")
        #expect(column(control.sectionConfigs, 2)?.colorHex == "#ff5a5a")
    }

    /// The reason the merge is a **field-level** diff and not a whole-config replace keyed by
    /// `uuid`. A replace would satisfy the test above and still lose this: two devices editing two
    /// different *fields* of the same column.
    @Test func twoStaleEditsToDifferentFieldsOfOneColumnBothSurvive() {
        let area = Area(name: "Ops")
        area.sectionConfigs = seededConfigs()
        let snapshot = area.sectionConfigs

        var mac = snapshot
        mac[1].name = "Discovery"
        area.applySectionConfigEdits(base: snapshot, edited: mac)

        var phone = snapshot
        phone[1].dueDate = "2026-10-05"
        area.applySectionConfigEdits(base: snapshot, edited: phone)

        #expect(column(area.sectionConfigs, 1)?.name == "Discovery")
        #expect(column(area.sectionConfigs, 1)?.dueDate == "2026-10-05")
    }

    /// The case a naive `uuid` merge gets wrong. Matching by `uuid` and keeping every match would
    /// bring a column another device deleted straight back, because the stale snapshot still
    /// carries it and the identity still lines up. What tells the two apart is `base`: a column the
    /// caller *opened with* and no longer finds on the model was deleted elsewhere, not added here.
    @Test func aStaleSnapshotCannotResurrectAColumnDeletedOnAnotherDevice() {
        let area = Area(name: "Ops")
        area.sectionConfigs = seededConfigs()
        let snapshot = area.sectionConfigs
        let deletedID = snapshot[2].uuid

        // The Mac deletes "Shipped".
        area.removeSectionConfig(uuid: deletedID)
        #expect(area.sectionConfigs.count == 2)

        // The iPhone's sheet, opened before that, saves with an unrelated rename.
        var phone = snapshot
        phone[1].name = "Discovery"
        area.applySectionConfigEdits(base: snapshot, edited: phone)

        #expect(area.sectionConfigs.map(\.name) == [TaskSectionDefaults.defaultName, "Discovery"])
        #expect(!area.sectionConfigs.contains { $0.uuid == deletedID }, "a deleted column came back")

        // Control: the stale array written straight through does resurrect it.
        let control = Area(name: "Ops")
        control.sectionConfigs = snapshot
        control.sectionConfigs = snapshot.filter { $0.uuid != deletedID }
        #expect(control.sectionConfigs.count == 2)
        control.sectionConfigs = phone
        #expect(
            control.sectionConfigs.contains { $0.uuid == deletedID },
            "the control no longer reproduces the resurrection"
        )
    }

    /// The other direction of the same question: a column the caller never knew about is a
    /// concurrent *add*, and dropping everything the caller's array does not mention would delete
    /// it.
    @Test func aColumnAddedOnAnotherDeviceSurvivesAStaleSave() {
        let area = Area(name: "Ops")
        area.sectionConfigs = seededConfigs()
        let snapshot = area.sectionConfigs

        area.addSectionConfig(TaskSectionConfig(name: "Backlog", colorHex: "#4a9eff"))

        var phone = snapshot
        phone[1].name = "Discovery"
        area.applySectionConfigEdits(base: snapshot, edited: phone)

        #expect(
            area.sectionConfigs.map(\.name)
                == [TaskSectionDefaults.defaultName, "Discovery", "Shipped", "Backlog"]
        )
        #expect(area.sectionConfigs.last?.colorHex == "#4a9eff")
    }

    /// **Order is last-writer-wins, and this pins the half of it that is not.** There is no
    /// per-column position field to merge, so a save that *did* reorder imposes its order. A save
    /// that did not touch order must not impose one anyway — its array is simply in the sequence
    /// the sheet opened with, which is not a decision the user made.
    @Test func aSaveThatDidNotTouchColumnOrderKeepsTheOrderTheOtherDeviceSet() {
        let area = Area(name: "Ops")
        area.sectionConfigs = seededConfigs()
        let snapshot = area.sectionConfigs

        // The Mac drags "Shipped" ahead of "Research".
        area.reorderSectionConfigs { configs in
            var moved = configs
            let shipped = moved.remove(at: 2)
            moved.insert(shipped, at: 1)
            return moved
        }
        #expect(area.sectionConfigs.map(\.name) == [TaskSectionDefaults.defaultName, "Shipped", "Research"])

        // The iPhone recolours a column from its pre-drag snapshot. It never touched order.
        var phone = snapshot
        phone[1].colorHex = "#ff5a5a"
        area.applySectionConfigEdits(base: snapshot, edited: phone)

        #expect(area.sectionConfigs.map(\.name) == [TaskSectionDefaults.defaultName, "Shipped", "Research"])
        #expect(column(area.sectionConfigs, 2)?.colorHex == "#ff5a5a")
    }

    /// And the half that is. Two devices reordering the same board cannot both win; the last
    /// genuine reorder takes the whole order and the earlier one is lost. That is the decision,
    /// stated as a test rather than left implicit.
    @Test func aSaveThatDidReorderColumnsWinsTheWholeOrder() {
        let area = Area(name: "Ops")
        area.sectionConfigs = seededConfigs() + [TaskSectionConfig(name: "Backlog")]
        let snapshot = area.sectionConfigs
        #expect(snapshot.map(\.name) == [TaskSectionDefaults.defaultName, "Research", "Shipped", "Backlog"])

        // The Mac pulls "Backlog" to the front.
        area.reorderSectionConfigs { configs in
            var moved = configs
            let backlog = moved.remove(at: 3)
            moved.insert(backlog, at: 1)
            return moved
        }
        #expect(
            area.sectionConfigs.map(\.name)
                == [TaskSectionDefaults.defaultName, "Backlog", "Research", "Shipped"]
        )

        // The iPhone reorders differently from its own snapshot and saves last.
        var phone = snapshot
        let shipped = phone.remove(at: 2)
        phone.insert(shipped, at: 1)
        area.applySectionConfigEdits(base: snapshot, edited: phone)

        #expect(
            area.sectionConfigs.map(\.name)
                == [TaskSectionDefaults.defaultName, "Shipped", "Research", "Backlog"],
            "the last genuine reorder does not win the order"
        )
    }

    /// A list still on the pre-config `sectionNamesRaw` string has no stored uuids at all, so
    /// `sectionConfigs`' getter mints fresh ones on **every read** — `base` and `current` never
    /// share one. A uuid-only merge would read two reads of the same list as a full
    /// delete-and-replace and throw the edit away.
    @Test func aListStillOnTheLegacyNameListMergesByNameRatherThanLosingTheEdit() {
        let area = Area(name: "Ops")
        area.sectionNamesRaw = "\(TaskSectionDefaults.defaultName)\nResearch\nShipped"

        #expect(area.sectionConfigsRaw.isEmpty, "the fixture is not a legacy list")
        #expect(
            area.sectionConfigs.map(\.uuid) != area.sectionConfigs.map(\.uuid),
            "the legacy getter stopped minting fresh uuids; this test no longer proves anything"
        )

        let snapshot = area.sectionConfigs
        var edited = snapshot
        edited[1].colorHex = "#ff5a5a"
        area.applySectionConfigEdits(base: snapshot, edited: edited)

        #expect(
            area.sectionConfigs.map(\.name)
                == [TaskSectionDefaults.defaultName, "Research", "Shipped"]
        )
        #expect(column(area.sectionConfigs, 1)?.colorHex == "#ff5a5a")
    }

    /// The merge writes through the `sectionConfigs` setter and nothing else, so the legacy
    /// `sectionNamesRaw` mirror — archived columns included — stays exactly as it was.
    @Test func aMergedWriteKeepsTheLegacySectionNameMirrorInStep() {
        let area = Area(name: "Ops")
        area.sectionConfigs = seededConfigs()
        let snapshot = area.sectionConfigs

        var phone = snapshot
        phone[1].name = "Discovery"
        area.applySectionConfigEdits(base: snapshot, edited: phone)

        #expect(area.sectionNamesRaw == "\(TaskSectionDefaults.defaultName)\nDiscovery\nShipped")
        #expect(!area.sectionConfigsRaw.isEmpty)
        // The filtered getter still hides the archived column, as it always did.
        #expect(area.sectionNames == [TaskSectionDefaults.defaultName, "Discovery"])
    }

    /// `Project` carries the same blob and the same normalisation as `Area`, so it goes through
    /// the same merge. A fix that reached one of them would be half a fix.
    @Test func aProjectMergesItsColumnsThroughTheSamePath() {
        let project = Project(name: "Launch")
        project.sectionConfigs = seededConfigs()
        let snapshot = project.sectionConfigs

        var mac = snapshot
        mac[1].name = "Discovery"
        project.applySectionConfigEdits(base: snapshot, edited: mac)

        var phone = snapshot
        phone[2].colorHex = "#ff5a5a"
        project.applySectionConfigEdits(base: snapshot, edited: phone)

        #expect(column(project.sectionConfigs, 1)?.name == "Discovery")
        #expect(column(project.sectionConfigs, 2)?.colorHex == "#ff5a5a")
    }

    /// The task re-pointing a merge implies is derived from the merge's **result**, not from the
    /// editor's drafts: a column another device deleted is gone from the result even though the
    /// drafts still list it, and its tasks have to follow it to Default like any other removal.
    @Test func theTaskMovesAMergeImpliesComeFromItsResultRatherThanFromTheDrafts() {
        let base = seededConfigs()
        var merged = base
        merged[1].name = "Discovery"
        merged.remove(at: 2)

        let moves = CadenceSectionConfigMerge.sectionNameMoves(base: base, merged: merged)
        #expect(moves.renames.count == 1)
        #expect(moves.renames.first?.from == "Research")
        #expect(moves.renames.first?.to == "Discovery")
        #expect(moves.removedNames == ["Shipped"])

        // Nothing to do reads as nothing to do rather than as a rename to the same name.
        let quiet = CadenceSectionConfigMerge.sectionNameMoves(base: base, merged: base)
        #expect(quiet.renames.isEmpty)
        #expect(quiet.removedNames.isEmpty)
    }
}
