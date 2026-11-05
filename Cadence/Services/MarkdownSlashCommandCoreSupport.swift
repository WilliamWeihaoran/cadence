import Foundation

nonisolated struct MarkdownSlashCommand: Identifiable {
    enum Action {
        case insertText(indentation: String, text: String, caretOffset: Int)
        case chooseImage
    }

    let id: String
    let title: String
    let subtitle: String
    let action: Action

    init(id: String, title: String, subtitle: String, replacement: (indentation: String, text: String, caretOffset: Int)) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.action = .insertText(
            indentation: replacement.indentation,
            text: replacement.text,
            caretOffset: replacement.caretOffset
        )
    }

    init(id: String, title: String, subtitle: String, action: Action) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.action = action
    }

    static let all: [MarkdownSlashCommand] = [
        .init(id: "h1", title: "Heading 1", subtitle: "Large section heading", replacement: (indentation: "", text: "# ", caretOffset: 2)),
        .init(id: "h2", title: "Heading 2", subtitle: "Medium section heading", replacement: (indentation: "", text: "## ", caretOffset: 3)),
        .init(id: "h3", title: "Heading 3", subtitle: "Small section heading", replacement: (indentation: "", text: "### ", caretOffset: 4)),
        .init(id: "todo", title: "To-do", subtitle: "Unchecked task item", replacement: (indentation: "", text: "○ ", caretOffset: 2)),
        .init(id: "done", title: "Done", subtitle: "Checked task item", replacement: (indentation: "", text: "✓ ", caretOffset: 2)),
        .init(id: "bullet", title: "Bullet List", subtitle: "Bulleted list item", replacement: (indentation: "", text: "• ", caretOffset: 2)),
        .init(id: "number", title: "Numbered List", subtitle: "Ordered list item", replacement: (indentation: "", text: "1. ", caretOffset: 3)),
        .init(id: "quote", title: "Quote", subtitle: "Block quote line", replacement: (indentation: "", text: "> ", caretOffset: 2)),
        .init(id: "code", title: "Code Block", subtitle: "Fenced code block", replacement: (indentation: "", text: "```\n\n```", caretOffset: 4)),
        .init(id: "image", title: "Image", subtitle: "Insert image", action: .chooseImage),
        .init(id: "bold", title: "Bold", subtitle: "Strong text", replacement: (indentation: "", text: "****", caretOffset: 2)),
        .init(id: "italic", title: "Italic", subtitle: "Emphasized text", replacement: (indentation: "", text: "**", caretOffset: 1)),
        .init(id: "strike", title: "Strikethrough", subtitle: "Deleted text", replacement: (indentation: "", text: "~~~~", caretOffset: 2)),
        .init(id: "highlight", title: "Highlight", subtitle: "Highlighted text", replacement: (indentation: "", text: "====", caretOffset: 2)),
        .init(id: "rule", title: "Divider", subtitle: "Horizontal divider rule", replacement: (indentation: "", text: "---", caretOffset: 3)),
        .init(id: "table", title: "Table", subtitle: "Two-column table", replacement: (indentation: "", text: "| Column | Column |\n| --- | --- |\n|  |  |", caretOffset: 36)),
        .init(id: "link", title: "Note Link", subtitle: "Insert [[link]]", replacement: (indentation: "", text: "[[]]", caretOffset: 2)),
        .init(id: "task", title: "Task Reference", subtitle: "Insert [[task:]]", replacement: (indentation: "", text: "[[task:]]", caretOffset: 7))
    ]

    /// `commands` with every entry that opens the image picker removed.
    ///
    /// **The `/` half of `allowsImageInsertion`, on both platforms (T-421, T-442).** A host whose
    /// text is not a row in the store — the note-template body, an `EKEvent.notes` — refuses image
    /// insertion, and a refused command is dropped from the menu rather than offered with a
    /// follow-up that silently does nothing. iOS open-coded this predicate inside the `/` strip's
    /// query filter and macOS was about to write it a second time; the platforms differ in where
    /// the menu is drawn, not in which commands an out-of-store host may run.
    ///
    /// Order-preserving, and stated over an argument rather than over `all`, because macOS appends
    /// `templateCommands(for:)` before filtering.
    static func refusingImageInsertion(_ commands: [MarkdownSlashCommand]) -> [MarkdownSlashCommand] {
        commands.filter { command in
            if case .chooseImage = command.action { return false }
            return true
        }
    }

    /// The commands a `/query` offers, in menu order: **every** match, never a shortlist.
    ///
    /// **[[T-8581]].** iOS's `/` strip took `.prefix(8)` of this filter, so a bare `/` offered
    /// Heading 1 through Quote and nothing after them. Code Block, Image, Bold, Italic,
    /// Strikethrough, Highlight, Divider, Table, Note Link and Task Reference could be reached only
    /// by already knowing their names, and `/table` is the only way either platform has to insert a
    /// table. The strip scrolls sideways and the Mac's picker scrolls its rows ([[T-7233]]), so the
    /// cap was never a screen limit; one function now answers "what does this query offer" for both.
    static func matching(_ commands: [MarkdownSlashCommand], query: String) -> [MarkdownSlashCommand] {
        commands.filter { command in
            query.isEmpty ||
                command.id.localizedCaseInsensitiveContains(query) ||
                command.title.localizedCaseInsensitiveContains(query)
        }
    }

    /// Note templates as `/` commands — one of the three places templates live now that they no
    /// longer take a row above every note.
    ///
    /// The frontmatter block is stripped from the inserted body. A template's `---\ntags: [...]---`
    /// only means anything at the very top of a note; dropped at the caret it is a horizontal rule
    /// followed by stray YAML. The header route (`NoteEditorPane.applyTemplate`) splits and
    /// re-merges frontmatter properly because it is replacing the whole note; this one is an
    /// insertion, so it inserts only the part that survives being inserted.
    ///
    /// These are deliberately absent from `typedMutation`'s auto-transform, which fires on the
    /// space after a bare `/word`: turning a stray "/checklist " into eight lines of markdown is
    /// not a thing anyone typed on purpose. Templates come from the picker, where you can see what
    /// you are choosing.
    static func templateCommands(for templates: [NoteTemplate]) -> [MarkdownSlashCommand] {
        templates.map { template in
            let body = MarkdownMetadataParser.splitFrontmatter(in: template.body).body
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return MarkdownSlashCommand(
                id: template.id,
                title: template.title,
                subtitle: template.subtitle,
                replacement: (indentation: "", text: body, caretOffset: body.count)
            )
        }
    }
}

