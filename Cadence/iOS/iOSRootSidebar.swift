#if os(iOS)
import SwiftData
import SwiftUI

struct iPadMacStyleRootShell<Content: View>: View {
    @Binding var selection: iOSSidebarItem?
    @ViewBuilder let detail: () -> Content

    /// Restored across launches, like `ios.calendar.anchorDateKey`.
    ///
    /// Written from **exactly two places**, both of them a tap on the fold control. Nothing
    /// derived, nothing measured, nothing written during layout — that is the lesson of `ecaf80f`,
    /// where a persisted navigation value took an initial scroll reading for a user action and then
    /// compounded across launches. A width read from a `GeometryReader` must never land here: the
    /// column is narrow at 744pt because the *window* is narrow, not because the user folded it.
    @AppStorage("ios.sidebar.collapsed") private var isSidebarCollapsed = false
    /// Owned by the shell rather than by the sidebar, so the editor is presented from a view that
    /// is always on screen. The sidebar goes to zero width and zero opacity when folded, and a
    /// sheet whose presenter has been hidden is a sheet nobody can see.
    @State private var listEditorMode: iOSListEditorMode?

    /// **The detail pane is hard-sized, and the row is pinned `.leading`.**
    ///
    /// Both halves of that matter, and neither used to be true. The detail was
    /// `.frame(maxWidth: .infinity)`, which sets no *minimum* — the minimum came from whatever the
    /// pane's own content declared, and an `HStack` handed a fixed sidebar plus a detail that will
    /// not go below 721pt does not shrink either one. It overflows. The row was then pinned into
    /// `.frame(width: proxy.size.width, height:)` at its **default centre alignment**, so half the
    /// overflow hung off the leading edge of the screen and the sidebar rendered as "KSPACE" and
    /// "GRESS". Nothing clipped the sidebar; the sidebar had been positioned off-screen by the
    /// Inbox's second column.
    ///
    /// `CadenceRootShellLayout` (in `Shared/`, with tests) is now the one place the split is
    /// decided, and it guarantees `sidebar + detail == window` — **folded or not**. Folding is a
    /// sidebar width of zero there, not a second layout path here. `.leading` is the belt to that
    /// braces: if some future pane still insists on more room than it is given, the excess leaves by
    /// the trailing edge — past content — rather than by the leading one, which is where the app's
    /// navigation lives.
    var body: some View {
        GeometryReader { proxy in
            let sidebarStyle = iOSSidebarStyle.style(for: proxy.size.width)
            let sidebarWidth = CadenceRootShellLayout.sidebarWidth(
                windowWidth: proxy.size.width,
                isCollapsed: isSidebarCollapsed
            )
            let detailWidth = CadenceRootShellLayout.detailWidth(
                windowWidth: proxy.size.width,
                isCollapsed: isSidebarCollapsed
            )

            HStack(spacing: 0) {
                iOSSidebar(
                    selection: $selection,
                    style: sidebarStyle,
                    onCreateList: { listEditorMode = $0 },
                    onCollapse: { setCollapsed(true) }
                )
                .frame(width: sidebarWidth)
                // `Theme.surface` against the detail pane's `Theme.bg`, closed by a full-weight
                // hairline — the same construction and the same reasoning as macOS's
                // `SidebarView`: on a near-black palette the tonal step alone does not separate
                // the column from the page, so the edge has to carry it. This used to paint
                // `surface` here and `bg` inside the sidebar, so the step never existed and the
                // edge was a half-point line at 58% of a subtle border.
                .background(Theme.surface)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(Theme.borderSubtle)
                        .frame(width: 1)
                }
                // Folded, the column is 0pt wide but still in the hierarchy, which is what lets the
                // width animate rather than jump. All three of these are stated rather than assumed:
                // a zero-width view still draws outside its bounds, still takes taps, and is still
                // read out by VoiceOver.
                .clipped()
                .opacity(isSidebarCollapsed ? 0 : 1)
                .allowsHitTesting(!isSidebarCollapsed)
                .accessibilityHidden(isSidebarCollapsed)
                .zIndex(1)

                detail()
                    .frame(width: detailWidth, height: proxy.size.height)
                    .background(Theme.bg)
                    .clipped()
                    // The way back. It floats over the detail because the fold is worth 188pt only
                    // if none of it is kept back for a stub column, and it sits at the vertical
                    // centre of the leading edge — clear of every page header, which is where the
                    // pages put their own titles and controls.
                    .overlay(alignment: .leading) {
                        if isSidebarCollapsed {
                            iOSSidebarExpandHandle { setCollapsed(false) }
                        }
                    }
                    .zIndex(0)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
        }
        .background(Theme.bg.ignoresSafeArea())
        .ignoresSafeArea(.container)
        .sheet(item: $listEditorMode) { mode in
            iOSListEditorSheet(mode: mode)
        }
    }

