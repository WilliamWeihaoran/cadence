#if os(macOS)
import SwiftUI
import SwiftData
import AppKit

/// **The** macOS header row: an eyebrow, a title, and optionally a count and one trailing control.
///
/// It replaces four of these. `DesktopPageHeader`, `PanelHeader`, `CommitmentPageHeader` and
/// `CadenceSettingsHeader` each drew the same idea and had drifted into three title spellings, three
/// identity tiles (32/15, 32/13 and 42/17 — three glyph ratios for one shape) and three tile fill
/// opacities. The three other names survive as thin wrappers over this; none of them decides
/// anything about appearance any more.
///
/// **No identity tile.** The rounded glyph square this used to lead with named the page you were
/// already looking at — the same argument as the deleted subtitle, one row higher — and the user
/// asked for it dropped on every page, on both platforms. The `systemImage` parameter is *deleted*
/// rather than left inert: the settings header, the list header and every feature page passed one,
/// and a parameter that still compiles and draws nothing is how `subtitle` survived three separate
/// removals. `CommitmentIconTile` is untouched — tiles inside rows, cards and pickers are not page
/// identity and keep doing their job.
///
/// What survives as a parameter is `role`, and only that: a column inside a split legitimately
/// speaks more quietly than a whole screen. Everything else is `CadencePageHeaderMetrics`, which is
/// in `Shared/` outside any platform guard so the ramp can be pinned by a test — and so this and
/// `iOSPageHeader` are demonstrably drawing from one decision rather than two that happen to agree.
///
/// **No subtitle.** A line under "All Tasks" explaining that All Tasks is where you review tasks
/// describes the page you are already looking at. Empty states, search results and picker rows are
/// the documented exceptions and none of them is a page header.
///
/// Two things here are deliberately *not* `iOSPageHeader`'s:
/// - **The count sits beside the title, not at the trailing edge.** iOS moved it to the trailing
///   edge because a phone header is 340pt wide and the two ends read as one row. A macOS page
///   header is the window less the sidebar — 1100pt and up — and a number parked at x=1150 does
///   not read as the count of a title at x=18.
/// - **The count takes the page tint**, so an area's tally is the area's colour. This is now the
///   *only* thing the tint colours, which is what keeps a list's own `colorHex` on its own page
///   after the tile went; `iOSPageHeader` was hardcoding `Theme.blue` and ignoring its `color`
///   parameter, and now reads the tint as well.
struct DesktopPageHeader<TrailingContent: View>: View {
    /// What this row is the top of. See `CadencePageHeaderRole`.
    let role: CadencePageHeaderRole
    let eyebrow: String?
    /// A second, sentence-case clause after the eyebrow, separated by a middle dot — Today's day
    /// summary. Shared with `iOSPageHeader.eyebrowDetail`, including the rule that it is the half
    /// that gives way: the eyebrow proper keeps the layout priority, so a squeezed column truncates
    /// "· 3 timed" before "WEDNESDAY, AUGUST 19".
    let eyebrowDetail: String?
    let title: String
    let count: Int?
    /// The page's accent. **The count capsule is now its only renderer**, which is deliberate and
    /// is why the parameter survived the tile: on a list's header `tint` is the user's own
    /// `colorHex`, so dropping it with the glyph would have taken a list's identity colour off its
    /// own page. `iOSPageHeader` hardcoded `Theme.blue` here and ignored its `color` parameter,
    /// which is the same fork the other way round; both read the header's tint now.
    let tint: Color
    /// `false` where the host supplies the gutter — a settings card, or a header that pads this
    /// row and a controls row underneath it as one block.
    let padded: Bool
    /// `nil` where the host paints its own plate. Today's three columns do.
    let background: Color?
    /// `false` where the row is a *fragment* of a wider row its host is assembling — Today's
    /// columns put their own controls beside this header, so it must stay intrinsically sized
    /// rather than claim the width with a `Spacer` and leave the host's own one nothing to do.
    let spreads: Bool
    @ViewBuilder let trailingContent: TrailingContent

