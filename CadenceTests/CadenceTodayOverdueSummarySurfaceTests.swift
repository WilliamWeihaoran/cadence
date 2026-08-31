import Foundation
import SwiftData
import Testing
@testable import Cadence

/// T-195, second half. Today's past-due summaries — "Past Due Lists" and "Past Due Sections" —
/// were declared in `macOS/Views/TasksPanelSupport.swift`, derived in `TasksPanelDerivedState.init`
/// and drawn by `TasksPanelSupportViews`, with **zero** references under `Cadence/iOS/`. Nothing in
/// any of it was AppKit-shaped: a filter over `Project.dueDate`, a walk of `sectionConfigs`, two
/// counts, and two cards.
///
/// The derivation is `CadenceTodayOverdueSummarySupport` now, the cards are
/// `Shared/Components/CadenceTodayOverdueSummaryCards.swift`, and macOS is rewired onto both rather
/// than left beside them. These tests pin the derivation directly, prove the Mac still derives
/// exactly what it used to, and — because `Cadence/iOS/` is inside `#if os(iOS)` and this target
/// builds for macOS — scan the iOS call sites as source.
@Suite("Today past-due summaries")
struct CadenceTodayOverdueSummarySurfaceTests {

    // MARK: - Past due lists

    @Test func listSummariesAreActiveProjectsWhoseDueDateHasGoneBy() throws {
        let today = "2026-08-20"
        let late = project(name: "Q3 Launch", due: "2026-08-18")
        let dueToday = project(name: "Due today", due: today)
        let later = project(name: "Later", due: "2026-09-01")
        let undated = project(name: "No date")

        let summaries = CadenceTodayOverdueSummarySupport.listSummaries(
            projects: [late, dueToday, later, undated],
            todayKey: today
        )

        #expect(summaries.map(\.title) == ["Q3 Launch"])
        #expect(summaries.first?.dueDateKey == "2026-08-18")
        #expect(summaries.first?.projectID == late.id)
        #expect(summaries.first?.areaID == nil)
    }

    /// A completed or archived project is a statement that the work is filed away. Today asking
    /// after it would be the page raising something the user has already answered.
    @Test func listSummariesSkipListsThatAreNoLongerActive() throws {
        let today = "2026-08-20"
        let done = project(name: "Finished", due: "2026-08-01")
        done.status = .done
        let archived = project(name: "Archived", due: "2026-08-01")
        archived.status = .archived
        let active = project(name: "Active", due: "2026-08-01")

        let summaries = CadenceTodayOverdueSummarySupport.listSummaries(
            projects: [done, archived, active],
            todayKey: today
        )

        #expect(summaries.map(\.title) == ["Active"])
    }

    @Test func listSummariesSortOldestFirstThenBySidebarOrder() throws {
        let today = "2026-08-20"
        let older = project(name: "Older", due: "2026-08-01")
        let newerSecond = project(name: "B", due: "2026-08-19")
        newerSecond.order = 2
        let newerFirst = project(name: "A", due: "2026-08-19")
        newerFirst.order = 1

        let summaries = CadenceTodayOverdueSummarySupport.listSummaries(
            projects: [newerSecond, newerFirst, older],
            todayKey: today
        )

        #expect(summaries.map(\.title) == ["Older", "A", "B"])
    }

    /// The colour travels as the list's own `colorHex`, not as a resolved `Color`: it is a
    /// user-owned palette value, and a string is what lets this whole derivation be checked without
    /// SwiftUI on a platform whose views this target cannot build.
    @Test func listSummariesCarryTheListsOwnColourAsAHex() throws {
        let late = project(name: "Q3 Launch", due: "2026-08-18")
        late.colorHex = "#ff6b6b"
        late.icon = "shippingbox.fill"

        let summaries = CadenceTodayOverdueSummarySupport.listSummaries(
            projects: [late],
            todayKey: "2026-08-20"
        )

        #expect(summaries.first?.colorHex == "#ff6b6b")
        #expect(summaries.first?.icon == "shippingbox.fill")
    }

    // MARK: - Past due sections

