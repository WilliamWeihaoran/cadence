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
}
