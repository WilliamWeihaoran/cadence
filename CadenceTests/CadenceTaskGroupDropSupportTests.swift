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
}
