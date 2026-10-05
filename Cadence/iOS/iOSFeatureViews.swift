#if os(iOS)
import SwiftData
import SwiftUI

/// Goals screen. Top-level goals are the long-running directions that used to live in their
/// own model; each is listed with its milestones (`subGoals`) nested directly underneath it.
struct iOSGoalsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \Goal.order) private var goals: [Goal]
    @State private var selectedID: UUID?

    private var activeGoals: [Goal] {
        GoalAssignmentRules.activeGoals(from: goals)
    }

    /// Genuine directions, plus any nested goal with no active ancestor — without the second half
    /// those milestones would have no row to appear under and drop off the screen.
    private var topLevelGoals: [Goal] {
        GoalAssignmentRules.activeTopLevelGoals(from: goals)
    }

    /// **The whole nested subtree, not the direct children ([[T-1337]]).** This asked
    /// `milestones(of:)` — one level — so a goal → milestone → sub-milestone tree, which stores
    /// written before [[T-1327]] hold and which syncs through CloudKit, had a row on no iOS screen
    /// while its tasks still moved the direction's percentage. macOS has flattened descendants
    /// into this same tier since `926a67b`; this is the iOS half of that reading.
    private func milestones(of goal: Goal) -> [Goal] {
        GoalAssignmentRules.activeNestedGoals(under: goal)
    }

    /// The detail pane's subject, and the row that draws as selected. Every rung of the resolution
    /// is filtered to active goals, so this pane can never show a goal the list above has no row
    /// for — see `GoalAssignmentRules.selectedGoal(id:from:)`, which holds the reasoning and the
    /// tests, including why the fall-through the deleted-out-from-under-you case needs survives it.
    private var selected: Goal? {
        GoalAssignmentRules.selectedGoal(id: selectedID, from: goals)
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                compactLayout
            } else {
                horizontalLayout
            }
        }
        .background(Theme.bg)
        .iOSHidesCompactNavigationBar()
        .onAppear {
            selectedID = selectedID ?? selected?.id
        }
        // **Two editor sheets and two alerts left with [[T-2079]]**: the goal editor, the habit
        // editor it could open, the delete confirmation and the delete-refusal alert. All four
        // reached `saveGoal` / `saveHabit` or `ModelContext.deleteGoal`, none of which exists.
    }

    /// `narrow` is the phone's own list, in its own `NavigationStack` — the rows push, so they need
    /// one, and the regular shell does not wrap this page. Local rather than hoisted into
    /// `iOSRootView.detailView` so the split path this page normally takes is left untouched.
    private var horizontalLayout: some View {
        iOSFeatureSplitLayout(
            list: { listPane(pushes: false) },
            detail: { detailPane },
            narrow: { NavigationStack { listPane(pushes: true) } }
        )
    }

    private var compactLayout: some View {
        listPane(pushes: true)
    }

    /// The eyebrow says what the title cannot. "PROGRESS / Goals" was a label over a label; this
    /// is the shape of the tree underneath it.
    private var shapeEyebrow: String {
        let milestoneCount = topLevelGoals.reduce(0) { $0 + milestones(of: $1).count }
        guard !topLevelGoals.isEmpty else { return "Nothing in flight" }
        let directions = topLevelGoals.count == 1 ? "1 direction" : "\(topLevelGoals.count) directions"
        let nested = milestoneCount == 1 ? "1 milestone" : "\(milestoneCount) milestones"
        return "\(directions) · \(nested)"
    }

    /// One pane, both shells. `pushes` is the whole of the difference between them: the phone's
    /// rows push a detail onto the tab's stack and carry the back control the hidden navigation bar
    /// would have held, the iPad's select into the detail beside them. See `iOSFeatureRowLink`.
    private func listPane(pushes: Bool) -> some View {
        iOSFeatureListPane(
            eyebrow: shapeEyebrow,
            title: "Goals",
            count: activeGoals.count,
            empty: emptyState,
            // No `actionTitle`/`action`: the New Goal button opened the goal editor sheet
            // ([[T-2079]]). `iOSFeatureListPane` renders no button when both are omitted.
            isPage: pushes,
            onBack: pushes && horizontalSizeClass == .compact ? { dismiss() } : nil
        ) {
            ForEach(topLevelGoals) { goal in
                goalLink(goal, pushes: pushes)

                ForEach(milestones(of: goal)) { milestone in
                    goalLink(milestone, pushes: pushes)
                        .padding(.leading, 16)
                }
            }
        }
    }

    private func goalLink(_ goal: Goal, pushes: Bool) -> some View {
        iOSFeatureRowLink(
            pushes: pushes,
            select: { selectedID = goal.id },
            destination: { pushedDetailView(for: goal) },
            label: { showsSelection in
                goalRow(goal, isSelected: showsSelection && selected?.id == goal.id)
            }
        )
        .buttonStyle(.iosPressable)
        // The long-press delete menu left with [[T-2079]]: `ModelContext.deleteGoal` is gone.
    }

    private func goalRow(_ goal: Goal, isSelected: Bool) -> some View {
        iOSFeatureSummaryRow(
            title: CadenceTitleNormalization.display(goal.title, fallback: CadenceTitleNormalization.defaultGoalTitle),
            subtitle: rowSubtitle(for: goal),
            detail: GoalContributionResolver.summary(for: goal).percentLabel,
            icon: goal.icon,
            color: Color(hex: goal.colorHex),
            isSelected: isSelected
        )
    }

    private func rowSubtitle(for goal: Goal) -> String {
        if let parent = goal.parentGoal {
            return CadenceTitleNormalization.display(parent.title, fallback: CadenceTitleNormalization.defaultGoalTitle)
        }
        let summary = CadenceGoalGroupSupport.summary(for: goal)
        return "\(CadencePluralization.phrase(summary.activeGoalCount, singular: "milestone", plural: "milestones")) / \(CadencePluralization.phrase(summary.activeHabitCount, singular: "habit", plural: "habits"))"
    }

    private func detailView(for goal: Goal, showsBackControl: Bool = false) -> some View {
        iOSGoalDetail(
            goal: goal,
            milestones: CadenceGoalGroupSupport.milestones(for: goal),
            habits: CadenceGoalGroupSupport.habits(for: goal),
            showsBackControl: showsBackControl
        )
    }

    /// The compact push stack's copy, which draws its own back chevron because the navigation bar
    /// it would otherwise sit in is hidden.
    private func pushedDetailView(for goal: Goal) -> some View {
        detailView(for: goal, showsBackControl: true)
    }

    /// The one empty state this screen has, read by **both** panes. See `iOSFeatureEmptyState`.
    ///
    /// **A third case, for "every goal is done" (T-689).** This page has no search field and no
    /// status picker, so `activeGoals.isEmpty` was always read as a first run — a reader who had
    /// completed every one of their goals saw "No goals yet" beside a list that was not actually
    /// empty. `allComplete` is true only when `goals` itself is non-empty and `activeGoals` is not,
    /// so a genuinely first-run store still reads the original words. Computed rather than
    /// `static let` because it now depends on this instance's own `goals`.
    private var emptyState: iOSFeatureEmptyState {
        let allComplete = !goals.isEmpty && activeGoals.isEmpty
        return iOSFeatureEmptyState(
            systemImage: "sparkles",
            title: CadenceEmptyStateCopy.goalsTitle(isNarrowed: false, allComplete: allComplete),
            subtitle: allComplete
                ? "Nothing in flight. Add another when you're ready."
                : "Create a direction, then nest milestones and habits underneath it."
        )
    }

    /// **What the detail pane says with nothing selected** (T-533).
    ///
    /// It said "No goal selected / Select an item from the list." unconditionally, next to a
    /// chooser that says "No goals yet" — a list with no items to select from.
    ///
    /// T-519's `unselectedDetail` needed a branch because its picker could be full while nothing
    /// was selected. **This pane has no such case.** `GoalAssignmentRules.selectedGoal(id:from:)`
    /// resolves only among active goals, so it is `nil` exactly when `activeGoals` is empty —
    /// which is `activeGoals.count == 0`, the condition `iOSFeatureListPane` draws its empty panel
    /// on. So every reader of this branch is looking at the chooser's empty panel at the same
    /// moment, and a `pickItems.isEmpty` guard copied from Focus would be a branch that never
    /// takes its other side.
    ///
    /// **T-541 made that an equality rather than an implication.** It used to hold by way of
    /// "`nil` only when `goals` is empty, and an empty `goals` makes the count zero" — true, but
    /// one-directional, and the gap was reachable: with every goal completed the count was zero
    /// and `selected` was not `nil`, so the chooser drew its empty panel while this branch went
    /// untaken and the pane rendered a completed goal.
    @ViewBuilder
    private var detailPane: some View {
        if let goal = selected {
            detailView(for: goal)
        } else {
            iOSFeatureEmptyDetail(matching: emptyState)
        }
    }
}

