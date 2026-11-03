#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// **T-10040: Return in the Mac New Task panel's subtask rows.**
///
/// Every Return in a draft row, and every press of Add Subtask, appended a fresh empty row at the
/// end of the list. A second Return on the row it had just opened stacked another blank "Subtask"
/// row under it, and Return in the middle of the list opened the new row at the bottom. The Mac
/// inspector's "Add subtask" field adds nothing on a blank Return, so the panel now does the same,
/// and opens the next row directly under the one Return was pressed in.
@MainActor
struct CadenceCreateTaskSubtaskReturnTests {

    @Test func returnOnABlankRowAddsNothingAndKeepsTheCaret() {
        let drafts = CreateTaskSubtaskDraft.drafts(from: ["Outline", "  "])

        let next = CreateTaskSubtaskDraft.addingDraft(after: drafts[1].id, in: drafts)

        #expect(next.drafts == drafts)
        #expect(next.focus == drafts[1].id)
    }

    @Test func returnOnAFilledRowOpensTheNewRowDirectlyBelowIt() {
        let drafts = CreateTaskSubtaskDraft.drafts(from: ["Outline", "Draft", "Review"])

        let next = CreateTaskSubtaskDraft.addingDraft(after: drafts[0].id, in: drafts)

        #expect(next.drafts.map(\.title) == ["Outline", "", "Draft", "Review"])
        #expect(next.focus == next.drafts[1].id)
        #expect(next.drafts.count == drafts.count + 1)
    }

    @Test func returnOnAFilledRowReusesTheBlankRowAfterIt() {
        let drafts = CreateTaskSubtaskDraft.drafts(from: ["Outline", ""])

        let next = CreateTaskSubtaskDraft.addingDraft(after: drafts[0].id, in: drafts)

        #expect(next.drafts == drafts)
        #expect(next.focus == drafts[1].id)
    }

    @Test func theAddButtonReusesABlankLastRow() {
        let drafts = CreateTaskSubtaskDraft.drafts(from: ["Outline", ""])

        let next = CreateTaskSubtaskDraft.addingDraft(after: nil, in: drafts)

        #expect(next.drafts == drafts)
        #expect(next.focus == drafts[1].id)
    }

    @Test func theAddButtonAppendsAfterAFilledLastRow() {
        let drafts = CreateTaskSubtaskDraft.drafts(from: ["Outline"])

        let next = CreateTaskSubtaskDraft.addingDraft(after: nil, in: drafts)

        #expect(next.drafts.map(\.title) == ["Outline", ""])
        #expect(next.focus == next.drafts[1].id)
        #expect(CreateTaskSubtaskDraft.addingDraft(after: nil, in: []).drafts.count == 1)
    }

    /// The row and the button both reach the rule above; a source read, because no unit test can
    /// press Return in a sheet.
    @Test func theRowAndTheButtonBothAskTheRule() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Sheets/CreateTaskSheet.swift")
        )
        let body = try #require(CadenceSourceScan.declarationBody("struct CreateTaskSheet: View", in: source))
        let compact = body.filter { !$0.isWhitespace }
        #expect(compact.contains(".onSubmit{addSubtaskDraft(after:draftID)}"))
        #expect(compact.contains("Button{addSubtaskDraft(after:nil)}label:"))
        #expect(compact.contains("CreateTaskSubtaskDraft.addingDraft(after:draftID,in:subtaskDrafts)"))
    }
}
#endif