    init(
        role: CadencePageHeaderRole = .page,
        eyebrow: String? = nil,
        eyebrowDetail: String? = nil,
        title: String,
        count: Int? = nil,
        tint: Color = Theme.blue,
        padded: Bool = true,
        background: Color? = Theme.surface,
        spreads: Bool = true,
        @ViewBuilder trailingContent: () -> TrailingContent = { EmptyView() }
    ) {
        self.role = role
        self.eyebrow = eyebrow
        self.eyebrowDetail = eyebrowDetail
        self.title = title
        self.count = count
        self.tint = tint
        self.padded = padded
        self.background = background
        self.spreads = spreads
        self.trailingContent = trailingContent()
    }

    private var metrics: CadencePageHeaderMetrics {
        CadencePageHeaderMetrics.metrics(role: role, surface: .desktop)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                if eyebrow != nil || eyebrowDetail != nil {
                    eyebrowLine
                }

                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text(title)
                        .font(.system(size: metrics.titleSize, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)

                    // A zero is chrome: the absence of a badge is the zero state, the same
                    // rule the sidebar counts follow.
                    if let count, count > 0 {
                        countBadge(count)
                    }
                }
            }

            if spreads {
                Spacer(minLength: 16)
                trailingContent
            }
        }
        .padding(.horizontal, padded ? metrics.horizontalPadding : 0)
        .padding(.top, padded ? metrics.topPadding : 0)
        .padding(.bottom, padded ? metrics.bottomPadding : 0)
        // ViewBuilder form rather than `.background(background)`: an `Optional<Color>` satisfies
        // the deprecated `background(_ view:)` overload rather than the `ShapeStyle` one, which
        // compiles and is not what this means.
        .background { if let background { background } }
    }

    /// Same two runs, same separator and same give-way rule as `iOSPageHeader.eyebrowLine`.
    private var eyebrowLine: some View {
        HStack(spacing: 6) {
            if let eyebrow {
                SectionEyebrowLabel(text: eyebrow)
                    .lineLimit(1)
                    .layoutPriority(1)
            }

            if let eyebrowDetail, !eyebrowDetail.isEmpty {
                Text("· \(eyebrowDetail)")
                    .font(.system(size: metrics.eyebrowSize, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }
        }
    }

    private func countBadge(_ count: Int) -> some View {
        Text("\(count)")
            .font(.system(size: metrics.countSize, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, metrics.countPaddingH)
            .padding(.vertical, metrics.countPaddingV)
            .background(tint.opacity(CadencePageHeaderMetrics.countFillOpacity))
            .clipShape(Capsule())
    }
}

struct DesktopControlBar<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 8) {
            content
            Spacer(minLength: 0)
        }
        .padding(.horizontal, CadenceDesktopMetrics.pageHorizontalPadding)
        .padding(.vertical, 9)
        .background(Theme.surface.opacity(0.92))
    }
}

/// The state a control-bar pill can be in. The fill ramp is
/// `clear -> Theme.surfaceElevated -> Theme.surfaceHighlight`; nothing here draws a border or an
/// accent tint, so a bar of mixed controls (tabs, sort, order, boolean filters) reads as one family.
enum CadenceQuietPillState {
    /// Unselected tab: bare text, no fill until hovered.
    case quiet
    /// Always present but carrying no on/off state (sort field, sort direction).
    case resting
    /// Selected tab or toggled-on filter.
    case active
}

enum CadenceQuietPillMetrics {
    static let cornerRadius = CadenceDesktopMetrics.controlCornerRadius
    static let horizontalPadding: CGFloat = 10
    /// Cluster spacing for a row of tabs. Deliberately tight: the selected pill's fill is what
    /// separates the tabs, so a wide gap would read as unrelated buttons rather than one control.
    static let clusterSpacing: CGFloat = 2
}

/// Shared chrome for every control in a page control bar: exactly one neutral fill layer at one
/// radius, no border, no accent. State is carried by fill depth and label brightness.
struct CadenceQuietPill: ViewModifier {
    let state: CadenceQuietPillState
    let isHovered: Bool

