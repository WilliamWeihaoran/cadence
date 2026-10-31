#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **[[T-3210]] — the Mac task row's menu, held by what it DOES.**
///
/// `MacTaskRowContextMenuParityTests` proves the Mac menu names the same shared helpers and says
/// the same words as iOS's. That is drift coverage: reroute Move Section to the container helper,
/// pass the wrong task, or drop `commit:`, and every one of those pins still passes. These tests
/// invoke each of the four writing actions — Duplicate, Move to List, Move Section, Repeat —
/// against an in-memory store and read the model back. The menu itself is SwiftUI and cannot be
/// presented from a unit test, so the actions are `static` on `MacTaskRowContextMenu` and the
/// menu's buttons call them; `eachSubmenuRoutesToItsOwnAction` holds that last hop.
///
/// Every fixture carries a sibling task the action must NOT touch, so passing the wrong task goes
/// red, and every commit-taking action is run once with a refusing `commit:`, so a call that drops
/// the parameter (and falls back to a `save()` that succeeds) goes red too.
@MainActor
struct MacTaskRowContextMenuEffectTests {
    private struct CommitRefused: Error {}

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let area: Area
        let project: Project
        let subject: AppTask
        let sibling: AppTask
        var allTasks: [AppTask] { [subject, sibling] }

