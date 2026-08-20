#if os(iOS)
import SwiftData
import SwiftUI

/// One detail surface for every goal, top-level or nested. A top-level goal reads as a
/// direction that owns milestones and habits; a nested goal reads as a milestone of its parent.
struct iOSGoalDetail: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// Pops *this* view. Reading `dismiss` here rather than taking a closure from the list pane is
    /// deliberate: the list pane's own `dismiss` pops the list, so a closure handed down from there
    /// would skip a level. Only consulted when `showsBackControl` is set.
    @Environment(\.dismiss) private var dismiss

    let goal: Goal
    var milestones: [Goal] = []
    var habits: [Habit] = []
    var onEdit: () -> Void = {}
    var onNewMilestone: () -> Void = {}
    var onNewHabit: () -> Void = {}
    /// Set on the compact push stack, where this view carries its own back control instead of a
    /// navigation bar holding one chevron and nothing else — the same trade every list pane in the
    /// iOS surface already makes (`iOSHidesCompactNavigationBar()`). Left off on iPad, where the
    /// detail sits beside its list and there is nothing to go back to.
    var showsBackControl = false

    private var summary: GoalContributionSummary {
        GoalContributionResolver.summary(for: goal)
    }

    private var tint: Color {
        Color(hex: goal.colorHex)
    }

    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }

    private var heroSubtitle: String {
        if !goal.desc.isEmpty { return goal.desc }
        if let parent = goal.parentGoal {
            return parent.title.isEmpty ? "Untitled Goal" : parent.title
        }
        return goal.context?.name ?? goal.kind.detail
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if showsBackControl && isCompact {
                    HStack(spacing: 0) {
                        iOSHeaderBackButton { dismiss() }
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, -8)
                }

                hero

                actions

                metrics

                linkedWorkChips

                if !milestones.isEmpty {
                    iOSEditorSection(title: "Milestones") {
                        rows(milestones) { milestone in
                            iOSEditorFieldRow(
                                label: milestone.title.isEmpty ? "Untitled Goal" : milestone.title,
                                systemImage: milestone.icon,
                                color: Color(hex: milestone.colorHex)
                            ) {
                                trailingMetric(GoalContributionResolver.summary(for: milestone).percentLabel)
                            }
                        }
                    }
                }

                if !habits.isEmpty {
                    iOSEditorSection(title: "Habits") {
                        rows(habits) { habit in
                            iOSEditorFieldRow(
                                label: habit.title.isEmpty ? "Untitled Habit" : habit.title,
                                systemImage: habit.icon,
                                color: Color(hex: habit.colorHex)
                            ) {
                                trailingMetric(habit.frequencyShortLabel)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, isCompact ? 16 : 20)
            .padding(.top, isCompact ? 8 : 20)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(Theme.bg)
        .iOSHidesCompactNavigationBar()
    }

    /// Milestones and habits are facts *about* the goal, so they read as editor rows in one card
    /// rather than a stack of elevated cards. They used to be `iOSFeatureSummaryRow`s — the exact
    /// shape the Goals list uses for rows that navigate — but only the split layout ever wired a
    /// tap to them, so on iPhone this was a column of controls that looked identical to the
    /// tappable ones a screen earlier and did nothing.
    @ViewBuilder
    private func rows<Item: Identifiable, Row: View>(
        _ items: [Item],
        @ViewBuilder row: @escaping (Item) -> Row
    ) -> some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            if index > 0 {
                iOSEditorDivider()
            }
            row(item)
        }
    }

    private func trailingMetric(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.muted)
            .monospacedDigit()
            .lineLimit(1)
    }

    /// What used to be a "LINKED WORK" section wrapping one `iOSFeatureSummaryRow` whose *title*
    /// was "0 linked lists" — a tappable-looking card row that was not tappable, saying nothing a
    /// chip could not. Chips are this app's established read-only vocabulary, and the section
    /// disappears entirely when there is nothing linked rather than announcing three zeroes.
    @ViewBuilder
    private var linkedWorkChips: some View {
        let summary = self.summary
        let hasAnything = summary.linkedListCount > 0
            || summary.overdueTaskCount > 0
            || summary.recentCompletedCount > 0

        if hasAnything {
            CadenceWrappingHStack(spacing: 7, lineSpacing: 7) {
                if summary.linkedListCount > 0 {
                    iOSMetaChip(
                        label: summary.linkedListCount == 1 ? "1 list" : "\(summary.linkedListCount) lists",
                        color: Theme.dim,
                        systemImage: "folder.fill"
                    )
                }
                if summary.overdueTaskCount > 0 {
                    // The one exceptional fact in the group, so the one that keeps a colour.
                    iOSMetaChip(label: "\(summary.overdueTaskCount) overdue", color: Theme.red)
                }
                if summary.recentCompletedCount > 0 {
                    iOSMetaChip(
                        label: summary.recentCompletedCount == 1 ? "1 done recently" : "\(summary.recentCompletedCount) done recently",
                        color: Theme.dim
                    )
                }
            }
        }
    }

    /// Identity, the two badges macOS shows beside a goal's title (kind and status), and the
    /// progress bar — all inside one card, so the goal's headline facts read as one object rather
    /// than a floating hero followed by an unlabelled system `ProgressView`.
    private var hero: some View {
        let summary = self.summary

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                iOSIconTile(systemImage: goal.icon, color: tint, size: 48, iconSize: 22)

                VStack(alignment: .leading, spacing: 7) {
                    Text(goal.title.isEmpty ? "Untitled Goal" : goal.title)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)

                    Text(heroSubtitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.subdued)
                        .lineLimit(3)

                    HStack(spacing: 7) {
                        if goal.isTopLevel {
                            iOSMetaChip(
                                label: goal.kind.label,
                                color: GoalKindPalette.color(for: goal.kind),
                                systemImage: goal.kind.systemImage
                            )
                        } else {
                            iOSMetaChip(label: "Milestone", color: Theme.green, systemImage: "flag.fill")
                        }

                        iOSMetaChip(
                            label: GoalStatusPalette.badgeLabel(for: goal.status),
                            color: GoalStatusPalette.color(for: goal.status)
                        )
                    }
                }

                Spacer(minLength: 0)

                Text(summary.percentLabel)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .monospacedDigit()
            }

            VStack(alignment: .leading, spacing: 10) {
                GoalProgressBar(progress: summary.progress, color: tint, height: 5)

                nextActionLine
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceCard(background: Theme.surface, cornerRadius: Theme.radiusPanel, shadowRadius: 16, shadowY: 6)
    }

    /// The next action, as one line under the progress bar rather than a "NEXT ACTION" section
    /// wrapping a card row.
    ///
    /// That row was styled exactly like the goal rows that navigate and was not tappable, and its
    /// subtitle read "Highest priority open task" — a description of the row rather than anything
    /// about the task in it. The due date is what the reader actually needs, and it is the one
    /// thing here allowed to carry a colour, because an overdue next action is the exception.
    @ViewBuilder
    private var nextActionLine: some View {
        if let title = summary.nextActionTitle {
            let todayKey = DateFormatters.todayKey()
            let dueLabel = summary.nextActionDueDate.flatMap {
                CadenceFocusSupport.dueLabel(forDueDateKey: $0, todayKey: todayKey)
            }
            let isOverdue = summary.nextActionDueDate.map {
                CadenceFocusSupport.isOverdue(dueDateKey: $0, todayKey: todayKey)
            } ?? false

            HStack(spacing: 7) {
                Text("Next")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .textCase(.uppercase)
                    .kerning(0.6)

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)

                if let dueLabel {
                    Text(dueLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isOverdue ? Theme.red : Theme.dim)
                        .lineLimit(1)
                        .layoutPriority(1)
                }

                Spacer(minLength: 0)
            }
        }
    }

    /// `.borderedProminent` / `.bordered` bring the OS's own material, radius and control height,
    /// so the same three actions rendered differently here than anywhere else in the app — and at
    /// well under 44pt. Same three actions, Cadence's own roles.
    private var actions: some View {
        HStack(spacing: 10) {
            iOSActionButton(
                title: "Edit",
                systemImage: "square.and.pencil",
                role: .primary,
                size: .compact,
                tint: tint,
                action: onEdit
            )

            // Green and amber said nothing here — they were not the goal's colour, not a status,
            // and not a warning. Two secondary actions, one secondary treatment.
            //
            // Only where a milestone can actually go. This detail serves milestones as well as
            // directions, and the button was unconditional, so from a milestone it created a
            // third-level goal that no screen draws — not in the list, not nested under anything,
            // and absent from the habit editor's goal picker. On iPad the save then selected it
            // and showed a detail pane for a goal with no row.
            if GoalAssignmentRules.canOwnMilestones(goal) {
                iOSActionButton(
                    title: "Milestone",
                    systemImage: "flag.fill",
                    role: .secondary,
                    size: .compact,
                    action: onNewMilestone
                )
            }

            iOSActionButton(
                title: "Habit",
                systemImage: "flame.fill",
                role: .secondary,
                size: .compact,
                action: onNewHabit
            )

            Spacer(minLength: 0)
        }
    }

    /// Two tiles, not four. The "Milestones" and "Habits" tiles counted the two sections directly
    /// below them — so a goal with milestones stated the number twice, and a goal without them
    /// showed a tile reading `0` above no section at all. The remaining pair are the only figures
    /// nothing else on the screen carries, and their icons are `Theme.dim`: four tiles in four
    /// colours encoded nothing but "these are four different tiles".
    private var metrics: some View {
        let summary = self.summary

        return HStack(spacing: 10) {
            iOSMetricTile(title: "Tasks", value: summary.taskCountLabel, icon: "checklist", color: Theme.dim)
            iOSMetricTile(title: "Focus", value: summary.focusLabel, icon: "timer", color: Theme.dim)
        }
    }
}

