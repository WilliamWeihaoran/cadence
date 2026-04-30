import Foundation
import OSLog
import SwiftData

struct DataIntegrityRepairReport: Codable, Equatable {
    var source: String
    var startedAt: Date
    var finishedAt: Date
    var success: Bool
    var errorMessage: String?
    var duplicateContextsMerged: Int = 0
    var duplicateAreasMerged: Int = 0
    var duplicateProjectsMerged: Int = 0
    var movedAreas: Int = 0
    var movedProjects: Int = 0
    var movedTasks: Int = 0
    var movedGoals: Int = 0
    var movedHabits: Int = 0
    var movedNotes: Int = 0
    var movedDocuments: Int = 0
    var movedLinks: Int = 0
    var movedGoalLinks: Int = 0

    var changed: Bool {
        duplicateContextsMerged > 0 ||
            duplicateAreasMerged > 0 ||
            duplicateProjectsMerged > 0 ||
            movedAreas > 0 ||
            movedProjects > 0 ||
            movedTasks > 0 ||
            movedGoals > 0 ||
            movedHabits > 0 ||
            movedNotes > 0 ||
            movedDocuments > 0 ||
            movedLinks > 0 ||
            movedGoalLinks > 0
    }
}

enum DataIntegrityRepairService {
    private struct RepairState {
        var deletedAreas = Set<ObjectIdentifier>()
        var deletedProjects = Set<ObjectIdentifier>()
        var deletedContexts = Set<ObjectIdentifier>()
    }

    private struct RepairStore {
        var contexts: [Context]
        var areas: [Area]
        var projects: [Project]
        var tasks: [AppTask]
        var goals: [Goal]
        var habits: [Habit]
        var notes: [Note]
        var documents: [Document]
        var links: [SavedLink]
        var goalLinks: [GoalListLink]
    }

    private static let logger = Logger(subsystem: "com.haoranwei.Cadence", category: "DataIntegrity")
    private static let lastReportKey = "dataIntegrityRepair.lastReport.v1"