        /// A second context on the same store: what it reads is what was COMMITTED, not what is
        /// merely pending in the menu's context.
        func committed(_ task: AppTask) throws -> AppTask? {
            let id = task.id
            return try ModelContext(container).fetch(FetchDescriptor<AppTask>(predicate: #Predicate { $0.id == id })).first
        }
    }

    private func makeFixture() throws -> Fixture {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let area = Area(name: "Home")
        area.sectionNames = ["Now", "Later"]
        let project = Project(name: "Launch")
        project.sectionNames = ["Plan", "Later"]
        context.insert(area)
        context.insert(project)

        let subject = AppTask(title: "Subject")
        subject.area = area
        subject.sectionName = "Later"
        subject.order = 0
        subject.priority = .high
        let sibling = AppTask(title: "Sibling")
        sibling.area = area
        sibling.sectionName = "Now"
        sibling.order = 1
        context.insert(subject)
        context.insert(sibling)
        area.tasks = [subject, sibling]
        try context.save()
        return Fixture(container: container, context: context, area: area, project: project, subject: subject, sibling: sibling)
    }

    private func allCommittedTasks(_ fixture: Fixture) throws -> [AppTask] {
        try ModelContext(fixture.container).fetch(FetchDescriptor<AppTask>(sortBy: [SortDescriptor(\.order)]))
    }

    // MARK: - Duplicate

    @Test func duplicateCommitsACopyOfTheRowsTaskInItsOwnList() throws {
        let f = try makeFixture()

        let outcome = MacTaskRowContextMenu.duplicate(f.subject, allTasks: f.allTasks, modelContext: f.context)

        #expect(outcome == .settled)
        let committed = try allCommittedTasks(f)
        #expect(committed.count == 3, "exactly one task inserted and committed")
        let copies = committed.filter { $0.id != f.subject.id && $0.id != f.sibling.id }
        let copy = try #require(copies.first)
        #expect(copy.title == "Subject", "the copy is of the row's task, not its sibling")
        #expect(copy.priority == .high)
        #expect(copy.area?.id == f.area.id)
        #expect(copy.sectionName == "Later")
        // The original and its sibling are left as they were.
        #expect(f.subject.area?.id == f.area.id && f.subject.sectionName == "Later")
        #expect(f.sibling.title == "Sibling" && f.sibling.sectionName == "Now")
    }

    // MARK: - Move to List

    @Test func moveToListCommitsTheRowsTaskIntoTheChosenListKeepingItsSection() throws {
        let f = try makeFixture()
        var commits = 0

        let outcome = MacTaskRowContextMenu.moveToList(
            f.subject, area: nil, project: f.project, allTasks: f.allTasks, modelContext: f.context,
            commit: { commits += 1; try $0.save() }
        )

        #expect(outcome == .settled)
        #expect(commits == 1, "the move committed through the caller's commit:")
        let committed = try #require(try f.committed(f.subject))
        #expect(committed.project?.id == f.project.id)
        #expect(committed.area == nil)
        // The row's own section is carried, not the helper's default: "Later" exists in the
        // project, and a dropped `sectionName:` would normalise to its first section, "Plan".
        #expect(committed.sectionName == "Later")
        let sibling = try #require(try f.committed(f.sibling))
        #expect(sibling.area?.id == f.area.id && sibling.project == nil, "the sibling did not move")
        #expect(f.context.insertedModelsArray.isEmpty, "Move to List inserts nothing")
    }

    @Test func moveToInboxClearsBothContainers() throws {
        let f = try makeFixture()

        let outcome = MacTaskRowContextMenu.moveToList(
            f.subject, area: nil, project: nil, allTasks: f.allTasks, modelContext: f.context
        )

        #expect(outcome == .settled)
        let committed = try #require(try f.committed(f.subject))
        #expect(committed.area == nil && committed.project == nil)
        #expect(try #require(try f.committed(f.sibling)).area?.id == f.area.id)
    }

    @Test func aRefusedMoveToListIsReportedAndUndone() throws {
        let f = try makeFixture()

        let outcome = MacTaskRowContextMenu.moveToList(
            f.subject, area: nil, project: f.project, allTasks: f.allTasks, modelContext: f.context,
            commit: { _ in throw CommitRefused() }
        )

        #expect(outcome == .refused(.move))
        #expect(f.subject.area?.id == f.area.id && f.subject.project == nil, "the task is back where it was")
        #expect(f.subject.sectionName == "Later")
    }

    // MARK: - T-5353: the pickers and the drop move a task the way the menu does

    /// The row's list chip speaks `TaskContainerSelection`; it used to write the relationships
    /// inline and keep the old list's `order`, so the task landed mid-list. Through the menu's path
    /// it goes to the end of the new list and is committed.
    @Test func aSelectionMovePutsTheTaskAtTheEndOfTheNewListAndCommits() throws {
        let f = try makeFixture()
        let resident = AppTask(title: "Resident")
        resident.project = f.project
        resident.order = 5
        f.context.insert(resident)
        try f.context.save()
        var commits = 0

        let outcome = MacTaskRowContextMenu.moveToList(
            f.subject, selection: .project(f.project.id), areas: [f.area], projects: [f.project],
            modelContext: f.context, commit: { commits += 1; try $0.save() }
        )

        #expect(outcome == .settled)
        #expect(commits == 1)
        let committed = try #require(try f.committed(f.subject))
        #expect(committed.project?.id == f.project.id)
        #expect(committed.order > resident.order, "the moved task kept its old order instead of going last")
        #expect(committed.sectionName == "Later")
    }

    /// Re-picking the list the task is already in is not a move: no commit, no re-order.
    @Test func aSelectionOfTheCurrentListMovesNothing() throws {
        let f = try makeFixture()
        var commits = 0

        let outcome = MacTaskRowContextMenu.moveToList(
            f.subject, selection: .area(f.area.id), areas: [f.area], projects: [f.project],
            modelContext: f.context, commit: { commits += 1; try $0.save() }
        )

        #expect(outcome == .settled)
        #expect(commits == 0)
        #expect(f.subject.order == 0)
    }

    @Test func aRefusedSelectionMoveIsReportedAndUndone() throws {
        let f = try makeFixture()

        let outcome = MacTaskRowContextMenu.moveToList(
            f.subject, selection: .inbox, areas: [f.area], projects: [f.project],
            modelContext: f.context, commit: { _ in throw CommitRefused() }
        )

        #expect(outcome == .refused(.move))
        #expect(f.subject.area?.id == f.area.id)
        #expect(f.subject.order == 0)
    }

    /// Dropping a task on another list's group goes through the same `assignContainer`, inside the
    /// drop's one commit: end of the new list, and a section that list actually has.
    @Test func aListDropPutsTheTaskAtTheEndOfTheNewListInASectionItHas() throws {
        let f = try makeFixture()
        f.subject.sectionName = "Now" // the area has it; the project does not
        let resident = AppTask(title: "Resident")
        resident.project = f.project
        resident.order = 5
        f.context.insert(resident)
        try f.context.save()

        let outcome = TasksPanelSupport.assignTask(
            f.subject, for: "list:p_\(f.project.id.uuidString)", todayKey: "2026-10-23",
            areas: [f.area], projects: [f.project], modelContext: f.context
        )

        #expect(outcome == .applied)
        let committed = try #require(try f.committed(f.subject))
        #expect(committed.project?.id == f.project.id)
        #expect(committed.area == nil)
        #expect(committed.order > resident.order, "the dropped task kept its old list's order")
        #expect(committed.sectionName != "Now")
        #expect(f.project.sectionNames.contains(committed.sectionName), "the dropped task kept a section its new list lacks")
    }

    /// The row's binding is SwiftUI and cannot be driven from a unit test, so this is the hop read
    /// from source: it hands the selection to the menu's path and writes no relationship itself.
    /// The inspector has no such binding since T-4108; its move is pinned by value below.
    @Test func theRowsListChipRoutesThroughTheMenusMove() throws {
        let path = "Cadence/macOS/Views/TasksPanelComponents.swift"
        let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
        let body = try #require(
            CadenceSourceScan.declarationBody("private var taskContainerBinding: Binding<TaskContainerSelection>", in: code),
            "taskContainerBinding not found in \(path)"
        )
        #expect(CadenceSourceScan.matchCount(#"MacTaskRowContextMenu\.moveToList\("#, in: body) == 1)
        #expect(CadenceSourceScan.matchCount(#"task\.(area|project|context|sectionName|order)\s*="#, in: body) == 0)
    }

