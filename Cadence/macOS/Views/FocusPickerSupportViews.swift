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
    let clockDisplay: String
    @Binding var searchText: String
    let items: [FocusPickItem]
    let onSelectTask: (AppTask) -> Void
    let onSelectBundle: (TaskBundle) -> Void
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Ready to focus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                        .textCase(.uppercase)

                    Text(title)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                FocusIdleClockBadge(clockDisplay: clockDisplay)
            }

            searchBar

            HStack(spacing: 10) {
                Text(resultSummary)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)

                Spacer(minLength: 12)

                FocusPickerLegendItem(color: Theme.blue, title: "Tasks")
                FocusPickerLegendItem(color: Theme.amber, title: "Bundles")
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    if items.isEmpty {
                        emptyState
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
                .padding(.bottom, 2)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(searchFieldFocused ? Theme.blue : Theme.dim)
            TextField("Search tasks and bundles", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(Theme.text)
                .focused($searchFieldFocused)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(Theme.surfaceElevated.opacity(searchFieldFocused ? 0.94 : 0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(searchFieldFocused ? Theme.blue.opacity(0.42) : Theme.borderSubtle.opacity(0.85), lineWidth: 1)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: isSearching ? "magnifyingglass" : "checkmark.circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isSearching ? Theme.dim : Theme.green)

            Text(isSearching ? "No matching tasks or bundles" : "Nothing ready right now")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)

            Text(isSearching ? "Try a project, bundle title, task title, priority, or date." : "When a task is ready, it will appear here.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.surfaceElevated.opacity(0.48))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var resultSummary: String {
        if items.isEmpty {
            return isSearching ? "No matches" : "No ready sessions"
        }

        let counts = itemCounts
        if isSearching {
            return "\(items.count) match\(items.count == 1 ? "" : "es")"
        }

        var parts: [String] = []
        if counts.tasks > 0 {
            parts.append("\(counts.tasks) task\(counts.tasks == 1 ? "" : "s")")
        }
        if counts.bundles > 0 {
            parts.append("\(counts.bundles) bundle\(counts.bundles == 1 ? "" : "s")")
        }
        return "Best matches / \(parts.joined(separator: " / "))"
    }

    private var itemCounts: (tasks: Int, bundles: Int) {
        var taskCount = 0
        var bundleCount = 0
        for item in items {
            switch item {
            case .task:
                taskCount += 1
            case .bundle:
                bundleCount += 1
            }
        }
        return (taskCount, bundleCount)
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct FocusPickItemRow: View {
    let item: FocusPickItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
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

                Text(kindLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(tint.opacity(0.1))
                    .clipShape(Capsule())

                Image(systemName: "play.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.12))
                    .clipShape(Circle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(Theme.surfaceElevated.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Theme.borderSubtle.opacity(0.55), lineWidth: 1)
            }
        }
        .buttonStyle(.cadencePlain)
        .help(helpText)
    }

    @ViewBuilder
    private var leadingIcon: some View {
        switch item {
        case .task(let task):
            ZStack {
                Circle()
                    .fill(Color(hex: task.containerColor).opacity(0.16))
                Circle()
                    .fill(Color(hex: task.containerColor))
                    .frame(width: 8, height: 8)
            }
            .frame(width: 28, height: 28)
        case .bundle:
            Image(systemName: "tray.full")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.amber)
                .frame(width: 28, height: 28)
                .background(Theme.amber.opacity(0.12))
                .clipShape(Circle())
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

    private var kindLabel: String {
        switch item {
        case .task:
            return "Task"
        case .bundle:
            return "Bundle"
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

private struct FocusIdleClockBadge: View {
    let clockDisplay: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("Session")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .textCase(.uppercase)

            Text(clockDisplay)
                .font(.system(size: 34, weight: .light, design: .monospaced))
                .foregroundStyle(Theme.muted)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minWidth: 142, alignment: .trailing)
        .background(Theme.surfaceElevated.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.borderSubtle.opacity(0.75), lineWidth: 1)
        }
    }
}

private struct FocusPickerLegendItem: View {
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.dim)
        }
    }
}
#endif