nonisolated struct MarkdownSlashCommandContext {
    let range: NSRange
    let indentation: String
    let query: String
    let cursorLocation: Int
}

nonisolated struct MarkdownSlashCommandMutation: Equatable {
    enum FollowUp: Equatable {
        case none
        case chooseImage
    }

    let replacementRange: NSRange
    let replacement: String
    let selection: NSRange
    let followUp: FollowUp
}

nonisolated enum MarkdownSlashCommandMutationSupport {
    static func mutation(
        for command: MarkdownSlashCommand,
        context: MarkdownSlashCommandContext
    ) -> MarkdownSlashCommandMutation {
        switch command.action {
        case let .insertText(_, text, caretOffset):
            let replacement = context.indentation + text
            return MarkdownSlashCommandMutation(
                replacementRange: context.range,
                replacement: replacement,
                selection: NSRange(
                    location: context.range.location + context.indentation.count + caretOffset,
                    length: 0
                ),
                followUp: .none
            )
        case .chooseImage:
            return MarkdownSlashCommandMutation(
                replacementRange: context.range,
                replacement: context.indentation,
                selection: NSRange(
                    location: context.range.location + context.indentation.count,
                    length: 0
                ),
                followUp: .chooseImage
            )
        }
    }

    static func typedMutation(in text: NSString, cursor: Int) -> MarkdownSlashCommandMutation? {
        let safeCursor = min(max(cursor, 0), text.length)
        guard let token = MarkdownSlashCommandTokenSupport.token(
            in: text,
            cursor: safeCursor,
            requiresTrailingSpace: true
        ) else {
            return nil
        }

        let context = MarkdownSlashCommandContext(
            range: token.range,
            indentation: token.indentation,
            query: token.query,
            cursorLocation: safeCursor
        )
        guard let command = MarkdownSlashCommand.all.first(where: { $0.id == token.query }),
              case .insertText = command.action else {
            return nil
        }
        return mutation(for: command, context: context)
    }
}