struct iOSHabitsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \Habit.order) private var habits: [Habit]
    @State private var selectedID: UUID?

    private var todayKey: String { DateFormatters.todayKey() }

    /// As on the goals screen: a selected id that no longer resolves falls through to the default
    /// rather than leaving the detail pane permanently empty.
    private var selected: Habit? {
        if let selectedID, let match = habits.first(where: { $0.id == selectedID }) {
            return match
        }
        return dueToday.first ?? habits.first
    }

    private var dueToday: [Habit] {
        habits.filter(\.isDueToday)
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                compactLayout
            } else {
                horizontalLayout
            }
        }
        .background(Theme.bg)
        .iOSHidesCompactNavigationBar()
        .onAppear {
            selectedID = selectedID ?? selected?.id
        }
        // The habit editor sheet and both delete alerts left with [[T-2079]] — see `iOSGoalsView`.
    }

    /// `narrow` is the phone's own list, in its own `NavigationStack` — the rows push, so they need
    /// one, and the regular shell does not wrap this page. Local rather than hoisted into
    /// `iOSRootView.detailView` so the split path this page normally takes is left untouched.
    private var horizontalLayout: some View {
        iOSFeatureSplitLayout(
            list: { listPane(pushes: false) },
            detail: { detailPane },
            narrow: { NavigationStack { listPane(pushes: true) } }
        )
    }

    private var compactLayout: some View {
        listPane(pushes: true)
    }

    /// The header eyebrow says what the title cannot — how today is actually going. "HABITS /
    /// Habits" told the reader the name of the screen they were already looking at, twice.
    private var todayEyebrow: String {
        guard !dueToday.isEmpty else { return "Nothing due today" }
        let done = dueToday.filter { $0.isDone(on: todayKey) }.count
        return "\(done) of \(dueToday.count) done today"
    }

    /// One pane, both shells — see `iOSGoalsView.listPane(pushes:)`, which this mirrors exactly.
    private func listPane(pushes: Bool) -> some View {
        iOSFeatureListPane(
            eyebrow: todayEyebrow,
            title: "Habits",
            count: habits.count,
            empty: Self.emptyState,
            // No `actionTitle`/`action`: see `iOSGoalsView.listPane` ([[T-2079]]).
            isPage: pushes,
            onBack: pushes && horizontalSizeClass == .compact ? { dismiss() } : nil
        ) {
            ForEach(habits) { habit in
                habitRow(habit, pushes: pushes)
            }
        }
    }

    /// The check-in control is layered *over* the row's select/navigate control rather than
    /// nested inside its label — a nested button never sees the tap on iOS, so checking a habit
    /// off from the list used to do nothing but open the detail. The row reserves exactly
    /// `iOSHabitCheckInSize` at its trailing edge for it.
    ///
    /// `.plain`, not `.iosPressable`: the press transform would scale and dim the row *underneath*
    /// the check-in button while leaving the button itself where it was.
    private func habitRow(_ habit: Habit, pushes: Bool) -> some View {
        ZStack(alignment: .trailing) {
            iOSFeatureRowLink(
                pushes: pushes,
                select: { selectedID = habit.id },
                destination: { detailView(for: habit, showsBackControl: true) },
                label: { showsSelection in
                    iOSHabitSummaryRow(
                        habit: habit,
                        todayKey: todayKey,
                        isSelected: showsSelection && selected?.id == habit.id
                    )
                }
            )
            .buttonStyle(.plain)

            // **The check-in button left with [[T-2079]].** The row keeps the trailing space it
            // reserved, because `iOSHabitSummaryRow` lays out against `iOSHabitCheckInSize` and
            // that is its own measurement rather than this control's.
            iOSHabitCheckInGlyph(habit: habit, todayKey: todayKey)
                .padding(.trailing, 4)
        }
        // The long-press delete menu left with [[T-2079]]: `ModelContext.deleteHabit` is gone.
    }

    private func detailView(for habit: Habit, showsBackControl: Bool = false) -> some View {
        iOSHabitDetail(
            habit: habit,
            todayKey: todayKey,
            showsBackControl: showsBackControl
        )
    }

    /// The one empty state this screen has, read by **both** panes. See `iOSFeatureEmptyState`.
    private static let emptyState = iOSFeatureEmptyState(
        systemImage: "flame.fill",
        title: CadenceEmptyStateCopy.habitsTitle(isNarrowed: false),
        subtitle: "Create repeating commitments and track today."
    )

    /// As on Goals, and for the same reason (T-533): `selected` falls back through
    /// `dueToday.first ?? habits.first`, so `nil` means `habits` is empty — the same emptiness
    /// `count: habits.count` puts the chooser's own empty panel on screen for. "Select an item
    /// from the list." named a list with no items.
    @ViewBuilder
    private var detailPane: some View {
        if let habit = selected {
            detailView(for: habit)
        } else {
            iOSFeatureEmptyDetail(matching: Self.emptyState)
        }
    }


}
#endif
