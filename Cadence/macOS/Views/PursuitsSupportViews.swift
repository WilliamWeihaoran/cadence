#if os(macOS)
import SwiftUI

struct PursuitContextGroup: Identifiable {
    let id: String
    let title: String
    let icon: String
    let colorHex: String
    let pursuits: [Pursuit]
}

struct PursuitUnassignedReviewCard: View {
    let goalCount: Int
    let habitCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.amber)
                Text("UNASSIGNED")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.dim)
                Spacer()
            }

            Text("Assign existing goals and habits to pursuits as you review them.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Text("\(goalCount) goals")
                Text("\(habitCount) habits")
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.amber)
        }
        .padding(12)
        .background(Theme.surfaceElevated.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.amber.opacity(0.22), lineWidth: 1))
    }
}

struct PursuitContextGroupView: View {
    let group: PursuitContextGroup
    let selectedPursuitID: UUID?
    let onSelect: (Pursuit) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: group.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: group.colorHex))
                Text(group.title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                Spacer()
            }

            VStack(spacing: 9) {
                ForEach(group.pursuits) { pursuit in
                    PursuitListCard(
                        pursuit: pursuit,
                        isSelected: selectedPursuitID == pursuit.id,
                        onSelect: { onSelect(pursuit) }
                    )
                }
            }
        }
    }
}

struct PursuitListCard: View {
    let pursuit: Pursuit
    let isSelected: Bool
    let onSelect: () -> Void

    private var activeGoals: [Goal] {
        (pursuit.goals ?? []).filter { $0.status == .active }
    }

    private var habits: [Habit] {
        pursuit.habits ?? []
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: pursuit.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: pursuit.colorHex))
                    .frame(width: 34, height: 34)
                    .background(Color(hex: pursuit.colorHex).opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 5) {
                    Text(pursuit.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    HStack(spacing: 10) {
                        Text("\(activeGoals.count) goals")
                        Text("\(habits.count) habits")
                        Text(pursuit.status.label)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.dim)
                }

                Spacer()
            }
            .padding(12)
            .background(isSelected ? Theme.surfaceElevated : Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color(hex: pursuit.colorHex).opacity(0.65) : Theme.borderSubtle, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct PursuitDetailView: View {
    let pursuit: Pursuit
    let onEdit: () -> Void
    @State private var showAddGoal = false
    @State private var showAddHabit = false

    private var goals: [Goal] {
        (pursuit.goals ?? []).sorted { $0.order < $1.order }
    }

    private var habits: [Habit] {
        (pursuit.habits ?? []).sorted { $0.order < $1.order }
    }

    private var activeGoalCount: Int {
        goals.filter { $0.status == .active }.count
    }

    private var dueHabitsToday: [Habit] {
        habits.filter(\.isDueToday)
    }

    private var doneHabitsToday: Int {
        dueHabitsToday.filter { $0.isDone(on: DateFormatters.todayKey()) }.count
    }

    private var nextActionTitle: String? {
        goals.compactMap { GoalContributionResolver.summary(for: $0).nextActionTitle }.first
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                hero
                signalRow
                commitmentActions
                goalsSection
                habitsSection
            }
            .padding(24)
        }
        .background(Theme.bg)
        .sheet(isPresented: $showAddGoal) {
            CreateGoalSheet(pursuit: pursuit)
        }
        .sheet(isPresented: $showAddHabit) {
            CreateHabitSheet(pursuit: pursuit)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: pursuit.icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color(hex: pursuit.colorHex))
                    .frame(width: 54, height: 54)
                    .background(Color(hex: pursuit.colorHex).opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(pursuit.title)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(2)
                        PursuitStatusBadge(status: pursuit.status)
                    }
                    Text(pursuit.desc.isEmpty ? "No direction yet" : pursuit.desc)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if let context = pursuit.context {
                        Text(context.name)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(hex: context.colorHex))
                    }
                }

                Spacer()

                CadenceActionButton(
                    title: "Edit",
                    systemImage: "pencil",
                    role: .secondary,
                    size: .compact,
                    tint: Color(hex: pursuit.colorHex),
                    action: onEdit
                )
            }
        }
        .padding(18)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: pursuit.colorHex).opacity(0.24), lineWidth: 1))
    }

    private var signalRow: some View {
        HStack(spacing: 12) {
            PursuitSignalTile(title: "Active Goals", value: "\(activeGoalCount)", icon: "target", color: Theme.green)
            PursuitSignalTile(title: "Habits Today", value: dueHabitsToday.isEmpty ? "None due" : "\(doneHabitsToday)/\(dueHabitsToday.count)", icon: "flame.fill", color: Theme.amber)
            PursuitSignalTile(title: "Next Action", value: nextActionTitle ?? "None", icon: "checklist", color: Theme.blue)
        }
    }

    private var commitmentActions: some View {
        HStack(spacing: 10) {
            CadenceActionButton(
                title: "Add Goal",
                systemImage: "target",
                role: .secondary,
                size: .compact,
                tint: Theme.green,
                fullWidth: true
            ) {
                showAddGoal = true
            }

            CadenceActionButton(
                title: "Add Habit",
                systemImage: "flame.fill",
                role: .secondary,
                size: .compact,
                tint: Theme.amber,
                fullWidth: true
            ) {
                showAddHabit = true
            }
        }
    }

    @ViewBuilder
    private var goalsSection: some View {
        PursuitSection(title: "Goals", count: goals.count) {
            if goals.isEmpty {
                PursuitEmptySectionText("No goals in this pursuit yet.")
            } else {
                VStack(spacing: 8) {
                    ForEach(goals) { goal in
                        PursuitGoalRow(goal: goal)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var habitsSection: some View {
        PursuitSection(title: "Habits", count: habits.count) {
            if habits.isEmpty {
                PursuitEmptySectionText("No habits in this pursuit yet.")
            } else {
                VStack(spacing: 8) {
                    ForEach(habits) { habit in
                        PursuitHabitRow(habit: habit)
                    }
                }
            }
        }
    }
}

private struct PursuitSignalTile: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                Text(value)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.borderSubtle, lineWidth: 1))
    }
}

