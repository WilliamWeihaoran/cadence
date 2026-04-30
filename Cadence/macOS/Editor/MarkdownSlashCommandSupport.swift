#if os(macOS)
import SwiftUI
import AppKit

struct MarkdownSlashCommand: Identifiable {
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
        .init(id: "todo", title: "To-do", subtitle: "Unchecked task item", replacement: (indentation: "", text: "[ ] ", caretOffset: 4)),
        .init(id: "done", title: "Done", subtitle: "Checked task item", replacement: (indentation: "", text: "● ", caretOffset: 2)),
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
}

struct MarkdownSlashCommandContext {
    let range: NSRange
    let indentation: String
    let query: String
    let cursorLocation: Int
}

enum MarkdownSlashCommandTokenSupport {
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

private struct MarkdownSlashCommandPickerView: View {
    let commands: [MarkdownSlashCommand]
    let highlightedIndex: Int
    let onSelect: (MarkdownSlashCommand) -> Void

    var body: some View {
        VStack(spacing: 2) {
            ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
                Button {
                    onSelect(command)
                } label: {
                    HStack(spacing: 8) {
                        Text("/\(command.id)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color(nsColor: MarkdownStylist.blueColor))
                            .frame(width: 54, alignment: .leading)

                        Text(command.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(nsColor: MarkdownStylist.textColor))
                            .lineLimit(1)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(index == highlightedIndex ? Color(nsColor: MarkdownStylist.blueColor).opacity(0.16) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .frame(width: 198)
        .background(Color(nsColor: MarkdownStylist.bgColor))
    }
}

final class MarkdownSlashCommandPickerController {
    private let popover = NSPopover()
    private weak var textView: NSTextView?
    private var onSelect: ((MarkdownSlashCommand, MarkdownSlashCommandContext) -> Void)?
    private(set) var context: MarkdownSlashCommandContext?
    private(set) var commands: [MarkdownSlashCommand] = []
    private(set) var highlightedIndex: Int = 0

    init() {
        popover.behavior = .transient
        popover.animates = false
    }

    var isShown: Bool {
        popover.isShown
    }

    func update(
        for textView: NSTextView,
        context: MarkdownSlashCommandContext?,
        onSelect: @escaping (MarkdownSlashCommand, MarkdownSlashCommandContext) -> Void
    ) {
        self.textView = textView
        self.onSelect = onSelect

        guard let context else {
            close()
            return
        }

        let filtered = MarkdownSlashCommand.all.filter {
            context.query.isEmpty || $0.id.localizedCaseInsensitiveContains(context.query) || $0.title.localizedCaseInsensitiveContains(context.query)
        }

        guard !filtered.isEmpty else {
            close()
            return
        }

        self.context = context
        commands = filtered
        highlightedIndex = min(highlightedIndex, max(filtered.count - 1, 0))

        let rootView = MarkdownSlashCommandPickerView(
            commands: filtered,
            highlightedIndex: highlightedIndex
        ) { command in
            onSelect(command, context)
        }

        popover.contentViewController = NSHostingController(rootView: rootView)
        let anchorRect = caretAnchorRect(for: textView, at: context.cursorLocation)

        if popover.isShown {
            popover.positioningRect = anchorRect
            if let content = popover.contentViewController as? NSHostingController<MarkdownSlashCommandPickerView> {
                content.rootView = rootView
            }
        } else {
            popover.show(relativeTo: anchorRect, of: textView, preferredEdge: .maxY)
        }
    }

    func moveSelection(delta: Int) {
        guard !commands.isEmpty else { return }
        highlightedIndex = min(max(0, highlightedIndex + delta), commands.count - 1)
        refresh()
    }

    func applyHighlighted(_ handler: (MarkdownSlashCommand, MarkdownSlashCommandContext) -> Void) -> Bool {
        guard let context, commands.indices.contains(highlightedIndex) else { return false }
        handler(commands[highlightedIndex], context)
        return true
    }

    func close() {
        context = nil
        commands = []
        highlightedIndex = 0
        onSelect = nil
        popover.close()
    }

    private func refresh() {
        guard popover.isShown,
              let content = popover.contentViewController as? NSHostingController<MarkdownSlashCommandPickerView>,
              let context,
              let onSelect else { return }
        content.rootView = MarkdownSlashCommandPickerView(
            commands: commands,
            highlightedIndex: highlightedIndex,
            onSelect: { command in
                onSelect(command, context)
            }
        )
    }

    private func caretAnchorRect(for textView: NSTextView, at characterIndex: Int) -> NSRect {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return NSRect(x: textView.textContainerInset.width, y: textView.textContainerInset.height, width: 1, height: 18)
        }

        let length = (textView.string as NSString).length
        let safeIndex = min(max(characterIndex, 0), length)
        layoutManager.ensureLayout(for: textContainer)
        let origin = textView.textContainerOrigin

        if safeIndex < length, layoutManager.numberOfGlyphs > 0 {
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: safeIndex)
            let lineRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            let glyphLocation = layoutManager.location(forGlyphAt: glyphIndex)
            return NSRect(
                x: origin.x + lineRect.minX + glyphLocation.x,
                y: origin.y + lineRect.minY,
                width: 1,
                height: max(lineRect.height, 18)
            )
        }

        guard layoutManager.numberOfGlyphs > 0 else {
            return NSRect(x: origin.x, y: origin.y, width: 1, height: 18)
        }

        let fallbackGlyphIndex = max(layoutManager.numberOfGlyphs - 1, 0)
        let lineRect = layoutManager.lineFragmentUsedRect(forGlyphAt: fallbackGlyphIndex, effectiveRange: nil)
        return NSRect(
            x: origin.x + lineRect.maxX,
            y: origin.y + lineRect.minY,
            width: 1,
            height: max(lineRect.height, 18)
        )
    }
}

struct MarkdownReferenceCompletionContext {
    let range: NSRange
    let kind: MarkdownReferenceKind
    let query: String
    let cursorLocation: Int
}

private struct MarkdownReferencePickerView: View {
    let suggestions: [MarkdownReferenceSuggestion]
    let highlightedIndex: Int
    let onSelect: (MarkdownReferenceSuggestion) -> Void

    var body: some View {
        VStack(spacing: 2) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                Button {
                    onSelect(suggestion)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: suggestion.kind == .task ? "checkmark.circle" : "doc.text")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(nsColor: suggestion.kind == .task ? MarkdownStylist.greenColor : MarkdownStylist.blueColor))
                            .frame(width: 15)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(suggestion.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color(nsColor: MarkdownStylist.textColor))
                                .lineLimit(1)
                            Text(suggestion.subtitle)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Color(nsColor: MarkdownStylist.dimColor))
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(index == highlightedIndex ? Color(nsColor: MarkdownStylist.blueColor).opacity(0.16) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .frame(width: 236)
        .background(Color(nsColor: MarkdownStylist.bgColor))
    }
}

final class MarkdownReferencePickerController {
    private let popover = NSPopover()
    private var onSelect: ((MarkdownReferenceSuggestion, MarkdownReferenceCompletionContext) -> Void)?
    private(set) var context: MarkdownReferenceCompletionContext?
    private(set) var suggestions: [MarkdownReferenceSuggestion] = []
    private(set) var highlightedIndex: Int = 0

    init() {
        popover.behavior = .transient
        popover.animates = false
    }

    var isShown: Bool {
        popover.isShown
    }

    func update(
        for textView: NSTextView,
        context: MarkdownReferenceCompletionContext?,
        suggestions allSuggestions: [MarkdownReferenceSuggestion],
        onSelect: @escaping (MarkdownReferenceSuggestion, MarkdownReferenceCompletionContext) -> Void
    ) {
        self.onSelect = onSelect

        guard let context else {
            close()
            return
        }

        let query = context.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = allSuggestions
            .filter { $0.kind == context.kind }
            .filter {
                query.isEmpty ||
                    $0.title.localizedCaseInsensitiveContains(query) ||
                    $0.subtitle.localizedCaseInsensitiveContains(query)
            }
            .prefix(8)

        let matches = Array(filtered)
        guard !matches.isEmpty else {
            close()
            return
        }

        self.context = context
        suggestions = matches
        highlightedIndex = min(highlightedIndex, max(matches.count - 1, 0))

        let rootView = MarkdownReferencePickerView(
            suggestions: matches,
            highlightedIndex: highlightedIndex
        ) { suggestion in
            onSelect(suggestion, context)
        }

        popover.contentViewController = NSHostingController(rootView: rootView)
        let anchorRect = caretAnchorRect(for: textView, at: context.cursorLocation)

        if popover.isShown {
            popover.positioningRect = anchorRect
            if let content = popover.contentViewController as? NSHostingController<MarkdownReferencePickerView> {
                content.rootView = rootView
            }
        } else {
            popover.show(relativeTo: anchorRect, of: textView, preferredEdge: .maxY)
        }
    }

    func moveSelection(delta: Int) {
        guard !suggestions.isEmpty else { return }
        highlightedIndex = min(max(0, highlightedIndex + delta), suggestions.count - 1)
        refresh()
    }

    func applyHighlighted(_ handler: (MarkdownReferenceSuggestion, MarkdownReferenceCompletionContext) -> Void) -> Bool {
        guard let context, suggestions.indices.contains(highlightedIndex) else { return false }
        handler(suggestions[highlightedIndex], context)
        return true
    }

    func close() {
        context = nil
        suggestions = []
        highlightedIndex = 0
        onSelect = nil
        popover.close()
    }

    private func refresh() {
        guard popover.isShown,
              let content = popover.contentViewController as? NSHostingController<MarkdownReferencePickerView>,
              let context,
              let onSelect else { return }
        content.rootView = MarkdownReferencePickerView(
            suggestions: suggestions,
            highlightedIndex: highlightedIndex,
            onSelect: { suggestion in
                onSelect(suggestion, context)
            }
        )
    }

    private func caretAnchorRect(for textView: NSTextView, at characterIndex: Int) -> NSRect {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return NSRect(x: textView.textContainerInset.width, y: textView.textContainerInset.height, width: 1, height: 18)
        }

        let length = (textView.string as NSString).length
        let safeIndex = min(max(characterIndex, 0), length)
        layoutManager.ensureLayout(for: textContainer)
        let origin = textView.textContainerOrigin

        if safeIndex < length, layoutManager.numberOfGlyphs > 0 {
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: safeIndex)
            let lineRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            let glyphLocation = layoutManager.location(forGlyphAt: glyphIndex)
            return NSRect(
                x: origin.x + lineRect.minX + glyphLocation.x,
                y: origin.y + lineRect.minY,
                width: 1,
                height: max(lineRect.height, 18)
            )
        }

        guard layoutManager.numberOfGlyphs > 0 else {
            return NSRect(x: origin.x, y: origin.y, width: 1, height: 18)
        }

        let fallbackGlyphIndex = max(layoutManager.numberOfGlyphs - 1, 0)
        let lineRect = layoutManager.lineFragmentUsedRect(forGlyphAt: fallbackGlyphIndex, effectiveRange: nil)
        return NSRect(
            x: origin.x + lineRect.maxX,
            y: origin.y + lineRect.minY,
            width: 1,
            height: max(lineRect.height, 18)
        )
    }
}
#endif
