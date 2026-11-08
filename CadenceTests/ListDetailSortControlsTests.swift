import Foundation
import SwiftUI
import Testing
@testable import Cadence

/// **[[T-13561]], [[T-13562]] — a list's Sort / Order / Group, and its board's Sort / Order, are the
/// Mac's per-list controls on iPhone and iPad too.**
///
/// The rules live in `ListDetailSortControls` (`Shared/`) so they run here: `Cadence/iOS/` is
/// invisible to this target. Every store is a throwaway suite, never the app group.
@MainActor
struct ListDetailSortControlsTests {

    // MARK: Keys

    /// The Mac's own key shapes, so a list sorted on one platform's build reads the same keys the
    /// other platform's list page writes.
    @Test func theKeysAreTheMacListPagesKeys() {
        let id = UUID()
        #expect(ListDetailSortControls.tasksKeyPrefix(areaID: id, projectID: nil) == "list_\(id.uuidString)")
        #expect(ListDetailSortControls.tasksKeyPrefix(areaID: nil, projectID: id) == "list_\(id.uuidString)")
        #expect(ListDetailSortControls.kanbanKeyPrefix(areaID: id, projectID: nil) == "kanban_\(id.uuidString)")
        #expect(ListDetailSortControls.tasksKeyPrefix(areaID: nil, projectID: nil) == "list_generic")
        #expect(ListDetailSortControls.kanbanKeyPrefix(areaID: nil, projectID: nil) == "kanban_generic")
        #expect(ListDetailSortControls.sortFieldKey("list_x") == "list_x_sortField")
        #expect(ListDetailSortControls.sortDirectionKey("list_x") == "list_x_sortDir")
        #expect(ListDetailSortControls.groupingKey("list_x") == "list_x_grouping")
    }

    // MARK: Defaults, per-list persistence, fallback

    @Test func aListNeverSortedOpensCustomAscendingByDate() throws {
        try withTemporaryDefaults("cadence.tests.listsort") { store in
            let tasks = ListDetailSortControls.tasks(prefix: "list_a", in: store)
            #expect(tasks == ListDetailSortControls.Tasks(sortField: .custom, sortDirection: .ascending, grouping: .byDate))
            let board = ListDetailSortControls.kanban(prefix: "kanban_a", in: store)
            #expect(board == ListDetailSortControls.Kanban(sortField: .custom, sortDirection: .ascending))
        }
    }

    /// Each list keeps its own, and the Tasks tab and the board keep theirs apart — the board no
    /// longer takes the Tasks tab's sort.
    @Test func eachListAndEachTabRemembersItsOwnControls() throws {
        try withTemporaryDefaults("cadence.tests.listsort") { store in
            let a = ListDetailSortControls.Tasks(sortField: .dueDate, sortDirection: .descending, grouping: .byList)
            ListDetailSortControls.save(a, prefix: "list_a", in: store)
            let boardA = ListDetailSortControls.Kanban(sortField: .priority, sortDirection: .ascending)
            ListDetailSortControls.save(boardA, prefix: "kanban_a", in: store)

            #expect(ListDetailSortControls.tasks(prefix: "list_a", in: store) == a)
            #expect(ListDetailSortControls.kanban(prefix: "kanban_a", in: store) == boardA)
            #expect(ListDetailSortControls.tasks(prefix: "list_b", in: store) == ListDetailSortControls.defaultTasks)
            #expect(ListDetailSortControls.kanban(prefix: "kanban_b", in: store) == ListDetailSortControls.defaultKanban)
            // Written under the Mac's raw values, which the Mac's `restoreTaskAndKanbanControls` decodes.
            #expect(store.string(forKey: "list_a_sortField") == "Due Date")
            #expect(store.string(forKey: "list_a_sortDir") == "Descending")
            #expect(store.string(forKey: "list_a_grouping") == "By List")
            #expect(store.string(forKey: "kanban_a_sortField") == "Priority")
        }
    }

