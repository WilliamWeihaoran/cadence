import Foundation

/// Today's past-due summaries — the "Past Due Lists" and "Past Due Sections" cards that sit above
/// the day's task groups — stated once, for both platforms.
///
/// This is the second half of T-195. The first half (the rollover banner) is
/// `CadenceTodayRolloverSupport`; this is the half that was still declared under `macOS/Views/`
/// with zero readers under `Cadence/iOS/`. Nothing in it is AppKit-shaped: it is a filter over
/// `Project.dueDate`, a walk of `Area.sectionConfigs` / `Project.sectionConfigs`, and two counts.
///
/// **A section is not a model.** It is a `TaskSectionConfig` value JSON-encoded into
/// `sectionConfigsRaw` and read back through the `sectionConfigs` computed property, which is what
/// the walks below use. A task points at one by *name* — `AppTask.sectionName`, read through
/// `resolvedSectionName` so a task with no explicit section still lands in the list's default
/// column — so the match is a case-insensitive name comparison and not an identity check.
///
/// Everything here is pure, so the derivation can be tested without a view on either platform.
/// That matters more than usual: `Cadence/iOS/` is entirely inside `#if os(iOS)` and invisible to
/// the macOS-built `CadenceTests`.
enum CadenceTodayOverdueSummarySupport {
    /// The two headings, so the platforms cannot name the same cards differently.
    static let listsHeading = "Past Due Lists"
    static let sectionsHeading = "Past Due Sections"

    /// Projects whose own due date has gone by, oldest first.
    ///
    /// Areas have no `dueDate` field at all, which is why this takes only projects — the mirror of
    /// `sectionSummaries`, which takes both because *columns* live on either kind of list.
    static func listSummaries(projects: [Project], todayKey: String) -> [CadenceTodayOverdueListSummary] {
        projects
            .filter { $0.isActive && !$0.dueDate.isEmpty && $0.dueDate < todayKey }
            .sorted { lhs, rhs in
                if lhs.dueDate != rhs.dueDate { return lhs.dueDate < rhs.dueDate }
                return lhs.order < rhs.order
            }
            .map { project in
                CadenceTodayOverdueListSummary(
                    id: "project-\(project.id.uuidString)",
                    areaID: nil,
                    projectID: project.id,
                    title: project.name,
                    icon: project.icon,
                    colorHex: project.colorHex,
                    dueDateKey: project.dueDate,
                    activeTaskCount: CadenceTaskQuerySupport.openTaskCount(for: project)
                )
            }
    }

    /// Kanban columns whose due date has gone by, across every active area and project.
    ///
    /// An archived or completed column is skipped: both are statements that the column is finished
    /// with, and a card offering to go and look at it would be Today asking about work the user has
    /// already filed away.
    static func sectionSummaries(
        areas: [Area],
        projects: [Project],
        todayKey: String
    ) -> [CadenceTodayOverdueSectionSummary] {
        let areaSummaries = areas
            .filter(\.isActive)
            .flatMap { area in
                summaries(
                    configs: area.sectionConfigs,
                    tasks: area.tasks ?? [],
                    todayKey: todayKey,
                    idPrefix: "area-\(area.id.uuidString)",
                    areaID: area.id,
                    projectID: nil,
                    parentName: area.name,
                    parentIcon: area.icon,
                    parentColorHex: area.colorHex
                )
            }
        let projectSummaries = projects
            .filter(\.isActive)
            .flatMap { project in
                summaries(
                    configs: project.sectionConfigs,
                    tasks: project.tasks ?? [],
                    todayKey: todayKey,
                    idPrefix: "project-\(project.id.uuidString)",
                    areaID: nil,
                    projectID: project.id,
                    parentName: project.name,
                    parentIcon: project.icon,
                    parentColorHex: project.colorHex
                )
            }

        return (areaSummaries + projectSummaries).sorted { lhs, rhs in
            if lhs.dueDateKey != rhs.dueDateKey { return lhs.dueDateKey < rhs.dueDateKey }
            if lhs.parentName != rhs.parentName {
                return lhs.parentName.localizedCaseInsensitiveCompare(rhs.parentName) == .orderedAscending
            }
            return lhs.sectionName.localizedCaseInsensitiveCompare(rhs.sectionName) == .orderedAscending
        }
    }

