import Foundation
import Testing
@testable import Cadence

/// **What a note-list row says a note contains.**
///
/// T-1700: the row detail was `previewBody(note).components(separatedBy: "\n")` picking the first
/// non-blank line, with no markdown step, while search ran the same note through
/// `CadenceMarkdownPresentationSupport.plainPreviewText`. One note, one screen, two answers — the
/// Notes list drew `## Level two` with its hashes and search drew "Level two". Both readers are
/// `CadenceMarkdownPresentationSupport` now, so the list cannot drift from search again.
///
/// `NoteRowText` has **four** text-reading call sites and they are all fed from here: the Daily row
/// (title and detail), the Weekly row (title and detail), the Notepad row, and the two list-note
/// rows on macOS and iOS. Nothing below reaches a view — these are the two helpers every one of
/// those rows calls.
@MainActor
struct CadenceNoteRowExcerptTests {
    // MARK: - The device reading

    /// **The exact note from the report.** A notepad note whose body opens with the `# H1` that
    /// supplied its title, then an `## H2`. The row draws the title itself, so the excerpt is the
    /// H2 — and it is the H2's *text*, not its source line.
    @Test func theHeadingUnderTheTitleLosesItsHashes() {
        let note = Note(
            kind: .permanent,
            title: "Markdown Smoke",
            content: "# Markdown Smoke\n## Level two\n### Level three\n**Inline bold**"
        )
        #expect(NoteRowText.previewBelowTitleHeading(note) == "Level two")
    }

    /// **The two answers, pinned to agree.** The same body through the row reader and through the
    /// search reader: search flattens the whole note and the row takes its opening block, so the
    /// row's string has to be search's opening words rather than a different rendering of them.
    @Test func theRowExcerptIsAPrefixOfWhatSearchShowsForTheSameNote() throws {
        let body = "# Markdown Smoke\n## Level two\n### Level three\n**Inline bold**"
        let note = Note(kind: .permanent, title: "Markdown Smoke", content: body)
        let searchText = CadenceMarkdownPresentationSupport.plainPreviewText(from: body)

        #expect(searchText == "Markdown Smoke Level two Level three Inline bold")
        let excerpt = try #require(NoteRowText.preview(note))
        #expect(excerpt == "Markdown Smoke")
        #expect(searchText.hasPrefix(excerpt))
    }

    /// **The property the old spelling existed for, kept.** The excerpt is measured against the
    /// *body*: a note that has only been tagged carries a `---` frontmatter fence, and previewing
    /// raw content would draw that fence as the row's text. `previewBody` strips it before the
    /// markdown reader ever sees it.
    @Test func aTaggedNoteNeverPreviewsItsOwnFrontmatterFence() {
        let note = Note(
            kind: .permanent,
            title: "Kitchen",
            content: "---\ntags: [home]\n---\n# Kitchen\nBuy a new kettle"
        )
        #expect(NoteRowText.previewBelowTitleHeading(note) == "Buy a new kettle")
        #expect(NoteRowText.preview(note) == "Kitchen")
    }

    /// **A tagged-and-unwritten note still reads as empty**, which is what the row styling asks
    /// `isEmpty` and what the excerpt has to agree with.
    @Test func aTaggedButUnwrittenNoteHasNoExcerptAndNoDetail() {
        let note = Note(kind: .permanent, title: "Kitchen", content: "---\ntags: [home]\n---\n")
        #expect(NoteRowText.preview(note) == nil)
        #expect(NoteRowText.previewBelowTitleHeading(note) == nil)
        #expect(NoteRowText.isEmpty(note))
    }

    // MARK: - Which heading is the title

    /// **`#  Two spaces` is the same title and used to slip through.** The skip was string equality
    /// against `"# \(displayTitle)"`, so an H1 with a second space did not match it and the row
    /// printed the title again as its own detail. `MarkdownNoteTitleSync` takes the title from that
    /// line all the same, so the row has to drop it.
    @Test func aTitleHeadingWithAnExtraSpaceIsStillTheTitle() {
        let note = Note(
            kind: .permanent,
            title: "Markdown Smoke",
            content: "#  Markdown Smoke\n## Level two"
        )
        #expect(NoteRowText.previewBelowTitleHeading(note) == "Level two")
    }

    /// **Only the leading H1 is the name.** A second `# Markdown Smoke` further down is a section
    /// heading — which is exactly how `MarkdownNoteTitleSync.title(from:kind:currentTitle:)` reads
    /// it, considering the first line and no other — so it is content and the row may show it.
    @Test func anH1FurtherDownIsASectionHeadingAndNotSkipped() {
        let note = Note(
            kind: .permanent,
            title: "Markdown Smoke",
            content: "# Markdown Smoke\n\n# Markdown Smoke\n\ntail"
        )
        #expect(NoteRowText.previewBelowTitleHeading(note) == "Markdown Smoke")
    }

    /// **An `## H2` that happens to match the title is not the title.** Only a level-1 heading
    /// feeds `MarkdownNoteTitleSync`, so an H2 of the same words is content.
    @Test func aSecondLevelHeadingMatchingTheTitleIsNotDropped() {
        let note = Note(kind: .permanent, title: "Markdown Smoke", content: "## Markdown Smoke\ntail")
        #expect(NoteRowText.previewBelowTitleHeading(note) == "Markdown Smoke")
    }

