#if os(macOS)
import SwiftUI

/// Pure filtering and ordering behind the container picker. Split out from the view so the
/// prefix match, the context grouping, and the flat order the arrow keys walk can be exercised
/// without SwiftUI.
enum ContainerPickerFilterSupport {

    /// A context heading and the rows drawn under it.
    ///
    /// **`contextID == nil` is the catch-all heading, and it is why this is a struct rather than
    /// the tuple it used to be (T-534).** The grouping is a `contexts.compactMap`, so a list that
    /// belongs to no context was reached by no iteration and drawn under no heading — not hidden,
    /// *absent*, with no row to file a task into and no row naming where a task already filed there
    /// is. `Area.context` and `Project.context` both default to `nil` and iOS's list editor offers a
    /// "None" context row in every mode, so that list is one a shipping surface makes.
    ///
    /// The bucket is keyed on the **offered** contexts rather than on `context == nil`, so a list
    /// whose context exists but was not handed to the picker lands in the same place. That is the
    /// rule `CadenceSidebarLists.sections` already applies to these two models on the iPad sidebar,
    /// and both the heading's wording and the membership test itself are read from there rather
    /// than respelled — `CadenceSidebarLists.isOffered`, which T-558 made shared after the fifth
    /// surface was filed for asking the question its own way.
    struct Group: Identifiable {
        let contextID: UUID?
        let title: String
        /// `nil` on the catch-all, which has no context and so no colour of its own.
        let colorHex: String?
        let areas: [Area]
        let projects: [Project]

        var id: String { contextID?.uuidString ?? CadenceSidebarLists.Section.ungroupedID }

        /// The context's own colour, or the quiet neutral the catch-all takes — the pairing
        /// `CadencePickerItem.tint` makes for a row with no colour of its own.
        var tint: Color { colorHex.map(Color.init(hex:)) ?? Theme.dim }
    }

    /// Forwards to the shared rule so the `~` suggestions in the iOS composer and this picker
    /// cannot disagree about what `des` matches.
    static func matches(_ name: String, query: String) -> Bool {
        CadenceTaskComposerSupport.matchesQuery(name, query: query)
    }

    static func matchesInbox(query: String) -> Bool {
        matches("Inbox", query: query)
    }

    /// What a row is titled — and so what the search matches. A blank-named list reads
    /// "Untitled Area" / "Untitled Project", as the badge that opened the picker
    /// (`CadenceTaskComposerSupport.containerName`), the sidebar and Cmd+K ([[T-7202]]) and the
    /// Kanban list board ([[T-8064]]) already say; before [[T-8102]] the row was a bare glyph.
    static func rowName(for area: Area) -> String {
        CadenceTitleNormalization.display(area.name, fallback: CadenceTitleNormalization.defaultAreaName)
    }

    static func rowName(for project: Project) -> String {
        CadenceTitleNormalization.display(project.name, fallback: CadenceTitleNormalization.defaultProjectName)
    }

    /// A blank-named context's heading reads "Untitled Context" rather than an empty eyebrow
    /// ([[T-8102]]).
    static func headingTitle(for context: Context) -> String {
        CadenceTitleNormalization.display(context.name, fallback: CadenceTitleNormalization.defaultContextName)
    }