    private func setCollapsed(_ collapsed: Bool) {
        withAnimation(.easeInOut(duration: 0.22)) {
            isSidebarCollapsed = collapsed
        }
    }
}

/// The iPad shell's navigation column: app header, primary nav, the scrolling lists region,
/// secondary nav.
///
/// **Only the lists region scrolls.** Everything else is pinned, for the reason macOS's
/// `SidebarView` gives: navigation and lists share one column, and if the whole column scrolled a
/// long list collection would push Settings below the fold.
///
/// Group membership, ordering and the count rule live in `CadenceSidebarLayout`; which context owns
/// which list lives in `CadenceSidebarLists`. Both are in `Shared/` and both are what macOS reads,
/// so this file is a rendering of that layout rather than a second copy of it.
struct iOSSidebar: View {
    @Binding var selection: iOSSidebarItem?
    let style: iOSSidebarStyle
    let onCreateList: (iOSListEditorMode) -> Void
    let onCollapse: () -> Void

    @Query(sort: \Context.order) private var contexts: [Context]
    @Query private var allTasks: [AppTask]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    @Query private var habits: [Habit]
    @Query(filter: #Predicate<Goal> { $0.statusRaw == "active" }) private var activeGoals: [Goal]
    /// The same preference macOS's Settings → Sidebar colour picker writes. This column has no
    /// picker of its own, so in practice this is empty and every row falls back to its
    /// destination's default — but reading it is what makes the two columns one sidebar rather
    /// than two that happen to agree today.
    @AppStorage(CadencePreferenceKeys.sidebarTabColors) private var sidebarTabColorsRaw = CadencePreferenceKeys.emptySidebarPreference

    private var tintOverrides: [CadenceFeatureDestination: String] {
        CadenceSidebarTint.overrides(from: sidebarTabColorsRaw)
    }

    private func tint(for destination: CadenceFeatureDestination) -> Color {
        Color(hex: tintOverrides[destination] ?? destination.defaultColorHex)
    }

    /// The selection as the *rows* see it.
    ///
    /// Inbox has no row of its own — it is one of the two views inside the Tasks destination — so
    /// a `.inbox` selection has to light the Tasks row rather than lighting nothing.
    /// `CadenceSidebarLayout.navRow(for:)` is the rule, shared with `SidebarView`.
    private var rowSelection: iOSSidebarItem? {
        guard let selection else { return nil }
        guard let destination = CadenceFeatureDestination.allCases.first(where: { $0.item == selection })
        else { return selection }
        return CadenceSidebarLayout.navRow(for: destination).item
    }

    /// Built once per render and handed to every row, the same shape `SidebarView` uses. Each tally
    /// is one pass over the task list.
    ///
    /// All Tasks counts only work inside still-active areas/projects, the scope its page uses.
    /// Today's overdue tally counts against every task, because Today itself does.
    private var countInputs: CadenceSidebarCountInputs {
        CadenceSidebarCountInputs(
            todayOverdueCount: CadenceSidebarLayout.overdueTaskCount(
                from: allTasks,
                todayKey: DateFormatters.todayKey()
            ),
            openTaskCount: CadenceTaskQuerySupport.openTaskCount(
                from: allTasks.filter(\.isInActiveContainer)
            ),
            activeGoalCount: activeGoals.count,
            habitCount: habits.count
        )
    }

    private var listSections: [CadenceSidebarLists.Section] {
        CadenceSidebarLists.sections(
            contexts: contexts.filter { !$0.isArchived }.map {
                CadenceSidebarLists.ContextRef(id: $0.id, name: $0.name)
            },
            // Spelled as closures rather than `map(Item.init)`: an unapplied initializer reference
            // is resolved in a nonisolated context, and these read SwiftData relationships.
            items: areas.filter(\.isActive).map { CadenceSidebarLists.Item($0) }
                + projects.filter(\.isActive).map { CadenceSidebarLists.Item($0) }
        )
    }

    var body: some View {
        let counts = countInputs

        VStack(alignment: .leading, spacing: 0) {
            iOSSidebarHeader(
                style: style,
                onSearch: { selection = .search },
                onCollapse: onCollapse
            )
            .padding(.horizontal, style.horizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, 10)

            navGroup(CadenceSidebarLayout.primaryDestinations, counts: counts)
                .padding(.bottom, iOSSidebarMetrics.groupSpacing)

            iOSSidebarRailDivider()
                .padding(.horizontal, style.horizontalPadding)

            listsRegion

            iOSSidebarRailDivider()
                .padding(.horizontal, style.horizontalPadding)

            // Expanded: Goals and Habits keep labelled rows, Settings and Focus collapse to one
            // row of two glyphs. Rail is already all glyphs at 58pt, where two across plus the
            // gap does not fit, so it keeps all four stacked.
            if style == .expanded {
                navGroup(CadenceSidebarLayout.secondaryRowDestinations, counts: counts)
                    .padding(.top, iOSSidebarMetrics.groupSpacing)

                footerGlyphRow
                    .padding(.horizontal, style.horizontalPadding)
                    .padding(.top, iOSSidebarMetrics.rowSpacing)
                    .padding(.bottom, 12)
            } else {
                navGroup(CadenceSidebarLayout.secondaryDestinations, counts: counts)
                    .padding(.top, iOSSidebarMetrics.groupSpacing)
                    .padding(.bottom, 12)
            }
        }
    }

    /// Settings and Focus, one row, pushed to opposite ends.
    ///
    /// Tinted glyphs on the column's own hover/selection plate, at the nav rows' radius — the same
    /// treatment `SidebarFooterGlyphRow` draws on macOS, which adopted this row's *structure* in
    /// the same pass this row adopted macOS's *colouring*. These are the two least-travelled
    /// destinations in the column, which is why they share one row's height rather than taking
    /// one each; it is not a reason to strip their identity.
    private var footerGlyphRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(CadenceSidebarLayout.footerGlyphDestinations.enumerated()), id: \.element) { index, destination in
                if index > 0 {
                    Spacer(minLength: 8)
                }

                iOSSidebarGlyphButton(
                    systemImage: destination.systemImage,
                    label: CadenceSidebarLayout.rowTitle(for: destination),
                    tint: tint(for: destination),
                    isSelected: rowSelection == destination.item
                ) {
                    selection = destination.item
                }
            }
        }
        .frame(minHeight: 44)
    }

    // MARK: - Nav groups

    private func navGroup(
        _ destinations: [CadenceFeatureDestination],
        counts: CadenceSidebarCountInputs
    ) -> some View {
        VStack(alignment: .leading, spacing: iOSSidebarMetrics.rowSpacing) {
            ForEach(destinations) { destination in
                iOSSidebarButton(
                    title: CadenceSidebarLayout.rowTitle(for: destination),
                    systemImage: destination.systemImage,
                    tint: tint(for: destination),
                    count: CadenceSidebarLayout.count(for: destination, counts: counts),
                    isSelected: rowSelection == destination.item,
                    style: style
                ) {
                    selection = destination.item
                }
            }
        }
        .padding(.horizontal, style.horizontalPadding)
    }

    // MARK: - Lists

    /// The single scrolling region, pinned under a **Lists** row.
    ///
    /// That row is the one place this column parts from macOS, and it earns the place: iOS has a
    /// real Lists page — creating, archiving, restoring and reordering all live there, and archived
    /// lists are readable nowhere else — where macOS has none, and puts a per-context `+` in the
    /// header instead. A `+` here would have to ignore the context it sits under, because
    /// `iOSListEditorSheet` takes no seed, so it would be a control that lies about what it does.
    private var listsRegion: some View {
        VStack(alignment: .leading, spacing: 0) {
            iOSSidebarButton(
                title: CadenceSidebarLayout.rowTitle(for: .lists),
                systemImage: CadenceFeatureDestination.lists.systemImage,
                tint: tint(for: .lists),
                count: nil,
                isSelected: selection == .lists,
                style: style
            ) {
                selection = .lists
            }
            .padding(.horizontal, style.horizontalPadding)
            .padding(.top, iOSSidebarMetrics.groupSpacing)

            ScrollView {
                VStack(alignment: .leading, spacing: iOSSidebarMetrics.sectionSpacing) {
                    ForEach(listSections) { section in
                        listSection(section)
                    }

                    if listSections.isEmpty {
                        emptyListsRow
                    }
                }
                .padding(.horizontal, style.horizontalPadding)
                .padding(.vertical, iOSSidebarMetrics.groupSpacing)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func listSection(_ section: CadenceSidebarLists.Section) -> some View {
        VStack(alignment: .leading, spacing: iOSSidebarMetrics.rowSpacing) {
            if style == .expanded {
                SectionEyebrowLabel(text: section.title)
                    .lineLimit(1)
                    .padding(.horizontal, iOSSidebarMetrics.rowHorizontalPadding)
                    .padding(.bottom, 2)
            }

            ForEach(section.items) { item in
                iOSSidebarListRow(
                    item: item,
                    isSelected: selection == item.selectionItem,
                    style: style,
                    onSelect: { selection = item.selectionItem },
                    onEdit: { editorMode(for: item).map(onCreateList) }
                )
            }
        }
    }

    /// A statement, not a button. The way to make a list is the Lists row directly above it, which
    /// is already on screen — a second create affordance here would be two doors to one page.
    @ViewBuilder
    private var emptyListsRow: some View {
        if style == .expanded {
            Text(CadenceEmptyStateCopy.listsTitle(isNarrowed: false))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.dim)
                .padding(.horizontal, iOSSidebarMetrics.rowHorizontalPadding)
                .padding(.vertical, 6)
        }
    }

    private func editorMode(for item: CadenceSidebarLists.Item) -> iOSListEditorMode? {
        switch item.kind {
        case .area:
            return areas.first { $0.id == item.id }.map(iOSListEditorMode.editArea)
        case .project:
            return projects.first { $0.id == item.id }.map(iOSListEditorMode.editProject)
        }
    }
}

// MARK: - Model → value bridge

/// The two `Item` initialisers this extension used to hold live in `CadenceSidebarListsBridge`
/// now. macOS carried a second, divergent copy that took the context id as a **non-optional**
/// parameter, which is what made a context-less list undrawable on that column (T-538).
private extension CadenceSidebarLists.Item {
    var selectionItem: iOSSidebarItem {
        switch kind {
        case .area: return .area(id)
        case .project: return .project(id)
        }
    }
}

extension iOSSidebarItem {
    /// The feature this row stands for, for the projection that carries a selection across a
    /// size-class change (`CadenceShellNavigationBridge`, T-334).
    ///
    /// A specific area or project answers `.lists`: the compact shell reaches a list through the
    /// Lists screen, and pushing the list itself would need a route this projection has no business
    /// minting. Landing on Lists is the same room one door out; landing on Today is the bug.
    var featureDestination: CadenceFeatureDestination? {
        switch self {
        case .today: return .today
        case .allTasks: return .allTasks
        case .focus: return .focus
        case .inbox: return .inbox
        case .calendar: return .calendar
        case .goals: return .goals
        case .habits: return .habits
        case .notes: return .notes
        case .lists, .area, .project: return .lists
        case .search: return .search
        case .settings: return .settings
        }
    }
}

extension CadenceFeatureDestination {
    var item: iOSSidebarItem {
        switch self {
        case .today: return .today
        case .allTasks: return .allTasks
        case .focus: return .focus
        case .inbox: return .inbox
        case .calendar: return .calendar
        case .goals: return .goals
        case .habits: return .habits
        case .notes: return .notes
        case .lists: return .lists
        case .search: return .search
        case .settings: return .settings
        }
    }
}

// MARK: - Style and metrics

enum iOSSidebarStyle: Equatable {
    case rail
    case expanded

    /// Full window width, not the sidebar's own column width. The threshold and the two widths live
    /// in `CadenceRootShellLayout` so the shell's arithmetic and this enum cannot drift — the shell
    /// sizing the detail from one number while the column drew itself at another is exactly how a
    /// pane ended up pushing the sidebar off-screen.
    static func style(for width: CGFloat) -> iOSSidebarStyle {
        CadenceRootShellLayout.usesExpandedSidebar(windowWidth: width) ? .expanded : .rail
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .rail: return 8
        case .expanded: return 10
        }
    }
}

