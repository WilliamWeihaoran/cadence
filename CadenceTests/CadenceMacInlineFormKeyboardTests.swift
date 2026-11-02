import Foundation
import Testing
@testable import Cadence

/// **[[T-10016]] and [[T-10017]]: two Mac in-pane forms that ignored the key their siblings answer.**
///
/// - The Links tab's add form (`AddLinkBar`) had a Cancel button and nothing listening for Escape,
///   while the inline task composer and the list-note rename both leave on Escape. It now cancels
///   through the same `onCancel`, focus-scoped, never as a window-wide `.cancelAction`.
/// - The Focus Log Session popover's hours and minutes fields ignored Return, while Return commits
///   the Kanban column name, an inspector subtask and a saved link's URL. Return now logs, through
///   the same `submitLog()` as the Log button; Discard takes no key.
///
/// Source reads in `CadenceSettingsSheetKeyboardTests`' style: no unit test can press a key in a
/// pane or a popover. Read from the declaration's own body, so a handler elsewhere in the file
/// cannot answer.
struct CadenceMacInlineFormKeyboardTests {
    private static func compactBody(_ declaration: String, in path: String) throws -> String {
        let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
        let body = try #require(CadenceSourceScan.declarationBody(declaration, in: source))
        return body.filter { !$0.isWhitespace }
    }

    private static func count(_ needle: String, in compact: String) -> Int {
        compact.components(separatedBy: needle).count - 1
    }

    /// [[T-10061]]: the list page's "+ Section" row (shared, drawn on the Mac list page and both
    /// iOS list pages) had an xmark and nothing listening for Escape.
    @Test func sectionCreationRowCancelsOnEscapeThroughItsOwnCancel() throws {
        let row = try Self.compactBody(
            "struct CadenceSectionCreationRow: View",
            in: "Cadence/Shared/Components/CadenceSectionCreationRow.swift"
        )
        #expect(row.contains("TextField(\"Sectionname\""), "the slice is not the section row")
        #expect(
            row.contains("#ifos(macOS).onExitCommand(perform:cancel)#endif"),
            "Escape from the focused Section name field must cancel through cancel()"
        )
        #expect(
            row.contains(".onKeyPress(.escape){cancel()return.handled}"),
            "Escape must also cancel along SwiftUI's focus route"
        )
        #expect(Self.count("Button(action:cancel)", in: row) == 1, "the xmark no longer cancels through cancel()")
    }

    @Test func addLinkFormCancelsOnEscapeThroughItsOwnCancel() throws {
        let bar = try Self.compactBody(
            "private struct AddLinkBar: View",
            in: "Cadence/macOS/Views/LinksView.swift"
        )
        #expect(
            bar.contains(".onExitCommand(perform:onCancel)"),
            "Escape from a focused add-link field must cancel through onCancel"
        )
        #expect(
            bar.contains(".onKeyPress(.escape){onCancel()return.handled}"),
            "Escape must also cancel along SwiftUI's focus route"
        )
        #expect(
            Self.count(".keyboardShortcut(", in: bar) + Self.count("shortcut:.", in: bar) == 0,
            "a key equivalent would answer Escape or Return anywhere in the window"
        )
    }

    @Test func logSessionFieldsLogOnReturnAndDiscardTakesNoKey() throws {
        let popover = try Self.compactBody(
            "struct LogSessionPopover: View",
            in: "Cadence/macOS/Views/FocusLogSessionPopovers.swift"
        )
        #expect(
            popover.contains(".onSubmit(submitLog)"),
            "Return in the hours or minutes field must log"
        )
        #expect(
            popover.contains("privatefuncsubmitLog(){onLog(logHours,logMinutes,markComplete)}"),
            "Return and the Log button must read the same typed figures"
        )
        #expect(
            popover.contains("size:.compact){submitLog()}"),
            "the Log button must go through submitLog()"
        )
        #expect(
            Self.count(".keyboardShortcut(", in: popover) + Self.count("shortcut:.", in: popover) == 0,
            "Discard throws the session away and must take no key"
        )
    }

    /// **[[T-10033]]: the Settings tag and context editors answer Return and Escape.** The Create
    /// Tag fields, a tag card's inline editor and a context row's inline rename all had a Save or
    /// Create button and nothing listening for either key, while the tag picker's "Find or create
    /// tag" field creates on Return and the add-link form cancels on Escape.
    @Test func settingsTagCreatorCreatesOnReturn() throws {
        let section = try Self.compactBody(
            "struct SettingsTagsSection: View",
            in: "Cadence/macOS/Views/SettingsTagsSection.swift"
        )
        #expect(
            section.contains("text:$newTagDescription)}.onSubmit(createTag)"),
            "Return in the Create Tag name or description field must create"
        )
        #expect(
            Self.count(".keyboardShortcut(", in: section) + Self.count("shortcut:.", in: section) == 0,
            "a key equivalent would answer Return anywhere in the Settings window"
        )
    }

    @Test func settingsTagCardEditorSavesOnReturnAndCancelsOnEscape() throws {
        let row = try Self.compactBody(
            "private struct SettingsTagRow: View",
            in: "Cadence/macOS/Views/SettingsTagsSection.swift"
        )
        #expect(
            row.contains(".frame(width:96)}}.onSubmit(requestSave)}"),
            "Return in the tag card's name, description or hex field must save through requestSave"
        )
        #expect(row.contains(".onExitCommand(perform:cancelEditing)"), "Escape from a focused field must cancel")
        #expect(
            row.contains(".onKeyPress(.escape){cancelEditing()return.handled}"),
            "Escape must also cancel along SwiftUI's focus route"
        )
        #expect(row.contains("action:cancelEditing){Text(\"Cancel\")}"), "the Cancel button and Escape share cancelEditing")
        #expect(Self.count(".keyboardShortcut(", in: row) + Self.count("shortcut:.", in: row) == 0)
    }

    @Test func settingsContextRenameSavesOnReturnAndCancelsOnEscape() throws {
        let row = try Self.compactBody(
            "struct ContextSettingsRow: View",
            in: "Cadence/macOS/Views/SettingsSupportViews.swift"
        )
        #expect(
            row.contains("TextField(\"Contextname\",text:$editName).textFieldStyle(.plain).font(.system(size:13)).foregroundStyle(Theme.text).cadenceSettingsWell().onSubmit(saveEdit)"),
            "Return in the context rename field must save through saveEdit"
        )
        #expect(row.contains(".onExitCommand(perform:cancelEditing)"), "Escape from the rename field must cancel")
        #expect(
            row.contains(".onKeyPress(.escape){cancelEditing()return.handled}"),
            "Escape must also cancel along SwiftUI's focus route"
        )
        #expect(
            row.contains("title:\"Cancel\",role:.ghost,size:.compact,action:cancelEditing)"),
            "the Cancel button and Escape share cancelEditing"
        )
        #expect(
            row.contains("privatefunccancelEditing(){withAnimation(.easeInOut(duration:0.15)){isEditing=false}}"),
            "cancelEditing must close the editor"
        )
        #expect(Self.count(".keyboardShortcut(", in: row) + Self.count("shortcut:.", in: row) == 0)
    }
}

