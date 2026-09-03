#if os(iOS)
import SwiftData
import SwiftUI

/// A 1pt palette hairline.
///
/// `Divider().background(Theme.borderSubtle)` — which every surface in this file used to draw —
/// does **not** recolour the divider on iOS: it paints the palette colour *behind* a translucent
/// UIKit separator, so what actually shipped was a system grey line with a Theme colour hidden
/// underneath. This is the same `Rectangle().fill(Theme.borderSubtle).frame(height: 1)` macOS's
/// `SidebarSectionDivider` draws.
struct iOSListHairline: View {
    var body: some View {
        Rectangle()
            .fill(Theme.borderSubtle)
            .frame(maxWidth: .infinity)
            .frame(height: 1)
    }
}

/// Section eyebrow for the Lists page's `List`. `Section("Areas")` renders UIKit's own header —
/// system grey small-caps sitting on a system plate — which is a second, non-palette surface on
/// top of the page background. This is the shared `SectionEyebrowLabel` instead.
struct iOSListSectionHeader: View {
    let title: String

    var body: some View {
        SectionEyebrowLabel(text: title)
            .padding(.top, 14)
            .padding(.bottom, 6)
            .textCase(nil)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

extension View {
    /// One row treatment for the Lists page: no plate of its own so the page background shows
    /// through, a palette separator instead of the UIKit one, and insets that line every row's
    /// icon tile up with the page header's.
    func iOSListRowChrome() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparatorTint(Theme.borderSubtle)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }
}

/// The Lists row swipe tray, as values — the same shape `iOSTaskRowSwipeActions` takes, drawn by
/// the same `iOSSwipeActionsModifier`.
///
/// It exists because a list row swiped on iPhone and did nothing on iPad: the compact rows carried
/// `.swipeActions`, which is a `List`-row modifier, and the iPad pane renders its rows in a
/// `ScrollView`, where SwiftUI discards it without a word. That is the same defect, and the same
/// fix, the task rows already went through — see the note above `iOSTaskRow`'s `.iOSSwipeActions`.
enum iOSListRowSwipeActions {
    /// `isDestructive` is not a claim that archiving destroys anything — an archived list is one
    /// tap from Restore in the Archived section. It is what withholds the action from a *full*
    /// swipe, which is what `allowsFullSwipe: false` did on the compact rows: filing a list away
    /// should take the deliberate tap, not a flick.
    static func archive(_ perform: @escaping () -> Void) -> [CadenceSwipeAction] {
        [
            CadenceSwipeAction(
                id: "archive-list",
                title: "Archive",
                systemImage: "archivebox",
                tint: Theme.red,
                isDestructive: true,
                perform: perform
            )
        ]
    }
}

/// Trailing count on a list row, in `SidebarNavCountBadge`'s vocabulary: neutral capsule, neutral
/// digits, fixed size so three digits are never squeezed by a long list name. It is deliberately
/// *not* tinted — the row's identity colour is the icon badge, and a second coloured element per
/// row turns a page of lists into a page of colours.
struct iOSListCountBadge: View {
    let count: Int

