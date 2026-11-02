import Foundation
import Testing
@testable import Cadence

/// [[T-9991]], [[T-9992]], [[T-9993]]: four iOS sheets that drew their bar chrome differently from
/// every other iOS sheet.
///
/// - The Context editor tinted its Cancel `Theme.muted`, the one grey Cancel among fourteen
///   `.cancellationAction` items, so it read as a disabled control.
/// - The folder sheet (New Folder Note / Move to Folder) put its commit in `.primaryAction` rather
///   than `.confirmationAction`, and declared no tint, so Cancel and the commit took the system
///   blue on the iPad, where no shell tint sits above the presenter.
/// - The event edit sheet draws the same `CadenceSchedulePanel` the quick-create sheet does, and
///   only the quick-create sheet declared a tint scope; the `[[link]]` reference picker declared
///   none either.
///
/// `Cadence/iOS/` is `#if os(iOS)` and this target's default leg builds for macOS, so these are
/// source reads of the named declarations, comments blanked, each with a non-vacuity anchor.
@Suite
struct CadenceIOSSheetToolbarTintTests {

    private func body(_ declaration: String, in path: String) throws -> String {
        let source = try CadenceSourceScan.sourceFile(path)
        let found = CadenceSourceScan.declarationBody(declaration, in: source)
        #expect(found != nil, "\(declaration) not found in \(path); the scan reads nothing")
        return found ?? ""
    }

    /// Whitespace-free, so a reformat cannot break a needle.
    private func squeezed(_ text: String) -> String {
        text.filter { !$0.isWhitespace }
    }

    @Test func theContextEditorsCancelIsBlueLikeEveryOtherSheetsCancel() throws {
        let cancel = squeezed(try body(
            "ToolbarItem(placement: .cancellationAction)",
            in: "Cadence/iOS/iOSSettingsContextSection.swift"
        ))
        #expect(cancel.contains("Button(\"Cancel\")"), "the scan no longer reaches the Cancel item")
        #expect(cancel.contains(".tint(Theme.blue)"))
        #expect(!cancel.contains("Theme.muted"))
    }

    @Test func theFolderSheetCommitsFromTheConfirmationSlotInsideItsOwnTint() throws {
        let sheet = squeezed(try body(
            "struct iOSNoteFolderSheet: View",
            in: "Cadence/iOS/iOSListNotesView.swift"
        ))
        #expect(sheet.contains("Button(request.actionTitle,action:save)"), "the scan no longer reaches the commit")
        #expect(sheet.contains("ToolbarItem(placement:.confirmationAction){Button(request.actionTitle,action:save)"))
        #expect(!sheet.contains(".primaryAction"))
        #expect(sheet.contains("}.tint(Theme.blue).preferredColorScheme(.dark)"))
    }

    @Test func theEventEditSheetDeclaresTheTintScopeTheQuickCreateSheetDoes() throws {
        let quickCreate = squeezed(try body(
            "var body: some View",
            in: "Cadence/iOS/iOSCalendarQuickCreateSheet.swift"
        ))
        #expect(quickCreate.contains(".tint(Theme.blue)"), "the sibling no longer declares the scope this pins against")

        let edit = squeezed(try body(
            "var body: some View",
            in: "Cadence/iOS/iOSCalendarEventEditSheet.swift"
        ))
        #expect(edit.contains("CadenceSchedulePanel("), "the scan no longer reaches the edit sheet's panel")
        #expect(edit.contains(".tint(Theme.blue).preferredColorScheme(.dark)"))
    }

    @Test func theReferencePickerSheetDeclaresItsOwnTintScope() throws {
        let picker = squeezed(try body(
            "struct iOSMarkdownReferencePickerSheet: View",
            in: "Cadence/iOS/iOSMarkdownAccessoryViews.swift"
        ))
        #expect(picker.contains("ToolbarItem(placement:.cancellationAction)"), "the scan no longer reaches the picker's bar")
        #expect(picker.contains("}.tint(Theme.blue).preferredColorScheme(.dark)"))
    }
}
