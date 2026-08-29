import Foundation
import SwiftData
import Testing
@testable import Cadence

@MainActor
struct DataIntegrityRepairServiceTests {
    @Test func duplicateContextsAreMergedWithoutDroppingListsOrTasks() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let oldWork = Context(name: "Work", colorHex: "#4ECB71", icon: "briefcase.fill")
        oldWork.order = 0
        let restoredWork = Context(name: "Work", colorHex: "#22c55e", icon: "briefcase.fill")
        restoredWork.order = 0

        let sharedProjectID = UUID()
        let oldProject = Project(name: "POPSA", context: oldWork)
        oldProject.id = sharedProjectID
        let restoredProject = Project(name: "POPSA", context: restoredWork)
        restoredProject.id = sharedProjectID

        let oldTask = AppTask(title: "Old task")
        oldTask.project = oldProject
        oldTask.context = oldWork
        let restoredTask = AppTask(title: "Restored task")
        restoredTask.project = restoredProject
        restoredTask.context = restoredWork

        let restoredArea = Area(name: "General", context: restoredWork)
        let habit = Habit(title: "Ship", context: oldWork)
        let goal = Goal(title: "Outcome", context: oldWork)

        modelContext.insert(oldWork)
        modelContext.insert(restoredWork)
        modelContext.insert(oldProject)
        modelContext.insert(restoredProject)
        modelContext.insert(oldTask)
        modelContext.insert(restoredTask)
        modelContext.insert(restoredArea)
        modelContext.insert(habit)
        modelContext.insert(goal)
        try modelContext.save()

        let report = try DataIntegrityRepairService.repairIfNeeded(in: modelContext, source: "test")

        #expect(report.duplicateContextsMerged == 1)
        #expect(report.duplicateProjectsMerged == 1)

        let contexts = try modelContext.fetch(FetchDescriptor<Context>())
        let projects = try modelContext.fetch(FetchDescriptor<Project>())
        let tasks = try modelContext.fetch(FetchDescriptor<AppTask>())
        let areas = try modelContext.fetch(FetchDescriptor<Area>())
        let goals = try modelContext.fetch(FetchDescriptor<Goal>())
        let habits = try modelContext.fetch(FetchDescriptor<Habit>())

