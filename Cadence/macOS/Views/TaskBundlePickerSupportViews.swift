#if os(macOS)
import SwiftUI

struct TaskBundleTaskPickerPanel: View {
    let bundleDateKey: String
    let allTasks: [AppTask]
    let areas: [Area]
    let projects: [Project]
    let excludedTaskIDs: Set<UUID>
    @Binding var searchText: String
    var maxHeight: CGFloat = 214
    let onAdd: (AppTask) -> Void

    @State private var selectedList: TaskBundlePickerListOption?

    private var queryTokens: [String] {
        searchText
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
    }

    private var availableTasks: [AppTask] {
        allTasks.filter { task in
            !task.isDone &&
            !task.isCancelled &&
            !excludedTaskIDs.contains(task.id)
        }
    }

    private var matchingLists: [TaskBundlePickerListOption] {
        guard !queryTokens.isEmpty, selectedList == nil else { return [] }
        let options = areas.filter(\.isActive).map { area in
            TaskBundlePickerListOption(
                id: "area-\(area.id.uuidString)",
                title: area.name,
                icon: area.icon,
                colorHex: area.colorHex,
                areaID: area.id,
                projectID: nil
            )
        } + projects.filter(\.isActive).map { project in
            TaskBundlePickerListOption(
                id: "project-\(project.id.uuidString)",
                title: project.name,
                icon: project.icon,
                colorHex: project.colorHex,
                areaID: nil,
                projectID: project.id
            )
        }

        return options
            .filter { option in
                matches(option.title) && activeTasks(in: option).isEmpty == false
            }
            .sorted { lhs, rhs in
                if activeTasks(in: lhs).count != activeTasks(in: rhs).count {
                    return activeTasks(in: lhs).count > activeTasks(in: rhs).count
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    private var candidateTasks: [AppTask] {
        let base = selectedList.map { activeTasks(in: $0) } ?? availableTasks
        return base
            .filter { task in
                guard !queryTokens.isEmpty else { return true }
                return matches(searchText(for: task))
            }
            .sorted { lhs, rhs in
                let lhsScore = candidateSortScore(lhs)
                let rhsScore = candidateSortScore(rhs)
                if lhsScore != rhsScore { return lhsScore > rhsScore }
                return lhs.createdAt > rhs.createdAt
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            pickerHeader

            Divider().background(Theme.borderSubtle)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if let selectedList {
                        selectedListHeader(selectedList)
                    } else if !matchingLists.isEmpty {
                        resultSectionLabel("Lists")
                        ForEach(matchingLists.prefix(6)) { list in
                            listRow(list)
                        }
                    }

                    let visibleTasks = Array(candidateTasks.prefix(selectedList == nil ? 8 : 20))
                    if !visibleTasks.isEmpty {
                        if selectedList == nil && !matchingLists.isEmpty {
                            resultSectionLabel("Tasks")
                        }
                        ForEach(visibleTasks) { task in
                            taskRow(task)
                        }
                    } else if matchingLists.isEmpty {
                        Text(emptyMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.dim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                }
                .padding(7)
            }
            .frame(maxHeight: maxHeight)
        }
        .background(Theme.surfaceElevated.opacity(0.54))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.borderSubtle.opacity(0.9), lineWidth: 1)
        }
    }

    private var pickerHeader: some View {
        HStack(spacing: 7) {
            if selectedList != nil {
                Button {
                    selectedList = nil
                    searchText = ""
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                }
                .buttonStyle(.cadencePlain)
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
            }

            TextField(selectedList == nil ? "Find tasks or lists" : "Filter list tasks", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim.opacity(0.55))
                }
                .buttonStyle(.cadencePlain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var emptyMessage: String {
        if selectedList != nil { return "No active tasks in this list." }
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "No available active tasks." }
        return "No matching tasks or lists."
    }

    private func selectedListHeader(_ list: TaskBundlePickerListOption) -> some View {
        HStack(spacing: 8) {
            Image(systemName: list.icon.isEmpty ? "folder" : list.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: list.colorHex))
            VStack(alignment: .leading, spacing: 1) {
                Text(list.title.isEmpty ? "Untitled List" : list.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text("\(activeTasks(in: list).count) active task\(activeTasks(in: list).count == 1 ? "" : "s")")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.dim)
            }
            Spacer()
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Theme.surface.opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func resultSectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.dim)
            .textCase(.uppercase)
            .padding(.horizontal, 3)
            .padding(.top, 2)
    }

    private func listRow(_ list: TaskBundlePickerListOption) -> some View {
        Button {
            selectedList = list
            searchText = ""
        } label: {
            HStack(spacing: 8) {
                Image(systemName: list.icon.isEmpty ? "folder" : list.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: list.colorHex))
                VStack(alignment: .leading, spacing: 2) {
                    Text(list.title.isEmpty ? "Untitled List" : list.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Text("Open active tasks")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text("\(activeTasks(in: list).count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(Theme.surfaceElevated.opacity(0.58))
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.cadencePlain)
    }

    private func taskRow(_ task: AppTask) -> some View {
        Button {
            onAdd(task)
            searchText = ""
        } label: {
            HStack(spacing: 8) {
                Image(systemName: task.bundle == nil ? "plus.circle" : "arrow.triangle.branch")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.amber)
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title.isEmpty ? "Untitled" : task.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Text(candidateDetail(task))
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text("\(max(task.estimatedMinutes, 5))m")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.dim)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(Theme.surfaceElevated.opacity(0.58))
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.cadencePlain)
    }

    private func activeTasks(in list: TaskBundlePickerListOption) -> [AppTask] {
        availableTasks.filter { task in
            if let areaID = list.areaID {
                return task.area?.id == areaID
            }
            if let projectID = list.projectID {
                return task.project?.id == projectID
            }
            return false
        }
    }

    private func matches(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return queryTokens.allSatisfy { normalized.contains($0) }
    }

    private func searchText(for task: AppTask) -> String {
        [
            task.title,
            task.notes,
            task.containerName,
            task.resolvedSectionName,
            task.priorityRaw
        ].joined(separator: " ")
    }

    private func candidateSortScore(_ task: AppTask) -> Int {
        var score = 0
        if task.scheduledDate == bundleDateKey { score += 8 }
        if task.dueDate == bundleDateKey { score += 5 }
        if task.bundle != nil { score -= 3 }
        switch task.priority {
        case .high: score += 3
        case .medium: score += 2
        case .low: score += 1
        case .none: break
        }
        return score
    }

    private func candidateDetail(_ task: AppTask) -> String {
        if let existingBundle = task.bundle {
            return "In \(existingBundle.displayTitle)"
        }
        if task.scheduledDate == bundleDateKey {
            return task.scheduledStartMin >= 0 ? "Scheduled \(TimeFormatters.timeString(from: task.scheduledStartMin))" : "Planned this day"
        }
        if task.dueDate == bundleDateKey {
            return "Due this day"
        }
        if !task.containerName.isEmpty {
            return task.containerName
        }
        return "Inbox"
    }
}

private struct TaskBundlePickerListOption: Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String
    let colorHex: String
    let areaID: UUID?
    let projectID: UUID?
}
#endif
