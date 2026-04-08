#if os(macOS)
import SwiftUI

enum KanbanSectionStateSupport {
    static func updateSection(
        sectionID: UUID,
        area: Area?,
        project: Project?,
        mutate: (inout TaskSectionConfig) -> Void
    ) {
        if let area {
            var configs = area.sectionConfigs
            guard let idx = configs.firstIndex(where: { $0.id == sectionID }) else { return }
            mutate(&configs[idx])
            area.sectionConfigs = configs
        } else if let project {
            var configs = project.sectionConfigs
            guard let idx = configs.firstIndex(where: { $0.id == sectionID }) else { return }
            mutate(&configs[idx])
            project.sectionConfigs = configs
        }
    }

    static func moveTasks(
        universeTasks: [AppTask],
        area: Area?,
        project: Project?,
        from oldName: String,
        to newName: String
    ) {
        for task in universeTasks where task.resolvedSectionName.caseInsensitiveCompare(oldName) == .orderedSame {
            if area != nil, task.area?.id != area?.id { continue }
            if project != nil, task.project?.id != project?.id { continue }
            task.sectionName = newName
        }
    }

    static func removeSection(sectionID: UUID, area: Area?, project: Project?) {
        if let area {
            area.sectionConfigs = area.sectionConfigs.filter { $0.id != sectionID }
        } else if let project {
            project.sectionConfigs = project.sectionConfigs.filter { $0.id != sectionID }
        }
    }

    static func saveSection(updatedSection: TaskSectionConfig, area: Area?, project: Project?) {
        if let area {
            var configs = area.sectionConfigs
            guard let index = configs.firstIndex(where: { $0.id == updatedSection.id }) else { return }
            configs[index] = updatedSection
            area.sectionConfigs = configs
        } else if let project {
            var configs = project.sectionConfigs
            guard let index = configs.firstIndex(where: { $0.id == updatedSection.id }) else { return }
            configs[index] = updatedSection
            project.sectionConfigs = configs
        }
    }
}
#endif
