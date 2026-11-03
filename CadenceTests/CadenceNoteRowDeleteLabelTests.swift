import Foundation
import Testing
@testable import Cadence

/// **[[T-8534]] — every note row menu says "Delete Note"**, from one shared label. The Mac's
/// Notepad row (`NotesView`) and list-note row (`ListNoteFolderRow`) said bare "Delete" where
/// iOS's `iOSNoteDeleteMenuButton` said "Delete Note" for the same menu. Read as source: the rows
/// are private views and the iOS file never compiles in this target.
struct CadenceNoteRowDeleteLabelTests {
    @Test func everyNoteRowMenuReadsTheOneDeleteNoteLabel() throws {
        #expect(CadenceNoteRowMenuCopy.deleteTitle == "Delete Note")
        #expect(CadenceNoteRowMenuCopy.deleteSystemImage == "trash")
        let sharedLabel = "Label(CadenceNoteRowMenuCopy.deleteTitle, systemImage: CadenceNoteRowMenuCopy.deleteSystemImage)"
        let sites = [
            "Cadence/macOS/Views/NotesView.swift",
            "Cadence/macOS/Views/ListNotesViewSupportViews.swift",
            "Cadence/iOS/iOSNoteDeletionSupport.swift"
        ]
        for path in sites {
            let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            // Non-vacuity: the read found the row menus' sibling item.
            #expect(code.contains("Label(CadenceNoteClipboard.copyLinkTitle"), "\(path) reads as empty")
            #expect(code.components(separatedBy: sharedLabel).count - 1 == 1, "\(path) no longer draws the shared Delete Note label")
            #expect(!code.contains("Label(\"Delete\", systemImage: \"trash\")"), "\(path) spells a bare Delete again")
            #expect(!code.contains("Label(\"Delete Note\""), "\(path) spells Delete Note of its own again")
        }
    }
}