    /// A body that is nothing but its own title heading has no second block to show.
    @Test func aBodyThatIsOnlyItsTitleHeadingHasNoExcerpt() {
        let note = Note(kind: .permanent, title: "Markdown Smoke", content: "# Markdown Smoke\n")
        #expect(NoteRowText.previewBelowTitleHeading(note) == nil)
    }

    // MARK: - Every other marker the first line can carry

    /// The report named `#`, `>`, `-`, `|` and `![…](…)` as markers that reached the row verbatim.
    @Test func bulletsQuotesChecklistsAndTablesAllReadAsText() {
        #expect(NoteRowText.preview(Note(kind: .permanent, content: "- Buy milk")) == "Buy milk")
        #expect(NoteRowText.preview(Note(kind: .permanent, content: "> Quoted line")) == "Quoted line")
        #expect(NoteRowText.preview(Note(kind: .permanent, content: "- [ ] Not done yet")) == "Not done yet")
        #expect(NoteRowText.preview(Note(kind: .permanent, content: "1. First step")) == "First step")
        #expect(
            NoteRowText.preview(Note(kind: .permanent, content: "| Name | Count |\n| --- | --- |\n| Kettle | 1 |"))
                == "Name Count Kettle 1"
        )
    }

    /// A divider carries no text, so it is not an excerpt — the row shows the block under it.
    @Test func aDividerIsSkippedRatherThanDrawnAsThreeDashes() {
        #expect(NoteRowText.preview(Note(kind: .permanent, content: "***\nAfter the rule")) == "After the rule")
    }

    /// **The excerpt is the first block, not the first source line.** A paragraph that soft-wraps
    /// across three lines fills the one-line row instead of stopping at the first newline.
    @Test func aSoftWrappedParagraphIsOneExcerpt() {
        #expect(
            NoteRowText.preview(Note(kind: .permanent, content: "one\ntwo\nthree\n\nsecond block"))
                == "one two three"
        )
    }

    // MARK: - The search shape is unchanged

    /// `plainPreviewText` is `plainPreviewLines` joined with spaces — the refactor that gave the
    /// row its own shape must not have moved search's.
    @Test func theSearchReaderStillFlattensTheWholeDocumentAndHonoursItsLimit() {
        let body = "# Markdown Smoke\n## Level two\n### Level three\n**Inline bold**"
        #expect(
            CadenceMarkdownPresentationSupport.plainPreviewLines(from: body)
                == ["Markdown Smoke", "Level two", "Level three", "Inline bold"]
        )
        #expect(
            CadenceMarkdownPresentationSupport.plainPreviewText(from: body)
                == CadenceMarkdownPresentationSupport.plainPreviewLines(from: body).joined(separator: " ")
        )
        #expect(CadenceMarkdownPresentationSupport.plainPreviewText(from: body, limit: 14) == "Markdown Smoke")
    }
}

/// **A page destination's two sentences, and why there are two.**
///
/// T-1701: `subtitle` and `searchSummary` are drawn on consecutive lines of the same iOS search
/// Pages row, and three of eleven destinations returned one string from both — Inbox read
/// "Capture and triage" twice. The contract the other eight already kept is that the subtitle names
/// what you go there to *do* and the summary names what is *in* there; where the subtitle is itself
/// a contents line, the summary is the fuller enumeration (Notes). Either way the two have to say
/// different things, because a row that prints one sentence twice is a row with a bug in it.
struct CadenceFeatureDestinationCopyTests {
    /// **The guard.** Every destination, not the three that were found: a twelfth added tomorrow
    /// fails here rather than on a device.
    @Test func noDestinationPrintsItsOneSentenceTwice() {
        for destination in CadenceFeatureDestination.allCases {
            #expect(!destination.subtitle.isEmpty, "\(destination.rawValue) has no subtitle")
            #expect(!destination.searchSummary.isEmpty, "\(destination.rawValue) has no search summary")
            #expect(
                destination.subtitle.caseInsensitiveCompare(destination.searchSummary) != .orderedSame,
                "\(destination.rawValue) draws \"\(destination.subtitle)\" on both of its two lines"
            )
        }
    }

    /// **The three that repeated, and what they say now.** Inbox and Goals took the wording the
    /// macOS command palette already uses for the same pages (`GlobalSearchPageDefinition.all`),
    /// rather than a fourth phrasing invented here; Lists has no palette entry, so its summary
    /// names the sections the page actually draws — Areas, Projects, Archived.
    ///
    /// Goals is gone (T-2076), so two of the three remain. The claim is unchanged for them: a
    /// destination's `subtitle` says what you go there to *do* and its `searchSummary` says what
    /// is *in* it, and the two are drawn on consecutive lines of one search row.
    @Test func theRepeatedDestinationsNowNameTheirContents() {
        #expect(CadenceFeatureDestination.inbox.subtitle == "Capture and triage")
        #expect(CadenceFeatureDestination.inbox.searchSummary == "Unsorted capture tasks")

        #expect(CadenceFeatureDestination.lists.subtitle == "Areas, projects, and lists")
        #expect(CadenceFeatureDestination.lists.searchSummary == "Active and archived lists")
    }

    /// Both sentences are matched against, so neither may quietly drop out of `searchAliases` —
    /// a summary nobody can search for would make the second line free to be anything.
    @Test func bothSentencesAreStillSearchableText() {
        for destination in CadenceFeatureDestination.allCases {
            #expect(destination.searchAliases.contains(destination.subtitle))
            #expect(destination.searchAliases.contains(destination.searchSummary))
        }
    }
}
