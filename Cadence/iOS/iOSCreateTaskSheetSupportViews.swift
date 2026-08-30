#if os(iOS)
import SwiftData
import SwiftUI

// The parts of `iOSCreateTaskSheet` that are not the sheet itself: the grid of value tiles and the
// suggestion strip the `~` and `#` title markers raise.
//
// Every control here is an existing shared one — `CadenceValueTile` for the tiles,
// `iOSContainerChoicePopover` / `iOSChoicePopoverList` / `CadenceQuickDatePopover` /
// `iOSTaskTagPickerPopover` for what they open. Nothing in this file draws a picker of its own, and
// nothing invents a fill, a radius or a caption style: a tile is `Theme.surface` at
// `Theme.radiusCard` under a `SectionEyebrowLabel`, which is what the sheet's title and notes fields
// already sit on.

// MARK: - Value tiles

/// **Do · Due**, **List · Priority**, then **Section · Tags** — three rows of 2-up tiles, with Tags
/// spreading across the last row on its own when the picked list has no sections.
///
/// This replaced five 57pt value rows, which had themselves replaced a horizontally-scrolling chip
/// strip pinned above the keyboard. The rows fixed the strip's real problem — this sheet opens from
/// four places (the tab bar `+`, the iPad corner `+`, quick capture, and a `+` dragged onto a row),
/// three of which **seed** fields, and a seeded chip is indistinguishable from an unseeded one — but
/// they bought it with height the sheet does not have. Each row spent a whole line on a field whose
/// label and value together are barely half a line wide, so the last of them sat under the software
/// keyboard, and a seeded value you cannot see is no better than a seeded chip you cannot tell
/// apart.
///
/// A tile states the same two things in the same order, stacked instead of spread, so two fields
/// share a line. Six fields cost three lines instead of six, and everything clears the fold — see
/// `CadenceTaskComposerLayout`, which is where the arithmetic lives and what the tests hold.
///
/// **Every tile opens its own picker and writes back through `fields`.** None of them is a label.
///
/// The estimate is still not here: how long something takes is a judgement made once the task is
/// real, and macOS's `CreateTaskSheet` has never offered one either.
struct iOSTaskComposerValueTiles: View {
    @Binding var fields: CadenceTaskComposerFields
    @Binding var selectedTags: [Tag]
    @Binding var newTagName: String
    /// The live title, read only so the priority tile can show a `!!!` the moment it is typed.
    let titleText: String
    /// **Every list, not the active ones.** These are the same two arrays the sheet builds its
    /// `TaskCreationService` from, which is the point: the List tile named its list out of a
    /// filtered copy while the save read the unfiltered one, so a list archived or completed while
    /// the sheet was open made the tile read "Inbox" and the task land in that list (T-318). The
    /// picker below still offers only active lists — `CadenceTaskComposerSupport.pickable*` —
    /// because what may be newly *chosen* is a different question from what a selection *names*.
    let areas: [Area]
    let projects: [Project]
    let availableSections: [String]
    let allTags: [Tag]
    /// Setting the priority explicitly also has to take any `!` marker out of the title, or the
    /// marker would silently overrule the choice at creation.
    let onPickPriority: (TaskPriority) -> Void

    @State private var showContainerPicker = false
    @State private var showSectionPicker = false
    @State private var showPriorityPicker = false
    @State private var showTagPicker = false

    var body: some View {
        VStack(spacing: CadenceTaskComposerLayout.tileSpacing) {
            HStack(spacing: CadenceTaskComposerLayout.tileSpacing) {
                doTile
                dueTile
            }

            HStack(spacing: CadenceTaskComposerLayout.tileSpacing) {
                listTile
                priorityTile
            }

            // The last row is the one that flexes: Section takes the half Tags would otherwise have
            // spread across, so the two rows above never move and the sheet is the same height
            // either way. See `CadenceTaskComposerLayout.tileCount(showsSectionTile:)`.
            HStack(spacing: CadenceTaskComposerLayout.tileSpacing) {
                if showsSectionTile {
                    sectionTile
                }
                tagsTile
            }
        }
    }

    // MARK: Dates

    private var doTile: some View {
        iOSTaskComposerDateTile(
            caption: "Do",
            systemImage: "sun.max.fill",
            dateKey: $fields.doDateKey
        )
    }

