#if os(macOS)
import SwiftUI
import SwiftData

struct TagPickerControl: View {
    @Binding var selectedTags: [Tag]
    let allTags: [Tag]
    let onCreateTag: (String) -> Tag
    var showsLabel: Bool = false
    /// Glyph on the picker trigger. Defaults to the tag icon, which reads as "this is the tag
    /// control" — right inside a task inspector, where it sits in a column of labelled fields.
    /// The note header passes `"plus"`: there the chips are the subject and the trigger's only
    /// job is "add one".
    var triggerSymbol: String = "tag.fill"

    @State private var isPresented = false

    private var visibleSelectedTags: [Tag] {
        TagSupport.sorted(selectedTags)
    }

    var body: some View {
        HStack(spacing: 6) {
            if !visibleSelectedTags.isEmpty {
                AdaptiveSelectedTagStrip(tags: visibleSelectedTags) { tag in
                    selectedTags.removeAll { $0.id == tag.id }
                }
            }

            Button {
                isPresented.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: triggerSymbol)
                        .font(.system(size: 10, weight: .semibold))
                    if showsLabel {
                        Text("Tags")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .foregroundStyle(Theme.dim)
                .padding(.horizontal, showsLabel ? 9 : 0)
                .frame(width: showsLabel ? nil : 24, height: 24)
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.cadencePlain)
            .help("Edit tags")
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                TagPickerPopover(
                    selectedTags: $selectedTags,
                    allTags: allTags,
                    onCreateTag: onCreateTag
                )
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct TagChip: View {
    let tag: Tag
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color(hex: tag.colorHex))
                .frame(width: 6, height: 6)
            Text(tag.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 118, alignment: .leading)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Theme.dim.opacity(0.8))
                        // The glyph alone is about 8x9pt, which `.cadencePlain`'s content shape
                        // then clamps to a capsule inside that. Fiddly with a mouse and the
                        // smallest hit target in the app.
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.cadencePlain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(hex: tag.colorHex).opacity(0.14))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke((tag.isArchived ? Theme.dim : Color(hex: tag.colorHex)).opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .opacity(tag.isArchived ? 0.62 : 1)
    }
}

