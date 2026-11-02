import Foundation
import SwiftUI
import Testing
@testable import Cadence

/// [[T-10008]]: a note's heading outline reads its depth by weight as well as indent, on both
/// platforms, from one shared rule.
///
/// The Mac's outline popover drew `#`/`##` semibold in `Theme.text` and deeper headings regular in
/// `Theme.muted`; the iOS outline sheet drew every level regular in `Theme.text`. The rule now lives
/// in `CadenceNoteOutlineRowStyle` and both rows read it. `Cadence/iOS/` is `#if os(iOS)` and this
/// target's default leg builds for macOS, so the two call sites are source reads with comments
/// blanked, each with a non-vacuity anchor.
@Suite
struct CadenceNoteOutlineRowStyleTests {

    @Test func topLevelHeadingsAreSemiboldTextAndDeeperOnesRegularMuted() {
        #expect(CadenceNoteOutlineRowStyle.weight(level: 1) == .semibold)
        #expect(CadenceNoteOutlineRowStyle.weight(level: 2) == .semibold)
        #expect(CadenceNoteOutlineRowStyle.weight(level: 3) == .regular)
        #expect(CadenceNoteOutlineRowStyle.weight(level: 6) == .regular)

        #expect(CadenceNoteOutlineRowStyle.color(level: 1) == Theme.text)
        #expect(CadenceNoteOutlineRowStyle.color(level: 2) == Theme.text)
        #expect(CadenceNoteOutlineRowStyle.color(level: 3) == Theme.muted)
        #expect(Theme.text != Theme.muted, "the two colours must differ for the pin to mean anything")
    }

    @Test func indentStepsOncePerLevelBelowTheFirst() {
        #expect(CadenceNoteOutlineRowStyle.indent(level: 1) == 0)
        #expect(CadenceNoteOutlineRowStyle.indent(level: 3) == 2 * CadenceNoteOutlineRowStyle.indentStep)
        #expect(CadenceNoteOutlineRowStyle.indent(level: 0) == 0)
    }

    private func body(_ declaration: String, in path: String) throws -> String {
        let source = try CadenceSourceScan.sourceFile(path)
        let found = CadenceSourceScan.declarationBody(declaration, in: source)
        #expect(found != nil, "\(declaration) not found in \(path); the scan reads nothing")
        return (found ?? "").filter { !$0.isWhitespace }
    }

    @Test func theIOSOutlineSheetRowReadsTheSharedStyle() throws {
        let sheet = try body(
            "private var outlineSheet: some View",
            in: "Cadence/iOS/iOSMarkdownEditingSurface.swift"
        )
        #expect(sheet.contains("Text(item.title)"), "the scan no longer reaches the outline row")
        #expect(sheet.contains(".fontWeight(CadenceNoteOutlineRowStyle.weight(level:item.level))"))
        #expect(sheet.contains(".foregroundStyle(CadenceNoteOutlineRowStyle.color(level:item.level))"))
        #expect(sheet.contains(".padding(.leading,CadenceNoteOutlineRowStyle.indent(level:item.level))"))
    }

    @Test func theMacOutlineRowReadsTheSameStyle() throws {
        let row = try body(
            "private struct NoteOutlineJumpRow: View",
            in: "Cadence/macOS/Views/NoteEditorAccessoryViews.swift"
        )
        #expect(row.contains("Text(item.title)"), "the scan no longer reaches the outline row")
        #expect(row.contains("weight:CadenceNoteOutlineRowStyle.weight(level:item.level)"))
        #expect(row.contains(".foregroundStyle(CadenceNoteOutlineRowStyle.color(level:item.level))"))
        #expect(row.contains(".padding(.leading,CadenceNoteOutlineRowStyle.indent(level:item.level))"))
        #expect(!row.contains("item.level<=2"), "a second spelling of the rule is back")
    }
}
