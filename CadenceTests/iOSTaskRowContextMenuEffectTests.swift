import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Cadence

// [[T-3210]]'s iOS half — the phone's task-row menu, held by what it DOES.
//
// The Mac half landed in `45673bc2`. The iOS half could not follow it: `CadenceTests` built for
// macOS alone, so every declaration inside `Cadence/iOS/`'s one big `#if os(iOS)` block was not
// merely untested but absent from the module under test, and the four actions were pinned by the
// menu body NAMING `CadenceTaskMutationSupport.*`. [[T-3244]] made this target compile and run
// against an iOS destination; `iOSTaskRecurrenceSelectionEffectTests` was the first suite to use
// it. This one is the four menu actions.
//
// What a naming pin cannot see, and each of these does: a swapped task, a dropped `sectionName:`,
// a Move Section rerouted onto the container helper, a `commit:` thrown away, a series member's
// rule rewritten before the user has chosen a scope. Every fixture carries a sibling task the
// action must NOT touch, and every read-back goes through a SECOND `ModelContext` on the same
// store, so only committed state counts.
#if os(iOS)

@Suite @MainActor
struct iOSTaskRowContextMenuEffectTests {
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
            return try ModelContext(container)
                .fetch(FetchDescriptor<AppTask>(predicate: #Predicate { $0.id == id }))
                .first
        }

        func committedTasks() throws -> [AppTask] {
            try ModelContext(container).fetch(FetchDescriptor<AppTask>(sortBy: [SortDescriptor(\.order)]))
        }
    }

    private func makeFixture() throws -> Fixture {
        let container = try CadenceTestStore.container()
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
        return Fixture(
            container: container,
            context: context,
            area: area,
            project: project,
            subject: subject,
            sibling: sibling
        )
    }

    // MARK: - Duplicate

    /// The copy is of the ROW's task, carries its list and its section, and is committed.
    ///
    /// `iOSTaskRowContextMenu.duplicate` swallows the refusal (`_ = try?`), which the save rule
    /// permits because the shared helper commits through `commitInsert` — so "it committed" is a
    /// statement about the store, and only a second context can make it.
    @Test func duplicateCommitsACopyOfTheRowsTaskInItsOwnListOnIOS() throws {
        let f = try makeFixture()

        iOSTaskRowContextMenu.duplicate(f.subject, allTasks: f.allTasks, modelContext: f.context)

        let committed = try f.committedTasks()
        #expect(committed.count == 3, "exactly one task inserted and committed, read \(committed.count)")
        let copy = try #require(committed.first { $0.id != f.subject.id && $0.id != f.sibling.id })
        #expect(copy.title == "Subject", "the copy is of the row's task, not its sibling")
        #expect(copy.priority == .high)
        #expect(copy.area?.id == f.area.id)
        #expect(copy.sectionName == "Later")
        // The original and its sibling are left as they were.
        #expect(f.subject.area?.id == f.area.id && f.subject.sectionName == "Later")
        #expect(f.sibling.title == "Sibling" && f.sibling.sectionName == "Now")
    }

    // MARK: - Move to List

    @Test func moveToListCommitsTheRowsTaskIntoTheChosenListKeepingItsSectionOnIOS() throws {
        let f = try makeFixture()
        var commits = 0

        let landed = iOSTaskRowContextMenu.moveToList(
            f.subject,
            area: nil,
            project: f.project,
            allTasks: f.allTasks,
            modelContext: f.context,
            commit: { commits += 1; try $0.save() }
        )

        #expect(landed, "the move was reported as refused")
        #expect(commits == 1, "the move committed through the caller's commit:")
        let committed = try #require(try f.committed(f.subject))
        #expect(committed.project?.id == f.project.id)
        #expect(committed.area == nil)
        // The row's own section is carried, not the helper's default: "Later" exists in the
        // project, and a dropped `sectionName:` would normalise to its first section, "Plan".
        #expect(committed.sectionName == "Later")
        let sibling = try #require(try f.committed(f.sibling))
        #expect(sibling.area?.id == f.area.id && sibling.project == nil, "the sibling did not move")
    }

    @Test func moveToInboxClearsBothContainersOnIOS() throws {
        let f = try makeFixture()

        let landed = iOSTaskRowContextMenu.moveToList(
            f.subject,
            area: nil,
            project: nil,
            allTasks: f.allTasks,
            modelContext: f.context
        )

        #expect(landed)
        let committed = try #require(try f.committed(f.subject))
        #expect(committed.area == nil && committed.project == nil)
        #expect(try #require(try f.committed(f.sibling)).area?.id == f.area.id)
    }

