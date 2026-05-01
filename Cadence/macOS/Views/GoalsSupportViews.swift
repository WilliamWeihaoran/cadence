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
            HStack(spacing: 8) {
                Image(systemName: group.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: group.colorHex))
                Text(group.title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                Text("\(group.goals.count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.text.opacity(0.75))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.surfaceElevated)
                    .clipShape(Capsule())
                Spacer()
            }

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
                        Text(goal.desc.isEmpty ? "No outcome yet" : goal.desc)
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

struct GoalInspectorView: View {
    let goal: Goal
    let onEdit: () -> Void
    let onAttachWork: () -> Void
    let onDetachList: (GoalListLink) -> Void

    private var summary: GoalContributionSummary {
        GoalContributionResolver.summary(for: goal)
    }

    private var habitMomentum: GoalHabitMomentumSummary {
        GoalHabitMomentumResolver.summary(for: goal)
    }

    private var linkedLists: [GoalListLink] {
        (goal.listLinks ?? [])
            .filter { $0.area != nil || $0.project != nil }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var contributingTasks: [AppTask] {
        GoalContributionResolver.contributingTasks(for: goal)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                inspectorHeader
                contributorLists
                allWorkSection
            }
            .padding(20)
        }
        .background(Theme.surface)
    }

    private var inspectorHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(goal.title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                GoalStatusBadge(status: goal.status)
                Spacer(minLength: 0)
            }

            Text(goal.desc.isEmpty ? "No outcome yet" : goal.desc)
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(summary.percentLabel)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .monospacedDigit()
                    Text("complete")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.dim)
                    Spacer()
                    Text(goal.daysSummary)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(goal.isOverdue ? Theme.red : Theme.dim)
                }
                GoalProgressBar(progress: summary.progress, color: Color(hex: goal.colorHex), height: 5)
            }

            HStack(spacing: 8) {
                CadenceActionButton(
                    title: "Edit",
                    systemImage: "pencil",
                    role: .secondary,
                    size: .compact,
                    action: onEdit
                )
                CadenceActionButton(
                    title: "Attach List",
                    systemImage: "plus",
                    role: .secondary,
                    size: .compact,
                    action: onAttachWork
                )
                Spacer()
            }
        }
    }

    private var signalGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            GoalSignalTile(title: "Deadline", value: goal.daysSummary, icon: "flag.fill", color: goal.isOverdue ? Theme.red : Theme.amber)
            GoalSignalTile(title: "Focus", value: summary.focusLabel, icon: "clock.fill", color: Theme.blue)
            GoalSignalTile(title: "Momentum", value: "\(summary.recentCompletedCount) done", icon: "sparkline", color: Theme.green)
            GoalSignalTile(title: "Habit Momentum", value: habitMomentum.linkedHabitCount == 0 ? "No habits" : habitMomentum.dueTodayLabel, icon: "flame.fill", color: habitMomentum.doneTodayCount >= habitMomentum.dueTodayCount && habitMomentum.dueTodayCount > 0 ? Theme.green : Theme.amber)
            GoalSignalTile(title: "Overdue", value: "\(summary.overdueTaskCount)", icon: "exclamationmark.triangle.fill", color: summary.overdueTaskCount > 0 ? Theme.red : Theme.dim)
        }
    }

    private var contributorLists: some View {
        VStack(alignment: .leading, spacing: 10) {
            GoalSectionHeading(title: "Linked Lists", count: linkedLists.count)
            if linkedLists.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No lists attached")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("Attach one area or project. Its active tasks will count toward this goal.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Theme.surfaceElevated.opacity(0.38))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                VStack(spacing: 8) {
                    ForEach(linkedLists) { link in
                        GoalLinkedListRow(link: link, onDetach: { onDetachList(link) })
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var allWorkSection: some View {
        if !contributingTasks.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                GoalSectionHeading(title: "Contributing Work", count: contributingTasks.count)
                VStack(spacing: 8) {
                    ForEach(contributingTasks.prefix(8)) { task in
                        GoalTaskContributorRow(task: task, onDetach: nil)
                    }
                }
            }
        }
    }
}

