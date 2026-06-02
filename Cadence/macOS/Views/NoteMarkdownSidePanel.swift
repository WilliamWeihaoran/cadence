#if os(macOS)
import SwiftUI

struct NoteMarkdownSidePanel: View {
    let outline: [MarkdownOutlineItem]
    let metadata: MarkdownNoteMetadata
    let templates: [NoteTemplate]
    let unlinkedMentions: [Note]
    let onJumpToOutline: (MarkdownOutlineItem) -> Void
    let onInsertFrontmatter: () -> Void
    let onApplyTemplate: (NoteTemplate) -> Void
    let onLinkMention: (Note) -> Void
    @AppStorage("noteMarkdownSidePanelTemplatesCollapsed") private var templatesCollapsed = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                NoteSidebarSection(
                    title: "Outline",
                    icon: "list.bullet.indent",
                    count: outline.count
                ) {
                    outlineContent
                }

                NoteSidebarSection(
                    title: "Properties",
                    icon: "slider.horizontal.3",
                    count: metadata.frontmatter.properties.count + metadata.tags.count
                ) {
                    propertiesContent
                }

                NoteSidebarSection(
                    title: "Templates",
                    icon: "doc.badge.plus",
                    count: templates.count,
                    isCollapsed: templatesCollapsed,
                    onToggleCollapse: { templatesCollapsed.toggle() }
                ) {
                    if !templatesCollapsed {
                        templatesContent
                    }
                }

                NoteSidebarSection(
                    title: "Unlinked",
                    icon: "link.badge.plus",
                    count: unlinkedMentions.count
                ) {
                    unlinkedContent
                }
            }
            .padding(14)
        }
        .background(
            LinearGradient(
                colors: [Theme.bg.opacity(0.52), Theme.surface.opacity(0.34)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.borderSubtle).frame(width: 1)
        }
    }

    @ViewBuilder
    private var outlineContent: some View {
        if outline.isEmpty {
            NoteSidebarEmptyState(icon: "text.line.first.and.arrowtriangle.forward", text: "No headings yet")
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(outline) { item in
                    Button {
                        onJumpToOutline(item)
                    } label: {
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(item.level <= 2 ? Theme.blue.opacity(0.72) : Theme.dim.opacity(0.55))
                                .frame(width: item.level <= 2 ? 4 : 3, height: item.level <= 2 ? 14 : 10)
                            Text(item.title)
                                .font(.system(size: 11, weight: item.level <= 2 ? .semibold : .medium))
                                .foregroundStyle(item.level <= 2 ? Theme.text.opacity(0.88) : Theme.muted)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.leading, CGFloat(max(0, item.level - 1)) * 10)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.cadencePlain)
                }
            }
        }
    }

    @ViewBuilder
    private var propertiesContent: some View {
        if metadata.frontmatter.properties.isEmpty && metadata.tags.isEmpty {
            Button {
                onInsertFrontmatter()
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "tag")
                        .font(.system(size: 12, weight: .semibold))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Add frontmatter")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Tags, status, and custom fields")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.dim)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Theme.blue)
                .padding(10)
                .background(Theme.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.cadencePlain)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if !metadata.frontmatter.properties.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(metadata.frontmatter.properties.keys.sorted(), id: \.self) { key in
                            NotePropertyRow(key: key, value: metadata.frontmatter.properties[key] ?? "")
                        }
                    }
                }
                if !metadata.tags.isEmpty {
                    FlowTags(tags: metadata.tags)
                }
            }
        }
    }

    private var templatesContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(templates) { template in
                Button {
                    onApplyTemplate(template)
                } label: {
                    HStack(alignment: .top, spacing: 9) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Theme.blue.opacity(0.12))
                            .frame(width: 28, height: 28)
                            .overlay {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Theme.blue)
                            }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.text.opacity(0.9))
                                .lineLimit(1)
                            Text(template.subtitle)
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.dim)
                                .lineLimit(2)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surfaceElevated.opacity(0.42))
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.cadencePlain)
            }
        }
    }

    @ViewBuilder
    private var unlinkedContent: some View {
        if unlinkedMentions.isEmpty {
            NoteSidebarEmptyState(icon: "link", text: "No mentions")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(unlinkedMentions, id: \.id) { note in
                    HStack(spacing: 8) {
                        Text(note.displayTitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Button {
                            onLinkMention(note)
                        } label: {
                            Image(systemName: "link")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.blue)
                        }
                        .buttonStyle(.cadencePlain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Theme.surfaceElevated.opacity(0.36))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
            }
        }
    }
}

private struct NoteSidebarSection<Content: View>: View {
    let title: String
    let icon: String
    let count: Int?
    var isCollapsed = false
    var onToggleCollapse: (() -> Void)?
    @ViewBuilder let content: Content

    init(
        title: String,
        icon: String,
        count: Int? = nil,
        isCollapsed: Bool = false,
        onToggleCollapse: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.count = count
        self.isCollapsed = isCollapsed
        self.onToggleCollapse = onToggleCollapse
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                onToggleCollapse?()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.blue.opacity(0.86))
                        .frame(width: 18, height: 18)
                        .background(Theme.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                    Text(title.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.dim)
                        .kerning(1.0)

                    if let count, count > 0 {
                        Text("\(count)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.dim)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.surfaceElevated.opacity(0.7))
                            .clipShape(Capsule())
                    }

                    Spacer(minLength: 0)

                    if onToggleCollapse != nil {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.dim)
                            .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                    }
                }
            }
            .buttonStyle(.cadencePlain)
            .disabled(onToggleCollapse == nil)

            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Theme.borderSubtle.opacity(0.9), lineWidth: 1)
        }
    }
}

private struct NoteSidebarEmptyState: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(Theme.dim)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}

private struct NotePropertyRow: View {
    let key: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(key)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Theme.surfaceElevated.opacity(0.34))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct FlowTags: View {
    let tags: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text("#\(tag)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.blue)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.blue.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
    }
}
#endif
