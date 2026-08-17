#if os(iOS)
import SwiftUI

// The chrome around the iOS markdown editor: the reference picker sheet, the `[[reference]]` and
// `/command` suggestion strips, the format toolbar, the empty-body placeholder and the status bar.
//
// Everything here is built out of `iOSDesignSystem.swift` (`iOSIconTile`, `iOSInlineEmpty`,
// `.iosPressable`) and the shared tokens (`Theme`, `SectionEyebrowLabel`) rather than assembling
// another plate inline — these surfaces had each grown their own radius, their own border alpha
// and their own accent for the same job.

// MARK: - Shared plate
//
// The one resting plate an editor-chrome control wears. Deliberately the same fill, hairline and
// radius as `iOSIconButton`'s in `iOSDesignSystem.swift`, so the format toolbar, the suggestion
// pills and the design system's own icon buttons read as one family of controls rather than three.

private enum iOSMarkdownChromeMetrics {
    static let plateFill = Theme.surfaceElevated.opacity(0.55)
    static let plateBorder = Theme.borderSubtle.opacity(0.45)
    static let cornerRadius = Theme.radiusControl
    /// Visual plate size for a single-glyph control.
    static let buttonPlate: CGFloat = 38
    /// Touch floor. Every control here clears it whatever its plate measures.
    static let touchTarget: CGFloat = 44
    /// Suggestion pills are one touch target tall, so a strip appearing over the keyboard does not
    /// change height between "matches" and "no matches".
    static let pillHeight: CGFloat = 44
}

private struct iOSMarkdownChromePlate: ViewModifier {
    var width: CGFloat? = nil
    var height: CGFloat = iOSMarkdownChromeMetrics.buttonPlate
    var horizontalPadding: CGFloat = 0

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: iOSMarkdownChromeMetrics.cornerRadius, style: .continuous)

        return content
            .padding(.horizontal, horizontalPadding)
            .frame(width: width, height: height)
            .background(shape.fill(iOSMarkdownChromeMetrics.plateFill))
            .overlay(shape.strokeBorder(iOSMarkdownChromeMetrics.plateBorder, lineWidth: 1))
            .frame(minWidth: iOSMarkdownChromeMetrics.touchTarget, minHeight: iOSMarkdownChromeMetrics.touchTarget)
            .contentShape(Rectangle())
    }
}

// MARK: - Reference picker sheet

enum iOSMarkdownReferencePickerKind: String, Identifiable {
    case note
    case task

    var id: String { rawValue }

    var title: String {
        switch self {
        case .note: return "Insert Note Link"
        case .task: return "Insert Task Reference"
        }
    }

    var emptyTitle: String {
        switch self {
        case .note: return "No notes yet"
        case .task: return "No tasks yet"
        }
    }

    var emptySubtitle: String {
        switch self {
        case .note: return "Create or open a note first, then link it here."
        case .task: return "Create a task first, then reference it here."
        }
    }

    var emptyIcon: String {
        switch self {
        case .note: return "doc.text.magnifyingglass"
        case .task: return "checklist"
        }
    }
}

