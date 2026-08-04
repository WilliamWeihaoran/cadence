import SwiftData
import SwiftUI
import WidgetKit

struct MilestoneMomentumWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: CadenceMilestoneWidgetSnapshot
}

struct MilestoneMomentumWidgetProvider: TimelineProvider {
    typealias Entry = MilestoneMomentumWidgetEntry

    func placeholder(in context: TimelineProviderContext) -> MilestoneMomentumWidgetEntry {
        MilestoneMomentumWidgetEntry(
            date: Date(),
            snapshot: placeholderSnapshot()
        )
    }

    func getSnapshot(in context: TimelineProviderContext, completion: @escaping (MilestoneMomentumWidgetEntry) -> Void) {
        completion(
            MilestoneMomentumWidgetEntry(
                date: Date(),
                snapshot: currentSnapshot()
            )
        )
    }

    func getTimeline(in context: TimelineProviderContext, completion: @escaping (Timeline<MilestoneMomentumWidgetEntry>) -> Void) {
        let entry = MilestoneMomentumWidgetEntry(
            date: Date(),
            snapshot: currentSnapshot()
        )
        completion(
            Timeline(
                entries: [entry],
                policy: .after(CadenceMilestoneWidgetSupport.recommendedReloadDate(for: entry.snapshot))
            )
        )
    }

    private func placeholderSnapshot() -> CadenceMilestoneWidgetSnapshot {
        let goals = [
            placeholderGoal(title: "Launch habit widgets", colorHex: "#6FA8FF", progress: 0.68, overdue: 2, nextAction: "Ship the interactive check-in flow", linkedHabitCount: 4, dueTodayLabel: "2/4 today"),
            placeholderGoal(title: "Summer reading rhythm", colorHex: "#FFB347", progress: 0.42, overdue: 0, nextAction: "Finish weekly review and sync notes", linkedHabitCount: 3, dueTodayLabel: "1/2 today"),
            placeholderGoal(title: "Quarter planning reset", colorHex: "#8FE1D6", progress: 0.21, overdue: 1, nextAction: "Break down remaining planning tasks", linkedHabitCount: 1, dueTodayLabel: "No habits due"),
            placeholderGoal(title: "Marathon base block", colorHex: "#FF7F7F", progress: 0.74, overdue: 0, nextAction: "Plan the next long run", linkedHabitCount: 2, dueTodayLabel: "1/1 today"),
        ]

        return CadenceMilestoneWidgetSnapshot(
            date: Date(),
            state: .ready,
            statusMessage: nil,
            totalGoalCount: goals.count,
            totalOverdueTaskCount: goals.reduce(0) { $0 + $1.overdueTaskCount },
            visibleGoals: goals
        )
    }

    private func currentSnapshot() -> CadenceMilestoneWidgetSnapshot {
        do {
            let container = try CadenceStoreSupport.makePrimaryContainer(
                allowsSave: false,
                cloudKitDatabase: .none
            )
            let modelContext = ModelContext(container)
            return try CadenceMilestoneWidgetSupport.snapshot(
                modelContext: modelContext,
                limit: 5
            )
        } catch {
            return CadenceMilestoneWidgetSupport.unavailableSnapshot()
        }
    }

    private func placeholderGoal(
        title: String,
        colorHex: String,
        progress: Double,
        overdue: Int,
        nextAction: String,
        linkedHabitCount: Int,
        dueTodayLabel: String
    ) -> CadenceMilestoneWidgetGoal {
        CadenceMilestoneWidgetGoal(
            id: UUID(),
            title: title,
            colorHex: colorHex,
            percentLabel: "\(Int((progress * 100).rounded()))%",
            progress: progress,
            overdueTaskCount: overdue,
            nextActionTitle: nextAction,
            linkedHabitCount: linkedHabitCount,
            dueTodayLabel: dueTodayLabel
        )
    }
}

struct CadenceMilestoneMomentumWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: CadenceWidgetRefreshCenter.milestoneWidgetKind,
            provider: MilestoneMomentumWidgetProvider()
        ) { entry in
            MilestoneMomentumWidgetView(entry: entry)
        }
        .configurationDisplayName("Milestone Momentum")
        .description("Track the milestones that need attention right now.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}

struct MilestoneMomentumWidgetView: View {
    let entry: MilestoneMomentumWidgetEntry

    @Environment(\.widgetFamily) private var widgetFamily
    private var scale: CadenceWidgetScale { .forFamily(widgetFamily) }

    var body: some View {
        Group {
            switch widgetFamily {
            case .systemSmall:
                smallLayout
            case .systemMedium:
                mediumLayout
            case .systemLarge:
                largeLayout
            default:
                extraLargeLayout
            }
        }
        .cadenceWidgetBackground([
            Color(red: 0.11, green: 0.08, blue: 0.14),
            Color(red: 0.16, green: 0.10, blue: 0.20),
        ])
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: scale.sectionSpacing) {
            header
            if entry.snapshot.isUnavailable {
                unavailableState
            } else if let goal = entry.snapshot.visibleGoals.first {
                heroCard(goal: goal, compact: true)
            } else {
                emptyState
            }
        }
        .padding(scale.outerPadding)
    }

    private var mediumLayout: some View {
        VStack(alignment: .leading, spacing: scale.sectionSpacing) {
            header
            if entry.snapshot.isUnavailable {
                unavailableState
            } else if entry.snapshot.visibleGoals.isEmpty {
                emptyState
            } else {
                VStack(spacing: scale.compactSectionSpacing) {
                    ForEach(entry.snapshot.visibleGoals.prefix(3)) { goal in
                        goalRow(goal, compact: false)
                    }
                }
            }
        }
        .padding(scale.outerPadding)
    }

    private var largeLayout: some View {
        VStack(alignment: .leading, spacing: scale.sectionSpacing) {
            header
            if entry.snapshot.isUnavailable {
                unavailableState
            } else if let first = entry.snapshot.visibleGoals.first {
                HStack(alignment: .top, spacing: scale.sectionSpacing) {
                    heroCard(goal: first, compact: false)
                    sidePanel
                }

                VStack(spacing: scale.compactSectionSpacing) {
                    ForEach(entry.snapshot.visibleGoals.dropFirst()) { goal in
                        goalRow(goal, compact: true)
                    }
                }
            } else {
                emptyState
            }
        }
        .padding(scale.outerPadding)
    }

    private var extraLargeLayout: some View {
        VStack(alignment: .leading, spacing: scale.sectionSpacing) {
            header
            if entry.snapshot.isUnavailable {
                unavailableState
            } else if entry.snapshot.visibleGoals.isEmpty {
                emptyState
            } else {
                HStack(alignment: .top, spacing: scale.sectionSpacing) {
                    VStack(alignment: .leading, spacing: scale.sectionSpacing) {
                        if let first = entry.snapshot.visibleGoals.first {
                            heroCard(goal: first, compact: false)
                        }
                        footerLink
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: scale.compactSectionSpacing) {
                        ForEach(entry.snapshot.visibleGoals.dropFirst()) { goal in
                            goalRow(goal, compact: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(scale.outerPadding)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: scale.compactSectionSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text(headerTitle)
                    .font(.system(size: scale.titleSize, weight: .bold))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                Text("\(entry.snapshot.totalGoalCount)")
                    .font(.system(size: scale.countSize, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.8)
            }

            HStack(spacing: 5) {
                ForEach(headerBadges) { badge in
                    CadenceWidgetBadge(text: badge.text, tint: badge.tint)
                }
            }
        }
    }

    private func heroCard(goal: CadenceMilestoneWidgetGoal, compact: Bool) -> some View {
        Link(destination: entry.snapshot.goalsURL) {
            VStack(alignment: .leading, spacing: scale.compactSectionSpacing) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(compact ? "Priority" : "Priority milestone")
                            .font(.system(size: scale.captionFontSize, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.58))
                        Text(goal.title)
                            .font(.system(size: compact ? scale.bodyFontSize + 2 : scale.titleSize, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(compact ? 3 : 2)
                            .minimumScaleFactor(0.85)
                    }
                    Spacer(minLength: 10)
                    Text(goal.percentLabel)
                        .font(.system(size: compact ? scale.metricValueSize : scale.metricValueSize + 3, weight: .black, design: .rounded))
                        .foregroundStyle(Color(hex: goal.colorHex))
                        .minimumScaleFactor(0.8)
                }

                progressBar(progress: goal.progress, tint: Color(hex: goal.colorHex))

                if let nextActionTitle = goal.nextActionTitle {
                    Text(nextActionTitle)
                        .font(.system(size: scale.bodyFontSize, weight: .medium))
                        .foregroundStyle(.white.opacity(0.70))
                        .lineLimit(compact ? 2 : 3)
                }

                HStack(spacing: 6) {
                    CadenceWidgetBadge(
                        text: "\(goal.linkedHabitCount) habits",
                        tint: Color(red: 0.55, green: 0.89, blue: 0.78)
                    )
                    if goal.overdueTaskCount > 0 {
                        CadenceWidgetBadge(
                            text: "\(goal.overdueTaskCount) overdue",
                            tint: Color(red: 1.0, green: 0.52, blue: 0.44)
                        )
                    }
                }
            }
            .padding(compact ? scale.compactCardPadding : scale.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [
                        Color(hex: goal.colorHex).opacity(0.32),
                        Color.white.opacity(0.07),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: compact ? scale.cardCornerRadius : scale.cardCornerRadius + 1, style: .continuous))
            .cadenceWidgetElevation(scale)
        }
    }

    private var sidePanel: some View {
        VStack(alignment: .leading, spacing: scale.compactSectionSpacing) {
            CadenceWidgetMetricCard(title: "Overdue", value: "\(entry.snapshot.totalOverdueTaskCount)")
            CadenceWidgetMetricCard(title: "Visible", value: "\(entry.snapshot.visibleGoals.count)")
            CadenceWidgetMetricCard(title: "Active", value: "\(entry.snapshot.totalGoalCount)")
        }
        .frame(width: 108)
    }

    private func goalRow(_ goal: CadenceMilestoneWidgetGoal, compact: Bool) -> some View {
        Link(destination: entry.snapshot.goalsURL) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(goal.title)
                        .font(.system(size: compact ? scale.bodyFontSize + 0.5 : scale.bodyFontSize + 1, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 8)
                    Text(goal.percentLabel)
                        .font(.system(size: scale.bodyFontSize + 0.5, weight: .bold))
                        .foregroundStyle(Color(hex: goal.colorHex))
                }

                progressBar(progress: goal.progress, tint: Color(hex: goal.colorHex))

                HStack(spacing: 6) {
                    Text(goal.dueTodayLabel)
                        .font(.system(size: scale.captionFontSize, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                    if goal.overdueTaskCount > 0 {
                        Text("\(goal.overdueTaskCount) overdue")
                            .font(.system(size: scale.captionFontSize, weight: .semibold))
                            .foregroundStyle(Color(red: 1.0, green: 0.52, blue: 0.44))
                    }
                }
            }
            .padding(.horizontal, scale.panelPadding)
            .padding(.vertical, compact ? max(scale.panelPadding - 2, 6) : max(scale.panelPadding - 1, 7))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.09))
            .clipShape(RoundedRectangle(cornerRadius: scale.cardCornerRadius, style: .continuous))
            .cadenceWidgetElevation(scale)
        }
    }

    private var footerLink: some View {
        CadenceWidgetFooterLink(label: "Open Milestones", url: entry.snapshot.goalsURL)
    }

    private var emptyState: some View {
        CadenceWidgetStateCard(
            title: "No active milestones",
            message: "Use Cadence to create a milestone, then this widget will track its momentum.",
            actionLabel: "Open Milestones",
            actionURL: entry.snapshot.goalsURL
        )
    }

    private var unavailableState: some View {
        CadenceWidgetStateCard(
            title: "Milestone widget needs Cadence",
            message: entry.snapshot.statusMessage,
            actionLabel: "Open Milestones",
            actionURL: entry.snapshot.goalsURL
        )
    }

    private func progressBar(progress: Double, tint: Color) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.10))
                Capsule()
                    .fill(tint)
                    .frame(width: max(8, proxy.size.width * max(0, min(progress, 1))))
            }
        }
        .frame(height: 6)
    }

    private var headerTitle: String {
        widgetFamily == .systemSmall ? "Momentum" : "Milestones"
    }

    private var headerBadges: [WidgetHeaderBadge] {
        let overdueTint = Color(red: 1.0, green: 0.52, blue: 0.44)
        let activeTint = Color(red: 0.48, green: 0.77, blue: 1.0)

        if widgetFamily == .systemSmall {
            if entry.snapshot.totalOverdueTaskCount > 0 {
                return [WidgetHeaderBadge(text: "\(entry.snapshot.totalOverdueTaskCount) overdue", tint: overdueTint)]
            }
            return [WidgetHeaderBadge(text: "\(entry.snapshot.totalGoalCount) active", tint: activeTint)]
        }

        return [
            WidgetHeaderBadge(text: "\(entry.snapshot.totalOverdueTaskCount) overdue", tint: overdueTint),
            WidgetHeaderBadge(text: "\(entry.snapshot.totalGoalCount) active", tint: activeTint),
        ]
    }
}
