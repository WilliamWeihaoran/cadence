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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sidebarSection("Outline") {
                    if outline.isEmpty {
                        sidebarEmpty("No headings")
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(outline) { item in
                                Button {
                                    onJumpToOutline(item)
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(String(repeating: "  ", count: max(0, item.level - 1)) + item.title)
                                            .font(.system(size: 11, weight: item.level <= 2 ? .semibold : .regular))
                                            .foregroundStyle(item.level <= 2 ? Theme.muted : Theme.dim)
                                            .lineLimit(1)
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.vertical, 3)
                                }
                                .buttonStyle(.cadencePlain)
                            }
                        }
                    }
                }

                sidebarSection("Properties") {
                    if metadata.frontmatter.properties.isEmpty && metadata.tags.isEmpty {
                        Button {
                            onInsertFrontmatter()
                        } label: {
                            Label("Add frontmatter", systemImage: "tag")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.blue)
                        }
                        .buttonStyle(.cadencePlain)
                    } else {
                        if !metadata.frontmatter.properties.isEmpty {
                            VStack(alignment: .leading, spacing: 5) {
                                ForEach(metadata.frontmatter.properties.keys.sorted(), id: \.self) { key in
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text(key)
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(Theme.dim)
                                            .frame(width: 58, alignment: .leading)
                                        Text(metadata.frontmatter.properties[key] ?? "")
                                            .font(.system(size: 11))
                                            .foregroundStyle(Theme.muted)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                        if !metadata.tags.isEmpty {
                            FlowTags(tags: metadata.tags)
                        }
                    }
                }

                sidebarSection("Templates") {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(templates) { template in
                            Button {
                                onApplyTemplate(template)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.title)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Theme.muted)
                                    Text(template.subtitle)
                                        .font(.system(size: 10))
                                        .foregroundStyle(Theme.dim)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.cadencePlain)
                        }
                    }
                }

                sidebarSection("Unlinked") {
                    if unlinkedMentions.isEmpty {
                        sidebarEmpty("No mentions")
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(unlinkedMentions, id: \.id) { note in
                                HStack(spacing: 6) {
                                    Text(note.displayTitle)
                                        .font(.system(size: 11, weight: .medium))
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
                            }
                        }
                    }
                }
            }
            .padding(14)
        }
        .background(Theme.bg.opacity(0.34))
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.borderSubtle).frame(width: 1)
        }
    }

    private func sidebarSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .kerning(0.8)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sidebarEmpty(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Theme.dim)
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
