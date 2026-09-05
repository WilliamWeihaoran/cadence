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

/// One of Today's **list** groups — an area, a project, or the Inbox — and the day's Completed
/// group under them.
///
/// **The sections say where the work lives, and that is the only axis left.** The type is still
/// called `…IntentSectionView` from when it drew four date buckets; those went to
/// `CadenceTaskQuerySupport.todayListGroups`, and the last date-shaped group with them — see
/// `TasksPanel.todayGroupSections` for the user's words. What replaced the intent axis is the sort:
/// `compareTasksForCurrentSort` leads with `todayTaskSortRank`, so a list still reads past-do, then
/// due-today, then do-today, with no heading spent saying so.
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
/// **The rows are `TaskListInteractiveRow`, not a fourth copy of it (T-608).** This drew
/// `MacTaskRow` and then re-implemented the shared row's whole chain around it — `.draggable`, the
/// `.dropDestination` with its `isTargeted:` write-back, the 2pt top indicator, the 0.15s
/// `.easeInOut` on `dragOverTaskID`, and the asymmetric insert/remove transition — while the shared
/// row had taken `leadingInset`/`trailingInset` as parameters the whole time. Passing the panel's
/// two insets is the entire difference the copy existed for.
///
/// **It was not quite a copy, and the difference was a defect.** The overlay went on the *unpadded*
/// row and the padding on the result, so Today's drop indicator was inset twice: 32pt from the
/// pane's leading edge over a row whose content starts at 16. The shared row overlays the padded
/// row, so the indicator now starts where the row it points at starts. Pinned by
/// `CadenceTodayUnificationTests.todaysRowsAreTheSharedInteractiveRowAtThePanelsOwnInsets`.
///
/// An `opacity` parameter went with the copy. It was declared with the group and **never passed by
/// the one call site**, so it dimmed nothing from the day it landed; iOS dims its Completed group,
/// and this was the intent groups.
///
/// The disclosure chevron comes with the header now, rather than being wrapped around it here.
struct TasksPanelIntentSectionView: View {
    let title: String
    let accent: Color
    let tasks: [AppTask]
    /// Today's own `yyyy-MM-dd`, handed down rather than recomputed per section, so every group on
    /// the page splits its counts against one day.
    let todayKey: String
    /// **`false` at the one call site**, and the header above these rows is why: it prints the
    /// list's name, so a chip under it is that name twice. It stays a parameter rather than becoming
    /// a constant because this view is the panel's section, not Today's only possible section — see
    /// `TasksPanel.todayGroupSections`, which says what it passes and why.
    let showsContainer: Bool
    let contexts: [Context]
    let areas: [Area]
    let projects: [Project]
    let isCollapsed: Bool
    @Binding var dragOverTaskID: UUID?
    let onToggle: () -> Void
    let taskDragPayload: (AppTask) -> String
    /// Non-`nil` for every group Today draws now — they are all lists, and a list on today is a
    /// real destination. Still optional because `CadenceTaskDropSupport.dropKey(forGroup:)` is what
    /// decides, for both platforms, and it still answers `nil` for identities that name no place.
    let onDropOnSectionPayload: ((String) -> Bool)?
    let onDropOnTaskPayload: (String, AppTask) -> Bool