    private var dueTile: some View {
        iOSTaskComposerDateTile(
            caption: "Due",
            systemImage: "flag.fill",
            dateKey: $fields.dueDateKey
        )
    }

    // MARK: List and section

    /// The list's own colour is what tells two lists apart at a glance, so the glyph carries it —
    /// one of the two fields (with priority) whose *value* is a colour the user already reads as
    /// one. Everything else on the sheet stays `Theme.dim`.
    private var listTile: some View {
        tileButton {
            showContainerPicker = true
        } tile: {
            CadenceValueTile(
                caption: "List",
                value: containerTitle,
                systemImage: containerIcon,
                glyphColor: containerColor,
                // Inbox is the absence of a list, so it reads as unset even though it is a real
                // destination — the same treatment the inspector's breadcrumb gives it.
                valueColor: isInbox ? Theme.dim : Theme.text
            )
        }
        .popover(isPresented: $showContainerPicker) {
            iOSContainerChoicePopover(
                areas: areas,
                projects: projects,
                selection: containerToken,
                isPresented: $showContainerPicker
            )
        }
    }

    private var sectionTile: some View {
        tileButton {
            showSectionPicker = true
        } tile: {
            CadenceValueTile(
                caption: "Section",
                // The real name of where the task will go, never "None": dimmer styling is what
                // conveys "unset", so the tile and its picker cannot disagree.
                value: CadenceTaskInspectorSupport.sectionSegmentTitle(fields.sectionName),
                systemImage: "rectangle.split.3x1.fill"
            )
        }
        .popover(isPresented: $showSectionPicker) {
            iOSChoicePopoverList(
                rows: availableSections.map { iOSChoiceRow(value: $0, title: $0, color: Theme.dim) },
                selection: $fields.sectionName,
                isPresented: $showSectionPicker
            )
        }
    }

    // MARK: Priority and tags

