#if os(iOS)
import SwiftData
import SwiftUI

// The parts of `iOSCreateTaskSheet` that are not the sheet itself: the do-date buttons, the value
// rows under them, and the suggestion row the `~` and `#` title markers raise.
//
// Every control here is an existing shared one — `iOSEditorSection` / `iOSEditorFieldRow` /
// `iOSEditorDivider` for the rows, `iOSChoiceValueButton` for a row's trailing value,
// `iOSContainerChoicePopover` / `iOSChoicePopoverList` / `CadenceDatePicker` /
// `iOSTaskTagPickerPopover` for what they open. Nothing in this file draws a picker of its own, and
// the row vocabulary is deliberately the task inspector's: the two screens edit the same fields, so
// filling one in and correcting it afterwards should not be two different-looking jobs.

// MARK: - Do date buttons

/// **Today / Tomorrow / Pick…**, the do date's whole control.
///
/// It is not a value row, and that is the point: of the five fields on this sheet the do date is the
/// one decided nearly every time, and a row would put the two answers it almost always gets behind
/// a picker. Here they are one tap each. Tapping the day the draft already has clears it — see
/// `CadenceTaskComposerSupport.toggledDoDateKey` — so a mis-tap costs one tap to undo.
///
/// The third button carries a custom day once one is set (`Pick…` → `Sep 3`), so the trio always
/// states the answer rather than only offering two of them.
///
/// It is **not** `iOSSegmentedChoice`: a segmented control asserts that exactly one of its options
/// is true, and here none may be — an unset do date is the common case — while the third option
/// opens a popover rather than selecting a value.
struct iOSTaskComposerDoDateButtons: View {
    @Binding var doDateKey: String

    @State private var isPickerOpen = false
    @State private var viewMonth = Date()

    private var pickedDate: Date {
        DateFormatters.date(from: doDateKey) ?? Date()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The same glyph-in-a-fixed-slot label the rows below use, so "Do" starts on the same x
            // as "List" and "Due" and the sheet reads as one column of fields.
            iOSEditorInlineLabel(label: "Do", systemImage: "sun.max.fill")

            HStack(spacing: 6) {
                dayButton(.today)
                dayButton(.tomorrow)
                pickButton
            }
        }
    }

    private func dayButton(_ choice: CadenceTaskComposerSupport.DoDateChoice) -> some View {
        let isSelected = CadenceTaskComposerSupport.isSelected(choice, doDateKey: doDateKey)

        return button(title: choice.label, isSelected: isSelected) {
            doDateKey = CadenceTaskComposerSupport.toggledDoDateKey(current: doDateKey, tapping: choice)
        }
        .accessibilityHint(isSelected ? "Clears the do date" : "Sets the do date")
    }

    private var pickButton: some View {
        let isSelected = CadenceTaskComposerSupport.isCustomDoDate(doDateKey)

        return button(
            title: CadenceTaskComposerSupport.doDatePickLabel(doDateKey),
            isSelected: isSelected
        ) {
            viewMonth = monthStart(of: pickedDate)
            isPickerOpen = true
        }
        .popover(isPresented: $isPickerOpen) {
            CadenceQuickDatePopover(
                selection: Binding(
                    get: { pickedDate },
                    set: { doDateKey = DateFormatters.dateKey(from: $0) }
                ),
                viewMonth: $viewMonth,
                isOpen: $isPickerOpen,
                showsClear: !doDateKey.isEmpty,
                onClear: { doDateKey = "" }
            )
            .background(Theme.surfaceElevated)
            // Stays an anchored overlay on iPhone instead of being promoted into a full-height
            // sheet, which would take the keyboard down with it.
            .presentationCompactAdaptation(.popover)
        }
    }

    private func button(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? Theme.onColor : Theme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(isSelected ? Theme.blue : Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
                .contentShape(Rectangle())
                // 40pt plate, 44pt target — the same derivation `iOSTaskAttributeChipSize` makes.
                .iOSExpandedHitArea(2)
        }
        .buttonStyle(.iosPressable)
    }

    private func monthStart(of date: Date) -> Date {
        var components = Calendar.current.dateComponents([.year, .month], from: date)
        components.day = 1
        return Calendar.current.date(from: components) ?? date
    }
}