    private var fill: Color {
        switch state {
        case .quiet:   return isHovered ? Theme.surfaceElevated : .clear
        case .resting: return isHovered ? Theme.surfaceHighlight : Theme.surfaceElevated
        case .active:  return Theme.surfaceHighlight
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: CadenceQuietPillMetrics.cornerRadius, style: .continuous)
    }

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, CadenceQuietPillMetrics.horizontalPadding)
            .frame(height: CadenceDesktopMetrics.compactControlHeight)
            .background(shape.fill(fill))
            .contentShape(shape)
    }
}

/// A button wearing `CadenceQuietPill`. It owns the hover state so call sites cannot accidentally
/// stack a second hover background at a different radius on top of the pill's.
///
/// Uses `.plain` rather than `.cadencePlain` on purpose: that style paints its own blue fill and
/// stroke at its own radius, which is the accent-bordered look this vocabulary replaces.
struct CadenceQuietPillButton<Label: View>: View {
    let state: CadenceQuietPillState
    let action: () -> Void
    @ViewBuilder let label: Label

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            label.modifier(CadenceQuietPill(state: state, isHovered: isHovered))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// The app's one tab-bar item. Text only — no icon, no accent dot, no segmented-control trough.
/// The selected tab is marked by a neutral `Theme.surfaceHighlight` fill plus a brighter label.
///
/// Both tab bars (All Tasks list/kanban, list-detail Tasks/Kanban/Notes/...) render through this,
/// so they are literally the same control instead of two idioms for the same job.
struct CadenceQuietTabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        CadenceQuietPillButton(state: isSelected ? .active : .quiet, action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Theme.text : Theme.dim)
                // The label sits in a fixed-height frame, so a wrap would overflow the pill rather
                // than grow it. Under compression this must truncate, never wrap.
                .lineLimit(1)
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The page-level "new task" affordance, on every task page that has one: All Tasks, Inbox, and
/// an area/project's Tasks tab. It opens the full `CreateTaskSheet`, because a page — unlike a
/// board column — does not answer "where does this go" on the user's behalf.
///
/// It is one view rather than three copies, and it replaced the "New Task" header pill that All
/// Tasks and Inbox used to carry: two shapes for one action, differing only by which screen you
/// happened to be on.
///
/// Callers place it themselves with `.floatingNewTaskButton()`, which pins it to the page's
/// bottom-trailing corner. Pages that use it should leave a bottom safe-area inset so the last
/// row can still be reached under it.
struct FloatingNewTaskButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(Theme.onColor)
                .frame(width: 54, height: 54)
                .background(Theme.blue)
                .clipShape(Circle())
                .shadow(color: Theme.blue.opacity(0.32), radius: 18, x: 0, y: 8)
        }
        .buttonStyle(.cadencePlain)
        .padding(.trailing, 24)
        .padding(.bottom, 24)
        .accessibilityLabel("New Task")
    }
}

extension View {
    /// Overlays `FloatingNewTaskButton` in the page's bottom-trailing corner.
    func floatingNewTaskButton(action: @escaping () -> Void) -> some View {
        overlay(alignment: .bottomTrailing) {
            FloatingNewTaskButton(action: action)
        }
    }
}

struct RootSidebarToggleButton: View {
    let isSidebarHidden: Bool
    let action: () -> Void

    var body: some View {
        CadenceIconButton(
            systemImage: isSidebarHidden ? "sidebar.left" : "sidebar.leading",
            accessibilityLabel: isSidebarHidden ? "Show Sidebar (Cmd+O)" : "Hide Sidebar (Cmd+O)",
            tint: Theme.blue,
            size: CadenceDesktopMetrics.compactControlHeight,
            iconSize: 12,
            action: action
        )
    }
}

