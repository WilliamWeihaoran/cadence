#if os(macOS)
import SwiftUI
import SwiftData

struct TagPickerControl: View {
    @Binding var selectedTags: [Tag]
    let allTags: [Tag]
    let onCreateTag: (String) -> Tag?
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
            .cadenceControlLabel("Edit tags")
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
                .accessibilityLabel("Show hidden tags")
                .accessibilityValue("\(count)")
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
                        .accessibilityLabel("Filter by \(CadenceTagChipStyle.displayName(for: tag))")
                        .accessibilityValue(isSelected ? "On" : "Off")
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
                        .cadenceControlLabel("Clear tag filters")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
        }
    }
}

/// What a macOS tag picker draws **where its rows would go**, when it has no rows to draw.
///
/// Both macOS pickers — `TagPickerPopover` and `TaskTitleInlineTagPicker` — reached one bare
/// `"No tags"` for two unrelated situations, and it was the wrong sentence in each (T-532):
///
/// - **The catalogue is empty.** After [T-528] the default tags are seeded only when someone asks,
///   so a brand-new store's first `#` picker is genuinely empty and the user's only routes to the
///   default set were typing each name or finding Settings > Tags. iOS already answers this in the
///   same place: `iOSTaskTagPickerPopover` offers **Add Default Tags** whenever its catalogue is
///   empty. This is macOS reaching parity with it.
/// - **A query matched nothing.** Here tags exist, so "No tags" was simply false. The house
///   spelling for a list narrowed to nothing is "No matching …" — `GoalsView` and `HabitsView`
///   both draw it.
///
/// Held as a value the two pickers *resolve* rather than a condition each spells out, because the
/// bare `"No tags"` was already two copies that had to stay in step and did not.
nonisolated enum TagPickerPlaceholder: Equatable {
    /// The picker is drawing rows of its own — tags, a create row, or a restore row. Nothing here.
    case none
    /// No unarchived tag exists at all. Offer the default set.
    case offerDefaultTags
    /// Tags exist; this query reaches none of them and offers no other row.
    case noMatches

    /// - Parameters:
    ///   - hasActiveTags: whether the store holds **any** unarchived tag, not whether this query
    ///     found one. That distinction is the whole point: the two callers previously keyed the
    ///     placeholder off the *filtered* list, which cannot tell an empty store from a narrow
    ///     query.
    ///   - matchCount: rows the picker is about to draw for the current query.
    ///   - canCreate: whether a create row is about to be drawn.
    ///   - canRestore: whether a restore row is about to be drawn. `TaskTitleInlineTagPicker` has
    ///     no restore affordance and leaves this at its default; `TagPickerPopover` used to draw
    ///     "Restore \"bug\"" and "No tags" one above the other, which contradicted itself.
    static func resolve(
        hasActiveTags: Bool,
        matchCount: Int,
        canCreate: Bool,
        canRestore: Bool = false
    ) -> TagPickerPlaceholder {
        guard matchCount == 0, !canCreate, !canRestore else { return .none }
        return hasActiveTags ? .noMatches : .offerDefaultTags
    }
}

/// The one rendering of `TagPickerPlaceholder`, in the row language both macOS tag pickers already
/// use for their create and restore rows.
///
/// This view owns the seed call. It is a `Button` action and nothing else — see
/// `CadenceFirstLaunchEmptyStoreTests.noUnpromptedCodePathSeedsTheDefaultTags`, which exists
/// because "the tag list is empty" is also what a second device renders while CloudKit is still
/// arriving. Do not move this call to `.onAppear`.
struct TagPickerPlaceholderRow: View {
    let placeholder: TagPickerPlaceholder
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        switch placeholder {
        case .none:
            EmptyView()
        case .offerDefaultTags:
            Button {
                TagSupport.seedDefaultTags(in: modelContext)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "tag.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.blue)
                    Text("Add Default Tags")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.text)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.cadencePlain)
            .cadenceHoverHighlight(cornerRadius: 6)
            .accessibilityLabel("Add Default Tags")
            .help("Add Cadence's starter tags")
        case .noMatches:
            Text("No matching tags")
                .font(.system(size: 12))
                .foregroundStyle(Theme.dim)
                .padding(10)
        }
    }
}

#endif