// MARK: - Value rows

/// **List · Section · Due · Priority · Tags** as labelled rows in the page, each stating its current
/// value on its trailing edge.
///
/// This replaced a horizontally-scrolling chip strip pinned above the keyboard. Two things were
/// wrong with the strip and only one of them was the clipping: six chips do not fit across a 390pt
/// phone, so the last of them sat off-screen — but the deeper problem is that this sheet is opened
/// from four places (the tab bar `+`, the iPad corner `+`, quick capture, and a `+` dragged onto a
/// row), three of which **seed** fields. A seeded chip reading "Errands" is indistinguishable from
/// an unseeded one until you have read the whole strip; a row reading `List   Errands` says what was
/// inherited without being hunted for.
///
/// Sizing note, because it is the constraint the whole shape was chosen against: each row is 44pt
/// with a 13pt divider, so every row costs 57pt of a ~380pt visible area on a phone with the
/// keyboard up. That is why the section row appears only when a list actually has sections to choose
/// between, and why the estimate is not here at all.
struct iOSTaskComposerFieldRows: View {
    @Binding var fields: CadenceTaskComposerFields
    @Binding var selectedTags: [Tag]
    @Binding var newTagName: String
    /// The live title, read only so the priority row can show a `!!!` the moment it is typed.
    let titleText: String
    let activeAreas: [Area]
    let activeProjects: [Project]
    let availableSections: [String]
    let allTags: [Tag]
    /// Setting the priority explicitly also has to take any `!` marker out of the title, or the
    /// marker would silently overrule the choice at creation.
    let onPickPriority: (TaskPriority) -> Void

    @State private var showContainerPicker = false
    @State private var showSectionPicker = false
    @State private var showPriorityPicker = false
    @State private var showTagPicker = false

    private var containerToken: Binding<String> {
        Binding(
            get: { CadenceTaskComposerSupport.token(for: fields.container) },
            set: { fields.container = CadenceTaskComposerSupport.selection(fromToken: $0) }
        )
    }

    private var selectedArea: Area? {
        guard case .area(let id) = fields.container else { return nil }
        return activeAreas.first { $0.id == id }
    }

    private var selectedProject: Project? {
        guard case .project(let id) = fields.container else { return nil }
        return activeProjects.first { $0.id == id }
    }

    private var containerTitle: String {
        if let selectedArea { return selectedArea.name.isEmpty ? "Untitled Area" : selectedArea.name }
        if let selectedProject { return selectedProject.name.isEmpty ? "Untitled Project" : selectedProject.name }
        return CadenceTaskInspectorSupport.inboxSegmentTitle
    }

    private var containerIcon: String {
        selectedProject == nil ? "tray.full.fill" : "checklist"
    }

    private var isInbox: Bool {
        fields.container == .inbox
    }

    private var showsSectionRow: Bool {
        CadenceTaskComposerSupport.showsSectionRow(
            container: fields.container,
            availableSections: availableSections
        )
    }

    private var resolvedPriority: TaskPriority {
        CadenceTaskComposerSupport.resolvedPriority(title: titleText, selected: fields.priority)
    }

    private var dueDateBinding: Binding<Date> {
        Binding(
            get: { DateFormatters.date(from: fields.dueDateKey) ?? Date() },
            set: { fields.dueDateKey = DateFormatters.dateKey(from: $0) }
        )
    }

    var body: some View {
        // No `contentSpacing`: `iOSEditorDivider` already pads itself on both sides and owns the
        // whole gap between two rows.
        iOSEditorSection(title: nil, style: .ruled) {
            listRow

            if showsSectionRow {
                iOSEditorDivider()
                sectionRow
            }

            iOSEditorDivider()
            dueRow

            iOSEditorDivider()
            priorityRow

            iOSEditorDivider()
            tagsRow
        }
    }

