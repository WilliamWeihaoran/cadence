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
    /// **Not destructive, and still no full swipe ([[T-12452]]).** Archiving destroys nothing -- an
    /// archived list is one tap from Restore in the Archived section -- so it neither wears Delete's
    /// red nor claims `isDestructive`; it takes `Theme.muted`, the tint macOS's
    /// `ListEditorArchiveButton` gives the same action, and the long-press menu's Archive is plain
    /// ([[T-12322]]). `refusesFullSwipe` is what withholds it from a *full* swipe, which is what
    /// `allowsFullSwipe: false` did on the compact rows: filing a list away should take the
    /// deliberate tap, not a flick.
    static func archive(_ perform: @escaping () -> Void) -> [CadenceSwipeAction] {
        [
            CadenceSwipeAction(
                id: "archive-list",
                title: "Archive",
                systemImage: "archivebox",
                tint: Theme.muted,
                refusesFullSwipe: true,
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.cadenceTypographyScaling) private var scaling
    let count: Int

    var body: some View {
        Text(count > 999 ? "999+" : "\(count)")
            .cadenceFont(.metadata, base: 11, weight: .semibold)
            .monospacedDigit()
            .foregroundStyle(Theme.muted)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .frame(minWidth: 24, minHeight: CadenceTypeScale.height(20, holding: .metadata, textBase: 11, at: dynamicTypeSize, scaling: scaling))
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

/// The Lists page's create door. Used by both the compact and regular layouts so list creation
/// doesn't rely on a native nav-bar toolbar menu (which disappears once the plain nav bar is
/// hidden in favor of `iOSListsPageHeader`).
///
/// **One button, not two (T-2054).** It was "New Area" beside "New Project" — the same question
/// asked twice before the sheet that owns it has opened. `iOSListEditorSheet`'s first control when
/// `!isEditing` is its Area/Project segment, exactly as macOS's `CreateListSheet` has had one all
/// along, so `.newArea` here is the editor's *entry* mode and not a decision: one door reaches
/// both types. That is what retires `iOSListEditorMode.newProject`'s last tap call site — this
/// row was the only thing in the app that set it from a tap, which is why the type could never be
/// chosen anywhere but here.
///
/// The copy and the glyph are the ones already in use for a type-neutral list door: "New List" is
/// the sheet's own `navigationTitle`, and `plus.circle` is what `SidebarAddFirstListButton` and
/// the iPad column's `addFirstListButton` draw. The tint is `Theme.blue` because that is the
/// Lists page's own accent — a list's colour is the user's, and it arrives with the list.
///
/// Before that it was two full-width `.borderedProminent` slabs, one blue and one green — the
/// loudest thing on a page whose subject is the user's own list colours; it is the same neutral
/// chip the task view-options bar uses now.
struct iOSListCreateButtonsRow: View {
    @Binding var editorMode: iOSListEditorMode?

    var body: some View {
        iOSActionButton(
            title: "New List",
            systemImage: "plus.circle",
            role: .secondary,
            size: .compact,
            tint: Theme.blue,
            fullWidth: true
        ) {
            editorMode = .newArea
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.cadenceTypographyScaling) private var scaling
    @Binding var page: ListDetailPage
    /// How many items each tab holds, for the tabs where a total means something. Each tab used
    /// to draw its own header carrying this number; removing those headers — the tab bar already
    /// names the tab — took the counts with them, and the count was not the redundant half.
    var counts: [ListDetailPage: Int] = [:]

    /// Whether the scrolling fallback has tabs hidden past either edge.
    @State private var overflow = EdgeOverflow()

    private struct EdgeOverflow: Equatable {
        var leading = false
        var trailing = false
    }

    /// T-6985. The first padding tier at which all five tabs fit is the one drawn, so on an
    /// iPhone with counts showing the strip tightens instead of running "Completed" off the edge.
    /// Only when even the tightest tier cannot hold them — large text, or very large counts —
    /// does it scroll, and that fallback fades the edge that has more tabs behind it and keeps
    /// the selected tab in view. See `ListDetailTabStripMetrics`.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(ListDetailTabStripMetrics.horizontalPaddingTiers, id: \.self) { padding in
                tabRow(horizontalPadding: padding)
            }
            scrollingStrip
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scrollingStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                tabRow(horizontalPadding: ListDetailTabStripMetrics.horizontalPaddingTiers.last ?? 6)
            }
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: EdgeOverflow.self) { geometry in
                EdgeOverflow(
                    leading: geometry.contentOffset.x > 1,
                    trailing: geometry.contentOffset.x + geometry.containerSize.width < geometry.contentSize.width - 1
                )
            } action: { _, newValue in
                overflow = newValue
            }
            .mask {
                HStack(spacing: 0) {
                    LinearGradient(colors: [overflow.leading ? .clear : .black, .black], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 28)
                    Rectangle()
                    LinearGradient(colors: [.black, overflow.trailing ? .clear : .black], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 28)
                }
            }
            .onAppear { proxy.scrollTo(page, anchor: .center) }
            .onChange(of: page) { _, newPage in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(newPage, anchor: .center) }
            }
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

    private func tabRow(horizontalPadding: CGFloat) -> some View {
        HStack(spacing: ListDetailTabStripMetrics.tabSpacing) {
            ForEach(ListDetailPage.allCases) { item in
                let isSelected = page == item
                Button {
                    page = item
                } label: {
                    HStack(spacing: ListDetailTabStripMetrics.labelCountSpacing) {
                        // Sized by the semibold spelling whatever the state, so selecting a tab
                        // never widens the row — which would otherwise flip the strip between
                        // padding tiers as you tap along it.
                        Text(item.rawValue)
                            .cadenceFont(.controlLabel, weight: .semibold)
                            .lineLimit(1)
                            .hidden()
                            .overlay {
                                Text(item.rawValue)
                                    .cadenceFont(.controlLabel, weight: isSelected ? .semibold : .medium)
                                    // `muted`, not `dim`: an unselected tab is a label you read and
                                    // tap, and `dim` on this surface sits under the AA floor at 13pt.
                                    .foregroundStyle(isSelected ? Theme.text : Theme.muted)
                                    .lineLimit(1)
                                    .fixedSize()
                            }

                        if let count = counts[item], count > 0 {
                            Text("\(count)")
                                .cadenceFont(.metadata, base: 11, weight: .semibold)
                                .monospacedDigit()
                                .foregroundStyle(isSelected ? Theme.muted : Theme.dim)
                        }
                    }
                        .padding(.horizontal, horizontalPadding)
                        .frame(minWidth: ListDetailTabStripMetrics.minimumTabWidth)
                        .frame(minHeight: CadenceTypeScale.height(44, holding: .controlLabel, at: dynamicTypeSize, scaling: scaling))
                        .background(
                            RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                                .fill(isSelected ? Theme.surfaceHighlight : Color.clear)
                        )
                        .contentShape(
                            RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .id(item)
                .accessibilityLabel(item.tabAccessibilityLabel(count: counts[item]))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, ListDetailTabStripMetrics.stripInset)
    }
}

struct iOSListPickerRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.cadenceTypographyScaling) private var scaling
    let title: String
    let subtitle: String?
    let icon: String
    let colorHex: String
    let count: Int

    var body: some View {
        let wraps = iOSTaskPageTypographyMetrics.stacksControls(at: dynamicTypeSize, scaling: scaling)
        let layout = wraps ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
        layout {
            iOSListIconBadge(icon: icon, colorHex: colorHex)

            VStack(alignment: .leading, spacing: 3) {
                Text(TaskTitleSupport.displayTitle(title, fallback: TaskTitleSupport.defaultCompactDisplayTitle))
                    .cadenceFont(.bodyText, weight: .semibold)
                    .foregroundStyle(Theme.text)
                    .lineLimit(wraps ? nil : 1)
                    .fixedSize(horizontal: false, vertical: wraps)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .cadenceFont(.metadata)
                        .foregroundStyle(Theme.subdued)
                        .lineLimit(wraps ? nil : 1)
                        .fixedSize(horizontal: false, vertical: wraps)
                }
            }

            if !wraps { Spacer(minLength: 8) }

            iOSListCountBadge(count: count)
        }
        .frame(minHeight: 44)
    }
}