    /// The retired app-wide phone sort is honoured for a list this device has never sorted, through
    /// `macOSSortPair`; once the list has its own keys they win. Group takes the Mac default.
    @Test func theRetiredPhoneSortSeedsOnlyAnUnsortedList() throws {
        try withTemporaryDefaults("cadence.tests.listsort") { store in
            let seeded = ListDetailSortControls.tasks(prefix: "list_a", in: store, legacyMode: .priority)
            #expect(seeded == ListDetailSortControls.Tasks(sortField: .priority, sortDirection: .descending, grouping: .byDate))

            ListDetailSortControls.save(
                ListDetailSortControls.Tasks(sortField: .newest, sortDirection: .ascending, grouping: .none),
                prefix: "list_a",
                in: store
            )
            let own = ListDetailSortControls.tasks(prefix: "list_a", in: store, legacyMode: .priority)
            #expect(own == ListDetailSortControls.Tasks(sortField: .newest, sortDirection: .ascending, grouping: .none))
        }
    }

    /// A value this build cannot decode falls back for that one control, not to another field.
    @Test func anUndecodableValueFallsBackPerControl() throws {
        try withTemporaryDefaults("cadence.tests.listsort") { store in
            store.set("Start Date", forKey: "list_a_sortField")
            store.set("Descending", forKey: "list_a_sortDir")
            store.set("By Mood", forKey: "list_a_grouping")
            let tasks = ListDetailSortControls.tasks(prefix: "list_a", in: store)
            #expect(tasks.sortField == .custom)
            #expect(tasks.sortDirection == .descending)
            #expect(tasks.grouping == .byDate)
        }
    }

    /// The iPad sidebar swaps lists under one live page: a pick made on list A is not list B's.
    @Test func aPickMadeOnAnotherListIsNotThisListsControls() {
        let pick = ListDetailSortControls.Kanban(sortField: .priority, sortDirection: .descending)
        let stored = ListDetailSortControls.defaultKanban
        #expect(ListDetailSortControls.displayed(choice: pick, choiceListKey: "kanban_a", listKey: "kanban_a") { stored } == pick)
        #expect(ListDetailSortControls.displayed(choice: pick, choiceListKey: "kanban_a", listKey: "kanban_b") { stored } == stored)
        #expect(ListDetailSortControls.displayed(choice: nil, choiceListKey: nil, listKey: "kanban_a") { stored } == stored)
    }

    // MARK: What the controls do

    private func task(_ title: String, priority: TaskPriority = .none, section: String = TaskSectionDefaults.defaultName, order: Int = 0) -> AppTask {
        let task = AppTask(title: title)
        task.priority = priority
        task.sectionName = section
        task.order = order
        return task
    }

    /// The board's cards come out in the board's own Sort + Order, open cards only.
    @Test func sortedOpenTasksUsesTheMacComparatorOverTheOpenHalf() {
        let low = task("low", priority: .low, order: 0)
        let high = task("high", priority: .high, order: 1)
        let done = task("done", priority: .high, order: 2)
        done.status = .done
        let all = [low, high, done]

        let byPriorityDesc = ListDetailSortControls.sortedOpenTasks(all, sortField: .priority, sortDirection: .descending)
        #expect(byPriorityDesc.map(\.title) == ["high", "low"])
        let byPriorityAsc = ListDetailSortControls.sortedOpenTasks(all, sortField: .priority, sortDirection: .ascending)
        #expect(byPriorityAsc.map(\.title) == ["low", "high"])
        #expect(byPriorityDesc.map(\.title) == all.filter { !$0.isDone }.taskSorted(by: .priority, direction: .descending).map(\.title))
    }

