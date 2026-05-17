#if os(macOS)
import SwiftUI
import SwiftData

extension Goal {
    var dependsOnGoalIDs: [UUID] {
        get {
            guard !dependsOnGoalIDsJSON.isEmpty,
                  let data = dependsOnGoalIDsJSON.data(using: .utf8),
                  let strings = try? JSONDecoder().decode([String].self, from: data)
            else { return [] }
            return strings.compactMap { UUID(uuidString: $0) }
        }
        set {
            let strings = newValue.map(\.uuidString)
            dependsOnGoalIDsJSON = (try? String(data: JSONEncoder().encode(strings), encoding: .utf8)) ?? ""
        }
    }
}

enum GoalStatusFilter: CaseIterable {
    case active, paused, done, all

    var label: String {
        switch self {
        case .active: return "Active"
        case .paused: return "Paused"
        case .done: return "Done"
        case .all: return "All"
        }
    }

    func matches(_ status: GoalStatus) -> Bool {
        switch self {
        case .all: return true
        case .active: return status == .active
        case .paused: return status == .paused
        case .done: return status == .done
        }
    }
}

struct GoalMissionGroup: Identifiable {
    let id: String
    let title: String
    let icon: String
    let colorHex: String
    let goals: [Goal]
}

struct GoalHeaderMetric: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 26, height: 26)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.surfaceElevated.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.borderSubtle, lineWidth: 1))
    }
}

struct GoalMissionGroupView: View {
    let group: GoalMissionGroup
    let selectedGoalID: UUID?
    let onSelect: (Goal) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CommitmentGroupHeader(
                title: group.title,
                icon: group.icon,
                color: Color(hex: group.colorHex),
                trailingText: "\(group.goals.count)"
            )

            VStack(spacing: 10) {
                ForEach(group.goals) { goal in
                    GoalMissionCard(
                        goal: goal,
                        isSelected: selectedGoalID == goal.id,
                        onSelect: { onSelect(goal) }
                    )
                }
            }
        }
    }
}

struct GoalMissionCard: View {
    let goal: Goal
    let isSelected: Bool
    let onSelect: () -> Void

    private var summary: GoalContributionSummary {
        GoalContributionResolver.summary(for: goal)
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 7) {
                            Text(goal.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.text)
                                .lineLimit(1)
                            GoalStatusBadge(status: goal.status)
                        }
                        Text(goal.desc.isEmpty ? "No definition of done yet" : goal.desc)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text(summary.percentLabel)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .monospacedDigit()
                }

                GoalProgressBar(progress: summary.progress, color: Color(hex: goal.colorHex), height: 4)

                HStack(spacing: 12) {
                    Label(summary.linkedListCount == 0 ? "No lists" : "\(summary.linkedListCount) lists", systemImage: "folder")
                    Label(summary.totalTasks == 0 ? "No tasks" : summary.taskCountLabel, systemImage: "checklist")
                    Spacer(minLength: 0)
                    Text(goal.daysSummary)
                        .foregroundStyle(goal.isOverdue ? Theme.red : Theme.dim)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .lineLimit(1)

                if let nextAction = summary.nextActionTitle {
                    Text(nextAction)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .padding(.top, 1)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Theme.blue.opacity(0.75) : Theme.borderSubtle, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.cadencePlain)
    }
}

struct GoalProgressOrb: View {
    let goal: Goal
    let summary: GoalContributionSummary
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: goal.colorHex).opacity(0.13))
            Circle()
                .trim(from: 0, to: max(0.025, summary.progress))
                .stroke(Color(hex: goal.colorHex), style: StrokeStyle(lineWidth: size > 50 ? 5 : 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(4)
            Text(summary.percentLabel)
                .font(.system(size: size > 50 ? 13 : 11, weight: .bold))
                .foregroundStyle(Theme.text)
        }
        .frame(width: size, height: size)
    }
}