private struct AdaptiveSelectedTagStrip: View {
    let tags: [Tag]
    let onRemove: (Tag) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            selectedTagRow(limit: min(3, tags.count))
            selectedTagRow(limit: min(2, tags.count))
            selectedTagRow(limit: min(1, tags.count))
            selectedTagRow(limit: 0)
        }
    }

    private func selectedTagRow(limit: Int) -> some View {
        HStack(spacing: 5) {
            ForEach(tags.prefix(limit)) { tag in
                TagChip(tag: tag) {
                    onRemove(tag)
                }
            }
            if tags.count > limit {
                // The remover has to reach the collapsed tags too. `ViewThatFits` falls all the
                // way through to `limit: 0` when the row is tight — measured to happen in the
                // create-task sheet once a list, a section and both dates are set, since its
                // toolbar shares a fixed 600pt with the container badge, the date chips and the
                // close button. While this badge was a bare `Text`, every selected tag was then
                // unreachable. The task inspector never collapses because it gives the same
                // control its own full-width row, which is why the bug looked sheet-specific.
                TagOverflowBadge(
                    count: tags.count - limit,
                    hiddenTags: tags.dropFirst(limit),
                    onRemove: onRemove
                )
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct CompactTagStrip: View {
    let tags: [Tag]
    var limit: Int = 2
    var allowsArchived: Bool = true

    private var visibleTags: [Tag] {
        let base = allowsArchived ? tags : tags.filter { !$0.isArchived }
        return TagSupport.uniqueBySlug(base)
    }

    var body: some View {
        if !visibleTags.isEmpty {
            ViewThatFits(in: .horizontal) {
                compactTagRow(limit: min(limit, visibleTags.count))
                compactTagRow(limit: min(1, visibleTags.count))
                compactTagRow(limit: 0)
            }
        }
    }

    private func compactTagRow(limit: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(visibleTags.prefix(limit)) { tag in
                TagMiniChip(tag: tag)
            }
            if visibleTags.count > limit {
                TagOverflowBadge(count: visibleTags.count - limit, hiddenTags: visibleTags.dropFirst(limit), size: .mini)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct TagMiniChip: View {
    let tag: Tag

    var body: some View {
        Text(tag.name)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(tag.isArchived ? Theme.dim : Color(hex: tag.colorHex))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: 88, alignment: .leading)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(Color(hex: tag.colorHex).opacity(tag.isArchived ? 0.08 : 0.13))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color(hex: tag.colorHex).opacity(tag.isArchived ? 0.18 : 0.26), lineWidth: 1)
            )
            .help(tag.isArchived ? "\(tag.name) (archived)" : tag.name)
    }
}

private struct TagOverflowBadge: View {
    enum Size {
        case regular
        case mini

        var fontSize: CGFloat {
            switch self {
            case .regular: return 11
            case .mini: return 9
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .regular: return 7
            case .mini: return 5
            }
        }

        var verticalPadding: CGFloat {
            switch self {
            case .regular: return 5
            case .mini: return 3
            }
        }

        var cornerRadius: CGFloat {
            switch self {
            case .regular: return 7
            case .mini: return 5
            }
        }
    }

    let count: Int
    let hiddenTags: ArraySlice<Tag>
    var size: Size = .regular
    /// Supplied by editable strips only. Read-only strips pass nothing and keep the plain
    /// tooltip, because there is nothing there to remove a tag from.
    var onRemove: ((Tag) -> Void)? = nil

    @State private var isPresented = false

    var body: some View {
        if let onRemove {
            Button { isPresented.toggle() } label: { badge }
                .buttonStyle(.cadencePlain)
                .help("Show the tags that do not fit")
                .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(hiddenTags)) { tag in
                            TagChip(tag: tag) {
                                onRemove(tag)
                                // Close on the last one rather than leave an empty popover
                                // anchored to a badge that is no longer being drawn.
                                if hiddenTags.count <= 1 { isPresented = false }
                            }
                        }
                    }
                    .padding(8)
                }
        } else {
            badge.help(hiddenTags.map(\.name).joined(separator: ", "))
        }
    }

    private var badge: some View {
        Text("+\(count)")
            .font(.system(size: size.fontSize, weight: .semibold))
            .foregroundStyle(Theme.dim)
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .background(Theme.surfaceElevated.opacity(0.75))
            .clipShape(RoundedRectangle(cornerRadius: size.cornerRadius))
    }
}

struct TagFilterBar: View {
    let tags: [Tag]
    @Binding var selectedSlugs: Set<String>
    var maxVisibleTags: Int = 8

    private var visibleTags: [Tag] {
        Array(TagSupport.uniqueBySlug(tags.filter { !$0.isArchived }).prefix(maxVisibleTags))
    }

    var body: some View {
        if !visibleTags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(visibleTags) { tag in
                        let isSelected = selectedSlugs.contains(tag.slug)
                        Button {
                            if isSelected {
                                selectedSlugs.remove(tag.slug)
                            } else {
                                selectedSlugs.insert(tag.slug)
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(Color(hex: tag.colorHex))
                                    .frame(width: 6, height: 6)
                                Text(tag.name)
                                    .font(.system(size: 10, weight: .semibold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(isSelected ? Theme.text : Theme.dim)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 5)
                            .background(isSelected ? Color(hex: tag.colorHex).opacity(0.18) : Theme.surfaceElevated.opacity(0.58))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(Color(hex: tag.colorHex).opacity(isSelected ? 0.42 : 0.18), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.cadencePlain)
                        .help(isSelected ? "Remove tag filter" : "Filter by \(tag.name)")
                    }

                    if !selectedSlugs.isEmpty {
                        Button {
                            selectedSlugs.removeAll()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.dim)
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.cadencePlain)
                        .help("Clear tag filters")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
        }
    }
}

#endif
