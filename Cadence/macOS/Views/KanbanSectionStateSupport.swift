#if os(macOS)
import SwiftUI

/// The macOS column's section writes. Every one of them goes through
/// `CadenceSectionConfigMerge` rather than reading the whole array, changing one entry and writing
/// the whole array back — see that type for what the merge keeps and what it still loses
/// (`docs/TODO.md` T-358).
enum KanbanSectionStateSupport {
    static func updateSection(
        sectionID: UUID,
        area: Area?,
        project: Project?,
        mutate: (inout TaskSectionConfig) -> Void
    ) {
        CadenceSectionConfigMerge.container(area: area, project: project)?
            .updateSectionConfig(uuid: sectionID, mutate: mutate)
    }

    /// The cards `moveTasks(universeTasks:area:project:from:to:)` will re-point.
    ///
    /// Split out rather than left inline because a refused rename or column delete has to put those
    /// cards' `sectionName` back, and the snapshot must be taken over **the same walk the write
    /// performs** — not a second one that happens to agree today. It is every card in the column,
    /// finished ones included, which is what makes it the wrong set for `editSnapshot(settling:)`
    /// and the right one here: deleting a column moves its whole stack into Default, while a
    /// lifecycle settle only reaches the open half.
    static func tasksMoving(
        universeTasks: [AppTask],
        area: Area?,
        project: Project?,
        from oldName: String
    ) -> [AppTask] {
        universeTasks.filter { task in
            guard task.resolvedSectionName.caseInsensitiveCompare(oldName) == .orderedSame else { return false }
            if area != nil, task.area?.id != area?.id { return false }
            if project != nil, task.project?.id != project?.id { return false }
            return true
        }
    }

    static func moveTasks(
        universeTasks: [AppTask],
        area: Area?,
        project: Project?,
        from oldName: String,
        to newName: String
    ) {
        for task in tasksMoving(universeTasks: universeTasks, area: area, project: project, from: oldName) {
            task.sectionName = newName
        }
    }

    static func removeSection(sectionID: UUID, area: Area?, project: Project?) {
        CadenceSectionConfigMerge.container(area: area, project: project)?
            .removeSectionConfig(uuid: sectionID)
    }

    /// `base` is the column **as the caller last saw it**. Pass it whenever the caller has been
    /// holding the value for a while — only the fields that differ from it are written, so a
    /// concurrent edit to a different field of the same column survives. Omitting it diffs against
    /// what the model has now, which is the right base for a value read moments ago.
    static func saveSection(
        updatedSection: TaskSectionConfig,
        area: Area?,
        project: Project?,
        base: TaskSectionConfig? = nil
    ) {
        guard let container = CadenceSectionConfigMerge.container(area: area, project: project) else { return }
        let current = container.sectionConfigs
        guard let currentConfig = current.first(where: { $0.uuid == updatedSection.uuid }) else { return }
        let baseConfig = base ?? currentConfig
        container.applySectionConfigEdits(
            base: current.map { $0.uuid == updatedSection.uuid ? baseConfig : $0 },
            edited: current.map { $0.uuid == updatedSection.uuid ? updatedSection : $0 }
        )
    }
}
#endif
