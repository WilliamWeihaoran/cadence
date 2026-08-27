import Foundation
import SwiftData
import Testing
@testable import Cadence

/// Drag-to-create: what a destination's `dropKey` says, and what a new task therefore starts life
/// with.
///
/// The drag itself lives under `Cadence/iOS/` and is invisible to this target, which is exactly
/// why the two questions worth pinning were kept out of it — the key a row offers, and the seed a
/// key resolves to. Between them they are the whole feature; the view layer only carries them.
///
/// **The payload and the routing suites are gone, and their absence is the point.** They pinned
/// `CadenceTaskDropPayload` and `CadenceTaskDropCoordinator`, which existed to carry a *system*
/// `.onDrag` across the view tree and back to the button that started it. T-282 gave the iPad's
/// corner `+` the same held-palette gesture the iPhone's has, and `UIDragInteraction` cannot host
/// that gesture — its lift is a ~350ms long press of its own — so the system drag lost its last
/// source and both halves went with it. The custom drag hit-tests published frames instead
/// (`CadenceCaptureDropHitTest`, pinned in `CadenceCapturePaletteTests`) and needs neither an item
/// provider nor a return path.
@MainActor
struct CadenceTaskDropSupportTests {

    // MARK: - What a row offers

    @Test func anInboxRowWithNoDatesOffersItsListAndNothingElse() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Buy milk")
        context.insert(task)