struct RootTimelineSidebarPane: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Today Timeline")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                Spacer()
                CadenceIconButton(
                    systemImage: "xmark",
                    accessibilityLabel: "Close timeline",
                    size: 24,
                    iconSize: 10,
                    action: onClose
                )
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(Theme.surface)

            Divider().background(Theme.borderSubtle)

            // Headerless, because the title six lines up has already said "Timeline" and the rule
            // above is this pane's own. `SchedulePanel`'s three other hosts have nothing naming
            // them, so they keep their headers — see `SchedulePanelPresentation.hosted` (T-615).
            SchedulePanel(presentation: .hosted)
                .frame(minWidth: 320, idealWidth: 360, maxWidth: 420)
        }
        .frame(width: 360)
        .frame(maxHeight: .infinity)
        .background(Theme.surface)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Theme.borderSubtle.opacity(0.85))
                .frame(width: 1)
        }
        .shadow(color: Theme.sidePanelShadow, radius: 18, y: 8)
    }
}

struct TaskCreationLayerView: View {
    @Environment(TaskCreationManager.self) private var taskCreationManager

    var body: some View {
        if taskCreationManager.isPresented {
            ZStack {
                Theme.scrim
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        clearAppEditingFocus()
                        taskCreationManager.dismiss()
                    }

                CreateTaskPanelSurface(seed: taskCreationManager.seed)
                    .onTapGesture {
                        // Prevent outside tap handler from firing when clicking inside the panel.
                    }
            }
            .transition(.opacity)
            .zIndex(10)
        }
    }
}

struct SuccessToastLayerView: View {
    @Environment(TaskCreationManager.self) private var taskCreationManager

    var body: some View {
        if taskCreationManager.showSuccessToast {
            VStack {
                Spacer()
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(Theme.green)
                    Text("Task Created")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.text)
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 20)
                .cadenceCard(
                    background: Theme.surfaceElevated.opacity(0.98),
                    cornerRadius: Theme.radiusPanel,
                    shadowRadius: 30,
                    shadowY: 12
                )
                .padding(.bottom, 36)
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .zIndex(30)
        }
    }
}

struct DeleteConfirmationLayerView: View {
    @Environment(DeleteConfirmationManager.self) private var deleteConfirmationManager

    var body: some View {
        if let deleteRequest = deleteConfirmationManager.request {
            DeleteConfirmationOverlay(
                title: deleteRequest.title,
                message: deleteRequest.message,
                confirmLabel: deleteRequest.confirmLabel,
                // T-376. A refused delete leaves the overlay standing and puts the reason here, so
                // the reappearing row is explained rather than merely surprising.
                failureNotice: deleteConfirmationManager.failureNotice,
                onConfirm: { deleteConfirmationManager.confirm() },
                onCancel: { deleteConfirmationManager.cancel() }
            )
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
            .zIndex(20)
        }
    }
}

struct DatePickerLayerView: View {
    @Environment(HoveredTaskDatePickerManager.self) private var hoveredTaskDatePickerManager
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        if let request = hoveredTaskDatePickerManager.request {
            HoveredTaskDatePickerOverlay(
                request: request,
                onUpdateDate: { hoveredTaskDatePickerManager.request?.selectedDate = $0 },
                onConfirm: { hoveredTaskDatePickerManager.confirm(in: modelContext) },
                onClear: { hoveredTaskDatePickerManager.clearDate(in: modelContext) },
                onCancel: { hoveredTaskDatePickerManager.cancel() }
            )
            .transition(.opacity.combined(with: .scale(scale: 0.985)))
            .zIndex(21)
        }
    }
}

struct GlobalSearchLayerView: View {
    @Environment(GlobalSearchManager.self) private var globalSearchManager
    let onSelect: (GlobalSearchResult) -> Void

    var body: some View {
        if globalSearchManager.isPresented {
            GlobalSearchOverlay(
                onSelect: onSelect,
                onDismiss: { globalSearchManager.dismiss() }
            )
            .transition(.opacity.combined(with: .scale(scale: 0.985)))
            .zIndex(40)
        }
    }
}

struct HoveredTaskDatePickerOverlay: View {
    let request: HoveredTaskDatePickerManager.Request
    let onUpdateDate: (Date) -> Void
    let onConfirm: () -> Void
    let onClear: () -> Void
    let onCancel: () -> Void
    @State private var pickerViewMonth: Date

