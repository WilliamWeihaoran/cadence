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
    let onSelect: (Tag) -> Void
    let onCreate: () -> Void
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

                    if canCreate {
                        createRow(isHighlighted: highlightIndex == filteredTags.count)
                    }

                    TagPickerPlaceholderRow(
                        placeholder: TagPickerPlaceholder.resolve(
                            hasActiveTags: hasActiveTags,
                            matchCount: filteredTags.count,
                            canCreate: canCreate
                        )
                    )
                }
                .padding(6)
            }
            .frame(maxHeight: 220)
        }
        .frame(width: 240)
        .background(Theme.surfaceElevated)
        .onAppear {
            clampHighlightIndex()
            DispatchQueue.main.async { isSearchFocused = true }
        }
        .onChange(of: query) { _, _ in highlightIndex = 0 }
        .onChange(of: filteredTags.map(\.id)) { _, _ in clampHighlightIndex() }
        .onChange(of: canCreate) { _, _ in clampHighlightIndex() }
    }

    private var searchRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim)
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
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim.opacity(0.5))
                }
                .buttonStyle(.cadencePlain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
        .buttonStyle(.cadencePlain)
        .cadenceHoverHighlight(cornerRadius: 6)
    }

    private var optionCount: Int {
        filteredTags.count + (canCreate ? 1 : 0)
    }

    private func clampHighlightIndex() {
        guard optionCount > 0 else {
            highlightIndex = 0
            return
        }
        highlightIndex = min(max(highlightIndex, 0), optionCount - 1)
    }
}

private struct InlineTagPickerRow: View {
    let tag: Tag
    let isHighlighted: Bool
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

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
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.cadencePlain)
        .onHover { isHovered = $0 }
    }

    private var rowBackground: Color {
        if isHighlighted { return Theme.blue.opacity(0.08) }
        if isHovered { return Theme.blue.opacity(0.06) }
        return .clear
    }
}
#endif