    var body: some View {
        Text(count > 999 ? "999+" : "\(count)")
            .font(.system(size: 11, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(Theme.muted)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .frame(minWidth: 24, minHeight: 20)
            .background(Capsule(style: .continuous).fill(Theme.borderSubtle))
            .accessibilityHidden(true)
    }
}

/// The identity tile a list row leads with: the list's own `colorHex` on the glyph over a wash of
/// itself. Delegates to `iOSIconTile` — the shared iOS counterpart of `ListEditorIdentityTile` —
/// rather than re-spelling a rounded square, so a list looks the same wherever it is listed.
struct iOSListIconBadge: View {
    let icon: String
    let colorHex: String
    var size: CGFloat = 34
    var isMuted = false

    var body: some View {
        iOSIconTile(
            systemImage: icon,
            color: Color(hex: colorHex).opacity(isMuted ? 0.55 : 1),
            size: size,
            iconSize: size * 0.44,
            fillOpacity: isMuted ? 0.09 : 0.14
        )
    }
}

/// Page-level header for the Lists page. Used identically by both the compact (iPhone) and
/// regular (iPad) Lists layouts so the two look like the same page rather than a shrunk/expanded
/// variant of each other.
struct iOSListsPageHeader: View {
    let areaCount: Int
    let projectCount: Int
    /// Set on iPhone, where this page is pushed with its navigation bar hidden. See
    /// `iOSHidesCompactNavigationBar()`.
    var onBack: (() -> Void)? = nil

    private var totalCount: Int {
        areaCount + projectCount
    }

    var body: some View {
        // `iOSPageHeader` down to the folder tile and the count, which is what this always was —
        // it had simply spelled the tile as `iOSListIconBadge`, the eyebrow through
        // `SectionEyebrowLabel`, and the count as the neutral `iOSListCountBadge` while the other
        // five headers counted in blue.
        //
        // `onBack` is the tell, exactly as in `iOSFeatureListPane`: set, this is the top of a pushed
        // screen; unset, it is the chooser column of the regular-width Lists split, which speaks at
        // the same volume as the Goals and Habits choosers beside it rather than shouting over the
        // detail it is choosing for.
        iOSPageHeader(
            role: onBack == nil ? .pane : .page,
            eyebrow: CadenceListsSummary.eyebrow(areaCount: areaCount, projectCount: projectCount),
            title: "Lists",
            color: Theme.blue,
            count: totalCount > 0 ? totalCount : nil,
            onBack: onBack
        )
    }
}

/// Shared "New Area / New Project" action row for the Lists page. Used by both the
/// compact and regular layouts so list creation doesn't rely on a native nav-bar
/// toolbar menu (which disappears once the plain nav bar is hidden in favor of
/// `iOSListsPageHeader`).
///
/// These were two full-width `.borderedProminent` slabs, one blue and one green — the loudest
/// thing on a page whose subject is the user's own list colours. They are the same neutral chip
/// the task view-options bar uses now; the type still carries its colour, on the glyph only.
struct iOSListCreateButtonsRow: View {
    @Binding var editorMode: iOSListEditorMode?

    var body: some View {
        HStack(spacing: 8) {
            iOSActionButton(
                title: "New Area",
                systemImage: "folder.badge.plus",
                role: .secondary,
                size: .compact,
                tint: Theme.blue,
                fullWidth: true
            ) {
                editorMode = .newArea
            }

            iOSActionButton(
                title: "New Project",
                systemImage: "checklist",
                role: .secondary,
                size: .compact,
                tint: Theme.green,
                fullWidth: true
            ) {
                editorMode = .newProject
            }
        }
    }
}

/// The list-detail tab bar, in the vocabulary `CadenceQuietTabButton` established on macOS: text
/// only, exactly one neutral fill layer at one radius, state carried by fill depth and label
/// weight instead of an accent wash. Sized to a 44pt touch target.
///
/// `.plain` rather than `.cadencePlain` on purpose — that style paints its own fill and stroke,
/// which would stack a second selection layer on top of this one.
struct iOSListDetailPagePicker: View {
    @Binding var page: ListDetailPage
    /// How many items each tab holds, for the tabs where a total means something. Each tab used
    /// to draw its own header carrying this number; removing those headers — the tab bar already
    /// names the tab — took the counts with them, and the count was not the redundant half.
    var counts: [ListDetailPage: Int] = [:]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 2) {
                ForEach(ListDetailPage.allCases) { item in
                    let isSelected = page == item
                    Button {
                        page = item
                    } label: {
                        HStack(spacing: 6) {
                            Text(item.rawValue)
                                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                                // `muted`, not `dim`: an unselected tab is a label you read and
                                // tap, and `dim` on this surface sits under the AA floor at 13pt.
                                .foregroundStyle(isSelected ? Theme.text : Theme.muted)
                                .lineLimit(1)

                            if let count = counts[item], count > 0 {
                                Text("\(count)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(isSelected ? Theme.muted : Theme.dim)
                            }
                        }
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                                    .fill(isSelected ? Theme.surfaceHighlight : Color.clear)
                            )
                            .contentShape(
                                RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.rawValue)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 1)
        }
        .scrollIndicators(.hidden)
        // A page carrying the floating `+` sets
        // `contentMargins(.bottom, iOSCircularAddButton.scrollClearance, for: .scrollContent)` — 100pt —
        // once, for its own bottom-reaching list. `contentMargins` is **inherited through the
        // environment**, so it lands on every scroll view underneath, including this tab strip. This
        // one is a single 44pt row, so the inherited 100pt becomes 100pt of empty content region
        // *below* the tabs — the strip grows to 144pt and every tab on the page appears to start a
        // touch target and a half lower. The band reads as the page's, which is why it looked like
        // five separate bugs: it is above `pageBody`, so it is in front of Tasks, Kanban, Notes,
        // Links and Completed alike. Compact width was never affected — the host sets 0 there,
        // because the tab bar's centre `+` is the capture affordance and no page floats one.
        //
        // Reset here rather than at the host, for the same reason the markdown accessory strips do
        // it: a short single-row horizontal scroll view is never the page's bottom-reaching content,
        // so it should never inherit the page's clearance for the button. This is the third instance
        // of `D-104` — see `iOSMarkdownAccessoryViews.swift` — and putting the reset on the strip is
        // what makes it true for the next host as well as this one.
        .contentMargins(.vertical, 0, for: .scrollContent)
    }
}

struct iOSListPickerRow: View {
    let title: String
    let subtitle: String?
    let icon: String
    let colorHex: String
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            iOSListIconBadge(icon: icon, colorHex: colorHex)