struct AttachWorkSheet: View {
    let goal: Goal
    let contexts: [Context]
    let areas: [Area]
    let projects: [Project]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var groupedLists: [(context: Context?, areas: [Area], projects: [Project])] {
        var result: [(Context?, [Area], [Project])] = contexts.compactMap { context in
            let contextAreas = areas
                .filter { $0.context?.id == context.id && matches($0.name) }
                .sorted { $0.order < $1.order }
            let contextProjects = projects
                .filter { $0.context?.id == context.id && matches($0.name) }
                .sorted { $0.order < $1.order }
            guard !contextAreas.isEmpty || !contextProjects.isEmpty else { return nil }
            return (context, contextAreas, contextProjects)
        }

        let unfiledAreas = areas.filter { $0.context == nil && matches($0.name) }
        let unfiledProjects = projects.filter { $0.context == nil && matches($0.name) }
        if !unfiledAreas.isEmpty || !unfiledProjects.isEmpty {
            result.append((nil, unfiledAreas, unfiledProjects))
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Attach Lists")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Text(goal.title)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                Spacer()
                CadenceActionButton(title: "Done", role: .secondary, size: .compact) {
                    dismiss()
                }
            }
            .padding(20)

            Divider().background(Theme.borderSubtle)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
                TextField("Search lists", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.borderSubtle, lineWidth: 1))
            .padding(16)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    attachListsSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
            }
        }
        .frame(width: 620, height: 700)
        .background(Theme.surface)
    }

    private var attachListsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GoalSectionHeading(title: "Lists", count: groupedLists.reduce(0) { $0 + $1.areas.count + $1.projects.count })
            if groupedLists.isEmpty {
                GoalInlineEmpty(text: "No matching lists.")
            } else {
                ForEach(Array(groupedLists.enumerated()), id: \.offset) { _, group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text((group.context?.name ?? "No Context").uppercased())
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(group.context.map { Color(hex: $0.colorHex) } ?? Theme.dim)
                            .padding(.top, 4)
                        ForEach(group.areas) { area in
                            AttachListCandidateRow(
                                icon: area.icon,
                                title: area.name,
                                subtitle: "\(area.tasks?.filter { !$0.isCancelled }.count ?? 0) active tasks",
                                color: Color(hex: area.colorHex),
                                isAttached: isAttached(area: area),
                                onToggle: { toggle(area: area) }
                            )
                        }
                        ForEach(group.projects) { project in
                            AttachListCandidateRow(
                                icon: project.icon,
                                title: project.name,
                                subtitle: "\(project.tasks?.filter { !$0.isCancelled }.count ?? 0) active tasks",
                                color: Color(hex: project.colorHex),
                                isAttached: isAttached(project: project),
                                onToggle: { toggle(project: project) }
                            )
                        }
                    }
                }
            }
        }
    }

    private func matches(_ text: String) -> Bool {
        query.isEmpty || text.lowercased().contains(query)
    }

    private func isAttached(area: Area) -> Bool {
        (goal.listLinks ?? []).contains { $0.pointsTo(area: area) }
    }

    private func isAttached(project: Project) -> Bool {
        (goal.listLinks ?? []).contains { $0.pointsTo(project: project) }
    }

    private func toggle(area: Area) {
        if let existing = (goal.listLinks ?? []).first(where: { $0.pointsTo(area: area) }) {
            modelContext.delete(existing)
        } else {
            modelContext.insert(GoalListLink(goal: goal, area: area))
        }
    }

    private func toggle(project: Project) {
        if let existing = (goal.listLinks ?? []).first(where: { $0.pointsTo(project: project) }) {
            modelContext.delete(existing)
        } else {
            modelContext.insert(GoalListLink(goal: goal, project: project))
        }
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
        Text(label)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
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
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Theme.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Theme.surfaceElevated.opacity(0.38))
            .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}

struct GoalsEmptyDetail: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "target")
                .font(.system(size: 32))
                .foregroundStyle(Theme.dim)
            Text("Select a goal")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text("The inspector shows contributors, next actions, and momentum.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface)
    }
}

extension Goal {
    var startDateDate: Date? { DateFormatters.ymd.date(from: startDate) }
    var endDateDate: Date? { DateFormatters.ymd.date(from: endDate) }

    var rangeLabel: String {
        guard let s = startDateDate, let e = endDateDate else { return "No target range" }
        return "\(DateFormatters.shortDate.string(from: s)) - \(DateFormatters.shortDate.string(from: e))"
    }

    var progressSummary: String {
        GoalContributionResolver.summary(for: self).taskCountLabel
    }

    var daysSummary: String {
        guard let end = endDateDate else { return "No target date" }
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
