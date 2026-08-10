#if os(macOS)
import SwiftUI
import SwiftData
import AppKit

struct TasksPanelHeader: View {
    let mode: TasksPanelMode

    @Environment(TaskCreationManager.self) private var taskCreationManager

    private var title: String {
        switch mode {
        case .todayOverview: return "Today"
        case .byDoDate:      return "By Do Date"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                PanelHeader(eyebrow: "Tasks", title: title)
                Spacer()
                Button {
                    switch mode {
                    case .todayOverview: taskCreationManager.present(doDateKey: DateFormatters.todayKey())
                    case .byDoDate:      taskCreationManager.present()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                        Text("New Task").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Theme.onColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.cadencePlain)
                .padding(.top, 15)
                .padding(.trailing, 16)
            }
        }
    }
}

struct TodayOverdueListCard: View {
    let summary: TodayOverdueListSummary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(summary.color.opacity(0.16))
                    .frame(width: 30, height: 30)
                    .overlay {
                        Image(systemName: summary.icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(summary.color)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Text("\(DateFormatters.relativeDate(from: summary.dueDateKey)) • \(summary.activeTaskCount) active tasks")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.red)
                        .lineLimit(1)
                }

                Spacer()

                Text("List")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.red)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Theme.red.opacity(0.12))
                    .clipShape(Capsule())
            }
            .padding(16)
            .cadenceCard(background: Theme.red.opacity(0.08), cornerRadius: Theme.radiusCard, shadowRadius: 12, shadowY: 5)
        }
        .buttonStyle(.cadencePlain)
    }
}

struct TodayOverdueSectionCard: View {
    let summary: TodayOverdueSectionSummary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(summary.parentColor.opacity(0.16))
                    .frame(width: 30, height: 30)
                    .overlay {
                        Image(systemName: summary.parentIcon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(summary.parentColor)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.sectionName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Text("\(summary.parentName) • \(DateFormatters.relativeDate(from: summary.dueDateKey))")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.red)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(summary.openTaskCount) open")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    if summary.completedTaskCount > 0 {
                        Text("\(summary.completedTaskCount) done")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.dim)
                    }
                }
            }
            .padding(16)
            .cadenceCard(background: Theme.red.opacity(0.08), cornerRadius: Theme.radiusCard, shadowRadius: 12, shadowY: 5)
        }
        .buttonStyle(.cadencePlain)
    }
}

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

    private var label: String {
        switch selection {
        case .inbox:           return "Inbox"
        case .area(let id):    return areas.first(where: { $0.id == id })?.name ?? "Area"
        case .project(let id): return projects.first(where: { $0.id == id })?.name ?? "Project"
        }
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
        .popover(isPresented: $showPicker) {
            ContainerPickerPopoverContent(contexts: contexts, areas: areas, projects: projects) { picked in
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

struct CollapsibleTaskGroupHeader: View {
    let title: String
    let isCollapsed: Bool
    let overdueCount: Int?
    let regularCount: Int
    var accent: Color = Theme.dim
    let onToggle: () -> Void

    @State private var isHovered = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                if let overdueCount, overdueCount > 0 {
                    Text("\(overdueCount)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.red)
                    Text("/")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.dim.opacity(0.8))
                }
                Text("\(regularCount)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(accent)
            }
            .foregroundStyle(Theme.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            // Exactly one hover layer at one radius: the same neutral wash the task rows below
            // use, transparent at rest and with no border. The previous treatment stacked a
            // resting card, its shadow, and `CadencePlainButtonStyle`'s blue fill and stroke at a
            // different radius, which made a hovered header read as a focused text field.
            .background(shape.fill(TaskHoverVisuals.hoverFill(isHovered: isHovered)))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2, perform: onToggle)
    }
}

struct CompletedSectionHeader: View {
    let count: Int
    var isCollapsed: Bool = false
    var onToggle: (() -> Void)? = nil

    var body: some View {
        CollapsibleTaskGroupHeader(
            title: "Completed",
            isCollapsed: isCollapsed,
            overdueCount: nil,
            regularCount: count,
            accent: Theme.green,
            onToggle: { onToggle?() }
        )
        .allowsHitTesting(onToggle != nil)
        .overlay {
            if onToggle == nil {
                RoundedRectangle(cornerRadius: Theme.radiusControl)
                    .fill(Color.clear)
                    .allowsHitTesting(false)
            }
        }
    }
}

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