    @discardableResult
    static func repairIfNeeded(in context: ModelContext, source: String = "unknown") throws -> DataIntegrityRepairReport {
        var report = DataIntegrityRepairReport(
            source: source,
            startedAt: Date(),
            finishedAt: Date(),
            success: false
        )

        do {
            try repair(in: context, report: &report)
            if report.changed {
                try context.save()
            }
            report.finishedAt = Date()
            report.success = true
            record(report)
            log(report)
            return report
        } catch {
            report.finishedAt = Date()
            report.success = false
            report.errorMessage = error.localizedDescription
            record(report)
            logger.error("Data integrity repair failed from \(source, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    @discardableResult
    static func repairAndRecordFailure(in context: ModelContext, source: String) -> DataIntegrityRepairReport? {
        do {
            return try repairIfNeeded(in: context, source: source)
        } catch {
            return lastReport()
        }
    }

    static func lastReport() -> DataIntegrityRepairReport? {
        guard let data = UserDefaults.standard.data(forKey: lastReportKey) else { return nil }
        return try? JSONDecoder().decode(DataIntegrityRepairReport.self, from: data)
    }

    private static func repair(in context: ModelContext, report: inout DataIntegrityRepairReport) throws {
        let store = try RepairStore(
            contexts: context.fetch(FetchDescriptor<Context>()),
            areas: context.fetch(FetchDescriptor<Area>()),
            projects: context.fetch(FetchDescriptor<Project>()),
            tasks: context.fetch(FetchDescriptor<AppTask>()),
            goals: context.fetch(FetchDescriptor<Goal>()),
            habits: context.fetch(FetchDescriptor<Habit>()),
            notes: context.fetch(FetchDescriptor<Note>()),
            documents: context.fetch(FetchDescriptor<Document>()),
            links: context.fetch(FetchDescriptor<SavedLink>()),
            goalLinks: context.fetch(FetchDescriptor<GoalListLink>())
        )
        var state = RepairState()

        let activeContexts = store.contexts.filter { !$0.isArchived && !normalizedName($0).isEmpty }
        let groups = Dictionary(grouping: activeContexts) { normalizedName($0) }

        for group in groups.values where group.count > 1 {
            guard let canonical = group.max(by: { contextScore($0, in: store) < contextScore($1, in: store) }) else {
                continue
            }

            for duplicate in group where duplicate !== canonical {
                mergeContext(duplicate, into: canonical, in: store, modelContext: context, state: &state, report: &report)
            }
        }
    }

    private static func mergeContext(
        _ duplicate: Context,
        into canonical: Context,
        in store: RepairStore,
        modelContext: ModelContext,
        state: inout RepairState,
        report: inout DataIntegrityRepairReport
    ) {
        guard !state.deletedContexts.contains(ObjectIdentifier(duplicate)) else { return }

        for area in store.areas where area.context === duplicate && !state.deletedAreas.contains(ObjectIdentifier(area)) {
            _ = mergeArea(area, intoContext: canonical, in: store, modelContext: modelContext, state: &state, report: &report)
        }

        for project in store.projects where project.context === duplicate && !state.deletedProjects.contains(ObjectIdentifier(project)) {
            _ = mergeProject(project, intoContext: canonical, preferredArea: project.area, in: store, modelContext: modelContext, state: &state, report: &report)
        }

        for task in store.tasks where task.context === duplicate {
            task.context = canonical
            report.movedTasks += 1
        }
        for goal in store.goals where goal.context === duplicate {
            goal.context = canonical
            report.movedGoals += 1
        }
        for habit in store.habits where habit.context === duplicate {
            habit.context = canonical
            report.movedHabits += 1
        }

        modelContext.delete(duplicate)
        state.deletedContexts.insert(ObjectIdentifier(duplicate))
        report.duplicateContextsMerged += 1
    }

    @discardableResult
    private static func mergeArea(
        _ source: Area,
        intoContext canonicalContext: Context,
        in store: RepairStore,
        modelContext: ModelContext,
        state: inout RepairState,
        report: inout DataIntegrityRepairReport
    ) -> Area? {
        guard !state.deletedAreas.contains(ObjectIdentifier(source)) else { return nil }

        let existing = store.areas
            .filter { area in
                area !== source &&
                    !state.deletedAreas.contains(ObjectIdentifier(area)) &&
                    area.context === canonicalContext &&
                    area.id == source.id
            }
            .max { areaScore($0, in: store) < areaScore($1, in: store) }

        guard let target = existing else {
            if source.context !== canonicalContext {
                source.context = canonicalContext
                report.movedAreas += 1
            }
            return source
        }

        mergeAreaFields(from: source, into: target)

        for task in store.tasks where task.area === source {
            task.area = target
            task.context = target.context
            report.movedTasks += 1
        }
        for project in store.projects where project.area === source && !state.deletedProjects.contains(ObjectIdentifier(project)) {
            project.area = target
            _ = mergeProject(project, intoContext: canonicalContext, preferredArea: target, in: store, modelContext: modelContext, state: &state, report: &report)
        }
        for note in store.notes where note.area === source {
            note.area = target
            report.movedNotes += 1
        }
        for document in store.documents where document.area === source {
            document.area = target
            report.movedDocuments += 1
        }
        for link in store.links where link.area === source {
            link.area = target
            report.movedLinks += 1
        }
        for goalLink in store.goalLinks where goalLink.area === source {
            goalLink.area = target
            report.movedGoalLinks += 1
        }

        modelContext.delete(source)
        state.deletedAreas.insert(ObjectIdentifier(source))
        report.duplicateAreasMerged += 1
        return target
    }

    @discardableResult
    private static func mergeProject(
        _ source: Project,
        intoContext canonicalContext: Context,
        preferredArea: Area?,
        in store: RepairStore,
        modelContext: ModelContext,
        state: inout RepairState,
        report: inout DataIntegrityRepairReport
    ) -> Project? {
        guard !state.deletedProjects.contains(ObjectIdentifier(source)) else { return nil }

        let existing = store.projects
            .filter { project in
                project !== source &&
                    !state.deletedProjects.contains(ObjectIdentifier(project)) &&
                    project.context === canonicalContext &&
                    project.id == source.id
            }
            .max { projectScore($0, in: store) < projectScore($1, in: store) }

        guard let target = existing else {
            if source.context !== canonicalContext {
                source.context = canonicalContext
                report.movedProjects += 1
            }
            if let preferredArea, source.area !== preferredArea {
                source.area = preferredArea
            }
            return source
        }

        mergeProjectFields(from: source, into: target)
        if target.area == nil, let preferredArea {
            target.area = preferredArea
        }

        for task in store.tasks where task.project === source {
            task.project = target
            task.context = target.context
            report.movedTasks += 1
        }
        for note in store.notes where note.project === source {
            note.project = target
            report.movedNotes += 1
        }
        for document in store.documents where document.project === source {
            document.project = target
            report.movedDocuments += 1
        }
        for link in store.links where link.project === source {
            link.project = target
            report.movedLinks += 1
        }
        for goalLink in store.goalLinks where goalLink.project === source {
            goalLink.project = target
            report.movedGoalLinks += 1
        }

        modelContext.delete(source)
        state.deletedProjects.insert(ObjectIdentifier(source))
        report.duplicateProjectsMerged += 1
        return target
    }

    private static func contextScore(_ context: Context, in store: RepairStore) -> Int {
        let areaCount = store.areas.filter { $0.context === context }.count
        let projectCount = store.projects.filter { $0.context === context }.count
        let taskCount = store.tasks.filter { $0.context === context }.count
        let goalCount = store.goals.filter { $0.context === context }.count
        let habitCount = store.habits.filter { $0.context === context }.count
        return areaCount * 25 + projectCount * 20 + taskCount + goalCount * 10 + habitCount * 10 - context.order
    }

    private static func areaScore(_ area: Area, in store: RepairStore) -> Int {
        let taskCount = store.tasks.filter { $0.area === area }.count
        let projectCount = store.projects.filter { $0.area === area }.count
        let noteCount = store.notes.filter { $0.area === area }.count
        let documentCount = store.documents.filter { $0.area === area }.count
        return taskCount + projectCount * 10 + noteCount * 5 + documentCount * 5
    }

    private static func projectScore(_ project: Project, in store: RepairStore) -> Int {
        let taskCount = store.tasks.filter { $0.project === project }.count
        let noteCount = store.notes.filter { $0.project === project }.count
        let documentCount = store.documents.filter { $0.project === project }.count
        return taskCount + noteCount * 5 + documentCount * 5
    }

    private static func normalizedName(_ context: Context) -> String {
        context.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func mergeAreaFields(from source: Area, into target: Area) {
        if target.desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            target.desc = source.desc
        }
        target.loggedMinutes = max(target.loggedMinutes, source.loggedMinutes)
        target.hideDueDateIfEmpty = target.hideDueDateIfEmpty && source.hideDueDateIfEmpty
        target.hideSectionDueDateIfEmpty = target.hideSectionDueDateIfEmpty && source.hideSectionDueDateIfEmpty
        target.sectionConfigs = mergedSectionConfigs(primary: target.sectionConfigs, secondary: source.sectionConfigs)
        if target.status != .active && source.status == .active {
            target.status = .active
        }
    }

    private static func mergeProjectFields(from source: Project, into target: Project) {
        if target.desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            target.desc = source.desc
        }
        if target.dueDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            target.dueDate = source.dueDate
        }
        target.loggedMinutes = max(target.loggedMinutes, source.loggedMinutes)
        target.hideDueDateIfEmpty = target.hideDueDateIfEmpty && source.hideDueDateIfEmpty
        target.hideSectionDueDateIfEmpty = target.hideSectionDueDateIfEmpty && source.hideSectionDueDateIfEmpty
        target.sectionConfigs = mergedSectionConfigs(primary: target.sectionConfigs, secondary: source.sectionConfigs)
        if target.status != .active && source.status == .active {
            target.status = .active
        }
    }

    private static func mergedSectionConfigs(primary: [TaskSectionConfig], secondary: [TaskSectionConfig]) -> [TaskSectionConfig] {
        var result = primary
        var seen = Set(primary.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        for config in secondary {
            let key = config.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(config)
        }
        return result
    }

    private static func record(_ report: DataIntegrityRepairReport) {
        guard let data = try? JSONEncoder().encode(report) else { return }
        UserDefaults.standard.set(data, forKey: lastReportKey)
    }

    private static func log(_ report: DataIntegrityRepairReport) {
        guard report.changed else { return }
        logger.info(
            "Data integrity repair merged contexts=\(report.duplicateContextsMerged, privacy: .public), areas=\(report.duplicateAreasMerged, privacy: .public), projects=\(report.duplicateProjectsMerged, privacy: .public), movedTasks=\(report.movedTasks, privacy: .public) from \(report.source, privacy: .public)"
        )
    }
}