    var body: some View {
        Section {
            header
                .padding(.horizontal, TasksPanelMetrics.horizontalInset)
                .padding(.top, TasksPanelMetrics.sectionHeaderTopInset)
                .padding(.bottom, TasksPanelMetrics.sectionHeaderBottomInset)
                // **T-681.** `.listRowBackground`/`.listRowSeparator` are `List` row modifiers;
                // `TasksPanel` draws this section inside `ScrollView { LazyVStack(pinnedViews:
                // .sectionHeaders) }`, not a `List`, so both were no-ops here — checked before
                // removing, because `TaskListDisplayRow` carries the same two modifiers and *is*
                // load-bearing for its other caller, `ListTasksCompletedSectionView` on the All
                // Tasks page, which sits inside a real `List`.
                .dropDestination(for: String.self) { items, _ in
                    guard let onDropOnSectionPayload, let payload = items.first else { return false }
                    return onDropOnSectionPayload(payload)
                }

            if !isCollapsed {
                ForEach(tasks) { task in
                    // `.standard`, not `.todayGrouped`: that style drops the do-date pill for the
                    // whole section, and the do date is a thing Today's rows still have to say — a
                    // list group holds work due today, work merely planned for it, and work planned
                    // for a day already gone, and the pill is the only thing that tells them apart.
                    //
                    // What Today withholds instead is **the one day it has already named**:
                    // `dayAlreadyStatedBySurface: todayKey` drops a pill that would read "Today" on
                    // the page called Today, and leaves every other reading — including a red "3
                    // days ago" — exactly where it was. See `MacTaskRow.dayAlreadyStatedBySurface`.
                    //
                    // Both insets are named rather than left to default. `TaskListInteractiveRow`
                    // defaults to the **list detail's** 52, which clears leading furniture Today's
                    // rows do not have — an omitted argument here would indent the rows past their
                    // own heading rather than fail.
                    TaskListInteractiveRow(
                        task: task,
                        style: .standard,
                        showsContainer: showsContainer,
                        dayAlreadyStatedBySurface: todayKey,
                        contexts: contexts,
                        areas: areas,
                        projects: projects,
                        leadingInset: todayRowLeadingInset,
                        trailingInset: TaskListDisplayMetrics.taskTrailingInset,
                        dragOverTaskID: $dragOverTaskID,
                        taskDragPayload: taskDragPayload,
                        onDropOnTaskPayload: onDropOnTaskPayload
                    )
                }
            }
        }
    }

    /// The two figures the other three macOS task surfaces already show, from the same two
    /// functions they call — `TasksPanelSupport.overdueCount` / `.openCount`, which exclude
    /// completed tasks so a ticked-off row with a past due date stops inflating either.
    ///
    /// **They are independent questions now.** `openCount` used to be `regularCount` and subtracted
    /// the flag's figure, so a group whose open work was all late read `0 tasks` over its own rows —
    /// which the old "Overdue" section hit on every render, and which a *list* group hits the moment
    /// every task it has left is past its date. That comment used to sit here calling the state
    /// acceptable because All Tasks reached it too; All Tasks reaching a wrong number is not a
    /// reason for Today to.
    private var header: some View {
        TaskListGroupHeader(
            title: title,
            isCollapsed: isCollapsed,
            overdueCount: TasksPanelSupport.overdueCount(in: tasks, todayKey: todayKey),
            taskCount: TasksPanelSupport.openCount(in: tasks),
            accent: accent,
            onToggle: onToggle
        )
    }
}

struct TasksPanelCompletedSectionView: View {
    let tasks: [AppTask]
    /// The panel's surface answer — see `TasksPanel.options`. **True here and false in the groups
    /// above**, which is not an inconsistency: this section is flat, so its rows are the only thing
    /// that can say which list a finished task came from.
    let showsContainer: Bool
    /// Today's own `yyyy-MM-dd`, for the same reason the groups above take it — see
    /// `MacTaskRow.dayAlreadyStatedBySurface`. A task finished today and planned for today does not
    /// get to say "Today" on the Today page just because it is in the Completed section.
    let todayKey: String
    let contexts: [Context]
    let areas: [Area]
    let projects: [Project]
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
                // `TaskListDisplayRow` plus a `.draggable`, which is exactly the shape
                // `TasksListCompletedSectionView` uses on All Tasks: finished rows can still be
                // dragged out, and nothing can be dropped onto them, so there is no indicator and
                // no `dragOverTaskID` to bind.
                ForEach(tasks) { task in
                    TaskListDisplayRow(
                        task: task,
                        style: .standard,
                        showsContainer: showsContainer,
                        dayAlreadyStatedBySurface: todayKey,
                        contexts: contexts,
                        areas: areas,
                        projects: projects,
                        leadingInset: todayRowLeadingInset,
                        trailingInset: TaskListDisplayMetrics.taskTrailingInset
                    )
                    .draggable(taskDragPayload(task))
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
