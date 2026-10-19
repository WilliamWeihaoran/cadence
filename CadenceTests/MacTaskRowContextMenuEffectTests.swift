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
