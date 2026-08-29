import SwiftData
import Foundation

/// Ongoing responsibility with no definitive end date.
@Model final class Area {
    var id: UUID = UUID()
    var name: String = ""
    var desc: String = ""
    var statusRaw: String = "active"

    var status: AreaStatus {
        get { AreaStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }
    var colorHex: String = "#4a9eff"
    var icon: String = "folder.fill"
    var order: Int = 0
    /// The `EKCalendar.calendarIdentifier` this list mirrors, or `""` when unlinked.
    ///
    /// **T-390 — this is a decision, not an oversight.** The identifier is stored alone: no title,
    /// no source, no companion metadata anywhere in the app. Cadence treats an EventKit calendar
    /// identifier as opaque and permanent, and that assumption has consequences worth stating
    /// where a model edit will meet them.
    ///
    /// If Apple Calendar deletes and recreates a calendar — a resubscribed feed, an account
    /// removed and re-added, a restore — the replacement arrives under a new identifier and this
    /// link is dead. It stays dead **visibly**: the list reads as unlinked and the user re-picks
    /// the calendar. Nothing re-matches by name. Silently rebinding someone's calendar on a title
    /// match is worse than a link they can see is broken, and doing it safely needs a conflict UI
    /// that does not exist.
    ///
    /// Meeting notes filed under the old identifier stay under it. `CadenceEventNoteSupport`
    /// compares `calendarID` exactly, including inside its date/title fallback, so re-linking does
    /// not drag old notes across. That is the accepted cost of an id-only link, and
    /// `CadenceEventKitPlatformParityTests` pins both halves.
    ///
    /// The other branch — storing title and source so a stale link could warn and offer rebinding
    /// — is a stored-property change on this `@Model`, and this project has no
    /// `SchemaMigrationPlan`. It is blocked until one exists.
    var linkedCalendarID: String = ""
    var loggedMinutes: Int = 0          // cumulative focus time logged to tasks in this area
    var hideDueDateIfEmpty: Bool = true
    var hideSectionDueDateIfEmpty: Bool = true
    var sectionNamesRaw: String = TaskSectionDefaults.defaultName
    var sectionConfigsRaw: String = ""

    var context: Context? = nil
    @Relationship(inverse: \AppTask.area) var tasks: [AppTask]? = nil
    @Relationship(inverse: \Project.area) var projects: [Project]? = nil
    @Relationship(inverse: \Document.area) var documents: [Document]? = nil
    @Relationship(inverse: \Note.area) var notes: [Note]? = nil
    @Relationship(inverse: \SavedLink.area) var links: [SavedLink]? = nil
    @Relationship(inverse: \GoalListLink.area) var goalLinks: [GoalListLink]? = nil

    init(name: String, context: Context? = nil, colorHex: String = "#4a9eff", icon: String = "folder.fill") {
        self.name = name
        self.context = context
        self.colorHex = colorHex
        self.icon = icon
    }

    var isDone: Bool { status == .done }
    var isArchived: Bool { status == .archived }
    var isActive: Bool { status == .active }

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