/// The iPad column's spelling of `CadenceSidebarMetrics`.
///
/// **Every figure here is the shared one now.** The two columns had each been deciding for
/// themselves and had drifted in five dimensions nobody chose — 13pt glyphs against macOS's 15,
/// 14pt labels against 13, 9pt of icon-to-label against 10, a 16pt list colour bar against 14, and
/// an 11pt due-date caption against 10. The user asked for one sidebar, so the numbers live in
/// `Shared/` and both files read them.
///
/// `buttonHeight` is the single exception, and it is `CadenceSidebarMetrics`' exception rather than
/// this file's: 44pt because a nav row is the most-tapped control in this shell, where macOS's 32
/// is right under a pointer.
enum iOSSidebarMetrics {
    private static let shared = CadenceSidebarMetrics.metrics(for: .tablet)

    static let buttonHeight: CGFloat = shared.rowHeight
    static let iconSize: CGFloat = shared.iconSize
    static let selectedCornerRadius: CGFloat = shared.cornerRadius
    static let rowSpacing: CGFloat = shared.rowSpacing
    static let rowHorizontalPadding: CGFloat = shared.horizontalPadding
    static let iconSlotWidth: CGFloat = shared.iconSlotWidth
    static let iconLabelSpacing: CGFloat = shared.iconLabelSpacing
    static let labelFontSize: CGFloat = shared.labelFontSize
    static let badgeLeadingGap: CGFloat = shared.badgeLeadingGap
    static let groupSpacing: CGFloat = shared.groupSpacing
    static let sectionSpacing: CGFloat = shared.sectionSpacing
    static let secondaryIconOpacity: Double = shared.secondaryIconOpacity