    /// A section is **not a model**: it is a `TaskSectionConfig` value JSON-encoded into
    /// `sectionConfigsRaw`, read back through `sectionConfigs`, and pointed at by name from
    /// `AppTask.sectionName`. This walks the real accessor rather than the raw string.
    @Test func sectionSummariesWalkTheListsOwnColumnConfigs() throws {
        let today = "2026-08-20"
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let area = Area(name: "Home")
        context.insert(area)
        area.sectionConfigs = [
            TaskSectionConfig(name: "Repairs", dueDate: "2026-08-18"),
            TaskSectionConfig(name: "Someday", dueDate: "2026-09-30"),
            TaskSectionConfig(name: "Undated")
        ]

        let summaries = CadenceTodayOverdueSummarySupport.sectionSummaries(
            areas: [area],
            projects: [],
            todayKey: today
        )

        #expect(summaries.map(\.sectionName) == ["Repairs"])
        #expect(summaries.first?.parentName == "Home")
        #expect(summaries.first?.areaID == area.id)
        #expect(summaries.first?.projectID == nil)
    }

    @Test func sectionSummariesSkipArchivedAndCompletedColumns() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let area = Area(name: "Home")
        context.insert(area)
        var archived = TaskSectionConfig(name: "Archived", dueDate: "2026-08-01")
        archived.isArchived = true
        var completed = TaskSectionConfig(name: "Completed", dueDate: "2026-08-01")
        completed.isCompleted = true
        area.sectionConfigs = [
            archived,
            completed,
            TaskSectionConfig(name: "Open", dueDate: "2026-08-01")
        ]

        let summaries = CadenceTodayOverdueSummarySupport.sectionSummaries(
            areas: [area],
            projects: [],
            todayKey: "2026-08-20"
        )