    /// T-5353's third picker, the inspector's breadcrumb and `~` field. Since T-4108 the inspector
    /// edits a `CadenceScheduleDraft` and saves through `CadenceTaskEditDraftCommit`, so the move it
    /// makes is that commit's: end of the new list, in one commit, like the menu's.
    @Test func theInspectorsDraftSavePutsAMovedTaskAtTheEndOfTheNewList() throws {
        let f = try makeFixture()
        let resident = AppTask(title: "Resident")
        resident.project = f.project
        resident.order = 5
        f.context.insert(resident)
        try f.context.save()
        let opened = CadenceScheduleDraft(editing: f.subject)
        var draft = opened
        draft.listToken = CadenceTaskComposerSupport.token(for: .project(f.project.id))
        var commits = 0

        let landed = CadenceTaskEditDraftCommit.save(
            draft, opened: opened, to: f.subject, area: nil, project: f.project,
            allTasks: [f.subject, resident], scope: .thisTask, in: f.context, reconciler: .inert,
            commit: { commits += 1; try $0.save() }
        )

        #expect(landed)
        #expect(commits == 1)
        let committed = try #require(try f.committed(f.subject))
        #expect(committed.project?.id == f.project.id)
        #expect(committed.area == nil)
        #expect(committed.order > resident.order, "the inspector's move kept the old list's order")
    }

    // MARK: - Move Section

    @Test func moveSectionCommitsTheRowsTaskIntoTheChosenSectionOfItsOwnList() throws {
        let f = try makeFixture()

        let outcome = MacTaskRowContextMenu.moveSection("Now", task: f.subject, modelContext: f.context)

        #expect(outcome == .settled)
        let committed = try #require(try f.committed(f.subject))
        #expect(committed.sectionName == "Now")
        #expect(committed.area?.id == f.area.id && committed.project == nil, "a section move never changes list")
        #expect(committed.order == 0, "a section move does not re-place the task at a list's tail")
        let sibling = try #require(try f.committed(f.sibling))
        #expect(sibling.sectionName == "Now" && sibling.order == 1, "the sibling is untouched")
    }

