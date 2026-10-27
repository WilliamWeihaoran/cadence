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
    private static let macSettingsPath = "Cadence/macOS/Views/SettingsTagsSection.swift"
    private static let iosSettingsTagsPath = "Cadence/iOS/iOSSettingsTagsSection.swift"
    private static let iosSwatchPath = "Cadence/iOS/iOSSettingsComponents.swift"

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

    /// T-7337: every row's edit control read "Edit tag", so a picker of eight tags was eight
    /// identical buttons to VoiceOver and to the tooltip.
    @Test func macPopoverEditControlIsNamedForItsTag() throws {
        #expect(CadenceTagChipStyle.editControlLabel(name: "Work", slug: "work") == "Edit Work")
        #expect(CadenceTagChipStyle.editControlLabel(name: "  ", slug: "deep-work") == "Edit deep-work",
                "an unnamed tag falls back to its slug, as the chip does")
        let row = try Self.compactBody("private func tagRow(_ tag: Tag) -> some View", in: Self.macPopoverPath)
        #expect(row.contains("beginEditing(tag)"), "non-vacuity: the row still draws its edit control")
        #expect(row.contains(".cadenceControlLabel(CadenceTagChipStyle.editControlLabel(for:tag))"),
                "the Mac tag picker's edit control is not named for its tag")
        #expect(!row.contains(#".cadenceControlLabel("Edittag")"#))
    }

    /// T-7361: the T-7337 gap on both Settings tag lists, where every row's pencil read "Edit tag".
    @Test func settingsTagListEditControlsAreNamedForTheirTag() throws {
        let mac = try Self.compactBody("private var displayContent: some View", in: Self.macSettingsPath)
        #expect(mac.contains("startEditing()"), "non-vacuity: the Mac Settings row still draws its edit control")
        #expect(mac.contains(#"rowButton(icon:"pencil",accessibilityLabel:CadenceTagChipStyle.editControlLabel(for:tag))"#),
                "the Mac Settings tag row's edit control is not named for its tag")
        #expect(!mac.contains(#"accessibilityLabel:"Edittag""#))

        let ios = try Self.compactBody("private var displayContent: some View", in: Self.iosSettingsTagsPath)
        #expect(ios.contains("isEditing=true"), "non-vacuity: the iOS Settings row still draws its edit control")
        #expect(ios.contains(#"iOSIconButton(systemImage:"pencil",accessibilityLabel:CadenceTagChipStyle.editControlLabel(for:tag))"#),
                "the iOS Settings tag row's edit control is not named for its tag")
        #expect(!ios.contains(#"accessibilityLabel:"Edittag""#))
    }

    /// T-7382: the same gap on the rows' Archive / Restore buttons, which read "Archive tag" and
    /// "Restore tag" on every row.
    @Test func settingsTagListArchiveAndRestoreControlsAreNamedForTheirTag() throws {
        #expect(CadenceTagChipStyle.archiveControlLabel(name: "Work", slug: "work") == "Archive Work")
        #expect(CadenceTagChipStyle.restoreControlLabel(name: "Work", slug: "work") == "Restore Work")
        #expect(CadenceTagChipStyle.archiveControlLabel(name: " ", slug: "deep-work") == "Archive deep-work",
                "an unnamed tag falls back to its slug, as the chip does")
        #expect(CadenceTagChipStyle.restoreControlLabel(name: " ", slug: "deep-work") == "Restore deep-work")

        let mac = try Self.compactBody("private var displayContent: some View", in: Self.macSettingsPath)
        #expect(mac.contains("action:onArchive") && mac.contains("action:onRestore"),
                "non-vacuity: the Mac Settings row still draws both archive controls")
        #expect(mac.contains(#"accessibilityLabel:CadenceTagChipStyle.restoreControlLabel(for:tag),action:onRestore"#),
                "the Mac Settings tag row's restore control is not named for its tag")
        #expect(mac.contains(#"accessibilityLabel:CadenceTagChipStyle.archiveControlLabel(for:tag),action:onArchive"#),
                "the Mac Settings tag row's archive control is not named for its tag")
        #expect(!mac.contains(#""Archivetag""#) && !mac.contains(#""Restoretag""#))

        let ios = try Self.compactBody("private var displayContent: some View", in: Self.iosSettingsTagsPath)
        #expect(ios.contains("isArchivedList?restore():archive()"),
                "non-vacuity: the iOS Settings row still draws its archive control")
        #expect(ios.contains("accessibilityLabel:isArchivedList?CadenceTagChipStyle.restoreControlLabel(for:tag):CadenceTagChipStyle.archiveControlLabel(for:tag)"),
                "the iOS Settings tag row's archive / restore control is not named for its tag")
        #expect(!ios.contains(#""Archivetag""#) && !ios.contains(#""Restoretag""#))
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

    @Test func macEditTagSheetUsesTheNamedSettingsStrip() throws {
        let sheet = try Self.compactBody("private struct TagEditSheet: View", in: Self.macPopoverPath)
        #expect(sheet.contains("TagColorSwatches(selectedHex:$colorHex)"))
        #expect(
            !sheet.contains("ForEach(TagSupport.colorOptions"),
            "The Edit tag sheet must not draw its own unnamed swatch copy again"
        )

        let strip = try Self.compactBody("struct TagColorSwatches: View", in: Self.macSettingsPath)
        #expect(strip.contains(#".accessibilityLabel(isSelected?"Selectedcolor":"Usethiscolor")"#))
        #expect(strip.contains(".accessibilityAddTraits(isSelected?.isSelected:[])"))
    }

    @Test func iosSettingsSwatchIsNamedByWhatATapDoes() throws {
        let strip = try Self.compactBody("struct iOSSettingsColorSwatchRow: View", in: Self.iosSwatchPath)
        #expect(strip.contains(#".accessibilityLabel(isSelected(option)?"Selectedcolor":"Usethiscolor")"#))
        #expect(strip.contains(".accessibilityAddTraits(isSelected(option)?.isSelected:[])"))
        #expect(!strip.contains(".accessibilityLabel(option)"), "VoiceOver must not read the bare hex")
    }
}
