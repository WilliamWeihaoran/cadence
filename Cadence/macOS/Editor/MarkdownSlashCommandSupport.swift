#if os(macOS)
import SwiftUI
import AppKit

struct MarkdownSlashCommand: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let replacement: (indentation: String, text: String, caretOffset: Int)

    static let all: [MarkdownSlashCommand] = [
        .init(id: "h1", title: "Heading 1", subtitle: "Large section heading", replacement: (indentation: "", text: "# ", caretOffset: 2)),
        .init(id: "h2", title: "Heading 2", subtitle: "Medium section heading", replacement: (indentation: "", text: "## ", caretOffset: 3)),
        .init(id: "h3", title: "Heading 3", subtitle: "Small section heading", replacement: (indentation: "", text: "### ", caretOffset: 4)),
        .init(id: "todo", title: "To-do", subtitle: "Unchecked task item", replacement: (indentation: "", text: "○ ", caretOffset: 2)),
        .init(id: "done", title: "Done", subtitle: "Checked task item", replacement: (indentation: "", text: "● ", caretOffset: 2)),
        .init(id: "bullet", title: "Bullet List", subtitle: "Bulleted list item", replacement: (indentation: "", text: "• ", caretOffset: 2)),
        .init(id: "number", title: "Numbered List", subtitle: "Ordered list item", replacement: (indentation: "", text: "1. ", caretOffset: 3)),
        .init(id: "quote", title: "Quote", subtitle: "Block quote line", replacement: (indentation: "", text: "> ", caretOffset: 2)),
        .init(id: "code", title: "Code Block", subtitle: "Fenced code block", replacement: (indentation: "", text: "```\n\n```", caretOffset: 4)),
        .init(id: "bold", title: "Bold", subtitle: "Strong text", replacement: (indentation: "", text: "****", caretOffset: 2)),
        .init(id: "italic", title: "Italic", subtitle: "Emphasized text", replacement: (indentation: "", text: "**", caretOffset: 1)),
        .init(id: "strike", title: "Strikethrough", subtitle: "Deleted text", replacement: (indentation: "", text: "~~~~", caretOffset: 2)),
        .init(id: "rule", title: "Divider", subtitle: "Horizontal divider rule", replacement: (indentation: "", text: "---", caretOffset: 3)),
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
        guard let layoutManager = textView.layoutManager else {
            return NSRect(x: textView.textContainerInset.width, y: textView.textContainerInset.height, width: 1, height: 18)
        }

        let length = (textView.string as NSString).length
        let safeIndex = min(max(characterIndex, 0), length)

        if safeIndex < length {
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: safeIndex)
            let lineRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil, withoutAdditionalLayout: true)
            let glyphLocation = layoutManager.location(forGlyphAt: glyphIndex)
            return NSRect(
                x: textView.textContainerInset.width + lineRect.minX + glyphLocation.x,
                y: textView.textContainerInset.height + lineRect.minY,
                width: 1,
                height: max(lineRect.height, 18)
            )
        }

        let fallbackGlyphIndex = max(layoutManager.numberOfGlyphs - 1, 0)
        let lineRect = layoutManager.lineFragmentUsedRect(forGlyphAt: fallbackGlyphIndex, effectiveRange: nil, withoutAdditionalLayout: true)
        return NSRect(
            x: textView.textContainerInset.width + lineRect.maxX,
            y: textView.textContainerInset.height + lineRect.minY,
            width: 1,
            height: max(lineRect.height, 18)
        )
    }
}
#endif