    /// The menu offers the row's own section even when its list no longer has it
    /// (`availableSectionNames` appends it), so choosing it must leave the task there. The
    /// container helper normalises to a section the list HAS — "Now" — which is how a reroute of
    /// Move Section onto it shows: on a task whose list is unchanged, it is otherwise identical.
    @Test func moveSectionKeepsASectionTheListNoLongerNames() throws {
        let f = try makeFixture()
        f.subject.sectionName = "Retired"
        try f.context.save()

        let outcome = MacTaskRowContextMenu.moveSection("Retired", task: f.subject, modelContext: f.context)

        #expect(outcome == .settled)
        #expect(try #require(try f.committed(f.subject)).sectionName == "Retired")
    }

    // MARK: - Repeat

    @Test func repeatOnAOneOffTaskCommitsTheRuleOnTheRowsTask() throws {
        let f = try makeFixture()
        var commits = 0

        let outcome = MacTaskRowContextMenu.selectRecurrenceRule(
            .daily, for: f.subject, allTasks: f.allTasks, modelContext: f.context,
            commit: { commits += 1; try $0.save() }
        )

        #expect(outcome == .settled)
        #expect(commits == 1, "the rule committed through the caller's commit:")
        #expect(try #require(try f.committed(f.subject)).recurrenceRule == .daily)
        #expect(try #require(try f.committed(f.sibling)).recurrenceRule == TaskRecurrenceRule.none, "the sibling did not start repeating")
    }

    @Test func aRefusedRepeatIsReportedAndUndone() throws {
        let f = try makeFixture()

        let outcome = MacTaskRowContextMenu.selectRecurrenceRule(
            .weekly, for: f.subject, allTasks: f.allTasks, modelContext: f.context,
            commit: { _ in throw CommitRefused() }
        )

        #expect(outcome == .refused(.recurrence(CadenceTaskFieldEditCommit.saveFailureNotice)))
        #expect(f.subject.recurrenceRule == TaskRecurrenceRule.none, "the rule is rolled back")
    }

    @Test func repeatOnASeriesMemberWaitsForTheScopeAndWritesNothing() throws {
        let f = try makeFixture()
        f.subject.recurrenceRule = .weekly
        try f.context.save()
        var commits = 0

        let outcome = MacTaskRowContextMenu.selectRecurrenceRule(
            .daily, for: f.subject, allTasks: f.allTasks, modelContext: f.context,
            commit: { commits += 1; try $0.save() }
        )

        #expect(outcome == .needsRecurrenceScope(.daily))
        #expect(commits == 0)
        #expect(f.subject.recurrenceRule == .weekly)
    }

    @Test func choosingTheRuleAlreadySetWritesNothing() throws {
        let f = try makeFixture()
        var commits = 0

        let outcome = MacTaskRowContextMenu.selectRecurrenceRule(
            .none, for: f.subject, allTasks: f.allTasks, modelContext: f.context,
            commit: { _ in commits += 1 }
        )

        #expect(outcome == .settled)
        #expect(commits == 0)
    }

    // MARK: - The series writer behind both Mac scope dialogs ([[T-9122]])

    /// A three-occurrence series: `first` spawned `second`, which spawned `third`.
    private func series(in context: ModelContext) throws -> [AppTask] {
        let seriesID = UUID()
        let tasks = (0..<3).map { index -> AppTask in
            let task = AppTask(title: "Occurrence \(index)")
            task.recurrenceRule = .daily
            task.recurrenceSeriesIDRaw = seriesID.uuidString
            task.recurrenceOccurrenceIndex = index
            task.scheduledDate = "2026-05-0\(index + 1)"
            context.insert(task)
            return task
        }
        tasks[0].recurrenceSpawnedTaskID = tasks[1].id
        tasks[1].recurrenceSpawnedTaskID = tasks[2].id
        try context.save()
        return tasks
    }

    /// "This and future" fetches the series itself and commits the rule on every occurrence it
    /// reaches -- read back through a second context, so it is the store, not the pending edit.
    @Test func theScopeWriterCommitsThisAndFutureOnEveryLaterOccurrence() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let tasks = try series(in: context)
        var commits = 0

        let outcome = MacTaskRowContextMenu.applyRecurrenceRule(
            .weekly, scope: .thisAndFuture, for: tasks[0], modelContext: context,
            commit: { commits += 1; try $0.save() }
        )

