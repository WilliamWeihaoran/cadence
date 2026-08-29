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