    // MARK: List rows

    static let listColorBarWidth: CGFloat = shared.listColorBarWidth
    static let listColorBarHeight: CGFloat = shared.listColorBarHeight
    static let listColorBarLeadingInset: CGFloat = shared.listColorBarLeadingInset
    static let listDueDateIconSize: CGFloat = shared.listDueDateIconSize
    static let listDueDateFontSize: CGFloat = shared.listDueDateFontSize
    static let listDueDateSpacing: CGFloat = shared.listDueDateSpacing
    static let listTrailingItemSpacing: CGFloat = shared.listTrailingItemSpacing

    /// The footer row's two glyph plates, matching `SidebarMetrics.footerGlyphSize`.
    static let footerGlyphSize: CGFloat = 28
}

struct iOSSidebarRailDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.borderSubtle)
            .frame(maxWidth: .infinity)
            .frame(height: 1)
    }
}

// MARK: - Header

/// The app mark, the product name, and the column's two controls: search, and fold.
///
/// The mark used to be the button that opened the lists drawer, wearing a `sidebar.leading` glyph
/// that promised to collapse the sidebar and did not. The glyph is now a control of its own, and it
/// does exactly what it has always looked like it would.
///
/// Search lives here because the sidebar's two nav groups are `CadenceSidebarLayout`'s, and that
/// layout deliberately leaves `.search` out of them — it is the header's button, on both platforms.
struct iOSSidebarHeader: View {
    let style: iOSSidebarStyle
    let onSearch: () -> Void
    let onCollapse: () -> Void