private struct PursuitSection<Content: View>: View {
    let title: String
    let count: Int
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.text.opacity(0.72))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.surfaceElevated)
                    .clipShape(Capsule())
                Spacer()
            }
            content
        }
        .padding(16)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.borderSubtle, lineWidth: 1))
    }
}

private struct PursuitGoalRow: View {
    let goal: Goal

    private var summary: GoalContributionSummary {
        GoalContributionResolver.summary(for: goal)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "target")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: goal.colorHex))
                .frame(width: 28, height: 28)
                .background(Color(hex: goal.colorHex).opacity(0.13))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(goal.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(goal.desc.isEmpty ? "No outcome yet" : goal.desc)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }
            Spacer()
            Text(summary.percentLabel)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.text)
                .monospacedDigit()
        }
        .padding(10)
        .background(Theme.surfaceElevated.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct PursuitHabitRow: View {
    let habit: Habit

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: habit.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: habit.colorHex))
                .frame(width: 28, height: 28)
                .background(Color(hex: habit.colorHex).opacity(0.13))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(habit.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(habit.frequencySummary)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
            }
            Spacer()
            Text(habit.currentStreak > 0 ? "\(habit.currentStreak)d" : "No streak")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(habit.currentStreak > 0 ? Theme.amber : Theme.dim)
        }
        .padding(10)
        .background(Theme.surfaceElevated.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct PursuitEmptySectionText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Theme.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Theme.surfaceElevated.opacity(0.36))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct PursuitStatusBadge: View {
    let status: PursuitStatus

    var body: some View {
        Text(status.label)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private var color: Color {
        switch status {
        case .active: return Theme.green
        case .paused: return Theme.amber
        case .done: return Theme.blue
        }
    }
}
#endif
