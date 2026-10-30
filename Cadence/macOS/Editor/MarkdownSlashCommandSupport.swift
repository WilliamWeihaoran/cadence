#if os(macOS)
import SwiftUI
import AppKit

private func markdownPickerCaretAnchorRect(for textView: NSTextView, at characterIndex: Int) -> NSRect {
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

private struct MarkdownSlashCommandPickerView: View {
    let commands: [MarkdownSlashCommand]
    let highlightedIndex: Int
    let onSelect: (MarkdownSlashCommand) -> Void

    var body: some View {
        // [[T-7233]]: a bare `/` lists every built-in plus the note's templates (~22 rows), and the
        // uncapped stack drew a popover ~580pt tall that fit neither above nor below the caret on a
        // 13-inch screen. The list now shows at most `visibleRowLimit` rows and scrolls the rest,
        // keeping the keyboard-highlighted row in view as the arrow keys walk it.
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                rows
            }
            .scrollIndicators(commands.count > MarkdownSlashCommandPickerMetrics.visibleRowLimit ? .automatic : .never)
            .frame(height: MarkdownSlashCommandPickerMetrics.listHeight(forRowCount: commands.count))
            .onAppear { scrollToHighlighted(proxy) }
            .onChange(of: highlightedIndex) { _, _ in scrollToHighlighted(proxy) }
        }
        .padding(6)
        .frame(width: MarkdownSlashCommandPickerMetrics.pickerWidth(for: commands))
        .background(Color(nsColor: MarkdownStylist.bgColor))
    }

    private func scrollToHighlighted(_ proxy: ScrollViewProxy) {
        guard commands.indices.contains(highlightedIndex) else { return }
        proxy.scrollTo(commands[highlightedIndex].id)
    }

    private var rows: some View {
        VStack(spacing: MarkdownSlashCommandPickerMetrics.rowSpacing) {
            ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
                Button {
                    onSelect(command)
                } label: {
                    HStack(spacing: 8) {
                        Text(MarkdownSlashCommandPickerMetrics.token(for: command))
                            .font(Font(MarkdownSlashCommandPickerMetrics.tokenFont as CTFont))
                            .foregroundStyle(Color(nsColor: MarkdownStylist.blueColor))
                            .lineLimit(1)
                            .frame(width: tokenColumnWidth, alignment: .leading)

                        Text(command.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(nsColor: MarkdownStylist.textColor))
                            .lineLimit(1)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: MarkdownSlashCommandPickerMetrics.rowHeight)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.radiusControlCompact, style: .continuous)
                            .fill(index == highlightedIndex ? Color(nsColor: MarkdownStylist.blueColor).opacity(0.16) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .id(command.id)
            }
        }
    }

    private var tokenColumnWidth: CGFloat {
        MarkdownSlashCommandPickerMetrics.tokenColumnWidth(for: commands)
    }
}