            VStack(alignment: .leading, spacing: 3) {
                Text(TaskTitleSupport.displayTitle(title, fallback: TaskTitleSupport.defaultCompactDisplayTitle))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.subdued)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            iOSListCountBadge(count: count)
        }
        .frame(minHeight: 44)
    }
}

struct iOSArchivedListRow: View {
    let title: String
    let subtitle: String?
    let icon: String
    let colorHex: String
    let restore: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            iOSListIconBadge(icon: icon, colorHex: colorHex, isMuted: true)

            VStack(alignment: .leading, spacing: 3) {
                Text(TaskTitleSupport.displayTitle(title, fallback: TaskTitleSupport.defaultCompactDisplayTitle))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            iOSActionButton(
                title: "Restore",
                role: .secondary,
                size: .compact,
                action: restore
            )
        }
        .frame(minHeight: 44)
    }
}

/// No panel header on any of the list-detail tabs. The tab bar sits directly above them and
/// already names the tab; a second "COMPLETED / Completed" block 40pt underneath it was the page
/// describing the page you are already on.
struct iOSListCompletedPanel: View {
    let tasks: [AppTask]

    var body: some View {
        Group {
            if tasks.isEmpty {
                iOSEmptyPanel(
                    systemImage: "checkmark.circle",
                    title: CadenceEmptyStateCopy.completedTasksTitle,
                    subtitle: CadenceEmptyStateCopy.completedTasksSubtitle
                )
            } else {
                List {
                    ForEach(tasks) { task in
                        // Scoped to one list already — see `iOSTaskRow.showsContainer`.
                        iOSTaskListRow(task: task, opacity: 0.62, showsContainer: false)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }
}

/// The list's kanban board, in the vocabulary the three macOS boards share
/// (`CadenceBoardColumnHeader` / `KanbanColumnScroll` / `KanbanCard`): a containerless column — no fill,
/// no stroke — opened by a section-coloured dot, an uppercase name, a count and a closing
/// hairline, with `iOSBoardTaskCard`s under it — the same card the Calendar Board's day columns
/// use, at the same width.
///
/// Each column used to be a plate tinted with the **list's** colour, so a six-column board was
/// six identical washes and the per-column colour the list editor stores had nowhere to show. The
/// dot is where that colour lives now, exactly as on macOS.
struct iOSListKanbanPanel: View {
    let tasks: [AppTask]
    let sectionNames: [String]
    /// Colour/completion for the named columns. Names that only exist on a task (a section a list
    /// no longer configures) have no config and fall back to the list's own colour.
    let sectionConfigs: [TaskSectionConfig]
    /// The list's `hideSectionDueDateIfEmpty`. Wired for the same reason the due-date line itself
    /// is (T-331): the flag was already in the model and already editable on macOS, so an iOS board
    /// that ignored it would have shown "No due date" under every column of a list whose owner had
    /// asked for exactly the opposite — and there would have been no iOS control to ask with.
    let hideSectionDueDateIfEmpty: Bool
    let accent: Color
    /// Which list this board belongs to, and what it is called — the two things a column header
    /// needs to seed a dropped `+`, and neither of which a *column* knows. See
    /// `CadenceTaskDropSupport.groupIdentity(container:listName:sectionName:)`.
    let container: TaskContainerSelection
    let listName: String
    /// A column to bring into view and briefly ring on arrival. Today's past-due **section** card
    /// is the only caller so far — it names a column, and a board that opened at the far left would
    /// have answered a different question than the card asked.
    var highlightedSectionName: String?

    /// Which column the ring is currently on. Separate from `highlightedSectionName` because the
    /// request outlives the emphasis: the ring fades after a beat and the request is still the
    /// reason this board is on screen, so clearing one must not clear the other.
    @State private var activeHighlightName: String?

    /// **Every configured column, filled or not.** An unfilled column is the case the drop rule
    /// exists for, and it was the one case that could not happen here: `sectionGroups` discarded
    /// the column before anything could offer it. The board's own empty state below still stands in
    /// when the *list* has nothing in it, rather than a row of zeroes.
    private var columns: [CadenceTaskDisplayGroup] {
        CadenceTaskQuerySupport.sectionGroups(
            from: tasks,
            sectionNames: sectionNames,
            includingEmpty: true
        )
    }

    var body: some View {
        Group {
            if tasks.isEmpty {
                iOSEmptyPanel(
                    systemImage: "square.grid.3x2",
                    title: "No kanban cards",
                    subtitle: "Tasks grouped by section will appear here."
                )
                // The list itself, for the same reason the Tasks tab's empty state takes it: with
                // no columns drawn there is nothing narrower to point at.
                .iOSNewTaskDropTarget(
                    group: CadenceTaskDropSupport.groupIdentity(
                        container: container,
                        listName: listName
                    )
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 14) {
                            ForEach(columns) { column in
                                iOSListKanbanColumn(
                                    title: column.title,
                                    dotColor: dotColor(for: column.title),
                                    dueDatePlan: dueDatePlan(for: column.title),
                                    tasks: column.tasks,
                                    isHighlighted: isHighlighted(column.title),
                                    dropIdentity: CadenceTaskDropSupport.groupIdentity(
                                        container: container,
                                        listName: listName,
                                        sectionName: column.title
                                    )
                                )
                                .id(column.title)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 16)
                        .frame(maxHeight: .infinity, alignment: .top)
                    }
                    .scrollIndicators(.hidden)
                    // Both arrival routes, for the same reason `iOSFocusView` covers both: this
                    // board is built fresh when the sheet opens (`onAppear`), and is *updated*
                    // rather than rebuilt when the page it is on is already standing.
                    .onAppear { applyHighlightIfNeeded(with: proxy) }
                    .onChange(of: highlightedSectionName) { _, _ in
                        applyHighlightIfNeeded(with: proxy)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }

    private func isHighlighted(_ name: String) -> Bool {
        activeHighlightName?.caseInsensitiveCompare(name) == .orderedSame
    }

    /// Scroll to the named column and ring it, then let the ring go.
    ///
    /// The match is a **case-insensitive name** comparison, because that is the only handle there
    /// is: a section is a `TaskSectionConfig` value in `sectionConfigsRaw`, and a task points at one
    /// through `AppTask.sectionName` — a string. `columns` is keyed by the same names, including the
    /// ones that exist only on a task, so a column the list no longer configures is still reachable.
    ///
    /// The fade-out is deliberately not a `withAnimation` on the request itself: the request is the
    /// reason the board is open and outlives the emphasis.
    private func applyHighlightIfNeeded(with proxy: ScrollViewProxy) {
        guard let highlightedSectionName,
              let match = columns.first(where: {
                  $0.title.caseInsensitiveCompare(highlightedSectionName) == .orderedSame
              }) else {
            activeHighlightName = nil
            return
        }

        activeHighlightName = match.title
        withAnimation(.easeInOut(duration: 0.22)) {
            proxy.scrollTo(match.title, anchor: .center)
        }

        let ringedName = match.title
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard activeHighlightName?.caseInsensitiveCompare(ringedName) == .orderedSame else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                activeHighlightName = nil
            }
        }
    }

    private func dotColor(for name: String) -> Color {
        guard let config = config(for: name) else { return accent }
        return config.isCompleted ? Theme.green : Color(hex: config.colorHex)
    }

    /// A column the list no longer configures has no due date to show, but it still obeys the
    /// list's hide flag — otherwise the one column with no config would be the only one drawing
    /// "No due date" on a board that shows dates.
    private func dueDatePlan(for name: String) -> CadenceBoardColumnDueDatePlan {
        let config = config(for: name)
        return CadenceBoardColumnDueDatePlan.plan(
            dueDate: config?.dueDate ?? "",
            hideWhenEmpty: hideSectionDueDateIfEmpty,
            isCompleted: config?.isCompleted ?? false
        )
    }

    private func config(for name: String) -> TaskSectionConfig? {
        sectionConfigs.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}

private struct iOSListKanbanColumn: View {
    let title: String
    let dotColor: Color
    /// The metadata this column used to withhold from the shared header (T-331). The board draws
    /// the line; it does not edit it — a section's due date is set in the list editor on iOS, the
    /// way macOS sets it from the header popover.
    let dueDatePlan: CadenceBoardColumnDueDatePlan
    let tasks: [AppTask]
    /// Set for the one column a caller arrived here to look at. It is emphasis, not selection —
    /// nothing about the column behaves differently — so it draws a ring at the card radius and
    /// nothing else, and the panel takes it away after a beat.
    var isHighlighted = false
    /// See `iOSTaskGroupHeader.dropIdentity` — the header is the drop target here for the same
    /// reason, and reaches the same place a card cannot: a column with nothing in it.
    var dropIdentity: CadenceTaskGroupDropIdentity?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Both slots spelled out, and `trailing` empty: see the note beside the header's
            // convenience inits for why there is no detail-only shorthand to use here.
            CadenceBoardColumnHeader(
                dotColor: dotColor,
                title: title,
                count: tasks.count,
                trailing: { EmptyView() },
                detail: {
                    if dueDatePlan.isVisible {
                        CadenceBoardColumnDueDateLine(plan: dueDatePlan)
                            .padding(.leading, CadenceBoardColumnHeaderMetrics.detailLeadingInset)
                    }
                }
            )
            .iOSNewTaskDropTarget(group: dropIdentity)

            // The card stack scrolls inside the column, as `KanbanColumnScroll` does on macOS. The
            // board only scrolled horizontally before, so anything past the bottom of a tall column
            // was unreachable.
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(tasks) { task in
                        // Scoped to one list already — the same reason `iOSTaskListRow` drops its
                        // container, and the same knob macOS's `KanbanCard` uses.
                        iOSBoardTaskCard(task: task, showsContainerChip: false)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
        .frame(width: iOSBoardColumnWidth, alignment: .topLeading)
        // One layer at one radius. The ring is an overlay on the column itself rather than a second
        // background under the header, which is the stacked-hover shape the standing rule rules out.
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                .strokeBorder(isHighlighted ? dotColor : Color.clear, lineWidth: 2)
                .allowsHitTesting(false)
        }
    }
}

struct iOSListLinksPanel: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query(sort: \SavedLink.order) private var allLinks: [SavedLink]
    let area: Area?
    let project: Project?
    @State private var isAdding = false
    @State private var newTitle = ""
    @State private var newURL = ""
    /// What the store refused, in the same two sentences macOS's list shows. Before T-507 the two
    /// writes here were `try?` and this property did not exist, so a refused commit was reported
    /// by the form closing.
    @State private var actionError: String?

    private var links: [SavedLink] {
        if let area {
            return allLinks.filter { $0.area?.id == area.id }
        }
        if let project {
            return allLinks.filter { $0.project?.id == project.id }
        }
        return []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                iOSActionButton(
                    title: isAdding ? "Cancel" : "Add Link",
                    systemImage: isAdding ? "xmark" : "plus",
                    role: isAdding ? .ghost : .secondary,
                    size: .compact
                ) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isAdding.toggle()
                    }
                    actionError = nil
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if isAdding {
                iOSAddLinkForm(
                    title: $newTitle,
                    url: $newURL,
                    save: addLink
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }

            // Above the hairline rather than inside the add form: the delete reports here too, and
            // a swipe-to-delete happens with the form closed.
            if let actionError {
                Text(actionError)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }

            iOSListHairline()

            if links.isEmpty {
                iOSEmptyPanel(
                    systemImage: "link",
                    title: CadenceEmptyStateCopy.savedLinksTitle,
                    subtitle: CadenceEmptyStateCopy.savedLinksSubtitle
                )
            } else {
                List {
                    ForEach(links) { link in
                        Button {
                            open(link)
                        } label: {
                            iOSLinkRow(link: link)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(Theme.borderSubtle)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                delete(link)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.bg)
    }

    private func addLink() {
        let title = CadenceTitleNormalization.normalized(newTitle)
        // Trim, blank-check and scheme come from the shared helper. The three lines that used to
        // sit here were a copy of macOS's, defect included: `hasPrefix` is case-sensitive, so a
        // pasted `HTTPS://example.com` was stored as `https://HTTPS://example.com` (T-509).
        guard let url = CadenceSavedLinkURL.normalized(newURL) else { return }

        let link = SavedLink(title: CadenceTitleNormalization.display(title, fallback: url), url: url)
        link.area = area
        link.project = project
        link.order = (links.map(\.order).max() ?? -1) + 1
        // Same commit as macOS, through the one helper, so the two surfaces cannot drift on
        // whether a saved link is actually saved (T-327) — and, since T-507, on whether a refused
        // one is reported. The `try?` this replaces cleared both fields and closed the form over a
        // commit that had already rolled the link back out, so the user watched what they typed
        // disappear and was told it had worked.
        do {
            try CadenceSavedLinkPersistence.insert(link, in: modelContext)
        } catch {
            actionError = CadenceSavedLinkPersistence.saveFailureNotice
            return
        }
        actionError = nil
        newTitle = ""
        newURL = ""
        isAdding = false
    }

    private func open(_ link: SavedLink) {
        guard let url = URL(string: link.url) else { return }
        openURL(url)
    }

    /// The delete reports as well, even though `CadenceSaveCommitDisciplineTests`' report half
    /// could never have named it: nothing followed the swallow, so there was no dismissal for the
    /// scan to see. The helper rolls a refused delete back, which puts the row straight back into
    /// the list — so without a notice the swipe simply looked like it had not registered.
    private func delete(_ link: SavedLink) {
        do {
            try CadenceSavedLinkPersistence.delete(link, in: modelContext)
            actionError = nil
        } catch {
            actionError = CadenceSavedLinkPersistence.deleteFailureNotice
        }
    }
}

/// `.roundedBorder` and `.borderedProminent` are UIKit's own chrome: a grey system field and a
/// filled tint capsule, neither of which reads from the palette. These are the same fields and
/// the same primary action every other iOS surface draws.
private struct iOSAddLinkForm: View {
    @Binding var title: String
    @Binding var url: String
    let save: () -> Void

    private var isSaveDisabled: Bool {
        url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 9) {
            iOSLinkField(placeholder: "Title (optional)", text: $title)
                .textInputAutocapitalization(.words)

            iOSLinkField(placeholder: "URL", text: $url)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(save)

            iOSActionButton(
                title: "Save Link",
                systemImage: "checkmark",
                role: .primary,
                size: .compact,
                fullWidth: true,
                isDisabled: isSaveDisabled,
                action: save
            )
        }
    }
}

private struct iOSLinkField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(Theme.surfaceElevated.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
    }
}

private struct iOSLinkRow: View {
    let link: SavedLink

    var body: some View {
        HStack(spacing: 12) {
            iOSListIconBadge(icon: "link", colorHex: Theme.blueHex)

            VStack(alignment: .leading, spacing: 3) {
                Text(CadenceTitleNormalization.display(link.title, fallback: link.url))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)

                Text(link.url)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.subdued)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "arrow.up.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.dim)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}
#endif
