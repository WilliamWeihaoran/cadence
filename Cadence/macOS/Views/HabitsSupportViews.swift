#if os(macOS)
import SwiftUI

struct HabitTodayCockpit: View {
    let dueCount: Int
    let doneCount: Int
    let openCount: Int
    let goalCoverage: String

    var body: some View {
        HStack(spacing: 12) {
            Text("Today")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.dim)
            Text("\(doneCount)/\(dueCount)")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.text)
            Text(openCount == 0 ? "done" : "\(openCount) open")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(openCount == 0 ? Theme.green : Theme.amber)
            Spacer()
            Label(goalCoverage, systemImage: "sparkles")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.blue)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .cadenceCard(background: Theme.surfaceElevated.opacity(0.65), cornerRadius: Theme.radiusControl, shadowRadius: 8, shadowY: 3)
    }
}

struct HabitSignalStrip: View {
    let streakingCount: Int
    let averageLast30Completion: Int
    let linkedCount: Int
    let totalCount: Int

    var body: some View {
        HStack(spacing: 10) {
            HabitInlineMetric(icon: "flame.fill", value: "\(streakingCount)", label: "streaking", color: Theme.amber)
            HabitInlineMetric(icon: "chart.bar.fill", value: "\(averageLast30Completion)%", label: "30d avg", color: Theme.blue)
            HabitInlineMetric(icon: "sparkles", value: "\(linkedCount)/\(totalCount)", label: "linked", color: Theme.green)
        }
    }
}

struct HabitInlineMetric: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.text)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceCard(background: Theme.bg.opacity(0.34), cornerRadius: Theme.radiusControl, shadowRadius: 6, shadowY: 2)
    }
}

struct HabitNextUpBanner: View {
    let habit: Habit
    let todayKey: String
    let onSelect: () -> Void
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HabitIconTile(habit: habit, size: 32, iconSize: 14)
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.dim)
                    Text(habit.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.cadencePlain)

            Button(action: onToggle) {
                Image(systemName: habit.isDone(on: todayKey) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(habit.isDone(on: todayKey) ? Theme.green : Color(hex: habit.colorHex))
            }
            .buttonStyle(.cadencePlain)
        }
        .padding(13)
        .cadenceCard(background: Color(hex: habit.colorHex).opacity(0.1), cornerRadius: Theme.radiusCard, shadowRadius: 10, shadowY: 4)
    }
}

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

                        Text(streak > 0 ? "\(streak)d streak" : "no streak")
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

struct HabitIconTile: View {
    let habit: Habit
    var size: CGFloat
    var iconSize: CGFloat

    var body: some View {
        CommitmentIconTile(
            systemImage: habit.icon,
            color: Color(hex: habit.colorHex),
            size: size,
            iconSize: iconSize,
            fillOpacity: 0.16
        )
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
                    HabitHeatmap(habit: habit)
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
            quietMetric("Streak", "\(habit.currentStreak)d")
            quietMetric("30 days", "\(habit.last30DayCompletionRate)%")
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

struct HabitSummaryTile: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                Text(value)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceCard(background: Theme.surface, cornerRadius: Theme.radiusCard, shadowRadius: 12, shadowY: 5)
    }
}

struct HabitDetailStatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)
            }
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.text)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceCard(background: Theme.surface, cornerRadius: Theme.radiusCard, shadowRadius: 12, shadowY: 5)
    }
}

struct HabitInfoCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .kerning(0.8)
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceCard(background: Theme.surface, cornerRadius: Theme.radiusCard, shadowRadius: 12, shadowY: 5)
    }
}

struct HabitMiniProgress: View {
    let label: String
    let value: String
    let detail: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(tint.opacity(0.16))
                .frame(width: 8, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                Text(value)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.text)
            }

            Spacer()

            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct HabitRecentStrip: View {
    let habit: Habit

    var body: some View {
        HStack(spacing: 5) {
            ForEach(habit.last7DayStates.indices, id: \.self) { index in
                Circle()
                    .fill(habit.last7DayStates[index] ? Color(hex: habit.colorHex) : Theme.borderSubtle)
                    .frame(width: 6, height: 6)
            }
            Text("\(habit.last7DayCount)/7")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.dim)
        }
    }
}

