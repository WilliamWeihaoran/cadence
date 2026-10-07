import Foundation
import Testing
@testable import Cadence

struct CadenceCodexListCreationChoiceTests {
    @Test func codexCreationChoiceReachesTheSaveWhileEditingKeepsItsOriginalType() throws {
        let source = try CadenceSourceScan.strippedSourceReader()("Cadence/iOS/iOSListEditorViews.swift")
        #expect(source.contains("struct iOSListEditorSheet: View"))
        let resolved = try #require(CadenceSourceScan.declarationBody("private var resolvedMode:", in: source))
        #expect(resolved.contains("guard !isEditing else { return mode }"))
        #expect(resolved.contains("return createsProject ? .newProject : .newArea"))
        let projectMode = try #require(CadenceSourceScan.declarationBody("private var isProjectMode:", in: source))
        #expect(projectMode.contains("switch resolvedMode"), "project-only fields must follow the choice too")
        let body = try #require(CadenceSourceScan.declarationBody("var body: some View", in: source))
        let chooser = try #require(CadenceSourceScan.declarationBody("if !isEditing", in: body))
        #expect(chooser.contains("iOSSegmentedChoice("))
        #expect(chooser.contains("options: [(false, \"Area\"), (true, \"Project\")]"))
        #expect(chooser.contains("selection: $createsProject"))
        let save = try #require(CadenceSourceScan.declarationBody("private func save()", in: source))
        #expect(save.contains("switch resolvedMode"))
        #expect(save.contains("Area(name: trimmedName, context: selectedContext"))
        #expect(save.contains("Project(name: trimmedName, context: selectedContext, area: selectedArea"))
        #expect(save.contains("try CadencePendingChangePersistence.commitInsert(of: area, in: modelContext)"))
        #expect(save.contains("try CadencePendingChangePersistence.commitInsert(of: project, in: modelContext)"))
    }

    @Test func codexBothEntryModesSeedAndSwitchingTypePreservesTheDraftAndCustomAppearance() throws {
        let source = try CadenceSourceScan.strippedSourceReader()("Cadence/iOS/iOSListEditorViews.swift")
        let load = try #require(CadenceSourceScan.declarationBody("private func load()", in: source))
        #expect(load.contains("case .newArea:\n            createsProject = false"))
        #expect(load.contains("case .newProject:\n            createsProject = true"))
        #expect(load.components(separatedBy: "selectedContextID = seededContextValue").count - 1 == 2)
        let change = try #require(CadenceSourceScan.declarationBody(".onChange(of: createsProject)", in: source))
        #expect(change.contains("guard !isEditing else { return }"))
        #expect(change.contains("if icon == oldIcon"))
        #expect(change.contains("if colorHex == oldColor"))
        #expect(change.contains("showAreaPicker = false"))
        for field in ["selectedContextID", "selectedAreaID", "name", "details", "sectionDrafts", "hasProjectDueDate"] {
            #expect(!change.contains(field + " ="), "type selection must not clear \(field)")
        }
    }
}
