import AppIntents
import SwiftData
import SwiftUI
import WidgetKit

struct TodayTasksWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: CadenceTodayWidgetSnapshot
}

struct TodayTasksWidgetProvider: AppIntentTimelineProvider {
    typealias Intent = CadenceTodayWidgetConfigurationIntent
    typealias Entry = TodayTasksWidgetEntry

    func placeholder(in context: TimelineProviderContext) -> TodayTasksWidgetEntry {
        TodayTasksWidgetEntry(date: Date(), snapshot: placeholderSnapshot)
    }

    func snapshot(for configuration: CadenceTodayWidgetConfigurationIntent, in context: TimelineProviderContext) async -> TodayTasksWidgetEntry {
        TodayTasksWidgetEntry(date: Date(), snapshot: currentSnapshot())
    }

    func timeline(for configuration: CadenceTodayWidgetConfigurationIntent, in context: TimelineProviderContext) async -> Timeline<TodayTasksWidgetEntry> {
        let entry = TodayTasksWidgetEntry(date: Date(), snapshot: currentSnapshot())
        return Timeline(
            entries: [entry],
            policy: .after(CadenceTodayWidgetSupport.recommendedReloadDate(for: entry.snapshot))
        )
    }

    private var placeholderSnapshot: CadenceTodayWidgetSnapshot {
        CadenceTodayWidgetSnapshot(
            date: Date(),
            dateKey: DateFormatters.todayKey(),
            state: .ready,
            statusMessage: nil,
            totalCount: 3,
            overdueCount: 1,
            dueTodayCount: 1,
            scheduledTodayCount: 1,
            tasks: [
                CadenceTodayWidgetTask(
                    id: UUID(),
                    title: "Finish widget pass",
                    priorityRaw: TaskPriority.high.rawValue,
                    dueDate: DateFormatters.todayKey(),
                    scheduledDate: DateFormatters.todayKey(),
                    containerName: "Cadence"
                ),
                CadenceTodayWidgetTask(
                    id: UUID(),
                    title: "Plan today timeline",
                    priorityRaw: TaskPriority.medium.rawValue,
                    dueDate: "",
                    scheduledDate: DateFormatters.todayKey(),
                    containerName: "Work"
                ),
                CadenceTodayWidgetTask(
                    id: UUID(),
                    title: "Clean up inbox",
                    priorityRaw: TaskPriority.low.rawValue,
                    dueDate: "",
                    scheduledDate: DateFormatters.todayKey(),
                    containerName: ""
                ),
            ]
        )
    }

    private func currentSnapshot() -> CadenceTodayWidgetSnapshot {
        do {
            let container = try CadenceStoreSupport.makeSharedContainer(
                allowsSave: false,
                cloudKitDatabase: .none
            )
            let modelContext = ModelContext(container)
            return try CadenceTodayWidgetSupport.snapshot(modelContext: modelContext, limit: 3)
        } catch {
            return CadenceTodayWidgetSupport.unavailableSnapshot()
        }
    }
}

struct CadenceTodayTasksWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: CadenceWidgetRefreshCenter.todayWidgetKind,
            intent: CadenceTodayWidgetConfigurationIntent.self,
            provider: TodayTasksWidgetProvider()
        ) { entry in
            TodayTasksWidgetView(entry: entry)
        }
        .configurationDisplayName("Today Tasks")
        .description("See and complete today's Cadence tasks.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct TodayTasksWidgetView: View {
    let entry: TodayTasksWidgetEntry
    @Environment(\.widgetFamily) private var widgetFamily

    var body: some View {
        Group {
            switch widgetFamily {
            case .systemSmall:
                smallLayout
            default:
                mediumLayout
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.10, blue: 0.15),
                    Color(red: 0.12, green: 0.14, blue: 0.21),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            widgetHeader

            if entry.snapshot.isUnavailable {
                unavailableState(alignment: .leading)
            } else if let task = entry.snapshot.tasks.first {
                VStack(alignment: .leading, spacing: 10) {
                    Link(destination: task.deepLinkURL) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(task.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(3)

                            if !task.containerName.isEmpty {
                                Text(task.containerName)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.62))
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    HStack {
                        statusPill(for: task)
                        Spacer(minLength: 8)
                        Button(intent: CompleteTaskIntent(taskID: task.id)) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Color(red: 0.35, green: 0.89, blue: 0.56))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                emptyState(alignment: .leading)
            }
        }
        .padding(14)
    }

    private var mediumLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            widgetHeader

            if entry.snapshot.isUnavailable {
                unavailableState(alignment: .center)
            } else if entry.snapshot.tasks.isEmpty {
                emptyState(alignment: .center)
            } else {
                VStack(spacing: 8) {
                    ForEach(entry.snapshot.tasks.prefix(3)) { task in
                        HStack(spacing: 10) {
                            Link(destination: task.deepLinkURL) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(task.title)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(2)

                                    HStack(spacing: 6) {
                                        statusPill(for: task)
                                        if !task.containerName.isEmpty {
                                            Text(task.containerName)
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundStyle(.white.opacity(0.55))
                                                .lineLimit(1)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            Button(intent: CompleteTaskIntent(taskID: task.id)) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(Color(red: 0.35, green: 0.89, blue: 0.56))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
        }
        .padding(14)
    }

    private var widgetHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                Spacer(minLength: 10)
                Text("\(entry.snapshot.totalCount)")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }

            HStack(spacing: 6) {
                if entry.snapshot.isUnavailable {
                    summaryBadge(label: "unavailable", value: nil, tint: Color(red: 1.0, green: 0.72, blue: 0.28))
                } else {
                    summaryBadge(label: "overdue", value: entry.snapshot.overdueCount, tint: Color(red: 1.0, green: 0.45, blue: 0.41))
                    summaryBadge(label: "due", value: entry.snapshot.dueTodayCount, tint: Color(red: 1.0, green: 0.72, blue: 0.28))
                    summaryBadge(label: "scheduled", value: entry.snapshot.scheduledTodayCount, tint: Color(red: 0.39, green: 0.71, blue: 1.0))
                }
            }
        }
    }

    private func emptyState(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 8) {
            Text("Nothing planned today")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            Link(destination: entry.snapshot.todayURL) {
                Text("Open Today in Cadence")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment == .leading ? .topLeading : .center)
        .padding(.vertical, 10)
    }

    private func unavailableState(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 8) {
            Text("Widget needs Cadence")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            if let statusMessage = entry.snapshot.statusMessage {
                Text(statusMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(alignment == .leading ? .leading : .center)
            }

            Link(destination: entry.snapshot.todayURL) {
                Text("Open Cadence")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment == .leading ? .topLeading : .center)
        .padding(.vertical, 10)
    }

    private func summaryBadge(label: String, value: Int?, tint: Color) -> some View {
        let text: String
        if let value {
            text = "\(value) \(label)"
        } else {
            text = label
        }

        return Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(tint.opacity(0.16))
            .clipShape(Capsule())
    }

    private func statusPill(for task: CadenceTodayWidgetTask) -> some View {
        let label: String
        let tint: Color

        if !task.dueDate.isEmpty && task.dueDate < entry.snapshot.dateKey {
            label = "Overdue"
            tint = Color(red: 1.0, green: 0.45, blue: 0.41)
        } else if task.dueDate == entry.snapshot.dateKey {
            label = "Due today"
            tint = Color(red: 1.0, green: 0.72, blue: 0.28)
        } else {
            label = "Scheduled"
            tint = Color(red: 0.39, green: 0.71, blue: 1.0)
        }

        return Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(tint.opacity(0.16))
            .clipShape(Capsule())
    }
}