struct GoalProgressBar: View {
    let progress: Double
    let color: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.borderSubtle.opacity(0.75))
                if progress > 0 {
                    Capsule()
                        .fill(color)
                        .frame(width: max(height, geo.size.width * progress))
                }
            }
        }
        .frame(height: height)
    }
}

struct GoalMetricChip: View {
    let icon: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

struct GoalSignalTile: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
        .padding(11)
        .background(Theme.surfaceElevated.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.borderSubtle, lineWidth: 1))
    }
}

struct GoalSectionHeading: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 7) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.dim)
            Text("\(count)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.text.opacity(0.75))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.surfaceElevated)
                .clipShape(Capsule())
            Spacer()
        }
    }
}

struct GoalLinkedListRow: View {
    let link: GoalListLink
    let onDetach: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: link.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: link.colorHex))
                .frame(width: 26, height: 26)
                .background(Color(hex: link.colorHex).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                Text(link.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text("\(link.tasks.filter { !$0.isCancelled }.count) contributing tasks")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.dim)
            }
            Spacer()
            Button(action: onDetach) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.cadencePlain)
        }
        .padding(9)
        .background(Theme.surfaceElevated.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}

struct GoalTaskContributorRow: View {
    let task: AppTask
    let onDetach: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(task.isDone ? Theme.green : Theme.dim)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(task.isDone ? Theme.dim : Theme.text)
                    .lineLimit(1)
                Text(task.containerName.isEmpty ? "Inbox" : task.containerName)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }
            Spacer()
            if let onDetach {
                Button(action: onDetach) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.cadencePlain)
            }
        }
        .padding(9)
        .background(Theme.surfaceElevated.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}

struct AttachListCandidateRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let isAttached: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 28, height: 28)
                    .background(color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.dim)
                }
                Spacer()
                Label(isAttached ? "Attached" : "Attach", systemImage: isAttached ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isAttached ? Theme.green : Theme.blue)
            }
            .padding(10)
            .background(isAttached ? Theme.green.opacity(0.08) : Theme.surfaceElevated.opacity(0.58))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isAttached ? Theme.green.opacity(0.22) : Theme.borderSubtle, lineWidth: 1))
        }
        .buttonStyle(.cadencePlain)
    }
}

struct GoalStatusBadge: View {
    let status: GoalStatus

    var body: some View {
        CommitmentMetaChip(label: label, color: color)
    }

    private var label: String {
        switch status {
        case .active: return "ACTIVE"
        case .paused: return "PAUSED"
        case .done: return "DONE"
        }
    }

    private var color: Color {
        switch status {
        case .active: return Theme.blue
        case .paused: return Theme.amber
        case .done: return Theme.green
        }
    }
}

struct GoalInlineEmpty: View {
    let text: String

    var body: some View {
        CommitmentInlineEmpty(text: text)
    }
}

struct GoalsEmptyDetail: View {
    var body: some View {
        CommitmentEmptyDetail(
            icon: "flag.fill",
            title: "Select a milestone",
            subtitle: "The inspector shows contributors, next actions, and momentum."
        )
    }
}

extension Goal {
    var startDateDate: Date? { DateFormatters.ymd.date(from: startDate) }
    var endDateDate: Date? { DateFormatters.ymd.date(from: endDate) }

    var rangeLabel: String {
        guard let s = startDateDate, let e = endDateDate else { return "No milestone range" }
        return "\(DateFormatters.shortDate.string(from: s)) - \(DateFormatters.shortDate.string(from: e))"
    }

    var progressSummary: String {
        GoalContributionResolver.summary(for: self).taskCountLabel
    }

    var daysSummary: String {
        guard let end = endDateDate else { return "No milestone date" }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: end).day ?? 0
        if status == .done { return "Completed" }
        if days < 0 { return "\(-days)d late" }
        if days == 0 { return "Due today" }
        return "\(days)d left"
    }

    var isOverdue: Bool {
        guard status != .done, let end = endDateDate else { return false }
        return end < Calendar.current.startOfDay(for: Date())
    }
}
#endif