    init(
        request: HoveredTaskDatePickerManager.Request,
        onUpdateDate: @escaping (Date) -> Void,
        onConfirm: @escaping () -> Void,
        onClear: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.request = request
        self.onUpdateDate = onUpdateDate
        self.onConfirm = onConfirm
        self.onClear = onClear
        self.onCancel = onCancel
        var comps = Calendar.current.dateComponents([.year, .month], from: request.selectedDate)
        comps.day = 1
        _pickerViewMonth = State(initialValue: Calendar.current.date(from: comps) ?? request.selectedDate)
    }

    var body: some View {
        ZStack {
            Theme.scrim
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onCancel)

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill((request.kind == .doDate ? Theme.blue : Theme.amber).opacity(0.16))
                                .frame(width: 40, height: 40)
                            Image(systemName: request.kind == .doDate ? "calendar" : "calendar.badge.exclamationmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(request.kind == .doDate ? Theme.blue : Theme.amber)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(request.kind.title)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(Theme.text)
                            // **T-513.** Same label as every other surface that names a
                            // blank-titled task; this one read "Untitled task", lower-cased.
                            Text(TaskTitleSupport.displayTitle(request.task.title))
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.dim)
                                .lineLimit(2)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(request.kind == .doDate ? "Choose when you want to do this task." : "Choose when this task is due.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.dim)

                        MonthCalendarPanel(
                            selection: Binding(
                                get: { request.selectedDate },
                                set: { newDate in
                                    onUpdateDate(newDate)
                                    var comps = Calendar.current.dateComponents([.year, .month], from: newDate)
                                    comps.day = 1
                                    pickerViewMonth = Calendar.current.date(from: comps) ?? newDate
                                }
                            ),
                            viewMonth: $pickerViewMonth,
                            isOpen: Binding(
                                get: { true },
                                set: { _ in }
                            ),
                            inlineStyle: true
                        )
                    }
                }
                .padding(20)

                Divider().background(Theme.borderSubtle)

                HStack(spacing: 10) {
                    CadenceActionButton(
                        title: "Clear",
                        role: .destructive,
                        size: .regular,
                        minWidth: 74
                    ) {
                        onClear()
                    }

                    Spacer()

                    CadenceActionButton(
                        title: "Cancel",
                        role: .secondary,
                        size: .regular,
                        tint: Theme.dim,
                        minWidth: 96,
                        shortcut: .cancelAction
                    ) {
                        onCancel()
                    }

                    CadenceActionButton(
                        title: "Apply",
                        role: .primary,
                        size: .regular,
                        tint: request.kind == .doDate ? Theme.blue : Theme.amber,
                        minWidth: 96,
                        shortcut: .defaultAction
                    ) {
                        onConfirm()
                    }
                }
                .padding(20)
            }
            .frame(width: 360)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusPanel)
                    .fill(Theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusPanel).strokeBorder(Theme.borderSubtle.opacity(0.4)))
            )
            .shadow(color: Theme.overlayCardShadow, radius: 24, x: 0, y: 14)
        }
    }
}

struct DeleteConfirmationOverlay: View {
    let title: String
    let message: String
    let confirmLabel: String
    /// Shown in place of nothing when the confirmed delete was refused and rolled back (T-376).
    var failureNotice: String?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Theme.scrim
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onCancel)

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Theme.red.opacity(0.14))
                                .frame(width: 40, height: 40)
                            Image(systemName: "trash.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.red)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(title)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(Theme.text)
                            Text(message)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.dim)
                                .fixedSize(horizontal: false, vertical: true)
                            if let failureNotice {
                                CadenceInlineFailureNotice(text: failureNotice)
                            }
                        }
                    }
                }
                .padding(20)

                Divider().background(Theme.borderSubtle)

                HStack(spacing: 10) {
                    Spacer()
                    CadenceActionButton(
                        title: "Cancel",
                        role: .secondary,
                        size: .regular,
                        tint: Theme.dim,
                        minWidth: 96,
                        shortcut: .cancelAction
                    ) {
                        onCancel()
                    }

                    CadenceActionButton(
                        title: confirmLabel,
                        role: .primary,
                        size: .regular,
                        tint: Theme.red,
                        minWidth: 96,
                        shortcut: .defaultAction
                    ) {
                        onConfirm()
                    }
                }
                .padding(20)
            }
            .frame(width: 420)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusPanel)
                    .fill(Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusPanel)
                            .strokeBorder(Theme.borderSubtle, lineWidth: 1)
                    )
            )
            .shadow(color: Theme.overlayCardShadow, radius: 28, x: 0, y: 16)
        }
    }
}

