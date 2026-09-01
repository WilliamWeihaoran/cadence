#if os(macOS)
import SwiftUI
import SwiftData
import AppKit

/// Today's task column header, and the one place macOS says what day it is.
///
/// **This is `iPadTodayTaskHeader`'s row, on macOS.** It read `TASKS / Today` — an eyebrow naming
/// the column and a title naming the page, neither of which the day changes — while iOS read
/// `WEDNESDAY, AUGUST 19 · 1 done / Today` with the day's open count beside it. The date and the
/// summary win: they are the two facts about *this* day, and a column headed "TASKS" on a screen
/// whose only content is tasks is the header-describes-its-own-page rule one row down.
///
/// There is **no identity tile**, here or anywhere else. macOS was about to gain one from iOS's
/// header; the user's call went the other way — drop them everywhere — so `DesktopPageHeader` and
/// `iOSPageHeader` no longer draw one at all.
///
/// The capture button stays in the trailing slot — Today's task column is the one macOS task
/// surface with no floating `+` over it, so this is its affordance rather than a second one, and
/// `CadenceTodayPresentationSupport.emptySubtitle` points at it by name.
///
/// **It is a glyph now, not a `+ New Task` pill.** Measured, not preferred: the task column's
/// declared minimum is 300pt, and at that width the pill left ~150pt for an eyebrow that needs
/// ~130 — so "THURSDAY, AUGUST 20" truncated to "THURSDAY, AUGU…" the moment the divider was
/// dragged left. It is also the last survivor of the header pills `DesktopPrimaryActionButton`
/// was deleted with; every other macOS task surface captures through a circular `+`.
///
/// It took a `mode` until T-487, and answered "By Do Date" over the eyebrow "Tasks" for the
/// `.byDoDate` panel. That panel was unreachable, so this row has only ever rendered the day.
struct TasksPanelHeader: View {
    /// The day's counts. Not optional: this header only exists on the day's page.
    let summary: CadenceTodaySummary

    @Environment(TaskCreationManager.self) private var taskCreationManager

    private let title = "Today"

    /// The day itself — `DateFormatters.longDate`, uppercased by `SectionEyebrowLabel`, exactly as
    /// both iOS Todays spell it.
    private var eyebrow: String { DateFormatters.longDate.string(from: Date()) }

    var body: some View {
        DesktopPageHeader(
            role: .pane,
            eyebrow: eyebrow,
            // The half that gives way: the eyebrow proper holds the layout priority, so a narrow
            // task column truncates "· 3 timed" before it truncates the date.
            eyebrowDetail: summary.line,
            title: title,
            count: summary.activeCount,
            // Today's colour, and with the tile gone the count capsule is the only thing wearing
            // it. iPad Today passes the same `Theme.amber` for the same badge.
            tint: Theme.amber,
            // The panel paints its own plate behind the header band.
            background: nil
        ) {
            newTaskButton
        }
    }

    private var newTaskButton: some View {
        Button {
            taskCreationManager.present(doDateKey: DateFormatters.todayKey())
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.onColor)
                .frame(width: 28, height: 28)
                .background(Theme.blue)
                .clipShape(Circle())
        }
        .buttonStyle(.cadencePlain)
        .help("New task for today")
        .accessibilityLabel("New task")
    }
}

// The two past-due summary cards used to be here — `TodayOverdueListCard`,
// `TodayOverdueSectionCard`, their shared `OverdueSummaryCard` chrome and the
// `OverdueSummaryCaption` both read. They are `Shared/Components/CadenceTodayOverdueSummaryCards.swift`
// now (T-195, second half), rendered by iOS's Today as well as this panel. Nothing in them was
// AppKit-shaped; the one thing that was — the `ListNavigationManager` hop behind the tap — never
// lived in the card and still does not.