struct iOSArchivedListRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.cadenceTypographyScaling) private var scaling
    let title: String
    let subtitle: String?
    let icon: String
    let colorHex: String
    let restore: () -> Void

    var body: some View {
        let wraps = iOSTaskPageTypographyMetrics.stacksControls(at: dynamicTypeSize, scaling: scaling)
        let layout = wraps ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
        layout {
            iOSListIconBadge(icon: icon, colorHex: colorHex, isMuted: true)

            VStack(alignment: .leading, spacing: 3) {
                Text(TaskTitleSupport.displayTitle(title, fallback: TaskTitleSupport.defaultCompactDisplayTitle))
                    .cadenceFont(.bodyText, weight: .medium)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(wraps ? nil : 1)
                    .fixedSize(horizontal: false, vertical: wraps)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .cadenceFont(.metadata)
                        .foregroundStyle(Theme.dim)
                        .lineLimit(wraps ? nil : 1)
                        .fixedSize(horizontal: false, vertical: wraps)
                }
            }

            if !wraps { Spacer(minLength: 8) }

            // [[T-8563]] (b): "Unarchive", the word Settings > Lists says for the same action.
            iOSActionButton(
                title: CadenceListVocabularyCopy.unarchiveActionTitle,
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
///
/// **[[T-14292]]: the rows are headed by their count**, `ListLogRowPresentation.countLabel(for:)`
/// -- "3 completed", "2 completed, 1 canceled" -- the eyebrow the Mac's same tab (`ListLogView`)
/// draws over the same rows. That is a count, not the tab's name again.
struct iOSListCompletedPanel: View {
    let tasks: [AppTask]
    /// The list page's observed day, for `iOSTaskRow.todayKey` ([[T-14341]]).
    let todayKey: String
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// Over the rows' completion circles: the row's list inset plus the row's own content padding.
    private var eyebrowLeadingInset: CGFloat {
        12 + CadenceTaskRowMetrics.metrics(isRegularWidth: horizontalSizeClass == .regular).horizontalPadding
    }

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
                    SectionEyebrowLabel(text: ListLogRowPresentation.countLabel(for: tasks))
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                        .textCase(nil)
                        .listRowInsets(EdgeInsets(top: 0, leading: eyebrowLeadingInset, bottom: 0, trailing: 12))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

                    ForEach(tasks) { task in
                        // Scoped to one list already — see `iOSTaskRow.showsContainer`. Dimmed at
                        // the shared settled-row figure, as the Mac's same tab is ([[T-16461]]).
                        iOSTaskListRow(
                            task: task,
                            opacity: CadenceTaskRowMetrics.settledRowOpacity,
                            showsContainer: false,
                            todayKey: todayKey
                        )
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
    /// **The list's FINISHED tasks, so a column can close with the Mac's "Completed N" toggle**
    /// ([[T-9837]]). This panel was handed `activeTasks` only, so a column whose work was all done
    /// read "0" and empty on an iPad while every macOS list Kanban column showed its finished
    /// cards behind `KanbanCompletedTasksToggle`. The iOS list page having its own Completed tab
    /// is not a hardware or input reason, and the Mac list page has finished work in more than one
    /// place too, so under [[T-8201]] the difference was drift.
    ///
    /// They are bucketed into columns by `ListDetailKanbanBoard.completedTasksByColumn`, the same
    /// `sectionGroups` call the open cards go through, so the two halves of a column cannot
    /// disagree about which section a task is in. Empty by default: a caller that has no finished
    /// half gets the board it always got, with no footer drawn anywhere.
    var completedTasks: [AppTask] = []
    let sectionNames: [String]
    /// Colour/completion for the named columns, and -- every config, archived ones included -- what
    /// `liveFiling` reads to file a card whose column is not live ([[T-11222]] (b)). Every column
    /// drawn is a configured one now, so the list-colour fallback for a config-less name is a
    /// guard rather than a case the board reaches.
    let sectionConfigs: [TaskSectionConfig]
    /// The list's `hideSectionDueDateIfEmpty`. Wired for the same reason the due-date line itself
    /// is (T-331): the flag was already in the model and already editable on macOS, so an iOS board
    /// that ignored it would have shown "No due date" under every column of a list whose owner had
    /// asked for exactly the opposite — and there would have been no iOS control to ask with.
    let hideSectionDueDateIfEmpty: Bool
    /// The list page's observed day, handed to every card's do and due chips ([[T-14581]]) -- the
    /// board's inputs are otherwise the same on both sides of midnight.
    let todayKey: String
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
    /// The list itself, for the add-column control. A column is a `TaskSectionConfig` on the area or
    /// project, so adding one is `CadenceSectionCreationRow`'s store write — the same control the
    /// Tasks tab ends with and the Mac list draws — not a second path of this board's own.
    var area: Area?
    var project: Project?
    /// The list's tasks from the store, finished ones included: the sequence a card drop
    /// renumbers, which `tasks` (the open cards only) is not. The same array macOS's list board
    /// hands its columns as `spanTasks` ([[T-1175]], [[T-8183]]).
    var spanTasks: [AppTask]?
    /// True while the page's "Show Archived" chip is on ([[T-8565]]), so `sectionNames` are the
    /// list's ARCHIVED columns. Like the Mac's `ListSectionsKanbanView`, the board then draws no
    /// add-column control: a column made there would be a live one, drawn on a board that is not
    /// showing live columns.
    var showsArchivedColumns = false

    @Environment(\.modelContext) private var modelContext

    /// Which column the ring is currently on. Separate from `highlightedSectionName` because the
    /// request outlives the emphasis: the ring fades after a beat and the request is still the
    /// reason this board is on screen, so clearing one must not clear the other.
    @State private var activeHighlightName: String?
    /// The composer a column's "Add task" row asked for ([[T-8184]]). The same `iOSCreateTaskSheet`
    /// the capture `+` opens, seeded rather than reimplemented: a board column on iOS opens the
    /// sheet, as the Calendar Board's day columns do, where macOS composes inline — a touch
    /// keyboard rises over the column an inline field would sit in.
    @State private var addRequest: iOSListKanbanAddRequest?

    /// **Every configured column, filled or not.** An unfilled column is the case the drop rule
    /// exists for, and it was the one case that could not happen here: `sectionGroups` discarded
    /// the column before anything could offer it. The board's own empty state below stands in only
    /// when the list has no column at all — it used to stand in whenever there was no open task,
    /// which hid every column a fresh list had ([[T-7033]]).
    private var columns: [CadenceTaskDisplayGroup] {
        ListDetailKanbanBoard.columns(tasks: tasks, sectionNames: sectionNames, filing: liveFiling)
    }

    /// [[T-11222]] (b): on the live board a card whose section names no live column is drawn under
    /// Default, as on the Mac, instead of in a column of its own that resurrected an archived one.
    /// The Show Archived board matches by the task's own name.
    private var liveFiling: ListBoardCardFiling? {
        showsArchivedColumns ? nil : ListBoardCardFiling(configs: sectionConfigs)
    }

    /// Finished cards keyed by the column title `columns` produces ([[T-9837]]). One pass for the
    /// whole board rather than a filter per column: a SwiftUI computed property is recomputed at
    /// every reference, and the body reaches this once per column inside a `ForEach` (T-1501).
    private var completedByColumn: [String: [AppTask]] {
        ListDetailKanbanBoard.completedTasksByColumn(tasks: completedTasks, sectionNames: sectionNames, filing: liveFiling)
    }

    var body: some View {
        Group {
            if !ListDetailKanbanBoard.drawsColumns(columns) {
                VStack(spacing: 0) {
                    iOSEmptyPanel(
                        systemImage: showsArchivedColumns
                            ? CadenceEmptyStateCopy.listKanbanArchivedSystemImage
                            : CadenceEmptyStateCopy.listKanbanSystemImage,
                        title: showsArchivedColumns
                            ? CadenceEmptyStateCopy.listKanbanArchivedTitle
                            : CadenceEmptyStateCopy.listKanbanTitle,
                        subtitle: showsArchivedColumns
                            ? CadenceEmptyStateCopy.listKanbanArchivedSubtitle
                            : CadenceEmptyStateCopy.listKanbanSubtitle
                    )
                    // The list itself, for the same reason the Tasks tab's empty state takes it:
                    // with no columns drawn there is nothing narrower to point at.
                    .iOSNewTaskDropTarget(
                        group: CadenceTaskDropSupport.groupIdentity(
                            container: container,
                            listName: listName
                        )
                    )
                    if !showsArchivedColumns {
                        CadenceSectionCreationRow(area: area, project: project, noun: .column)
                            .frame(width: iOSBoardColumnWidth, alignment: .leading)
                            .padding(.bottom, 16)
                    }
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 14) {
                            // Derived once for the row, not once per column — see
                            // `completedByColumn`.
                            let finished = completedByColumn
                            ForEach(columns) { column in
                                let identity = CadenceTaskDropSupport.groupIdentity(
                                    container: container,
                                    listName: listName,
                                    sectionName: column.title
                                )
                                // One write for the column's three drop targets: a card, the
                                // column body and the end slot ([[T-16503]]).
                                let dropCard: ([String], CadenceKanbanCardDrop.Slot) -> Bool = { items, slot in
                                    CadenceKanbanCardDrop.drop(
                                        items,
                                        intoColumn: column.title,
                                        at: slot,
                                        // [[T-15622]]: the column's finished cards too, so a
                                        // card dropped on one lands in front of it.
                                        columnTasks: ListDetailKanbanBoard.dropColumnCards(
                                            open: column.tasks,
                                            finished: finished[column.title] ?? []
                                        ),
                                        // [[T-15620]]: the finished cards too -- they are
                                        // draggable behind the Completed toggle, as on the Mac.
                                        among: ListDetailKanbanBoard.droppableCards(
                                            open: tasks,
                                            finished: completedTasks
                                        ),
                                        spanning: spanTasks ?? tasks,
                                        ofList: CadenceTaskDropSupport.containerKey(for: container),
                                        in: modelContext
                                    )
                                }
                                iOSListKanbanColumn(
                                    title: column.title,
                                    dotColor: dotColor(for: column.title),
                                    dueDatePlan: dueDatePlan(for: column.title),
                                    lifecycleLabel: lifecycleLabel(for: column.title),
                                    tasks: column.tasks,
                                    completedTasks: finished[column.title] ?? [],
                                    todayKey: todayKey,
                                    isHighlighted: isHighlighted(column.title),
                                    dropIdentity: identity,
                                    // [[T-8184]]: the header's drop identity, so a tap on the row
                                    // and a `+` dropped on the header seed the same list and section.
                                    onAddTask: {
                                        addRequest = iOSListKanbanAddRequest(
                                            seed: ListDetailKanbanBoard.addTaskSeed(for: identity)
                                        )
                                    },
                                    onDropCard: { items, target in
                                        dropCard(items, .before(target))
                                    },
                                    onDropAtColumnEnd: { items in
                                        dropCard(items, .columnEnd)
                                    }
                                )
                                .id(column.title)
                            }
                            // The trailing add-column rail macOS ends every list board with
                            // (`ListSectionsKanbanView.addSectionRail`), at a column's width so the
                            // name field has room. T-7033.
                            if !showsArchivedColumns {
                                CadenceSectionCreationRow(area: area, project: project, noun: .column)
                                    .frame(width: iOSBoardColumnWidth, alignment: .topLeading)
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
        .sheet(item: $addRequest) { request in
            iOSCreateTaskSheet(seed: request.seed)
        }
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

    /// The Mac section column's rule, not a second one ([[T-11221]]): Default is neutral, a
    /// completed column green, a column the list no longer configures the list's own colour.
    private func dotColor(for name: String) -> Color {
        CadenceBoardColumnTint.dot(for: config(for: name)).color(listAccent: accent)
    }

    /// "Completed" under a completed column's header, the Mac's words ([[T-11221]]).
    private func lifecycleLabel(for name: String) -> String? {
        CadenceBoardColumnLifecycleCopy.label(isCompleted: config(for: name)?.isCompleted ?? false)
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

/// One press of a column's "Add task" row: the seed the composer opens with. Identified per press
/// so a second press on the same column presents again rather than matching the last one.
private struct iOSListKanbanAddRequest: Identifiable {
    let id = UUID()
    let seed: CadenceTaskComposerSeed
}

/// The end slot's height: a fingertip's worth of target under the last card ([[T-16503]]), short
/// of the 44pt floor because it is a drop target rather than a tap target and sits in the stack's
/// spacing.
private let iOSListKanbanColumnEndSlotHeight: CGFloat = 28

private struct iOSListKanbanColumn: View {
    let title: String
    let dotColor: Color
    /// The metadata this column used to withhold from the shared header (T-331). The board draws
    /// the line; it does not edit it — a section's due date is set in the list editor on iOS, the
    /// way macOS sets it from the header popover.
    let dueDatePlan: CadenceBoardColumnDueDatePlan
    /// "Completed" for a completed column, under the due date as the Mac's header draws it
    /// ([[T-11221]]); `nil` for an open one.
    var lifecycleLabel: String? = nil
    let tasks: [AppTask]
    /// **The column's finished cards, drawn behind a collapsed "Completed N" toggle at the foot of
    /// the stack** ([[T-9837]]) -- where macOS's `ListSectionKanbanColumn` closes with
    /// `KanbanCompletedTasksToggle` over the same half and this column drew nothing at all.
    ///
    /// They are NOT in `tasks` and must not be: the header's count is the OPEN work, which is
    /// macOS's rule and T-571's, and the toggle below carries its own count. Adding the two would
    /// state one number twice over.
    var completedTasks: [AppTask] = []
    /// The board's observed day, for its cards' chips ([[T-14581]]).
    let todayKey: String
    /// Set for the one column a caller arrived here to look at. It is emphasis, not selection —
    /// nothing about the column behaves differently — so it draws a ring at the card radius and
    /// nothing else, and the panel takes it away after a beat.
    var isHighlighted = false
    /// See `iOSTaskGroupHeader.dropIdentity` — the header is the drop target here for the same
    /// reason, and reaches the same place a card cannot: a column with nothing in it.
    var dropIdentity: CadenceTaskGroupDropIdentity?
    /// **[[T-8184]]: the column's new-task row**, directly under the header as the Calendar Board's
    /// day column and all three macOS hosts (`KanbanColumnScroll`) draw theirs. The board answers,
    /// not the column, for the reason it answers a card drop: the board holds the composer.
    var onAddTask: () -> Void = {}
    /// **[[T-8183]]: the column takes a card.** Its only drop target used to be the header's `+`
    /// ghost, so a card could not change column by touch at all. The board answers, not the column:
    /// the board holds the task list a payload is checked against, and the write is
    /// `CadenceKanbanCardDrop`'s, the one macOS's columns make.
    ///
    /// **[[T-8271]]: and so does each card**, the target macOS's `KanbanDraggableCard` is
    /// (`onDropBefore`). The second argument is the card dropped on — the card lands in front of
    /// it, in this column or from another — or `nil` for the column body, which files it at the end.
    /// Without it a card could change column and never move within one.
    var onDropCard: ([String], AppTask?) -> Bool = { _, _ in false }
    /// **[[T-16503]]: the slot under the last open card**, which files a card at the column's end
    /// -- its own column included. A card dropped on a card lands in front of it and the column
    /// body refuses the card's own column (a touch set down in a gap would otherwise jump to the
    /// bottom), so before this nothing put a card below the last one of its own column. The Mac
    /// reaches that slot through its column body under the cards; a touch board cannot tell a gap
    /// from the end, so the end is a target of its own.
    var onDropAtColumnEnd: ([String]) -> Bool = { _ in false }
    @State private var isCardDropTargeted = false
    /// Whether a held card is over the end slot, for the same 2pt insertion line a card draws.
    @State private var isColumnEndDropTargeted = false
    /// **Collapsed on arrival**, as the Mac's toggle and the iOS Calendar Board's footer both are:
    /// the board is for the work that is left, and finished cards are there to be found rather
    /// than to be read past ([[T-9837]]).
    @State private var isCompletedCollapsed = true
    /// The card a held card is over, for macOS's insertion line (`KanbanDraggableCard`'s 2pt top
    /// rule): where the drop will land, drawn on the card rather than as a second column layer.
    @State private var dropTargetTaskID: UUID?

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
                    if let lifecycleLabel {
                        CadenceBoardColumnLifecycleLine(label: lifecycleLabel)
                            .padding(.leading, CadenceBoardColumnHeaderMetrics.detailLeadingInset)
                    }
                }
            )
            .iOSNewTaskDropTarget(group: dropIdentity)

            // The Calendar Board's row, not a second ghost row of this board's own.
            iOSCalendarAddItemRow(
                accessibilityLabel: "Add task to \(title)",
                action: onAddTask
            )
            .padding(.horizontal, 4)
            .padding(.top, 10)

            // The card stack scrolls inside the column, as `KanbanColumnScroll` does on macOS. The
            // board only scrolled horizontally before, so anything past the bottom of a tall column
            // was unreachable.
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(tasks) { task in
                        boardCard(task)
                    }

                    if !tasks.isEmpty {
                        columnEndDropSlot
                    }

                    // **Inside the scroller, after the cards** ([[T-9611]] settled that for the
                    // Calendar Board's column: a footer pinned under the scroller is a second
                    // thing competing for the column's height, and macOS puts its toggle in the
                    // card stack). Same `LazyVStack`, so an expanded Completed section scrolls
                    // with the work above it.
                    completedFooter
                        .padding(.top, tasks.isEmpty ? 0 : 2)
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
        // A card held over the column draws the same ring: it is the one emphasis this column has,
        // and a second treatment for "this is where it lands" would be a second layer.
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                .strokeBorder(isHighlighted || isCardDropTargeted ? dotColor : Color.clear, lineWidth: 2)
                .allowsHitTesting(false)
        }
        // The whole column, header to foot, so an empty column — the one a move most often wants —
        // is a target and not only the space under its cards.
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { items, _ in
            onDropCard(items, nil)
        } isTargeted: { isCardDropTargeted = $0 }
    }

    /// **One card, for both stacks: the open cards and the finished ones behind the Completed
    /// toggle** ([[T-15622]]). The finished half drew the card and its drag only, so a card set down
    /// on a finished one fell through to the column body and went to the column's end, where every
    /// Mac finished card is `KanbanDraggableCard` with `onDropBefore`. One builder rather than a
    /// second copy of the chain below, so the two stacks cannot drift apart again.
    private func boardCard(_ task: AppTask) -> some View {
        // Scoped to one list already — the same reason `iOSTaskListRow` drops its
        // container, and the same knob macOS's `KanbanCard` uses.
        iOSBoardTaskCard(task: task, showsContainerChip: false, todayKey: todayKey)
            // The source half of [[T-8183]]: the payload the Calendar Board's card
            // and the task row already offer (`TaskDragPayload`), not a board-own
            // spelling. Outside the card, after its context menu, as both of those
            // put it — see `iOSBoardTaskCard`'s note on how the two share a press.
            .draggable(TaskDragPayload.string(for: task.id))
            // [[T-8271]]: the card is a drop target too, so a card set down on it
            // lands in front of it — macOS's `onDropBefore`, through the same write.
            .overlay(alignment: .top) {
                if dropTargetTaskID == task.id {
                    Rectangle()
                        .fill(Theme.blue)
                        .frame(height: 2)
                        .allowsHitTesting(false)
                }
            }
            .dropDestination(for: String.self) { items, _ in
                onDropCard(items, task)
            } isTargeted: { isOver in
                if isOver { dropTargetTaskID = task.id }
                else if dropTargetTaskID == task.id { dropTargetTaskID = nil }
            }
    }

    /// **The end of the column's open cards, as a drop target** ([[T-16503]]). Drawn only under a
    /// card: an empty column's body already files a card at its end, and the card dragged can only
    /// be from another column. The insertion line is a card's (`boardCard(_:)`), drawn where the
    /// card will land -- under the last one.
    private var columnEndDropSlot: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: iOSListKanbanColumnEndSlotHeight)
            .contentShape(Rectangle())
            .overlay(alignment: .top) {
                if isColumnEndDropTargeted {
                    Rectangle()
                        .fill(Theme.blue)
                        .frame(height: 2)
                        .allowsHitTesting(false)
                }
            }
            .dropDestination(for: String.self) { items, _ in
                onDropAtColumnEnd(items)
            } isTargeted: { isColumnEndDropTargeted = $0 }
            .accessibilityHidden(true)
    }

    /// **The "Completed N" row this column closes with** ([[T-9837]]).
    ///
    /// The shape is the iOS Calendar Board day column's, which is the in-app precedent and is
    /// already the Mac's look through the one shared label ([[T-9835]]): the green count right
    /// after the word on a hairlined surface plate, with iOS's 44pt touch floor the only platform
    /// input. Drawing it a second way here is exactly what that ticket took out of the tree.
    ///
    /// Nothing is drawn when the column has no finished work, so a board of open columns looks
    /// precisely as it did.
    @ViewBuilder
    private var completedFooter: some View {
        if !completedTasks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(.snappy(duration: 0.16)) {
                        isCompletedCollapsed.toggle()
                    }
                } label: {
                    CadenceBoardCompletedToggleLabel(
                        count: completedTasks.count,
                        isExpanded: !isCompletedCollapsed,
                        minimumHeight: 44
                    )
                }
                .buttonStyle(.iosPressable)
                // [[T-9833]]: the disclosure states Expanded/Collapsed, in the words
                // `iOSTaskGroupSection`'s Completed heading uses and macOS's
                // `KanbanCompletedTasksToggle` has read since [[T-7081]].
                .accessibilityValue(isCompletedCollapsed ? "Collapsed" : "Expanded")

                if !isCompletedCollapsed {
                    VStack(spacing: 8) {
                        ForEach(completedTasks) { task in
                            // The same card the open half draws, at the same width and with the
                            // same container chip suppressed -- a finished card is not a different
                            // kind of card, which is the Mac's position too. [[T-15622]]: and the
                            // same drop target with the same insertion line, as every Mac finished
                            // card is (`completedTaskCards`' `KanbanDraggableCard`).
                            boardCard(task)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }
}

struct iOSListLinksPanel: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query(sort: \SavedLink.order) private var allLinks: [SavedLink]
    let area: Area?
    let project: Project?
    /// [[T-10056]]: the Mac's form state, so every close — the header's Cancel, a save — discards
    /// the draft through one `cancel()`. Three loose `@State`s here let the header hide the form
    /// and keep what was typed, so reopening it brought the abandoned title and URL back.
    @State private var addForm = SavedLinkAddForm()
    /// What the store refused, in the same two sentences macOS's list shows. Before T-507 the two
    /// writes here were `try?` and this property did not exist, so a refused commit was reported
    /// by the form closing.
    @State private var actionError: String?

    @State private var linkToDelete: SavedLink?

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
                    title: addForm.headerTitle,
                    systemImage: addForm.headerSymbol,
                    role: addForm.isOpen ? .ghost : .secondary,
                    size: .compact
                ) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        _ = addForm.toggle()
                    }
                    actionError = nil
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if addForm.isOpen {
                iOSAddLinkForm(
                    title: $addForm.title,
                    url: $addForm.url,
                    save: saveForm
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }

            // Above the hairline rather than inside the add form: the delete reports here too, and
            // a swipe-to-delete happens with the form closed.
            if let actionError {
                Text(actionError)
                    .cadenceFont(.controlLabel)
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
                                linkToDelete = link
                            } label: {
                                Label(CadenceSavedLinkRowMenu.deleteTitle, systemImage: CadenceSavedLinkRowMenu.deleteSystemImage)
                            }
                            // [[T-7259]]: the swipe's spelling of the menu's Edit Link.
                            Button {
                                beginEditing(link)
                            } label: {
                                Label(CadenceSavedLinkRowMenu.editTitle, systemImage: CadenceSavedLinkRowMenu.editSystemImage)
                            }
                            .tint(Theme.blue)
                        }
                        // [[T-10057]]: the Mac row's right-click menu, item for item and in its
                        // order. Delete asks through the same `linkToDelete` as the swipe.
                        .contextMenu {
                            Button {
                                open(link)
                            } label: {
                                Label(CadenceSavedLinkRowMenu.openTitle, systemImage: CadenceSavedLinkRowMenu.openSystemImage)
                            }
                            Button {
                                UIPasteboard.general.string = link.url
                            } label: {
                                Label(CadenceSavedLinkRowMenu.copyTitle, systemImage: CadenceSavedLinkRowMenu.copySystemImage)
                            }
                            Button {
                                beginEditing(link)
                            } label: {
                                Label(CadenceSavedLinkRowMenu.editTitle, systemImage: CadenceSavedLinkRowMenu.editSystemImage)
                            }
                            Divider()
                            Button(role: .destructive) {
                                linkToDelete = link
                            } label: {
                                Label(CadenceSavedLinkRowMenu.deleteTitle, systemImage: CadenceSavedLinkRowMenu.deleteSystemImage)
                            }
                            // [[T-11752]]: a red glyph beside the red title, not the root's blue.
                            .cadenceDestructiveMenuRow()
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.bg)
        .iOSSavedLinkDeletion(link: $linkToDelete, perform: delete)
    }

    /// [[T-7259]]: the add form, reopened on this link -- the Mac row's Edit Link, through the
    /// same `SavedLinkAddForm.beginEditing`.
    private func beginEditing(_ link: SavedLink) {
        withAnimation(.easeInOut(duration: 0.18)) {
            addForm.beginEditing(id: link.id, title: link.title, url: link.url)
        }
        actionError = nil
    }

    /// The form's Save: an edit when it was opened on a link, an add otherwise -- the Mac's
    /// `LinksView.saveForm()`.
    private func saveForm() {
        if addForm.isEditing {
            actionError = CadenceSavedLinkPersistence.saveEdit(&addForm, among: links, in: modelContext)
        } else {
            addLink()
        }
    }

    private func addLink() {
        let title = CadenceTitleNormalization.normalized(addForm.title)
        // Trim, blank-check and scheme come from the shared helper. The three lines that used to
        // sit here were a copy of macOS's, defect included: `hasPrefix` is case-sensitive, so a
        // pasted `HTTPS://example.com` was stored as `https://HTTPS://example.com` (T-509).
        guard let url = CadenceSavedLinkURL.normalized(addForm.url) else { return }

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
        addForm.cancel()
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

extension View {
    func iOSSavedLinkDeletion(link: Binding<SavedLink?>, perform: @escaping (SavedLink) -> Void) -> some View {
        modifier(iOSSavedLinkDeletionModifier(link: link, perform: perform))
    }
}

private struct iOSSavedLinkDeletionModifier: ViewModifier {
    @Binding var link: SavedLink?
    let perform: (SavedLink) -> Void

    private var isPresented: Binding<Bool> {
        Binding(get: { link != nil }, set: { if !$0 { link = nil } })
    }

    func body(content: Content) -> some View {
        content.alert(CadenceSavedLinkPersistence.deleteConfirmationTitle, isPresented: isPresented, presenting: link) { selected in
            Button("Delete", role: .destructive) {
                perform(selected)
                link = nil
            }
            Button("Cancel", role: .cancel) { link = nil }
        } message: { selected in
            Text(CadenceSavedLinkPersistence.deleteConfirmationMessage(title: selected.title))
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
                title: CadenceSavedLinkPersistence.saveActionTitle,
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.cadenceTypographyScaling) private var scaling
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .cadenceFont(.bodyText, weight: .medium)
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 12)
            .frame(minHeight: CadenceTypeScale.height(44, holding: .bodyText, at: dynamicTypeSize, scaling: scaling))
            .background(Theme.surfaceElevated.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
    }
}

private struct iOSLinkRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.cadenceTypographyScaling) private var scaling
    let link: SavedLink

    var body: some View {
        let wraps = iOSTaskPageTypographyMetrics.stacksControls(at: dynamicTypeSize, scaling: scaling)
        let layout = wraps ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
        layout {
            iOSListIconBadge(icon: "link", colorHex: Theme.blueHex)

            VStack(alignment: .leading, spacing: 3) {
                Text(CadenceTitleNormalization.display(link.title, fallback: link.url))
                    .cadenceFont(.bodyText, weight: .semibold)
                    .foregroundStyle(Theme.text)
                    .lineLimit(wraps ? nil : 1)
                    .fixedSize(horizontal: false, vertical: wraps)

                Text(link.url)
                    .cadenceFont(.metadata)
                    .foregroundStyle(Theme.subdued)
                    .lineLimit(wraps ? nil : 1)
                    .fixedSize(horizontal: false, vertical: wraps)
            }

            if !wraps { Spacer(minLength: 8) }

            Image(systemName: CadenceSavedLinkRowMenu.openSystemImage)
                .cadenceFont(.metadata, base: 11, weight: .bold)
                .foregroundStyle(Theme.dim)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}
#endif