    /// The refusal the row's `moveFailed` alert exists for: `false`, and the task back where it
    /// was. This is the one of the four a test can make refuse — the other three shared helpers
    /// take no `commit:` to inject.
    @Test func aRefusedMoveToListIsReportedAndUndoneOnIOS() throws {
        let f = try makeFixture()

        let landed = iOSTaskRowContextMenu.moveToList(
            f.subject,
            area: nil,
            project: f.project,
            allTasks: f.allTasks,
            modelContext: f.context,
            commit: { _ in throw CommitRefused() }
        )

        #expect(landed == false, "a refused move answered the menu as if it had landed")
        #expect(f.subject.area?.id == f.area.id && f.subject.project == nil, "the task is back where it was")
        #expect(f.subject.sectionName == "Later")
    }

    // MARK: - Move Section

    @Test func moveSectionCommitsTheRowsTaskIntoTheChosenSectionOfItsOwnListOnIOS() throws {
        let f = try makeFixture()

        iOSTaskRowContextMenu.moveSection("Now", task: f.subject, modelContext: f.context)

        let committed = try #require(try f.committed(f.subject))
        #expect(committed.sectionName == "Now")
        #expect(committed.area?.id == f.area.id && committed.project == nil, "a section move never changes list")
        #expect(committed.order == 0, "a section move does not re-place the task at a list's tail")
        let sibling = try #require(try f.committed(f.sibling))
        #expect(sibling.sectionName == "Now" && sibling.order == 1, "the sibling is untouched")
    }

    /// The menu offers the row's own section even when its list no longer names it
    /// (`availableSectionNames` appends it), so choosing it must leave the task there. The
    /// container helper normalises to a section the list HAS — "Now" — which is how a reroute of
    /// Move Section onto it shows: on a task whose list is unchanged it is otherwise identical.
    @Test func moveSectionKeepsASectionTheListNoLongerNamesOnIOS() throws {
        let f = try makeFixture()
        f.subject.sectionName = "Retired"
        try f.context.save()

        iOSTaskRowContextMenu.moveSection("Retired", task: f.subject, modelContext: f.context)

        #expect(try #require(try f.committed(f.subject)).sectionName == "Retired")
    }

    // MARK: - Repeat

    @Test func repeatOnAOneOffTaskCommitsTheRuleOnTheRowsTaskOnIOS() throws {
        let f = try makeFixture()
        var parked: TaskRecurrenceRule?

        let landed = iOSTaskRowContextMenu.selectRecurrenceRule(
            .daily,
            for: f.subject,
            allTasks: f.allTasks,
            modelContext: f.context,
            pendingRecurrenceRule: Binding(get: { parked }, set: { parked = $0 })
        )

        #expect(landed, "the menu was told the store refused an edit it took")
        #expect(parked == nil, "a one-off task armed the scope dialog it has no series for")
        #expect(try #require(try f.committed(f.subject)).recurrenceRule == .daily)
        #expect(
            try #require(try f.committed(f.sibling)).recurrenceRule == TaskRecurrenceRule.none,
            "the sibling started repeating"
        )
    }

    /// The branch a source scan is blindest to: a series member's rule is PARKED for the scope
    /// dialog and the store is left exactly as it was found.
    @Test func repeatOnASeriesMemberParksTheRuleAndWritesNothing() throws {
        let f = try makeFixture()
        f.subject.recurrenceRule = .weekly
        try f.context.save()
        #expect(f.subject.isRecurrenceSeriesMember, "fixture is not the series case this test is about")
        var parked: TaskRecurrenceRule?

        let landed = iOSTaskRowContextMenu.selectRecurrenceRule(
            .daily,
            for: f.subject,
            allTasks: f.allTasks,
            modelContext: f.context,
            pendingRecurrenceRule: Binding(get: { parked }, set: { parked = $0 })
        )

        #expect(landed, "the menu stayed open over an edit that was deferred, not refused")
        #expect(parked == .daily, "the scope dialog was never armed with the chosen rule")
        #expect(
            try #require(try f.committed(f.subject)).recurrenceRule == .weekly,
            "a series member's rule was rewritten before the user chose a scope"
        )
        #expect(f.context.hasChanges == false, "the series branch wrote to the store")
    }

    @Test func choosingTheRuleAlreadySetWritesNothingOnIOS() throws {
        let f = try makeFixture()
        var parked: TaskRecurrenceRule?

        let landed = iOSTaskRowContextMenu.selectRecurrenceRule(
            .none,
            for: f.subject,
            allTasks: f.allTasks,
            modelContext: f.context,
            pendingRecurrenceRule: Binding(get: { parked }, set: { parked = $0 })
        )

        #expect(landed)
        #expect(parked == nil)
        #expect(f.context.hasChanges == false, "an unchanged rule wrote to the store")
    }
}

#endif

// MARK: - The last hop, read from source

/// The effect suite above holds the four actions; this holds that each submenu's buttons reach the
/// right one of them, and that the two row-side wrappers hand their answer to the right flag. A
/// unit test cannot press a SwiftUI menu item, so this hop is still a source scan — read on the
/// macOS leg, where every other scan of this file already lives, because the file being READ is
/// the same on both platforms while a simulator's access to the repository's own sources is not.
#if os(macOS)

