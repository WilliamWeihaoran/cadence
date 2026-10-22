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

    /// **T-2054's remainder: the Lists page asks the type question once, in the sheet that owns it.**
    ///
    /// The ticket's own sentence was "the one-call-site `iOSListEditorMode.newProject` problem".
    /// `iOSListCreateButtonsRow` was that call site — "New Area" beside "New Project", drawn by
    /// `iOSListsView` and `iOSListsRegularPane` — and it is the reason the toggle the two tests
    /// above pin could land and still change nothing a user sees: the page decided the type before
    /// the sheet could offer it. The row is one "New List" door on `.newArea` now, which is the
    /// editor's *entry* mode exactly as the iPad column's `+` already used it.
    ///
    /// **Both halves, because either alone passes on a tree nobody wants.** One door without the
    /// absence sweep is satisfied by a second button somewhere else on the page; the absence
    /// without the door is a Lists page that cannot make a list at all.
    ///
    /// Source shape, and stated as such: the macOS unit target never compiles `Cadence/iOS/`, so
    /// nothing here renders a `View` — see `Cadence/iOS/AGENTS.md`.
    @Test func theListsPageOffersOneCreateDoorAndNothingTapsNewProjectAnyMore() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let support = try read("Cadence/iOS/iOSListSupportViews.swift")
        #expect(support.contains("struct iOSListCreateButtonsRow: View"), "non-vacuity: wrong file read")

        let row = try #require(CadenceSourceScan.declarationBody("struct iOSListCreateButtonsRow: View", in: support))
        #expect(row.components(separatedBy: "iOSActionButton(").count - 1 == 1,
                "the Lists page draws more than one create button again, so it asks the type before the sheet does")
        #expect(row.contains("title: \"New List\""),
                "the one door stopped naming the sheet it opens, which is titled New List")
        #expect(row.contains("editorMode = .newArea"),
                "the Lists page's create door no longer opens the editor on its entry mode")

        // The absence, swept over the whole app rather than over this one file: `.newProject` is
        // reachable only from `resolvedMode`, which is the segment's answer, so no surface can
        // commit a user to a Project before the sheet has drawn its first control.
        let instrument = try CadenceScanInstrument(
            "newProject reference",
            fires: "editorMode = .newProject",
            andNotOn: "editorMode = .newArea",
            by: { $0.contains(".newProject") }
        )
        let paths = try CadenceSourceScan.swiftFiles(under: "Cadence")
        #expect(paths.contains("Cadence/iOS/iOSListSupportViews.swift"))
        let hits = try instrument.sweep(
            paths,
            atLeast: 300,
            including: "Cadence/iOS/iOSListEditorViews.swift",
            read: read
        )
        #expect(hits == ["Cadence/iOS/iOSListEditorViews.swift"],
                "`.newProject` is named outside the editor that resolves it: \(hits.joined(separator: ", "))")
    }
}