nonisolated enum MarkdownSlashCommandTokenSupport {
    static func context(in text: String, selection: NSRange, requiresTrailingSpace: Bool = false) -> MarkdownSlashCommandContext? {
        guard selection.length == 0 else { return nil }
        let nsText = text as NSString
        let safeCursor = min(max(selection.location, 0), nsText.length)
        guard let token = token(in: nsText, cursor: safeCursor, requiresTrailingSpace: requiresTrailingSpace) else {
            return nil
        }
        return MarkdownSlashCommandContext(
            range: token.range,
            indentation: token.indentation,
            query: token.query,
            cursorLocation: safeCursor
        )
    }

    static func token(
        in text: NSString,
        cursor: Int,
        requiresTrailingSpace: Bool
    ) -> (range: NSRange, indentation: String, query: String)? {
        let safeCursor = min(max(cursor, 0), text.length)
        let tokenEnd: Int
        if requiresTrailingSpace {
            guard safeCursor > 0, isHorizontalWhitespace(text.character(at: safeCursor - 1)) else {
                return nil
            }
            tokenEnd = safeCursor - 1
        } else {
            tokenEnd = safeCursor
        }

        let lineRange = text.lineRange(for: NSRange(location: max(0, tokenEnd - 1), length: 0))
        guard tokenEnd >= lineRange.location else { return nil }

        var queryStart = tokenEnd
        while queryStart > lineRange.location {
            let previous = text.character(at: queryStart - 1)
            if isASCIIAlphaNumeric(previous) {
                queryStart -= 1
            } else {
                break
            }
        }

        let slashLocation = queryStart - 1
        guard slashLocation >= lineRange.location,
              slashLocation < text.length,
              isCommandSlash(text.character(at: slashLocation)) else { return nil }
        let beforeSlashRange = NSRange(location: lineRange.location, length: slashLocation - lineRange.location)
        let beforeSlash = text.substring(with: beforeSlashRange)
        let startsAtIndentedLine = beforeSlash.allSatisfy { $0 == " " || $0 == "\t" }

        if !startsAtIndentedLine {
            guard slashLocation > lineRange.location,
                  isHorizontalWhitespace(text.character(at: slashLocation - 1)) else {
                return nil
            }
        }

        let queryRange = NSRange(location: slashLocation + 1, length: max(0, tokenEnd - slashLocation - 1))
        let query = text.substring(with: queryRange)
        let range: NSRange
        let indentation: String
        if startsAtIndentedLine {
            range = NSRange(location: lineRange.location, length: tokenEnd - lineRange.location + (requiresTrailingSpace ? 1 : 0))
            indentation = beforeSlash
        } else {
            range = NSRange(location: slashLocation, length: tokenEnd - slashLocation + (requiresTrailingSpace ? 1 : 0))
            indentation = ""
        }
        return (range, indentation, query)
    }

    private static func isCommandSlash(_ character: unichar) -> Bool {
        character == 47 || character == 92
    }

    private static func isASCIIAlphaNumeric(_ character: unichar) -> Bool {
        (character >= 48 && character <= 57) ||
        (character >= 65 && character <= 90) ||
        (character >= 97 && character <= 122)
    }

    private static func isHorizontalWhitespace(_ character: unichar) -> Bool {
        character == 32 || character == 9
    }
}