    private var priorityTile: some View {
        tileButton {
            showPriorityPicker = true
        } tile: {
            CadenceValueTile(
                caption: "Priority",
                value: CadenceTaskComposerSupport.priorityValueLabel(resolvedPriority),
                systemImage: "exclamationmark.circle.fill",
                glyphColor: resolvedPriority == .none ? Theme.dim : Theme.priorityColor(resolvedPriority),
                valueColor: resolvedPriority == .none ? Theme.dim : Theme.priorityColor(resolvedPriority)
            )
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

    private var tagsTile: some View {
        tileButton {
            showTagPicker = true
        } tile: {
            CadenceValueTile(
                caption: "Tags",
                // Full width, so it can spell two names before counting is the better answer.
                value: CadenceTaskComposerSupport.tagsValueLabel(
                    names: selectedTags.map { $0.name.isEmpty ? $0.slug : $0.name },
                    limit: 2
                ),
                systemImage: "number",
                valueColor: selectedTags.isEmpty ? Theme.dim : Theme.text
            )
        }
        .popover(isPresented: $showTagPicker) {
            iOSTaskTagPickerPopover(
                selectedTags: $selectedTags,
                allTags: allTags,
                newTagName: $newTagName
            )
        }
    }

    // MARK: - Chrome

    /// One `Button` wrapper for every tile, so the press feedback and the hit area are decided once.
    /// `CadenceValueTile` deliberately draws no button of its own — it is shared with macOS, which
    /// has no `.iosPressable`.
    private func tileButton<Tile: View>(
        action: @escaping () -> Void,
        @ViewBuilder tile: () -> Tile
    ) -> some View {
        Button(action: action, label: tile)
            .buttonStyle(.iosPressable)
    }

    // MARK: - Derived state

    private var containerToken: Binding<String> {
        Binding(
            get: { CadenceTaskComposerSupport.token(for: fields.container) },
            set: { fields.container = CadenceTaskComposerSupport.selection(fromToken: $0) }
        )
    }

    /// The list the selection names, resolved **once** and read by the tile's name, glyph and
    /// colour alike, out of the same arrays the sheet saves through.
    private var resolvedContainer: GoalLinkTarget? {
        CadenceTaskComposerSupport.resolvedContainer(
            for: fields.container,
            areas: areas,
            projects: projects
        )
    }

    private var containerTitle: String {
        CadenceTaskComposerSupport.containerName(
            for: fields.container,
            areas: areas,
            projects: projects
        )
    }

    private var containerIcon: String {
        switch resolvedContainer {
        case .project: return "checklist"
        case .area, .none: return "tray.full.fill"
        }
    }

    private var containerColor: Color {
        guard let resolvedContainer else { return Theme.dim }
        return Color(hex: resolvedContainer.colorHex)
    }

    /// Whether the tile is naming a list at all. A selection whose list has gone reads as unset
    /// here for the same reason it reads "Inbox" above: that is where the task would go.
    private var isInbox: Bool {
        resolvedContainer == nil
    }

    private var showsSectionTile: Bool {
        CadenceTaskComposerSupport.showsSectionRow(
            container: fields.container,
            availableSections: availableSections
        )
    }

    private var resolvedPriority: TaskPriority {
        CadenceTaskComposerSupport.resolvedPriority(title: titleText, selected: fields.priority)
    }
}

/// A Do or Due tile and the date popover it opens.
///
/// Its own struct because the popover needs a `viewMonth` of its own, and two date tiles sharing one
/// would open the second on the month the first was left scrolled to.
///
/// The picker is `CadenceQuickDatePopover` — the same one the task inspector's date rows and macOS's
/// `CadenceDatePicker` open, Today / Tomorrow / This Weekend pills, month grid and Clear included.
/// That is where the do date's old one-tap Today and Tomorrow buttons went: they cost a tap each now
/// and they gave the do date a control twice the height of every other field's, on the sheet whose
/// height was the problem.
private struct iOSTaskComposerDateTile: View {
    let caption: String
    let systemImage: String
    @Binding var dateKey: String

    @State private var isOpen = false
    @State private var viewMonth = Date()

    private var pickedDate: Date {
        DateFormatters.date(from: dateKey) ?? Date()
    }

    var body: some View {
        Button {
            viewMonth = monthStart(of: pickedDate)
            isOpen = true
        } label: {
            CadenceValueTile(
                caption: caption,
                value: CadenceTaskComposerSupport.dateValueLabel(dateKey),
                systemImage: systemImage,
                valueColor: dateKey.isEmpty ? Theme.dim : Theme.text
            )
        }
        .buttonStyle(.iosPressable)
        .popover(isPresented: $isOpen) {
            CadenceQuickDatePopover(
                selection: Binding(
                    get: { pickedDate },
                    set: { dateKey = DateFormatters.dateKey(from: $0) }
                ),
                viewMonth: $viewMonth,
                isOpen: $isOpen,
                showsClear: !dateKey.isEmpty,
                onClear: { dateKey = "" }
            )
            .background(Theme.surfaceElevated)
            // Stays an anchored overlay on iPhone instead of being promoted into a full-height
            // sheet, which would take the keyboard down with it.
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
    /// Every list. A suggestion strip is a picker, so it narrows to the active ones itself through
    /// `CadenceTaskComposerSupport.pickable*` — the sheet hands every control the same two arrays
    /// rather than a differently-filtered copy each (T-318).
    let areas: [Area]
    let projects: [Project]
    let allTags: [Tag]
    let onPickContainer: (TaskContainerSelection) -> Void
    let onPickTag: (Tag) -> Void
    let onCreateTag: (String) -> Void

    private var trimmedQuery: String {
        shortcut.query.trimmingCharacters(in: .whitespaces)
    }

    private var matchingAreas: [Area] {
        CadenceTaskComposerSupport.pickableAreas(areas)
            .filter { CadenceTaskComposerSupport.matchesQuery($0.name, query: shortcut.query) }
    }

    private var matchingProjects: [Project] {
        CadenceTaskComposerSupport.pickableProjects(projects)
            .filter { CadenceTaskComposerSupport.matchesQuery($0.name, query: shortcut.query) }
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
                title: area.name.isEmpty ? CadenceTitleNormalization.defaultAreaName : area.name,
                systemImage: "tray.full.fill",
                tint: Color(hex: area.colorHex)
            ) {
                onPickContainer(.area(area.id))
            }
        }

        ForEach(matchingProjects) { project in
            suggestion(
                title: project.name.isEmpty ? CadenceTitleNormalization.defaultProjectName : project.name,
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
