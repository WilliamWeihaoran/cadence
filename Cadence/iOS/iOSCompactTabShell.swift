#if os(iOS)
import SwiftData
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

    // No `@Query` and no `modelContext` here on purpose. The shell used to hold
    // `@Query(sort: \AppTask.order) private var allTasks` for the placeholder capture sheet, which
    // meant the root of the app kept a live fetch of every task and an observation registration
    // that re-rendered the whole shell — all four stacks — on any task write. The creation sheet
    // owns its own data now, so the shell reads nothing.
    @State private var visitedTabs: Set<CadenceCompactTab> = []
    @State private var showQuickCapture = false

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
                onCapture: presentQuickCapture
            )
        }
        // Carries the bar's colour down through the home-indicator strip, so the bar does not float
        // on a band of page background. Bottom edge only — the status bar keeps the page's own.
        .background(Theme.surface.ignoresSafeArea(edges: .bottom))
        .tint(Theme.blue)
        .task(id: selectedTab) { visitedTabs.insert(selectedTab) }
        // The `+`'s one presentation site. It owns its own `NavigationStack`, toolbar, focus and
        // dismissal, so the bar hands it nothing — no seed here, because capture from the bar is
        // deliberately unscoped: you press it from any tab and file the task afterwards.
        .sheet(isPresented: $showQuickCapture) {
            iOSCreateTaskSheet()
        }
    }

    @ViewBuilder
    private func stack(for tab: CadenceCompactTab) -> some View {
        NavigationStack(path: pathBinding(for: tab)) {
            root(for: tab)
                .navigationDestination(for: CadenceFeatureDestination.self) { destination in
                    iOSCompactFeatureDestinationView(destination: destination)
                }
        }
    }

    @ViewBuilder
    private func root(for tab: CadenceCompactTab) -> some View {
        switch tab {
        case .tasks:
            iOSTasksTabView(section: $tasksSection, path: pathBinding(for: .tasks))
        case .calendar:
            iOSCalendarView(isCompactTabRoot: true)
        case .notes:
            iOSCompactNotesView(isCompactTabRoot: true)
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

    private func presentQuickCapture() {
        showQuickCapture = true
    }
}

/// The pushed-screen switch, shared by all four stacks so a destination reached from Search inside
/// More renders the same screen it would anywhere else.
struct iOSCompactFeatureDestinationView: View {
    let destination: CadenceFeatureDestination

    var body: some View {
        switch destination {
        case .today:
            iPadTodayView()
        case .allTasks:
            iOSAllTasksView()
        case .focus:
            iOSFocusView()
        case .inbox:
            iPadInboxView()
        case .calendar:
            iOSCalendarView()
        case .notes:
            iOSCompactNotesView()
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
    let onCapture: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            item(.tasks)
            item(.calendar)
            iOSCompactCaptureButton(action: onCapture)
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
private struct iOSCompactCaptureButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Theme.onColor)
                .frame(width: 44, height: 44)
                .background(Theme.blue)
                .clipShape(Circle())
                .shadow(color: Theme.blue.opacity(0.30), radius: 10, x: 0, y: 4)
                .frame(minHeight: 46)
                .contentShape(Circle())
        }
        .buttonStyle(.iosPressable)
        .accessibilityLabel("New Task")
    }
}
#endif
