#if os(macOS)
import SwiftUI

/// macOS picker for linking something to a `Goal` — the parent of another goal, or the goal a
/// habit belongs to. Replaces the old pursuit picker: a goal is now always optional, so this
/// picker always offers a "none" row instead of gating saves behind a selection.
struct GoalLinkPickerButton: View {
    let goals: [Goal]
    @Binding var selectedID: UUID?
    var noneTitle: String = "No parent goal"
    var noneSubtitle: String = "Keep as a top-level goal"
    var searchPlaceholder: String = "Search goals"
    var emptyText: String = "No matching goals"
    var style: GoalLinkPickerStyle = .standard

    @State private var showPicker = false

    private var selectedGoal: Goal? {
        selectedID.flatMap { id in goals.first { $0.id == id } }
    }

    var body: some View {
        Button { showPicker.toggle() } label: {
            HStack(spacing: style.iconLabelSpacing) {
                selectedIcon

                Text(selectedGoal?.title ?? noneTitle)
                    .font(.system(size: style.fontSize, weight: .medium))
                    .foregroundStyle(selectedGoal == nil ? Theme.dim : Theme.text)
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
            .overlay(RoundedRectangle(cornerRadius: style.cornerRadius).strokeBorder(Theme.borderSubtle))
        }
        .buttonStyle(.cadencePlain)
        .popover(isPresented: $showPicker, arrowEdge: .bottom) {
            GoalLinkPickerList(
                goals: goals,
                selectedID: $selectedID,
                noneTitle: noneTitle,
                noneSubtitle: noneSubtitle,
                searchPlaceholder: searchPlaceholder,
                emptyText: emptyText,
                onPick: { showPicker = false }
            )
            .frame(width: 280)
            .frame(maxHeight: 340)
            .background(Theme.surface)
        }
    }

    @ViewBuilder
    private var selectedIcon: some View {
        if let selectedGoal {
            Image(systemName: selectedGoal.icon)
                .font(.system(size: style.iconSize, weight: .semibold))
                .foregroundStyle(Color(hex: selectedGoal.colorHex))
                .frame(width: style.iconBoxSize, height: style.iconBoxSize)
                .background(Color(hex: selectedGoal.colorHex).opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: style.iconCornerRadius))
        } else {
            Image(systemName: "circle.dashed")
                .font(.system(size: style.iconSize, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .frame(width: style.iconBoxSize, height: style.iconBoxSize)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: style.iconCornerRadius))
        }
    }
}

struct GoalLinkPickerList: View {
    let goals: [Goal]
    @Binding var selectedID: UUID?
    var noneTitle: String = "No parent goal"
    var noneSubtitle: String = "Keep as a top-level goal"
    var searchPlaceholder: String = "Search goals"
    var emptyText: String = "No matching goals"
    var onPick: (() -> Void)? = nil

    @State private var searchQuery = ""
    @State private var highlightIndex = 0
    @FocusState private var isSearchFocused: Bool

    private struct PickerItem: Equatable {
        let id: UUID?
        let label: String
    }

    private var sortedGoals: [Goal] {
        goals.sorted {
            if $0.order == $1.order {
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            return $0.order < $1.order
        }
    }

    private var filteredGoals: [Goal] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return sortedGoals }
        let needle = trimmed.localizedLowercase
        return sortedGoals.filter {
            $0.title.localizedLowercase.contains(needle)
                || $0.desc.localizedLowercase.contains(needle)
                || $0.kind.label.localizedLowercase.contains(needle)
                || ($0.context?.name.localizedLowercase.contains(needle) ?? false)
        }
    }

    private var flattenedItems: [PickerItem] {
        [PickerItem(id: nil, label: noneTitle)]
            + filteredGoals.map { PickerItem(id: $0.id, label: $0.title) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField

            Divider().background(Theme.borderSubtle).padding(.top, 6)

            row(id: nil, title: noneTitle, subtitle: noneSubtitle, icon: "circle.dashed", colorHex: nil)
            Divider().background(Theme.borderSubtle).padding(.vertical, 2)

            if filteredGoals.isEmpty {
                Text(searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No goals yet" : emptyText)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(filteredGoals) { goal in
                    row(
                        id: goal.id,
                        title: goal.title,
                        subtitle: "\(goal.kind.label) • \(goal.context?.name ?? goal.status.label)",
                        icon: goal.icon,
                        colorHex: goal.colorHex
                    )
                }
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

            TextField(searchPlaceholder, text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text)
                .focused($isSearchFocused)
                .onSubmit {
                    guard highlightIndex >= 0, highlightIndex < flattenedItems.count else { return }
                    pick(flattenedItems[highlightIndex].id)
                }

            CadenceSearchFieldClearButton(text: $searchQuery, glyphSize: 12, focus: $isSearchFocused)
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
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControlCompact))

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
        .modifier(GoalLinkPickerRowHover())
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

enum GoalLinkPickerStyle {
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

private struct GoalLinkPickerRowHover: ViewModifier {
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

/// Shared kind selector used by the goal editor. Mirrors the status selector's layout so the
/// sheet reads as one control stack.
struct GoalKindSection: View {
    @Binding var selection: GoalKind

    var body: some View {
        HStack(spacing: 8) {
            ForEach(GoalKind.allCases, id: \.self) { kind in
                kindButton(kind)
            }
        }
    }

    private func kindButton(_ kind: GoalKind) -> some View {
        let isSelected = selection == kind
        let tint = GoalKindPalette.color(for: kind)

        return Button {
            selection = kind
        } label: {
            HStack(spacing: 8) {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.onColor : tint)
                    .frame(width: 22, height: 22)
                    .background(isSelected ? tint : tint.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 1) {
                    Text(kind.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isSelected ? Theme.text : Theme.muted)
                        .lineLimit(1)
                    Text(kind.detail)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(isSelected ? tint.opacity(0.12) : Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(isSelected ? tint.opacity(0.45) : Theme.borderSubtle, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.cadencePlain)
    }
}

struct GoalKindBadge: View {
    let kind: GoalKind

    var body: some View {
        CommitmentMetaChip(
            label: kind.label,
            color: GoalKindPalette.color(for: kind),
            systemImage: kind.systemImage
        )
    }
}
#endif