    var body: some View {
        if style == .expanded {
            HStack(spacing: 8) {
                iOSIconTile(systemImage: "circle.hexagongrid.fill", color: Theme.blue, size: 28, iconSize: 14)

                Text("Cadence")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 2)

                searchButton
                collapseButton
            }
            .frame(minHeight: 44)
        } else {
            VStack(spacing: 4) {
                iOSIconTile(systemImage: "circle.hexagongrid.fill", color: Theme.blue, size: 28, iconSize: 14)
                    .accessibilityHidden(true)
                searchButton
                collapseButton
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var searchButton: some View {
        iOSSidebarGlyphButton(
            systemImage: CadenceFeatureDestination.search.systemImage,
            label: "Search",
            action: onSearch
        )
    }

    private var collapseButton: some View {
        iOSSidebarGlyphButton(
            systemImage: "sidebar.leading",
            label: "Hide Sidebar",
            action: onCollapse
        )
    }
}

/// A small plate with a 44pt hit area — `iOSIconButton`'s trick. The header has to hold a mark, a
/// wordmark and two controls inside 188pt, and padding either control out to 44pt in *layout* would
/// push the wordmark off the row.
///
/// Two jobs, told apart by `tint`. The header's search and collapse controls are **actions**: they
/// stay `Theme.dim` and can never be selected. The footer's Settings and Focus are
/// **destinations**: they carry the same per-destination tint the nav rows above them do, and
/// selection is the same `Theme.surfaceHighlight` plate at the same radius — one layer, one
/// radius. Brightening the glyph to `Theme.text` was how this row used to carry selection, and it
/// cannot survive a tinted glyph: the colour is the destination's identity, so overwriting it to
/// mean "selected" would say two things through one channel.
private struct iOSSidebarGlyphButton: View {
    let systemImage: String
    let label: String
    /// `nil` for the header's two action controls. See the type comment.
    var tint: Color? = nil
    var isSelected = false
    let action: () -> Void

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: iOSSidebarMetrics.selectedCornerRadius, style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: glyphSize, weight: .semibold))
                .foregroundStyle(glyphColor)
                .frame(width: plateSize, height: plateSize)
                .background(shape.fill(isSelected ? Theme.surfaceHighlight : Color.clear))
                .contentShape(shape)
                .iOSExpandedHitArea(9)
        }
        .buttonStyle(.iosPressable)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var glyphSize: CGFloat {
        tint == nil ? 13 : iOSSidebarMetrics.iconSize
    }

    private var plateSize: CGFloat {
        tint == nil ? 26 : iOSSidebarMetrics.footerGlyphSize
    }

    private var glyphColor: Color {
        guard let tint else { return Theme.dim }
        return tint.opacity(iOSSidebarMetrics.secondaryIconOpacity)
    }
}

