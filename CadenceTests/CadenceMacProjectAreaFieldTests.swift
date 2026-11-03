// macOS only: `EditProjectSheet` and `CreateListSheet` are macOS sheets.
#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **[[T-10180]]: the Mac's project sheets choose a project's parent area, as iOS's editor does.**
///
/// iOS's list editor offered an Area row in project mode and wrote `project.area` on create and on
/// edit; the Mac's `EditProjectSheet` and `CreateListSheet`'s `.project` arm had no such field, and
/// no macOS view wrote `project.area` at all ([[T-8201]]: no hardware constraint explained it).
///
/// The fixture is the shape that tells a real area write from a cosmetic one: a project with **no
/// context of its own**, so its tasks' denormalized `context` comes from its area, and moving the
/// area has to move that copy too ([[T-293]]).
@MainActor
struct CadenceMacProjectAreaFieldTests {
    private struct Fixture {
        let modelContext: ModelContext
        let work: Context
        let personal: Context
        let operations: Area
        let home: Area
        let launch: Project
        let task: AppTask
    }

    private func makeFixture() throws -> Fixture {
        let modelContext = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
        let work = Context(name: "Work")
        let personal = Context(name: "Personal")
        let operations = Area(name: "Operations", context: work)
        let home = Area(name: "Home", context: personal)
        let launch = Project(name: "Launch", context: nil, area: operations)
        let task = AppTask(title: "Ship it")
        for model in [work, personal] { modelContext.insert(model) }
        for model in [operations, home] { modelContext.insert(model) }
        modelContext.insert(launch)
        modelContext.insert(task)
        task.project = launch
        task.context = work
        try modelContext.save()
        return Fixture(
            modelContext: modelContext,
            work: work,
            personal: personal,
            operations: operations,
            home: home,
            launch: launch,
            task: task
        )
    }

    // MARK: - Edit

    /// The edit sheet's write: the project lands under the chosen area, and its tasks follow the
    /// context they now inherit.
    @Test func editMovesTheProjectUnderTheChosenAreaAndItsTasksFollow() throws {
        let f = try makeFixture()
        #expect(f.task.context?.id == f.work.id)

        EditProjectSheet.applyOwnership(to: f.launch, context: nil, area: f.home)

        #expect(f.launch.area?.id == f.home.id)
        #expect(f.launch.resolvedContext?.id == f.personal.id)
        #expect(f.task.context?.id == f.personal.id)
        try f.modelContext.save()
        #expect(f.home.projects?.contains { $0.id == f.launch.id } == true)
    }

    /// "None" takes the project out of its area, and a context-less project's tasks lose the
    /// context they were inheriting.
    @Test func editCanTakeTheProjectOutOfItsArea() throws {
        let f = try makeFixture()

        EditProjectSheet.applyOwnership(to: f.launch, context: nil, area: nil)

        #expect(f.launch.area == nil)
        #expect(f.task.context == nil)
    }

    /// The change detector the snapshot's task set keys on: an area move alone counts, and an
    /// unchanged pair does not (non-vacuity for the test above).
    @Test func anAreaMoveAloneCountsAsAnOwnershipChange() throws {
        let f = try makeFixture()
        #expect(EditProjectSheet.ownershipChanged(f.launch, contextID: nil, areaID: f.home.id))
        #expect(!EditProjectSheet.ownershipChanged(f.launch, contextID: nil, areaID: f.operations.id))
    }

    /// A refused commit puts the area back: the Mac's write goes under the same
    /// `CadenceListEditSnapshot` iOS's does, which holds `project.area`.
    @Test func aRefusedEditPutsTheAreaAndTheTasksContextBack() throws {
        let f = try makeFixture()
        let undo = CadenceListEditSnapshot(
            f.launch,
            tasks: CadenceTaskMutationSupport.inheritedContextTargets(project: f.launch)
        )

        EditProjectSheet.applyOwnership(to: f.launch, context: nil, area: f.home)
        undo.restore()

        #expect(f.launch.area?.id == f.operations.id)
        #expect(f.task.context?.id == f.work.id)
    }

    // MARK: - Create

    @Test func createFilesTheNewProjectUnderTheChosenArea() throws {
        let f = try makeFixture()

        let made = CreateListSheet.makeNewProject(
            name: "Garden",
            context: nil,
            area: f.home,
            colorHex: CreateListSheet.ListType.project.defaultColor,
            icon: CreateListSheet.ListType.project.defaultIcon
        )
        f.modelContext.insert(made)
        try f.modelContext.save()

        #expect(made.area?.id == f.home.id)
        #expect(made.resolvedContext?.id == f.personal.id)
        #expect(made.icon == CreateListSheet.ListType.project.defaultIcon)

        let unfiled = CreateListSheet.makeNewProject(
            name: "Loose", context: nil, area: nil, colorHex: "#4ecb71", icon: "checklist"
        )
        #expect(unfiled.area == nil)
    }

    // MARK: - Source shape: both platforms build the field

    private func code(_ path: String) throws -> String {
        CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
    }

    /// **Both platforms build an Area field off the shared list, drawing the area glyph.** The
    /// iOS half is behind `#if os(iOS)` and no assertion above can reach it.
    @Test func bothPlatformsBuildTheAreaFieldFromTheSharedList() throws {
        for path in [
            "Cadence/iOS/iOSListEditorViews.swift",
            "Cadence/macOS/Sheets/ListEditorSupportViews.swift"
        ] {
            let source = try code(path)
            #expect(
                CadenceSourceScan.matchCount(#"CadenceAreaPickerSupport\.items\("#, in: source) >= 1,
                "\(path) does not build an Area list from CadenceAreaPickerSupport"
            )
            #expect(
                CadenceSourceScan.matchCount(#"CadenceListKindIcon\.area\b"#, in: source) >= 1,
                "\(path) does not draw the area glyph"
            )
        }
        let support = try code("Cadence/macOS/Sheets/ListEditorSupportViews.swift")
        #expect(CadenceSourceScan.matchCount(#"struct ListEditorAreaRow\s*:"#, in: support) == 1)
    }

    /// And both Mac project sheets draw it, and the edit sheet routes its write through the tested
    /// `applyOwnership` rather than writing `project.area` beside it.
    @Test func bothMacProjectSheetsDrawTheAreaRowAndWriteThroughTheTestedSeam() throws {
        let edit = try code("Cadence/macOS/Sheets/EditListSheet.swift")
        let create = try code("Cadence/macOS/Sheets/CreateListSheet.swift")
        #expect(CadenceSourceScan.matchCount(#"ListEditorAreaRow\("#, in: edit) == 1)
        #expect(CadenceSourceScan.matchCount(#"ListEditorAreaRow\("#, in: create) == 1)
        #expect(CadenceSourceScan.matchCount(#"Self\.applyOwnership\("#, in: edit) == 1)
        #expect(CadenceSourceScan.matchCount(#"Self\.makeNewProject\("#, in: create) == 1)
        #expect(CadenceSourceScan.matchCount(#"Project\(name:[^)]*\barea:"#, in: create) == 1)
    }
}
#endif
