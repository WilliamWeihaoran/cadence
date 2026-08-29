import Foundation
import SwiftData
import Testing
@testable import Cadence

/// T-317 and T-318: one shape twice — a create sheet's container selection outliving the list it
/// names.
///
/// **T-317.** `TaskContainerResolver.applyContainer` guards on finding the area or project by id
/// and simply returns when it cannot, attaching nothing, while `insertTask` inserts the task
/// regardless. Both create sheets held their selection in `@State` and re-normalized only when the
/// *selection* changed, never when the available lists did, so an id for a list deleted in another
/// window or removed by sync stayed reachable — and produced an Inbox task under a sheet that
/// still named a list.
///
/// **T-318.** The iOS sheet's List tile resolved its name out of `activeAreas` / `activeProjects`
/// and fell back to Inbox text when the selection was not among them, while the save path built its
/// `TaskCreationService` from the unfiltered `areas` / `projects`. A list archived or completed
/// while the sheet was open therefore made the tile read "Inbox" while the task landed in that
/// list.
///
/// **What these tests hold is that both answers now come from one place.** Every case below asks
/// for the label and for the saved container and asserts they name the same destination, because
/// two sources that agree today are exactly what produced T-318.
@MainActor
struct CadenceComposerContainerSurfaceTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
    }

    private func draft(container: TaskContainerSelection) -> TaskCreationDraft {
        TaskCreationDraft(
            title: "Write the brief",
            notes: "",
            priority: .none,
            container: container,
            sectionName: "",
            dueDateKey: "",
            scheduledDateKey: "",
            subtaskTitles: [],
            tags: []
        )
    }

    /// What the composer's List tile says.
    private func shownContainer(
        _ selection: TaskContainerSelection,
        areas: [Area],
        projects: [Project]
    ) -> String {
        CadenceTaskComposerSupport.containerName(for: selection, areas: areas, projects: projects)
    }

    /// Where a task actually lands, named the way the tile would have to name it.
    ///
    /// The "no container" answer is spelled as a literal here rather than read back from
    /// `CadenceTaskInspectorSupport.inboxSegmentTitle`, so the comparison cannot pass by both sides
    /// reaching for the same constant.
    private func savedContainer(
        _ selection: TaskContainerSelection,
        areas: [Area],
        projects: [Project],
        in modelContext: ModelContext
    ) throws -> String {
        let task = try #require(
            TaskCreationService(areas: areas, projects: projects)
                .insertTask(from: draft(container: selection), into: modelContext)
        )
        try modelContext.save()
        if let area = task.area { return area.name }
        if let project = task.project { return project.name }
        return "Inbox"
    }

    // MARK: - T-317: the list has vanished

    /// The sheet is holding an id for an area that has been deleted. The tile can only say Inbox,
    /// and Inbox is where the task goes — but the sheet must not get there by accident, so the
    /// selection it holds is reset first and the Add is refused once.
    @Test func aSelectionNamingADeletedAreaShowsInboxAndSavesToTheInbox() throws {
        let modelContext = try makeContext()
        let area = Area(name: "Operations")
        let vanishedID = area.id
        modelContext.insert(area)
        try modelContext.save()

        modelContext.delete(area)
        try modelContext.save()
        let remainingAreas = try modelContext.fetch(FetchDescriptor<Area>())
        #expect(remainingAreas.isEmpty)

        let selection = TaskContainerSelection.area(vanishedID)
        #expect(
            CadenceTaskComposerSupport.namesMissingContainer(
                selection, areas: remainingAreas, projects: []
            ),
            "a deleted list has to read as missing, or nothing resets the selection"
        )
        #expect(
            CadenceTaskComposerSupport.normalizedContainer(
                selection, areas: remainingAreas, projects: []
            ) == .inbox
        )

        let shown = shownContainer(selection, areas: remainingAreas, projects: [])
        let saved = try savedContainer(selection, areas: remainingAreas, projects: [], in: modelContext)
        #expect(shown == "Inbox")
        #expect(saved == "Inbox")
        #expect(shown == saved)
    }

    /// The same for a project, and this time through the selection the sheet is left holding —
    /// which is the value the Add button actually creates from once `reconcileContainer` has run.
    @Test func aSelectionNamingADeletedProjectResetsToInboxAndTheResetSelectionSavesToInbox() throws {
        let modelContext = try makeContext()
        let project = Project(name: "Rebrand")
        let vanishedID = project.id
        modelContext.insert(project)
        try modelContext.save()

        modelContext.delete(project)
        try modelContext.save()
        let remainingProjects = try modelContext.fetch(FetchDescriptor<Project>())

        let stale = TaskContainerSelection.project(vanishedID)
        let reset = CadenceTaskComposerSupport.normalizedContainer(
            stale, areas: [], projects: remainingProjects
        )
        #expect(reset == .inbox)

        let shown = shownContainer(reset, areas: [], projects: remainingProjects)
        let saved = try savedContainer(reset, areas: [], projects: remainingProjects, in: modelContext)
        #expect(shown == "Inbox")
        #expect(shown == saved)
    }

    /// Inbox is the *absence* of a list, so it can never be the thing that went missing — not even
    /// in a store with no lists at all. A composer that reset here would show its notice on every
    /// ordinary Inbox capture.
    @Test func inboxIsNeverMissingEvenWithNoListsInTheStore() {
        #expect(!CadenceTaskComposerSupport.namesMissingContainer(.inbox, areas: [], projects: []))
        #expect(CadenceTaskComposerSupport.normalizedContainer(.inbox, areas: [], projects: []) == .inbox)
        #expect(shownContainer(.inbox, areas: [], projects: []) == "Inbox")
    }

    // MARK: - T-318: the list has gone inactive

    /// An area archived while the sheet is open. It still exists, so it is still where the task
    /// goes — and the tile now says so instead of reading "Inbox" over a task headed elsewhere.
    @Test func aSelectionNamingAnArchivedAreaShowsThatAreaAndSavesIntoIt() throws {
        let modelContext = try makeContext()
        let area = Area(name: "Operations")
        modelContext.insert(area)
        try modelContext.save()

        area.status = .archived
        try modelContext.save()

        let areas = try modelContext.fetch(FetchDescriptor<Area>())
        #expect(areas.count == 1)
        #expect(!(areas.first?.isActive ?? true))

        let selection = TaskContainerSelection.area(area.id)
        #expect(!CadenceTaskComposerSupport.namesMissingContainer(selection, areas: areas, projects: []))

        let shown = shownContainer(selection, areas: areas, projects: [])
        let saved = try savedContainer(selection, areas: areas, projects: [], in: modelContext)
        #expect(shown == "Operations")
        #expect(saved == "Operations", "the save went somewhere the tile did not name")
        #expect(shown == saved)
    }

    /// A project completed while the sheet is open — `done`, not `archived`, because those are two
    /// different ways to leave the active set and only one of them was ever exercised.
    @Test func aSelectionNamingACompletedProjectShowsThatProjectAndSavesIntoIt() throws {
        let modelContext = try makeContext()
        let project = Project(name: "Rebrand")
        modelContext.insert(project)
        try modelContext.save()

        project.status = .done
        try modelContext.save()

        let projects = try modelContext.fetch(FetchDescriptor<Project>())
        #expect(!(projects.first?.isActive ?? true))

        let selection = TaskContainerSelection.project(project.id)
        let shown = shownContainer(selection, areas: [], projects: projects)
        let saved = try savedContainer(selection, areas: [], projects: projects, in: modelContext)
        #expect(shown == "Rebrand")
        #expect(saved == "Rebrand")
        #expect(shown == saved)
    }

    /// The ordinary case, so none of the above can pass by everything answering "Inbox".
    @Test func anActiveListShowsItsOwnNameAndSavesIntoItself() throws {
        let modelContext = try makeContext()
        let area = Area(name: "Operations")
        let project = Project(name: "Rebrand")
        modelContext.insert(area)
        modelContext.insert(project)
        try modelContext.save()

        let areas = try modelContext.fetch(FetchDescriptor<Area>())
        let projects = try modelContext.fetch(FetchDescriptor<Project>())

        let areaShown = shownContainer(.area(area.id), areas: areas, projects: projects)
        let areaSaved = try savedContainer(.area(area.id), areas: areas, projects: projects, in: modelContext)
        #expect(areaShown == "Operations")
        #expect(areaShown == areaSaved)

        let projectShown = shownContainer(.project(project.id), areas: areas, projects: projects)
        let projectSaved = try savedContainer(.project(project.id), areas: areas, projects: projects, in: modelContext)
        #expect(projectShown == "Rebrand")
        #expect(projectShown == projectSaved)
    }

    /// An untitled list is named, not blank: the badge used to render `area.name` straight through
    /// and drew a chip with a glyph and nothing beside it.
    @Test func anUntitledListStillGetsANameInComposerContainerSurface() throws {
        let modelContext = try makeContext()
        let area = Area(name: "")
        modelContext.insert(area)
        try modelContext.save()
        let areas = try modelContext.fetch(FetchDescriptor<Area>())

        #expect(shownContainer(.area(area.id), areas: areas, projects: []) == "Untitled Area")
    }

    // MARK: - What a picker may offer is a different question

    /// Existence is what a *selection* is measured against; activity is what a *picker* offers.
    /// Both container pickers already filtered this way, and keeping the two rules apart is what
    /// lets one pair of arrays feed the tile, the sections and the save.
    @Test func pickableListsAreTheActiveOnesOnly() throws {
        let modelContext = try makeContext()
        let live = Area(name: "Operations")
        let archived = Area(name: "Old Ops")
        archived.status = .archived
        let done = Area(name: "Finished Ops")
        done.status = .done
        let liveProject = Project(name: "Rebrand")
        let pausedProject = Project(name: "Paused Rebrand")
        pausedProject.status = .paused
        for model in [live, archived, done] { modelContext.insert(model) }
        modelContext.insert(liveProject)
        modelContext.insert(pausedProject)
        try modelContext.save()

        let areas = try modelContext.fetch(FetchDescriptor<Area>())
        let projects = try modelContext.fetch(FetchDescriptor<Project>())

        #expect(CadenceTaskComposerSupport.pickableAreas(areas).map(\.name) == ["Operations"])
        #expect(CadenceTaskComposerSupport.pickableProjects(projects).map(\.name) == ["Rebrand"])
        // …while every one of them still resolves as a destination.
        #expect(shownContainer(.area(archived.id), areas: areas, projects: projects) == "Old Ops")
        #expect(shownContainer(.project(pausedProject.id), areas: areas, projects: projects) == "Paused Rebrand")
    }

    /// The downgrade `reconcileContainer` exists to keep out of reach, asserted directly so the
    /// preflight is not pinned against a service that had quietly stopped doing it.
    @Test func theServiceStillSilentlyDowngradesAStaleSelection() throws {
        let modelContext = try makeContext()
        let area = Area(name: "Operations")
        let vanishedID = area.id
        modelContext.insert(area)
        try modelContext.save()
        modelContext.delete(area)
        try modelContext.save()

        let task = try #require(
            TaskCreationService(areas: [], projects: [])
                .insertTask(from: draft(container: .area(vanishedID)), into: modelContext)
        )
        try modelContext.save()
        #expect(task.area == nil)
        #expect(task.project == nil)
        #expect(task.sectionName == TaskSectionDefaults.defaultName)
    }

    // MARK: - The notice

    /// The refusal says what happened and what pressing Add again will do. It is one string so the
    /// two composers cannot come to describe the same failure differently.
    @Test func theMissingContainerNoticeNamesTheInboxAndTheNextStep() {
        let notice = CadenceTaskComposerSupport.missingContainerNotice
        #expect(notice.contains("no longer available"))
        #expect(notice.contains("Inbox"))
        #expect(notice.hasSuffix("."))
    }

    // MARK: - The wiring, which lives inside views

    private func strippedSource(_ relativePath: String) throws -> String {
        let raw = try CadenceSourceScan.sourceFile(relativePath)
        #expect(raw.count > 400, "\(relativePath) read as far too short to be the real file")
        let stripped = CadenceSourceScan.strippingComments(raw)
        #expect(stripped != raw, "\(relativePath) has no comments, which cannot be right")
        #expect(stripped.count == raw.count, "the stripper must blank comments, not delete them")
        return stripped
    }

    /// Both needles, against the shapes they have to tell apart: an argument fed by the query, an
    /// argument fed by a filtered copy, a differently-named parameter, and the property declaration
    /// the counter must not mistake for a call.
    @Test func theArgumentRegexesSeparateTheQueryFromAFilteredCopy() {
        let anyArgument = "(?<![A-Za-z])areas: [a-zA-Z]"
        let fromTheQuery = "(?<![A-Za-z])areas: areas(?![A-Za-z.])"

        #expect(CadenceSourceScan.matchCount(anyArgument, in: "TileView(areas: areas)") == 1)
        #expect(CadenceSourceScan.matchCount(anyArgument, in: "TileView(areas: activeAreas)") == 1)
        #expect(CadenceSourceScan.matchCount(anyArgument, in: "TileView(activeAreas: activeAreas)") == 0)
        #expect(CadenceSourceScan.matchCount(anyArgument, in: "private var areas: [Area]") == 0)

        #expect(CadenceSourceScan.matchCount(fromTheQuery, in: "TileView(areas: areas, projects: projects)") == 1)
        #expect(CadenceSourceScan.matchCount(fromTheQuery, in: "TileView(activeAreas: activeAreas)") == 0)
        #expect(CadenceSourceScan.matchCount(fromTheQuery, in: "TileView(areas: activeAreas)") == 0)
        #expect(CadenceSourceScan.matchCount(fromTheQuery, in: "TileView(areas: areasFiltered)") == 0)
        #expect(CadenceSourceScan.matchCount(fromTheQuery, in: "TileView(areas: areas.filter(isActive))") == 0)
    }

    /// **T-318, at the sheet.** Every list argument the iOS composer hands out is the same `@Query`
    /// the Add button saves through — the tile that names the destination, the sections, the marker
    /// suggestions and `TaskCreationService` alike. A filtered copy passed to any one of them is
    /// how the tile and the save came to disagree.
    @Test func theIOSComposerHandsEveryControlTheSameLists() throws {
        let source = try strippedSource("Cadence/iOS/iOSCreateTaskSheet.swift")
        #expect(source.contains("struct iOSCreateTaskSheet: View"))
        #expect(source.contains("@Query(sort: \\Area.order) private var areas: [Area]"))

        let areaArguments = CadenceSourceScan.matchCount("(?<![A-Za-z])areas: [a-zA-Z]", in: source)
        let areaArgumentsFromTheQuery = CadenceSourceScan.matchCount(
            "(?<![A-Za-z])areas: areas(?![A-Za-z.])", in: source
        )
        #expect(areaArguments >= 5)
        #expect(
            areaArgumentsFromTheQuery == areaArguments,
            "an `areas:` argument in the composer is fed by something other than the sheet's own query"
        )

        let projectArguments = CadenceSourceScan.matchCount("(?<![A-Za-z])projects: [a-zA-Z]", in: source)
        let projectArgumentsFromTheQuery = CadenceSourceScan.matchCount(
            "(?<![A-Za-z])projects: projects(?![A-Za-z.])", in: source
        )
        #expect(projectArguments >= 5)
        #expect(projectArgumentsFromTheQuery == projectArguments)

        #expect(source.contains("TaskCreationService(areas: areas, projects: projects)"))
    }

    /// **T-317, at the iOS sheet.** The Add button reconciles before it creates, and the sheet
    /// watches the lists rather than only its own selection.
    @Test func theIOSComposerReconcilesBeforeItCreatesAndWatchesTheLists() throws {
        let source = try strippedSource("Cadence/iOS/iOSCreateTaskSheet.swift")

        let create = try #require(CadenceSourceScan.functionBody(named: "create", in: source))
        let reconcileCall = create.range(of: "reconcileContainer()")
        let serviceCall = create.range(of: "TaskCreationService(")
        #expect(reconcileCall != nil, "create() creates without preflighting its container")
        #expect(serviceCall != nil)
        if let reconcileCall, let serviceCall {
            #expect(reconcileCall.upperBound < serviceCall.lowerBound,
                    "the preflight runs after the task has already been built")
        }

        let reconcile = try #require(CadenceSourceScan.functionBody(named: "reconcileContainer", in: source))
        #expect(reconcile.contains("namesMissingContainer"))
        #expect(reconcile.contains("fields.container = .inbox"))
        #expect(reconcile.contains("CadenceTaskComposerSupport.missingContainerNotice"))

        #expect(source.contains(".onChange(of: containerStillExists)"),
                "the sheet re-normalizes only when the selection changes, which is T-317's cause")
    }

    /// **T-318, at the tile.** The List tile's name comes from the shared resolver over the same
    /// arrays, and its picker narrows to the active lists itself rather than being handed a second
    /// pair.
    @Test func theListTileNamesItsContainerThroughTheSharedResolver() throws {
        let source = try strippedSource("Cadence/iOS/iOSCreateTaskSheetSupportViews.swift")
        #expect(source.contains("struct iOSTaskComposerValueTiles: View"))
        #expect(source.contains("let areas: [Area]"))
        #expect(source.contains("let projects: [Project]"))
        #expect(source.contains("CadenceTaskComposerSupport.containerName("))
        #expect(source.contains("CadenceTaskComposerSupport.resolvedContainer("))
        #expect(source.contains("CadenceTaskComposerSupport.pickableAreas(areas)"))
        #expect(source.contains("CadenceTaskComposerSupport.pickableProjects(projects)"))
    }

    /// **T-317, at the macOS sheet.** Same preflight, same watch, and the badge that names the
    /// container reads the shared resolver so it cannot answer "Area" over a task bound for the
    /// Inbox.
    @Test func theMacComposerReconcilesBeforeItCreatesAndItsBadgeSharesTheResolver() throws {
        let sheet = try strippedSource("Cadence/macOS/Sheets/CreateTaskSheet.swift")

        let createTask = try #require(CadenceSourceScan.functionBody(named: "createTask", in: sheet))
        let reconcileCall = createTask.range(of: "reconcileContainer()")
        let draftCall = createTask.range(of: "TaskCreationDraft(")
        #expect(reconcileCall != nil, "createTask() creates without preflighting its container")
        if let reconcileCall, let draftCall {
            #expect(reconcileCall.upperBound < draftCall.lowerBound)
        }

        let reconcile = try #require(CadenceSourceScan.functionBody(named: "reconcileContainer", in: sheet))
        #expect(reconcile.contains("namesMissingContainer"))
        #expect(reconcile.contains("selectedContainer = .inbox"))
        #expect(reconcile.contains("CadenceTaskComposerSupport.missingContainerNotice"))
        #expect(sheet.contains(".onChange(of: containerStillExists)"))

        let badge = try strippedSource("Cadence/macOS/Views/TasksPanelSupportViews.swift")
        #expect(badge.contains("struct ContainerPickerBadge: View"))
        #expect(badge.contains(
            "CadenceTaskComposerSupport.containerName(for: selection, areas: areas, projects: projects)"
        ))
    }
}
