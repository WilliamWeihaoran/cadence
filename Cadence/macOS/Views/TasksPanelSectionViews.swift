#if os(macOS)
import SwiftUI

/// A single list-level task group (one area / project / Inbox).
///
/// `contextIcon` / `contextColor` are **not** used by Today, which groups by list
/// only. They exist for `TasksListView`, which still shows a small context glyph beside the list
/// icon. `TasksPanel`'s `.byDoDate` list grouping was the other reader and is gone (T-487).
struct TodayTaskGroup: Identifiable {
    let id: String
    let contextIcon: String?
    let contextColor: Color?
    let listIcon: String
    let listName: String
    let listColor: Color
    var tasks: [AppTask]
}

// `FrozenTodayTaskGroup`, `FrozenFlatTaskSection`, `TasksPanelGroupSectionView` and
// `TasksPanelFlatSectionView` were here — the list-grouped and flat section rows, and the two
// snapshot types the hover freeze rehydrated them from. All four existed only for `TasksPanel`'s
// `.byDoDate` mode, which nothing could reach, and all four went with it (T-487). Today's sections
// are `TasksPanelIntentSectionView` below; `TasksListView` and `ListDetailComponents` draw their
// own and never used these.

/// The figures the macOS Today panel is laid out with.
///
/// **The panel had three section headers and no metrics type** (`docs/TODO.md` T-597). Two adjacent
/// headings — the intent groups and the Completed group under them — were padded identically except
/// for **1pt** of bottom inset, 5 against 6, and the gutter they share with the controls bar, the
/// overdue heading and the two overdue card stacks was typed out at six sites as a bare `16`.
///
/// **Deliberately not `TaskListDisplayMetrics`**, whose `headerHorizontalInset` is 24. That is a
/// list *detail*'s gutter, and its rows are indented 52 to clear their own leading furniture;
/// Today's rows start at `MacTaskRow`'s own 14. A 24pt header over a 14pt row is the "header
/// indented from the rows under it" defect `CadencePageHeaderMetrics.horizontalPadding` keeps its
/// own gutter to avoid — so the panel keeps 16, and now says so once.
enum TasksPanelMetrics {
    /// The panel's gutter: its headings, its controls bar, its overdue cards — and its rows, which
    /// is not a coincidence but the rule. Today's rows sit directly under a panel heading and are
    /// indented to match it, which was already written down as the reason `todayRowLeadingInset`
    /// was 16 and not `TaskListDisplayMetrics.taskLeadingInset`'s 52.
    static let horizontalInset: CGFloat = 16

    /// Above a section heading, separating it from the group before it.
    static let sectionHeaderTopInset: CGFloat = 16

    /// Under one, before its first row. **6, and neither of the pair had a reason** — so it is the
    /// tie-break the ticket asks for rather than a third figure: `.padding(.bottom, 6)` stands at
    /// five sites under `Cadence/macOS/` against one for `5`. It is deliberately not the
    /// list-detail sibling's 8; that header is a page's and this one is a pane's, and the pane's
    /// two headings only ever disagreed with each other.
    static let sectionHeaderBottomInset: CGFloat = 6
}

/// How far Today's rows are indented from the pane's leading edge.
///
/// **Deliberately not `TaskListDisplayMetrics.taskLeadingInset` (52).** That inset clears a list
/// detail's own leading furniture; Today's rows sit directly under a panel header and are indented
/// to match it — which is why this is now that heading's own inset rather than a second 16. The
/// **trailing** gutter has no such story — both surfaces need the hover fill and its 1pt border to
/// stop short of the divider — so Today reads `TaskListDisplayMetrics.taskTrailingInset` rather
/// than restating 12. It had no trailing padding at all until T-593, which is why Today alone drew
/// rows flush to the divider.
private let todayRowLeadingInset: CGFloat = TasksPanelMetrics.horizontalInset

