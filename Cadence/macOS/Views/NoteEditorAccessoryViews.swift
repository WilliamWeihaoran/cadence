#if os(macOS)
import SwiftUI

// The three pieces that used to live in the note editor's permanent right-hand panel
// (`NoteMarkdownSidePanel`). That panel was a third column that spent most of its life showing
// empty states, so each piece moved to the moment it is actually wanted:
//
// - Outline    -> a toolbar button, because you reach for an outline to navigate a long note,
//                 not while writing one.
// - Templates  -> chips shown only while the note is still empty, because that is the one moment
//                 a template helps; offering to replace existing text is noise.
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

/// Template chips for a still-empty note. Renders nothing once the note has content, so the
/// caller can hand it the note's emptiness and forget about it.
struct NoteTemplateChipStrip: View {
    let templates: [NoteTemplate]
    let onApply: (NoteTemplate) -> Void

    var body: some View {
        if !templates.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Text("Start with")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                        .fixedSize()

                    ForEach(templates) { template in
                        NoteTemplateChip(template: template) { onApply(template) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background(Theme.surface)
        }
    }
}

private struct NoteTemplateChip: View {
    let template: NoteTemplate
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(template.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isHovered ? Theme.text : Theme.muted)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(isHovered ? Theme.surfaceHighlight : Theme.surfaceElevated))
                .contentShape(Capsule())
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