/// The way back into a folded sidebar.
///
/// A tab on the leading edge rather than a button in a corner: page headers own the top-leading
/// corner of every detail pane, and a floating control there would cover one. 22pt of plate and
/// 44pt of target, vertically centred, where a thumb reaching round the bezel already is.
struct iOSSidebarExpandHandle: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.muted)
                .frame(width: 22, height: 56)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: Theme.radiusControl,
                        topTrailingRadius: Theme.radiusControl,
                        style: .continuous
                    )
                    .fill(Theme.surfaceElevated)
                )
                .overlay(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: Theme.radiusControl,
                        topTrailingRadius: Theme.radiusControl,
                        style: .continuous
                    )
                    .strokeBorder(Theme.borderSubtle, lineWidth: 1)
                )
                .contentShape(Rectangle())
                .iOSExpandedHitArea(11)
        }
        .buttonStyle(.iosPressable)
        .accessibilityLabel("Show Sidebar")
    }
}

// MARK: - Rows

/// A navigation row in the iPad shell's sidebar.
///
/// **The glyph carries its destination's tint**, the same one macOS draws. This file argued the
/// opposite for a while — that six hues in one column encode nothing a reader can act on, and that
/// macOS only keeps its tints because Settings → Sidebar has a per-destination colour picker there
/// while iPad has none, so the hue was decoration here. The user compared the two columns and asked
/// for iOS to match macOS's colouring, which settles it: `CadencePreferenceKeys.sidebarTabColors`
/// is a plain preference string, `CadenceSidebarTint` parses it for both platforms, and this column
/// honours an override written on the Mac whether or not it ever grows the picker itself.
///
/// What carries state is the row: `Theme.surfaceHighlight` behind it, `Theme.text` on the label,
/// semibold. One layer, one radius — `SidebarNavRow`'s rule, and the iPhone More tab's.
struct iOSSidebarButton: View {
    let title: String
    let systemImage: String
    /// The destination's own colour, resolved through `CadenceSidebarTint` so this column reads
    /// the same `sidebarTabColors` preference macOS's picker writes.
    let tint: Color
    let count: CadenceSidebarCount?
    let isSelected: Bool
    let style: iOSSidebarStyle
    let action: () -> Void

