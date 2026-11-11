import Foundation
import SwiftUI

/// **[[T-5833]] — on a list's own Tasks tab, `.byList` is "By Section".** `TaskGroupingMode` says
/// "By List", which is right on Today and All Tasks, where it groups by list; on one list's page it
/// groups that list's tasks by section (`CadenceTaskQuerySupport.listSectionGroups`), beside the
/// page's own "+ Section" row and the row menu's "Move Section". Only the label changes here — the
/// stored grouping key and every other page keep "By List".
///
/// In `Shared/` since [[T-13561]]: the iPhone and iPad list tab draws the same Group chip and has
/// to call the same case the same thing.
enum ListTasksGroupingLabel {
    /// `nonisolated`: the badge's `labelOverride` is a plain, non-isolated closure.
    nonisolated static func label(for mode: TaskGroupingMode) -> String? {
        mode == .byList ? "By Section" : nil
    }
}

/// **A list page's own Sort / Order / Group, remembered per list, on both platforms**
/// ([[T-13561]], [[T-13562]]).
///
/// The Mac's list page has always kept three controls on its Tasks tab and two on its Kanban tab,
/// each list remembering its own under a `list_<uuid>` key per control and a `kanban_<uuid>` key
/// per board control. iOS drew one app-wide Sort chip and no board sort at
/// all, so the same list opened grouped By Date on the Mac and by section on the phone. The keys,
/// the defaults and the decoding live here so both platforms read one answer.
///
/// A key holding a value this build cannot decode falls back to the default for that one control,
/// never to another field — the rule the Mac's `restoreTaskAndKanbanControls` always had.
enum ListDetailSortControls {
    /// The Tasks tab's three controls.
    struct Tasks: Equatable {
        var sortField: TaskSortField
        var sortDirection: TaskSortDirection
        var grouping: TaskGroupingMode
    }

    /// The Kanban tab's two. A board has no Group control: its columns are its grouping.
    struct Kanban: Equatable {
        var sortField: TaskSortField
        var sortDirection: TaskSortDirection
    }

    /// Custom / Ascending / By Date: the Mac list page's `@State` defaults, which are now these.
    static let defaultTasks = Tasks(sortField: .custom, sortDirection: .ascending, grouping: .byDate)
    static let defaultKanban = Kanban(sortField: .custom, sortDirection: .ascending)

    // MARK: Keys

    private static func listToken(areaID: UUID?, projectID: UUID?) -> String {
        if let areaID { return areaID.uuidString }
        if let projectID { return projectID.uuidString }
        return "generic"
    }

    /// `list_<uuid>`, the prefix the Tasks tab's three keys hang off.
    static func tasksKeyPrefix(areaID: UUID?, projectID: UUID?) -> String {
        "list_\(listToken(areaID: areaID, projectID: projectID))"
    }

    /// `kanban_<uuid>`, the prefix the Kanban tab's two keys hang off.
    static func kanbanKeyPrefix(areaID: UUID?, projectID: UUID?) -> String {
        "kanban_\(listToken(areaID: areaID, projectID: projectID))"
    }

    static func sortFieldKey(_ prefix: String) -> String { "\(prefix)_sortField" }
    static func sortDirectionKey(_ prefix: String) -> String { "\(prefix)_sortDir" }
    static func groupingKey(_ prefix: String) -> String { "\(prefix)_grouping" }

    // MARK: Reading

    /// The Tasks tab's controls for the list whose keys start with `prefix`.
    ///
    /// `legacyMode` is iOS's retired app-wide `ios.listDetail.sortMode`: a list this device has
    /// never sorted on its own takes that choice's Sort + Order pair, through
    /// `CadenceTaskSortMode.macOSSortPair`, so the update does not silently undo a sort the user
    /// picked on the phone. Once the list is sorted here its own keys win. Group has no legacy
    /// value — the phone could not choose one — and takes the Mac's default.
    static func tasks(
        prefix: String,
        in store: UserDefaults,
        legacyMode: CadenceTaskSortMode? = nil
    ) -> Tasks {
        var controls = defaultTasks
        if let storedField = store.string(forKey: sortFieldKey(prefix)).flatMap(TaskSortField.init(rawValue:)) {
            controls.sortField = storedField
            if let direction = store.string(forKey: sortDirectionKey(prefix)).flatMap(TaskSortDirection.init(rawValue:)) {
                controls.sortDirection = direction
            }
        } else if let legacyMode {
            let pair = legacyMode.macOSSortPair
            controls.sortField = pair.field
            controls.sortDirection = pair.direction
        } else if let direction = store.string(forKey: sortDirectionKey(prefix)).flatMap(TaskSortDirection.init(rawValue:)) {
            controls.sortDirection = direction
        }
        if let grouping = store.string(forKey: groupingKey(prefix)).flatMap(TaskGroupingMode.init(rawValue:)) {
            controls.grouping = grouping
        }
        return controls
    }