struct SubtaskRow: View {
    @Bindable var subtask: Subtask
    var showDelete: Bool = false
    var onDelete: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Button { subtask.isDone.toggle() } label: {
                Image(systemName: subtask.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(subtask.isDone ? Theme.green : Theme.dim.opacity(0.6))
            }
            .buttonStyle(.cadencePlain)

            Text(subtask.title.isEmpty ? "Untitled" : subtask.title)
                .font(.system(size: 13))
                .foregroundStyle(subtask.isDone ? Theme.dim : Theme.muted)
                .strikethrough(subtask.isDone, color: Theme.dim)
                .lineLimit(1)

            Spacer(minLength: 0)

            if showDelete, let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.dim.opacity(0.5))
                }
                .buttonStyle(.cadencePlain)
            }
        }
        .padding(.vertical, 3)
    }
}

struct ContainerPickerBadge: View {
    @Binding var selection: TaskContainerSelection
    let contexts: [Context]
    let areas: [Area]
    let projects: [Project]
    var compact: Bool = false
    /// Renders as plain icon+text with no pill background or chevron — used where the row
    /// itself already provides enough affordance (e.g. MacTaskRow's trailing metadata).
    var flat: Bool = false
    /// Renders as a bordered, unfilled chip with no chevron — used in toolbar rows
    /// (e.g. CreateTaskSheet) alongside other outlined chips.
    var outlined: Bool = false
    /// Renders the trigger as one segment of the task inspector's `List › Section` breadcrumb:
    /// icon + name, no pill, no chevron, sized to its text. The popover — search, arrow-key
    /// highlight, selection — is the same one the chip presents.
    var breadcrumbSegment: Bool = false

    @State private var showPicker = false

    /// The name of the list the selection actually resolves to, and "Inbox" when it resolves to
    /// none — including when the list it named has been deleted.
    ///
    /// It used to answer a bare "Area" / "Project" in that last case, which reads as a list and is
    /// not one: `TaskContainerResolver.applyContainer` attaches nothing for an id it cannot find,
    /// so the destination was already the Inbox and the badge was the only thing still claiming
    /// otherwise (T-317). Shared with the iOS composer's List tile so the two cannot drift.
    private var label: String {
        CadenceTaskComposerSupport.containerName(for: selection, areas: areas, projects: projects)
    }

    private var labelIcon: String {
        switch selection {
        case .inbox:           return "tray"
        case .area(let id):    return areas.first(where: { $0.id == id })?.icon ?? "tray"
        case .project(let id): return projects.first(where: { $0.id == id })?.icon ?? "tray"
        }
    }

    private var labelColor: Color {
        switch selection {
        case .inbox:           return Theme.dim
        case .area(let id):    return areas.first(where: { $0.id == id }).map { Color(hex: $0.colorHex) } ?? Theme.dim
        case .project(let id): return projects.first(where: { $0.id == id }).map { Color(hex: $0.colorHex) } ?? Theme.dim
        }
    }

    /// Inbox is the *absence* of a list, so the inspector row reads it as an unset field.
    private var hasContainer: Bool {
        selection != .inbox
    }