/// **[[T-7231]] — the `/` column is as wide as the longest token it is showing.** It was a fixed
/// 54pt, which holds `/h1` through `/strike` and nothing longer: `/highlight` measures ~62pt in
/// this face and every note-template token (`/meeting-notes`, `/weekly-review`, `/research-note`
/// …, appended by `MarkdownEditorView`) ~80-87pt, so those rows wrapped their token onto a second
/// line beside a one-line title. The column now grows to the widest token in the filtered list and
/// the popover grows by the same amount, so the title column keeps exactly the room it had.
/// 54pt stays the floor so a short list does not shrink the picker.
enum MarkdownSlashCommandPickerMetrics {
    static let tokenFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold)
    static let minimumTokenColumnWidth: CGFloat = 54
    static let minimumPickerWidth: CGFloat = 198

    static func token(for command: MarkdownSlashCommand) -> String {
        "/\(command.id)"
    }

    static func tokenWidth(_ token: String) -> CGFloat {
        ceil((token as NSString).size(withAttributes: [.font: tokenFont]).width)
    }

    static func tokenColumnWidth(for commands: [MarkdownSlashCommand]) -> CGFloat {
        let widest = commands.map { tokenWidth(token(for: $0)) }.max() ?? 0
        return max(minimumTokenColumnWidth, widest)
    }

    static func pickerWidth(for commands: [MarkdownSlashCommand]) -> CGFloat {
        minimumPickerWidth + (tokenColumnWidth(for: commands) - minimumTokenColumnWidth)
    }

    /// [[T-7233]] — the list's height cap. A row is a fixed `rowHeight` (the 11pt title line plus
    /// the 5pt top and bottom padding it used to take), so the list's height is exact arithmetic
    /// rather than a measurement, and `visibleRowLimit` rows is the most it ever shows at once.
    static let visibleRowLimit = 9
    static let rowHeight: CGFloat = 24
    static let rowSpacing: CGFloat = 2

    static func visibleRowCount(forRowCount count: Int) -> Int {
        min(max(count, 0), visibleRowLimit)
    }

    static func listHeight(forRowCount count: Int) -> CGFloat {
        let visible = visibleRowCount(forRowCount: count)
        guard visible > 0 else { return 0 }
        return CGFloat(visible) * rowHeight + CGFloat(visible - 1) * rowSpacing
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
        commands allCommands: [MarkdownSlashCommand] = MarkdownSlashCommand.all,
        onSelect: @escaping (MarkdownSlashCommand, MarkdownSlashCommandContext) -> Void
    ) {
        self.textView = textView
        self.onSelect = onSelect

        guard let context else {
            close()
            return
        }

        let filtered = MarkdownSlashCommand.matching(allCommands, query: context.query)

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
        let anchorRect = markdownPickerCaretAnchorRect(for: textView, at: context.cursorLocation)

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
                        RoundedRectangle(cornerRadius: Theme.radiusControlCompact, style: .continuous)
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
            .filter { $0.matches(query: query) }
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
        let anchorRect = markdownPickerCaretAnchorRect(for: textView, at: context.cursorLocation)

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
}

struct MarkdownTagCompletionContext {
    let range: NSRange
    let query: String
    let cursorLocation: Int
}

enum MarkdownTagCompletionTokenSupport {
    static func token(in text: NSString, cursor: Int) -> MarkdownTagCompletionContext? {
        let safeCursor = min(max(cursor, 0), text.length)
        let lineRange = text.lineRange(for: NSRange(location: max(0, safeCursor - 1), length: 0))
        guard safeCursor >= lineRange.location else { return nil }

        var queryStart = safeCursor
        while queryStart > lineRange.location {
            let previous = text.character(at: queryStart - 1)
            if isTagBodyCharacter(previous) {
                queryStart -= 1
            } else {
                break
            }
        }

        let hashLocation = queryStart - 1
        guard hashLocation >= lineRange.location,
              hashLocation < text.length,
              text.character(at: hashLocation) == 35 else { return nil }

        if hashLocation > lineRange.location {
            let beforeHash = text.character(at: hashLocation - 1)
            guard beforeHash != 35, !isTagBodyCharacter(beforeHash) else { return nil }
        }

        let queryRange = NSRange(location: hashLocation + 1, length: safeCursor - hashLocation - 1)
        let query = text.substring(with: queryRange)
        guard query.count <= 64 else { return nil }

        return MarkdownTagCompletionContext(
            range: NSRange(location: hashLocation, length: safeCursor - hashLocation),
            query: query,
            cursorLocation: safeCursor
        )
    }

    private static func isTagBodyCharacter(_ character: unichar) -> Bool {
        (character >= 48 && character <= 57) ||
        (character >= 65 && character <= 90) ||
        (character >= 97 && character <= 122) ||
        character == 45 ||
        character == 95
    }
}

enum MarkdownTagPickerChoice: Hashable {
    case existing(MarkdownTagSuggestion)
    case create(String)
}

