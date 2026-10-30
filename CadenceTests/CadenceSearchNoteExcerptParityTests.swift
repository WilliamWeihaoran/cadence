// Compiled for macOS only: the palette half (`GlobalSearchIndexSupport`) is a macOS type, and the
// iOS half is pinned by scanning `iOSSearchView.swift`, which this bundle cannot call.
#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// **One note, one excerpt, both search surfaces** ([[T-8763]], minimum half).
///
/// An iOS Search note row carried a 120-character body excerpt and a Cmd+K note row carried none,
/// so a note matched by a word in its text gave the Mac no sign why. The rule now lives in
/// `CadenceSearchNoteExcerpt`, and both `GlobalSearchIndexSupport.noteResult` and
/// `iOSSearchView.noteResult` call it. The iOS row is a private member of an iOS view this macOS
/// bundle cannot run, so its half is pinned by source shape: it calls the helper, and the old
/// private `excerpt(_:)` spelling — the second copy that let the two drift — is gone.
@MainActor
struct CadenceSearchNoteExcerptParityTests {

    /// The expression iOS Search ran before [[T-8763]] moved it into the helper, written out so the
    /// helper is pinned to what an iOS note row already showed, not just to itself.
    private func iOSExcerpt(_ note: Note, taskTitles: [UUID: String]) -> String {
        CadenceMarkdownPresentationSupport.plainPreviewText(
            from: MarkdownTaskEmbedTitleCache.resolving(note.content, titles: taskTitles),
            limit: 120
        )
    }

    @Test func aCmdKNoteRowShowsTheExcerptAnIOSSearchNoteRowShows() throws {
        let task = AppTask(title: "Live embed title")
        let titles = MarkdownTaskEmbedTitleCache.titles(for: [task])
        let filler = String(repeating: "lorem ipsum ", count: 20)
        let note = Note(
            kind: .permanent,
            title: "Kickoff",
            content: "## Agenda\nDiscuss **budget** with [[task:\(task.id.uuidString)|Stale title]] \(filler)"
        )

        let palette = GlobalSearchIndexSupport.noteResults(notes: [note], query: "budget", taskTitles: titles)
        let row = try #require(palette.first)
        let ios = iOSExcerpt(note, taskTitles: titles)

        #expect(palette.count == 1)
        #expect(!row.detail.isEmpty)
        #expect(row.detail == ios)
        #expect(row.detail == CadenceSearchNoteExcerpt.text(for: note, taskTitles: titles))
        // The properties the excerpt exists for, so "both empty" cannot pass as agreement.
        #expect(row.detail.hasPrefix("Agenda Discuss budget"))
        #expect(row.detail.contains("Live embed title"))
        #expect(!row.detail.contains("Stale title"))
        #expect(!row.detail.contains("**"))
        #expect(!row.detail.contains("#"))
        #expect(row.detail.count <= 120)
        #expect(row.detail.count > 100)
        // The subtitle is untouched: the excerpt is a third line, not a replacement.
        #expect(row.subtitle == "Notepad")
    }

    @Test func theIdlePaletteNoteRowCarriesTheSameExcerpt() throws {
        let note = Note(kind: .permanent, title: "Groceries", content: "- [ ] milk\n- [ ] eggs")
        let idle = GlobalSearchIndexSupport.noteResults(notes: [note], query: "", taskTitles: [:])
        let row = try #require(idle.first)
        #expect(row.detail == iOSExcerpt(note, taskTitles: [:]))
        #expect(row.detail.contains("milk"))
    }

    @Test func iOSSearchRunsTheSameExcerptExpression() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSSearchView.swift")
        let code = CadenceSourceScan.codeOnly(raw)
        #expect(code.contains("struct iOSSearchView"))

        let row = try #require(CadenceSourceScan.functionBody(named: "noteResult", in: code))
        #expect(CadenceSourceScan.matchCount(
            #"detail: CadenceSearchNoteExcerpt\.text\(for: note, taskTitles: taskTitles\)"#, in: row
        ) == 1)
        // No second spelling of the rule anywhere in the file.
        #expect(CadenceSourceScan.matchCount(#"plainPreviewText\("#, in: code) == 0)
        #expect(CadenceSourceScan.matchCount(#"func excerpt\("#, in: code) == 0)
    }

    @Test func theCmdKRowDrawsTheDetailLine() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/GlobalSearchSupportViews.swift")
        let code = CadenceSourceScan.codeOnly(raw)
        let row = try #require(CadenceSourceScan.declarationBody("struct GlobalSearchResultRow", in: code))
        #expect(CadenceSourceScan.matchCount(#"Text\(result\.detail\)"#, in: row) == 1)
    }
}
#endif
