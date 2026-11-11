#if os(macOS)
import SwiftUI

struct TaskTitleInlineTagPicker: View {
    @Binding var query: String
    @Binding var highlightIndex: Int
    let filteredTags: [Tag]
    let selectedTags: [Tag]
    /// Whether the store holds **any** unarchived tag. `filteredTags` cannot answer this — it is
    /// already narrowed by the query — and the placeholder below needs the difference. See
    /// `TagPickerPlaceholder`.
    let hasActiveTags: Bool
    let canCreate: Bool
    /// [[T-16583]]: the archived tag the query's slug names, drawn as `Unarchive "<name>"` in the
    /// Create row's place -- the row every other tag picker draws for it ([[T-12744]], [[T-13963]]).
    /// `nil` when the host offers no unarchive.
    let archivedMatch: Tag?
    let onSelect: (Tag) -> Void
    let onCreate: () -> Void
    let onUnarchive: () -> Void
    let onSubmit: () -> Void
    let onMoveHighlight: (Int) -> Void
    let onRestoreLiteral: () -> Void

    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchRow

            Divider().background(Theme.borderSubtle)

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(filteredTags.enumerated()), id: \.element.id) { index, tag in
                        InlineTagPickerRow(
                            tag: tag,
                            isHighlighted: index == highlightIndex,
                            isSelected: selectedTags.contains { $0.id == tag.id },
                            action: { onSelect(tag) }
                        )
                    }

                    if let archivedMatch {
                        unarchiveRow(archivedMatch, isHighlighted: highlightIndex == filteredTags.count)
                    } else if canCreate {
                        createRow(isHighlighted: highlightIndex == filteredTags.count)
                    }

                    TagPickerPlaceholderRow(
                        placeholder: TagPickerPlaceholder.resolve(
                            hasActiveTags: hasActiveTags,
                            matchCount: filteredTags.count,
                            canCreate: canCreate,
                            canRestore: archivedMatch != nil
                        )
                    )
                }
                .padding(6)
            }
            .frame(maxHeight: 220)
        }
        .frame(width: 240)
        // [[T-9802]]: the Mac picker-popover surface, as `TagPickerPopover` (the same tags, picked
        // from the inspector) and every other Mac picker popover draw it.
        .background(Theme.surface)
        .onAppear {
            clampHighlightIndex()
            DispatchQueue.main.async { isSearchFocused = true }
        }
        .onChange(of: query) { _, _ in highlightIndex = 0 }
        .onChange(of: filteredTags.map(\.id)) { _, _ in clampHighlightIndex() }
        .onChange(of: canCreate) { _, _ in clampHighlightIndex() }
        .onChange(of: archivedMatch?.id) { _, _ in clampHighlightIndex() }
    }

    private var searchRow: some View {
        CadenceSearchFieldRow(query: $query, focus: $isSearchFocused) {
            TextField("Find or create tag", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
                .focused($isSearchFocused)
                .onSubmit(onSubmit)
                .onKeyPress(.upArrow) {
                    onMoveHighlight(-1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    onMoveHighlight(1)
                    return .handled
                }
                .onKeyPress(.tab) {
                    onSubmit()
                    return .handled
                }
                .onKeyPress(.escape) {
                    onRestoreLiteral()
                    return .handled
                }
                .onKeyPress(.delete) {
                    guard query.isEmpty else { return .ignored }
                    onRestoreLiteral()
                    return .handled
                }
        }
    }

    private func createRow(isHighlighted: Bool) -> some View {
        Button(action: onCreate) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.blue)
                Text("Create \"\(TagSupport.displayName(for: query))\"")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.text)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(isHighlighted ? Theme.blue.opacity(0.08) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        // [[T-9465]]: the row style is the one hover plate.
        .buttonStyle(.cadenceMenuRow)
    }

    /// The `TagPickerPopover` restore row's anatomy, so the two Mac tag pickers say it alike.
    private func unarchiveRow(_ tag: Tag, isHighlighted: Bool) -> some View {
        Button(action: onUnarchive) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.blue)
                Text(CadenceListVocabularyCopy.unarchiveRowTitle(name: tag.name))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.text)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(isHighlighted ? Theme.blue.opacity(0.08) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        // [[T-9465]]: the row style is the one hover plate.
        .buttonStyle(.cadenceMenuRow)
    }

    private var optionCount: Int {
        TaskTitleInlineTagSubmit.optionCount(
            matchCount: filteredTags.count,
            canCreate: canCreate,
            offersUnarchive: archivedMatch != nil
        )
    }

    private func clampHighlightIndex() {
        guard optionCount > 0 else {
            highlightIndex = 0
            return
        }
        highlightIndex = min(max(highlightIndex, 0), optionCount - 1)
    }
}

/// **[[T-16583]] -- what Return (or Tab) does in the title field's `#` panel.**
///
/// The panel's rows are the query's matches, then one trailing row: `Unarchive "<name>"` when an
/// archived tag carries the query's slug, otherwise `Create "<name>"` when the name can become a
/// tag. The two never draw together -- `TagSupport.pickerQuery` offers no Create name for an
/// archived match. The panel used to have no Unarchive row at all, so typing an archived tag's name
/// in a Mac board column's composer drew `No matching tags` and Return did nothing, where the
/// inspector's tag popover, the capture card's strip and iOS's pickers all offer to bring it back.
enum TaskTitleInlineTagSubmit {
    case select(Tag)
    case unarchive(Tag)
    case create
    case nothing

    static func optionCount(matchCount: Int, canCreate: Bool, offersUnarchive: Bool) -> Int {
        matchCount + (offersUnarchive || canCreate ? 1 : 0)
    }

    /// `archivedMatch` is the query's, already `nil` when the host offers no unarchive.
    static func action(
        highlightIndex: Int,
        matches: [Tag],
        canCreate: Bool,
        archivedMatch: Tag?
    ) -> TaskTitleInlineTagSubmit {
        let count = optionCount(matchCount: matches.count, canCreate: canCreate, offersUnarchive: archivedMatch != nil)
        let index = TaskPickerHighlightSupport.clampedIndex(highlightIndex, count: count)
        if index < matches.count { return .select(matches[index]) }
        if let archivedMatch { return .unarchive(archivedMatch) }
        return canCreate ? .create : .nothing
    }
}

private struct InlineTagPickerRow: View {
    let tag: Tag
    let isHighlighted: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                CadenceTagChip(tag: tag)
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.blue)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(isHighlighted ? Theme.blue.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        // [[T-9465]]: the row style is the one hover plate.
        .buttonStyle(.cadenceMenuRow)
        // T-7334: the checkmark says which tags the title already carries; this says it aloud.
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
#endif
