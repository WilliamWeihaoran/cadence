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
        HStack(spacing: CadenceTagChipStyle.editableStripSpacing(for: .regular)) {
            ForEach(tags.prefix(limit)) { tag in
                CadenceTagChip(tag: tag) {
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

// `CompactTagStrip` was declared here, inside `#if os(macOS)`, and is now in
// `Shared/Components/CadenceTagChip.swift` beside the chip and the overflow badge it is made of.
// It moved unchanged apart from its overflow badge, which is now the inert `CadenceTagOverflowBadge`
// with the hidden names on `help` rather than the `TagOverflowBadge` below: this strip never
// supplied `onRemove`, so it only ever took that type's no-popover branch. `TagOverflowBadge` stays
// here because the *editable* strip above does supply one, and a removal popover is a pointer
// affordance.

/// The `+N` a strip collapses into, plus the popover that keeps the collapsed tags reachable.
/// The badge itself is `CadenceTagOverflowBadge`; what lives here is only the reachability.
private struct TagOverflowBadge: View {
    let count: Int
    let hiddenTags: ArraySlice<Tag>
    var size: CadenceTagChipSize = .regular
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
                    VStack(alignment: .leading, spacing: CadenceTagChipStyle.editableStripLineSpacing(for: .regular)) {
                        ForEach(Array(hiddenTags)) { tag in
                            CadenceTagChip(tag: tag) {
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
            badge.help(hiddenTags.map { CadenceTagChipStyle.accessibilityLabel(for: $0) }.joined(separator: ", "))
        }
    }

    private var badge: some View {
        CadenceTagOverflowBadge(count: count, size: size)
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
                            CadenceTagChip(tag: tag, selection: isSelected ? .on : .off)
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
