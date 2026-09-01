import Foundation
import SwiftData
import Testing
@testable import Cadence

@Suite(.preservesTheStoredLaunchReports)
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

    // MARK: - T-445, the stored report outlives the counter that was added after it

    /// The concrete regression: a `lastReport.v1` blob written before [[T-428]] added
    /// `habitRemindersCleared`. Synthesized decoding throws `keyNotFound` on it, `lastReport()`
    /// turns that into `nil` with `try?`, and `repairAndRecordFailure` hands back nothing on the
    /// one launch where the previous report was worth having.
    ///
    /// The JSON is spelled out rather than produced by deleting a key from a fresh encode, because
    /// that is what is actually on disk — including `errorMessage` being absent rather than null,
    /// which is the other thing synthesis is asked to tolerate here.
    @Test func aReportStoredBeforeTheReminderCounterExistedStillDecodes() throws {
        let legacy = """
        {
          "source": "app-startup",
          "startedAt": 745200000.0,
          "finishedAt": 745200001.0,
          "success": true,
          "duplicateContextsMerged": 2,
          "duplicateAreasMerged": 0,
          "duplicateProjectsMerged": 0,
          "duplicateNotesMerged": 1,
          "duplicateHabitCompletionsRemoved": 0,
          "movedAreas": 0,
          "movedProjects": 0,
          "movedTasks": 3,
          "movedGoals": 0,
          "movedHabits": 0,
          "movedNotes": 0,
          "movedDocuments": 0,
          "movedLinks": 0,
          "movedGoalLinks": 0
        }
        """

        let report = try JSONDecoder().decode(
            DataIntegrityRepairReport.self,
            from: Data(legacy.utf8)
        )

        #expect(report.source == "app-startup")
        #expect(report.success)
        #expect(report.errorMessage == nil)
        // The counters that were written are read back, not defaulted along with the missing one.
        #expect(report.duplicateContextsMerged == 2)
        #expect(report.duplicateNotesMerged == 1)
        #expect(report.movedTasks == 3)
        // The key that did not exist yet reads as its default rather than as a decoding failure.
        #expect(report.habitRemindersCleared == 0)
        #expect(report.changed)
    }

    /// **The guard that does not need editing when a fourth counter is added.** It encodes a live
    /// report, then removes each key in turn and requires the result to still decode — so the
    /// counter list is re-derived from the struct rather than restated here. A new counter decoded
    /// with `decode` instead of `decodeIfPresent` fails this the day it lands, which is the whole
    /// reason T-445 is a second occurrence rather than a first.
    ///
    /// The four head fields are the deliberate exception: they carry no defaults, they have been
    /// written by every version of this key, and a blob missing `success` is not an older report.
    @Test func aStoredReportSurvivesEveryCounterThisStructWillEverGain() throws {
        var report = DataIntegrityRepairReport(
            source: "app-startup",
            startedAt: Date(timeIntervalSince1970: 1_000),
            finishedAt: Date(timeIntervalSince1970: 1_001),
            success: true
        )
        report.duplicateContextsMerged = 1
        report.habitRemindersCleared = 1
        report.movedGoalLinks = 1

        let encoded = try JSONEncoder().encode(report)
        let object = try #require(
            try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        let required: Set<String> = ["source", "startedAt", "finishedAt", "success"]
        let optionalKeys = object.keys.filter { !required.contains($0) }

        // Non-vacuity: the loop below is worthless if the encode produced a handful of keys.
        #expect(optionalKeys.count >= 15, "expected every counter in the encoded report, got \(optionalKeys.count)")
        #expect(optionalKeys.contains("habitRemindersCleared"))
        #expect(optionalKeys.contains("duplicateContextsMerged"))

        for key in optionalKeys {
            var trimmed = object
            trimmed.removeValue(forKey: key)
            let data = try JSONSerialization.data(withJSONObject: trimmed)
            #expect(
                (try? JSONDecoder().decode(DataIntegrityRepairReport.self, from: data)) != nil,
                "DataIntegrityRepairReport stops decoding when \(key) is missing, so every report stored before that key existed is lost"
            )
        }
    }

    /// The other half of the same failure: `lastReport()` is the reader that swallows it, and it is
    /// the value `repairAndRecordFailure` falls back to. Asserted through the real `UserDefaults`
    /// key so the archive round trip — encoder, key, decoder — is what is measured.
    ///
    /// The hand-written `let saved = … defer { … }` this test used to carry is gone: the suite
    /// trait above restores the same key for every test here, and two spellings of one guard is one
    /// too many to keep working. `StoredLaunchReports.keys` names this key, and
    /// `everyTestSuiteReachingALaunchReportWriterPreservesTheStoredReports` keeps the trait on.
    @Test func lastReportReadsBackAReportStoredWithoutTheNewestCounter() throws {
        let key = "dataIntegrityRepair.lastReport.v1"

        var report = DataIntegrityRepairReport(
            source: "previous-launch",
            startedAt: Date(timeIntervalSince1970: 2_000),
            finishedAt: Date(timeIntervalSince1970: 2_002),
            success: false
        )
        report.errorMessage = "store unavailable"
        report.movedTasks = 4
        var object = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as? [String: Any]
        )
        object.removeValue(forKey: "habitRemindersCleared")
        UserDefaults.standard.set(try JSONSerialization.data(withJSONObject: object), forKey: key)

        let read = try #require(DataIntegrityRepairService.lastReport())
        #expect(read.source == "previous-launch")
        #expect(read.errorMessage == "store unavailable")
        #expect(read.movedTasks == 4)
        #expect(read.habitRemindersCleared == 0)
    }

    // MARK: - T-622, forked recurring successor chains

    /// Two devices, one occurrence, two successors.
    ///
    /// `spawnNextOccurrenceIfNeeded` guards on `recurrenceSpawnedTaskID == nil` against the local
    /// replica, so each device inserted a successor for occurrence 1 and each wrote its own id into
    /// a single `String` pointer. CloudKit keeps both rows: the user sees the same occurrence twice,
    /// in the same list, each with its own reminders.
    ///
    /// The fixture is built the way the fork actually arrives — both rows carry the series id and
    /// occurrence index the spawn writes — rather than by calling `markDone` twice, which cannot
    /// reach this: one object, one pointer, and the second call returns immediately.
    ///
    /// Asserted by identity. "One task is left" is equally true of the run that kept the wrong one,
    /// and the survivor rule is the part that has to hold on both devices at once.
    @Test func repairCollapsesTwoDevicesForkedSuccessorsOntoOneOccurrence() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let fork = try forkedSeries(in: modelContext)
        try modelContext.save()

        let report = try DataIntegrityRepairService.repairIfNeeded(in: modelContext, source: "test")

        #expect(report.duplicateRecurrenceOccurrencesRemoved == 1)
        #expect(report.changed)
        let remaining = try modelContext.fetch(FetchDescriptor<AppTask>()).map(\.id)
        #expect(remaining.count == 2, "the origin and exactly one successor")
        #expect(remaining.contains(fork.lowerID))
        #expect(!remaining.contains(fork.higherID))
        // The series stays walkable: the predecessor points at the row that survived, not at the
        // nil `repairDanglingRecurrenceLinks` would otherwise leave behind.
        #expect(fork.origin.recurrenceSpawnedTaskID == fork.lowerID)
    }

    /// **The survivor cannot depend on anything local.** Both devices see the same two rows in
    /// whatever order their own fetch returns them, and if the rule reads that order — or "the
    /// newest", or "the completed one" — device A keeps X while device B keeps Y, each deletes the
    /// other, and the occurrence is gone. A duplicate the user can see is recoverable; a deletion
    /// neither device intended is not.
    ///
    /// So this runs the collapse against both permutations of the same pair and requires the same
    /// survivor, and it seeds `createdAt` in the *opposite* order to `id` so a rule that reached for
    /// creation time would answer differently in one of the two runs.
    @Test func theSurvivingOccurrenceIsTheSameOnEveryDeviceWhateverTheLocalOrder() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let fork = try forkedSeries(in: modelContext)
        try modelContext.save()

        let pair = [fork.lower, fork.higher]
        let forward = try #require(
            CadenceTaskRecurrenceWorkflowSupport.collapsibleDuplicateOccurrences(among: pair)
        )
        let backward = try #require(
            CadenceTaskRecurrenceWorkflowSupport.collapsibleDuplicateOccurrences(among: Array(pair.reversed()))
        )

        #expect(forward.survivor.id == fork.lowerID)
        #expect(backward.survivor.id == fork.lowerID)
        #expect(forward.removable.map(\.id) == [fork.higherID])
        #expect(backward.removable.map(\.id) == [fork.higherID])
    }

    /// A duplicate the user has already completed is **not** collected, even though it is the one
    /// the deterministic rule would otherwise remove.
    ///
    /// This is the half that decides whether the pass is safe to run unattended: the survivor is
    /// chosen without looking at work, so the protection for work is the removability test. A
    /// settled occurrence carries a `completedAt` the user earned and, through
    /// `GoalContributionSummary`, a contribution to goal progress.
    @Test func aDuplicateOccurrenceTheUserAlreadyCompletedIsLeftAlone() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let fork = try forkedSeries(in: modelContext)
        fork.higher.status = .done
        fork.higher.completedAt = Date(timeIntervalSince1970: 5_000)
        try modelContext.save()

        let report = try DataIntegrityRepairService.repairIfNeeded(in: modelContext, source: "test")

        #expect(report.duplicateRecurrenceOccurrencesRemoved == 0)
        let remaining = try modelContext.fetch(FetchDescriptor<AppTask>()).map(\.id)
        #expect(remaining.contains(fork.higherID), "a completed occurrence was collected as a clone")
        #expect(remaining.contains(fork.lowerID))
    }

    /// The same protection for a duplicate the user only *edited*. Renaming one of the two is the
    /// cheapest way a person disambiguates a fork they can see, and it must not be what marks that
    /// row as disposable.
    @Test func aDuplicateOccurrenceTheUserEditedIsLeftAlone() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let fork = try forkedSeries(in: modelContext)
        fork.higher.title = "Water the plants — the real one"
        try modelContext.save()

        let report = try DataIntegrityRepairService.repairIfNeeded(in: modelContext, source: "test")

        #expect(report.duplicateRecurrenceOccurrencesRemoved == 0)
        #expect(try modelContext.fetch(FetchDescriptor<AppTask>()).count == 3)
    }

    /// Two occurrences of one series at *different* indexes are the series working, not a fork.
    /// Grouping on the series alone would collapse a recurring task's entire future into one row.
    @Test func consecutiveOccurrencesOfOneSeriesAreNotDuplicates() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let seriesID = UUID()
        let first = occurrence(seriesID: seriesID, index: 1, in: modelContext)
        let second = occurrence(seriesID: seriesID, index: 2, in: modelContext)
        try modelContext.save()

        let report = try DataIntegrityRepairService.repairIfNeeded(in: modelContext, source: "test")

        #expect(report.duplicateRecurrenceOccurrencesRemoved == 0)
        let remaining = Set(try modelContext.fetch(FetchDescriptor<AppTask>()).map(\.id))
        #expect(remaining == [first.id, second.id])
    }

    /// Non-recurring tasks carry an empty `recurrenceSeriesIDRaw`, and the computed
    /// `recurrenceSeriesID` falls back to the task's own `id` — so a pass that grouped on the
    /// computed value would put every ordinary task in a series. Two plain tasks, index 0, left
    /// alone.
    @Test func ordinaryTasksAreNeverGroupedAsRecurringDuplicates() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let one = AppTask(title: "Buy milk")
        let two = AppTask(title: "Buy milk")
        modelContext.insert(one)
        modelContext.insert(two)
        try modelContext.save()

        #expect(CadenceTaskRecurrenceWorkflowSupport.duplicateOccurrenceGroups(among: [one, two]).isEmpty)
        let report = try DataIntegrityRepairService.repairIfNeeded(in: modelContext, source: "test")
        #expect(report.duplicateRecurrenceOccurrencesRemoved == 0)
        #expect(try modelContext.fetch(FetchDescriptor<AppTask>()).count == 2)
    }

    /// A collected duplicate takes its copied subtasks with it. The spawn copies them
    /// (`makeNextRecurringTask`), so collapsing through anything other than the shared delete core
    /// would leave `Subtask` rows whose parent no longer exists — orphans this service is
    /// explicitly not allowed to clean up later.
    @Test func collapsingADuplicateOccurrenceTakesItsCopiedSubtasksWithIt() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let fork = try forkedSeries(in: modelContext)
        for task in [fork.lower, fork.higher] {
            let step = Subtask(title: "Fill the can")
            step.parentTask = task
            modelContext.insert(step)
        }
        try modelContext.save()
        #expect(try modelContext.fetch(FetchDescriptor<Subtask>()).count == 2)

        _ = try DataIntegrityRepairService.repairIfNeeded(in: modelContext, source: "test")

        let subtasks = try modelContext.fetch(FetchDescriptor<Subtask>())
        #expect(subtasks.count == 1)
        #expect(subtasks.first?.parentTask?.id == fork.lowerID)
    }

    // MARK: - T-622 fixtures

    private struct ForkedSeries {
        let origin: AppTask
        let lower: AppTask
        let higher: AppTask
        var lowerID: UUID { lower.id }
        var higherID: UUID { higher.id }
    }

    /// An origin plus the two successors two devices minted for occurrence 1.
    ///
    /// `createdAt` is seeded so the *higher*-id row is the older one, which is what makes
    /// `theSurvivingOccurrenceIsTheSameOnEveryDeviceWhateverTheLocalOrder` able to tell a
    /// uuid rule from a timestamp rule.
    private func forkedSeries(in modelContext: ModelContext) throws -> ForkedSeries {
        let origin = AppTask(title: "Water the plants")
        origin.recurrenceRule = .daily
        origin.recurrenceSeriesIDRaw = origin.id.uuidString
        origin.status = .done
        origin.completedAt = Date(timeIntervalSince1970: 1_000)
        modelContext.insert(origin)

        let seriesID = origin.recurrenceSeriesID
        let first = occurrence(seriesID: seriesID, index: 1, in: modelContext)
        let second = occurrence(seriesID: seriesID, index: 2, in: modelContext)
        // The two rows are the same occurrence, so give the second the same index as the first;
        // `occurrence` only differs them so the ids are distinct objects.
        second.recurrenceOccurrenceIndex = 1

        let ordered = [first, second].sorted { $0.id.uuidString < $1.id.uuidString }
        let lower = ordered[0]
        let higher = ordered[1]
        lower.createdAt = Date(timeIntervalSince1970: 2_000)
        higher.createdAt = Date(timeIntervalSince1970: 1_500)
        // Each device recorded *its own* successor. The store keeps one string, and this is the
        // branch this replica happens to hold.
        origin.recurrenceSpawnedTaskID = higher.id
        return ForkedSeries(origin: origin, lower: lower, higher: higher)
    }

    private func occurrence(seriesID: UUID, index: Int, in modelContext: ModelContext) -> AppTask {
        let task = AppTask(title: "Water the plants")
        task.recurrenceRule = .daily
        task.recurrenceSeriesIDRaw = seriesID.uuidString
        task.recurrenceOccurrenceIndex = index
        task.dueDate = "2026-09-02"
        modelContext.insert(task)
        return task
    }

}