        #expect(summaries.map(\.sectionName) == ["Open"])
    }

    /// The counts are over the column's own tasks, matched by `resolvedSectionName` — which is what
    /// puts a task carrying no explicit `sectionName` into the list's Default column rather than
    /// nowhere.
    @Test func sectionSummariesCountByResolvedSectionName() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let area = Area(name: "Home")
        context.insert(area)
        area.sectionConfigs = [TaskSectionConfig(name: "Repairs", dueDate: "2026-08-18")]

        let open = AppTask(title: "Fix the door")
        open.sectionName = "Repairs"
        // Case is not the handle: `resolvedSectionName` is compared case-insensitively, because
        // the pointer is a user-typed string and the column name is another one.
        let alsoOpen = AppTask(title: "Fix the window")
        alsoOpen.sectionName = "repairs"
        let done = AppTask(title: "Fixed the tap")
        done.sectionName = "Repairs"
        done.status = .done
        let elsewhere = AppTask(title: "Unrelated")
        elsewhere.sectionName = "Someday"
        for task in [open, alsoOpen, done, elsewhere] {
            context.insert(task)
            task.area = area
        }

        let summaries = CadenceTodayOverdueSummarySupport.sectionSummaries(
            areas: [area],
            projects: [],
            todayKey: "2026-08-20"
        )

        #expect(summaries.count == 1)
        #expect(summaries.first?.openTaskCount == 2)
        #expect(summaries.first?.completedTaskCount == 1)
    }

    @Test func sectionSummariesSortByDateThenParentThenColumn() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let alpha = Area(name: "Alpha")
        let beta = Area(name: "Beta")
        [alpha, beta].forEach(context.insert)
        alpha.sectionConfigs = [
            TaskSectionConfig(name: "Zebra", dueDate: "2026-08-19"),
            TaskSectionConfig(name: "Apple", dueDate: "2026-08-19")
        ]
        beta.sectionConfigs = [
            TaskSectionConfig(name: "Oldest", dueDate: "2026-08-01"),
            TaskSectionConfig(name: "Also nineteenth", dueDate: "2026-08-19")
        ]

        let summaries = CadenceTodayOverdueSummarySupport.sectionSummaries(
            areas: [alpha, beta],
            projects: [],
            todayKey: "2026-08-20"
        )

        #expect(summaries.map(\.sectionName) == ["Oldest", "Apple", "Zebra", "Also nineteenth"])
        #expect(summaries.map(\.parentName) == ["Beta", "Alpha", "Alpha", "Beta"])
    }

    /// Columns live on both kinds of list, unlike due dates, which is why this takes areas *and*
    /// projects while `listSummaries` takes only projects — `Area` has no `dueDate` field at all.
    @Test func sectionSummariesCoverAreasAndProjectsAlike() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let area = Area(name: "Home")
        let proj = Project(name: "Launch")
        [area].forEach(context.insert)
        context.insert(proj)
        area.sectionConfigs = [TaskSectionConfig(name: "Repairs", dueDate: "2026-08-18")]
        proj.sectionConfigs = [TaskSectionConfig(name: "Copy", dueDate: "2026-08-18")]

        let summaries = CadenceTodayOverdueSummarySupport.sectionSummaries(
            areas: [area],
            projects: [proj],
            todayKey: "2026-08-20"
        )

        #expect(Set(summaries.map(\.sectionName)) == ["Repairs", "Copy"])
        #expect(summaries.first(where: { $0.sectionName == "Copy" })?.projectID == proj.id)
        #expect(summaries.first(where: { $0.sectionName == "Repairs" })?.areaID == area.id)
    }

    // MARK: - The tap target's decision

    /// The one piece both platforms have to agree on. macOS spends the request on
    /// `ListNavigationManager`; iOS presents the same page. What must not differ is *which* page.
    @Test func aPastDueListOpensItsTaskListAndAPastDueColumnOpensTheBoard() throws {
        let listSummary = CadenceTodayOverdueListSummary(
            id: "project-1",
            areaID: nil,
            projectID: UUID(),
            title: "Q3 Launch",
            icon: "folder.fill",
            colorHex: Theme.blueHex,
            dueDateKey: "2026-08-18",
            activeTaskCount: 3
        )
        let sectionSummary = CadenceTodayOverdueSectionSummary(
            id: "area-1-section-1",
            areaID: UUID(),
            projectID: nil,
            sectionName: "Repairs",
            parentName: "Home",
            parentIcon: "house.fill",
            parentColorHex: Theme.blueHex,
            dueDateKey: "2026-08-18",
            openTaskCount: 2,
            completedTaskCount: 1
        )

        let listRequest = CadenceTodayOverdueSummarySupport.openRequest(for: listSummary)
        #expect(listRequest?.page == .tasks)
        #expect(listRequest?.sectionName == nil)
        #expect(listRequest?.target == .project(listSummary.projectID!))

        let sectionRequest = CadenceTodayOverdueSummarySupport.openRequest(for: sectionSummary)
        #expect(sectionRequest?.page == .kanban)
        #expect(sectionRequest?.sectionName == "Repairs")
        #expect(sectionRequest?.target == .area(sectionSummary.areaID!))
    }

    /// A summary that names no list is one nothing can open. Declining is the answer; guessing at
    /// an id is what would send a tap to the wrong page.
    @Test func aSummaryNamingNoListYieldsNoRequest() {
        let orphan = CadenceTodayOverdueListSummary(
            id: "orphan",
            areaID: nil,
            projectID: nil,
            title: "Nowhere",
            icon: "folder.fill",
            colorHex: Theme.blueHex,
            dueDateKey: "2026-08-18",
            activeTaskCount: 0
        )
        #expect(CadenceTodayOverdueSummarySupport.openRequest(for: orphan) == nil)
        #expect(CadenceListOpenRequest.Target(areaID: nil, projectID: nil) == nil)
    }

    /// `.sheet(item:)` needs an id, and it is derived from the request's own members rather than a
    /// fresh token: two taps on the same card are the same presentation, not two.
    @Test func aRequestsIdentityIsItsMembersAndNotAToken() {
        let target = CadenceListOpenRequest.Target.area(UUID())
        let first = CadenceListOpenRequest(target: target, page: .kanban, sectionName: "Repairs")
        let second = CadenceListOpenRequest(target: target, page: .kanban, sectionName: "Repairs")
        let other = CadenceListOpenRequest(target: target, page: .kanban, sectionName: "Someday")

        #expect(first.id == second.id)
        #expect(first.id != other.id)
        #expect(first == second)
    }

    // MARK: - macOS behaviour preservation

    /// Rewiring `TasksPanelDerivedState` onto the shared derivation is a refactor of a **live**
    /// surface, so this recomputes both summary arrays with the *old* inline expressions and
    /// asserts the new ones are identical — member for member and in order, because both feed a
    /// rendered list where a reordering would be visible.
    @Test func theMacDerivedStateStillDerivesExactlyWhatItUsedToInTodayOverdueSummarySurface() throws {
        let today = "2026-08-20"
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let home = Area(name: "Home")
        let work = Area(name: "Work")
        let archivedArea = Area(name: "Filed away")
        archivedArea.status = .archived
        [home, work, archivedArea].forEach(context.insert)
        home.sectionConfigs = [
            TaskSectionConfig(name: "Repairs", dueDate: "2026-08-18"),
            TaskSectionConfig(name: "Someday", dueDate: "2026-09-30")
        ]
        work.sectionConfigs = [TaskSectionConfig(name: "Reviews", dueDate: "2026-08-01")]
        archivedArea.sectionConfigs = [TaskSectionConfig(name: "Ignored", dueDate: "2026-01-01")]

        let launch = project(name: "Q3 Launch", due: "2026-08-18")
        launch.order = 2
        let rewrite = project(name: "Rewrite", due: "2026-08-18")
        rewrite.order = 1
        let future = project(name: "Next quarter", due: "2026-12-01")
        let doneProject = project(name: "Shipped", due: "2026-01-01")
        doneProject.status = .done
        [launch, rewrite, future, doneProject].forEach(context.insert)
        launch.sectionConfigs = [TaskSectionConfig(name: "Copy", dueDate: "2026-08-19")]

        let tasks = ["Fix the door", "Fix the window"].map { title -> AppTask in
            let task = AppTask(title: title)
            task.sectionName = "Repairs"
            context.insert(task)
            task.area = home
            return task
        }
        let settled = AppTask(title: "Fixed the tap")
        settled.sectionName = "Repairs"
        settled.status = .done
        context.insert(settled)
        settled.area = home

        let areas = [home, work, archivedArea]
        let projects = [launch, rewrite, future, doneProject]

        let derived = TasksPanelDerivedState(
            allTasks: tasks + [settled],
            areas: areas,
            projects: projects,
            mode: .todayOverview,
            todayKey: today
        )

        // The expressions that used to be inline in `TasksPanelDerivedState.init`, verbatim apart
        // from the `Color` that is now a hex string and the type names.
        let legacyLists = projects
            .filter { $0.isActive && !$0.dueDate.isEmpty && $0.dueDate < today }
            .sorted { lhs, rhs in
                if lhs.dueDate != rhs.dueDate { return lhs.dueDate < rhs.dueDate }
                return lhs.order < rhs.order
            }
            .map { project in
                (
                    id: "project-\(project.id.uuidString)",
                    title: project.name,
                    icon: project.icon,
                    colorHex: project.colorHex,
                    dueDateKey: project.dueDate,
                    activeTaskCount: CadenceTaskQuerySupport.openTaskCount(for: project)
                )
            }

        #expect(derived.overdueListSummaries.map(\.id) == legacyLists.map(\.id))
        #expect(derived.overdueListSummaries.map(\.title) == legacyLists.map(\.title))
        #expect(derived.overdueListSummaries.map(\.icon) == legacyLists.map(\.icon))
        #expect(derived.overdueListSummaries.map(\.colorHex) == legacyLists.map(\.colorHex))
        #expect(derived.overdueListSummaries.map(\.dueDateKey) == legacyLists.map(\.dueDateKey))
        #expect(derived.overdueListSummaries.map(\.activeTaskCount) == legacyLists.map(\.activeTaskCount))
        #expect(derived.overdueListSummaries.map(\.title) == ["Rewrite", "Q3 Launch"])

        typealias LegacySection = (
            id: String,
            sectionName: String,
            parentName: String,
            parentIcon: String,
            parentColorHex: String,
            dueDateKey: String,
            openTaskCount: Int,
            completedTaskCount: Int
        )

        let legacyAreaSections: [LegacySection] = areas
            .filter(\.isActive)
            .flatMap { area in
                area.sectionConfigs.compactMap { config -> LegacySection? in
                    guard !config.isArchived, !config.isCompleted, !config.dueDate.isEmpty, config.dueDate < today else { return nil }
                    let sectionTasks = (area.tasks ?? []).filter { $0.resolvedSectionName.caseInsensitiveCompare(config.name) == .orderedSame }
                    return (
                        id: "area-\(area.id.uuidString)-section-\(config.id.uuidString)",
                        sectionName: config.name,
                        parentName: area.name,
                        parentIcon: area.icon,
                        parentColorHex: area.colorHex,
                        dueDateKey: config.dueDate,
                        openTaskCount: CadenceTaskQuerySupport.openTaskCount(from: sectionTasks),
                        completedTaskCount: CadenceTaskQuerySupport.completedTaskCount(from: sectionTasks)
                    )
                }
            }
        let legacyProjectSections: [LegacySection] = projects
            .filter(\.isActive)
            .flatMap { project in
                project.sectionConfigs.compactMap { config -> LegacySection? in
                    guard !config.isArchived, !config.isCompleted, !config.dueDate.isEmpty, config.dueDate < today else { return nil }
                    let sectionTasks = (project.tasks ?? []).filter { $0.resolvedSectionName.caseInsensitiveCompare(config.name) == .orderedSame }
                    return (
                        id: "project-\(project.id.uuidString)-section-\(config.id.uuidString)",
                        sectionName: config.name,
                        parentName: project.name,
                        parentIcon: project.icon,
                        parentColorHex: project.colorHex,
                        dueDateKey: config.dueDate,
                        openTaskCount: CadenceTaskQuerySupport.openTaskCount(from: sectionTasks),
                        completedTaskCount: CadenceTaskQuerySupport.completedTaskCount(from: sectionTasks)
                    )
                }
            }
        let legacySections = (legacyAreaSections + legacyProjectSections).sorted { lhs, rhs in
            if lhs.dueDateKey != rhs.dueDateKey { return lhs.dueDateKey < rhs.dueDateKey }
            if lhs.parentName != rhs.parentName {
                return lhs.parentName.localizedCaseInsensitiveCompare(rhs.parentName) == .orderedAscending
            }
            return lhs.sectionName.localizedCaseInsensitiveCompare(rhs.sectionName) == .orderedAscending
        }

        #expect(derived.overdueSectionSummaries.map(\.id) == legacySections.map(\.id))
        #expect(derived.overdueSectionSummaries.map(\.sectionName) == legacySections.map(\.sectionName))
        #expect(derived.overdueSectionSummaries.map(\.parentName) == legacySections.map(\.parentName))
        #expect(derived.overdueSectionSummaries.map(\.parentIcon) == legacySections.map(\.parentIcon))
        #expect(derived.overdueSectionSummaries.map(\.parentColorHex) == legacySections.map(\.parentColorHex))
        #expect(derived.overdueSectionSummaries.map(\.dueDateKey) == legacySections.map(\.dueDateKey))
        #expect(derived.overdueSectionSummaries.map(\.openTaskCount) == legacySections.map(\.openTaskCount))
        #expect(derived.overdueSectionSummaries.map(\.completedTaskCount) == legacySections.map(\.completedTaskCount))

        // Non-vacuity: the fixture really exercises both arrays, both list kinds, both skip rules
        // and the counts. Without this the eight comparisons above pass on two empty arrays.
        #expect(derived.overdueListSummaries.count == 2)
        #expect(derived.overdueSectionSummaries.map(\.sectionName) == ["Reviews", "Repairs", "Copy"])
        #expect(derived.overdueSectionSummaries.first(where: { $0.sectionName == "Repairs" })?.openTaskCount == 2)
        #expect(derived.overdueSectionSummaries.first(where: { $0.sectionName == "Repairs" })?.completedTaskCount == 1)
        #expect(!derived.overdueSectionSummaries.contains { $0.parentName == "Filed away" })
        #expect(!derived.overdueListSummaries.contains { $0.title == "Shipped" })
    }

    // MARK: - Call-site wiring

    /// **Behavioural, because the value was there all along (T-161).** This read the two call sites
    /// as text — `openRequest(for: summary)` and `listNavigationManager.open(` present *somewhere*
    /// in `TasksPanelSupport.swift` — which is the `cfa3b3b` shape exactly: the private
    /// `open(_:listNavigationManager:)` could swap its `.area` and `.project` branches, or drop
    /// `sectionName:`, and every scanned string would still be sitting in the file. macOS's half is
    /// compiled by this target, so the hop is run instead: two summaries in, and the request the
    /// manager is actually left holding is compared against the shared decision.
    @MainActor
    @Test func theMacCardsHopTheNavigationManagerThroughTheSharedRequest() throws {
        let manager = ListNavigationManager.shared
        manager.request = nil

        let projectID = UUID()
        let listSummary = CadenceTodayOverdueListSummary(
            id: "project-1",
            areaID: nil,
            projectID: projectID,
            title: "Q3 Launch",
            icon: "folder.fill",
            colorHex: Theme.blueHex,
            dueDateKey: "2026-08-18",
            activeTaskCount: 3
        )
        TasksPanelSupport.openOverdueListSummary(listSummary, listNavigationManager: manager)
        // A *project* card must not land the router on an area of the same id, and a list card
        // carries no column to scroll to.
        #expect(manager.request?.projectID == projectID)
        #expect(manager.request?.areaID == nil)
        #expect(manager.request?.page == .tasks)
        #expect(manager.request?.sectionName == nil)

        let areaID = UUID()
        let sectionSummary = CadenceTodayOverdueSectionSummary(
            id: "area-1-section-1",
            areaID: areaID,
            projectID: nil,
            sectionName: "Repairs",
            parentName: "Home",
            parentIcon: "house.fill",
            parentColorHex: Theme.blueHex,
            dueDateKey: "2026-08-18",
            openTaskCount: 2,
            completedTaskCount: 1
        )
        TasksPanelSupport.openOverdueSectionSummary(sectionSummary, listNavigationManager: manager)
        #expect(manager.request?.areaID == areaID)
        #expect(manager.request?.projectID == nil)
        #expect(manager.request?.page == .kanban)
        // The column the card names, carried through the hop. Dropping it lands the board on
        // whatever column it last showed, which is the tap doing something other than what it said.
        #expect(manager.request?.sectionName == "Repairs")

        // A summary naming no list spends nothing rather than routing somewhere invented.
        manager.request = nil
        let orphan = CadenceTodayOverdueListSummary(
            id: "orphan",
            areaID: nil,
            projectID: nil,
            title: "Nowhere",
            icon: "folder.fill",
            colorHex: Theme.blueHex,
            dueDateKey: "2026-08-18",
            activeTaskCount: 0
        )
        TasksPanelSupport.openOverdueListSummary(orphan, listNavigationManager: manager)
        #expect(manager.request == nil)

        manager.request = nil

        // The two branches that used to be spelled out per card, gone: one translation, not two.
        // An absence over the whole file is the one claim a scan states better than a call.
        let source = try strippingComments(sourceFile("Cadence/macOS/Views/TasksPanelSupport.swift"))
        #expect(!source.contains("if let projectID = summary.projectID"))
    }

    @Test func theMacPanelDrawsTheSharedCardsAndHeadings() throws {
        let panel = try strippingComments(sourceFile("Cadence/macOS/Views/TasksPanel.swift"))
        #expect(panel.contains("CadenceTodayOverdueListCard(summary: summary)"))
        #expect(panel.contains("CadenceTodayOverdueSectionCard(summary: summary)"))
        #expect(panel.contains("CadenceTodayOverdueSummaryHeading(title: title, count: count)"))
        #expect(panel.contains("CadenceTodayOverdueSummarySupport.listsHeading"))
        #expect(panel.contains("CadenceTodayOverdueSummarySupport.sectionsHeading"))

        let views = try strippingComments(sourceFile("Cadence/macOS/Views/TasksPanelSupportViews.swift"))
        #expect(!views.contains("struct TodayOverdueListCard"))
        #expect(!views.contains("struct TodayOverdueSectionCard"))
        #expect(!views.contains("struct OverdueSummaryCaption"))
    }

    /// `Cadence/iOS/` is invisible to this target, so the iOS half is pinned by reading it.
    @Test func iOSTodayDerivesTheSameSummariesAndDrawsTheSameCards() throws {
        let host = try strippingComments(sourceFile("Cadence/iOS/iOSTodayView.swift"))
        #expect(host.contains("CadenceTodayOverdueSummarySupport.listSummaries("))
        #expect(host.contains("CadenceTodayOverdueSummarySupport.sectionSummaries("))
        #expect(host.contains("iOSTodayOverdueSummaries("))

        let list = try strippingComments(sourceFile("Cadence/iOS/iOSTodayTaskSections.swift"))
        #expect(list.contains("CadenceTodayOverdueListCard(summary: summary)"))
        #expect(list.contains("CadenceTodayOverdueSectionCard(summary: summary)"))
        #expect(list.contains("CadenceTodayOverdueSummaryHeading("))
        #expect(list.contains("CadenceTodayOverdueSummarySupport.openRequest(for: summary)"))
    }

    /// Both widths draw the cards because both draw `iOSTodayTaskSections` — the one list. A second
    /// `CadenceTodayOverdue*Card(` under this folder is the near-copy this whole ticket is about.
    @Test func bothIOSWidthsDrawTheCardsFromTheOneList() throws {
        for host in ["Cadence/iOS/iOSTodayView.swift", "Cadence/iOS/iOSTodayCompactViews.swift"] {
            let source = try strippingComments(sourceFile(host))
            #expect(source.contains("overdueSummaries"), "\(host) does not pass the summaries through")
            #expect(
                !source.contains("CadenceTodayOverdueListCard("),
                "\(host) draws its own cards instead of going through iOSTodayTaskSections"
            )
            #expect(
                !source.contains("CadenceTodayOverdueSectionCard("),
                "\(host) draws its own cards instead of going through iOSTodayTaskSections"
            )
        }

        var drawing = 0
        for path in try swiftFiles(under: "Cadence/iOS") {
            let source = try strippingComments(sourceFile(path))
            if source.contains("CadenceTodayOverdueListCard(") || source.contains("CadenceTodayOverdueSectionCard(") {
                drawing += 1
            }
        }
        #expect(drawing == 1, "\(drawing) iOS files draw the past-due cards — there should be exactly one")
    }

    /// The tap target is the one genuinely platform-shaped piece, and iOS must not have grown a
    /// second copy of the Mac's router to serve it.
    @Test func theIOSTapTargetPresentsRatherThanReachingForANavigationManager() throws {
        let host = try strippingComments(sourceFile("Cadence/iOS/iOSTodayView.swift"))
        #expect(host.contains("iOSTodayOverdueListSheet(request: request)"))
        #expect(!host.contains("ListNavigationManager"))

        for path in try swiftFiles(under: "Cadence/iOS") {
            let source = try strippingComments(sourceFile(path))
            #expect(!source.contains("ListNavigationManager"), "\(path) reaches for the macOS-only navigation manager")
        }
    }

    /// One set of strings. A second literal is how the two platforms would name the same run of
    /// cards differently.
    @Test func neitherPlatformRespellsTheHeadings() throws {
        let owner = "Cadence/Shared/CadenceTodayOverdueSummarySupport.swift"
        let literals = ["\"Past Due Lists\"", "\"Past Due Sections\""]
        var scanned = 0
        for path in try swiftFiles(under: "Cadence") where path != owner {
            let source = try strippingComments(sourceFile(path))
            scanned += 1
            for literal in literals {
                #expect(!source.contains(literal), "\(path) re-spells \(literal)")
            }
        }
        #expect(scanned > 300, "only \(scanned) files scanned — the enumerator read nothing")
        let ownerSource = try strippingComments(sourceFile(owner))
        for literal in literals {
            #expect(ownerSource.contains(literal), "\(owner) no longer declares \(literal)")
        }
    }

    /// The comment stripper is load-bearing above — several of these files explain the feature in
    /// prose that names the very strings and types being banned.
    @Test func theCommentStripperStripsInTodayOverdueSummarySurface() throws {
        let stripped = try strippingComments("let a = 1 // \"Past Due Lists\"\n/* ListNavigationManager */ let b = 2\n")
        #expect(!stripped.contains("Past Due Lists"))
        #expect(!stripped.contains("ListNavigationManager"))
        #expect(stripped.contains("let a = 1"))
        #expect(stripped.contains("let b = 2"))
    }

    /// **"Nothing planned for today" must not print under a card saying three of your lists are
    /// past due.** `isEmptyState` tested the four task buckets plus Completed, and the past-due
    /// cards are the one thing on Today derived from *projects* and *columns* rather than tasks —
    /// so a day with no work on it and an overdue list drew both at once (T-592). iOS had guarded
    /// this since it got the cards; macOS never did.
    @Test func theMacTodayIsNotEmptyWhileAPastDueCardIsOnScreen() throws {
        let today = "2026-08-20"
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let launch = project(name: "Q3 Launch", due: "2026-08-18")
        context.insert(launch)

        let area = Area(name: "Home")
        context.insert(area)
        area.sectionConfigs = [TaskSectionConfig(name: "Repairs", dueDate: "2026-08-01")]

        // No tasks at all: every bucket `isEmptyState` used to consult is empty by construction.
        let listCardOnly = TasksPanelDerivedState(
            allTasks: [],
            areas: [],
            projects: [launch],
            mode: .todayOverview,
            todayKey: today
        )
        #expect(!listCardOnly.overdueListSummaries.isEmpty)
        #expect(!listCardOnly.isEmptyState(for: .todayOverview))

        let sectionCardOnly = TasksPanelDerivedState(
            allTasks: [],
            areas: [area],
            projects: [],
            mode: .todayOverview,
            todayKey: today
        )
        #expect(!sectionCardOnly.overdueSectionSummaries.isEmpty)
        #expect(!sectionCardOnly.isEmptyState(for: .todayOverview))

        // And a day with neither cards nor tasks is still empty, so the guard cannot be satisfied
        // by never reporting empty at all.
        let nothing = TasksPanelDerivedState(
            allTasks: [],
            areas: [],
            projects: [],
            mode: .todayOverview,
            todayKey: today
        )
        #expect(nothing.isEmptyState(for: .todayOverview))
    }

    // MARK: - Fixtures

    private func project(name: String, due: String = "") -> Project {
        let project = Project(name: name)
        project.dueDate = due
        return project
    }
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

/// `enumerator(atPath:)` rather than `enumerator(at:)`: the URL variant yields *absolute* paths,
/// and `#filePath` can name the repo through a symlinked prefix (`/tmp` against `/private/tmp` on
/// an isolated build tree) that `FileManager` resolves and the literal does not.
private func swiftFiles(under relativeDirectory: String) throws -> [String] {
    let directory = repositoryRoot().appendingPathComponent(relativeDirectory)
    guard let enumerator = FileManager.default.enumerator(atPath: directory.path) else {
        return []
    }
    return enumerator.compactMap { element in
        guard let relativePath = element as? String, relativePath.hasSuffix(".swift") else { return nil }
        return "\(relativeDirectory)/\(relativePath)"
    }
}

private func sourceFile(_ relativePath: String) throws -> String {
    try String(contentsOf: repositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
}

private func strippingComments(_ source: String) throws -> String {
    var result = source
    for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            result.replaceSubrange(range, with: "")
        }
    }
    return result
}