    /// The glyph keeps its destination tint selected or not, exactly as `SidebarNavRow` does:
    /// selection is the plate and the heavier label, never the hue.
    private var glyphColor: Color {
        tint
    }

    var body: some View {
        Button(action: action) {
            if style == .expanded {
                expandedLabel
            } else {
                railLabel
            }
        }
        .buttonStyle(.iosPressable)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var expandedLabel: some View {
        HStack(spacing: iOSSidebarMetrics.iconLabelSpacing) {
            Image(systemName: systemImage)
                .font(.system(size: iOSSidebarMetrics.iconSize, weight: .semibold))
                .foregroundStyle(glyphColor)
                .frame(width: iOSSidebarMetrics.iconSlotWidth)

            Text(title)
                .font(.system(size: iOSSidebarMetrics.labelFontSize, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Theme.text : Theme.muted)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: iOSSidebarMetrics.badgeLeadingGap)

            if let count {
                CadenceSidebarCountLabel(count: count)
                    // The count is the row's fixed element; the label is what gives.
                    .layoutPriority(1)
            }
        }
        .padding(.horizontal, iOSSidebarMetrics.rowHorizontalPadding)
        .frame(height: iOSSidebarMetrics.buttonHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selectionLayer)
        .contentShape(selectionShape)
    }

    private var railLabel: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: systemImage)
                .font(.system(size: iOSSidebarMetrics.iconSize, weight: .semibold))
                .foregroundStyle(glyphColor)
                .frame(maxWidth: .infinity)
                .frame(height: iOSSidebarMetrics.buttonHeight)

            if let count {
                CadenceSidebarCountLabel(count: count)
                    .padding(.trailing, 2)
                    .padding(.top, 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(height: iOSSidebarMetrics.buttonHeight)
        .background(selectionLayer)
        .contentShape(selectionShape)
    }

    private var selectionShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: iOSSidebarMetrics.selectedCornerRadius, style: .continuous)
    }

    /// One selection layer at one radius, the rule `SidebarNavRow` follows: selection is a step up
    /// the neutral ramp, not a coloured 2pt rail bolted to the leading edge of an otherwise
    /// unchanged row.
    private var selectionLayer: some View {
        selectionShape.fill(isSelected ? Theme.surfaceHighlight : Color.clear)
    }
}

/// One area/project row: a 2pt colour bar, the name, and optional trailing metadata.
///
/// **No glyph.** A list's icon was a second identity competing with its colour and its name, and a
/// column of a dozen different symbols is harder to scan than a column of names. The list's own
/// `colorHex` survives as a 2pt bar drawn *inside the row's leading padding* — outside the text
/// column — so every name starts on the same x whatever colour it carries.
struct iOSSidebarListRow: View {
    let item: CadenceSidebarLists.Item
    let isSelected: Bool
    let style: iOSSidebarStyle
    let onSelect: () -> Void
    let onEdit: () -> Void