/// **[[T-10032]]: every tag editor names its fields "Tag name" and "Optional description".** The Mac
/// creator said "Name" / "Optional description", the Mac Settings card editor and the tag picker's
/// Edit Tag sheet "Name" / "Description", and iOS "Tag name" / "Optional description" in both. One
/// shared copy now feeds all five editors' fields.
struct CadenceTagEditorPlaceholderTests {
    @Test func theSharedPlaceholdersAreIOSsWording() {
        #expect(CadenceTagSettingsCopy.nameFieldPlaceholder == "Tag name")
        #expect(CadenceTagSettingsCopy.descriptionFieldPlaceholder == "Optional description")
    }

    @Test func everyTagEditorReadsTheSharedPlaceholders() throws {
        let editors: [(path: String, name: Int, description: Int)] = [
            ("Cadence/macOS/Views/SettingsTagsSection.swift", 2, 2),
            ("Cadence/macOS/Views/TagPickerPopoverViews.swift", 1, 1),
            ("Cadence/iOS/iOSSettingsTagsSection.swift", 2, 2),
        ]
        for editor in editors {
            let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(editor.path))
            let compact = source.filter { !$0.isWhitespace }
            #expect(
                compact.components(separatedBy: "(CadenceTagSettingsCopy.nameFieldPlaceholder,text:").count - 1 == editor.name,
                "\(editor.path) names a tag-name field with its own literal"
            )
            #expect(
                compact.components(separatedBy: "(CadenceTagSettingsCopy.descriptionFieldPlaceholder,text:").count - 1 == editor.description,
                "\(editor.path) names a tag-description field with its own literal"
            )
            for stale in [#"("Name",text:"#, #"("Description",text:"#, #"("Tagname",text:"#, #"("Optionaldescription",text:"#] {
                #expect(!compact.contains(stale), "\(editor.path) still spells \(stale)")
            }
        }
    }
}