    /// The list's own colour is what tells two lists apart at a glance, so the glyph carries it —
    /// one of the two fields (with priority) whose *value* is a colour the user already reads as
    /// one. Everything else on the sheet stays `Theme.dim`.
    private var listRow: some View {
        iOSEditorFieldRow(
            label: "List",
            systemImage: containerIcon,
            color: isInbox ? Theme.dim : (selectedArea.map { Color(hex: $0.colorHex) } ?? selectedProject.map { Color(hex: $0.colorHex) } ?? Theme.dim)
        ) {
            iOSChoiceValueButton(
                title: containerTitle,
                // Inbox is the absence of a list, so it reads as unset even though it is a real
                // destination — the same treatment the inspector's breadcrumb gives it.
                color: isInbox ? Theme.dim : Theme.text,
                minHeight: 44
            ) {
                showContainerPicker = true
            }
            .popover(isPresented: $showContainerPicker) {
                iOSContainerChoicePopover(
                    activeAreas: activeAreas,
                    activeProjects: activeProjects,
                    selection: containerToken,
                    isPresented: $showContainerPicker
                )
            }
        }
    }

    private var sectionRow: some View {
        iOSEditorFieldRow(label: "Section", systemImage: "rectangle.split.3x1.fill") {
            iOSChoiceValueButton(
                // The real name of where the task will go, never "None": dimmer styling is what
                // conveys "unset", so the row and its picker cannot disagree.
                title: CadenceTaskInspectorSupport.sectionSegmentTitle(fields.sectionName),
                color: Theme.text,
                minHeight: 44
            ) {
                showSectionPicker = true
            }
            .popover(isPresented: $showSectionPicker) {
                iOSChoicePopoverList(
                    rows: availableSections.map { iOSChoiceRow(value: $0, title: $0, color: Theme.dim) },
                    selection: $fields.sectionName,
                    isPresented: $showSectionPicker
                )
            }
        }
    }

    /// The same `CadenceDatePicker` the inspector's Due row uses, placeholder and Clear included —
    /// one control for the whole field, with no separate switch that could disagree with it.
    private var dueRow: some View {
        iOSEditorFieldRow(label: "Due", systemImage: "flag.fill") {
            CadenceDatePicker(
                selection: dueDateBinding,
                placeholder: fields.dueDateKey.isEmpty ? "No due date" : nil,
                minHeight: 44,
                showsClear: !fields.dueDateKey.isEmpty,
                onClear: { fields.dueDateKey = "" }
            )
        }
    }

    private var priorityRow: some View {
        iOSEditorFieldRow(label: "Priority", systemImage: "exclamationmark.circle.fill") {
            iOSChoiceValueButton(
                title: CadenceTaskComposerSupport.priorityValueLabel(resolvedPriority),
                color: resolvedPriority == .none ? Theme.dim : Theme.priorityColor(resolvedPriority),
                minHeight: 44
            ) {
                showPriorityPicker = true
            }
            .popover(isPresented: $showPriorityPicker) {
                iOSChoicePopoverList(
                    rows: TaskPriority.allCases.map { priority in
                        iOSChoiceRow(
                            value: priority,
                            title: priority.label,
                            systemImage: "flag.fill",
                            color: Theme.priorityColor(priority)
                        )
                    },
                    selection: Binding(
                        get: { resolvedPriority },
                        set: { onPickPriority($0) }
                    ),
                    isPresented: $showPriorityPicker
                )
            }
        }
    }

    private var tagsRow: some View {
        iOSEditorFieldRow(label: "Tags", systemImage: "number") {
            iOSChoiceValueButton(
                title: CadenceTaskComposerSupport.tagsValueLabel(
                    names: selectedTags.map { $0.name.isEmpty ? $0.slug : $0.name }
                ),
                color: selectedTags.isEmpty ? Theme.dim : Theme.text,
                minHeight: 44
            ) {
                showTagPicker = true
            }
            .popover(isPresented: $showTagPicker) {
                iOSTaskTagPickerPopover(
                    selectedTags: $selectedTags,
                    allTags: allTags,
                    newTagName: $newTagName
                )
            }
        }
    }
}

// MARK: - Inline marker suggestions

/// Which title marker is currently open.
enum iOSTaskComposerMarkerKind {
    case list
    case tag
}