/// Sentence-case display names for the format toolbar, keyed by the `MarkdownFormatCommand` both
/// platforms already execute — one table, so a toolbar reads it instead of typing its own.
///
/// **T-845.** iOS's toolbar spelled these Title Case ("Bulleted List", "Code Block", "Note
/// Link"); macOS's spelled the same actions sentence case for VoiceOver ("Bulleted list", "Code
/// block", "Note link"). Two hand-typed case tables for one vocabulary, and whichever platform's
/// author reached for a string first decided the casing for that row — not a rule, a coin flip.
/// This is sentence case throughout, matching what macOS already had and what VoiceOver/HIG both
/// ask for, and both `iOSMarkdownFormatToolbar` and `MarkdownEditorToolbar` read it now rather
/// than keep their own copy.
///
/// Deliberately not `MarkdownSlashCommand.title`: that table's own casing is Title Case by a
/// different rule (a picker row's bold label), and "bullet" there is titled "Bullet List" — a
/// different word entirely from "Bulleted list" — so reading it verbatim would trade one drift for
/// another rather than closing this one.
nonisolated enum MarkdownFormatCommandTitle {
    static func sentenceCase(for command: MarkdownFormatCommand) -> String {
        switch command {
        case .bold: return "Bold"
        case .italic: return "Italic"
        case .inlineCode: return "Inline code"
        case .strikethrough: return "Strikethrough"
        case .highlight: return "Highlight"
        case .link: return "Link"
        case .paragraph: return "Paragraph"
        case .heading(let level): return "Heading \(level)"
        case .orderedList: return "Numbered list"
        case .unorderedList: return "Bulleted list"
        case .todoList: return "Checklist"
        case .quote: return "Quote"
        case .codeBlock: return "Code block"
        case .divider: return "Divider"
        case .noteLink: return "Note link"
        case .taskReference: return "Task reference"
        case .insertMarkdown, .insertBlockMarkdown, .insertReferenceMarkdown, .replaceMarkdown, .replaceMarkdownWithCaret:
            // Never a toolbar button's own command — these insert a specific, already-composed
            // snippet (a chosen note or task reference) rather than offering a fixed action a
            // button could be labelled for.
            return "Insert"
        }
    }
}

/// One button of the note editor's format toolbar: the command it runs and what it draws.
///
/// **[[T-8584]].** Both toolbars build from `MarkdownFormatToolbarCatalog` now. Their accessible
/// name is the shared `MarkdownFormatCommandTitle`, so neither platform types a title either.
nonisolated struct MarkdownFormatToolbarItem: Identifiable, Hashable {
    enum Glyph: Hashable {
        /// A short text glyph ("P", "H1") where no SF Symbol says it better.
        case text(String)
        case symbol(String)
    }

    let command: MarkdownFormatCommand
    let glyph: Glyph

    /// The accessible name, which is also the item's identity: no two toolbar commands share one.
    var id: String { title }
    var title: String { MarkdownFormatCommandTitle.sentenceCase(for: command) }

    var systemImage: String? {
        if case .symbol(let name) = glyph { return name }
        return nil
    }

    /// The symbol an overflow menu row draws, where a text glyph cannot stand in for an icon.
    var menuSystemImage: String {
        switch command {
        case .paragraph: return "paragraphsign"
        case .heading: return "textformat.size"
        default: return systemImage ?? "textformat"
        }
    }

    static func text(_ glyph: String, _ command: MarkdownFormatCommand) -> MarkdownFormatToolbarItem {
        MarkdownFormatToolbarItem(command: command, glyph: .text(glyph))
    }

    static func symbol(_ name: String, _ command: MarkdownFormatCommand) -> MarkdownFormatToolbarItem {
        MarkdownFormatToolbarItem(command: command, glyph: .symbol(name))
    }
}

