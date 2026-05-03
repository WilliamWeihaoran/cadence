#if os(macOS)
import SwiftUI

struct CadencePursuitPickerButton: View {
    let pursuits: [Pursuit]
    @Binding var selectedID: UUID?
    var allowNone = true
    var style: CadencePursuitPickerStyle = .standard
    var onCreate: (() -> Void)? = nil

    @State private var showPicker = false

    private var selectedPursuit: Pursuit? {
        selectedID.flatMap { id in pursuits.first { $0.id == id } }
    }

    private var placeholder: String {
        allowNone ? "No pursuit" : "Choose pursuit"
    }

    var body: some View {
        Button { showPicker.toggle() } label: {
            HStack(spacing: style.iconLabelSpacing) {
                selectedIcon

                Text(selectedPursuit?.title ?? placeholder)
                    .font(.system(size: style.fontSize, weight: .medium))
                    .foregroundStyle(selectedPursuit == nil ? Theme.dim : Theme.text)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: style.chevronSize, weight: .semibold))
                    .foregroundStyle(Theme.dim)
            }
            .padding(.horizontal, style.horizontalPadding)
            .padding(.vertical, style.verticalPadding)
            .frame(minHeight: style.minHeight)
            .contentShape(Rectangle())
            .background(Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: style.cornerRadius).stroke(Theme.borderSubtle))
        }
        .buttonStyle(.cadencePlain)
        .popover(isPresented: $showPicker, arrowEdge: .bottom) {
            CadencePursuitPickerList(
                pursuits: pursuits,
                selectedID: $selectedID,
                allowNone: allowNone,
                onPick: { showPicker = false },
                onCreate: onCreate.map { create in
                    {
                        showPicker = false
                        create()
                    }
                }
            )
            .frame(width: 280)
            .frame(maxHeight: 340)
            .background(Theme.surface)
        }
    }

    @ViewBuilder
    private var selectedIcon: some View {
        if let selectedPursuit {
            Image(systemName: selectedPursuit.icon)
                .font(.system(size: style.iconSize, weight: .semibold))
                .foregroundStyle(Color(hex: selectedPursuit.colorHex))
                .frame(width: style.iconBoxSize, height: style.iconBoxSize)
                .background(Color(hex: selectedPursuit.colorHex).opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: style.iconCornerRadius))
        } else {
            Image(systemName: "sparkles")
                .font(.system(size: style.iconSize, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .frame(width: style.iconBoxSize, height: style.iconBoxSize)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: style.iconCornerRadius))
        }
    }
}

struct CadencePursuitPickerList: View {
    let pursuits: [Pursuit]
    @Binding var selectedID: UUID?
    var allowNone = true
    var onPick: (() -> Void)? = nil
    var onCreate: (() -> Void)? = nil

    @State private var searchQuery = ""
    @State private var highlightIndex = 0
    @FocusState private var isSearchFocused: Bool

    private struct PickerItem: Equatable {
        let id: UUID?
        let label: String
    }

