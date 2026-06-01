#if os(macOS)
import SwiftUI

struct TaskTitleInlineTagPicker: View {
    @Binding var query: String
    @Binding var highlightIndex: Int
    let filteredTags: [Tag]
    let selectedTags: [Tag]
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
                        createRow
                    }

                    if filteredTags.isEmpty && !canCreate {
                        Text("No tags")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.dim)
                            .padding(10)
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 220)
        }
        .frame(width: 240)
        .background(Theme.surfaceElevated)
        .onAppear { DispatchQueue.main.async { isSearchFocused = true } }
        .onChange(of: query) { _, _ in highlightIndex = 0 }
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
                    onRestoreLiteral()
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

    private var createRow: some View {
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
        }
        .buttonStyle(.cadencePlain)
        .cadenceHoverHighlight(cornerRadius: 6)
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
                Circle()
                    .fill(Color(hex: tag.colorHex))
                    .frame(width: 8, height: 8)
                Text(tag.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Spacer()
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