/// Diameter of the habit check-in control's hit area. It is also the width `iOSHabitSummaryRow`
/// reserves at its trailing edge, so the button `iOSHabitsView` layers on top lands exactly in
/// the gap the row left for it.
let iOSHabitCheckInSize: CGFloat = 44

/// The row's check-in control, deliberately a **sibling** of the row's select/navigate button
/// rather than a button nested inside its label: a nested button never receives the tap on iOS
/// (the enclosing `Button`/`NavigationLink` swallows it), so checking a habit off from the list
/// silently did nothing and just opened the detail instead.
struct iOSHabitCheckInButton: View {
    let habit: Habit
    let todayKey: String
    let action: () -> Void

    private var isDoneToday: Bool {
        habit.isDone(on: todayKey)
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: isDoneToday ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(isDoneToday ? Color(hex: habit.colorHex) : Theme.dim.opacity(0.55))
                .frame(width: iOSHabitCheckInSize, height: iOSHabitCheckInSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.iosPressable)
        .accessibilityLabel(isDoneToday ? "Undo check-in for \(habit.title)" : "Check in \(habit.title)")
    }
}

/// List row for a habit, matching the macOS `HabitListCard` vocabulary: colored icon tile,
/// title, then the one metadata line that actually answers "should I do this today" —
/// frequency, streak, and whether it is due.
struct iOSHabitSummaryRow: View {
    let habit: Habit
    let todayKey: String
    let isSelected: Bool

