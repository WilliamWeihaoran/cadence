import Foundation
import SwiftData
import Testing
@testable import Cadence

/// Drag-to-create, second half: what a **group header** offers a dropped `+`.
///
/// `CadenceTaskDropSupportTests` pins the row half. A row carries its group's defining attribute
/// by construction, which covers every grouping — but it cannot cover a group with *no rows*, and
/// that is the group you most want to seed a task from. The header is that destination, and the
/// two questions worth pinning are the same two: what key a header offers, and what a key
/// resolves to. The view layer under `Cadence/iOS/` is invisible to this target and only carries
/// them.
@MainActor
struct CadenceTaskGroupDropSupportTests {

    private let todayKey = "2026-08-17"

    // MARK: - What a header offers, per grouping

    /// Both of these groups are *defined* by a day that has already gone by, so there is nothing a
    /// task created today could inherit from them. `dateValue` would drop the date anyway; the
    /// point of resolving to `nil` is that the header then never lights up, rather than lighting
    /// up and seeding nothing.
    @Test func todaysPastDateGroupsAreNotDropTargets() {
        #expect(CadenceTaskDropSupport.dropKey(forGroup: .todayDate(.overdue)) == nil)
        #expect(CadenceTaskDropSupport.dropKey(forGroup: .todayDate(.pastDo)) == nil)
    }

    /// On the Today screen these two buckets are exact — `todayGroups` gives `dueToday` every task
    /// due today, and `plannedToday` only ever holds tasks scheduled *for* today, because the two
    /// due buckets have already claimed everything carrying a due date.
    @Test func todaysTwoDatedGroupsOfferTheirOwnField() {
        #expect(CadenceTaskDropSupport.dropKey(forGroup: .todayDate(.dueToday)) == "due:today")
        #expect(CadenceTaskDropSupport.dropKey(forGroup: .todayDate(.plannedToday)) == "date:today")
    }

    /// The two halves of that pair must not collapse into each other: "Due Today" is a due date
    /// and "Planned Today" is a do date, and a header that seeded the wrong one of the two would
    /// look right in every screenshot.
    @Test func dueTodayAndPlannedTodaySeedDifferentFields() throws {
        let due = CadenceTaskDropSupport.seed(
            forDropKey: try #require(CadenceTaskDropSupport.dropKey(forGroup: .todayDate(.dueToday))),
            todayKey: todayKey
        )
        let planned = CadenceTaskDropSupport.seed(
            forDropKey: try #require(CadenceTaskDropSupport.dropKey(forGroup: .todayDate(.plannedToday))),
            todayKey: todayKey
        )

        #expect(due.dueDateKey == todayKey)
        #expect(due.doDateKey.isEmpty)
        #expect(planned.doDateKey == todayKey)
        #expect(planned.dueDateKey.isEmpty)
    }

    /// "Active" and "Completed" group by completion status, which is not a placement: every new
    /// task is active and none is created done, so there is nothing here to start a composer from.
    @Test func completionStatusGroupsAreNotDropTargets() {
        #expect(CadenceTaskDropSupport.dropKey(forGroup: .completion) == nil)
        #expect(CadenceTaskDropSupport.placementCaption(forGroup: .completion, todayKey: todayKey) == nil)
    }

