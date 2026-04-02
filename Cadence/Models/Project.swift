import SwiftData
import Foundation

/// Finite effort with a clear outcome and optional deadline.
@Model final class Project {
    var id: UUID = UUID()
    var name: String = ""
    var desc: String = ""
    var statusRaw: String = "active"

    var status: ProjectStatus {
        get { ProjectStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }
    var colorHex: String = "#4ecb71"
    var icon: String = "checklist"
    var dueDate: String = ""        // YYYY-MM-DD or ""
    var order: Int = 0
    var linkedCalendarID: String = ""   // EKCalendar identifier
    var loggedMinutes: Int = 0          // cumulative focus time logged to tasks in this project
    var hideDueDateIfEmpty: Bool = true
    var hideSectionDueDateIfEmpty: Bool = true
    var sectionNamesRaw: String = TaskSectionDefaults.defaultName
    var sectionConfigsRaw: String = ""

    var context: Context? = nil
    var area: Area? = nil
    @Relationship(inverse: \AppTask.project) var tasks: [AppTask]? = nil
    @Relationship(inverse: \Document.project) var documents: [Document]? = nil
    @Relationship(inverse: \SavedLink.project) var links: [SavedLink]? = nil

    var isDone: Bool { status == .done }
    var isArchived: Bool { status == .archived }
    var isActive: Bool { status == .active }

    var completionRate: Double {
        let all = tasks ?? []
        let total = all.filter { $0.status != .cancelled }.count
        guard total > 0 else { return 0 }
        return Double(all.filter { $0.isDone }.count) / Double(total)
    }

    init(name: String, context: Context? = nil, area: Area? = nil, colorHex: String = "#4ecb71") {
        self.name = name
        self.context = context
        self.area = area
        self.colorHex = colorHex
    }

    var sectionNames: [String] {
        get {
            sectionConfigs.filter { !$0.isArchived }.map(\.name)
        }
        set {
            let existingByName = Dictionary(uniqueKeysWithValues: sectionConfigs.map { ($0.name.lowercased(), $0) })
            sectionConfigs = newValue.map { name in
                if let existing = existingByName[name.lowercased()] {
                    return TaskSectionConfig(
                        uuid: existing.uuid,
                        name: name,
                        colorHex: existing.colorHex,
                        dueDate: existing.dueDate,
                        isCompleted: existing.isCompleted,
                        isArchived: false
                    )
                }
                return TaskSectionConfig(name: name)
            }
        }
    }

    var sectionConfigs: [TaskSectionConfig] {
        get {
            if let data = sectionConfigsRaw.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([TaskSectionConfig].self, from: data) {
                return normalizedSectionConfigs(decoded)
            }

            let parsed = sectionNamesRaw
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { TaskSectionConfig(name: $0) }
            return normalizedSectionConfigs(parsed)
        }
        set {
            let normalized = normalizedSectionConfigs(newValue)
            sectionNamesRaw = normalized.map(\.name).joined(separator: "\n")
            if let data = try? JSONEncoder().encode(normalized),
               let json = String(data: data, encoding: .utf8) {
                sectionConfigsRaw = json
            }
        }
    }

    private func normalizedSectionConfigs(_ configs: [TaskSectionConfig]) -> [TaskSectionConfig] {
        var seen = Set<String>()
        var cleaned: [TaskSectionConfig] = []
        for config in configs {
            let trimmed = config.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            cleaned.append(
                TaskSectionConfig(
                    uuid: config.uuid,
                    name: trimmed,
                    colorHex: config.colorHex,
                    dueDate: config.dueDate,
                    isCompleted: config.isCompleted,
                    isArchived: config.isArchived
                )
            )
        }
        if let defaultIndex = cleaned.firstIndex(where: { $0.name.caseInsensitiveCompare(TaskSectionDefaults.defaultName) == .orderedSame }) {
            cleaned[defaultIndex].name = TaskSectionDefaults.defaultName
            cleaned[defaultIndex].isCompleted = false
            cleaned[defaultIndex].isArchived = false
            if cleaned[defaultIndex].colorHex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                cleaned[defaultIndex].colorHex = TaskSectionDefaults.defaultColorHex
            }
            if defaultIndex != 0 {
                let value = cleaned.remove(at: defaultIndex)
                cleaned.insert(value, at: 0)
            }
        } else {
            cleaned.insert(TaskSectionConfig(name: TaskSectionDefaults.defaultName), at: 0)
        }
        return cleaned
    }
}