/// **The** Tasks page: All Tasks and Inbox, two axes, one implementation.
///
/// ```
/// Tasks
/// ├─ view:  All | Inbox      (CadenceTasksPageScope)
/// └─ mode:  List | Kanban
/// ```
///
/// The two were separate sidebar rows and separate pages over one universe of work. The axes are
/// deliberately orthogonal — all four combinations exist — because the board's columns *are* lists
/// and Inbox is one of them, so "the Inbox board" is the same board with one column rather than a
/// special case. The alternative, hiding the mode switcher under one view, makes a control appear
/// and disappear as you cross a filter.
///
/// **`.allTasks` and `.inbox` both survive as destinations.** They are distinct, deep-linkable, and
/// named separately by the command palette, the iPhone's Tasks segments and the widgets; collapsing
/// them would have been a far wider change than the sidebar asked for. What merged is the row and
/// the page, not the vocabulary.
struct TasksPageView: View {
    private enum Mode: String, CaseIterable {
        case list = "List"
        case kanban = "Kanban"
    }

    /// Non-`nil` when the selection named a view outright — the command palette's "Inbox" entry,
    /// or a deep link that resolved to Inbox. The sidebar's own row passes `nil`, which reopens
    /// whichever view you last left the page on (`tasksPageScope`, below — a *page* preference,
    /// not a root one).
    ///
    /// **Nothing restores a selection when the app launches**, so this is `nil` on the first frame
    /// of every launch. `macOSRootView.selection` is plain `@State` seeded to `.today`, with no
    /// `SceneStorage` or `AppStorage` behind it anywhere; only navigation afterwards — the palette,
    /// a deep link, a sidebar row — can make this non-`nil`. That is the intended contract, not an
    /// omission (T-352).
    ///
    /// This sentence used to say an `.inbox` selection was restored when the app relaunched,
    /// describing a mechanism that has never existed. A comment asserting machinery the code does
    /// not have is worse than no comment at all, because it stops the next reader looking. Pinned
    /// by `CadenceRootSelectionLaunchContractTests`, which forbids the old claim by its words.
    var requestedScope: CadenceTasksPageScope?

    @AppStorage("tasksPageScope") private var scopeRaw = CadenceTasksPageScope.defaultScope.rawValue
    /// Still `allTasksViewMode`. The key is the *presentation*, which did not change meaning, and
    /// renaming it would strand every existing user on the default — the hazard
    /// `CadenceNotesEditorPreferences.purgeRetiredKeys()` exists to clean up after.
    @AppStorage("allTasksViewMode") private var modeRaw: String = Mode.list.rawValue

    // The two views keep their own sort/order/group preferences, under the keys each page already
    // wrote. They are answering different questions — Inbox is a hand-ordered capture list, where
    // `.custom` and drag-to-reorder are the point, and All Tasks is date-first — so folding them
    // onto one key would have picked a winner *and* discarded whichever preference the user had
    // stored on the other page.
    @AppStorage("allTasksSortField") private var allSortField: TaskSortField = .date
    @AppStorage("allTasksSortDirection") private var allSortDirection: TaskSortDirection = .ascending
    @AppStorage("allTasksGroupingMode") private var allGroupingMode: TaskGroupingMode = .byDate
    @AppStorage("inboxSortField") private var inboxSortField: TaskSortField = .custom
    @AppStorage("inboxSortDirection") private var inboxSortDirection: TaskSortDirection = .ascending
    @AppStorage("inboxGroupingMode") private var inboxGroupingMode: TaskGroupingMode = .none