/// The row of suggestions a `~` or `#` in the title raises.
///
/// Hands are already on the keyboard here, which is exactly where the markers pay off — so the
/// suggestions sit under the title rather than in a popover that would need a second tap to reach.
/// Accepting one consumes the marker and its query out of the title
/// (`CadenceTaskComposerSupport.title(removingShortcut:)`); ignoring it and carrying on typing
/// leaves the text alone, so `~` is never a trap.
struct iOSTaskComposerMarkerSuggestions: View {
    let kind: iOSTaskComposerMarkerKind
    let shortcut: TaskTitleInlineShortcut
    let activeAreas: [Area]
    let activeProjects: [Project]
    let allTags: [Tag]
    let onPickContainer: (TaskContainerSelection) -> Void
    let onPickTag: (Tag) -> Void
    let onCreateTag: (String) -> Void

    private var trimmedQuery: String {
        shortcut.query.trimmingCharacters(in: .whitespaces)
    }

    private var matchingAreas: [Area] {
        activeAreas.filter { CadenceTaskComposerSupport.matchesQuery($0.name, query: shortcut.query) }
    }

    private var matchingProjects: [Project] {
        activeProjects.filter { CadenceTaskComposerSupport.matchesQuery($0.name, query: shortcut.query) }
    }

    private var matchingTags: [Tag] {
        TagSupport.uniqueBySlug(allTags.filter { !$0.isArchived })
            .filter { CadenceTaskComposerSupport.matchesQuery($0.name.isEmpty ? $0.slug : $0.name, query: shortcut.query) }
    }

    private var showsInbox: Bool {
        CadenceTaskComposerSupport.matchesQuery(CadenceTaskInspectorSupport.inboxSegmentTitle, query: shortcut.query)
    }

    private var canCreateTag: Bool {
        guard kind == .tag, !trimmedQuery.isEmpty else { return false }
        return !matchingTags.contains { ($0.name.isEmpty ? $0.slug : $0.name).caseInsensitiveCompare(trimmedQuery) == .orderedSame }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                switch kind {
                case .list:
                    listSuggestions
                case .tag:
                    tagSuggestions
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 44)
    }

    @ViewBuilder
    private var listSuggestions: some View {
        if showsInbox {
            suggestion(
                title: CadenceTaskInspectorSupport.inboxSegmentTitle,
                systemImage: "tray.full.fill",
                tint: Theme.blue
            ) {
                onPickContainer(.inbox)
            }
        }

        ForEach(matchingAreas) { area in
            suggestion(
                title: area.name.isEmpty ? "Untitled Area" : area.name,
                systemImage: "tray.full.fill",
                tint: Color(hex: area.colorHex)
            ) {
                onPickContainer(.area(area.id))
            }
        }

        ForEach(matchingProjects) { project in
            suggestion(
                title: project.name.isEmpty ? "Untitled Project" : project.name,
                systemImage: "checklist",
                tint: Color(hex: project.colorHex)
            ) {
                onPickContainer(.project(project.id))
            }
        }

        if !showsInbox && matchingAreas.isEmpty && matchingProjects.isEmpty {
            emptyHint("No list matches “\(trimmedQuery)”")
        }
    }

    @ViewBuilder
    private var tagSuggestions: some View {
        if canCreateTag {
            suggestion(title: "Create “\(trimmedQuery)”", systemImage: "plus", tint: Theme.blue) {
                onCreateTag(trimmedQuery)
            }
        }

        ForEach(matchingTags) { tag in
            suggestion(
                title: tag.name.isEmpty ? tag.slug : tag.name,
                systemImage: "number",
                tint: Color(hex: tag.colorHex)
            ) {
                onPickTag(tag)
            }
        }

        if !canCreateTag && matchingTags.isEmpty {
            emptyHint("No tag matches “\(trimmedQuery)”")
        }
    }

    private func suggestion(
        title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
            }
            .padding(.horizontal, 11)
            .frame(minHeight: 34)
            .background(tint.opacity(0.13))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                    .strokeBorder(tint.opacity(0.24), lineWidth: 1)
            }
            .contentShape(Rectangle())
            .iOSExpandedHitArea(5)
        }
        .buttonStyle(.iosPressable)
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.dim)
            .lineLimit(1)
            .padding(.horizontal, 4)
            .frame(minHeight: 34)
    }
}
#endif