    @Test func aListGroupOffersItsList() throws {
        let areaID = UUID()

        #expect(CadenceTaskDropSupport.dropKey(forGroup: .list(key: "inbox", name: "Inbox")) == "list:inbox")

        let seed = CadenceTaskDropSupport.seed(
            forDropKey: try #require(
                CadenceTaskDropSupport.dropKey(forGroup: .list(key: "a_\(areaID.uuidString)", name: "Home"))
            ),
            todayKey: todayKey
        )
        #expect(seed.container == .area(areaID))
    }

    /// **A Today list group is a list *and* a day, and a plain list group is only a list.**
    ///
    /// Today groups by list (T-305), so its headers are no longer date-shaped — and a header there
    /// that offered only its list would create a task that was filed correctly and then vanished
    /// off the page it was dropped on. `.todayList` is the case that says both. `.list` must stay
    /// dateless: a list detail's empty state and the Inbox panel are the same shape of destination
    /// with no day in them, and picking one up there would be inventing a date nothing named.
    ///
    /// The seed is the assertion that matters. A key-shape check alone would pass against a
    /// resolver that read `date:today` and threw it away.
    @Test func aTodayListGroupOffersTheDayAsWellAsTheListAndAPlainListGroupDoesNot() throws {
        let projectID = UUID()
        let key = "p_\(projectID.uuidString)"

        #expect(
            CadenceTaskDropSupport.dropKey(forGroup: .todayList(key: key, name: "Launch"))
                == "list:\(key)\(CadenceTaskDropSupport.separator)date:today"
        )

        let onToday = CadenceTaskDropSupport.seed(
            forDropKey: try #require(CadenceTaskDropSupport.dropKey(forGroup: .todayList(key: key, name: "Launch"))),
            todayKey: todayKey
        )
        #expect(onToday.container == .project(projectID))
        #expect(onToday.doDateKey == todayKey)
        // Planned for today, not due today: the header claims the do date and nothing else.
        #expect(onToday.dueDateKey.isEmpty)

        let elsewhere = CadenceTaskDropSupport.seed(
            forDropKey: try #require(CadenceTaskDropSupport.dropKey(forGroup: .list(key: key, name: "Launch"))),
            todayKey: todayKey
        )
        #expect(elsewhere.container == .project(projectID))
        #expect(elsewhere.doDateKey.isEmpty)

        // Both are real destinations, so both survive emptying; and the ghost can name the list
        // for either, which it can only do if `listName(forGroup:)` answers for the new case too.
        #expect(CadenceTaskDropSupport.showsWhenEmpty(.todayList(key: key, name: "Launch")))
        #expect(CadenceTaskDropSupport.listName(forGroup: .todayList(key: key, name: "Launch")) == "Launch")
        #expect(
            CadenceTaskDropSupport.placementCaption(
                forGroup: .todayList(key: key, name: "Launch"),
                todayKey: todayKey
            ) == "Launch · Do Today"
        )
    }

    /// The case the whole feature exists for: a kanban column you made and have not filled. The
    /// header carries the list *and* the section, because a section belongs to one list — a key
    /// naming only the section would be resolved against an Inbox default and lose the column.
    @Test func aSectionGroupOffersItsListAndItsSection() throws {
        let projectID = UUID()
        let seed = CadenceTaskDropSupport.seed(
            forDropKey: try #require(CadenceTaskDropSupport.dropKey(
                forGroup: .section(listKey: "p_\(projectID.uuidString)", listName: "Website", name: "Backlog")
            )),
            todayKey: todayKey
        )

        #expect(seed.container == .project(projectID))
        #expect(seed.sectionName == "Backlog")
    }

    /// The one identity the data model already spells this way. `priorityDisplayGroups` fills
    /// `CadenceTaskDisplayGroup.dropKey` with exactly this string, so the two must not drift.
    @Test func aPriorityGroupOffersTheKeyTheModelAlreadyProduces() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        var tasks: [AppTask] = []
        for priority in TaskPriority.allCases {
            let task = AppTask(title: priority.rawValue)
            task.priority = priority
            context.insert(task)
            tasks.append(task)
        }

        for group in CadenceTaskQuerySupport.priorityDisplayGroups(from: tasks) {
            let priority = try #require(TaskPriority.allCases.first { $0.label == group.title })
            #expect(group.dropKey == CadenceTaskDropSupport.dropKey(forGroup: .priority(priority)))
        }
    }

    // MARK: - Whether an empty group still draws

    /// **A group you can still add to does not vanish; a group you cannot does.** The two
    /// properties are one predicate on purpose — a header shown as an empty invitation that then
    /// refused the drop would be worse than no header at all.
    @Test func onlyDropTargetGroupsSurviveEmptying() {
        #expect(CadenceTaskDropSupport.showsWhenEmpty(.list(key: "inbox", name: "Inbox")))
        #expect(CadenceTaskDropSupport.showsWhenEmpty(
            .section(listKey: "a_\(UUID().uuidString)", listName: "Home", name: "Backlog")
        ))
        #expect(CadenceTaskDropSupport.showsWhenEmpty(.todayDate(.dueToday)))

        #expect(!CadenceTaskDropSupport.showsWhenEmpty(.completion))
        #expect(!CadenceTaskDropSupport.showsWhenEmpty(.todayDate(.overdue)))
        #expect(!CadenceTaskDropSupport.showsWhenEmpty(.todayDate(.pastDo)))
        #expect(!CadenceTaskDropSupport.showsWhenEmpty(nil))
    }

    /// Inbox's "Active" and All Tasks' "Active" carry the same word and are not the same group:
    /// every row under the first is in the Inbox by construction, while the second spans every
    /// list. The identity decides, not the title — so one survives emptying and the other does not.
    @Test func twoGroupsTitledActiveResolveDifferently() {
        #expect(CadenceTaskDropSupport.dropKey(forGroup: .list(key: "inbox", name: "Inbox")) != nil)
        #expect(CadenceTaskDropSupport.dropKey(forGroup: .completion) == nil)
    }

    // MARK: - What the ghost says on a header

    /// **A key that never named a list must not print one.** `CadenceTaskComposerSeed.container`
    /// defaults to `.inbox`, so reading the resolved seed alone made a header like "Due Today" —
    /// which names a date and nothing else — claim it would put the task in the Inbox. No task row
    /// could ever produce this, because a row always emits a `list:` part; a header can.
    @Test func theGhostDoesNotClaimInboxWhenTheKeyNeverNamedAList() {
        #expect(CadenceTaskDropSupport.placementCaption(
            forGroup: .todayDate(.dueToday),
            todayKey: todayKey
        ) == "Due Today")

        #expect(CadenceTaskDropSupport.placementCaption(
            forGroup: .todayDate(.plannedToday),
            todayKey: todayKey
        ) == "Do Today")
    }

    /// A header that *does* name Inbox still says so — the omission above is about keys with no
    /// `list:` part, not about suppressing the Inbox.
    @Test func theGhostStillNamesInboxWhenTheHeaderIsTheInbox() {
        #expect(CadenceTaskDropSupport.placementCaption(
            forGroup: .list(key: "inbox", name: "Inbox"),
            todayKey: todayKey
        ) == "Inbox")
    }

    @Test func theGhostOnASectionHeaderNamesTheListAndTheColumn() {
        #expect(CadenceTaskDropSupport.placementCaption(
            forGroup: .section(listKey: "a_\(UUID().uuidString)", listName: "Home", name: "Backlog"),
            todayKey: todayKey
        ) == "Home › Backlog")
    }

    /// The default section is what a task in that list gets anyway, so naming it says nothing the
    /// list has not — the same rule the composer's section chip follows.
    @Test func theGhostOnADefaultSectionHeaderNamesOnlyTheList() {
        #expect(CadenceTaskDropSupport.placementCaption(
            forGroup: .section(
                listKey: "a_\(UUID().uuidString)",
                listName: "Home",
                name: TaskSectionDefaults.defaultName
            ),
            todayKey: todayKey
        ) == "Home")
    }

    /// A priority header contributes exactly one thing, so the ghost has to be the one place it is
    /// said. Silently seeding a priority the drag never mentioned is the disagreement between
    /// header and composer this caption exists to prevent.
    @Test func theGhostOnAPriorityHeaderNamesThePriority() {
        #expect(CadenceTaskDropSupport.placementCaption(
            forGroup: .priority(.high),
            todayKey: todayKey
        ) == "High priority")
    }

    /// The binding property: a header and a row that resolve to the same placement print the same
    /// sentence, because there is one caption builder behind both.
    @Test func aHeaderAndARowAgreeOnTheSamePlacement() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let area = Area(name: "Home")
        context.insert(area)
        let task = AppTask(title: "Sweep")
        task.area = area
        task.sectionName = "Backlog"
        context.insert(task)

        let rowCaption = CadenceTaskDropSupport.placementCaption(
            forDropKey: CadenceTaskDropSupport.dropKey(for: task),
            todayKey: todayKey,
            listName: "Home"
        )
        let headerCaption = CadenceTaskDropSupport.placementCaption(
            forGroup: .section(listKey: "a_\(area.id.uuidString)", listName: "Home", name: "Backlog"),
            todayKey: todayKey
        )

        #expect(rowCaption == "Home › Backlog")
        #expect(headerCaption == rowCaption)
    }

    /// A header that is not a drop target has no caption to give, and the view layer keys the
    /// whole `onDrop` off exactly this.
    @Test func aHeaderThatIsNotADropTargetHasNoCaption() {
        for identity: CadenceTaskGroupDropIdentity in [.completion, .todayDate(.overdue), .todayDate(.pastDo)] {
            #expect(CadenceTaskDropSupport.placementCaption(forGroup: identity, todayKey: todayKey) == nil)
        }
    }

    // MARK: - Constructing an identity from the surface

    /// **The half that was missing, and the reason three of these five cases were dead.** The
    /// resolver already knew what a `.section` or a real `.list` header should hand over; nothing
    /// ever built one, because a header knows its column but only the *page* knows which list it is
    /// standing in. These two constructors are where the page says so, in the one spelling
    /// `container(fromListKey:)` reads back.
    @Test func aContainerSpellsItselfTheWayTheResolverReadsIt() {
        let areaID = UUID()
        let projectID = UUID()

        #expect(CadenceTaskDropSupport.containerKey(for: .inbox) == "inbox")
        #expect(CadenceTaskDropSupport.containerKey(for: .area(areaID)) == "a_\(areaID.uuidString)")
        #expect(CadenceTaskDropSupport.containerKey(for: .project(projectID)) == "p_\(projectID.uuidString)")
    }

    /// The round trip that matters: whatever the page spells, the seed has to resolve back to the
    /// same container. A key the resolver could not parse would fall through to `.inbox` and file
    /// the task in the wrong place while looking entirely correct.
    @Test func aConstructedListIdentityResolvesBackToItsOwnContainer() throws {
        for container in [TaskContainerSelection.inbox, .area(UUID()), .project(UUID())] {
            let identity = CadenceTaskDropSupport.groupIdentity(container: container, listName: "Home")
            let seed = CadenceTaskDropSupport.seed(
                forDropKey: try #require(CadenceTaskDropSupport.dropKey(forGroup: identity)),
                todayKey: todayKey
            )
            #expect(seed.container == container)
        }
    }

    /// A list-detail section header: the list *and* the column, because a section belongs to one.
    @Test func aConstructedSectionIdentityCarriesItsListAndItsColumn() throws {
        let projectID = UUID()
        let identity = CadenceTaskDropSupport.groupIdentity(
            container: .project(projectID),
            listName: "Website",
            sectionName: "Backlog"
        )

        #expect(identity == .section(
            listKey: "p_\(projectID.uuidString)",
            listName: "Website",
            name: "Backlog"
        ))

        let seed = CadenceTaskDropSupport.seed(
            forDropKey: try #require(CadenceTaskDropSupport.dropKey(forGroup: identity)),
            todayKey: todayKey
        )
        #expect(seed.container == .project(projectID))
        #expect(seed.sectionName == "Backlog")
    }

    /// **The Inbox owns no columns, so it is handed none.** A section belongs to a list and the
    /// Inbox is the absence of one — the rule `dropKey(for:)` follows when it withholds `section:`
    /// from an unfiled row, and the one `seed(forDropKey:)` enforces when it collapses a key naming
    /// both. Stated in the constructor so a caller cannot mint an identity the resolver would then
    /// quietly contradict.
    @Test func theInboxNeverProducesASectionIdentity() {
        let identity = CadenceTaskDropSupport.groupIdentity(
            container: .inbox,
            listName: "Inbox",
            sectionName: "Backlog"
        )

        #expect(identity == .list(key: "inbox", name: "Inbox"))
        #expect(CadenceTaskDropSupport.dropKey(forGroup: identity) == "list:inbox")
    }

    /// The property the list detail's Tasks tab and its board both now lean on: a column you have
    /// not filled still draws, and still takes a `+`. It is the case
    /// `CadenceTaskDropSupport.showsWhenEmpty(_:)` names as the reason it exists, and until the
    /// identity above existed there was no way for that surface to ask.
    @Test func aConstructedSectionIdentitySurvivesEmptying() {
        #expect(CadenceTaskDropSupport.showsWhenEmpty(
            CadenceTaskDropSupport.groupIdentity(
                container: .area(UUID()),
                listName: "Home",
                sectionName: "Someday"
            )
        ))
        #expect(CadenceTaskDropSupport.showsWhenEmpty(
            CadenceTaskDropSupport.groupIdentity(container: .project(UUID()), listName: "Website")
        ))
    }

    // MARK: - The columns the surface offers it

    /// **An empty column has to reach the component for the component's rule to apply.**
    /// `sectionGroups` dropped every unfilled column, so "a group you can still add to does not
    /// vanish when it empties" could never fire on a list detail — the column was gone one layer
    /// earlier. `includingEmpty` is that layer's answer, and it keeps the configured order.
    @Test func emptyColumnsSurviveOnlyWhenAskedFor() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Draft")
        task.sectionName = "Doing"
        context.insert(task)

        let names = ["Backlog", "Doing", "Done"]

        let filledOnly = CadenceTaskQuerySupport.sectionGroups(from: [task], sectionNames: names)
        #expect(filledOnly.map(\.title) == ["Doing"])

        let all = CadenceTaskQuerySupport.sectionGroups(
            from: [task],
            sectionNames: names,
            includingEmpty: true
        )
        #expect(all.map(\.title) == names)
        #expect(all.map(\.tasks.count) == [0, 1, 0])
    }

    // MARK: - What the mover reads back

    /// **The other end of the same key.** Everything above pins what a header *offers* a dropped
    /// `+`; this pins what the header's key means to the code that *moves an existing row*, which
    /// is a second reader of one vocabulary and drifted away from it unnoticed.
    ///
    /// `TasksPanelSupport.assignTask` took the whole key as one `list:` value, so a Today list
    /// header's `list:p_<uuid>|date:today` sent it looking for a project whose `uuidString` was
    /// `"<uuid>|date:today"`. It matched nothing, fell out of every branch, and the drop was
    /// accepted anyway (T-591). Only a running app could see that, which is why the parse is a
    /// value now.
    @Test func aTodayListHeadersKeyResolvesToBothTheListAndTheDay() throws {
        let projectID = UUID()
        let key = try #require(
            CadenceTaskDropSupport.dropKey(forGroup: .todayList(key: "p_\(projectID.uuidString)", name: "Website"))
        )

        #expect(key == "list:p_\(projectID.uuidString)|date:today")
        #expect(TasksPanelSupport.dropAssignments(forDropKey: key) == [.project(projectID), .scheduleToday])
    }

    /// Inbox is the case that hides best: the key still *parses*, it just resolves the compound
    /// string as a list id, and `"inbox|date:today" != "inbox"` fails silently rather than loudly.
    @Test func aTodayInboxHeadersKeyResolvesToInboxAndTheDay() throws {
        let key = try #require(
            CadenceTaskDropSupport.dropKey(forGroup: .todayList(key: "inbox", name: "Inbox"))
        )

        #expect(key == "list:inbox|date:today")
        #expect(TasksPanelSupport.dropAssignments(forDropKey: key) == [.inbox, .scheduleToday])
    }

    @Test func aTodayAreaHeadersKeyResolvesToTheAreaAndTheDay() throws {
        let areaID = UUID()
        let key = try #require(
            CadenceTaskDropSupport.dropKey(forGroup: .todayList(key: "a_\(areaID.uuidString)", name: "Home"))
        )

        #expect(TasksPanelSupport.dropAssignments(forDropKey: key) == [.area(areaID), .scheduleToday])
    }

    /// The bare forms every other macOS task surface still hands it. Splitting on the separator
    /// must not have cost the single-part keys anything — a key with no separator is one part.
    @Test func theBareKeysEveryOtherSurfaceSendsStillResolve() {
        let areaID = UUID()
        let projectID = UUID()

        #expect(TasksPanelSupport.dropAssignments(forDropKey: "list:inbox") == [.inbox])
        #expect(TasksPanelSupport.dropAssignments(forDropKey: "list:a_\(areaID.uuidString)") == [.area(areaID)])
        #expect(TasksPanelSupport.dropAssignments(forDropKey: "list:p_\(projectID.uuidString)") == [.project(projectID)])
        #expect(TasksPanelSupport.dropAssignments(forDropKey: "date:today") == [.scheduleToday])
        #expect(TasksPanelSupport.dropAssignments(forDropKey: "date:scheduled") == [.pushToScheduled])
        #expect(TasksPanelSupport.dropAssignments(forDropKey: "date:unscheduled") == [.clearSchedule])
        #expect(TasksPanelSupport.dropAssignments(forDropKey: "priority:high") == [.priority(.high)])
    }

    /// A key naming something this surface cannot apply keeps the parts it can. `section:` is the
    /// live case: `dropKey(forGroup: .section(...))` mints `list:<key>|section:<name>`, and the
    /// mover has no column assignment — dropping the column must not cost the list with it.
    @Test func aPartTheMoverCannotApplyDoesNotDiscardTheRestOfTheKey() throws {
        let projectID = UUID()
        let key = try #require(
            CadenceTaskDropSupport.dropKey(
                forGroup: .section(listKey: "p_\(projectID.uuidString)", listName: "Website", name: "Doing")
            )
        )

        #expect(key == "list:p_\(projectID.uuidString)|section:Doing")
        #expect(TasksPanelSupport.dropAssignments(forDropKey: key) == [.project(projectID)])
    }

    /// Nothing at all, and it must read as nothing rather than as an unfilled `list:` value.
    @Test func aKeyTheMoverCannotReadResolvesToNoAssignment() {
        #expect(TasksPanelSupport.dropAssignments(forDropKey: "").isEmpty)
        #expect(TasksPanelSupport.dropAssignments(forDropKey: "list:").isEmpty)
        #expect(TasksPanelSupport.dropAssignments(forDropKey: "list:p_not-a-uuid").isEmpty)
        #expect(TasksPanelSupport.dropAssignments(forDropKey: "due:today").isEmpty)
        #expect(TasksPanelSupport.dropAssignments(forDropKey: "priority:High").isEmpty)
        #expect(TasksPanelSupport.dropAssignments(forDropKey: "|").isEmpty)
    }

    /// End to end, because the parse being right is only half of it: the row has to arrive.
    @Test func droppingOnATodayListHeaderFilesTheTaskAndKeepsItOnToday() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let project = Project(name: "Website")
        let task = AppTask(title: "Draft")
        context.insert(project)
        context.insert(task)

        let key = try #require(
            CadenceTaskDropSupport.dropKey(forGroup: .todayList(key: "p_\(project.id.uuidString)", name: "Website"))
        )
        let moved = TasksPanelSupport.assignTask(
            task,
            for: key,
            todayKey: todayKey,
            areas: [],
            projects: [project],
            modelContext: context
        )

        #expect(moved)
        #expect(task.project?.id == project.id)
        #expect(task.area == nil)
        #expect(task.scheduledDate == todayKey)
    }

    /// **A drop that applied nothing must not report success.** This is the half that matters more
    /// than the parse: for as long as `handleSectionDrop` answered `true` unconditionally, the
    /// header lit up, swallowed the row and left it exactly where it was, and no amount of using
    /// the app told you which of the two had happened.
    @Test func aHeaderWhoseListIsGoneRefusesTheDropRatherThanSwallowingIt() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Draft")
        context.insert(task)

        let coordinator = TasksPanelDropCoordinator(
            allTasks: [task],
            taskIDFromPayload: { TasksPanelSupport.taskID(from: $0) },
            assignTask: { dropped, dropKey in
                TasksPanelSupport.assignTask(
                    dropped,
                    for: dropKey,
                    todayKey: self.todayKey,
                    areas: [],
                    projects: [],
                    modelContext: context
                )
            },
            reorderTask: { _, _, _ in true }
        )
        let payload = TasksPanelSupport.taskDragPayload(for: task)

        #expect(coordinator.handleSectionDrop(payload: payload, dropKey: "list:p_\(UUID().uuidString)") == false)
        #expect(coordinator.handleSectionDrop(payload: payload, dropKey: "somebody:elses-vocabulary") == false)
        #expect(task.scheduledDate.isEmpty)

        // And the live key still succeeds, so "returns false" cannot be satisfied by refusing
        // everything.
        #expect(coordinator.handleSectionDrop(payload: payload, dropKey: "list:inbox|date:today"))
        #expect(task.scheduledDate == todayKey)
    }

    /// **All Tasks and Inbox carried the same silent accept, one screen over (T-607).**
    ///
    /// `TasksListView` wrote its own copy of `handleSectionDrop` inside its body, and the copy is
    /// exactly how the defect outlived T-591: it discarded what `assignTask` answered and returned
    /// `true` unconditionally, so a header whose list is gone highlighted, took the row and left it
    /// where it was. Both surfaces route through the coordinator above now.
    ///
    /// The key is built the way the page builds it — `"list:\(group.id)"` over
    /// `TasksPanelSupport.listGroups` — rather than typed out here. A test that invents its own
    /// vocabulary cannot notice the page changing its.
    @Test func anAllTasksListHeaderRefusesADropWhoseListIsNoLongerThere() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let project = Project(name: "Website")
        let task = AppTask(title: "Draft")
        task.project = project
        context.insert(project)
        context.insert(task)

        let group = try #require(TasksPanelSupport.listGroups(from: [task], contexts: []).first)
        let dropKey = "list:\(group.id)"
        #expect(dropKey == "list:p_\(project.id.uuidString)", "the page's own key vocabulary moved")

        func coordinator(projects: [Project]) -> TasksPanelDropCoordinator {
            TasksPanelDropCoordinator(
                allTasks: [task],
                taskIDFromPayload: { TasksPanelSupport.taskID(from: $0) },
                assignTask: { dropped, key in
                    TasksPanelSupport.assignTask(
                        dropped,
                        for: key,
                        todayKey: self.todayKey,
                        areas: [],
                        projects: projects,
                        modelContext: context
                    )
                },
                reorderTask: { _, _, _ in true }
            )
        }
        let payload = TasksPanelSupport.taskDragPayload(for: task)

        // The list is still there: the drop lands, so "refuses" cannot be satisfied by refusing
        // everything.
        #expect(coordinator(projects: [project]).handleSectionDrop(payload: payload, dropKey: dropKey))
        // And gone — the state a stale header holds after a list is deleted out from under it.
        #expect(coordinator(projects: []).handleSectionDrop(payload: payload, dropKey: dropKey) == false)
    }

    /// The other half of T-607, and the half a value test cannot reach: **the page must not keep
    /// its own copy of the decision.**
    ///
    /// The copy is what made the bug invisible — `TasksPanelDropCoordinator` was fixed by T-591 and
    /// All Tasks did not read it. So this reads the call site: the section handler is the
    /// coordinator's, and there is no second `assignTask(droppedTask` in the file to answer over.
    @Test func theMergedTasksListRoutesBothDropsThroughTheSharedCoordinator() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TasksListView.swift")
        )
        #expect(source.contains("struct TasksListView: View"), "non-vacuity: wrong file read")

        #expect(
            source.contains("onDropOnSectionPayload: coordinator.sectionDropHandler(for: section.dropKey)"),
            "All Tasks / Inbox no longer take the coordinator's section handler"
        )
        #expect(source.contains("coordinator.handleTaskDrop("))
        #expect(
            CadenceSourceScan.matchCount(#"assignTask\(droppedTask"#, in: source) == 0,
            "the page is deciding a drop for itself again — that is the T-607 copy"
        )
    }

    // MARK: - T-715: the row drop's keyless arm

    /// **T-715.** `handleTaskDrop`'s `dropKey` no longer defaults to `nil` — both call sites spell
    /// it — but the `nil` **arm** stays, and this is the test it never had.
    ///
    /// A keyless row drop must **reorder and assign nothing**. That is the deliberate asymmetry
    /// with `handleSectionDrop`, which answers `false` on a key that resolved to nothing (T-591):
    /// a *header* that swallows a row and leaves it put is a silent accept, while a *row* drop has
    /// already moved the row, so there is nothing silent about it.
    @Test func arowDropIntoAGroupWithNoKeyReordersAndAssignsNothing() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let dropped = AppTask(title: "Draft")
        let target = AppTask(title: "Ship")
        context.insert(dropped)
        context.insert(target)

        var assigned: [String] = []
        var reordered: [(UUID, UUID)] = []
        let coordinator = TasksPanelDropCoordinator(
            allTasks: [dropped, target],
            taskIDFromPayload: { TasksPanelSupport.taskID(from: $0) },
            assignTask: { _, key in
                assigned.append(key)
                return true
            },
            // Answers `true`: since T-868 a row drop reports the *commit*, so a stub that
            // answered `false` would make `handleTaskDrop` refuse every drop below and the two
            // reorder counts would be measuring the stub rather than the coordinator.
            reorderTask: { moved, before, _ in
                reordered.append((moved, before))
                return true
            }
        )
        let payload = TasksPanelSupport.taskDragPayload(for: dropped)

        #expect(coordinator.handleTaskDrop(
            payload: payload,
            targetTask: target,
            scopeTasks: [dropped, target],
            dropKey: nil
        ))
        #expect(assigned.isEmpty, "a keyless row drop reassigned the task: \(assigned)")
        #expect(reordered.count == 1, "a keyless row drop did not reorder")
        #expect(reordered.first?.0 == dropped.id)
        #expect(reordered.first?.1 == target.id)

        // Paired, because "assigned nothing" is worthless from a coordinator that calls nothing:
        // the same coordinator, one key, and the assignment happens **and** the reorder still runs.
        #expect(coordinator.handleTaskDrop(
            payload: payload,
            targetTask: target,
            scopeTasks: [dropped, target],
            dropKey: "date:today"
        ))
        #expect(assigned == ["date:today"])
        #expect(reordered.count == 2, "the reorder must run either way")
    }

    /// The other half: the `nil` arm is reached by **real groups**, not only by a test that passes
    /// `nil`. These three are exactly the groups whose headers offer no drop key, so every row
    /// drop inside Today's Overdue, Past-do and Completed group takes the arm above.
    @Test func thegroupsThatOfferNoDropKeyAreTheOnesARowDropOnlyReorders() {
        let keyless: [CadenceTaskGroupDropIdentity] = [.todayDate(.overdue), .todayDate(.pastDo), .completion]
        for identity in keyless {
            #expect(CadenceTaskDropSupport.dropKey(forGroup: identity) == nil, "\(identity) offers a key now")
        }

        // Non-vacuity: the same call does answer for the groups that name a placement, so "nil"
        // above is about these three rather than about a function that resolves nothing.
        #expect(CadenceTaskDropSupport.dropKey(forGroup: .todayDate(.dueToday)) == "due:today")
        #expect(CadenceTaskDropSupport.dropKey(forGroup: .list(key: "inbox", name: "Inbox")) == "list:inbox")
    }

    /// **The default is gone.** A deleted *declaration* is invisible to a value test, so it is
    /// pinned as source — the shape `CadenceTodayUnificationTests
    /// .theDropCoordinatorKeepsOnlyTheHalfItsCallersUse` already uses for T-564(b)'s deletion —
    /// together with the two call sites that make it dead.
    @Test func therowDropDeclaresNoDefaultDropKeyAndBothCallersSupplyOne() throws {
        let coordinator = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TasksPanelDropCoordinator.swift")
        )
        #expect(coordinator.contains("func handleTaskDrop("), "non-vacuity: wrong file read")
        #expect(
            CadenceSourceScan.matchCount(#"dropKey: String\? = nil"#, in: coordinator) == 0,
            "handleTaskDrop's dropKey default is back, and no caller takes it"
        )

        for (path, argument) in [
            ("Cadence/macOS/Views/TasksPanel.swift", "dropKey: dropKey"),
            ("Cadence/macOS/Views/TasksListView.swift", "dropKey: section.dropKey")
        ] {
            let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            #expect(
                CadenceSourceScan.matchCount(#"handleTaskDrop\("#, in: source) == 1,
                "\(path) no longer makes exactly one row drop"
            )
            #expect(source.contains(argument), "\(path) no longer passes its own drop key")
        }
    }
}
