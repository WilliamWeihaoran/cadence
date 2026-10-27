import Foundation
import Testing
@testable import Cadence

/// **T-7334 and T-7335: the tag pickers and the tag colour strips say what they draw.**
///
/// T-7334: the three tag picker rows — the Mac `#` popover (`TagPickerPopover.tagRow`), the Mac
/// title's inline `#` picker (`InlineTagPickerRow`) and the iOS task sheet's picker
/// (`iOSTaskTagPickerPopover.tagRow`) — draw a chosen tag with a tint and a checkmark and told
/// VoiceOver nothing, so every row read the same whether the tag was on or off. Each row's button
/// now carries `.isSelected`, the T-7267 / T-7292 precedent.
///
/// T-7335: two swatch strips missed the convention `CadenceIconOnlyColorSwatchAccessibilityTests`
/// describes ("Use this color" / "Selected color", T-5003's words) while that suite's own prose
/// listed them as following it. The Mac picker's Edit tag sheet drew its own unnamed copy of
/// Settings' `TagColorSwatches` and now uses that view; iOS's `iOSSettingsColorSwatchRow` read the
/// bare hex and now names the swatch by what a tap does.
///
/// Source reads in `CadenceNoteActionSheetKeyboardTests`' style: the rows are private views inside
/// popovers, and no unit test can ask VoiceOver what it heard.
struct CadenceTagPickerAccessibilityTests {
    private static let macPopoverPath = "Cadence/macOS/Views/TagPickerPopoverViews.swift"
    private static let macInlinePath = "Cadence/macOS/Views/TaskTitleInlineTagPicker.swift"
    private static let iosPickerPath = "Cadence/iOS/iOSTaskDetailComponents.swift"

    private static func compactBody(_ declaration: String, in path: String) throws -> String {
        let source = try CadenceSourceScan.sourceFile(path)
        let body = try #require(CadenceSourceScan.declarationBody(declaration, in: source))
        return body.filter { !$0.isWhitespace }
    }

    @Test func macPopoverTagRowSaysWhichTagsAreOn() throws {
        let row = try Self.compactBody("private func tagRow(_ tag: Tag) -> some View", in: Self.macPopoverPath)
        #expect(
            row.contains(".buttonStyle(.cadencePlain).accessibilityAddTraits(selected?.isSelected:[])"),
            "VoiceOver must hear which tags the Mac tag picker has on, on the row's own button"
        )
    }

    @Test func macInlinePickerRowSaysWhichTagsAreOn() throws {
        let row = try Self.compactBody("private struct InlineTagPickerRow: View", in: Self.macInlinePath)
        #expect(
            row.contains(".buttonStyle(.cadencePlain).accessibilityAddTraits(isSelected?.isSelected:[])"),
            "VoiceOver must hear which tags the title's inline # picker has on"
        )
    }

    @Test func iosTaskTagPickerRowSaysWhichTagsAreOn() throws {
        let row = try Self.compactBody("private func tagRow(_ tag: Tag) -> some View", in: Self.iosPickerPath)
        #expect(
            row.contains(".buttonStyle(.iosPressable).accessibilityAddTraits(isSelected?.isSelected:[])"),
            "VoiceOver must hear which tags the iOS task tag picker has on"
        )
    }
}
