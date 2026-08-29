#if os(iOS)
import SwiftUI

/// One `NavigationPath` per tab.
///
/// Each stays **type-erased**. A `NavigationStack` bound to a homogeneous
/// `[CadenceFeatureDestination]` can only ever push that one type — a `NavigationLink(value:)`
/// carrying anything else is silently discarded, with no warning and no push. That is what made
/// every row on the Lists page dead on iPhone, because it pushes an `iOSListRoute`. Four paths
/// multiply that trap by four, so none of them is typed.
struct iOSCompactTabPaths {
    var tasks = NavigationPath()
    var calendar = NavigationPath()
    var notes = NavigationPath()
    var more = NavigationPath()

    subscript(tab: CadenceCompactTab) -> NavigationPath {
        get {
            switch tab {
            case .tasks: return tasks
            case .calendar: return calendar
            case .notes: return notes
            case .more: return more
            }
        }
        set {
            switch tab {
            case .tasks: tasks = newValue
            case .calendar: calendar = newValue
            case .notes: notes = newValue
            case .more: more = newValue
            }
        }
    }
}

/// iPhone navigation: a bottom bar of four tabs with a capture control in the middle.
///
/// It replaced a single `NavigationStack` rooted at `iOSCompactHomeView`, a grid of eight tiles.
/// That grid was not a home screen; it was a stand-in for navigation the app did not have. Because
/// there was no bar you had to return to it to reach anything, and because it therefore had to
/// list everything, most of its tiles were silent boxes. Restyling it could not fix that, and three
/// rounds of trying is what produced this shell.
///
/// Each tab keeps its own stack, so switching away and back lands you where you were rather than at
/// the tab's root. The tabs are kept alive once visited — first selection builds the stack, every
/// selection after that reveals the one already standing, which is what preserves scroll position
/// and any in-progress edit. Unvisited tabs are never built, so a cold launch pays for Tasks alone.
struct iOSCompactRootShell: View {
    @Binding var selectedTab: CadenceCompactTab
    @Binding var tasksSection: CadenceTasksSection
    @Binding var paths: iOSCompactTabPaths
    /// Reported up because a `NavigationPath` is write-only — it can be replaced and counted, never
    /// read — so the root cannot otherwise tell whether the More tab is showing its menu or a
    /// feature the sidebar has a row for. Without that, widening out of More → Goals had nothing to
    /// widen *into* and left the sidebar on whatever it was last pointed at (T-334). Every feature
    /// push in every tab passes through the one `navigationDestination` below, so this is one call
    /// site rather than a rule each screen has to remember.
    var onFeatureDestinationAppear: (CadenceCompactTab, CadenceFeatureDestination) -> Void = { _, _ in }

    // No `@Query` here on purpose. The shell used to hold
    // `@Query(sort: \AppTask.order) private var allTasks` for the placeholder capture sheet, which
    // meant the root of the app kept a live fetch of every task and an observation registration
    // that re-rendered the whole shell — all four stacks — on any task write. The creation sheets
    // own their own data.
    //
    // There is no `modelContext` here either any more. The palette's **Note** segment has to *make*
    // the note before `iOSNoteEditorCover` has anything to be presented over, and that — with the
    // other two composers — moved into `.iOSCaptureHost(_:)` when the iPad's corner `+` took the
    // same gesture (T-282). One routing, both placements.
    @State private var visitedTabs: Set<CadenceCompactTab> = []
    /// One live touch on the centre `+`. See `iOSCaptureRadialMenuButton` for why the gesture is
    /// ours rather than a `Button` plus `.onDrag`, and `CadenceCapturePalettePlacement` for why the
    /// bar's arc is a semicircle where the corner button's is a quadrant.
    @State private var captureInteraction = iOSCaptureInteraction(placement: .bottomCentre)

    /// The bar is a **sibling** of the tab content, not an overlay or a `safeAreaInset` on it.
    ///
    /// `safeAreaInset(edge: .bottom)` is the idiomatic answer and was the first one tried. It did
    /// not hold here: several of these screens paint `Theme.bg.ignoresSafeArea()` behind their
    /// scroll view, and the inset came back as nothing — the last row of All Tasks sat under the bar
    /// at full scroll and could not be brought out. A `VStack` cannot fail that way. The tab content
    /// is handed a height that stops where the bar starts, so no screen can put a row underneath it,
    /// and no screen needs to know the bar's height to avoid it (which is the per-screen bottom
    /// padding this replaced, and which would break again the moment the bar changed size).
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                ForEach(CadenceCompactTab.allCases) { tab in
                    if visitedTabs.contains(tab) || tab == selectedTab {
                        stack(for: tab)
                            .opacity(tab == selectedTab ? 1 : 0)
                            .allowsHitTesting(tab == selectedTab)
                            .accessibilityHidden(tab != selectedTab)
                            .zIndex(tab == selectedTab ? 1 : 0)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            iOSCompactTabBar(
                selection: selectedTab,
                onSelect: { selectedTab = $0 },
                captureInteraction: captureInteraction
            )
        }
        // The palette and the drag puck both have to leave the 46pt bar row the button sits in, so
        // they are drawn here, once, above every tab — together with the three composers a finished
        // press can ask for. Same reasoning as `iOSTaskInspectorHost()`: a control that must draw
        // outside its container cannot be hosted by that container. A plain tap is deliberately
        // unscoped — you press it from any tab and file the task afterwards — and since T-337 that
        // is true of the corner `+` as well: neither placement passes a seed, because context comes
        // from the drop target and nowhere else.
        .iOSCaptureHost(captureInteraction)
        // Carries the bar's colour down through the home-indicator strip, so the bar does not float
        // on a band of page background. Bottom edge only — the status bar keeps the page's own.
        .background(Theme.surface.ignoresSafeArea(edges: .bottom))
        .tint(Theme.blue)
        .task(id: selectedTab) { visitedTabs.insert(selectedTab) }
    }