    private var rowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: iOSSidebarMetrics.selectedCornerRadius, style: .continuous)
    }

    private var displayName: String {
        CadenceTitleNormalization.display(item.name, fallback: CadenceTitleNormalization.defaultCompactTitle)
    }

    var body: some View {
        Button(action: onSelect) {
            Group {
                if style == .expanded {
                    expandedLabel
                } else {
                    railLabel
                }
            }
            .frame(height: iOSSidebarMetrics.buttonHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowShape.fill(isSelected ? Theme.surfaceHighlight : Color.clear))
            // Decorative and inside the button's own label, but `allowsHitTesting(false)` is
            // stated rather than assumed: a filled shape laid over an interactive surface is
            // exactly the thing that has silently eaten taps in this repo before.
            .overlay(alignment: .leading) { colorBar.allowsHitTesting(false) }
            .contentShape(rowShape)
        }
        .buttonStyle(.iosPressable)
        // The touch equivalent of macOS's right-click-to-edit on the same row. Not `.swipeActions`:
        // that modifier does nothing outside a `List`, and this region is a `ScrollView`.
        .contextMenu {
            Button {
                onEdit()
            } label: {
                Label("Edit \(item.kind == .area ? "Area" : "Project")", systemImage: "pencil")
            }
        }
        .accessibilityLabel(displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var expandedLabel: some View {
        HStack(spacing: iOSSidebarMetrics.listTrailingItemSpacing) {
            Text(displayName)
                .font(.system(size: iOSSidebarMetrics.labelFontSize, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Theme.text : Theme.muted)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: iOSSidebarMetrics.badgeLeadingGap)

            if let dueDateKey = item.dueDateKey {
                dueDateBadge(dueDateKey)
            }

            if let count = CadenceSidebarLayout.listCount(openTaskCount: item.openTaskCount) {
                CadenceSidebarCountLabel(count: count)
                    .layoutPriority(1)
            }
        }
        .padding(.horizontal, iOSSidebarMetrics.rowHorizontalPadding)
    }

    /// At rail width there is no room for a name, so the colour bar is the whole row — which is
    /// exactly what it is on the labelled column too, just without a name beside it. The initial
    /// gives the row something to aim at.
    private var railLabel: some View {
        Text(String(displayName.prefix(1)).uppercased())
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isSelected ? Theme.text : Theme.muted)
            .frame(maxWidth: .infinity)
    }

    private var colorBar: some View {
        Capsule(style: .continuous)
            .fill(Color(hex: item.colorHex))
            .frame(
                width: iOSSidebarMetrics.listColorBarWidth,
                height: iOSSidebarMetrics.listColorBarHeight
            )
            .padding(.leading, iOSSidebarMetrics.listColorBarLeadingInset)
    }

    /// Bare tinted text rather than a filled pill: as a capsule this annotation carried more weight
    /// than the list name it annotates. Read-only here — the date is set in the list editor, which
    /// the row's own context menu opens.
    private func dueDateBadge(_ key: String) -> some View {
        HStack(spacing: iOSSidebarMetrics.listDueDateSpacing) {
            Image(systemName: "flag.fill")
                .font(.system(size: iOSSidebarMetrics.listDueDateIconSize, weight: .semibold))
                .foregroundStyle(Theme.red)
            Text(DateFormatters.relativeDate(from: key))
                .font(.system(size: iOSSidebarMetrics.listDueDateFontSize, weight: .semibold))
                .foregroundStyle(key < DateFormatters.todayKey() ? Theme.red : Theme.dim)
                .lineLimit(1)
        }
        .fixedSize()
        .accessibilityHidden(true)
    }
}

struct iOSMissingListView: View {
    var body: some View {
        iOSEmptyPanel(
            systemImage: "questionmark.folder",
            title: CadenceEmptyStateCopy.missingListTitle,
            subtitle: CadenceEmptyStateCopy.missingListSubtitle
        )
        .background(Theme.bg.ignoresSafeArea())
    }
}
#endif