    @Environment(TaskCreationManager.self) private var taskCreationManager
    @Environment(RemindersManager.self) private var remindersManager
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]

    private var scope: CadenceTasksPageScope { CadenceTasksPageScope.resolved(scopeRaw) }
    private var mode: Mode { Mode(rawValue: modeRaw) ?? .list }

    private var sortField: Binding<TaskSortField> {
        scope == .inbox ? $inboxSortField : $allSortField
    }

    private var sortDirection: Binding<TaskSortDirection> {
        scope == .inbox ? $inboxSortDirection : $allSortDirection
    }

    private var groupingMode: Binding<TaskGroupingMode> {
        scope == .inbox ? $inboxGroupingMode : $allGroupingMode
    }

    /// The same number the sidebar's Tasks row shows, plus — in the Inbox view — the Apple
    /// Reminders the strip below is about to draw. Inbox's header has always counted those; they
    /// are items in the inbox whether or not Cadence owns them.
    private var headerCount: Int {
        switch scope {
        case .all:
            return CadenceTaskQuerySupport.openTaskCount(from: allTasks.filter(\.isInActiveContainer))
        case .inbox:
            return CadenceTaskQuerySupport.openTaskCount(from: CadenceTaskQuerySupport.inboxTasks(from: allTasks))
                + remindersManager.reminders.count
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // No trailing action: the page's "new task" affordance is the floating circle over the
            // list below, the same one an area/project's Tasks tab has always had.
            DesktopPageHeader(
                eyebrow: "Tasks",
                title: scope.pageTitle,
                count: headerCount
            )

            Divider().background(Theme.borderSubtle)

            DesktopControlBar {
                HStack(spacing: CadenceQuietPillMetrics.clusterSpacing) {
                    ForEach(CadenceTasksPageScope.allCases) { option in
                        CadenceQuietTabButton(title: option.title, isSelected: scope == option) {
                            scopeRaw = option.rawValue
                        }
                    }
                }

                // The two switchers are separate clusters, not one seven-wide strip: they are
                // different questions — which tasks, and drawn how.
                HStack(spacing: CadenceQuietPillMetrics.clusterSpacing) {
                    ForEach(Mode.allCases, id: \.self) { viewMode in
                        CadenceQuietTabButton(title: viewMode.rawValue, isSelected: mode == viewMode) {
                            modeRaw = viewMode.rawValue
                        }
                    }
                }
                .padding(.leading, CadenceQuietPillMetrics.clusterSpacing * 2)

                Spacer(minLength: 12)

                // Sort and order serve the **kanban** board on this page too, and the board is not
                // one of `CadenceTaskSurface`'s cases — so the gate asks the shared table only
                // about the list mode it does name (T-290).
                if mode == .kanban || CadenceTaskSurfaceOptions.options(for: scope.surface).showsSort {
                    CadenceEnumPickerBadge(title: "Sort", selection: sortField)
                    CadenceEnumPickerBadge(title: "Order", selection: sortDirection)
                }
                if mode == .list {
                    CadenceEnumPickerBadge(title: "Group", selection: groupingMode)
                }
            }

            Divider().background(Theme.borderSubtle)

            Group {
                switch mode {
                case .list:
                    TasksListView(
                        scope: scope,
                        sortField: sortField.wrappedValue,
                        sortDirection: sortDirection.wrappedValue,
                        groupingMode: groupingMode.wrappedValue
                    )
                    // The inset keeps the last row reachable from under the floating button.
                    .safeAreaInset(edge: .bottom) {
                        Color.clear.frame(height: 72)
                    }
                    .floatingNewTaskButton {
                        taskCreationManager.present()
                    }
                case .kanban:
                    // No page-level button here, exactly as on a list's Kanban tab: every column
                    // has its own ghost row, and each of those knows which list the card lands in.
                    TaskListsKanbanView(
                        scope: scope,
                        sortField: sortField.wrappedValue,
                        sortDirection: sortDirection.wrappedValue
                    )
                }
            }
        }
        .background(Theme.bg)
        .onChange(of: requestedScope, initial: true) { _, requested in
            guard let requested else { return }
            scopeRaw = requested.rawValue
        }
    }
}
#endif
