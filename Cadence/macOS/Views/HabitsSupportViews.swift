#if os(macOS)
import SwiftUI

struct HabitGoalSectionView: View {
    let group: HabitGoalGroup
    let todayKey: String
    let selectedHabitID: UUID?
    let onSelect: (Habit) -> Void
    let onToggle: (Habit) -> Void

    private var doneCount: Int {
        group.habits.filter { $0.isDone(on: todayKey) }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CommitmentGroupHeader(
                title: group.title,
                icon: group.icon,
                color: Color(hex: group.colorHex),
                trailingText: "\(doneCount)/\(group.habits.count)",
                trailingTint: Color(hex: group.colorHex)
            )

            VStack(spacing: 9) {
                ForEach(group.habits) { habit in
                    HabitListCard(
                        habit: habit,
                        todayKey: todayKey,
                        isSelected: selectedHabitID == habit.id,
                        onSelect: { onSelect(habit) },
                        onToggle: { onToggle(habit) }
                    )
                }
            }
        }
    }
}

struct HabitListCard: View {
    let habit: Habit
    let todayKey: String
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggle: () -> Void

    private var isDoneToday: Bool {
        habit.isDone(on: todayKey)
    }

    var body: some View {
        // `currentStreak` walks the habit's completion history day by day; reading it twice on
        // one line walked it twice per row per pass.
        let streak = habit.currentStreak

        return Button(action: onSelect) {
            HStack(spacing: 12) {
                HabitIconTile(habit: habit, size: 32, iconSize: 14)

                VStack(alignment: .leading, spacing: 5) {
                    Text(habit.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)

                    HStack(spacing: 10) {
                        Text(habit.frequencySummary)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.dim)

                        // Unit from the frequency: `currentStreak` counts weeks for `.timesPerWeek`.
                        Text(streak > 0 ? "\(habit.streakUnit.shortLabel(streak)) streak" : "no streak")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.amber)

                        if habit.isDueToday {
                            Text(isDoneToday ? "Done today" : "Due today")
                                .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(isDoneToday ? Theme.green : Theme.blue)
                        }
                    }
                }

                Spacer(minLength: 8)

                Button(action: onToggle) {
                    Image(systemName: isDoneToday ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(isDoneToday ? Color(hex: habit.colorHex) : Theme.dim.opacity(0.55))
                }
                .buttonStyle(.cadencePlain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .cadenceCard(
                background: isSelected ? Theme.surfaceElevated : Theme.surface,
                cornerRadius: Theme.radiusCard,
                shadowRadius: 12,
                shadowY: 5
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                    .stroke(Color(hex: habit.goal?.colorHex ?? habit.colorHex).opacity(0.75), lineWidth: 1.5)
                    .opacity(isSelected ? 1 : 0)
            )
        }
        .buttonStyle(.plain)
    }
}

struct HabitDetailView: View {
    let habit: Habit
    let todayKey: String
    let onToggle: () -> Void
    let onEdit: () -> Void

    private var totalCompletions: Int {
        (habit.completions ?? []).count
    }

    private var isDoneToday: Bool {
        habit.isDone(on: todayKey)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                habitHero

                HabitInfoCard(title: "Goal") {
                    HabitGoalSupportCard(habit: habit)
                }

                HabitQuietMetrics(habit: habit, totalCompletions: totalCompletions)

                HabitInfoCard(title: "Activity") {
                    VStack(alignment: .leading, spacing: 16) {
                        // The recent week and the long arc, in that order — the same two ranges
                        // the iOS habit detail already showed. `last7DayStates` was computed on
                        // the model and read only from iOS, so this is a rendering gap closing,
                        // not a second definition of a recent week.
                        HabitLast7DayStrip(habit: habit)

                        Divider().background(Theme.borderSubtle.opacity(0.6))

                        HabitHeatmap(habit: habit)
                    }
                }
            }
            .padding(24)
        }
        .background(Theme.bg)
    }

    private var habitHero: some View {
        HStack(alignment: .top, spacing: 16) {
            HabitIconTile(habit: habit, size: 56, iconSize: 24)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 10) {
                    Text(habit.title)
                        .font(.system(size: 25, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)

                    if let ctx = habit.context {
                        Text(ctx.name)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(hex: ctx.colorHex))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(hex: ctx.colorHex).opacity(0.14))
                            .clipShape(Capsule())
                    }
                }

                Text(habit.frequencySummary)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)

                HStack(spacing: 8) {
                    CommitmentMetaChip(label: habit.isDueToday ? "Due today" : "Not due today", color: habit.isDueToday ? Theme.blue : Theme.dim.opacity(0.8))
                    CommitmentMetaChip(label: isDoneToday ? "Checked in" : "Pending", color: isDoneToday ? Theme.green : Theme.amber)
                }
            }

            Spacer(minLength: 16)

            HStack(spacing: 8) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 34, height: 34)
                        .background(Theme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(Theme.borderSubtle, lineWidth: 1)
                        )
                }
                .buttonStyle(.cadencePlain)
                .help("Edit habit")

                CadenceActionButton(
                    title: isDoneToday ? "Undo" : "Check In Today",
                    systemImage: isDoneToday ? "arrow.uturn.backward" : "checkmark",
                    role: .primary,
                    size: .regular,
                    tint: isDoneToday ? Theme.green : Color(hex: habit.colorHex),
                    action: onToggle
                )
            }
        }
        .padding(22)
        .cadenceCard(background: Theme.surface, cornerRadius: Theme.radiusPanel, shadowRadius: 16, shadowY: 6)
    }
}

struct HabitQuietMetrics: View {
    let habit: Habit
    let totalCompletions: Int

    var body: some View {
        HStack(spacing: 18) {
            quietMetric("Streak", habit.streakUnit.shortLabel(habit.currentStreak))
            // `bestStreak` goes through `Habit`'s one definition of a streak, so it cannot
            // disagree with the figure beside it. It had an iOS reader and no macOS one, which
            // is why a record run was invisible on the desktop.
            quietMetric("Best", habit.streakUnit.shortLabel(habit.bestStreak))
            quietMetric(habit.completionRateWindowLabel, "\(habit.last30DayCompletionRate)%")
            quietMetric("Total", "\(totalCompletions)")
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private func quietMetric(_ label: String, _ value: String) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.dim)
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.text)
        }
    }
}

struct HabitGoalSupportCard: View {
    let habit: Habit

    var body: some View {
        if let goal = habit.goal {
            HStack(spacing: 12) {
                Image(systemName: goal.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: goal.colorHex))
                    .frame(width: 36, height: 36)
                    .background(Color(hex: goal.colorHex).opacity(0.13))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(goal.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Text(goal.desc.isEmpty ? "Recurring practice behind this goal" : goal.desc)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                }
                Spacer()
            }
        } else {
            HStack(spacing: 10) {
                Image(systemName: "circle.dashed")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 34, height: 34)
                    .background(Theme.surfaceElevated.opacity(0.75))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 3) {
                    Text("No goal")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Text("This habit is tracked independently.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                }
                Spacer()
            }
        }
    }
}

struct HabitsEmptyDetail: View {
    var body: some View {
        CommitmentEmptyDetail(
            icon: "flame.fill",
            title: "Select a habit",
            subtitle: "Pick a habit on the left to inspect streaks, recent activity, and consistency.",
            background: Theme.bg
        )
    }
}

#endif