    /// One list's columns. Private because the sort above is part of the answer — a caller handed
    /// only half the store would get a stable but incomplete order.
    private static func summaries(
        configs: [TaskSectionConfig],
        tasks: [AppTask],
        todayKey: String,
        idPrefix: String,
        areaID: UUID?,
        projectID: UUID?,
        parentName: String,
        parentIcon: String,
        parentColorHex: String
    ) -> [CadenceTodayOverdueSectionSummary] {
        configs.compactMap { config -> CadenceTodayOverdueSectionSummary? in
            guard !config.isArchived,
                  !config.isCompleted,
                  !config.dueDate.isEmpty,
                  config.dueDate < todayKey else { return nil }
            let columnTasks = tasks.filter {
                $0.resolvedSectionName.caseInsensitiveCompare(config.name) == .orderedSame
            }
            return CadenceTodayOverdueSectionSummary(
                id: "\(idPrefix)-section-\(config.id.uuidString)",
                areaID: areaID,
                projectID: projectID,
                sectionName: config.name,
                parentName: parentName,
                parentIcon: parentIcon,
                parentColorHex: parentColorHex,
                dueDateKey: config.dueDate,
                openTaskCount: CadenceTaskQuerySupport.openTaskCount(from: columnTasks),
                completedTaskCount: CadenceTaskQuerySupport.completedTaskCount(from: columnTasks)
            )
        }
    }

    /// Where a past-due **list** card goes: the list's Tasks page. There is no column to point at,
    /// so the board would be the wrong tab to land on.
    static func openRequest(for summary: CadenceTodayOverdueListSummary) -> CadenceListOpenRequest? {
        guard let target = summary.listTarget else { return nil }
        return CadenceListOpenRequest(target: target, page: .tasks)
    }

    /// Where a past-due **section** card goes: the list's Kanban page, at that column. The board
    /// rather than the task list because the card names a column, and the column is a thing only
    /// the board draws.
    static func openRequest(for summary: CadenceTodayOverdueSectionSummary) -> CadenceListOpenRequest? {
        guard let target = summary.listTarget else { return nil }
        return CadenceListOpenRequest(target: target, page: .kanban, sectionName: summary.sectionName)
    }
}

/// A project whose own due date has gone by.
///
/// The colour is carried as the list's `colorHex` rather than as a resolved `Color`: it is a
/// user-owned palette value, and keeping it a string is what lets the derivation be checked without
/// SwiftUI. The card resolves it.
struct CadenceTodayOverdueListSummary: Identifiable, Equatable {
    let id: String
    let areaID: UUID?
    let projectID: UUID?
    let title: String
    let icon: String
    let colorHex: String
    let dueDateKey: String
    let activeTaskCount: Int
}

/// A kanban column whose due date has gone by, and the list it belongs to.
struct CadenceTodayOverdueSectionSummary: Identifiable, Equatable {
    let id: String
    let areaID: UUID?
    let projectID: UUID?
    let sectionName: String
    let parentName: String
    let parentIcon: String
    let parentColorHex: String
    let dueDateKey: String
    let openTaskCount: Int
    let completedTaskCount: Int
}

extension CadenceTodayOverdueListSummary {
    var listTarget: CadenceListOpenRequest.Target? {
        CadenceListOpenRequest.Target(areaID: areaID, projectID: projectID)
    }
}

extension CadenceTodayOverdueSectionSummary {
    var listTarget: CadenceListOpenRequest.Target? {
        CadenceListOpenRequest.Target(areaID: areaID, projectID: projectID)
    }
}

/// Which list to open, at which page, with which column brought into view.
///
/// **This is the decision; the transport is the platform-shaped half.** macOS says it with
/// `ListNavigationManager` — a shell-level router whose request the sidebar and `ListDetailView`
/// consume — and that manager is macOS-only. iOS has no equivalent and deliberately does not grow
/// one for this: see `iOSTodayOverdueSummaries`. Extracting the *request* is what lets both
/// platforms agree that a list card lands on Tasks and a section card lands on the board at its
/// column, while each keeps its own way of getting there.
///
/// The target is a `Target` rather than a bare `UUID` for the same reason `CadenceFocusTarget` is:
/// an area and a project with equal ids are different destinations, and a pair of optionals lets a
/// caller state neither or both.
nonisolated struct CadenceListOpenRequest: Equatable, Identifiable {
    enum Target: Equatable {
        case area(UUID)
        case project(UUID)

        /// `nil` when the pair says neither. A summary that names no list is one nothing can open,
        /// which is a thing to decline rather than to guess at.
        init?(areaID: UUID?, projectID: UUID?) {
            if let projectID {
                self = .project(projectID)
            } else if let areaID {
                self = .area(areaID)
            } else {
                return nil
            }
        }
    }

    var target: Target
    var page: ListDetailPage
    /// Only ever set alongside `.kanban`: a column is a thing the board draws, and no other page
    /// has anywhere to put a highlight.
    var sectionName: String?

    /// Derived from the request's own members rather than a fresh token, so `.sheet(item:)` treats
    /// two taps on the same card as the same presentation. A token would be right if this were an
    /// inbox something else consumed — `CadenceFocusHandoff` carries one for exactly that reason —
    /// and it is wrong here, where the request *is* the sheet's subject.
    var id: String {
        let targetID: String
        switch target {
        case .area(let uuid): targetID = "area-\(uuid.uuidString)"
        case .project(let uuid): targetID = "project-\(uuid.uuidString)"
        }
        return "\(targetID)|\(page.rawValue)|\(sectionName ?? "")"
    }
}

