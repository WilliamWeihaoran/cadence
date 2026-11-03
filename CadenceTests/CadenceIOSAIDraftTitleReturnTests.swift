import Foundation
import Testing
@testable import Cadence

/// **[[T-10220]]: Return in the iOS AI task draft's title typed a line break into the task.**
///
/// `iOSAITaskDraftCard.titleRow` drew `TextField("Task title", ..., axis: .vertical)` with no
/// `onSubmit`, and a vertical-axis field with none inserts "\n" on Return. Create then made the
/// task with that break inside its title, because `TaskCreationDraft.trimmedTitle` trims only the
/// ends. The Mac card's title field is single-line. Now Return ends the title, as it does in the
/// other vertical-axis title fields (`CadenceSchedulePanel.titleField`, the capture card, the
/// task sheet's subtask rows). Source reads in `CadenceIOSFormReturnKeyTests`' style: no unit test
/// can press a key, and the file is `#if os(iOS)`.
struct CadenceIOSAIDraftTitleReturnTests {
    private static let path = "Cadence/iOS/iOSAINoteActionsViews.swift"

    private static func compactBody(_ declaration: String) throws -> String {
        let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
        let body = try #require(CadenceSourceScan.declarationBody(declaration, in: source))
        return body.filter { !$0.isWhitespace }
    }

    @Test func returnInTheDraftTitleEndsTheFieldInsteadOfTypingALineBreak() throws {
        let row = try Self.compactBody("private var titleRow: some View")
        #expect(row.contains("TextField(\"Tasktitle\",text:$draft.title,axis:.vertical)"),
                "non-vacuity: the title field is the vertical-axis one this pins")
        #expect(row.contains(".focused($isTitleFocused).submitLabel(.done).onSubmit{isTitleFocused=false}"),
                "Return in the draft's title must submit (ending the field), not insert a line break")
    }

    /// The trim that let the break through: ends only. If creation ever folds inner line breaks
    /// itself, this pin can go; until then the field is the only guard.
    @Test func creationTrimsOnlyTheTitlesEnds() {
        let draft = TaskCreationDraft(
            title: "Buy\nmilk\n",
            notes: "",
            priority: .none,
            container: .inbox,
            sectionName: TaskSectionDefaults.defaultName,
            dueDateKey: "",
            scheduledDateKey: "",
            subtaskTitles: [],
            tags: []
        )
        #expect(draft.trimmedTitle == "Buy\nmilk")
    }
}
