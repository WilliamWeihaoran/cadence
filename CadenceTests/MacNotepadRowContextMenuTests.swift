// macOS only: the scanned `NotesView.swift` is macOS app code.
#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// **[[T-5806]] — a Notepad note's row on the Mac Notes page answers a right-click** with Copy Note
/// Link and Delete, as a list's note rows do, Delete going through the page's own confirmed
/// `deleteNote(_:)`. A source pin, because the menu is a modifier on a `private` view's row.
struct MacNotepadRowContextMenuTests {
    @Test func theNotepadRowCarriesCopyLinkAndDelete() throws {
        let source = try CadenceSourceScan.strippedSourceReader()("Cadence/macOS/Views/NotesView.swift")
        let page = try #require(CadenceSourceScan.declarationBody("private struct NotepadPage: View", in: source))
        let rowStart = try #require(page.range(of: "NotepadNoteListRow(note: note, isSelected: selectedNoteID == note.id)"))
        let afterRow = String(page[rowStart.upperBound...])
        let menuStart = try #require(afterRow.range(of: ".contextMenu {"))
        let menu = String(afterRow[menuStart.upperBound...].prefix(400))
        #expect(menu.contains("NoteActionSupport.copyMarkdownLink(to: note)"))
        #expect(menu.contains("Button(role: .destructive) {\n                                deleteNote(note)"))
        // The menu belongs to the row's `NoteListRowButton` ([[T-7068]]), not to something drawn
        // after it: only the button's closing brace sits between the row and the menu.
        #expect(page.contains("NoteListRowButton(action: { selectedNoteID = note.id }) {\n" + String(repeating: " ", count: 28) + "NotepadNoteListRow(note: note, isSelected: selectedNoteID == note.id)"))
        let between = afterRow[..<menuStart.lowerBound].filter { !$0.isWhitespace }
        #expect(between == "}")
        // The dated pages stay without one (see `iOSNotesView.sidebarRow(for:)`).
        for other in ["DailyNotesPage", "WeeklyNotesPage", "MeetingNotesPage"] {
            let body = try #require(CadenceSourceScan.declarationBody("private struct \(other): View", in: source))
            #expect(!body.contains(".contextMenu"))
        }
    }
}
#endif
