#if os(macOS)
import SwiftUI

enum FocusPickItem: Identifiable {
    case task(AppTask)
    case bundle(TaskBundle)

    var id: String {
        switch self {
        case .task(let task): return "task-\(task.id.uuidString)"
        case .bundle(let bundle): return "bundle-\(bundle.id.uuidString)"
        }
    }

    static func filtered(tasks: [AppTask], bundles: [TaskBundle], query: String, todayKey: String) -> [FocusPickItem] {
        let activeBundles = bundles
            .filter { !$0.sortedTasks.isEmpty && !$0.isCompleted }
            .sorted { lhs, rhs in
                if lhs.dateKey != rhs.dateKey {
                    return bundleDateRank(lhs.dateKey, todayKey: todayKey) < bundleDateRank(rhs.dateKey, todayKey: todayKey)
                }
                if lhs.startMin != rhs.startMin {
                    return lhs.startMin < rhs.startMin
                }
                return lhs.createdAt > rhs.createdAt
            }

        let items = tasks.map(FocusPickItem.task) + activeBundles.map(FocusPickItem.bundle)
        let cleanedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedQuery.isEmpty else {
            return Array(items.prefix(18))
        }

        return items.filter { $0.matches(cleanedQuery) }
    }

    private static func bundleDateRank(_ dateKey: String, todayKey: String) -> Int {
        if dateKey == todayKey { return 0 }
        if dateKey.isEmpty { return 2 }
        return dateKey > todayKey ? 1 : 3
    }

    private func matches(_ query: String) -> Bool {
        let needle = query.lowercased()
        return searchText.lowercased().contains(needle)
    }

    private var searchText: String {
        switch self {
        case .task(let task):
            return [
                task.title,
                task.containerName,
                task.priority.label,
                task.dueDate,
                task.scheduledDate
            ].joined(separator: " ")
        case .bundle(let bundle):
            return ([bundle.displayTitle, bundle.dateKey] + bundle.sortedTasks.map(\.title)).joined(separator: " ")
        }
    }
}

struct FocusPickSessionCard: View {
    let title: String
    let subtitle: String
    @Binding var searchText: String
    let items: [FocusPickItem]
    let onSelectTask: (AppTask) -> Void
    let onSelectBundle: (TaskBundle) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                }
                Spacer()
            }

            searchBar

            ScrollView {
                VStack(spacing: 8) {
                    if items.isEmpty {
                        Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Nothing ready right now" : "No matching tasks or bundles")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.dim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                    } else {
                        ForEach(items) { item in
                            FocusPickItemRow(item: item) {
                                switch item {
                                case .task(let task):
                                    onSelectTask(task)
                                case .bundle(let bundle):
                                    onSelectBundle(bundle)
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.blue.opacity(0.18), lineWidth: 1)
        )
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.dim)
            TextField("Search tasks and bundles", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                }
                .buttonStyle(.cadencePlain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(Theme.surfaceElevated.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.borderSubtle.opacity(0.85), lineWidth: 1)
        }
    }
}

private struct FocusPickItemRow: View {
    let item: FocusPickItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                leadingIcon

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(1)
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(1)
                }

                Image(systemName: "play.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.12))
                    .clipShape(Circle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.surfaceElevated.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.cadencePlain)
        .help(helpText)
    }

    @ViewBuilder
    private var leadingIcon: some View {
        switch item {
        case .task(let task):
            Circle()
                .fill(Color(hex: task.containerColor))
                .frame(width: 8, height: 8)
        case .bundle:
            Image(systemName: "tray.full")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.amber)
                .frame(width: 18, height: 18)
        }
    }

    private var title: String {
        switch item {
        case .task(let task):
            return task.title.isEmpty ? "Untitled Task" : task.title
        case .bundle(let bundle):
            return bundle.displayTitle
        }
    }

    private var detail: String {
        switch item {
        case .task(let task):
            return FocusSessionSupport.sidebarDetail(for: task, todayKey: DateFormatters.todayKey(), fallback: "Ready to focus")
        case .bundle(let bundle):
            var parts = ["Bundle", "\(bundle.sortedTasks.count) task\(bundle.sortedTasks.count == 1 ? "" : "s")"]
            if !bundle.dateKey.isEmpty {
                parts.append(bundle.dateKey == DateFormatters.todayKey() ? "Today" : DateFormatters.relativeDate(from: bundle.dateKey))
            }
            parts.append(TimeFormatters.timeRange(startMin: bundle.startMin, endMin: bundle.endMin))
            if bundle.totalEstimatedMinutes > 0 {
                parts.append("\(bundle.totalEstimatedMinutes)m tasks")
            }
            return parts.joined(separator: " / ")
        }
    }

    private var tint: Color {
        switch item {
        case .task:
            return Theme.blue
        case .bundle:
            return Theme.amber
        }
    }

    private var helpText: String {
        switch item {
        case .task:
            return "Focus this task"
        case .bundle:
            return "Focus this bundle"
        }
    }
}
#endif