/// **The note editor's format commands, once, for the Mac toolbar and the iOS one ([[T-8584]]).**
///
/// The two toolbars were typed separately and had drifted: the Mac had Highlight and no
/// Paragraph, iOS had Paragraph and no Highlight, and they ordered the rest differently. Neither
/// difference answered a hardware or input constraint ([[T-8201]]), so both platforms now draw the
/// union in this order. What still differs is width only: the iPhone's compact row shows
/// `compactCommands` and moves the rest into its overflow menu, because sixteen 44pt touch
/// targets do not fit a 393pt screen. The Mac's note and task reference buttons open a menu of
/// suggestions and iOS's open a picker sheet — the presentation each platform has for "choose from
/// a list", not a different command.
///
/// The image button and the template menu are not here: neither is a `MarkdownFormatCommand`, and
/// each host gates them on its own (`allowsImageInsertion`, a note kind).
nonisolated enum MarkdownFormatToolbarCatalog {
    /// Block style / inline style / references / lists / blocks. Each toolbar draws a separator
    /// between groups.
    static let groups: [[MarkdownFormatToolbarItem]] = [
        [
            .text("P", .paragraph),
            .text("H1", .heading(1)),
            .text("H2", .heading(2)),
        ],
        [
            .symbol("bold", .bold),
            .symbol("italic", .italic),
            .symbol("strikethrough", .strikethrough),
            .symbol("highlighter", .highlight),
            .symbol("chevron.left.forwardslash.chevron.right", .inlineCode),
        ],
        [
            .symbol("link", .link),
            .symbol("text.badge.plus", .noteLink),
            .symbol("checkmark.circle", .taskReference),
        ],
        [
            .symbol("list.bullet", .unorderedList),
            .symbol("list.number", .orderedList),
            .symbol("checklist", .todoList),
            .symbol("text.quote", .quote),
        ],
        [
            .symbol("curlybraces.square", .codeBlock),
            .symbol("minus", .divider),
        ],
    ]

    static var items: [MarkdownFormatToolbarItem] { groups.flatMap { $0 } }

    /// The indices of `items` a full-width toolbar draws a separator before.
    static var separatorIndices: Set<Int> {
        var indices = Set<Int>()
        var start = 0
        for group in groups.dropLast() {
            start += group.count
            indices.insert(start)
        }
        return indices
    }

    /// What a compact (iPhone-width) row keeps in line; every other item goes into its overflow
    /// menu, in catalog order.
    static let compactCommands: [MarkdownFormatCommand] = [
        .bold, .italic, .link, .unorderedList, .todoList, .noteLink,
    ]

    static var compactItems: [MarkdownFormatToolbarItem] {
        compactCommands.compactMap { command in items.first(where: { $0.command == command }) }
    }

    static var compactOverflowItems: [MarkdownFormatToolbarItem] {
        items.filter { !compactCommands.contains($0.command) }
    }
}

extension MarkdownSlashCommand {
    /// **What a bare `/` offers at a host, on both platforms ([[T-8584]]).** The built-ins, then
    /// the host's note templates, less the image command where the host refuses images. The Mac
    /// appended templates and iOS never did, so on iPhone and iPad a template was reachable only
    /// from the toolbar's menu; a typed `/` is not an input one platform lacks.
    nonisolated static func offered(templates: [NoteTemplate], allowingImages: Bool) -> [MarkdownSlashCommand] {
        let all = MarkdownSlashCommand.all + MarkdownSlashCommand.templateCommands(for: templates)
        return allowingImages ? all : MarkdownSlashCommand.refusingImageInsertion(all)
    }
}

extension MarkdownReferenceCompletionSupport {
    /// **How many `[[` matches the inline menu shows, on both platforms ([[T-8584]]).** The Mac's
    /// picker kept 8 and iOS's strip kept 6; the strip scrolls sideways, so the smaller number was
    /// never a screen limit.
    nonisolated static let inlineShortlistLimit = 8
}