    /// The Kanban tab's controls for the list whose keys start with `prefix`.
    static func kanban(prefix: String, in store: UserDefaults) -> Kanban {
        var controls = defaultKanban
        if let field = store.string(forKey: sortFieldKey(prefix)).flatMap(TaskSortField.init(rawValue:)) {
            controls.sortField = field
        }
        if let direction = store.string(forKey: sortDirectionKey(prefix)).flatMap(TaskSortDirection.init(rawValue:)) {
            controls.sortDirection = direction
        }
        return controls
    }

    /// **The controls on screen: a pick made on THIS list, else what this list has stored.**
    ///
    /// The iPad sidebar swaps lists under one live `iOSListDetailView`, so a pick held in `@State`
    /// without the list it was made on would carry list A's sort onto list B (the T-7032 shape
    /// `ListDetailPage.displayedPage` answers for the tab). A pick tagged with another list's key
    /// is ignored and the stored value read instead.
    static func displayed<Controls>(
        choice: Controls?,
        choiceListKey: String?,
        listKey: String,
        stored: () -> Controls
    ) -> Controls {
        if let choice, choiceListKey == listKey { return choice }
        return stored()
    }

    // MARK: Writing

    /// Writes all three, so a list sorted once on this device stops reading the legacy fallback.
    static func save(_ controls: Tasks, prefix: String, in store: UserDefaults) {
        store.set(controls.sortField.rawValue, forKey: sortFieldKey(prefix))
        store.set(controls.sortDirection.rawValue, forKey: sortDirectionKey(prefix))
        store.set(controls.grouping.rawValue, forKey: groupingKey(prefix))
    }

    static func save(_ controls: Kanban, prefix: String, in store: UserDefaults) {
        store.set(controls.sortField.rawValue, forKey: sortFieldKey(prefix))
        store.set(controls.sortDirection.rawValue, forKey: sortDirectionKey(prefix))
    }

    // MARK: What the controls do

    /// The open tasks in the order a list's Tasks tab or board draws them: the Mac's comparator,
    /// `taskSorted(by:direction:)`, over the open half. The board buckets this into columns, which
    /// keeps the order, so each column is in the same order the Mac's `columnCards` sorts it into.
    static func sortedOpenTasks(_ tasks: [AppTask], sortField: TaskSortField, sortDirection: TaskSortDirection) -> [AppTask] {
        CadenceTaskQuerySupport.activeTasks(from: tasks, sortField: sortField, sortDirection: sortDirection)
    }

    /// **The finished cards behind a board column's "Completed N" toggle, in the board's Sort +
    /// Order** ([[T-16301]]) -- the Mac's `ListSectionsKanbanView.columnCards`, which sorts a
    /// column's whole bucket, finished cards included, with `taskSorted(by:direction:)`.
    ///
    /// The iOS board was handed the Completed TAB's list (`CadenceTaskQuerySupport.completedTasks`,
    /// most recently finished first), so one column's finished stack read in a different order on
    /// an iPad than on the Mac under the same Sort chip, and a finished card dragged into place
    /// under Custom snapped back to its completion slot. Neither is a hardware or input reason
    /// ([[T-8201]]). `isFinishedTask`, not `isDone`, so a cancelled card is finished here too.
    static func sortedFinishedTasks(_ tasks: [AppTask], sortField: TaskSortField, sortDirection: TaskSortDirection) -> [AppTask] {
        tasks
            .filter { CadenceTaskQuerySupport.isFinishedTask($0) }
            .taskSorted(by: sortField, direction: sortDirection)
    }

    /// **The Tasks tab's groups under each Group choice** — the switch the Mac's
    /// `ListTasksView.liveGroups` makes, for the touch page.
    ///
    /// By Section is the list's own columns (`listSectionGroups`, every live section, Default left
    /// out of an empty page) tinted by `sectionAccent`; By Date and By Priority are the shared
    /// builders, which drop an empty bucket; None is the one "Tasks" group the Mac draws.
    static func taskGroups(
        from activeTasks: [AppTask],
        grouping: TaskGroupingMode,
        sectionNames: [String],
        sectionConfigs: [TaskSectionConfig],
        pageIsEmpty: Bool,
        todayKey: String
    ) -> [CadenceTaskDisplayGroup] {
        switch grouping {
        case .none:
            return [
                CadenceTaskDisplayGroup(
                    id: "all",
                    title: CadenceTaskQuerySupport.ungroupedGroupTitle,
                    accent: Theme.blue,
                    tasks: activeTasks
                )
            ]
        case .byDate:
            return CadenceTaskQuerySupport.dateDisplayGroups(from: activeTasks, todayKey: todayKey)
        case .byPriority:
            return CadenceTaskQuerySupport.priorityDisplayGroups(from: activeTasks)
        case .byList:
            return CadenceTaskQuerySupport.listSectionGroups(
                from: activeTasks,
                sectionNames: sectionNames,
                pageIsEmpty: pageIsEmpty,
                filing: ListBoardCardFiling(configs: sectionConfigs)
            )
            .map { group in
                CadenceTaskDisplayGroup(
                    id: group.id,
                    title: group.title,
                    accent: CadenceTaskQuerySupport.sectionAccent(named: group.title, configs: sectionConfigs),
                    tasks: group.tasks,
                    dropKey: group.dropKey
                )
            }
        }
    }
}
