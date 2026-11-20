#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// **T-18639.** Four capped-height Mac pickers scroll to follow the arrow-key highlight, as the Cmd+K
/// palette does since [[T-8063]] and the slash menu since [[T-7233]]. None had a `ScrollViewReader`,
/// so holding Down walked the highlight below the popover's bottom edge and Return acted on a row
/// the user could not see -- and the list picker could OPEN with its highlight below the fold.
///
/// Source wiring, in the `theSectionsListScrollsTheHighlightedRowIntoView` shape: a scroll position
/// is not observable from a unit test, so what is pinned is the reader, the per-row ids `scrollTo`
/// needs, and the scroll on appear and on every highlight change.
@MainActor
struct CadenceMacPickerHighlightScrollTests {
    private static func compactBody(_ declaration: String, in path: String) throws -> String {
        let file = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
        return try #require(
            CadenceSourceScan.declarationBody(declaration, in: file),
            "could not read \(declaration)"
        ).filter { !$0.isWhitespace }
    }

    @Test func theListPickerScrollsTheHighlightedRowIntoView() throws {
        let body = try Self.compactBody(
            "struct ContainerPickerPopoverContent: View",
            in: "Cadence/macOS/Views/ContainerPickerSupportViews.swift"
        )
        #expect(body.contains("ScrollViewReader{proxyinScrollView{"))
        #expect(body.contains(".onAppear{scrollToHighlighted(proxy)}"), "the highlight can open below the fold")
        #expect(body.contains(".onChange(of:highlighted){_,_inscrollToHighlighted(proxy)}"),
                "an arrow move must scroll the highlighted row into view")
        #expect(body.contains("proxy.scrollTo(highlighted)"))
        #expect(body.contains(".id(TaskContainerSelection.inbox)"))
        #expect(body.contains(".id(TaskContainerSelection.area(area.id))"))
        #expect(body.contains(".id(TaskContainerSelection.project(project.id))"))
    }

    @Test func theTitleTagPanelScrollsTheHighlightedRowIntoView() throws {
        let body = try Self.compactBody(
            "struct TaskTitleInlineTagPicker: View",
            in: "Cadence/macOS/Views/TaskTitleInlineTagPicker.swift"
        )
        #expect(body.contains("ScrollViewReader{proxyinScrollView{"))
        #expect(body.contains(".onAppear{proxy.scrollTo(highlightIndex)}"))
        #expect(body.contains(".onChange(of:highlightIndex){_,_inproxy.scrollTo(highlightIndex)}"),
                "an arrow move must scroll the highlighted row into view")
        #expect(body.contains(".id(index)"), "scrollTo needs each tag row tagged with its highlight index")
        #expect(CadenceSourceScan.matchCount(#"\.id\(filteredTags\.count\)"#, in: body) == 2,
                "the Create and Unarchive rows sit at index filteredTags.count")
    }

    @Test func theContextPickerScrollsTheHighlightedRowIntoView() throws {
        let path = "Cadence/macOS/Views/CadenceContextPicker.swift"
        let body = try Self.compactBody("struct CadenceContextPickerList: View", in: path)
        #expect(body.contains("ScrollViewReader{proxyinScrollView{rows}"))
        #expect(body.contains(".onAppear{scrollToHighlighted(proxy)}"))
        #expect(body.contains(".onChange(of:highlightedItemID){_,_inscrollToHighlighted(proxy)}"),
                "an arrow move must scroll the highlighted row into view")
        #expect(body.contains("proxy.scrollTo(highlightedItemID)"))
        #expect(body.contains(".id(item.id)"))
        try Self.expectHostsDoNotWrapTheList("CadenceContextPickerList(", paths: [path, Self.listEditorPath], count: 2)
    }

    @Test func theCalendarPickerScrollsTheHighlightedRowIntoView() throws {
        let path = "Cadence/macOS/CadenceCalendarPicker.swift"
        let body = try Self.compactBody("struct CadenceCalendarPickerList: View", in: path)
        #expect(body.contains("ScrollViewReader{proxyinScrollView{rows}"))
        #expect(body.contains(".onAppear{scrollToHighlighted(proxy)}"))
        #expect(body.contains(".onChange(of:highlightedItemID){_,_inscrollToHighlighted(proxy)}"),
                "an arrow move must scroll the highlighted row into view")
        #expect(body.contains("proxy.scrollTo(highlightedItemID)"))
        #expect(body.contains(".id(id)"))
        try Self.expectHostsDoNotWrapTheList("CadenceCalendarPickerList(", paths: [path, Self.listEditorPath], count: 2)
    }

    private static let listEditorPath = "Cadence/macOS/Sheets/ListEditorSupportViews.swift"

    /// A host `ScrollView` around the list would put the list's own scroll view inside another and
    /// the search field back under the scroll. Counts the presentations so a renamed list cannot pass
    /// this vacuously.
    private static func expectHostsDoNotWrapTheList(_ call: String, paths: [String], count: Int) throws {
        var seen = 0
        for path in paths {
            let code = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path)).filter { !$0.isWhitespace }
            seen += code.components(separatedBy: call).count - 1
            #expect(!code.contains("ScrollView{" + call), "\(path) wraps \(call) in its own ScrollView again")
        }
        #expect(seen == count, "expected \(count) presentations of \(call), found \(seen)")
    }
}
#endif