    /// The rows the picker offers, grouped by context.
    ///
    /// **`selection` is the whole of T-534.** "Which lists may I offer" is a rule about *fresh*
    /// choices, and the list a task is already in is not a fresh choice — so filtering on
    /// `isActive` alone gave a task in an archived or completed list a popover with no row for
    /// where it is, and the one correction the user needed was the one the control would not draw.
    /// The rule that fixes it is `CadencePickerSupport.selectable(_:selectedID:)`: hide what you
    /// could newly pick, never the one already assigned. A picker that is never told the
    /// assignment cannot apply it, which is why the parameter is the work and the filter change
    /// follows from it. Reached here through the same `pickableAreas` / `pickableProjects` pair
    /// T-514 gave the iOS three-way control, so the two platforms cannot drift.
    ///
    /// Membership is `context?.id`, matching `CadenceSidebarLists`' bridge and deliberately not
    /// `Project.resolvedContext` — that answers which context a *task* inherits, not where a list
    /// is filed.
    static func groups(
        contexts: [Context],
        areas: [Area],
        projects: [Project],
        selection: TaskContainerSelection,
        query: String
    ) -> [Group] {
        let offerableAreas = CadenceTaskComposerSupport
            .pickableAreas(areas, selectedID: CadenceTaskComposerSupport.selectedAreaID(selection))
            .filter { matches(rowName(for: $0), query: query) }
        let offerableProjects = CadenceTaskComposerSupport
            .pickableProjects(projects, selectedID: CadenceTaskComposerSupport.selectedProjectID(selection))
            .filter { matches(rowName(for: $0), query: query) }

        let offered = Set(contexts.map(\.id))
        var groups = contexts.compactMap { context -> Group? in
            let ownedAreas = offerableAreas.filter { $0.context?.id == context.id }
            let ownedProjects = offerableProjects.filter { $0.context?.id == context.id }
            guard !ownedAreas.isEmpty || !ownedProjects.isEmpty else { return nil }
            return Group(
                contextID: context.id,
                title: headingTitle(for: context),
                colorHex: context.colorHex,
                areas: ownedAreas,
                projects: ownedProjects
            )
        }

        let looseAreas = offerableAreas.filter { !CadenceSidebarLists.isOffered($0.context?.id, among: offered) }
        let looseProjects = offerableProjects.filter { !CadenceSidebarLists.isOffered($0.context?.id, among: offered) }
        if !looseAreas.isEmpty || !looseProjects.isEmpty {
            groups.append(
                Group(
                    contextID: nil,
                    title: CadenceSidebarLists.ungroupedTitle,
                    colorHex: nil,
                    areas: looseAreas,
                    projects: looseProjects
                )
            )
        }
        return groups
    }

    /// The flat order the arrow-key highlight walks. Must stay in the order the rows render.
    static func flatSelections(inGroups groups: [Group], includingInbox: Bool) -> [TaskContainerSelection] {
        var result: [TaskContainerSelection] = []
        if includingInbox { result.append(.inbox) }
        for group in groups {
            result.append(contentsOf: group.areas.map { .area($0.id) })
            result.append(contentsOf: group.projects.map { .project($0.id) })
        }
        return result
    }

    /// The row `highlightIdx` currently names, or `nil` when the query matches nothing.
    static func highlighted(at index: Int, in selections: [TaskContainerSelection]) -> TaskContainerSelection? {
        guard !selections.isEmpty else { return nil }
        return selections[TaskPickerHighlightSupport.clampedIndex(index, count: selections.count)]
    }

    /// The row the highlight opens on: the list the task is already in, so a Return straight after
    /// opening re-files it where it is rather than into the Inbox ([[T-8101]]). The first row when
    /// that list is not offered, which an empty query never leaves out (`groups` keeps the
    /// assigned list whatever its status).
    static func openingHighlightIndex(for selection: TaskContainerSelection, in selections: [TaskContainerSelection]) -> Int {
        selections.firstIndex(of: selection) ?? 0
    }
}

/// The searchable, context-grouped list picker. Every container control presents this same body;
/// only the *trigger* and what a selection writes to differ — `ContainerPickerBadge` writes
/// through its own binding, the kanban card's list chip goes through
/// `CadenceTaskMutationSupport.moveToContainer` — so the picker itself lives here once.
struct ContainerPickerPopoverContent: View {
    let contexts: [Context]
    let areas: [Area]
    let projects: [Project]
    /// Where the task being filed already is.
    ///
    /// **It draws the checkmark, and the highlight opens on it ([[T-8101]]).** The checkmark used
    /// to track the keyboard highlight, which always opened on Inbox: a task in "Work" opened onto
    /// "checkmark Inbox", and one Return moved it there. Now the mark names the list the task is in,
    /// as the row menu's Move to List does, and the highlight is a fill only. It also lets the list
    /// narrow without dropping the row that names where the task is *now*; see
    /// `ContainerPickerFilterSupport.groups`. Composers pass the container their draft is holding,
    /// which is the same question asked before the task exists.
    let selection: TaskContainerSelection
    /// Selecting a row does not dismiss on its own: the presenting surface owns its
    /// `isPresented` state and closes as part of writing the selection.
    let onSelect: (TaskContainerSelection) -> Void

    @State private var searchQuery = ""
    @State private var highlightIdx = 0
    @FocusState private var isSearchFocused: Bool

    private var groups: [ContainerPickerFilterSupport.Group] {
        ContainerPickerFilterSupport.groups(
            contexts: contexts,
            areas: areas,
            projects: projects,
            selection: selection,
            query: searchQuery
        )
    }

    private var showsInbox: Bool {
        ContainerPickerFilterSupport.matchesInbox(query: searchQuery)
    }