struct HabitTodayPlanPill: View {
    let title: String
    let detail: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Habit Heatmap

struct HabitHeatmap: View {
    let habit: Habit

    private let cellSize: CGFloat = 12
    private let gap: CGFloat = 2
    private let weeks = 52

    private var completionDates: Set<String> {
        Set((habit.completions ?? []).map { $0.date })
    }

    /// The heatmap's date math, pulled out of the view so it can be asserted on.
    ///
    /// The grid used to anchor on `today - weeks * 7` and then round *backwards* to the start of
    /// that week, so its last cell landed between one and seven days before today — today's own
    /// check-in never appeared, on any day of the week. (`isFuture` in the body was consequently
    /// unreachable, which is the clearest evidence the grid was meant to run through today.)
    /// Anchoring on the week containing today and counting back puts the current week in the
    /// final column, where a heatmap's most recent week belongs.
    enum HabitHeatmapGrid {
        static func startDate(weeks: Int, today: Date, calendar: Calendar) -> Date {
            let startOfToday = calendar.startOfDay(for: today)
            let weekday = calendar.component(.weekday, from: startOfToday)
            let startOfThisWeek = calendar.date(byAdding: .day, value: -(weekday - 1), to: startOfToday) ?? startOfToday
            return calendar.date(byAdding: .day, value: -(max(1, weeks) - 1) * 7, to: startOfThisWeek) ?? startOfThisWeek
        }

        /// Every `yyyy-MM-dd` key the grid draws, in render order.
        static func dateKeys(weeks: Int, today: Date, calendar: Calendar) -> [String] {
            let start = startDate(weeks: weeks, today: today, calendar: calendar)
            return (0..<(max(1, weeks) * 7)).compactMap { offset in
                calendar.date(byAdding: .day, value: offset, to: start).map {
                    DateFormatters.dateKey(from: $0, calendar: calendar)
                }
            }
        }
    }

    private var cal: Calendar { Calendar.current }

    private var startDate: Date {
        HabitHeatmapGrid.startDate(weeks: weeks, today: Date(), calendar: cal)
    }

    private var months: [(label: String, weekCol: Int)] {
        var result: [(String, Int)] = []
        var seenMonths = Set<Int>()
        for weekIdx in 0..<weeks {
            guard let weekStart = cal.date(byAdding: .day, value: weekIdx * 7, to: startDate) else { continue }
            let month = cal.component(.month, from: weekStart)
            if !seenMonths.contains(month) {
                seenMonths.insert(month)
                result.append((DateFormatters.monthAbbrev.string(from: weekStart), weekIdx))
            }
        }
        return result
    }

    var body: some View {
        let fmt = DateFormatters.ymd
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                Color.clear.frame(height: 16)
                ForEach(months, id: \.weekCol) { m in
                    Text(m.label)
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.dim)
                        .offset(x: CGFloat(m.weekCol) * (cellSize + gap))
                }
            }

            HStack(alignment: .top, spacing: gap) {
                ForEach(0..<weeks, id: \.self) { weekIdx in
                    VStack(spacing: gap) {
                        ForEach(0..<7, id: \.self) { dayOfWeek in
                            let dayOffset = weekIdx * 7 + dayOfWeek
                            let date = cal.date(byAdding: .day, value: dayOffset, to: startDate) ?? startDate
                            let key = fmt.string(from: date)
                            let isDone = completionDates.contains(key)
                            // Live now that the grid runs through the end of the current week:
                            // the days after today in that final column are drawn empty.
                            let isFuture = date > Date()

                            RoundedRectangle(cornerRadius: 2)
                                .fill(isFuture ? Color.clear : (isDone ? Color(hex: habit.colorHex) : Theme.borderSubtle))
                                .frame(width: cellSize, height: cellSize)
                        }
                    }
                }
            }
        }
    }
}
#endif