        #expect(CadenceTaskDropSupport.dropKey(for: task) == "list:inbox")
    }

    /// Inbox is the absence of a list and a list is what owns sections, so a section is not named.
    @Test func anInboxRowDoesNotOfferASection() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Buy milk")
        task.sectionName = "Backlog"
        context.insert(task)

        #expect(!CadenceTaskDropSupport.dropKey(for: task).contains("section:"))
    }

    @Test func anAreaRowOffersItsListAndSection() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let area = Area(name: "Home")
        let task = AppTask(title: "Fix the door")
        task.area = area
        task.sectionName = "Backlog"
        context.insert(area)
        context.insert(task)

        let key = CadenceTaskDropSupport.dropKey(for: task)
        #expect(key.contains("list:a_\(area.id.uuidString)"))
        #expect(key.contains("section:Backlog"))
    }

    @Test func aProjectRowOffersTheProjectRatherThanTheArea() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let area = Area(name: "Home")
        let project = Project(name: "Kitchen")
        let task = AppTask(title: "Order tiles")
        task.area = area
        task.project = project
        context.insert(area)
        context.insert(project)
        context.insert(task)

        let key = CadenceTaskDropSupport.dropKey(for: task)
        #expect(key.contains("list:p_\(project.id.uuidString)"))
        #expect(!key.contains("list:a_"))
    }

    @Test func aSectionlessListRowFallsBackToTheDefaultSectionName() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let area = Area(name: "Home")
        let task = AppTask(title: "Fix the door")
        task.area = area
        context.insert(area)
        context.insert(task)

        #expect(CadenceTaskDropSupport.dropKey(for: task).contains("section:\(TaskSectionDefaults.defaultName)"))
    }

    @Test func aDatedRowOffersBothOfItsDates() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Ship it")
        task.scheduledDate = "2026-08-20"
        task.dueDate = "2026-08-22"
        context.insert(task)

        let key = CadenceTaskDropSupport.dropKey(for: task)
        #expect(key.contains("date:2026-08-20"))
        #expect(key.contains("due:2026-08-22"))
    }

    /// Placement, not judgement. A brand-new empty task has not earned a priority, and the
    /// composer has `!`/`!!`/`!!!` and a chip for saying otherwise in the same keystroke.
    @Test func aRowDoesNotOfferItsPriority() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Ship it")
        task.priority = .high
        context.insert(task)

        #expect(!CadenceTaskDropSupport.dropKey(for: task).contains("priority:"))
    }

    // MARK: - What a key resolves to

    @Test func anEmptyKeyResolvesToTheSameSeedATapWouldOpen() {
        let seed = CadenceTaskDropSupport.seed(forDropKey: "", todayKey: "2026-08-17")

        #expect(seed == CadenceTaskComposerSeed())
    }

    @Test func aListKeyResolvesToItsContainer() {
        let areaID = UUID()
        let projectID = UUID()

        #expect(CadenceTaskDropSupport.seed(forDropKey: "list:inbox", todayKey: "2026-08-17").container == .inbox)
        #expect(CadenceTaskDropSupport.seed(forDropKey: "list:a_\(areaID.uuidString)", todayKey: "2026-08-17").container == .area(areaID))
        #expect(CadenceTaskDropSupport.seed(forDropKey: "list:p_\(projectID.uuidString)", todayKey: "2026-08-17").container == .project(projectID))
    }

    /// A stale identifier — a list deleted while the drag was in flight — reads as Inbox, which is
    /// where a task with no list lives. It must not fail the drop.
    @Test func anUnknownListKeyFallsBackToInbox() {
        let seed = CadenceTaskDropSupport.seed(forDropKey: "list:a_not-a-uuid", todayKey: "2026-08-17")

        #expect(seed.container == .inbox)
    }

    @Test func aCompoundKeyContributesEveryAttributeItNames() {
        let areaID = UUID()
        let key = "list:a_\(areaID.uuidString)|section:Backlog|date:2026-08-20|due:2026-08-22"

        let seed = CadenceTaskDropSupport.seed(forDropKey: key, todayKey: "2026-08-17")

        #expect(seed.container == .area(areaID))
        #expect(seed.sectionName == "Backlog")
        #expect(seed.doDateKey == "2026-08-20")
        #expect(seed.dueDateKey == "2026-08-22")
    }

    @Test func aRowsOwnKeyRoundTripsBackIntoItsPlacement() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let project = Project(name: "Kitchen")
        let task = AppTask(title: "Order tiles")
        task.project = project
        task.sectionName = "Review"
        task.scheduledDate = "2026-08-20"
        context.insert(project)
        context.insert(task)

        let seed = CadenceTaskDropSupport.seed(
            forDropKey: CadenceTaskDropSupport.dropKey(for: task),
            todayKey: "2026-08-17"
        )

        #expect(seed.container == .project(project.id))
        #expect(seed.sectionName == "Review")
        #expect(seed.doDateKey == "2026-08-20")
        #expect(seed.dueDateKey.isEmpty)
        #expect(seed.priority == .none)
    }

    /// A section belongs to a list. A key naming both Inbox and a section contradicts itself, and
    /// the list wins — the section is a subdivision of the field it disagrees with.
    @Test func aSectionNamedAlongsideInboxIsDiscarded() {
        let seed = CadenceTaskDropSupport.seed(forDropKey: "list:inbox|section:Backlog", todayKey: "2026-08-17")

        #expect(seed.sectionName == TaskSectionDefaults.defaultName)
    }

    @Test func anEmptySectionNameFallsBackToTheDefault() {
        let areaID = UUID()
        let seed = CadenceTaskDropSupport.seed(
            forDropKey: "list:a_\(areaID.uuidString)|section:   ",
            todayKey: "2026-08-17"
        )

        #expect(seed.sectionName == TaskSectionDefaults.defaultName)
    }

    // MARK: - Dates

    @Test func todayResolvesToTheDayHandedIn() {
        let seed = CadenceTaskDropSupport.seed(forDropKey: "date:today|due:today", todayKey: "2026-08-17")

        #expect(seed.doDateKey == "2026-08-17")
        #expect(seed.dueDateKey == "2026-08-17")
    }

    /// Overdue and Past Do are real groups on the Today screen, and their rows carry days that
    /// have already gone by. A new task cannot be done yesterday.
    @Test func aDateAlreadyInThePastIsDroppedRatherThanSeeded() {
        let seed = CadenceTaskDropSupport.seed(
            forDropKey: "date:2026-08-10|due:2026-08-11",
            todayKey: "2026-08-17"
        )

        #expect(seed.doDateKey.isEmpty)
        #expect(seed.dueDateKey.isEmpty)
    }

    @Test func todayItselfIsNotInThePast() {
        let seed = CadenceTaskDropSupport.seed(forDropKey: "date:2026-08-17", todayKey: "2026-08-17")

        #expect(seed.doDateKey == "2026-08-17")
    }

    /// `TasksPanelSupport.assignTask` reads these two as "push to tomorrow" and "clear the date"
    /// because it is *moving* a task out of a bucket. Creating is not moving: neither names a day,
    /// so neither contributes one.
    @Test func bucketNamesThatAreNotDaysContributeNothing() {
        for key in ["date:scheduled", "date:unscheduled"] {
            let seed = CadenceTaskDropSupport.seed(forDropKey: key, todayKey: "2026-08-17")
            #expect(seed.doDateKey.isEmpty)
            #expect(seed.scheduledStartMin == -1)
        }
    }

    @Test func aMalformedDateIsIgnoredRatherThanGuessedAt() {
        let seed = CadenceTaskDropSupport.seed(forDropKey: "date:next-tuesday", todayKey: "2026-08-17")

        #expect(seed.doDateKey.isEmpty)
    }

    // MARK: - Priority groups

    /// No row emits `priority:`, but `CadenceTaskQuerySupport.priorityDisplayGroups` already
    /// produces exactly this key, so the resolver honours the vocabulary it joined.
    @Test func aPriorityGroupsOwnDropKeyResolvesToThatPriority() throws {
        for priority in TaskPriority.allCases {
            let group = CadenceTaskDisplayGroup(
                id: "priority-\(priority.rawValue)",
                title: priority.label,
                accent: Theme.priorityColor(priority),
                tasks: [],
                dropKey: "priority:\(priority.rawValue)"
            )
            let seed = CadenceTaskDropSupport.seed(
                forDropKey: try #require(group.dropKey),
                todayKey: "2026-08-17"
            )

            #expect(seed.priority == priority)
        }
    }

    // MARK: - What the insertion ghost says
    //
    // The ghost that opens between rows makes no promise about *where* the task will sit — the
    // drop seeds placement and never `order`. Everything it does claim is in this one line, so
    // the line has to agree with the seed the same key resolves to, guard for guard.

    @Test func theGhostNamesInboxWhenThereIsNoList() {
        #expect(CadenceTaskDropSupport.placementCaption(
            forDropKey: "list:inbox",
            todayKey: "2026-08-17",
            listName: ""
        ) == "Inbox")
    }

    @Test func theGhostNamesTheListTheSectionAndBothDates() {
        let caption = CadenceTaskDropSupport.placementCaption(
            forDropKey: "list:a_\(UUID().uuidString)|section:Backlog|date:2026-08-20|due:2026-08-22",
            todayKey: "2026-08-17",
            listName: "Home"
        )

        #expect(caption == "Home › Backlog · Do Aug 20 · Due Aug 22")
    }

    /// The default section is what a task in that list gets anyway; naming it says nothing the
    /// list has not said. Same rule the composer's section chip follows.
    @Test func theGhostDoesNotNameTheDefaultSection() {
        let caption = CadenceTaskDropSupport.placementCaption(
            forDropKey: "list:a_\(UUID().uuidString)|section:\(TaskSectionDefaults.defaultName)",
            todayKey: "2026-08-17",
            listName: "Home"
        )

        #expect(caption == "Home")
    }

    /// Today is a word, not a date. The composer's date chips say it that way too.
    @Test func theGhostSaysTodayRatherThanTodaysDate() {
        #expect(CadenceTaskDropSupport.placementCaption(
            forDropKey: "list:inbox|date:today",
            todayKey: "2026-08-17",
            listName: ""
        ) == "Inbox · Do Today")
    }

    /// The caption cannot advertise what the seed drops. A row in Overdue offers a date already
    /// gone by, `seed(forDropKey:)` refuses it, and the ghost must refuse it in the same breath —
    /// otherwise the block promises a due date the composer then opens without.
    @Test func theGhostDoesNotAdvertiseAPastDateTheSeedRefuses() {
        let caption = CadenceTaskDropSupport.placementCaption(
            forDropKey: "list:inbox|due:2026-08-01",
            todayKey: "2026-08-17",
            listName: ""
        )

        #expect(caption == "Inbox")
    }

    /// `assignTask`'s bucket keys name *some* future day, not a day. Nothing to print.
    @Test func theGhostPrintsNothingForABucketKey() {
        #expect(CadenceTaskDropSupport.placementCaption(
            forDropKey: "list:inbox|date:scheduled",
            todayKey: "2026-08-17",
            listName: ""
        ) == "Inbox")
    }

    /// A list whose name is empty drops the segment rather than inventing one — and must not
    /// silently read as Inbox, which is a different place.
    @Test func theGhostOmitsANamelessListRatherThanCallingItInbox() {
        let caption = CadenceTaskDropSupport.placementCaption(
            forDropKey: "list:p_\(UUID().uuidString)|section:Backlog|due:2026-08-22",
            todayKey: "2026-08-17",
            listName: "   "
        )

        #expect(caption == "Backlog · Due Aug 22")
    }

    /// A key that names Inbox *and* a section contradicts itself and the seed resolves the list's
    /// way. The caption has to resolve it the same way rather than print the section anyway.
    @Test func theGhostFollowsTheSeedWhenAKeyContradictsItself() {
        #expect(CadenceTaskDropSupport.placementCaption(
            forDropKey: "list:inbox|section:Backlog",
            todayKey: "2026-08-17",
            listName: "Home"
        ) == "Inbox")
    }

    // MARK: - The day a key names is stored fixed-width

    /// `DateFormatters.date(from:)` is lenient — `"2026-8-20"` parses — and every date comparison
    /// in Cadence is a string comparison, so a seed that kept the caller's spelling would hand the
    /// composer a key that loses those comparisons. The seed carries the canonical one.
    @Test func aLenientlySpelledDayIsSeededInItsFixedWidthSpelling() {
        let seed = CadenceTaskDropSupport.seed(
            forDropKey: "list:inbox|date:2026-8-20|due:2026-9-2",
            todayKey: "2026-08-17"
        )

        #expect(seed.doDateKey == "2026-08-20")
        #expect(seed.dueDateKey == "2026-09-02")
    }

    /// The past-date rule is that string comparison, so it only holds on a canonical key.
    /// `"2026-8-16" >= "2026-08-17"` is **true** — `"8"` sorts after `"0"` — so comparing the raw
    /// text lets a day that has already gone by through the guard that exists to stop it.
    @Test func aLenientlySpelledPastDayIsStillDropped() {
        let seed = CadenceTaskDropSupport.seed(
            forDropKey: "list:inbox|date:2026-8-16|due:2026-8-16",
            todayKey: "2026-08-17"
        )

        #expect(seed.doDateKey == "")
        #expect(seed.dueDateKey == "")
        // The comparison this guard rests on, stated so the test's premise cannot rot silently.
        #expect("2026-8-16" >= "2026-08-17")
    }

    /// Two digits short of a year is a century-sized guess, not a spelling, so it is refused
    /// rather than normalised — `normalizedDateKey` would otherwise store the year 26 AD.
    @Test func aTwoDigitYearSeedsNoDateAtAll() {
        let seed = CadenceTaskDropSupport.seed(
            forDropKey: "list:inbox|date:26-8-20",
            todayKey: "2026-08-17"
        )

        #expect(seed.doDateKey == "")
    }
}
