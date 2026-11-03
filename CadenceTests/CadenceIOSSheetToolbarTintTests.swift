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

    /// [[T-9975]]: the palette's blue was declared on the iPhone's tab shell alone, so the iPad
    /// sidebar shell -- and the task inspector, hosted by the root outside both shells -- drew the
    /// system blue wherever a control inherits its tint. One declaration on the root now, wrapping
    /// both shells and the inspector host.
    @Test func theRootDeclaresThePalettesTintAboveBothShellsAndTheInspectorHost() throws {
        let root = squeezed(try body(
            "struct iOSRootView: View",
            in: "Cadence/iOS/iOSRootView.swift"
        ))
        let ipadShell = root.range(of: "iPadMacStyleRootShell(selection:")
        let phoneShell = root.range(of: "iOSCompactRootShell(")
        let inspectorHost = root.range(of: ".iOSTaskInspectorHost()")
        let tint = root.range(of: ".tint(Theme.blue)")
        #expect(ipadShell != nil && phoneShell != nil && inspectorHost != nil,
                "the scan no longer reaches the two shells and the inspector host")
        #expect(tint != nil, "iOSRootView declares no tint above its shells")
        if let tint, let inspectorHost, let ipadShell, let phoneShell {
            // A modifier wraps what precedes it, so the tint must come after all three.
            #expect(inspectorHost.upperBound <= tint.lowerBound)
            #expect(ipadShell.upperBound <= tint.lowerBound)
            #expect(phoneShell.upperBound <= tint.lowerBound)
        }
    }

    @Test func theReferencePickerSheetDeclaresItsOwnTintScope() throws {
        let picker = squeezed(try body(
            "struct iOSMarkdownReferencePickerSheet: View",
            in: "Cadence/iOS/iOSMarkdownAccessoryViews.swift"
        ))
        #expect(picker.contains("ToolbarItem(placement:.cancellationAction)"), "the scan no longer reaches the picker's bar")
        #expect(picker.contains("}.tint(Theme.blue).preferredColorScheme(.dark)"))
    }

    /// [[T-8587]]: the two note editors Search and `[[link]]`s open put a confirming Done in
    /// `.confirmationAction` (trailing), where the system puts it on every iOS sheet, not in
    /// `.cancellationAction` (leading), where both had it until 2026-11-02.
    @Test func theNoteEditorsConfirmFromTheTrailingDoneSlot() throws {
        for (declaration, path) in [
            ("struct iOSEventNoteEditorSheet: View", "Cadence/iOS/iOSEventNoteEditorSheet.swift"),
            ("struct iOSNoteEditorCover: View", "Cadence/iOS/iOSNotesView.swift")
        ] {
            let sheet = squeezed(try body(declaration, in: path))
            #expect(sheet.contains("Button(\"Done\")"), "the scan no longer reaches \(declaration)'s Done")
            #expect(sheet.contains("ToolbarItem(placement:.confirmationAction){Button(\"Done\")"), "\(declaration)")
            #expect(!sheet.contains("ToolbarItem(placement:.cancellationAction){Button(\"Done\")"), "\(declaration)")
        }
    }
}