struct iOSMarkdownReferencePickerSheet: View {
    let kind: iOSMarkdownReferencePickerKind
    let notes: [Note]
    let tasks: [AppTask]
    let insert: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filteredNotes: [Note] {
        notes
            .filter { matches($0.displayTitle) || matches($0.content) }
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
                return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
            }
    }

    private var filteredTasks: [AppTask] {
        tasks
            .filter { !$0.isCancelled }
            .filter { matches($0.title) || matches($0.notes) || matches($0.containerName) }
            .sorted { lhs, rhs in
                if lhs.isDone != rhs.isDone { return !lhs.isDone && rhs.isDone }
                if lhs.priority.rank != rhs.priority.rank {
                    return lhs.priority.rank > rhs.priority.rank
                }
                if lhs.order != rhs.order { return lhs.order < rhs.order }
                return lhs.createdAt > rhs.createdAt
            }
    }

    private var isEmpty: Bool {
        switch kind {
        case .note: return filteredNotes.isEmpty
        case .task: return filteredTasks.isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isEmpty {
                    // The shared pane-level empty state rather than a fourth hand-rolled
                    // icon/title/subtitle stack. Picker empty states keep their subtitle — it
                    // says something the screen does not.
                    iOSEmptyPanel(
                        systemImage: kind.emptyIcon,
                        title: kind.emptyTitle,
                        subtitle: kind.emptySubtitle
                    )
                } else {
                    referenceList
                }
            }
            .background(Theme.surface.ignoresSafeArea())
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    /// A plain scrolling column rather than a `List`. `List` brought its own inset, separator and
    /// selection plate, so every row carried system chrome at a system radius underneath the app's
    /// own row treatment — two layers at two radii for one row.
    private var referenceList: some View {
        // Built once per pass rather than once per row, and only on the side that shows note text:
        // the task rows carry no excerpt, so a map there would be built and never read. See
        // `MarkdownTaskEmbedTitleCache` and `iOSMarkdownNoteReferenceRow.preview`.
        let taskTitles = kind == .note ? MarkdownTaskEmbedTitleCache.titles(for: tasks) : [:]

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                switch kind {
                case .note:
                    ForEach(filteredNotes) { note in
                        Button {
                            insert(NoteReferenceParser.noteReferenceMarkdown(for: note))
                            dismiss()
                        } label: {
                            iOSMarkdownNoteReferenceRow(note: note, taskTitles: taskTitles)
                        }
                        .buttonStyle(.iosPressable)
                    }
                case .task:
                    ForEach(filteredTasks) { task in
                        Button {
                            insert(NoteReferenceParser.taskReferenceMarkdown(for: task))
                            dismiss()
                        } label: {
                            iOSMarkdownTaskReferenceRow(task: task)
                        }
                        .buttonStyle(.iosPressable)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    private func matches(_ value: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return value.localizedCaseInsensitiveContains(trimmed)
    }
}

private struct iOSMarkdownNoteReferenceRow: View {
    let note: Note
    /// Live task titles for `preview`, built once by the list rather than once per row.
    let taskTitles: [UUID: String]

    private var subtitle: String {
        switch note.kind {
        case .daily:
            return note.dateKey.isEmpty ? "Daily note" : note.dateKey
        case .weekly:
            return note.weekKey.isEmpty ? "Weekly note" : note.weekKey
        case .permanent:
            return "Notepad"
        case .list:
            return "Linked note"
        case .meeting:
            return note.eventDateKey.isEmpty ? "Event note" : "Event · \(note.eventDateKey)"
        }
    }

    /// Excerpted from the note's text with embed titles resolved against the live tasks first — the
    /// title stored in `[[task:UUID|Title]]` is a cache, so the raw string names a renamed task by
    /// its old name. See `iOSMeetingNoteRow.preview`, which carries the same note.
    private var preview: String {
        let resolved = MarkdownTaskEmbedTitleCache.resolving(note.content, titles: taskTitles)
        let preview = CadenceMarkdownPresentationSupport.plainPreviewText(from: resolved, limit: 120)
        return preview.isEmpty ? "Empty note" : preview
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            iOSIconTile(systemImage: "doc.text", color: Theme.blue)

            VStack(alignment: .leading, spacing: 4) {
                Text(note.displayTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.subdued)
                    .lineLimit(1)
                Text(preview)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct iOSMarkdownTaskReferenceRow: View {
    let task: AppTask

    private var title: String {
        let trimmed = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Task" : trimmed
    }

    private var subtitle: String {
        var parts: [String] = []
        if !task.containerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(task.containerName)
        }
        if !task.scheduledDate.isEmpty {
            parts.append("Do \(CadenceTaskPresentationSupport.scheduledDateLabel(for: task))")
        } else if !task.dueDate.isEmpty {
            parts.append("Due \(CadenceTaskPresentationSupport.dueDateLabel(for: task))")
        }
        if task.isDone {
            parts.append("Completed")
        }
        return parts.isEmpty ? "Inbox" : parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            iOSIconTile(
                systemImage: task.isDone ? "checkmark.circle.fill" : "circle",
                color: task.isDone ? Theme.green : Theme.blue,
                iconSize: 16
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(task.isDone ? Theme.muted : Theme.text)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.subdued)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

// MARK: - Suggestion strips

/// The strip above the editor that offers `[[reference]]` completions or `/command`s.
///
/// One view for both. They were two structs differing only in their label, their empty sentence
/// and which accent their leading glyph took — which is how one ended up purple and the other blue
/// for the same job. The eyebrow is the shared `SectionEyebrowLabel`, so it matches every other
/// small-caps section label in the app, and the strip sits in a `Theme.surfaceRecessed` well: a
/// real stop on the neutral ramp instead of the app background at a hand-picked alpha.
struct iOSMarkdownSuggestionStrip<Content: View>: View {
    let label: String
    let query: String
    let emptyText: String
    let isEmpty: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SectionEyebrowLabel(text: label)

                if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(query)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            if isEmpty {
                iOSInlineEmpty(text: emptyText)
                    .frame(height: iOSMarkdownChromeMetrics.pillHeight)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) { content }
                        .padding(.trailing, 12)
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.surfaceRecessed)
    }
}

/// One card in a suggestion strip, wearing the shared editor-chrome plate so a suggestion and a
/// format button are visibly the same kind of control.
private struct iOSMarkdownSuggestionPill<Leading: View>: View {
    let title: String
    let subtitle: String
    let action: () -> Void
    @ViewBuilder let leading: Leading

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                leading

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: 220, alignment: .leading)
            .modifier(iOSMarkdownChromePlate(
                height: iOSMarkdownChromeMetrics.pillHeight,
                horizontalPadding: 10
            ))
        }
        .buttonStyle(.iosPressable)
    }
}

struct iOSMarkdownReferenceCompletionChoice: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let markdown: String
}

struct iOSMarkdownReferenceCompletionStrip: View {
    let context: MarkdownReferenceCompletionContext
    let choices: [iOSMarkdownReferenceCompletionChoice]
    let insert: (String) -> Void

    private var label: String {
        switch context.kind {
        case .note: return "Notes"
        case .task: return "Tasks"
        }
    }

    private var emptyText: String {
        switch context.kind {
        case .note: return "No matching notes"
        case .task: return "No matching tasks"
        }
    }

    var body: some View {
        iOSMarkdownSuggestionStrip(
            label: label,
            query: context.query,
            emptyText: emptyText,
            isEmpty: choices.isEmpty
        ) {
            ForEach(choices) { choice in
                iOSMarkdownSuggestionPill(
                    title: choice.title,
                    subtitle: choice.subtitle,
                    action: { insert(choice.markdown) }
                ) {
                    iOSIconTile(
                        systemImage: choice.systemImage,
                        color: choice.tint,
                        size: 26,
                        iconSize: 12,
                        bordered: false
                    )
                }
            }
        }
    }
}

struct iOSMarkdownSlashCommandStrip: View {
    let context: MarkdownSlashCommandContext
    let commands: [MarkdownSlashCommand]
    let apply: (MarkdownSlashCommand) -> Void

    var body: some View {
        iOSMarkdownSuggestionStrip(
            label: "Commands",
            query: context.query.isEmpty ? "" : "/\(context.query)",
            emptyText: "No matching commands",
            isEmpty: commands.isEmpty
        ) {
            ForEach(commands) { command in
                iOSMarkdownSuggestionPill(
                    title: command.title,
                    subtitle: command.subtitle,
                    action: { apply(command) }
                ) {
                    // The command's own token, in the mono face the editor uses for markdown
                    // syntax. It reads as syntax rather than as a link, so the accent is not
                    // spent once per row on a list where every row is equally actionable.
                    Text("/\(command.id)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                        .frame(minWidth: 38, alignment: .leading)
                }
            }
        }
    }
}

// MARK: - Format toolbar

struct iOSMarkdownFormatToolbar: View {
    let apply: (MarkdownFormatCommand) -> Void
    let chooseImages: () -> Void
    /// Set to put the note's template menu in this row rather than in the page header.
    ///
    /// Applying a template inserts markdown into the note, which is what every other control here
    /// does — so this is where it belongs, and on the phone it is also the only place it fits: the
    /// Notes header spends its row on the date, four tabs and a back control, and a week range
    /// (`Aug 17–23`) truncated with the button beside it. This row is a horizontal scroller, so an
    /// extra control costs it nothing.
    var templateKind: NoteKind? = nil
    var applyTemplate: ((NoteTemplate) -> Void)? = nil

    /// One touch target plus the row's own padding.
    static let height: CGFloat = iOSMarkdownChromeMetrics.touchTarget + 12

    /// Indices the full toolbar draws a separator *before*, grouping block style / inline style /
    /// lists / blocks / references.
    private static let fullSeparatorIndices: Set<Int> = [3, 8, 11, 14]
    private static let compactWidthThreshold: CGFloat = 620

    private let primaryItems: [iOSMarkdownFormatToolbarItem] = [
        .text("P", "Paragraph", .paragraph),
        .text("H1", "Heading 1", .heading(1)),
        .text("H2", "Heading 2", .heading(2)),
        .icon("bold", "Bold", .bold),
        .icon("italic", "Italic", .italic),
        .icon("strikethrough", "Strikethrough", .strikethrough),
        .icon("chevron.left.forwardslash.chevron.right", "Inline Code", .inlineCode),
        .icon("link", "Link", .link),
        .icon("list.bullet", "Bulleted List", .unorderedList),
        .icon("list.number", "Numbered List", .orderedList),
        .icon("checklist", "Checklist", .todoList),
        .icon("text.quote", "Quote", .quote),
        .icon("curlybraces.square", "Code Block", .codeBlock),
        .icon("minus", "Divider", .divider),
        .icon("text.badge.plus", "Note Link", .noteLink),
        .icon("checkmark.circle", "Task Reference", .taskReference)
    ]

    private var compactItems: [iOSMarkdownFormatToolbarItem] {
        [
            .icon("bold", "Bold", .bold),
            .icon("italic", "Italic", .italic),
            .icon("link", "Link", .link),
            .icon("list.bullet", "Bulleted List", .unorderedList),
            .icon("checklist", "Checklist", .todoList),
            .icon("text.badge.plus", "Note Link", .noteLink)
        ]
    }

    private var compactMoreItems: [iOSMarkdownFormatToolbarItem] {
        primaryItems.filter { item in
            !compactItems.contains(where: { $0.id == item.id })
        }
    }

    var body: some View {
        GeometryReader { proxy in
            toolbarRow(isCompact: proxy.size.width < Self.compactWidthThreshold)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
        }
        .frame(height: Self.height)
        .background(Theme.surface)
    }

    /// One row for both widths. The full and compact toolbars were two near-copies that each
    /// repeated the image button and the container chrome; they now differ only in which items
    /// they carry and whether the rest go into an overflow menu.
    ///
    /// The row used to sit on a `cadenceCard` — a shadowed, elevated plate holding buttons that
    /// were themselves plated, so every button read as two elevations above the note it formats.
    /// The card is gone; this is a row of controls on the editor's own surface, closed by the
    /// hairline the editing surface already draws under it.
    private func toolbarRow(isCompact: Bool) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(Array((isCompact ? compactItems : primaryItems).enumerated()), id: \.element.id) { index, item in
                    if !isCompact, Self.fullSeparatorIndices.contains(index) {
                        separator
                    }

                    iOSMarkdownFormatButton(item: item) {
                        apply(item.command)
                    }
                }

                separator

                Button(action: chooseImages) {
                    Image(systemName: "photo")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .modifier(iOSMarkdownChromePlate(width: iOSMarkdownChromeMetrics.buttonPlate))
                }
                .buttonStyle(.iosPressable)
                .accessibilityLabel("Image")

                if let templateKind, let applyTemplate {
                    iOSNoteTemplateMenu(kind: templateKind, compact: true, apply: applyTemplate)
                }

                if isCompact {
                    Menu {
                        ForEach(compactMoreItems) { item in
                            Button {
                                apply(item.command)
                            } label: {
                                if let systemImage = item.systemImage {
                                    Label(item.title, systemImage: systemImage)
                                } else {
                                    Label(item.id, systemImage: item.menuSystemImage)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.text)
                            .modifier(iOSMarkdownChromePlate(width: iOSMarkdownChromeMetrics.buttonPlate))
                    }
                    .accessibilityLabel("More formatting")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .scrollIndicators(.hidden)
    }

    private var separator: some View {
        Capsule()
            .fill(Theme.border)
            .frame(width: 1, height: 20)
            .padding(.horizontal, 4)
    }
}

private struct iOSMarkdownFormatToolbarItem: Identifiable {
    let id: String
    let title: String
    let systemImage: String?
    let command: MarkdownFormatCommand

    static func icon(_ systemImage: String, _ title: String, _ command: MarkdownFormatCommand) -> iOSMarkdownFormatToolbarItem {
        iOSMarkdownFormatToolbarItem(id: title, title: title, systemImage: systemImage, command: command)
    }

    static func text(_ title: String, _ accessibilityTitle: String, _ command: MarkdownFormatCommand) -> iOSMarkdownFormatToolbarItem {
        iOSMarkdownFormatToolbarItem(id: accessibilityTitle, title: title, systemImage: nil, command: command)
    }

    var menuSystemImage: String {
        switch command {
        case .paragraph:
            return "paragraphsign"
        case .heading:
            return "textformat.size"
        default:
            return systemImage ?? "textformat"
        }
    }
}

/// Not `iOSIconButton`: three of the toolbar's items ("P", "H1", "H2") are text glyphs rather than
/// SF Symbols, and a row where half the buttons wore the design system's plate and half wore a
/// hand-made one is exactly the drift this pass exists to remove. It wears the same plate instead.
private struct iOSMarkdownFormatButton: View {
    let item: iOSMarkdownFormatToolbarItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage = item.systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                } else {
                    Text(item.title)
                        .font(.system(size: 12, weight: .bold))
                }
            }
            .foregroundStyle(Theme.text)
            .modifier(iOSMarkdownChromePlate(width: iOSMarkdownChromeMetrics.buttonPlate))
        }
        .buttonStyle(.iosPressable)
        .accessibilityLabel(item.id)
    }
}

// MARK: - Empty body placeholder

/// Ghost text on the first line of an empty note, matching macOS's `NoteEmptyBodyPlaceholder`.
///
/// It used to be a bold near-white line plus three monospace "cheat sheet" chips (`# Heading`,
/// `- [ ] Task`, `**Bold** · [[Link]] · #tag`). The chips restated what the format toolbar and the
/// `/` strip immediately above them already offer, in a third visual idiom, and they were the
/// brightest thing on an otherwise empty screen. What is left is one quiet line saying where the
/// caret is and how to reach the commands.
struct iOSMarkdownEmptyPrompt: View {
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(placeholder)
                .font(.system(size: 15))
                .foregroundStyle(Theme.dim)

            Text("Type / for commands.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.dim)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        // Non-interactive, so a tap anywhere in the empty body still places the caret — which is
        // the thing you came here to do.
        .allowsHitTesting(false)
    }
}
#endif
