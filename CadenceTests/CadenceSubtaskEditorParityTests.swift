import SwiftUI
import Testing
@testable import Cadence

/// Two editor-side subtask drifts between the Mac inspector and iOS's detail sheet, closed together.
///
/// - [[T-16627]]: an open subtask's title was `Theme.muted` in the Mac inspector and `Theme.text` in
///   the iOS sheet. `CadenceSubtaskTitleInk` decides it once: the editor draws `Theme.text`, a row or
///   card preview keeps `Theme.muted`, and a finished subtask is `Theme.dim` on either.
/// - [[T-16626]]: iOS's "Add subtask" field dropped the keyboard after every add while the Mac
///   composer kept first responder. The on-screen half is owed to a sighting; this pins the wiring.
struct CadenceSubtaskEditorParityTests {
    private static let tasksPanelSupportPath = "Cadence/macOS/Views/TasksPanelSupportViews.swift"
    private static let iOSTaskDetailComponentsPath = "Cadence/iOS/iOSTaskDetailComponents.swift"
    private static let iOSTaskRowActionViewsPath = "Cadence/iOS/iOSTaskRowActionViews.swift"
    private static let iOSTaskDetailSheetSectionsPath = "Cadence/iOS/iOSTaskDetailSheetSections.swift"

    private func body(_ declaration: String, in path: String) throws -> String {
        let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
        return try #require(CadenceSourceScan.declarationBody(declaration, in: source), "\(declaration)")
    }

    // MARK: - T-16627: one subtask title ink

    @Test func theEditorDrawsAnOpenSubtaskInTextAndThePreviewKeepsMuted() {
        #expect(CadenceSubtaskTitleInk.editor.color(isDone: false) == Theme.text)
        #expect(CadenceSubtaskTitleInk.preview.color(isDone: false) == Theme.muted)
        // The two hosts differ only while a subtask is open; done is dim on both.
        #expect(CadenceSubtaskTitleInk.editor.color(isDone: true) == Theme.dim)
        #expect(CadenceSubtaskTitleInk.preview.color(isDone: true) == Theme.dim)
        #expect(CadenceSubtaskTitleInk.editor.color(isDone: false) != CadenceSubtaskTitleInk.preview.color(isDone: false))
    }

    /// The Mac row is both hosts: the inspector passes `editsTitle: true`, the task row does not.
    /// Both title branches (field and text) read the one ink, so neither can keep its own literal.
    @Test func theMacSubtaskRowChoosesItsInkByWhetherItIsTheEditor() throws {
        let row = try body("struct SubtaskRow: View", in: Self.tasksPanelSupportPath)
        #expect(row.contains("private var titleInk: CadenceSubtaskTitleInk { editsTitle ? .editor : .preview }"))
        #expect(CadenceSourceScan.matchCount(#"\.foregroundStyle\(titleInk\.color\(isDone: subtask\.isDone\)\)"#, in: row) == 2)
        #expect(!row.contains("Theme.muted"))
    }

    @Test func everyOtherSubtaskTitleReadsTheSharedInk() throws {
        let sheetRow = try body("struct iOSSubtaskRow: View", in: Self.iOSTaskDetailComponentsPath)
        #expect(sheetRow.contains(".foregroundStyle(CadenceSubtaskTitleInk.editor.color(isDone: subtask.isDone))"))
        #expect(!sheetRow.contains("Theme.dim : Theme.text"))

        let taskRowPreview = try body("struct iOSTaskRowSubtaskRow: View", in: Self.iOSTaskRowActionViewsPath)
        #expect(taskRowPreview.contains(".foregroundStyle(CadenceSubtaskTitleInk.preview.color(isDone: false))"))
        #expect(!taskRowPreview.contains("Theme.muted"))
    }

    // MARK: - T-16626: the iOS composer keeps the keyboard

    @Test func theIOSComposerTakesFocusBackAfterANonEmptySubmit() throws {
        let section = try body("struct iOSTaskSubtasksSection: View", in: Self.iOSTaskDetailSheetSectionsPath)
        #expect(section.contains("@FocusState private var isComposerFocused: Bool"))
        #expect(section.contains(".focused($isComposerFocused)"))
        #expect(section.contains(".onSubmit(submitFromKeyboard)"))
        // Return no longer goes straight to the add, which is what let the field resign for good.
        #expect(!section.contains(".onSubmit(onAdd)"))

        let submit = try #require(CadenceSourceScan.declarationBody("private func submitFromKeyboard()", in: section))
        // Read before the add: a landed add clears the field, so asking afterwards would always
        // answer "nothing to add" and the keyboard would go every time.
        let readsEntry = try #require(submit.range(of: "let addsSomething = canAddSubtask"))
        let adds = try #require(submit.range(of: "onAdd()"))
        #expect(readsEntry.lowerBound < adds.lowerBound)
        #expect(submit.contains("guard addsSomething else { return }"))
        #expect(submit.contains("isComposerFocused = true"))
    }
}