    private var sortedPursuits: [Pursuit] {
        pursuits.sorted {
            if $0.order == $1.order {
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            return $0.order < $1.order
        }
    }

    private var filteredPursuits: [Pursuit] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return sortedPursuits }
        let needle = trimmed.localizedLowercase
        return sortedPursuits.filter {
            $0.title.localizedLowercase.contains(needle)
                || $0.desc.localizedLowercase.contains(needle)
                || ($0.context?.name.localizedLowercase.contains(needle) ?? false)
        }
    }

    private var flattenedItems: [PickerItem] {
        var items: [PickerItem] = []
        if allowNone {
            items.append(PickerItem(id: nil, label: "No pursuit"))
        }
        items.append(contentsOf: filteredPursuits.map { PickerItem(id: $0.id, label: $0.title) })
        return items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField

            Divider().background(Theme.borderSubtle).padding(.top, 6)

            if filteredPursuits.isEmpty && !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if allowNone {
                    row(id: nil, title: "No pursuit", subtitle: "Leave ungrouped", icon: "sparkles", colorHex: nil)
                    Divider().background(Theme.borderSubtle).padding(.vertical, 2)
                }

                Text("No matching pursuits")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                if allowNone {
                    row(id: nil, title: "No pursuit", subtitle: "Leave ungrouped", icon: "sparkles", colorHex: nil)
                    Divider().background(Theme.borderSubtle).padding(.vertical, 2)
                }

                ForEach(filteredPursuits) { pursuit in
                    row(
                        id: pursuit.id,
                        title: pursuit.title,
                        subtitle: pursuit.context?.name ?? pursuit.status.label,
                        icon: pursuit.icon,
                        colorHex: pursuit.colorHex
                    )
                }
            }

            if let onCreate {
                Divider().background(Theme.borderSubtle).padding(.top, 4)
                Button(action: onCreate) {
                    HStack(spacing: 9) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.blue)
                            .frame(width: 24, height: 24)
                            .background(Theme.blue.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 7))

                        Text("New Pursuit")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.cadencePlain)
                .padding(.horizontal, 4)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            isSearchFocused = true
            syncHighlight()
        }
        .onChange(of: searchQuery) {
            syncHighlight()
        }
        .onMoveCommand { direction in
            guard !flattenedItems.isEmpty else { return }
            switch direction {
            case .down:
                highlightIndex = min(highlightIndex + 1, flattenedItems.count - 1)
            case .up:
                highlightIndex = max(highlightIndex - 1, 0)
            default:
                break
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Theme.dim)

            TextField("Search pursuits", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text)
                .focused($isSearchFocused)
                .onSubmit {
                    guard highlightIndex >= 0, highlightIndex < flattenedItems.count else { return }
                    pick(flattenedItems[highlightIndex].id)
                }

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                    isSearchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                }
                .buttonStyle(.cadencePlain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 8)
    }

    @MainActor
    @ViewBuilder
    private func row(id: UUID?, title: String, subtitle: String, icon: String, colorHex: String?) -> some View {
        let isSelected = selectedID == id
        let isHighlighted = highlightIndex < flattenedItems.count && flattenedItems[highlightIndex].id == id
        let tint = colorHex.map(Color.init(hex:)) ?? Theme.dim

        Button {
            pick(id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 24, height: 24)
                    .background(tint.opacity(colorHex == nil ? 0.06 : 0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Theme.text : Theme.muted)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.blue)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 38)
            .background(isSelected ? Theme.blue.opacity(0.08) : (isHighlighted ? Theme.blue.opacity(0.05) : Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.cadencePlain)
        .modifier(PursuitPickerRowHover())
        .padding(.horizontal, 4)
    }

    private func pick(_ id: UUID?) {
        selectedID = id
        onPick?()
    }

    private func syncHighlight() {
        guard !flattenedItems.isEmpty else {
            highlightIndex = 0
            return
        }

        if let selectedIndex = flattenedItems.firstIndex(where: { $0.id == selectedID }) {
            highlightIndex = selectedIndex
        } else {
            highlightIndex = min(highlightIndex, flattenedItems.count - 1)
        }
    }
}

enum CadencePursuitPickerStyle {
    case standard
    case compact

    var fontSize: CGFloat { self == .compact ? 12 : 13 }
    var iconSize: CGFloat { self == .compact ? 11 : 12 }
    var iconBoxSize: CGFloat { self == .compact ? 20 : 22 }
    var iconCornerRadius: CGFloat { self == .compact ? 6 : 7 }
    var iconLabelSpacing: CGFloat { self == .compact ? 7 : 9 }
    var chevronSize: CGFloat { self == .compact ? 8 : 9 }
    var horizontalPadding: CGFloat { self == .compact ? 9 : 10 }
    var verticalPadding: CGFloat { self == .compact ? 6 : 8 }
    var minHeight: CGFloat { self == .compact ? 30 : 34 }
    var cornerRadius: CGFloat { self == .compact ? 7 : 8 }
}

private struct PursuitPickerRowHover: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Theme.blue.opacity(0.06) : Color.clear)
            )
            .onHover { isHovered = $0 }
    }
}

struct CadencePursuitRequiredHint: View {
    let hasSelection: Bool

    var body: some View {
        if !hasSelection {
            Label("Choose or create a Pursuit before saving.", systemImage: "sparkles")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.amber)
        }
    }
}
#endif