    /// Each Group choice is the Mac list tab's arm: sections (tinted), priority buckets, date
    /// buckets, or one "Tasks" group.
    @Test func eachGroupingIsTheMacListTabsArm() {
        let configs = [
            TaskSectionConfig(name: TaskSectionDefaults.defaultName),
            TaskSectionConfig(name: "Review", colorHex: "#FF3366"),
        ]
        let names = configs.map(\.name)
        let a = task("a", priority: .high, section: "Review")
        let b = task("b", priority: .low)
        let open = [a, b]

        let bySection = ListDetailSortControls.taskGroups(
            from: open, grouping: .byList, sectionNames: names, sectionConfigs: configs, pageIsEmpty: false, todayKey: "2026-11-08"
        )
        #expect(bySection.map(\.title) == [TaskSectionDefaults.defaultName, "Review"])
        #expect(bySection.last?.tasks.map(\.title) == ["a"])
        #expect(bySection.last?.accent == Color(hex: "#FF3366"))

        let byPriority = ListDetailSortControls.taskGroups(
            from: open, grouping: .byPriority, sectionNames: names, sectionConfigs: configs, pageIsEmpty: false, todayKey: "2026-11-08"
        )
        #expect(byPriority.map(\.id) == CadenceTaskQuerySupport.priorityDisplayGroups(from: open).map(\.id))
        #expect(byPriority.count == 2)

        let byDate = ListDetailSortControls.taskGroups(
            from: open, grouping: .byDate, sectionNames: names, sectionConfigs: configs, pageIsEmpty: false, todayKey: "2026-11-08"
        )
        #expect(byDate.map(\.id) == CadenceTaskQuerySupport.dateDisplayGroups(from: open, todayKey: "2026-11-08").map(\.id))
        #expect(!byDate.map(\.title).contains("Review"), "By Date drew sections")

        let none = ListDetailSortControls.taskGroups(
            from: open, grouping: .none, sectionNames: names, sectionConfigs: configs, pageIsEmpty: false, todayKey: "2026-11-08"
        )
        #expect(none.map(\.title) == ["Tasks"])
        #expect(none.first?.tasks.count == 2)
    }

    /// "By Section" on a list's tab, "By List" everywhere else, on both platforms.
    @Test func theListTabCallsByListBySection() {
        #expect(ListTasksGroupingLabel.label(for: .byList) == "By Section")
        #expect(ListTasksGroupingLabel.label(for: .byDate) == nil)
    }

    // MARK: Call sites

    /// Both list pages read the shared keys and defaults, and iOS draws the Mac's controls on both
    /// tabs. Source pins: the call sites are `private` members of SwiftUI views.
    @Test func bothListPagesReadTheSharedControls() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let mac = try read("Cadence/macOS/Views/ListDetailView.swift")
        #expect(mac.contains("ListDetailSortControls.kanban(prefix: kanbanUDKey, in: ud)"))
        #expect(mac.contains("ListDetailSortControls.tasks(prefix: taskUDKeyPrefix, in: ud)"))

        let iOS = try read("Cadence/iOS/iOSListDetailView.swift")
        let column = try #require(CadenceSourceScan.declarationBody("private var taskColumn: some View", in: iOS))
        #expect(column.contains("iOSTaskSortGroupBar("))
        #expect(column.contains("groupingLabel: ListTasksGroupingLabel.label(for:)"))
        #expect(!iOS.contains("iOSTaskViewOptionsBar("), "the list tab went back to the one chip")
        #expect(!iOS.contains("@AppStorage(CadencePreferenceKeys.iosListDetailSortMode)"), "the list tab reads the app-wide sort again")

        let board = try #require(CadenceSourceScan.declarationBody("private var kanbanPage: some View", in: iOS))
        #expect(board.contains("selection: kanbanControl(\\.sortField)"))
        #expect(board.contains("if kanbanControls.sortField.honorsDirection {"))
        #expect(board.contains("tasks: kanbanTasks,"), "the board takes the Tasks tab's sort again")
        let cards = try #require(CadenceSourceScan.declarationBody("private var kanbanTasks: [AppTask]", in: iOS))
        #expect(cards.contains("let controls = kanbanControls"), "the board's cards are sorted by the Tasks tab's controls")
        #expect(cards.contains("ListDetailSortControls.sortedOpenTasks("))
    }
}
