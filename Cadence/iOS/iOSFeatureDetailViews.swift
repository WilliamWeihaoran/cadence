#if os(iOS)
import SwiftData
import SwiftUI

/// One detail surface for every goal, top-level or nested. A top-level goal reads as a
/// direction that owns milestones and habits; a nested goal reads as a milestone of its parent.
struct iOSGoalDetail: View {
    let goal: Goal
    var milestones: [Goal] = []
    var habits: [Habit] = []
    var onEdit: () -> Void = {}
    var onNewMilestone: () -> Void = {}
    var onNewHabit: () -> Void = {}
    var onSelectMilestone: ((Goal) -> Void)? = nil

    private var summary: GoalContributionSummary {
        GoalContributionResolver.summary(for: goal)
    }

    private var tint: Color {
        Color(hex: goal.colorHex)
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
            VStack(alignment: .leading, spacing: 20) {
                hero

                actions

                metrics

                if let nextActionTitle = summary.nextActionTitle {
                    iOSFeatureSection(title: "Next Action") {
                        iOSFeatureSummaryRow(
                            title: nextActionTitle,
                            subtitle: "Highest priority open task",
                            icon: "arrow.right.circle.fill",
                            color: Theme.blue
                        )
                    }
                }

                if !milestones.isEmpty {
                    iOSFeatureSection(title: "Milestones") {
                        ForEach(milestones) { milestone in
                            milestoneRow(milestone)
                        }
                    }
                }

                if !habits.isEmpty {
                    iOSFeatureSection(title: "Habits") {
                        ForEach(habits) { habit in
                            iOSFeatureSummaryRow(
                                title: habit.title.isEmpty ? "Untitled Habit" : habit.title,
                                subtitle: habit.frequencySummary,
                                detail: "\(habit.currentStreak)d",
                                icon: habit.icon,
                                color: Color(hex: habit.colorHex)
                            )
                        }
                    }
                }

                iOSFeatureSection(title: "Linked Work") {
                    iOSFeatureSummaryRow(
                        title: "\(summary.linkedListCount) linked lists",
                        subtitle: "\(summary.overdueTaskCount) overdue, \(summary.recentCompletedCount) recent completions",
                        icon: "folder.fill",
                        color: Theme.green
                    )
                }
            }
            .padding(20)
        }
        .background(Theme.bg)
    }

    /// Identity, the two badges macOS shows beside a goal's title (kind and status), and the
    /// progress bar — all inside one card, so the goal's headline facts read as one object rather
    /// than a floating hero followed by an unlabelled system `ProgressView`.
    private var hero: some View {
        let summary = self.summary

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                iOSIconTile(systemImage: goal.icon, color: tint, size: 48, iconSize: 22, cornerRadius: Theme.radiusControl)

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

            GoalProgressBar(progress: summary.progress, color: tint, height: 5)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceCard(background: Theme.surface, cornerRadius: Theme.radiusPanel, shadowRadius: 16, shadowY: 6)
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

            iOSActionButton(
                title: "Milestone",
                systemImage: "flag.fill",
                role: .secondary,
                size: .compact,
                tint: Theme.green,
                action: onNewMilestone
            )

            iOSActionButton(
                title: "Habit",
                systemImage: "flame.fill",
                role: .secondary,
                size: .compact,
                tint: Theme.amber,
                action: onNewHabit
            )

            Spacer(minLength: 0)
        }
    }

    /// Five tiles, not six: "Progress" and "Status" both moved into the hero, where the percentage
    /// now sits beside the bar that draws it and the status reads as the badge macOS shows.
    private var metrics: some View {
        let summary = self.summary

        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                iOSMetricTile(title: "Tasks", value: summary.taskCountLabel, icon: "checklist", color: Theme.blue)
                iOSMetricTile(title: "Focus", value: summary.focusLabel, icon: "timer", color: Theme.amber)
            }
            HStack(spacing: 10) {
                iOSMetricTile(title: "Milestones", value: "\(milestones.count)", icon: "flag.fill", color: Theme.green)
                iOSMetricTile(title: "Habits", value: "\(habits.count)", icon: "flame.fill", color: Theme.amber)
            }
        }
    }

    @ViewBuilder
    private func milestoneRow(_ milestone: Goal) -> some View {
        let milestoneSummary = GoalContributionResolver.summary(for: milestone)
        let row = iOSFeatureSummaryRow(
            title: milestone.title.isEmpty ? "Untitled Goal" : milestone.title,
            subtitle: milestoneSummary.nextActionTitle ?? milestone.status.label,
            detail: milestoneSummary.percentLabel,
            icon: milestone.icon,
            color: Color(hex: milestone.colorHex)
        )

        if let onSelectMilestone {
            Button {
                onSelectMilestone(milestone)
            } label: {
                row
            }
            .buttonStyle(.iosPressable)
        } else {
            row
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

                    Text(streak > 0 ? "\(streak)d streak" : "no streak")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.amber)
                        .lineLimit(1)

                    if habit.isDueToday {
                        Text(isDoneToday ? "Done today" : "Due today")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(isDoneToday ? Theme.green : Theme.blue)
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

    let habit: Habit
    let todayKey: String
    let toggle: () -> Void
    var onEdit: () -> Void = {}

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
                hero

                metrics

                HabitInfoCard(title: "Goal", padding: cardPadding) {
                    goalContent
                }

                HabitInfoCard(title: "Activity", padding: cardPadding) {
                    activityContent
                }
            }
            .padding(isCompact ? 16 : 20)
        }
        .scrollIndicators(.hidden)
        .background(Theme.bg)
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
    private var metrics: some View {
        HStack(spacing: 10) {
            iOSMetricTile(title: "Current", value: "\(habit.currentStreak)d", icon: "flame.fill", color: Theme.amber)
            iOSMetricTile(title: "Best", value: "\(habit.bestStreak)d", icon: "trophy.fill", color: Theme.green)
            iOSMetricTile(title: "30 days", value: "\(habit.last30DayCompletionRate)%", icon: "chart.bar.fill", color: Theme.blue)
        }
    }

    // MARK: - Goal

    /// Context / due / checked-in, on one line where they fit and two where they do not. A
    /// single `HStack` truncated one of them on an iPhone, and half a "Checked in" is worse
    /// than a second row.
    @ViewBuilder
    private var chips: some View {
        let context = habit.context
        let dueChip = iOSMetaChip(
            label: habit.isDueToday ? "Due today" : "Not due today",
            color: habit.isDueToday ? Theme.blue : Theme.dim
        )
        let stateChip = iOSMetaChip(
            label: isDoneToday ? "Checked in" : "Pending",
            color: isDoneToday ? Theme.green : Theme.amber
        )

        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                if let context {
                    iOSMetaChip(label: context.name, color: Color(hex: context.colorHex))
                }
                dueChip
                stateChip
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 8) {
                if let context {
                    iOSMetaChip(label: context.name, color: Color(hex: context.colorHex))
                }
                HStack(spacing: 8) {
                    dueChip
                    stateChip
                    Spacer(minLength: 0)
                }
            }
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
        } else {
            iOSInlineEmpty(text: "Not linked to a goal — this habit is tracked on its own.")
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
