import Foundation
import Testing
@testable import Cadence

/// **[[T-8561]]: the iOS list editor said two things the Mac's never says.**
///
/// - Its title was "Edit List" whatever it was editing, under a context-menu row that had just
///   said "Edit Area" or "Edit Project" — the words macOS's `EditAreaSheet` / `EditProjectSheet`
///   title themselves with.
/// - Its Context row and that row's popover called the empty choice "None", where every Mac list
///   editor (`ListEditorContextRow.noneTitle`) and the Mac context picker say "No context".
///
/// Neither difference answers a hardware or input constraint, so by [[T-8201]] both were drift.
/// `iOSListEditorSheet` is inside `#if os(iOS)`, which this macOS test target does not compile, so
/// the iOS half is pinned as comment-stripped source text against the Mac's live constant.
@MainActor
struct CadenceiOSListEditorCopyTests {
    private let path = "Cadence/iOS/iOSListEditorViews.swift"

    private func code() throws -> String {
        CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
    }

    /// The editor names the kind of list in edit mode, and keeps "New List" for creation, where
    /// the kind is still the Area/Project segment's open question.
    @Test func theEditorTitleNamesTheKindOfListItEdits() throws {
        let source = try code()
        let title = try #require(CadenceSourceScan.declarationBody("private var sheetTitle: String", in: source))
        #expect(title.contains("guard isEditing else { return \"New List\" }"))
        #expect(title.contains("return isProjectMode ? \"Edit Project\" : \"Edit Area\""))
        #expect(CadenceSourceScan.matchCount("\\.navigationTitle\\(sheetTitle\\)", in: source) == 1)
        #expect(!source.contains("\"Edit List\""), "the editor must not call itself Edit List")
    }

    /// The same words the menu rows that open the editor use, on both of the iOS Lists shells.
    @Test func theTitleMatchesTheMenuRowsThatOpenTheEditor() throws {
        for shell in ["Cadence/iOS/iOSListViews.swift", "Cadence/iOS/iOSListsRegularPane.swift"] {
            let menu = try CadenceSourceScan.sourceFile(shell)
            #expect(menu.contains("Label(\"Edit Area\""), "\(shell) no longer opens the editor as Edit Area")
            #expect(menu.contains("Label(\"Edit Project\""), "\(shell) no longer opens the editor as Edit Project")
        }
    }

    /// Both readings of the empty context — the row's value and the popover's first row — go
    /// through the one constant, and that constant is the Mac's.
    @Test func theContextRowSaysNoContextAsTheMacDoes() throws {
        let source = try code()
        #expect(source.contains("static let contextNoneTitle = \"\(ListEditorContextRow.noneTitle)\""))
        #expect(CadenceSourceScan.matchCount("noneTitle: Self\\.contextNoneTitle", in: source) == 2)

        let contextTitle = try #require(CadenceSourceScan.declarationBody("private var contextTitle: String", in: source))
        #expect(contextTitle.contains("noneTitle: Self.contextNoneTitle"))
        #expect(!contextTitle.contains("\"None\""))
    }
}
