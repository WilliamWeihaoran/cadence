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

    /// **T-976.** T-845 converged both format toolbars and left the key-command table in
    /// `iOSMarkdownTextView.keyCommands` untouched — a third hand-typed case table for the same
    /// vocabulary, and it still spelled the multi-word rows Title Case ("Bulleted List", "Ordered
    /// List", "Inline Code", "Code Block", "Note Link", "Task Reference") while both toolbars said
    /// "Bulleted list" etc. Every row whose action calls `apply(.command)` now reads its
    /// discoverability title from the shared table instead of retyping it; "Indent List" / "Outdent
    /// List" have no `MarkdownFormatCommand` case to read (they drive `indentationCommandHandler`,
    /// not `apply(_:)`) and are hand-corrected to sentence case instead.
    @Test func iOSKeyCommandTableReadsTheSharedTitleTable() throws {
        let source = try CadenceCommitSurfaceScan.scanned("Cadence/iOS/iOSMarkdownTextView.swift")

        for command in [
            "bold", "italic", "inlineCode", "link", "strikethrough", "highlight", "paragraph",
            "heading(1)", "heading(2)", "heading(3)", "heading(4)", "heading(5)", "heading(6)",
            "orderedList", "unorderedList", "quote", "todoList", "codeBlock", "divider", "noteLink",
            "taskReference",
        ] {
            #expect(
                CadenceSourceScan.matchCount(
                    #"MarkdownFormatCommandTitle\.sentenceCase\(for: \."#
                        + NSRegularExpression.escapedPattern(for: command)
                        + #"\)"#,
                    in: source
                ) == 1,
                "the key-command table no longer reads the shared title for .\(command)"
            )
        }

        // The literals these replaced are gone, not just supplemented.
        for retired in [
            "\"Bulleted List\"", "\"Ordered List\"", "\"Inline Code\"", "\"Code Block\"",
            "\"Note Link\"", "\"Task Reference\"", "\"Checklist\"", "\"Quote\"", "\"Link\"",
            "\"Strikethrough\"", "\"Highlight\"", "\"Paragraph\"", "\"Bold\"", "\"Italic\"",
        ] {
            #expect(!source.contains(retired), "iOSMarkdownTextView.swift still types \(retired)")
        }

        // The two rows with no MarkdownFormatCommand case are hand-corrected to sentence case
        // rather than left as the Title Case the rest of the table used to share.
        #expect(source.contains(#""Indent list""#))
        #expect(source.contains(#""Outdent list""#))
        #expect(!source.contains(#""Indent List""#))
        #expect(!source.contains(#""Outdent List""#))
    }

    /// **The Title Case spellings of every multi-word command title**, plus the two indentation
    /// rows that have no `MarkdownFormatCommand` case to read one from.
    ///
    /// "Ordered List" is here although nothing is titled that today: it is what
    /// `iOSMarkdownTextView` typed for `.orderedList` before T-976, and the drift this population
    /// exists to catch is a hand-typed title, not only a currently-reachable one.
    private static let titleCaseCommandTitles = [
        "Bulleted List", "Ordered List", "Numbered List", "Inline Code", "Code Block",
        "Note Link", "Task Reference", "Indent List", "Outdent List",
    ]

    /// The one file excused from the sweep below, because its Title Case titles are a different
    /// vocabulary under a different rule (see `doesNotReadTheSlashCommandTitleVerbatim`).
    private static let slashCommandTableFile = "Cadence/Services/MarkdownSlashCommandCoreSupport.swift"

    /// **The ninth site cannot escape the way the eighth did (T-976).** Each of the three tests
    /// above is an allowlist: it names one file and asserts that file reads the shared table. The
    /// key-command table survived T-845 for exactly that reason — it was simply not on the list,
    /// and no test in the repository could see a fourth surface typing `"Bulleted List"`. This one
    /// is a population rather than a list: every Swift file the app ships, with one exemption.
    ///
    /// **`MarkdownSlashCommand.all` is that exemption, deliberately.** Its rows are picker labels
    /// under a different rule, and its "bullet" entry is titled "Bullet List" — a different *word*
    /// from "Bulleted list", not a case drift. The exemption is asserted below to still hold the
    /// titles it is excused for, so the sweep cannot come back clean because that table quietly
    /// moved into a file nothing excuses.
    @Test func noOtherFileInTheAppTypesAMarkdownCommandTitleInTitleCase() throws {
        let instrument = try CadenceScanInstrument(
            "markdown command title typed in Title Case (T-976)",
            fires: """
            command("8", [.command, .shift], "Bulleted List", #selector(applyUnorderedListCommand))
            """,
            // The nearest thing that must be left alone: the same row, reading the shared table.
            andNotOn: """
            command("8", [.command, .shift], MarkdownFormatCommandTitle.sentenceCase(for: .unorderedList), #selector(applyUnorderedListCommand))
            """,
            by: { code in
                Self.titleCaseCommandTitles.contains { code.contains("\"\($0)\"") }
            }
        )

        let read = CadenceSourceScan.strippedSourceReader()
        let offenders = try instrument.sweep(
            try cadenceAppSwiftFiles().filter { $0 != Self.slashCommandTableFile },
            atLeast: 400,
            // The file the ticket is about is in the walk, so a clean result is a result about it.
            including: "Cadence/iOS/iOSMarkdownTextView.swift",
            read: read
        )
        #expect(
            offenders.isEmpty,
            """
            \(offenders.joined(separator: ", ")) types a markdown command title in Title Case \
            instead of reading MarkdownFormatCommandTitle.sentenceCase(for:)
            """
        )

        // Non-vacuity of the exemption: the needles really are spelled in the file the sweep
        // excuses, so the excused set is live rather than nine strings nothing spells any more.
        let table = try read(Self.slashCommandTableFile)
        let excused = Self.titleCaseCommandTitles.filter { table.contains("\"\($0)\"") }
        #expect(
            excused.count >= 4,
            "the excused slash-command table no longer spells these titles: \(excused)"
        )
    }
}