        #expect(contexts.count == 1)
        #expect(contexts.first?.name == "Work")
        #expect(projects.count == 1)
        #expect(projects.first?.id == sharedProjectID)
        #expect(areas.count == 1)
        #expect(tasks.count == 2)
        #expect(tasks.allSatisfy { $0.context === contexts.first })
        #expect(tasks.allSatisfy { $0.project === projects.first })
        #expect(areas.first?.context === contexts.first)
        #expect(goals.first?.context === contexts.first)
        #expect(habits.first?.context === contexts.first)
    }

    @Test func duplicateCanonicalNotesAreMergedWithoutDroppingContentOrTags() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let area = Area(name: "Writing")
        let project = Project(name: "Review")
        let tagA = Tag(name: "daily", order: 1)
        let tagB = Tag(name: "review", order: 2)
        let older = Note(
            kind: .daily,
            title: "Untitled",
            content: "Morning plan",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200),
            dateKey: "2026-04-29",
            area: area
        )
        older.tags = [tagA]
        let newer = Note(
            kind: .daily,
            title: "Daily Review",
            content: "Evening notes",
            createdAt: Date(timeIntervalSince1970: 150),
            updatedAt: Date(timeIntervalSince1970: 300),
            dateKey: "2026-04-29",
            project: project
        )
        newer.tags = [tagB]

        modelContext.insert(area)
        modelContext.insert(project)
        modelContext.insert(tagA)
        modelContext.insert(tagB)
        modelContext.insert(older)
        modelContext.insert(newer)
        try modelContext.save()

        let report = try DataIntegrityRepairService.repairIfNeeded(in: modelContext, source: "test")
        let notes = try modelContext.fetch(FetchDescriptor<Note>())

        #expect(report.duplicateNotesMerged == 1)
        #expect(notes.count == 1)
        #expect(notes.first?.dateKey == "2026-04-29")
        #expect(notes.first?.content.contains("Morning plan") == true)
        #expect(notes.first?.content.contains("Evening notes") == true)
        #expect(notes.first?.area === area)
        #expect(notes.first?.project === project)
        #expect(Set(notes.first?.tags?.map(\.slug) ?? []) == ["daily", "review"])
    }

    @Test func unkeyedMeetingNotesAreNotMerged() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let first = Note(kind: .meeting, title: "First", content: "One")
        let second = Note(kind: .meeting, title: "Second", content: "Two")

        modelContext.insert(first)
        modelContext.insert(second)
        try modelContext.save()

        let report = try DataIntegrityRepairService.repairIfNeeded(in: modelContext, source: "test")
        let notes = try modelContext.fetch(FetchDescriptor<Note>())

        #expect(report.duplicateNotesMerged == 0)
        #expect(notes.count == 2)
    }

    // MARK: - T-340, the tasks already in the surviving project

    /// **The merge branch.** Two `Work` contexts and a project present under each with the same
    /// `id`, so `mergeProject` folds one into the other. `restoredWork` carries an extra area, and
    /// that weight is load-bearing: without it the two `contextScore`s tie at 21, the source and
    /// target roles are decided arbitrarily, and the resident task below gets re-pointed as an
    /// *arrival* by the loop that already existed. The first version of this test did tie, and
    /// passed against unmodified source while proving nothing.
    ///
    /// The task arriving from the source was always re-pointed. The task *already* in the target
    /// carries no context at all under a project that has one, and nothing ever re-derived it —
    /// nor does `mergeContext`'s sweep rescue it, because that walks `task.context === duplicate`
    /// and `nil` is not the duplicate. That is precisely why this gap survived.
    @Test func mergingAProjectRePointsTheTasksAlreadyInTheTargetNotOnlyTheArrivals() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let oldWork = Context(name: "Work")
        oldWork.order = 0
        let restoredWork = Context(name: "Work")
        restoredWork.order = 0

        let sharedID = UUID()
        let oldProject = Project(name: "Launch", context: oldWork)
        oldProject.id = sharedID
        let restoredProject = Project(name: "Launch", context: restoredWork)
        restoredProject.id = sharedID
        // Weight, so `restoredWork` is canonical and `restoredProject` is therefore the target.
        let restoredArea = Area(name: "General", context: restoredWork)

        let arriving = AppTask(title: "Arriving from the duplicate")
        arriving.project = oldProject
        arriving.context = oldWork
        // Already in the target, and pointing at nothing while its project points at a context.
        let resident = AppTask(title: "Already in the target")
        resident.project = restoredProject
        resident.context = nil

        for model in [oldWork, restoredWork] { modelContext.insert(model) }
        modelContext.insert(oldProject)
        modelContext.insert(restoredProject)
        modelContext.insert(restoredArea)
        modelContext.insert(arriving)
        modelContext.insert(resident)
        try modelContext.save()

        let report = try DataIntegrityRepairService.repairIfNeeded(in: modelContext, source: "test")

        #expect(report.duplicateProjectsMerged == 1)
        let survivingProject = try #require(try modelContext.fetch(FetchDescriptor<Project>()).first)
        // The fixture did its job: the survivor is the project the resident task was already in.
        #expect(survivingProject === restoredProject)
        #expect(resident.context != nil)
        #expect(resident.context === survivingProject.resolvedContext)
        #expect(arriving.context === survivingProject.resolvedContext)
    }

    /// **The no-duplicate branch.** No project is present twice; the project is simply adopted out
    /// of a duplicate area into the canonical one. The task inside it carries `nil`, so
    /// `mergeContext`'s `task.context === duplicate` sweep does not see it either, and before this
    /// fix the branch re-pointed the project and left its tasks behind entirely.
    ///
    /// **This is also where [[T-340]]'s stated mechanism turns out not to exist**, which the
    /// assertions below record rather than describe, because the ticket's version is what a reader
    /// would otherwise assume. The ticket says the merge changes the surviving project's *area* and
    /// so changes what it resolves to. It cannot: both branches end with `context` pinned to the
    /// canonical context — this one by assigning it outright, the merge branch by only ever
    /// selecting targets that already carry it — so `resolvedContext` is the canonical context no
    /// matter what happens to the area. The gap is real; the explanation was not.
    @Test func adoptingAProjectFromADuplicateAreaRePointsTheTasksInsideIt() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let duplicate = Context(name: "Work")
        duplicate.order = 1
        let canonical = Context(name: "Work")
        canonical.order = 0

        let sharedAreaID = UUID()
        let staleArea = Area(name: "Operations", context: duplicate)
        staleArea.id = sharedAreaID
        let canonicalArea = Area(name: "Operations", context: canonical)
        canonicalArea.id = sharedAreaID
        // Weight, so `canonical` wins `contextScore` by more than the ordering term alone.
        let ballast = AppTask(title: "Ballast")
        ballast.area = canonicalArea
        ballast.context = canonical
        let moreBallast = AppTask(title: "More ballast")
        moreBallast.area = canonicalArea
        moreBallast.context = canonical

        // Names no context: everything it has, it has from `staleArea`.
        let project = Project(name: "Launch", context: nil, area: staleArea)
        // `nil`, not `duplicate` — a task pointing at the duplicate is rescued by `mergeContext`,
        // and a fixture that used one would pass without this fix.
        let task = AppTask(title: "In the area-owned project")
        task.project = project
        task.context = nil

        for model in [duplicate, canonical] { modelContext.insert(model) }
        modelContext.insert(staleArea)
        modelContext.insert(canonicalArea)
        modelContext.insert(ballast)
        modelContext.insert(moreBallast)
        modelContext.insert(project)
        modelContext.insert(task)
        try modelContext.save()

        _ = try DataIntegrityRepairService.repairIfNeeded(in: modelContext, source: "test")

        #expect(try modelContext.fetch(FetchDescriptor<Context>()).count == 1)
        let survivingProject = try #require(try modelContext.fetch(FetchDescriptor<Project>()).first)
        #expect(survivingProject.area === canonicalArea)
        // The correction: this branch pins `context`, so the area never gets to decide.
        #expect(survivingProject.context === canonical)
        #expect(survivingProject.resolvedContext === canonical)
        #expect(task.context === canonical)
    }

    // MARK: - T-328, the boundary this service does not cross

    /// **Repair merges duplicates; it does not collect orphans, and that is a decision.**
    ///
    /// The four rows below are every orphan shape [[T-328]] names: a `Subtask` with no
    /// `parentTask`, a `TaskBundle` with no members, a `HabitCompletion` with no `habit`, and a
    /// `MarkdownImageAsset` no markdown references. Repair must leave all four alone and report
    /// `changed == false`, because `PersistenceController.performStartupMaintenance` runs it the
    /// instant the container opens with no gate on CloudKit sync state — so on a launch that races
    /// the first sync, an unowned row is indistinguishable from one whose owner has not arrived,
    /// and the emptier the store the more a sweep would delete.
    ///
    /// This test is the contract, not a description of missing work. A future sweep has to earn the
    /// right to delete by knowing the store is complete; changing these expectations without that
    /// is the failure mode it exists to catch.
    @Test func repairLeavesOrphanedRowsAloneRatherThanCollectingThemAtStartup() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let subtask = Subtask(title: "Targetless")
        let bundle = TaskBundle(title: "Empty", dateKey: "2026-08-21", startMin: 600, durationMinutes: 30)
        let completion = HabitCompletion(date: "2026-08-21")
        let asset = MarkdownImageAsset(
            data: Data([0x01, 0x02]),
            mimeType: "image/png",
            pixelWidth: 2,
            pixelHeight: 2,
            displayWidth: 100
        )
        modelContext.insert(subtask)
        modelContext.insert(bundle)
        modelContext.insert(completion)
        modelContext.insert(asset)
        try modelContext.save()

        let report = try DataIntegrityRepairService.repairIfNeeded(in: modelContext, source: "test")

        #expect(report.changed == false)
        #expect(try modelContext.fetch(FetchDescriptor<Subtask>()).count == 1)
        #expect(try modelContext.fetch(FetchDescriptor<TaskBundle>()).count == 1)
        #expect(try modelContext.fetch(FetchDescriptor<HabitCompletion>()).count == 1)
        #expect(try modelContext.fetch(FetchDescriptor<MarkdownImageAsset>()).count == 1)
    }

    // MARK: - T-428, a reminder minute that is not a time of day

    /// A `Habit.reminderMinuteOfDay` outside `0...1439` is invisible **and** inert: the planner
    /// refuses to schedule it (T-363) and both editors open it as unset (T-410), so the habit has
    /// no reminder while the field claims one and the user has nothing to look at or fix. Repair
    /// clears it, and clearing is the whole fix — the assertion that it is `nil` rather than
    /// `1439` or `0` is the decision, not a detail.
    @Test func repairClearsAHabitReminderMinuteThatIsNotATimeOfDay() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let overflow = Habit(title: "Wraps to midnight on iOS")
        overflow.reminderMinuteOfDay = 1440
        let negative = Habit(title: "Negative")
        negative.reminderMinuteOfDay = -15
        let wild = Habit(title: "Far out")
        wild.reminderMinuteOfDay = 100_000

        for habit in [overflow, negative, wild] { modelContext.insert(habit) }
        try modelContext.save()

        let report = try DataIntegrityRepairService.repairIfNeeded(in: modelContext, source: "test")

        #expect(report.habitRemindersCleared == 3)
        #expect(report.changed, "the report does not report the repair it made")

        for habit in [overflow, negative, wild] {
            #expect(habit.reminderMinuteOfDay == nil, "\(habit.title) was not cleared")
        }
        // Clearing, not clamping: neither end of the range is an answer the user chose.
        #expect(!([0, 1439] as [Int?]).contains(overflow.reminderMinuteOfDay))
        #expect(!([0, 1439] as [Int?]).contains(negative.reminderMinuteOfDay))

        // A second context on the same container: the repair saved, it did not merely mutate.
        let stored = try ModelContext(container).fetch(FetchDescriptor<Habit>())
        #expect(stored.count == 3)
        #expect(stored.allSatisfy { $0.reminderMinuteOfDay == nil })
    }

    /// Every value the pickers can emit survives, including both ends of the range and the `nil`
    /// that means "no reminder" — otherwise the test above would pass on a pass that cleared
    /// every reminder in the store.
    @Test func repairLeavesEveryRealReminderTimeAlone() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let midnight = Habit(title: "Midnight")
        midnight.reminderMinuteOfDay = 0
        let morning = Habit(title: "Morning")
        morning.reminderMinuteOfDay = 9 * 60
        let lastMinute = Habit(title: "23:59")
        lastMinute.reminderMinuteOfDay = 1439
        let unset = Habit(title: "No reminder")
        unset.reminderMinuteOfDay = nil

        for habit in [midnight, morning, lastMinute, unset] { modelContext.insert(habit) }
        try modelContext.save()

        let report = try DataIntegrityRepairService.repairIfNeeded(in: modelContext, source: "test")

        #expect(report.habitRemindersCleared == 0)
        #expect(report.changed == false, "a store with nothing wrong reported a repair")
        #expect(midnight.reminderMinuteOfDay == 0, "midnight was mistaken for unset")
        #expect(morning.reminderMinuteOfDay == 9 * 60)
        #expect(lastMinute.reminderMinuteOfDay == 1439)
        #expect(unset.reminderMinuteOfDay == nil)
    }

    /// The cleared habit reads as unset to the one caller that consumes the field, so the repair
    /// and the planner agree rather than merely both declining.
    @Test func aClearedReminderPlansNothingAndReadsAsUnsetAfterwards() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let habit = Habit(title: "Corrupt")
        habit.reminderMinuteOfDay = 1440
        modelContext.insert(habit)
        try modelContext.save()

        let now = Date(timeIntervalSince1970: 1_772_000_000)
        #expect(HabitNotificationPlanner.reminder(for: habit, now: now) == nil, "premise")

        _ = try DataIntegrityRepairService.repairIfNeeded(in: modelContext, source: "test")

        #expect(habit.reminderMinuteOfDay == nil)
        #expect(HabitNotificationPlanner.reminder(for: habit, now: now) == nil)

        // The user can now set a real one, and it survives a second repair.
        habit.reminderMinuteOfDay = 7 * 60
        let second = try DataIntegrityRepairService.repairIfNeeded(in: modelContext, source: "test")
        #expect(second.habitRemindersCleared == 0)
        #expect(HabitNotificationPlanner.reminder(for: habit, now: now) != nil)
    }

    /// The counter has to be wired into `changed`, because `performStartupMaintenance` gates its
    /// save on `repairReport?.changed` — a repair that mutates and reports `changed == false` is
    /// rolled back at the next fetch. Asserted on the value type so it fails for the right reason.
    @Test func theClearedReminderCounterCountsAsAChange() {
        var report = DataIntegrityRepairReport(
            source: "test",
            startedAt: Date(timeIntervalSince1970: 0),
            finishedAt: Date(timeIntervalSince1970: 0),
            success: true
        )
        #expect(report.changed == false)
        report.habitRemindersCleared = 1
        #expect(report.changed, "habitRemindersCleared is not wired into DataIntegrityRepairReport.changed")
    }

    /// **The T-328 boundary, re-asserted with the new pass in the store.** Clearing a reminder is
    /// not a sweep: it reads one scalar on a row that is present, so a half-synced store cannot
    /// make its predicate wrong. This pins that the pass did not widen the service's licence —
    /// the same four orphan rows survive, and a habit whose reminder is fine keeps `changed`
    /// `false` alongside them.
    @Test func clearingAReminderDidNotGiveRepairALicenceToCollectOrphans() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let subtask = Subtask(title: "Targetless")
        let bundle = TaskBundle(title: "Empty", dateKey: "2026-08-21", startMin: 600, durationMinutes: 30)
        let completion = HabitCompletion(date: "2026-08-21")
        let asset = MarkdownImageAsset(
            data: Data([0x01, 0x02]),
            mimeType: "image/png",
            pixelWidth: 2,
            pixelHeight: 2,
            displayWidth: 100
        )
        let habit = Habit(title: "Reminds at 9")
        habit.reminderMinuteOfDay = 9 * 60

        modelContext.insert(subtask)
        modelContext.insert(bundle)
        modelContext.insert(completion)
        modelContext.insert(asset)
        modelContext.insert(habit)
        try modelContext.save()

        let report = try DataIntegrityRepairService.repairIfNeeded(in: modelContext, source: "test")

        #expect(report.changed == false)
        #expect(report.habitRemindersCleared == 0)
        #expect(try modelContext.fetch(FetchDescriptor<Subtask>()).count == 1)
        #expect(try modelContext.fetch(FetchDescriptor<TaskBundle>()).count == 1)
        #expect(try modelContext.fetch(FetchDescriptor<HabitCompletion>()).count == 1)
        #expect(try modelContext.fetch(FetchDescriptor<MarkdownImageAsset>()).count == 1)
        #expect(try modelContext.fetch(FetchDescriptor<Habit>()).count == 1)
        #expect(habit.reminderMinuteOfDay == 9 * 60)
    }

    /// One spelling of the range, reachable from both targets that ask. `HabitReminderTime` lives
    /// in `Models/` because `NotificationScheduling.swift` is not in `CadenceMCPServer`'s source
    /// list and `DataIntegrityRepairService.swift` is — the [[T-409]] shape.
    @Test func theReminderMinuteRangeHasOneSpelling() {
        #expect(HabitReminderTime.minuteRange == 0...1439)
        #expect(HabitNotificationPlanner.reminderMinuteRange == HabitReminderTime.minuteRange)
        // The third reader, from T-410: the editors decide "unset" with the same range the repair
        // decides "corrupt" with, so a value one of them acts on is never one the other keeps.
        #expect(CadenceHabitReminderEditing.editorState(for: 1440).isOn == false)
        #expect(CadenceHabitReminderEditing.editorState(for: 1439).isOn)
        #expect(CadenceHabitReminderEditing.editorState(for: 0).isOn, "midnight is a reminder, not an unset one")
        #expect(HabitReminderTime.namesATimeOfDay(nil), "nil is no reminder, not a corrupt one")
        #expect(HabitReminderTime.namesATimeOfDay(0))
        #expect(HabitReminderTime.namesATimeOfDay(1439))
        #expect(!HabitReminderTime.namesATimeOfDay(1440))
        #expect(!HabitReminderTime.namesATimeOfDay(-1))
    }
}