    @ViewBuilder
    private var trigger: some View {
        if breadcrumbSegment {
            // Always the real container name ("Inbox" when unset) so the segment and its picker
            // agree; the dimmer treatment is what conveys "no list chosen".
            // The leading glyph is the container's own icon in its own colour.
            HStack(spacing: 5) {
                Image(systemName: labelIcon)
                    .font(.system(size: 10))
                    .foregroundStyle(labelColor)
                Text(label)
                    .font(TaskInspectorBreadcrumbMetrics.font)
                    .foregroundStyle(hasContainer ? Theme.muted : Theme.dim)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: TaskInspectorBreadcrumbMetrics.maxSegmentWidth, alignment: .leading)
            }
            .padding(.horizontal, TaskInspectorBreadcrumbMetrics.segmentHorizontalPadding)
            .frame(minHeight: TaskInspectorBreadcrumbMetrics.segmentHeight)
            .contentShape(Rectangle())
        } else {
            HStack(spacing: 4) {
                Image(systemName: labelIcon).font(.system(size: compact ? 9 : 10)).foregroundStyle(labelColor)
                Text(label)
                    .font(.system(size: compact ? 10 : 11))
                    .foregroundStyle(flat ? Theme.dim : Theme.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: compact ? 60 : 80, alignment: .leading)
                if !flat && !outlined {
                    Image(systemName: "chevron.down").font(.system(size: compact ? 7 : 8, weight: .semibold)).foregroundStyle(Theme.dim)
                }
            }
            .padding(.horizontal, flat ? 0 : (compact ? 6 : 8))
            .padding(.vertical, flat ? 0 : (compact ? 3 : 6))
            .frame(minHeight: flat ? 0 : (compact ? 21 : 28))
            .contentShape(Rectangle())
            .background(flat || outlined ? AnyShapeStyle(Color.clear) : AnyShapeStyle(Theme.surfaceElevated))
            .clipShape(RoundedRectangle(cornerRadius: flat ? 0 : (compact ? 6 : 7)))
            .overlay {
                if outlined {
                    RoundedRectangle(cornerRadius: compact ? 6 : 7)
                        .stroke(Theme.borderSubtle, lineWidth: 1)
                }
            }
        }
    }

    var body: some View {
        Button { showPicker.toggle() } label: {
            trigger
        }
        .modifier(TaskPickerTriggerStyle(breadcrumbSegment: breadcrumbSegment))
        // On the badge itself rather than on the task row that hosts it, so every surface that
        // draws this chip — the row, the composer, the inspector breadcrumb — is named by fixing it
        // once. It announced only the container's name, so a row read "…, Inbox, button" with
        // nothing saying Inbox was the *list* (T-594).
        .accessibilityLabel(CadenceTaskControlAccessibility.list)
        .accessibilityValue(label)
        .popover(isPresented: $showPicker) {
            ContainerPickerPopoverContent(
                contexts: contexts,
                areas: areas,
                projects: projects,
                selection: selection
            ) { picked in
                selection = picked
                showPicker = false
            }
        }
    }
}

/// Button style for a container/section picker trigger.
///
/// Breadcrumb segments live inside the task inspector, so they take the inspector's single hover
/// layer at its own small radius; `cadencePlain`'s radius-10 fill and stroke would draw a chip
/// around text that is deliberately not a chip. Every other presentation keeps `cadencePlain`.
private struct TaskPickerTriggerStyle: ViewModifier {
    let breadcrumbSegment: Bool

    func body(content: Content) -> some View {
        if breadcrumbSegment {
            content
                .buttonStyle(.plain)
                .modifier(InspectorPickerHover(cornerRadius: TaskInspectorBreadcrumbMetrics.hoverCornerRadius))
        } else {
            content.buttonStyle(.cadencePlain)
        }
    }
}

struct TaskSectionPickerBadge: View {
    @Binding var selection: String
    let sections: [String]
    var compact: Bool = false
    /// Renders the trigger as one segment of the task inspector's `List › Section` breadcrumb:
    /// bare name, no pill, no chevron. Presents the same picker popover.
    var breadcrumbSegment: Bool = false

    @State private var showPicker = false
    @State private var searchQuery = ""
    @State private var highlightIdx = 0
    @FocusState private var isSearchFocused: Bool

    private var resolvedSections: [String] {
        let cleaned = sections
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return cleaned.isEmpty ? [TaskSectionDefaults.defaultName] : cleaned
    }

    private var filteredSections: [String] {
        guard !searchQuery.isEmpty else { return resolvedSections }
        return resolvedSections.filter { $0.lowercased().hasPrefix(searchQuery.lowercased()) }
    }

    private var highlightedSection: String? {
        guard !filteredSections.isEmpty else { return nil }
        return filteredSections[min(highlightIdx, filteredSections.count - 1)]
    }

    /// The section the current selection actually resolves to, or `nil` when it names a
    /// section this list no longer has.
    private var matchedSection: String? {
        resolvedSections.first(where: { $0.caseInsensitiveCompare(selection) == .orderedSame })
    }

    private var label: String {
        matchedSection ?? TaskSectionDefaults.defaultName
    }