    private var flatFiltered: [TaskContainerSelection] {
        ContainerPickerFilterSupport.flatSelections(inGroups: groups, includingInbox: showsInbox)
    }

    private var highlighted: TaskContainerSelection? {
        ContainerPickerFilterSupport.highlighted(at: highlightIdx, in: flatFiltered)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchBar

            Divider().background(Theme.borderSubtle)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if showsInbox {
                        ContainerPickerRow(
                            icon: CadenceListKindIcon.inbox,
                            name: "Inbox",
                            color: Theme.dim,
                            isHighlighted: highlighted == .inbox,
                            isSelected: selection == .inbox,
                            action: { onSelect(.inbox) }
                        )
                    }

                    if !groups.isEmpty {
                        Divider().background(Theme.borderSubtle).padding(.vertical, 2)

                        ForEach(groups) { group in
                            SectionEyebrowLabel(
                                text: group.title,
                                size: .compact,
                                tint: group.tint
                            )
                                .padding(.horizontal, 12)
                                .padding(.top, 6)
                                .padding(.bottom, 2)

                            ForEach(group.areas) { area in
                                ContainerPickerRow(
                                    icon: CadenceListKindIcon.area,
                                    name: ContainerPickerFilterSupport.rowName(for: area),
                                    color: Color(hex: area.colorHex),
                                    isHighlighted: highlighted == .area(area.id),
                                    isSelected: selection == .area(area.id),
                                    action: { onSelect(.area(area.id)) }
                                )
                            }

                            ForEach(group.projects) { project in
                                ContainerPickerRow(
                                    icon: CadenceListKindIcon.project,
                                    name: ContainerPickerFilterSupport.rowName(for: project),
                                    color: Color(hex: project.colorHex),
                                    isHighlighted: highlighted == .project(project.id),
                                    isSelected: selection == .project(project.id),
                                    action: { onSelect(.project(project.id)) }
                                )
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 320)
        }
        .frame(minWidth: 190)
        .background(Theme.surfaceElevated)
        .onAppear {
            // This is also the reset-on-close: popover content is rebuilt per presentation, so
            // clearing here guarantees every open starts on the task's own list with an empty
            // query regardless of what the previous session left behind ([[T-8101]]).
            searchQuery = ""
            highlightIdx = ContainerPickerFilterSupport.openingHighlightIndex(
                for: selection,
                in: ContainerPickerFilterSupport.flatSelections(
                    inGroups: ContainerPickerFilterSupport.groups(
                        contexts: contexts, areas: areas, projects: projects, selection: selection, query: ""
                    ),
                    includingInbox: true
                )
            )
            DispatchQueue.main.async { isSearchFocused = true }
        }
        .onChange(of: searchQuery) { _, _ in
            highlightIdx = 0
        }
    }

    private var searchBar: some View {
        CadenceSearchFieldRow(query: $searchQuery, focus: $isSearchFocused) {
            TextField("Search", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
                .focused($isSearchFocused)
                .onSubmit {
                    if let highlighted { onSelect(highlighted) }
                }
                .onKeyPress(.upArrow) {
                    highlightIdx = TaskPickerHighlightSupport.clampedMovedIndex(highlightIdx, by: -1, count: flatFiltered.count)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    highlightIdx = TaskPickerHighlightSupport.clampedMovedIndex(highlightIdx, by: 1, count: flatFiltered.count)
                    return .handled
                }
        }
    }
}

/// A dedicated struct rather than a `@ViewBuilder` function so a highlight change updates the
/// affected rows in place. The checkmark marks `isSelected` — the list the task is in — and the
/// keyboard cursor is the fill alone ([[T-8101]]).
private struct ContainerPickerRow: View {
    let icon: String
    let name: String
    let color: Color
    let isHighlighted: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 12)).foregroundStyle(color).frame(width: 16)
                Text(name).font(.system(size: 13)).foregroundStyle(Theme.text).lineLimit(1)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.blue)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(isHighlighted ? Theme.blue.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: CadenceMenuRowButtonStyle.cornerRadius))
        }
        // [[T-9944]]: the row style is the one hover plate, as [[T-9465]] made it for the ~ panel's
        // rows. This row drew `.cadencePlain`'s blue wash AND stroke over its own `isHovered` fill,
        // so a pointer lit two layers and a hovered row outlined itself where no other picker row does.
        .buttonStyle(.cadenceMenuRow)
    }
}
#endif
