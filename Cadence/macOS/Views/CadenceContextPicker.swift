#if os(macOS)
import SwiftUI

// Moved out of `Shared/Components/` by T-288 rather than unfenced, and that was the live choice:
// T-288 named this file as "the one with a counterpart to converge on", because iOS spells a
// "pick a context" control twice more (`iOSListEditorViews`, `iOSTrackingEditorSheets`).
//
// It is not convergeable as written. `CadenceContextPickerList` is keyboard-first — `onMoveCommand`
// (macOS/tvOS only), a focused search field that takes focus on appear, a highlight index driven by
// arrow keys, an `onSubmit` that commits it — and `ContextPickerRowHover` is a hover wash. On iOS
// none of that fires, and what would be left is a list with a keyboard permanently up. The two iOS
// call sites already route through the shared `iOSChoiceRow` / `iOSChoicePopoverList` idiom, which
// is the touch answer to the same question.
//
// **T-446 finished it the other way round.** The two presentations stayed two; the *list* under them
// became one. Sort, the archive rule, the unnamed-context fallback and the "none" row are
// `CadenceContextPickerSupport` now — read here and at all three iOS sites — and the four spellings
// they replaced did not agree: see that type's doc for what each got wrong. Nothing below derives a
// context list; it presents one.

struct CadenceContextPickerButton: View {
    let contexts: [Context]
    @Binding var selectedID: UUID?
    var allowNone = true
    var style: CadenceContextPickerStyle = .standard

    @State private var showPicker = false

    private var selectedItem: CadenceContextPickerSupport.Item {
        CadenceContextPickerSupport.selectedItem(
            from: contexts,
            selectedID: selectedID,
            noneTitle: "No context"
        )
    }

    var body: some View {
        Button { showPicker.toggle() } label: {
            HStack(spacing: style.iconLabelSpacing) {
                selectedIcon

                Text(selectedItem.title)
                    .font(.system(size: style.fontSize, weight: .medium))
                    .foregroundStyle(selectedItem.isNone ? Theme.dim : Theme.text)
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
            ScrollView {
                CadenceContextPickerList(
                    contexts: contexts,
                    selectedID: $selectedID,
                    allowNone: allowNone,
                    onPick: { showPicker = false }
                )
            }
            .frame(width: 260)
            .frame(maxHeight: 320)
            .background(Theme.surface)
        }
    }

    private var selectedIcon: some View {
        let item = selectedItem
        return Image(systemName: item.icon ?? "circle")
            .font(.system(size: style.iconSize, weight: .semibold))
            .foregroundStyle(item.tint)
            .frame(width: style.iconBoxSize, height: style.iconBoxSize)
            .background(item.isNone ? Theme.surface : item.tint.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: style.iconCornerRadius))
    }
}

struct CadenceContextPickerList: View {
    let contexts: [Context]
    @Binding var selectedID: UUID?
    var allowNone = true
    var onPick: (() -> Void)? = nil

    @State private var searchQuery = ""
    @State private var highlightIndex = 0
    @FocusState private var isSearchFocused: Bool

    private var pickerItems: [CadenceContextPickerSupport.Item] {
        CadenceContextPickerSupport.items(
            from: contexts,
            selectedID: selectedID,
            query: searchQuery,
            noneTitle: allowNone ? "No context" : nil
        )
    }

    /// A search that matched no context. The "no context" row goes with it: picking it while
    /// looking for something named is not what the search was for.
    private var searchFoundNothing: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && pickerItems.allSatisfy(\.isNone)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField

            Divider().background(Theme.borderSubtle).padding(.top, 6)

            if searchFoundNothing {
                Text("No matching contexts")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(pickerItems) { item in
                    row(item)
                    if item.isNone {
                        Divider().background(Theme.borderSubtle).padding(.vertical, 2)
                    }
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
            guard !pickerItems.isEmpty else { return }
            switch direction {
            case .down:
                highlightIndex = min(highlightIndex + 1, pickerItems.count - 1)
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

            TextField("Search contexts", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text)
                .focused($isSearchFocused)
                .onSubmit {
                    guard highlightIndex >= 0, highlightIndex < pickerItems.count else { return }
                    pick(pickerItems[highlightIndex].id)
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
    private func row(_ item: CadenceContextPickerSupport.Item) -> some View {
        let isSelected = selectedID == item.id
        let isHighlighted = highlightIndex < pickerItems.count && pickerItems[highlightIndex].id == item.id
        let tint = item.tint

        Button {
            pick(item.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.icon ?? "circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 22, height: 22)
                    .background(tint.opacity(item.isNone ? 0.06 : 0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Text(item.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Theme.text : Theme.muted)
                    .lineLimit(1)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.blue)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .frame(minHeight: 32)
            .background(isSelected ? Theme.blue.opacity(0.08) : (isHighlighted ? Theme.blue.opacity(0.05) : Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.cadencePlain)
        .modifier(ContextPickerRowHover())
        .padding(.horizontal, 4)
    }

    private func pick(_ id: UUID?) {
        selectedID = id
        onPick?()
    }

    private func syncHighlight() {
        let items = pickerItems
        guard !items.isEmpty else {
            highlightIndex = 0
            return
        }

        if let selectedIndex = items.firstIndex(where: { $0.id == selectedID }) {
            highlightIndex = selectedIndex
        } else {
            highlightIndex = min(highlightIndex, items.count - 1)
        }
    }
}

enum CadenceContextPickerStyle {
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

private struct ContextPickerRowHover: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Theme.blue.opacity(0.06) : Color.clear)
            )
            .onHover { isHovered = $0 }
    }
}
#endif
