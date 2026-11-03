import Foundation
import Testing
@testable import Cadence

/// **[[T-9664]].** On iOS a notes row draws the blue "open note" plate -- and carries the VoiceOver
/// Selected trait with it -- only where the editor stands beside the list, the two-column form.
/// `selectedNoteID` is set on appear and on every tap and outlives the compact cover, so a plate
/// read from it alone lit today's row on arrival and the last-opened row after its cover closed,
/// on a screen where no note was open.
@Suite struct CadenceIOSNotesOpenPlateTests {
    private static func code(_ path: String) throws -> String {
        CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
    }

    @Test func theNotesTabLightsARowOnlyInTheTwoColumnForm() throws {
        let source = try Self.code("Cadence/iOS/iOSNotesView.swift")
        let body = try #require(CadenceSourceScan.declarationBody(
            "private func isSelected(_ note: Note) -> Bool", in: source
        ))
        #expect(body.contains("notesLayout == .twoColumn && selectedNoteID == note.id"),
                "the Notes tab's row plate is not gated on the two-column form")
        let rows = source.components(separatedBy: "isSelected: isSelected(note)").count - 1
        #expect(rows == 4, "\(rows) of the four note-kind rows read the gated isSelected(_:)")
        #expect(!source.contains("isSelected: selectedNoteID =="), "a row reads selectedNoteID directly")
    }

    @Test func theListNotesTabLightsARowOnlyInTheTwoColumnForm() throws {
        let source = try Self.code("Cadence/iOS/iOSListNotesView.swift")
        let body = try #require(CadenceSourceScan.declarationBody("private func noteRow(_ note: Note) -> some View", in: source))
        #expect(body.contains("NoteFolderListRow("), "non-vacuity: the list Notes row is drawn here")
        #expect(body.contains("isSelected: layout == .twoColumn && selectedNoteID == note.id"),
                "the list Notes tab's row plate is not gated on the two-column form")
        let ungated = source.components(separatedBy: "isSelected: selectedNoteID ==").count - 1
        #expect(ungated == 0, "\(ungated) list Notes row(s) read selectedNoteID directly")
    }
}
