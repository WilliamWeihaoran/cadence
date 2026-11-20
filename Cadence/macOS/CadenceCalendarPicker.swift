#if os(macOS)
import SwiftUI
import EventKit

// MARK: - Popover body

/// The list of calendars to embed inside a .popover().
/// Selecting a row writes to selectedID and can optionally close the popover.
struct CadenceCalendarPickerList: View {
    let calendars: [EKCalendar]
    @Binding var selectedID: String
    /// **T-464/T-467.** The link this list is offering, when its offer can contain a calendar from
    /// outside the normal set — the one already stored. The picker does not work out for itself
    /// which calendar that is, or what to call it: it has never had the full calendar list to work
    /// it out *from*, and a second opinion about which calendars are excluded is exactly what these
    /// tickets are about. `nil` for every caller whose offer is closed, which is the honest answer
    /// for them.
    var link: CadenceCalendarLink? = nil
    var allowNone: Bool = true
    /// Called after the user taps a row so the parent can dismiss the popover.
    var onPick: (() -> Void)? = nil

    @State private var searchQuery = ""
    @State private var highlightIdx = 0
    @FocusState private var isSearchFocused: Bool

    /// Calendars grouped by their account/source, each group sorted by name.
    ///
    /// **T-692.** This read the same absence — `cal.source?.title` missing — as Settings → Calendar
    /// and fell back to a different word: "Other" here, `CadenceAppleCalendarNaming
    /// .unnamedAccountTitle` ("Apple Calendar") there, for the same unnamed EventKit account. Now
    /// both say "Apple Calendar", which also doubles as this group's own heading (`SectionEyebrowLabel
    /// (text: group.source, …)` below), so an unnamed source's group in this popover reads the same
    /// as its row in Settings.
    private var allGroups: [(source: String, cals: [EKCalendar])] {
        // T-14701: the shared order, not a raw `<`, for the accounts and for the calendars in each.
        CadenceCalendarSorting.groupedBySource(
            calendars,
            source: { $0.source?.title ?? CadenceAppleCalendarNaming.unnamedAccountTitle },
            title: \.title,
            identifier: \.calendarIdentifier
        )
        .map { (source: $0.source, cals: $0.calendars) }
    }

