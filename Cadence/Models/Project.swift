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
    /// The `EKCalendar.calendarIdentifier` this list mirrors, or `""` when unlinked.
    ///
    /// **T-390.** Identifier only, with no title or source beside it. See
    /// `Area.linkedCalendarID` for the contract: why a recreated calendar leaves this link visibly
    /// dead rather than being re-matched by name, and why storing metadata is blocked without a
    /// `SchemaMigrationPlan`.
    var linkedCalendarID: String = ""
    var loggedMinutes: Int = 0          // cumulative focus time logged to tasks in this project
    var hideDueDateIfEmpty: Bool = true
    var hideSectionDueDateIfEmpty: Bool = true
    var sectionNamesRaw: String = TaskSectionDefaults.defaultName
    var sectionConfigsRaw: String = ""

    var context: Context? = nil
    var area: Area? = nil
    @Relationship(inverse: \AppTask.project) var tasks: [AppTask]? = nil
    @Relationship(inverse: \Document.project) var documents: [Document]? = nil
    @Relationship(inverse: \Note.project) var notes: [Note]? = nil
    @Relationship(inverse: \SavedLink.project) var links: [SavedLink]? = nil
    @Relationship(inverse: \GoalListLink.project) var goalLinks: [GoalListLink]? = nil

    /// The context a task filed in this project belongs to.
    ///
    /// A project either names its own context or inherits the one its area names, so the honest
    /// answer is `context ?? area?.context`. `AppTask.context` is denormalized for query speed, so
    /// **every** path that files a task into a project has to write this value rather than
    /// `project.context`: a project owned by an area, with no context of its own, otherwise hands
    /// the task a nil context, and every context-scoped list and count then misses a task that is
    /// plainly sitting in that context's list.
    ///
    /// It is spelled once, here, because it used to be spelled twice. `assignContainer` - the
    /// *move* path - applied the area fallback while seven creation and drag paths wrote
    /// `project.context` alone, so two tasks sitting in the same project could carry different
    /// contexts based only on how they got there (T-292). The same rule is what re-points a
    /// list's existing tasks when the list itself changes owner (T-293).
    var resolvedContext: Context? { context ?? area?.context }

    var isDone: Bool { status == .done }
    var isArchived: Bool { status == .archived }
    var isActive: Bool { status == .active }

    init(name: String, context: Context? = nil, area: Area? = nil, colorHex: String = "#4ecb71") {
        self.name = name
        self.context = context
        self.area = area
        self.colorHex = colorHex
    }

    /// The **unarchived** section names, as a plain list.
    ///
    /// The getter hides archived columns, so the setter has to put them back: it used to rebuild
    /// `sectionConfigs` from `newValue` alone, which meant every archived column was destroyed by
    /// any write. That is not theoretical — `iOSListEditorViews` edits a list purely through this
    /// property, so opening a list on iPhone and tapping Save with no changes at all silently
    /// deleted every archived column, with no undo and no other copy of the data. A view that
    /// filters on read must restore on write, or it is a delete in disguise.
    ///
    /// Known remaining limitation: matching is by name, so *renaming* a column on a surface that
    /// writes through here still mints a fresh config and loses that column's colour and due
    /// date. Fixing that needs identity in the editor UI (iOS has no per-column colour or due
    /// date control at all yet) rather than a smarter guess here.
    var sectionNames: [String] {
        get {
            sectionConfigs.filter { !$0.isArchived }.map(\.name)
        }
        set {
            let existing = sectionConfigs
            let existingByName = Dictionary(existing.map { ($0.name.lowercased(), $0) }) { first, _ in first }
            let keptNames = Set(newValue.map { $0.lowercased() })
            let visible: [TaskSectionConfig] = newValue.map { name in
                if let match = existingByName[name.lowercased()] {
                    return TaskSectionConfig(
                        uuid: match.uuid,
                        name: name,
                        colorHex: match.colorHex,
                        dueDate: match.dueDate,
                        isCompleted: match.isCompleted,
                        isArchived: false
                    )
                }
                return TaskSectionConfig(name: name)
            }
            // Archived columns are invisible to this property's getter, so `newValue` can never
            // mention them and their absence must not be read as a deletion.
            let preservedArchived = existing.filter {
                $0.isArchived && !keptNames.contains($0.name.lowercased())
            }
            sectionConfigs = visible + preservedArchived
        }
    }

    var sectionConfigs: [TaskSectionConfig] {
        // Element by element, because this getter's fallback is destructive: `sectionNamesRaw`
        // keeps names only, and the setter below rewrites `sectionConfigsRaw` from whatever it is
        // handed — so one unreadable column used to cost every column its colour, due date and
        // lifecycle flags, permanently, on the next save. `TaskSectionConfig.storedList` carries
        // the reasoning (T-475).
        get {
            switch TaskSectionConfig.storedList(fromRaw: sectionConfigsRaw) {
            case .clean(let decoded):
                return normalizedSectionConfigs(decoded)
            case .salvaged(let decoded):
                let recovered = TaskSectionConfig.legacyConfigs(fromRaw: sectionNamesRaw, excluding: decoded)
                return normalizedSectionConfigs(decoded + recovered)
            case .empty:
                return normalizedSectionConfigs(
                    TaskSectionConfig.legacyConfigs(fromRaw: sectionNamesRaw, excluding: [])
                )
            }
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