    @ViewBuilder
    private var trigger: some View {
        if breadcrumbSegment {
            // Always the real section name ("Default" when the task isn't in a named section)
            // so the segment and its picker agree; dim styling conveys the unset state. No
            // glyph: the list segment beside it already carries the one icon this line needs.
            Text(label)
                .font(TaskInspectorBreadcrumbMetrics.font)
                .foregroundStyle(matchedSection != nil ? Theme.muted : Theme.dim)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: TaskInspectorBreadcrumbMetrics.maxSegmentWidth, alignment: .leading)
                .padding(.horizontal, TaskInspectorBreadcrumbMetrics.segmentHorizontalPadding)
                .frame(minHeight: TaskInspectorBreadcrumbMetrics.segmentHeight)
                .contentShape(Rectangle())
        } else {
            HStack(spacing: 4) {
                Image(systemName: "square.split.2x1")
                    .font(.system(size: compact ? 9 : 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: compact ? 11 : 13)
                Text(label)
                    .font(.system(size: compact ? 10 : 11, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: compact ? 70 : 90, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.system(size: compact ? 7 : 8, weight: .semibold))
                    .foregroundStyle(Theme.dim)
            }
            .padding(.horizontal, compact ? 6 : 10)
            .frame(height: compact ? 22 : 32)
            .contentShape(Rectangle())
            .background(compact ? Color.clear : Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay {
                if compact {
                    RoundedRectangle(cornerRadius: 7).stroke(Theme.borderSubtle, lineWidth: 1)
                }
            }
        }
    }

    var body: some View {
        Button { showPicker.toggle() } label: {
            trigger
        }
        .modifier(TaskPickerTriggerStyle(breadcrumbSegment: breadcrumbSegment))
        .popover(isPresented: $showPicker) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                    TextField("Search…", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text)
                        .focused($isSearchFocused)
                        .onSubmit {
                            if let section = highlightedSection {
                                selection = section
                                showPicker = false
                            }
                        }
                        .onKeyPress(.upArrow) {
                            highlightIdx = TaskPickerHighlightSupport.clampedMovedIndex(highlightIdx, by: -1, count: filteredSections.count)
                            return .handled
                        }
                        .onKeyPress(.downArrow) {
                            highlightIdx = TaskPickerHighlightSupport.clampedMovedIndex(highlightIdx, by: 1, count: filteredSections.count)
                            return .handled
                        }
                    if !searchQuery.isEmpty {
                        Button { searchQuery = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.dim.opacity(0.5))
                        }
                        .buttonStyle(.cadencePlain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider().background(Theme.borderSubtle)

                VStack(alignment: .leading, spacing: 2) {
                    ForEach(filteredSections, id: \.self) { section in
                        SectionPickerRow(
                            section: section,
                            isHighlighted: section == highlightedSection,
                            action: {
                                selection = section
                                showPicker = false
                            }
                        )
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(minWidth: 170)
            .background(Theme.surfaceElevated)
            .onAppear {
                highlightIdx = 0
                DispatchQueue.main.async { isSearchFocused = true }
            }
            .onChange(of: showPicker) { _, isShown in
                if !isShown {
                    searchQuery = ""
                    highlightIdx = 0
                }
            }
            .onChange(of: searchQuery) { _, _ in
                highlightIdx = 0
            }
        }
    }
}

private struct SectionPickerRow: View {
    let section: String
    let isHighlighted: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: section.caseInsensitiveCompare(TaskSectionDefaults.defaultName) == .orderedSame
                      ? "square.grid.2x2" : "rectangle.split.3x1")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 16)
                Text(section).font(.system(size: 13)).foregroundStyle(Theme.text).lineLimit(1)
                Spacer()
                if isHighlighted {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.blue)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
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

struct TaskPickerRowHover: ViewModifier {
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

// `CollapsibleTaskGroupHeader` and `CompletedSectionHeader` were here.
//
// `CollapsibleTaskGroupHeader` was the chevron-plus-counts row with the deliberately colourless
// numbers, and `CompletedSectionHeader` was the neutral "Completed" heading over the `.byDoDate`
// logbook. Between them they had three call sites — `TasksPanelGroupSectionView`,
// `TasksPanelFlatSectionView` and `TasksPanelCompletedSectionView`'s `else` — and all three were
// `.byDoDate`'s, so both went with the mode (T-487). `TasksPanelIntentSectionHeader` was here too
// until T-605 — the chevron-plus-`CadenceTaskGroupHeading` row Today drew — and it went the same
// way, into its one surviving sibling. **There is now exactly one macOS group header:**
// `TaskListGroupHeader` (`ListDetailSupportViews`), drawn by Today, All Tasks, Inbox and list
// detail. Anything new that heads a group of tasks on this platform is that, or it is a fifth
// spelling of it.

// `CompletedSectionHeader` was here — the neutral "Completed" heading the `.byDoDate` logbook
// drew instead of Today's "Completed Today". It had one call site, inside the `else` of
// `TasksPanelCompletedSectionView`'s mode branch, and went with the mode (T-487).

/// A picker enum with exactly two values, which reads better as a click-to-toggle than as a
/// two-item menu. `CadenceEnumPickerBadge` renders conforming types as a single flipping button,
/// so existing `CadenceEnumPickerBadge(title:selection:)` call sites need no change and every
/// surface gets the same affordance.
protocol CadenceToggleablePickerValue {
    /// Glyph naming the *current* state. With the menu gone this is the only thing carrying it,
    /// so it points the way the sort actually runs rather than being decorative.
    var toggleGlyph: String { get }
    /// Raw value one click flips to. Raw rather than `Self` so the generic badge can resolve it
    /// through `T(rawValue:)` without opening an existential.
    var toggledRawValue: String { get }
}

extension TaskSortDirection: CadenceToggleablePickerValue {
    var toggleGlyph: String { self == .ascending ? "arrow.up" : "arrow.down" }
    var toggledRawValue: String {
        (self == .ascending ? TaskSortDirection.descending : TaskSortDirection.ascending).rawValue
    }
}

struct CadenceEnumPickerBadge<T: CaseIterable & RawRepresentable & Identifiable>: View where T.RawValue == String {
    let title: String
    @Binding var selection: T
    var excluded: [T] = []
    @State private var showPicker = false

    private var availableCases: [T] {
        Array(T.allCases).filter { item in !excluded.contains(where: { $0.id == item.id }) }
    }

    @ViewBuilder
    var body: some View {
        if let toggleable = selection as? CadenceToggleablePickerValue {
            toggleBadge(toggleable)
        } else {
            menuBadge
        }
    }

    /// Two-value form: one button that flips on click. The leading glyph is the state readout —
    /// there is no menu to open and read the current value from.
    private func toggleBadge(_ toggleable: CadenceToggleablePickerValue) -> some View {
        CadenceQuietPillButton(state: .resting, action: {
            if let next = T(rawValue: toggleable.toggledRawValue) { selection = next }
        }) {
            badgeLabel(icon: toggleable.toggleGlyph, iconWeight: .bold, showsChevron: false)
        }
        .accessibilityLabel("\(title), \(selection.rawValue)")
        .help("\(title): \(selection.rawValue) — click to switch to \(toggleable.toggledRawValue)")
    }

    private var menuBadge: some View {
        CadenceQuietPillButton(state: .resting, action: { showPicker.toggle() }) {
            badgeLabel(icon: titleIcon, iconWeight: .semibold, showsChevron: true)
        }
        .accessibilityLabel("\(title), \(selection.rawValue)")
        .help("\(title): \(selection.rawValue)")
        .popover(isPresented: $showPicker) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(availableCases, id: \.id) { value in
                    Button {
                        selection = value
                        showPicker = false
                    } label: {
                        HStack(spacing: 8) {
                            Text(value.rawValue).font(.system(size: 13)).foregroundStyle(Theme.text)
                            Spacer()
                            if selection.id == value.id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Theme.blue)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .background(selection.id == value.id ? Theme.blue.opacity(0.08) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.cadencePlain)
                }
            }
            .padding(.vertical, 6)
            .frame(minWidth: 170)
            .background(Theme.surfaceElevated)
        }
    }

    /// Shared label so the toggle and menu forms are the same pill with the same metrics; only the
    /// leading glyph and the trailing chevron differ.
    private func badgeLabel(icon: String, iconWeight: Font.Weight, showsChevron: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: iconWeight))
                .foregroundStyle(Theme.muted)

            Text(selection.rawValue)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(Theme.dim)
            }
        }
    }

    private var titleIcon: String {
        switch title {
        case "Sort":
            return "arrow.up.arrow.down"
        case "Group":
            return "square.3.layers.3d"
        default:
            return "slider.horizontal.3"
        }
    }
}
#endif