    private var isDoneToday: Bool {
        habit.isDone(on: todayKey)
    }

    var body: some View {
        // `currentStreak` walks the completion history day by day, so it is read once per row.
        let streak = habit.currentStreak

        return HStack(spacing: 12) {
            HabitIconTile(habit: habit, size: 34, iconSize: 15)

            VStack(alignment: .leading, spacing: 5) {
                Text(habit.title.isEmpty ? "Untitled Habit" : habit.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)

                HStack(spacing: 9) {
                    Text(habit.frequencySummary)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.subdued)
                        .lineLimit(1)

                    // A live streak is worth a colour; "no streak" is not, and rendering it amber
                    // gave the absence of a streak the same emphasis as a run of forty days.
                    // The unit comes from the frequency: `currentStreak` counts weeks for a
                    // `.timesPerWeek` habit, so a hardcoded "d" rendered eight kept weeks as "8d".
                    Text(streak > 0 ? "\(habit.streakUnit.shortLabel(streak)) streak" : "no streak")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(streak > 0 ? Theme.amber : Theme.dim)
                        .lineLimit(1)

                    // Only the outstanding half. The check-in control on this row already draws
                    // itself filled and in the habit's colour once today is done, so "Done today"
                    // beside it was the same fact stated twice.
                    if habit.isDueToday && !isDoneToday {
                        Text("Due today")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.blue)
                            .lineLimit(1)
                    }
                }

                // The goal a habit belongs to used to be this row's subtitle. Restyling replaced
                // it with frequency + streak and dropped it entirely, so the habits list stopped
                // saying which direction any habit served — it survived only in the detail's Goal
                // card. It reads as a quiet trailing note rather than competing with the title.
                if let goalTitle = habit.goal?.title, !goalTitle.isEmpty {
                    Text(goalTitle)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            // Reserved for the check-in button layered over the row.
            Color.clear
                .frame(width: iOSHabitCheckInSize, height: iOSHabitCheckInSize)
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .padding(.vertical, 10)
        .cadenceCard(
            background: isSelected ? Theme.surfaceElevated : Theme.surface,
            cornerRadius: Theme.radiusCard,
            shadowRadius: 12,
            shadowY: 5
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                .stroke(Color(hex: habit.colorHex).opacity(0.75), lineWidth: 1.5)
                .opacity(isSelected ? 1 : 0)
        )
    }
}

/// Habit detail, built from the same parts as the macOS `HabitDetailView`: a hero card carrying
/// the identity and the one action worth taking, the streak metrics, the goal the habit supports,
/// and the year-long activity grid.
struct iOSHabitDetail: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dismiss) private var dismiss

    let habit: Habit
    let todayKey: String
    let toggle: () -> Void
    var onEdit: () -> Void = {}
    /// Set on the compact push stack. See `iOSGoalDetail.showsBackControl`.
    var showsBackControl = false

    private var tint: Color {
        Color(hex: habit.colorHex)
    }

    private var isDoneToday: Bool {
        habit.isDone(on: todayKey)
    }

    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if showsBackControl && isCompact {
                    HStack(spacing: 0) {
                        iOSHeaderBackButton { dismiss() }
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, -8)
                }

                hero

                metrics

                // Only when there is a goal. An unlinked habit used to get a full titled card
                // wrapping one sentence explaining that the card had nothing in it.
                if habit.goal != nil {
                    HabitInfoCard(title: "Goal", padding: cardPadding) {
                        goalContent
                    }
                }

                HabitInfoCard(title: "Activity", padding: cardPadding) {
                    activityContent
                }
            }
            .padding(.horizontal, isCompact ? 16 : 20)
            .padding(.top, isCompact ? 8 : 20)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(Theme.bg)
        .iOSHidesCompactNavigationBar()
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                HabitIconTile(habit: habit, size: 52, iconSize: 22)

                VStack(alignment: .leading, spacing: 7) {
                    Text(habit.title.isEmpty ? "Untitled Habit" : habit.title)
                        .font(.system(size: isCompact ? 22 : 25, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)

                    Text(habit.frequencySummary)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }

            chips

            HStack(spacing: 10) {
                iOSActionButton(
                    title: isDoneToday ? "Undo Check-In" : "Check In Today",
                    systemImage: isDoneToday ? "arrow.uturn.backward" : "checkmark",
                    role: isDoneToday ? .secondary : .primary,
                    tint: isDoneToday ? Theme.green : tint,
                    fullWidth: true,
                    action: toggle
                )

                iOSIconButton(
                    systemImage: "square.and.pencil",
                    accessibilityLabel: "Edit habit",
                    plateSize: 44,
                    iconSize: 15,
                    action: onEdit
                )
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceCard(background: Theme.surface, cornerRadius: Theme.radiusPanel, shadowRadius: 16, shadowY: 6)
    }

    // MARK: - Metrics

    /// Current and Best were deliberately made to agree with each other (both go through
    /// `Habit`'s one definition of a streak); only their presentation is design-owned.
    ///
    /// Three neutral figures, so three `Theme.dim` glyphs. Amber, green and blue on the three tiles
    /// read as three different *kinds* of thing, which is not what a streak, a record streak and a
    /// completion rate are — the colour that means something on this screen is the habit's own, and
    /// it belongs to the icon tile, the check-in control and the heatmap.
    private var metrics: some View {
        HStack(spacing: 10) {
            iOSMetricTile(title: "Current", value: habit.streakUnit.shortLabel(habit.currentStreak), icon: "flame.fill", color: Theme.dim)
            iOSMetricTile(title: "Best", value: habit.streakUnit.shortLabel(habit.bestStreak), icon: "trophy.fill", color: Theme.dim)
            iOSMetricTile(title: habit.completionRateWindowLabel, value: "\(habit.last30DayCompletionRate)%", icon: "chart.bar.fill", color: Theme.dim)
        }
    }

    // MARK: - Goal

    /// Context and today's cadence, wrapping onto a second line rather than truncating.
    ///
    /// There used to be a third chip reading "Checked in" / "Pending", directly above a button
    /// reading "Undo Check-In" / "Check In Today" — the same fact, twice, in two vocabularies, with
    /// the chip in green and the button in green beside it. The button says it and can act on it,
    /// so the chip went.
    @ViewBuilder
    private var chips: some View {
        CadenceWrappingHStack(spacing: 8, lineSpacing: 8) {
            if let context = habit.context {
                iOSMetaChip(label: context.name, color: Color(hex: context.colorHex))
            }
            iOSMetaChip(
                label: habit.isDueToday ? "Due today" : "Not due today",
                color: habit.isDueToday ? Theme.blue : Theme.dim
            )
        }
    }

    private var cardPadding: CGFloat {
        isCompact ? 16 : 20
    }

    @ViewBuilder
    private var goalContent: some View {
        if let goal = habit.goal {
            HStack(spacing: 12) {
                iOSIconTile(systemImage: goal.icon, color: Color(hex: goal.colorHex), size: 38, iconSize: 16)

                VStack(alignment: .leading, spacing: 4) {
                    Text(goal.title.isEmpty ? "Untitled Goal" : goal.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Text(goal.desc.isEmpty ? "Recurring practice behind this goal" : goal.desc)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.subdued)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Activity

    private var activityContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            lastSevenDays

            Divider().background(Theme.borderSubtle.opacity(0.6))

            // A year of columns is wider than a phone, so the grid scrolls instead of being
            // shortened — the long arc is the whole point of it. Anchored trailing so it opens
            // on the current week.
            ScrollView(.horizontal) {
                HabitHeatmap(habit: habit)
            }
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(.trailing)
        }
    }

    private var lastSevenDays: some View {
        let states = habit.last7DayStates

        return VStack(alignment: .leading, spacing: 8) {
            Text("Last 7 days")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.subdued)

            HStack(spacing: 8) {
                ForEach(states.indices, id: \.self) { index in
                    let done = states[index]
                    VStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: Theme.radiusControl - 2, style: .continuous)
                            .fill(done ? tint : Theme.borderSubtle)
                            .frame(height: 26)
                        Text(recentDayLabel(offset: states.count - 1 - index))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.subdued)
                    }
                }
            }
        }
    }

    private func recentDayLabel(offset: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
        return DateFormatters.dayOfWeek.string(from: date)
    }
}
#endif