    @ViewBuilder
    private func stack(for tab: CadenceCompactTab) -> some View {
        NavigationStack(path: pathBinding(for: tab)) {
            root(for: tab)
                .navigationDestination(for: CadenceFeatureDestination.self) { destination in
                    iOSCompactFeatureDestinationView(destination: destination)
                        .onAppear { onFeatureDestinationAppear(tab, destination) }
                }
        }
        // A tab kept alive at zero opacity is still laying its rows out, and the custom capture
        // drag hit-tests published frames rather than the real view hierarchy — so without this
        // every hidden task surface would be a drop target sitting on top of the visible one.
        // `allowsHitTesting(false)` above is what makes the *system* drag immune; this is its
        // counterpart. See `iOSNewTaskDropTargetsAreLive`.
        .environment(\.iOSNewTaskDropTargetsAreLive, tab == selectedTab)
    }

    @ViewBuilder
    private func root(for tab: CadenceCompactTab) -> some View {
        switch tab {
        case .tasks:
            iOSTasksTabView(section: $tasksSection, path: pathBinding(for: .tasks))
        case .calendar:
            iOSCalendarView(isCompactTabRoot: true)
        case .notes:
            iOSNotesView(isCompactTabRoot: true)
        case .more:
            iOSMoreTabView()
        }
    }

    private func pathBinding(for tab: CadenceCompactTab) -> Binding<NavigationPath> {
        Binding(
            get: { paths[tab] },
            set: { paths[tab] = $0 }
        )
    }

}

/// The pushed-screen switch, shared by all four stacks so a destination reached from Search inside
/// More renders the same screen it would anywhere else.
struct iOSCompactFeatureDestinationView: View {
    let destination: CadenceFeatureDestination

    var body: some View {
        switch destination {
        case .today:
            iOSTodayView()
        case .allTasks:
            iOSAllTasksView()
        case .focus:
            iOSFocusView()
        case .inbox:
            iOSInboxView()
        case .calendar:
            iOSCalendarView()
        case .notes:
            iOSNotesView()
        case .lists:
            iOSListsView()
        case .goals:
            iOSGoalsView()
        case .habits:
            iOSHabitsView()
        case .search:
            iOSSearchView()
        case .settings:
            iOSSettingsView()
        }
    }
}

// MARK: - Bar

private struct iOSCompactTabBar: View {
    let selection: CadenceCompactTab
    let onSelect: (CadenceCompactTab) -> Void
    let captureInteraction: iOSCaptureInteraction

    var body: some View {
        HStack(spacing: 0) {
            item(.tasks)
            item(.calendar)
            iOSCompactCaptureButton(interaction: captureInteraction)
                .frame(maxWidth: .infinity)
            item(.notes)
            item(.more)
        }
        .padding(.horizontal, 6)
        .padding(.top, 6)
        .padding(.bottom, 2)
        .background(Theme.surface)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.borderSubtle)
                .frame(height: 1)
        }
    }

    private func item(_ tab: CadenceCompactTab) -> some View {
        iOSCompactTabBarItem(tab: tab, isSelected: selection == tab) {
            onSelect(tab)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct iOSCompactTabBarItem: View {
    let tab: CadenceCompactTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(height: 20)

                Text(tab.title)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            // `Theme.muted`, not `Theme.dim`, for the same reason `iOSSegmentedPill` gives: an
            // unselected tab is a label you are meant to read and tap, and `dim` at 10pt is under
            // the contrast floor.
            .foregroundStyle(isSelected ? Theme.blue : Theme.muted)
            .frame(maxWidth: .infinity, minHeight: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.iosPressable)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The centre control. It is **not** a tab: it presents capture and never selects, so it carries no
/// label, no selected state and no `CadenceCompactTab` case that could give it one. The filled
/// circle is what says "this one does something instead of taking you somewhere" —
/// `FloatingNewTaskButton`'s vocabulary on macOS, and the vocabulary the old Home screen's floating
/// `+` used before the bar absorbed it. Capture used to exist on Home alone, so from every other
/// screen you had to navigate away to write a task down.
///
/// It draws `iOSCircularAddButton`, the same circle the iPad pins to a page corner, at the one
/// diameter this placement can hold: 56pt does not fit in a 46pt bar row beside four tab items. It
/// was a hand-rolled copy that had drifted to a bolder glyph and a tighter shadow — see that type
/// for why the glyph and shadow are derived from the diameter now. Since T-282 the corner `+` runs
/// the *same* gesture through the same `iOSCaptureRadialMenuButton`, so what is left here is
/// genuinely only a placement: this one is centred in a bar row and carries no corner inset.
private struct iOSCompactCaptureButton: View {
    let interaction: iOSCaptureInteraction

    var body: some View {
        // **One gesture, three outcomes, and it is not `.onDrag` any more.** T-171: a quick press
        // then a move is a drag immediately; ~350ms of stillness opens a palette of composers
        // around the button; movement inside the palette's radius slides between its segments and
        // movement past that radius hands the touch back to the drag. `UIDragInteraction` cannot
        // host that — its lift *is* a 326–349ms long press, so it wants the same window the palette
        // does, and it refuses to lift at all when the finger moves first. See
        // `iOSCaptureRadialMenuButton` and `CadenceCapturePressResolver`.
        iOSCaptureRadialMenuButton(diameter: 44, interaction: interaction)
            // Matches the tab items' row height so the bar's baseline is set by one number.
            .frame(minHeight: 46)
    }
}
#endif