        #expect(outcome == .settled)
        #expect(commits == 1)
        let stored = try ModelContext(container).fetch(FetchDescriptor<AppTask>())
        #expect(stored.count == 3)
        #expect(stored.allSatisfy { $0.recurrenceRule == .weekly }, "a later occurrence kept the old rule")
    }

    /// "This one" writes only the occurrence it was asked about.
    @Test func theScopeWriterLeavesLaterOccurrencesAloneForThisTask() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let tasks = try series(in: context)

        let outcome = MacTaskRowContextMenu.applyRecurrenceRule(
            .weekly, scope: .thisTask, for: tasks[1], modelContext: context
        )

        #expect(outcome == .settled)
        #expect(tasks[1].recurrenceRule == .weekly)
        #expect(tasks[2].recurrenceRule == .daily, "a this-task edit reached a later occurrence")
    }

    /// A refused series edit is named, and puts back every occurrence it wrote -- not only the one
    /// the dialog was raised from.
    @Test func aRefusedScopeWriteIsReportedAndUndoneAcrossTheSeries() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let tasks = try series(in: context)

        let outcome = MacTaskRowContextMenu.applyRecurrenceRule(
            .weekly, scope: .thisAndFuture, for: tasks[0], modelContext: context,
            commit: { _ in throw CommitRefused() }
        )

        #expect(outcome == .refused(.recurrence(CadencePendingChangePersistence.editFailureNotice)))
        #expect(tasks.allSatisfy { $0.recurrenceRule == .daily }, "a refused series edit left an occurrence rewritten")
    }

    // MARK: - The last hop: each menu item calls its own action

    /// The effect tests above hold the actions; this holds that each submenu's buttons reach the
    /// right one of them. A unit test cannot press a SwiftUI menu item, so this is the one hop
    /// still read from source — and it reads each submenu separately, so a swap between two of
    /// them goes red here even though both names still appear somewhere in the file.
    @Test func eachSubmenuRoutesToItsOwnAction() throws {
        let code = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/MacTaskRowContextMenu.swift")
        )
        let actions = ["duplicate", "moveToList", "moveSection", "selectRecurrenceRule"]
        func calls(in declaration: String) throws -> [String: Int] {
            let body = try #require(CadenceSourceScan.declarationBody(declaration, in: code), "\(declaration) not found")
            return Dictionary(uniqueKeysWithValues: actions.map { ($0, CadenceSourceScan.matchCount(#"settle\(Self\."# + $0 + #"\("#, in: body)) })
        }

        #expect(try calls(in: "private var sectionMenu: some View") == ["duplicate": 0, "moveToList": 0, "moveSection": 1, "selectRecurrenceRule": 0])
        #expect(try calls(in: "private var moveToListMenu: some View") == ["duplicate": 0, "moveToList": 3, "moveSection": 0, "selectRecurrenceRule": 0])
        #expect(try calls(in: "private var recurrenceMenu: some View") == ["duplicate": 0, "moveToList": 0, "moveSection": 0, "selectRecurrenceRule": 1])
        // The top-level body holds Duplicate; the submenus are separate declarations it names.
        #expect(try calls(in: "var body: some View") == ["duplicate": 1, "moveToList": 0, "moveSection": 0, "selectRecurrenceRule": 0])

        // Each Move to List button passes its OWN destination, in the order the menu lists them.
        let moveBody = try #require(CadenceSourceScan.declarationBody("private var moveToListMenu: some View", in: code))
        let destinations = CadenceSourceScan.captures(#"Self\.moveToList\(task, (area: \w+, project: \w+)"#, in: moveBody).map(\.text)
        #expect(destinations == ["area: nil, project: nil", "area: area, project: nil", "area: nil, project: project"])
        // And every action is handed the row's own task, not some other one in scope.
        #expect(CadenceSourceScan.matchCount(#"settle\(Self\.\w+\((?:\w+, )?(?:task: |for: )?task[,)]"#, in: code) == 6)
    }
}

#endif
