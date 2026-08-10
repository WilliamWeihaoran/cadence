#if os(macOS)
import SwiftUI

// The three pieces that used to live in the note editor's permanent right-hand panel
// (`NoteMarkdownSidePanel`). That panel was a third column that spent most of its life showing
// empty states, so each piece moved to the moment it is actually wanted:
//
// - Outline    -> a toolbar button, because you reach for an outline to navigate a long note,
//                 not while writing one.
// - Templates  -> off the header entirely. They were a strip of chips above the note, shown while
//                 it was empty; even then they were a permanent row of chrome between the title
//                 and the first line of writing. They now have three homes, none of them a header
//                 row: the placeholder inside the empty body (below), the `/` command menu, and
//                 the Actions popover's "Start With" page.
// - Mentions   -> one quiet line at the foot of the note, with no permanent section header.
//
// The panel's fourth card, "Properties"/"Add frontmatter", was deleted outright rather than
// rehomed: it wrote a YAML block that nothing in the app reads back, duplicating the first-class
// `Tag` model already shown in the note header. Frontmatter *parsing* stays — see
// `MarkdownMetadataParser` — because notes that already carry a block still surface their tags
// through it.

// MARK: - Outline

/// Toolbar button that opens the note's heading outline as a jump list.
///
/// Renders nothing when the note has no headings: the whole point of moving the outline off the
/// permanent panel was to stop the screen carrying a "No headings yet" placeholder.
struct NoteOutlineJumpButton: View {
    let outline: [MarkdownOutlineItem]
    let onJump: (MarkdownOutlineItem) -> Void

    @State private var isPresented = false

    var body: some View {
        if !outline.isEmpty {
            CadenceQuietPillButton(state: .quiet, action: { isPresented = true }) {
                Image(systemName: "list.bullet.indent")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
            .help("Jump to heading")
            .accessibilityLabel("Outline")
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                NoteOutlinePopoverContent(outline: outline) { item in
                    isPresented = false
                    onJump(item)
                }
            }
        }
    }
}

private struct NoteOutlinePopoverContent: View {
    let outline: [MarkdownOutlineItem]
    let onJump: (MarkdownOutlineItem) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(outline) { item in
                    NoteOutlineJumpRow(item: item) { onJump(item) }
                }
            }
            .padding(6)
        }
        .frame(width: 250)
        .frame(maxHeight: 320)
        .background(Theme.surface)
    }
}

private struct NoteOutlineJumpRow: View {
    let item: MarkdownOutlineItem
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Text(item.title)
                    .font(.system(size: 12, weight: item.level <= 2 ? .semibold : .regular))
                    .foregroundStyle(item.level <= 2 ? Theme.text : Theme.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            // Depth is carried by indent and weight alone. The old panel drew a coloured rule per
            // heading, which spent the accent on static structure.
            .padding(.leading, CGFloat(max(0, item.level - 1)) * 12)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                    .fill(isHovered ? Theme.surfaceHighlight : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Templates

/// Ghost text on the first line of an empty note.
///
/// This replaces the template chip strip, and it is deliberately not a strip: it sits *inside* the
/// note, on the line the caret is already on, drawn in the same left column the text will occupy.
/// It costs no layout — an empty note has nothing there — and it disappears the moment a character
/// lands, rather than sitting above every note forever waiting for one.
///
/// The prose is non-interactive so clicking anywhere in the empty body still places the caret,
/// which is the thing you actually came here to do. Only the template names take clicks.
struct NoteEmptyBodyPlaceholder: View {
    let templates: [NoteTemplate]
    let isVisible: Bool
    let onApply: (NoteTemplate) -> Void

    var body: some View {
        if isVisible {
            VStack(alignment: .leading, spacing: 6) {
                Text("Start writing, or press / for commands.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.dim)
                    .allowsHitTesting(false)

                if !templates.isEmpty {
                    HStack(spacing: 4) {
                        Text("Start with")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.dim)
                            .fixedSize()
                            .allowsHitTesting(false)

                        ForEach(Array(templates.enumerated()), id: \.element.id) { index, template in
                            if index > 0 {
                                Text("·")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.dim)
                                    .allowsHitTesting(false)
                            }
                            NoteTemplateTextButton(template: template) { onApply(template) }
                        }
                    }
                }
            }
            .padding(.leading, MarkdownEditorMetrics.firstTextColumnInset)
            .padding(.top, MarkdownEditorMetrics.toolbarHeight + MarkdownEditorMetrics.textInset)
        }
    }
}

/// A template name as a word, not a capsule. The chip version read as a control you had to deal
/// with; inside placeholder prose the same name reads as an offer you can ignore.
private struct NoteTemplateTextButton: View {
    let template: NoteTemplate
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(template.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isHovered ? Theme.text : Theme.muted)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                        .fill(isHovered ? Theme.surfaceHighlight : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(template.subtitle)
    }
}

// MARK: - Unlinked mentions

/// One quiet line at the foot of the note: "3 mentions", expanding on click.
///
/// Deliberately headerless. As a permanent titled section this was the loudest empty state on the
/// screen; as a count that only appears when there is something to count, it costs nothing.
struct NoteUnlinkedMentionsFooter: View {
    let mentions: [Note]
    let onLink: (Note) -> Void

    @State private var isExpanded = false

    private var countLabel: String {
        mentions.count == 1 ? "1 mention" : "\(mentions.count) mentions"
    }

    var body: some View {
        if !mentions.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                NoteUnlinkedMentionsToggle(
                    label: countLabel,
                    isExpanded: isExpanded
                ) {
                    isExpanded.toggle()
                }

                if isExpanded {
                    ForEach(mentions, id: \.id) { mention in
                        NoteUnlinkedMentionRow(title: mention.displayTitle) { onLink(mention) }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .overlay(alignment: .top) {
                Divider().background(Theme.borderSubtle)
            }
        }
    }
}

private struct NoteUnlinkedMentionsToggle: View {
    let label: String
    let isExpanded: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                Text(label)
                    .font(.system(size: 11))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.dim)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                    .fill(isHovered ? Theme.surfaceHighlight : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct NoteUnlinkedMentionRow: View {
    let title: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            // Blue survives here because linking really is the actionable thing on this row.
            Button(action: action) {
                Text("Link")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.blue)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 22)
        .padding(.trailing, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                .fill(isHovered ? Theme.surfaceHighlight : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
        .onHover { isHovered = $0 }
    }
}
#endif