    private var groups: [(source: String, cals: [EKCalendar])] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return allGroups }
        let needle = trimmed.localizedLowercase
        return allGroups.compactMap { group in
            let filtered = group.cals.filter { cal in
                cal.title.localizedLowercase.contains(needle) ||
                group.source.localizedLowercase.contains(needle)
            }
            guard !filtered.isEmpty else { return nil }
            return (source: group.source, cals: filtered)
        }
    }

    private struct PickerItem: Equatable {
        let id: String
        let label: String
        let color: Color?
    }

    private var flattenedItems: [PickerItem] {
        var items: [PickerItem] = []
        if allowNone {
            items.append(PickerItem(id: "", label: CadenceCalendarLinkRowState.unlinkedText, color: nil))
        }
        for group in groups {
            items.append(contentsOf: group.cals.map {
                PickerItem(id: $0.calendarIdentifier, label: label(for: $0), color: Color(cgColor: $0.cgColor))
            })
        }
        return items
    }

    /// A search that matched no calendar. The unlinked row goes with it: picking it while looking
    /// for something named is not what the search was for ([[T-18637]]).
    private var searchFoundNothing: Bool {
        CadenceCalendarPickerKeyboard.searchFoundNothing(itemIDs: flattenedItems.map(\.id), query: searchQuery)
    }

    /// A calendar's name in this list. An excluded one carries the link's wording, so the calendar
    /// the field row calls "Team (Hidden)" — or "Holidays (Read-only)" — is the same words in the
    /// menu the row opens.
    private func label(for calendar: EKCalendar) -> String {
        link?.pickerLabel(title: calendar.title, calendarID: calendar.calendarIdentifier)
            ?? calendar.title
    }

    /// **[[T-18639]].** The rows scroll under a pinned search field, inside a reader that keeps the
    /// arrow-key highlight on screen -- the Cmd+K palette's rule ([[T-8063]]). The hosts used to wrap
    /// this whole list in their own `ScrollView`, where nothing could reach the proxy, so holding
    /// Down walked the highlight below the popover's 320pt floor and Return picked an unseen row.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField

            Divider().background(Theme.borderSubtle).padding(.top, 6)

            ScrollViewReader { proxy in
                ScrollView {
                    rows
                }
                .onAppear { scrollToHighlighted(proxy) }
                .onChange(of: highlightedItemID) { _, _ in scrollToHighlighted(proxy) }
            }
        }
        .padding(.vertical, 4)
        .frame(minWidth: 240)
        .onAppear {
            isSearchFocused = true
            syncHighlight()
        }
        .onChange(of: searchQuery) { _, _ in
            syncHighlight()
        }
    }

    /// The highlighted row's id; each row is tagged with exactly its item id below.
    private var highlightedItemID: String? {
        highlightIdx >= 0 && highlightIdx < flattenedItems.count ? flattenedItems[highlightIdx].id : nil
    }

    private func scrollToHighlighted(_ proxy: ScrollViewProxy) {
        guard let highlightedItemID else { return }
        proxy.scrollTo(highlightedItemID)
    }

    @ViewBuilder
    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            if searchFoundNothing || (groups.isEmpty && !allowNone) {
                Text("No matching calendars")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                if allowNone {
                    row(id: "", label: CadenceCalendarLinkRowState.unlinkedText, color: nil)
                    Divider().background(Theme.borderSubtle).padding(.vertical, 2)
                }
                ForEach(groups, id: \.source) { group in
                    SectionEyebrowLabel(text: group.source, size: .compact)
                        .padding(.horizontal, 14)
                        .padding(.top, 8)
                        .padding(.bottom, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(group.cals, id: \.calendarIdentifier) { cal in
                        row(
                            id: cal.calendarIdentifier,
                            label: label(for: cal),
                            color: Color(cgColor: cal.cgColor)
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(id: String, label: String, color: Color?) -> some View {
        let isSelected = selectedID == id
        let isHighlighted = highlightIdx < flattenedItems.count && flattenedItems[highlightIdx].id == id
        Button {
            pick(id)
        } label: {
            HStack(spacing: 10) {
                Group {
                    if let color {
                        Circle().fill(color)
                    } else {
                        Circle().strokeBorder(Theme.dim.opacity(0.45), lineWidth: 1.5)
                    }
                }
                .frame(width: 10, height: 10)

                Text(label)
                    .font(.system(size: 13))
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
            .frame(minHeight: 30)
            .background(isSelected ? Theme.blue.opacity(0.08) : (isHighlighted ? Theme.blue.opacity(0.05) : Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        // [[T-9465]]: the row style is the one hover plate.
        .buttonStyle(.cadenceMenuRow)
        .padding(.horizontal, 4)
        .id(id)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Theme.dim)

            TextField("Search calendars", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text)
                .focused($isSearchFocused)
                .onSubmit {
                    guard let target = CadenceCalendarPickerKeyboard.submitTarget(
                        itemIDs: flattenedItems.map(\.id),
                        query: searchQuery,
                        highlightIndex: highlightIdx
                    ) else { return }
                    pick(target)
                }

            CadenceSearchFieldClearButton(text: $searchQuery, glyphSize: 12, focus: $isSearchFocused)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 8)
        .onMoveCommand { direction in
            guard !flattenedItems.isEmpty else { return }
            switch direction {
            case .down:
                highlightIdx = min(highlightIdx + 1, flattenedItems.count - 1)
            case .up:
                highlightIdx = max(highlightIdx - 1, 0)
            default:
                break
            }
        }
    }

    private func pick(_ id: String) {
        selectedID = id
        onPick?()
    }

    private func syncHighlight() {
        highlightIdx = CadenceCalendarPickerKeyboard.highlightIndex(
            itemIDs: flattenedItems.map(\.id),
            selectedID: selectedID,
            query: searchQuery,
            current: highlightIdx
        )
    }
}

/// What the calendar picker's search field does with the keyboard ([[T-18637]]) -- the
/// [[T-14791]] rule `CadenceContextPickerKeyboard` already applies to its context sibling.
///
/// The unlinked row (id `noneID`) is always first in `flattenedItems` when `allowNone`, even while a
/// query is typed and even when the body draws "No matching calendars" in its place, and the
/// highlight used to follow the current selection whenever it was in the list. So with nothing
/// linked, typing `Work` and pressing Return picked the unlinked row again; and a query that
/// matched nothing left only that hidden row, which Return picked -- unlinking the list's calendar
/// on Save. While a query is typed the highlight now moves to the first matching calendar, and
/// Return over no match picks nothing; an empty field still follows the selection.
enum CadenceCalendarPickerKeyboard {
    /// The unlinked row's id, which is also what `selectedID` holds when nothing is linked.
    static let noneID = ""

    private static func isSearching(_ query: String) -> Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// A typed query that matched no calendar. The unlinked row alone is not a match.
    static func searchFoundNothing(itemIDs: [String], query: String) -> Bool {
        isSearching(query) && itemIDs.allSatisfy { $0 == noneID }
    }

    /// The row to highlight after the list or the query changes: the first matching calendar while
    /// searching, otherwise the current selection.
    static func highlightIndex(itemIDs: [String], selectedID: String, query: String, current: Int) -> Int {
        guard !itemIDs.isEmpty else { return 0 }
        if isSearching(query) {
            return itemIDs.firstIndex(where: { $0 != noneID }) ?? 0
        }
        if let selectedIndex = itemIDs.firstIndex(of: selectedID) {
            return selectedIndex
        }
        return min(max(current, 0), itemIDs.count - 1)
    }

    /// The id Return picks -- `noneID` is "unlink" -- or `nil` for nothing at all.
    static func submitTarget(itemIDs: [String], query: String, highlightIndex: Int) -> String? {
        guard !searchFoundNothing(itemIDs: itemIDs, query: query),
              highlightIndex >= 0, highlightIndex < itemIDs.count else { return nil }
        return itemIDs[highlightIndex]
    }
}

// MARK: - Button + popover combo

/// Drop-in replacement for any calendar picker in the app.
/// Shows the selected calendar's real iCal color and name; opens a styled popover on tap.
struct CadenceCalendarPickerButton: View {
    let calendars: [EKCalendar]
    @Binding var selectedID: String
    var allowNone: Bool = true
    /// **T-467.** The link this button is editing, when the offer it was handed can exclude the
    /// calendar already stored. It words the button's value and the menu's row with one rule, so
    /// the button cannot call a calendar something the menu under it does not.
    var link: CadenceCalendarLink? = nil
    /// Pass `.compact` for tighter padding (e.g. inside table rows).
    var style: CadenceCalendarPickerStyle = .standard

    @State private var showPicker = false

    private var selected: EKCalendar? {
        calendars.first { $0.calendarIdentifier == selectedID }
    }

    /// What the button prints for the calendar it is showing, or `nil` when it is showing none.
    ///
    /// Without a link this is the calendar's plain title, which is every closed offer's honest
    /// answer. `nil` is still worded by the button itself: "no calendar" and the menu's "None" are
    /// two different sentences in two different places, and unifying them is not this ticket.
    private var selectedLabel: String? {
        guard let selected else { return nil }
        return link?.pickerLabel(title: selected.title, calendarID: selected.calendarIdentifier)
            ?? selected.title
    }

    var body: some View {
        Button { showPicker.toggle() } label: {
            HStack(spacing: style.dotLabelSpacing) {
                // Color dot
                Group {
                    if let cal = selected {
                        Circle().fill(Color(cgColor: cal.cgColor))
                    } else {
                        Circle().strokeBorder(Theme.dim.opacity(0.45), lineWidth: 1.5)
                    }
                }
                .frame(width: style.dotSize, height: style.dotSize)

                // Label
                Text(selectedLabel ?? "No calendar")
                    .font(.system(size: style.fontSize))
                    .foregroundStyle(selected != nil ? Theme.text : Theme.dim)
                    .lineLimit(1)

                Spacer(minLength: 6)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: style.chevronSize, weight: .semibold))
                    .foregroundStyle(Theme.dim)
            }
            .padding(.horizontal, style.hPad)
            .padding(.vertical, style.vPad)
            .frame(minHeight: style == .compact ? 28 : 32)
            .contentShape(Rectangle())
            .background(Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius))
        }
        .buttonStyle(.cadencePlain(cornerRadius: style.cornerRadius))
        .popover(isPresented: $showPicker, arrowEdge: .bottom) {
            // The list scrolls its own rows ([[T-18639]]).
            CadenceCalendarPickerList(
                calendars: calendars,
                selectedID: $selectedID,
                link: link,
                allowNone: allowNone,
                onPick: { showPicker = false }
            )
            .frame(maxHeight: 320)
            .background(Theme.surface)
        }
    }
}

// MARK: - Style tokens

enum CadenceCalendarPickerStyle {
    case standard   // EditListSheet, standalone usage
    case compact    // QuickCreate popovers

    var fontSize: CGFloat     { self == .compact ? 12 : 13 }
    var dotSize: CGFloat      { self == .compact ? 9 : 10 }
    var dotLabelSpacing: CGFloat { self == .compact ? 6 : 8 }
    var chevronSize: CGFloat  { self == .compact ? 8 : 9 }
    var hPad: CGFloat         { self == .compact ? 9 : 10 }
    var vPad: CGFloat         { self == .compact ? 5 : 9 }
    var cornerRadius: CGFloat { self == .compact ? 7 : 8 }
}

#endif
