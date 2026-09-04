import Foundation
import Testing
@testable import Cadence

/// **T-845.** iOS's format toolbar spelled these Title Case ("Bulleted List", "Code Block", "Note
/// Link"); macOS's spelled the same actions sentence case for VoiceOver ("Bulleted list", "Code
/// block", "Note link") — two hand-typed case tables for one vocabulary. `MarkdownFormatCommandTitle`
/// in `MarkdownSlashCommandCoreSupport.swift` is the one table now; both platforms' toolbars read
/// it instead of keeping their own.
struct MarkdownFormatCommandTitleTests {
    /// The three items the ticket named, plus the two multi-word items it did not but which had
    /// the exact same drift (`orderedList`, `taskReference`, `inlineCode`). Every one of these is
    /// sentence case: capitalised first word, lowercase second.
    @Test func sentenceCaseTitlesAreCapitalizedOnlyOnTheFirstWord() throws {
        #expect(MarkdownFormatCommandTitle.sentenceCase(for: .unorderedList) == "Bulleted list")
        #expect(MarkdownFormatCommandTitle.sentenceCase(for: .codeBlock) == "Code block")
        #expect(MarkdownFormatCommandTitle.sentenceCase(for: .noteLink) == "Note link")
        #expect(MarkdownFormatCommandTitle.sentenceCase(for: .orderedList) == "Numbered list")
        #expect(MarkdownFormatCommandTitle.sentenceCase(for: .taskReference) == "Task reference")
        #expect(MarkdownFormatCommandTitle.sentenceCase(for: .inlineCode) == "Inline code")
    }

    /// Single-word titles, where Title Case and sentence case read identically — included so the
    /// switch's other arms are not silently untested, and so a future case added to
    /// `MarkdownFormatCommand` without a matching arm here is a compile error, not a silent gap.
    @Test func singleWordTitlesAreUnchangedBySentenceCasing() throws {
        #expect(MarkdownFormatCommandTitle.sentenceCase(for: .bold) == "Bold")
        #expect(MarkdownFormatCommandTitle.sentenceCase(for: .italic) == "Italic")
        #expect(MarkdownFormatCommandTitle.sentenceCase(for: .strikethrough) == "Strikethrough")
        #expect(MarkdownFormatCommandTitle.sentenceCase(for: .highlight) == "Highlight")
        #expect(MarkdownFormatCommandTitle.sentenceCase(for: .link) == "Link")
        #expect(MarkdownFormatCommandTitle.sentenceCase(for: .paragraph) == "Paragraph")
        #expect(MarkdownFormatCommandTitle.sentenceCase(for: .quote) == "Quote")
        #expect(MarkdownFormatCommandTitle.sentenceCase(for: .divider) == "Divider")
        #expect(MarkdownFormatCommandTitle.sentenceCase(for: .todoList) == "Checklist")
        #expect(MarkdownFormatCommandTitle.sentenceCase(for: .heading(1)) == "Heading 1")
        #expect(MarkdownFormatCommandTitle.sentenceCase(for: .heading(2)) == "Heading 2")
        #expect(MarkdownFormatCommandTitle.sentenceCase(for: .heading(6)) == "Heading 6")
    }

    /// **Not `MarkdownSlashCommand.title`.** That table's "bullet" entry is titled "Bullet List" —
    /// a different word from "Bulleted list", not just a different case — so reusing it verbatim
    /// would trade the reported drift for a wording regression. This is the guard that the two
    /// vocabularies stay independent rather than one silently reading the other's array by id.
    @Test func doesNotReadTheSlashCommandTitleVerbatim() throws {
        let slashBulletTitle = try #require(MarkdownSlashCommand.all.first(where: { $0.id == "bullet" })).title
        #expect(slashBulletTitle == "Bullet List")
        #expect(MarkdownFormatCommandTitle.sentenceCase(for: .unorderedList) != slashBulletTitle)
    }

    /// iOS's format toolbar reads the shared table now, at every one of the sixteen items in
    /// `primaryItems` — including the six `compactItems` repeats without their own second copy.
    @Test func iOSFormatToolbarReadsTheSharedTitleTable() throws {
        let source = try CadenceCommitSurfaceScan.scanned("Cadence/iOS/iOSMarkdownAccessoryViews.swift")

        // The builders compute the title from the command; a call site no longer passes a literal
        // string as the second argument to either.
        #expect(
            CadenceSourceScan.matchCount(#"\.icon\("[^"]+", "[^"]+", \."#, in: source) == 0,
            "iOSMarkdownFormatToolbarItem.icon is still called with a literal title"
        )
        #expect(
            CadenceSourceScan.matchCount(#"\.text\("[^"]+", "[^"]+", \."#, in: source) == 0,
            "iOSMarkdownFormatToolbarItem.text is still called with a literal accessibility title"
        )
        #expect(
            CadenceSourceScan.matchCount(#"MarkdownFormatCommandTitle\.sentenceCase\(for: command\)"#, in: source) == 2,
            "the two builders (icon, text) no longer read the shared table"
        )

        // Non-vacuity: `primaryItems`' thirteen `.icon` entries plus `compactItems`' six repeats,
        // all now spelled with two arguments — the count would fall if either list lost an entry
        // or a call reverted to three arguments.
        #expect(CadenceSourceScan.matchCount(#"\.icon\("[a-zA-Z.]+", \."#, in: source) == 19)
        #expect(CadenceSourceScan.matchCount(#"\.icon\("list\.bullet", \.unorderedList\)"#, in: source) == 2)
        #expect(CadenceSourceScan.matchCount(#"\.text\("[A-Z0-9]+", \."#, in: source) == 3)
    }

    /// macOS's toolbar reads the shared table at every multi-word item; the tests above already
    /// pin `H1`/`H2` (`CadenceControlAccessibilityLabelTests`) and the image button's "Image" is
    /// intentionally untouched (single word, and not a `MarkdownFormatCommand` at all).
    @Test func macOSToolbarReadsTheSharedTitleTable() throws {
        let source = try CadenceCommitSurfaceScan.scanned("Cadence/macOS/Editor/MarkdownEditorView.swift")

        for command in [
            "bold", "italic", "strikethrough", "highlight", "inlineCode", "link", "noteLink",
            "taskReference", "unorderedList", "orderedList", "todoList", "quote", "codeBlock", "divider",
        ] {
            #expect(
                CadenceSourceScan.matchCount(
                    #"MarkdownFormatCommandTitle\.sentenceCase\(for: \."# + command + #"\)"#,
                    in: source
                ) == 1,
                "MarkdownEditorToolbar no longer reads the shared title for .\(command)"
            )
        }

        // The literals these replaced are gone from the toolbar body, not just supplemented.
        for retired in [
            #"accessibilityLabel: "Bulleted list""#,
            #"accessibilityLabel: "Code block""#,
            #"accessibilityLabel: "Note link""#,
            #"accessibilityLabel: "Numbered list""#,
            #"accessibilityLabel: "Task reference""#,
            #"accessibilityLabel: "Inline code""#,
        ] {
            #expect(!source.contains(retired), "MarkdownEditorView.swift still types \(retired)")
        }

        // The Image button is deliberately unchanged: not a MarkdownFormatCommand, one word either
        // way, and the sweep above would be wrong to touch it.
        #expect(source.contains(#"accessibilityLabel: "Image""#))
    }
}