@MainActor
struct iOSTaskRowContextMenuRoutingTests {
    private static let path = "Cadence/iOS/iOSTaskRowActionViews.swift"

    private func code() throws -> String {
        let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(Self.path))
        #expect(code.contains("struct iOSTaskRowContextMenu: View"), "non-vacuity: wrong file read")
        return code
    }

    /// The menu struct alone. **This file holds six views**, so `var body: some View` is not a
    /// unique landmark in it -- a lookup over the whole file finds the first row's body and reads
    /// a declaration this test is not about. Every lookup below is scoped to the menu first.
    private func menu() throws -> String {
        try #require(CadenceSourceScan.declarationBody("struct iOSTaskRowContextMenu: View", in: try code()))
    }

    /// Each submenu is read separately, so a swap between two of them goes red here even though
    /// both names still appear somewhere in the file.
    @Test func eachSubmenuRoutesToItsOwnActionOnIOS() throws {
        let menu = try menu()
        let routes = ["Self.duplicate(", "moveToContainer(area:", "Self.moveSection(", "settleRecurrenceSelection("]
        func calls(in declaration: String) throws -> [String: Int] {
            let body = try #require(CadenceSourceScan.declarationBody(declaration, in: menu), "\(declaration) not found")
            return Dictionary(uniqueKeysWithValues: routes.map { ($0, body.components(separatedBy: $0).count - 1) })
        }

        #expect(try calls(in: "private var sectionMenu: some View") == [
            "Self.duplicate(": 0, "moveToContainer(area:": 0, "Self.moveSection(": 1, "settleRecurrenceSelection(": 0
        ])
        #expect(try calls(in: "private var moveToListMenu: some View") == [
            "Self.duplicate(": 0, "moveToContainer(area:": 3, "Self.moveSection(": 0, "settleRecurrenceSelection(": 0
        ])
        #expect(try calls(in: "private var recurrenceMenu: some View") == [
            "Self.duplicate(": 0, "moveToContainer(area:": 0, "Self.moveSection(": 0, "settleRecurrenceSelection(": 1
        ])
        // The top-level body holds Duplicate; the submenus are separate declarations it names.
        #expect(try calls(in: "var body: some View") == [
            "Self.duplicate(": 1, "moveToContainer(area:": 0, "Self.moveSection(": 0, "settleRecurrenceSelection(": 0
        ])
    }

    /// Each Move to List button passes its OWN destination, in the order the menu lists them.
    @Test func eachMoveToListButtonPassesItsOwnDestination() throws {
        let body = try #require(CadenceSourceScan.declarationBody("private var moveToListMenu: some View", in: try menu()))
        let destinations = CadenceSourceScan.captures(#"moveToContainer\((area: \w+, project: \w+)\)"#, in: body).map(\.text)
        #expect(destinations == ["area: nil, project: nil", "area: area, project: nil", "area: nil, project: project"])
    }

    /// The two row-side wrappers: each calls its own action and sets its own flag. `moveFailed` is
    /// raised above the line that clears it, which is what `CadenceInPlaceEditFlushCommitTests`
    /// has measured on this menu since T-702; what is new is that the call it guards on is now a
    /// `static` the effect suite invokes.
    @Test func eachRowSideWrapperHandsItsOwnAnswerToItsOwnFlag() throws {
        let code = try menu()

        let move = try #require(CadenceSourceScan.declarationBody("private func moveToContainer(area: Area?, project: Project?)", in: code))
        #expect(move.contains("guard Self.moveToList("), "the menu's move no longer routes through the invokable action")
        #expect(move.contains("moveFailed = true") && move.contains("moveFailed = false"))
        #expect(!move.contains("recurrenceFailed"), "the move wrapper writes the recurrence flag")

        let repeatWrapper = try #require(CadenceSourceScan.declarationBody("private func settleRecurrenceSelection(_ rule: TaskRecurrenceRule)", in: code))
        #expect(repeatWrapper.contains("Self.selectRecurrenceRule("), "the repeat submenu no longer routes through the invokable action")
        #expect(repeatWrapper.contains("recurrenceFailed = !landed"))
        #expect(!repeatWrapper.contains("moveFailed"), "the repeat wrapper writes the move flag")
    }

    /// And every action is handed the ROW's own task, not another one in scope.
    @Test func everyActionIsHandedTheRowsOwnTask() throws {
        let menu = try menu()
        for pattern in [
            #"Self\.duplicate\(\s*task,"#,
            #"Self\.moveSection\(\s*section, task: task,"#,
            #"Self\.moveToList\(\s*task,"#,
            #"Self\.selectRecurrenceRule\(\s*rule,\s*for: task,"#,
        ] {
            #expect(
                CadenceSourceScan.matchCount(pattern, in: menu) == 1,
                "no action call matches \(pattern)"
            )
        }
    }
}

#endif