/// One of Today's intent groups — Overdue / Past Do / Due Today / Planned Today — and the day's
/// Completed group under them.
///
/// **The sections say why a task is in front of you, not where it lives.** macOS's Today grouped by
/// list (one flat tier of area/project groups in sidebar order) while both iOS Todays grouped by
/// intent, so the same day read as an inventory on one platform and as a plan on the other. The
/// intent vocabulary wins, and it wins from `CadenceTaskQuerySupport.todayGroups` — the function
/// iOS already called — rather than from a second macOS copy of the same four predicates, which is
/// what `todayDateSections` was: the same buckets under the names "Past Due" and "Do Today".
///
/// **The heading is `TaskListGroupHeader` — macOS's, not the shared eyebrow (T-605).** Today drew
/// `CadenceTaskGroupHeading`: a 10pt uppercase eyebrow with one count capsule and no accent bar,
/// while All Tasks, Inbox and list detail all drew the 3×22pt bar, the 14pt bold sentence-case
/// title and the split overdue/regular counts. One desktop app, two group headings, and Today was
/// the minority of one — so Today moves and the other three do not.
///
/// **macOS and iOS now differ here, deliberately.** iOS routes Today, Inbox and All Tasks through
/// `CadenceTaskGroupHeading`, and that stays: a 3pt bar plus a chevron plus two capsules is a
/// pointer-density row, and the eyebrow is the phone's. `CadenceTaskGroupHeading`'s own doc used to
/// call itself "one heading for Today on both platforms" and no longer does. **This divergence is
/// the decision, not drift — do not re-file it.** What is still shared is the *rule* about counts:
/// both headings ask `CadenceTaskGroupHeadingMetrics.showsCapsule`, so neither invents a `0` for a
/// group that does not know its own size.
///
/// The disclosure chevron comes with the header now, rather than being wrapped around it here.
struct TasksPanelIntentSectionView: View {
    let title: String
    let accent: Color
    let tasks: [AppTask]
    /// Today's own `yyyy-MM-dd`, handed down rather than recomputed per section, so every group on
    /// the page splits its counts against one day.
    let todayKey: String
    /// The panel's surface answer, narrowed by the group's own — see `TasksPanel.options` and
    /// `CadenceTodayTaskGroup.showsContainerChip`.
    let showsContainer: Bool
    let contexts: [Context]
    let areas: [Area]
    let projects: [Project]
    let isCollapsed: Bool
    /// Dimmed as a whole rather than row by row, the way iOS dims its Completed group.
    var opacity: Double = 1
    @Binding var dragOverTaskID: UUID?
    let onToggle: () -> Void
    let taskDragPayload: (AppTask) -> String
    /// `nil` for a group defined by a day that has already gone by — there is nothing a drop could
    /// mean for "Overdue". `CadenceTaskDropSupport.dropKey(forGroup:)` decides, for both platforms.
    let onDropOnSectionPayload: ((String) -> Bool)?
    let onDropOnTaskPayload: (String, AppTask) -> Bool

    var body: some View {
        Section {
            header
                .padding(.horizontal, TasksPanelMetrics.horizontalInset)
                .padding(.top, TasksPanelMetrics.sectionHeaderTopInset)
                .padding(.bottom, TasksPanelMetrics.sectionHeaderBottomInset)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .dropDestination(for: String.self) { items, _ in
                    guard let onDropOnSectionPayload, let payload = items.first else { return false }
                    return onDropOnSectionPayload(payload)
                }

            if !isCollapsed {
                ForEach(tasks) { task in
                    // `.standard`, not `.todayGrouped`: that style suppresses the do-date pill as
                    // well as the list chip, and the do date is a thing Today's rows still have to
                    // say — a list group holds work due today and work merely planned for it, and
                    // the row is the only thing that tells them apart. The **list** chip is
                    // withheld by `showsContainer` instead (`CadenceTodayTaskGroup`
                    // .showsContainerChip), which is off inside a list group and on inside Overdue,
                    // so the one duplication `.todayGrouped` existed to avoid is still avoided
                    // without losing the date.
                    MacTaskRow(task: task, style: .standard, showsContainer: showsContainer, contexts: contexts, areas: areas, projects: projects)
                        .opacity(opacity)
                        .draggable(taskDragPayload(task))
                        .dropDestination(for: String.self) { items, _ in
                            guard let payload = items.first else { return false }
                            return onDropOnTaskPayload(payload, task)
                        } isTargeted: { isOver in
                            if isOver { dragOverTaskID = task.id }
                            else if dragOverTaskID == task.id { dragOverTaskID = nil }
                        }
                        .overlay(alignment: .top) {
                            if dragOverTaskID == task.id {
                                Rectangle()
                                    .fill(Theme.blue)
                                    .frame(height: 2)
                                    .padding(.leading, todayRowLeadingInset)
                                    .padding(.trailing, TaskListDisplayMetrics.taskTrailingInset)
                                    .transition(.opacity)
                            }
                        }
                        .animation(.easeInOut(duration: 0.15), value: dragOverTaskID)
                        .padding(.leading, todayRowLeadingInset)
                        .padding(.trailing, TaskListDisplayMetrics.taskTrailingInset)
                        .transition(.asymmetric(
                            insertion: .opacity,
                            removal: .opacity.combined(with: .move(edge: .top))
                        ))
                }
            }
        }
    }

    /// The split the other three macOS task surfaces already show, from the same two functions
    /// they call — `TasksPanelSupport.overdueCount` / `.regularCount`, which exclude completed
    /// tasks so a ticked-off row with a past due date stops inflating the flag.
    ///
    /// Inside "Overdue" the split degenerates — every open row is late, so the flag holds the whole
    /// group and the neutral capsule reads `0`. That is not a new state: a list group on All Tasks
    /// whose open work is all overdue has read exactly that since the header existed. Special-casing
    /// it here would put a fifth rule in the one place this ticket is removing a rule from.
    private var header: some View {
        TaskListGroupHeader(
            title: title,
            isCollapsed: isCollapsed,
            overdueCount: TasksPanelSupport.overdueCount(in: tasks, todayKey: todayKey),
            regularCount: TasksPanelSupport.regularCount(in: tasks, todayKey: todayKey),
            accent: accent,
            onToggle: onToggle
        )
    }
}