private struct MarkdownTagPickerView: View {
    let query: String
    let choices: [MarkdownTagPickerChoice]
    let highlightedIndex: Int
    let onSelect: (MarkdownTagPickerChoice) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(nsColor: MarkdownStylist.dimColor))
                Text(query.isEmpty ? "Tags" : "#\(TagSupport.slug(for: query))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(nsColor: MarkdownStylist.textColor))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()
                .background(Color(nsColor: MarkdownStylist.codeBorder))

            VStack(spacing: 2) {
                ForEach(Array(choices.enumerated()), id: \.offset) { index, choice in
                    Button {
                        onSelect(choice)
                    } label: {
                        row(for: choice, isHighlighted: index == highlightedIndex)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
        }
        .frame(width: 252)
        .background(Color(nsColor: MarkdownStylist.bgColor))
    }

    @ViewBuilder
    private func row(for choice: MarkdownTagPickerChoice, isHighlighted: Bool) -> some View {
        switch choice {
        case .existing(let tag):
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: tag.colorHex))
                    .frame(width: 8, height: 8)
                    .opacity(tag.isArchived ? 0.55 : 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(tag.name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(nsColor: MarkdownStylist.textColor))
                        .lineLimit(1)
                    Text(tag.isArchived ? "Restore archived tag" : tag.slug)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color(nsColor: MarkdownStylist.dimColor))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(rowBackground(isHighlighted))
            .opacity(tag.isArchived ? 0.75 : 1)
        case .create(let name):
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(nsColor: MarkdownStylist.blueColor))
                    .frame(width: 12)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Create #\(TagSupport.slug(for: name))")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(nsColor: MarkdownStylist.textColor))
                        .lineLimit(1)
                    Text("Add a new global tag")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color(nsColor: MarkdownStylist.dimColor))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(rowBackground(isHighlighted))
        }
    }

    private func rowBackground(_ isHighlighted: Bool) -> some View {
        RoundedRectangle(cornerRadius: Theme.radiusControlCompact, style: .continuous)
            .fill(isHighlighted ? Color(nsColor: MarkdownStylist.blueColor).opacity(0.16) : Color.clear)
    }
}

final class MarkdownTagPickerController {
    private let popover = NSPopover()
    private var onSelect: ((MarkdownTagPickerChoice, MarkdownTagCompletionContext) -> Void)?
    private(set) var context: MarkdownTagCompletionContext?
    private(set) var choices: [MarkdownTagPickerChoice] = []
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
        context: MarkdownTagCompletionContext?,
        suggestions allSuggestions: [MarkdownTagSuggestion],
        onSelect: @escaping (MarkdownTagPickerChoice, MarkdownTagCompletionContext) -> Void
    ) {
        self.onSelect = onSelect

        guard let context else {
            close()
            return
        }

        let query = context.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let querySlug = TagSupport.slug(for: query)
        let matches = allSuggestions
            .filter { suggestion in
                if query.isEmpty {
                    return !suggestion.isArchived
                }
                return suggestion.name.localizedCaseInsensitiveContains(query) ||
                    suggestion.slug.localizedCaseInsensitiveContains(querySlug)
            }
            .prefix(8)
            .map(MarkdownTagPickerChoice.existing)

        var nextChoices = Array(matches)
        if nextChoices.isEmpty,
           !query.isEmpty,
           TagSupport.displayName(for: query).rangeOfCharacter(from: .alphanumerics) != nil {
            nextChoices.append(.create(TagSupport.displayName(for: query)))
        }

        guard !nextChoices.isEmpty else {
            close()
            return
        }

        self.context = context
        choices = nextChoices
        highlightedIndex = min(highlightedIndex, max(nextChoices.count - 1, 0))

        let rootView = MarkdownTagPickerView(
            query: query,
            choices: nextChoices,
            highlightedIndex: highlightedIndex
        ) { choice in
            onSelect(choice, context)
        }

        popover.contentViewController = NSHostingController(rootView: rootView)
        let anchorRect = markdownPickerCaretAnchorRect(for: textView, at: context.cursorLocation)

        if popover.isShown {
            popover.positioningRect = anchorRect
            if let content = popover.contentViewController as? NSHostingController<MarkdownTagPickerView> {
                content.rootView = rootView
            }
        } else {
            popover.show(relativeTo: anchorRect, of: textView, preferredEdge: .maxY)
        }
    }

    func moveSelection(delta: Int) {
        guard !choices.isEmpty else { return }
        highlightedIndex = min(max(0, highlightedIndex + delta), choices.count - 1)
        refresh()
    }

    func applyHighlighted(_ handler: (MarkdownTagPickerChoice, MarkdownTagCompletionContext) -> Void) -> Bool {
        guard let context, choices.indices.contains(highlightedIndex) else { return false }
        handler(choices[highlightedIndex], context)
        return true
    }

    func close() {
        context = nil
        choices = []
        highlightedIndex = 0
        onSelect = nil
        popover.close()
    }

    private func refresh() {
        guard popover.isShown,
              let content = popover.contentViewController as? NSHostingController<MarkdownTagPickerView>,
              let context,
              let onSelect else { return }
        content.rootView = MarkdownTagPickerView(
            query: context.query,
            choices: choices,
            highlightedIndex: highlightedIndex,
            onSelect: { choice in
                onSelect(choice, context)
            }
        )
    }
}
#endif
