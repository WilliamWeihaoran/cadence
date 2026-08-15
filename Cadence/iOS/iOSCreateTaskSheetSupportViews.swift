#if os(iOS)
import SwiftData
import SwiftUI

// The parts of `iOSCreateTaskSheet` that are not the sheet itself: the chip strip that rides above
// the keyboard, the individual chips, and the suggestion row the `~` and `#` title markers raise.
//
// Every chip here is the shared `iOSTaskAttributeChip` wrapped around an existing picker
// (`iOSContainerChoicePopover`, `iOSChoicePopoverList`, `CadenceQuickDatePopover`,
// `iOSTaskTagPickerPopover`). Nothing in this file draws a picker of its own.

// MARK: - Chip strip

/// **List · Section · Do · Due · Priority · Tags**, pinned directly above the keyboard.
///
/// This strip is the design: capture is the app's highest-frequency action and now sits on the tab
/// bar of every screen, so the attributes have to be reachable with the thumb that is already on
/// the keyboard — without dismissing it, and without scrolling the sheet.
///
/// Each chip opens a `.popover`, and every one of those carries
/// `.presentationCompactAdaptation(.popover)` (inside the picker views themselves) so it stays a
/// small anchored overlay rather than being promoted into a full-height sheet that would take the
/// keyboard down with it.
struct iOSTaskComposerChipStrip: View {
    @Binding var fields: CadenceTaskComposerFields
    @Binding var selectedTags: [Tag]
    @Binding var newTagName: String
    /// The live title, read only so the priority chip can preview a `!!!` the moment it is typed.
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

    /// A list's own colour is the one thing that tells two lists apart at a glance, so it is one of
    /// the two attributes allowed to tint its chip.
    private var containerTint: Color? {
        if let selectedArea { return Color(hex: selectedArea.colorHex) }
        if let selectedProject { return Color(hex: selectedProject.colorHex) }
        return nil
    }

    private var resolvedPriority: TaskPriority {
        CadenceTaskComposerSupport.resolvedPriority(title: titleText, selected: fields.priority)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                containerChip

                if CadenceTaskComposerSupport.showsSectionChip(
                    container: fields.container,
                    availableSections: availableSections
                ) {
                    sectionChip
                }

                iOSTaskComposerDateChip(
                    placeholder: "Do",
                    systemImage: "sun.max.fill",
                    tint: Theme.blue,
                    dateKey: $fields.doDateKey
                )

                iOSTaskComposerDateChip(
                    placeholder: "Due",
                    systemImage: "flag.fill",
                    tint: Theme.red,
                    dateKey: $fields.dueDateKey
                )

                priorityChip
                tagChip
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity)
        // `surface`, not `surfaceElevated`: the chips themselves rest on `surfaceElevated` at 62%,
        // so a strip at the same token made every chip's plate invisible and left six bare
        // glyph-and-label pairs that read as static metadata rather than six controls.
        .background(Theme.surface)
    }

    private var containerChip: some View {
        iOSTaskAttributeChip(
            title: containerTitle,
            systemImage: containerIcon,
            isSet: fields.container != .inbox,
            tint: containerTint
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

    private var sectionChip: some View {
        iOSTaskAttributeChip(
            title: CadenceTaskInspectorSupport.sectionSegmentTitle(fields.sectionName),
            systemImage: "rectangle.split.3x1.fill",
            isSet: true
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

    /// The label is the `!!` mark rather than "Medium", because the same mark is what the title
    /// field accepts — the chip teaches the shortcut.
    ///
    /// The glyph is deliberately **not** `exclamationmark.2`: paired with a `!!` label it rendered
    /// as "!! !!" at medium and "!! !" at low, which reads as a count rather than as a field name
    /// with a value. A single circled bang names the field and lets the label alone carry how
    /// urgent this is.
    private var priorityChip: some View {
        iOSTaskAttributeChip(
            title: CadenceTaskComposerSupport.priorityChipLabel(resolvedPriority),
            systemImage: "exclamationmark.circle.fill",
            isSet: resolvedPriority != .none,
            tint: Theme.priorityColor(resolvedPriority)
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

    private var tagChip: some View {
        iOSTaskAttributeChip(
            title: CadenceTaskComposerSupport.tagChipLabel(
                names: selectedTags.map { $0.name.isEmpty ? $0.slug : $0.name }
            ),
            systemImage: "number",
            isSet: !selectedTags.isEmpty
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

// MARK: - Date chip

/// A do/due chip over the shared `CadenceQuickDatePopover` — the same Today / Tomorrow / This
/// Weekend pills, month grid and Clear row the task inspector's date fields open.
struct iOSTaskComposerDateChip: View {
    let placeholder: String
    let systemImage: String
    let tint: Color
    @Binding var dateKey: String

    @State private var isOpen = false
    @State private var viewMonth = Date()

    private var date: Date {
        DateFormatters.date(from: dateKey) ?? Date()
    }

    var body: some View {
        iOSTaskAttributeChip(
            title: CadenceTaskComposerSupport.dateChipLabel(dateKey, placeholder: placeholder),
            systemImage: systemImage,
            isSet: !dateKey.isEmpty,
            tint: tint
        ) {
            viewMonth = monthStart(of: date)
            isOpen = true
        }
        .popover(isPresented: $isOpen) {
            CadenceQuickDatePopover(
                selection: Binding(
                    get: { date },
                    set: { dateKey = DateFormatters.dateKey(from: $0) }
                ),
                viewMonth: $viewMonth,
                isOpen: $isOpen,
                showsClear: !dateKey.isEmpty,
                onClear: { dateKey = "" }
            )
            .background(Theme.surfaceElevated)
            .presentationCompactAdaptation(.popover)
        }
    }

    private func monthStart(of date: Date) -> Date {
        var components = Calendar.current.dateComponents([.year, .month], from: date)
        components.day = 1
        return Calendar.current.date(from: components) ?? date
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