struct TasksPanelCompletedSectionView: View {
    let tasks: [AppTask]
    /// The panel's surface answer — see `TasksPanel.options`.
    let showsContainer: Bool
    let contexts: [Context]
    let areas: [Area]
    let projects: [Project]
    let allTasks: [AppTask]
    let isCollapsed: Bool
    let onToggle: () -> Void
    let taskDragPayload: (AppTask) -> String

    var body: some View {
        Section {
            // The day's finished work, headed and tinted like every other Today group:
            // `CadenceTodayPresentationSupport` owns both, and iOS reads the same two constants.
            //
            // There was an `else` here drawing `CompletedSectionHeader`'s neutral "Completed" for
            // the `.byDoDate` logbook — everything ever finished, a different thing from the day's
            // work. It went with the mode, and so did that header (T-487).
            //
            // A plain `count:`, not the overdue/regular split the groups above take — and for the
            // same reason `TasksListCompletedSectionView` on All Tasks takes one. The split counts
            // *open* work, so on a group where every row is done it would report "0 tasks" over a
            // list of finished ones. Done work has one number.
            TaskListGroupHeader(
                title: CadenceTodayPresentationSupport.completedSectionTitle,
                count: tasks.count,
                isCollapsed: isCollapsed,
                accent: CadenceTodayPresentationSupport.completedSectionAccent,
                onToggle: onToggle
            )
            .padding(.horizontal, TasksPanelMetrics.horizontalInset)
            .padding(.top, TasksPanelMetrics.sectionHeaderTopInset)
            .padding(.bottom, TasksPanelMetrics.sectionHeaderBottomInset)

            if !isCollapsed {
                ForEach(tasks) { task in
                    MacTaskRow(task: task, style: .standard, showsContainer: showsContainer, contexts: contexts, areas: areas, projects: projects)
                        .draggable(taskDragPayload(task))
                        .padding(.leading, todayRowLeadingInset)
                        .padding(.trailing, TaskListDisplayMetrics.taskTrailingInset)
                        .transition(.asymmetric(
                            insertion: .opacity,
                            removal: .opacity.combined(with: .move(edge: .top))
                        ))
                }
            }
        }
    }
}

// `TasksPanelRolloverNoticeSectionView` was here. It is
// `Shared/Components/CadenceTodayRolloverBanner.swift` now, at `.panelBand` style — nothing in it
// was AppKit-shaped, and it being under `macOS/Views/` was one of the three reasons Today's
// rollover notice could not exist on iOS (T-195). `TasksPanel` builds the shared view directly;
// there is deliberately no macOS-named wrapper to reach for.

/// **Only the row order.** This carried two more bindings and two more snapshot arguments — the
/// frozen list groups and the frozen flat sections — and both were `.byDoDate`'s. Today's call
/// site already passed `[]` for each, so `TaskSurfaceFreezeCoordinator.capture` (which only writes
/// a snapshot when its source is non-empty) provably left both `nil` on every frame this observer
/// has ever run. They went with the mode (T-487); the row-order freeze, which is the part Today
/// uses, is untouched and still goes through the shared coordinator rather than a local copy.
struct HoverFreezeObserver: View {
    @Environment(HoveredTaskManager.self) private var hoveredTaskManager
    @Binding var frozenOrder: [AppTask]?
    let naturalTasks: [AppTask]
    @State private var isPointerInsideSurface = false
    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onChange(of: hoveredTaskManager.hoveredTask?.id) { _, newID in
                if newID != nil {
                    var freezeState = TaskSurfaceFreezeState<Never, Never>(
                        frozenOrder: frozenOrder,
                        primarySnapshot: nil,
                        secondarySnapshot: nil
                    )
                    // Only write back when something was actually frozen. Writing an unchanged
                    // value into a `@State` binding still invalidates the owning panel, and this
                    // fires on every row boundary the pointer crosses.
                    guard freezeState.captureIfNeeded(
                        naturalTasks: naturalTasks,
                        sourcePrimarySnapshot: [],
                        sourceSecondarySnapshot: []
                    ) else { return }
                    frozenOrder = freezeState.frozenOrder
                } else if !isPointerInsideSurface, frozenOrder != nil {
                    withAnimation(TaskSurfaceFreezeSupport.releaseAnimation) {
                        var freezeState = TaskSurfaceFreezeState<Never, Never>(
                            frozenOrder: frozenOrder,
                            primarySnapshot: nil,
                            secondarySnapshot: nil
                        )
                        freezeState.release()
                        frozenOrder = freezeState.frozenOrder
                    }
                }
            }
            .onHover { isPointerInsideSurface = $0 }
    }
}

#endif
