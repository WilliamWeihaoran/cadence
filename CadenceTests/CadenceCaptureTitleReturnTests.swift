import Foundation
import Testing
@testable import Cadence

/// **[[T-19958]] -- Return in a capture title submits on iOS as it does on the Mac.**
///
/// Both title fields are `TextField(..., axis: .vertical)`. The Mac fires `onSubmit` on Return; iOS
/// inserts a line break and never fires it, so on the iPad a Return in the capture card's title
/// grew the field instead of submitting. `CadenceCaptureTitleReturn` reads the break from the text
/// itself, and both fields' `onChange(of: draft.title)` act on its answer.
struct CadenceCaptureTitleReturnTests {

    /// **Behavioural.** One typed break is Return: the title comes back without it, and submits --
    /// at the end, in the middle, and into an empty title (where the submit raises the
    /// "Add a title first." notice rather than doing nothing).
    @Test func aTypedReturnStripsTheBreakAndSubmits() {
        let cases: [(old: String, new: String, title: String)] = [
            ("Buy milk", "Buy milk\n", "Buy milk"),
            ("!!", "!!\n", "!!"),
            ("Buy milk", "Buy\n milk", "Buy milk"),
            ("", "\n", ""),
            ("Call Ana", "Call Ana\r\n", "Call Ana"),
        ]
        for item in cases {
            #expect(
                CadenceCaptureTitleReturn.resolve(old: item.old, new: item.new)
                    == .init(title: item.title, submits: true),
                "\(item.new.debugDescription)"
            )
        }
    }

    /// **Behavioural.** No break, nothing to do -- ordinary typing and deleting are left alone.
    @Test func anEditWithoutABreakIsLeftAlone() {
        #expect(CadenceCaptureTitleReturn.resolve(old: "Buy", new: "Buy ") == nil)
        #expect(CadenceCaptureTitleReturn.resolve(old: "Buy milk", new: "Buy mil") == nil)
        #expect(CadenceCaptureTitleReturn.resolve(old: "", new: "") == nil)
    }

    /// **Behavioural.** A paste carrying breaks keeps its words on one line and does NOT submit:
    /// a pasted paragraph is not a Return.
    @Test func aPastedBreakJoinsTheLinesWithoutSubmitting() {
        #expect(
            CadenceCaptureTitleReturn.resolve(old: "", new: "Plan trip\nBook hotel")
                == .init(title: "Plan trip Book hotel", submits: false)
        )
        #expect(
            CadenceCaptureTitleReturn.resolve(old: "Notes: ", new: "Notes: a\n\nb\n")
                == .init(title: "Notes: a b", submits: false)
        )
    }

    /// **Behavioural.** The notice a Return raises survives the strip that rewrites the field
    /// under it; a change of words still retires it on the next keystroke (T-589).
    @Test func onlyAChangeOfWordsRetiresTheNotice() {
        #expect(!CadenceCaptureTitleReturn.changesWords(old: "", new: "\n"))
        #expect(!CadenceCaptureTitleReturn.changesWords(old: "\n", new: ""))
        #expect(!CadenceCaptureTitleReturn.changesWords(old: "!!", new: "!!\n"))
        #expect(!CadenceCaptureTitleReturn.changesWords(old: "!!\n", new: "!!"))
        #expect(CadenceCaptureTitleReturn.changesWords(old: "!!", new: "!!a"))
        #expect(CadenceCaptureTitleReturn.changesWords(old: "", new: "a"))
    }

    /// **Source shape.** Both vertical title fields route their title changes through the helper
    /// and still submit on `onSubmit`, so the Mac's Return and iOS's line break reach one commit.
    @Test func bothTitleFieldsSubmitAReturnThroughTheHelper() throws {
        for path in [
            "Cadence/Shared/Components/CadenceScheduleCaptureCard.swift",
            "Cadence/Shared/Components/CadenceSchedulePanel.swift",
        ] {
            let code = try CadenceCommitSurfaceScan.scanned(path)
            #expect(
                CadenceSourceScan.matchCount(#"CadenceCaptureTitleReturn\.resolve\(old: old, new: new\)"#, in: code) == 1,
                "\(path) no longer reads a typed Return"
            )
            #expect(code.contains("if resolution.submits { commit() }"), "\(path) strips the Return without submitting")
            #expect(code.contains("CadenceCaptureTitleReturn.changesWords(old: old, new: new)"), "\(path) retires the notice on its own strip")
            #expect(!code.contains("onChange(of: draft.title) { _, _ in actionError = nil }"), "\(path) clears the notice a Return raised")
            #expect(code.contains("TextField(draft.kind.titlePlaceholder, text: $draft.title, axis: .vertical)"), "\(path)")
            #expect(code.contains(".onSubmit(commit)"), "\(path) lost the Mac's Return")
        }
    }
}
