import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **First launch, against a store with nothing in it.**
///
/// Every other suite here builds a fixture and then asks a question of it. This one asks what the
/// app does when there is no fixture: the state a TestFlight tester is in for the first few
/// minutes, and the state a reinstall or a not-yet-synced CloudKit device is in for the first few
/// *seconds*. Those two are the same store as far as every launch-time pass can tell, which is the
/// thing this suite is here to record.
///
/// `PersistenceController.performStartupMaintenance` is `private`, so the sequence is replayed
/// rather than called. `theStartupSequenceThisSuiteReplaysIsTheOneLaunchActuallyRuns` reads the
/// real function's body and fails if the replay drifts from it.
@Suite(.preservesTheStoredLaunchReports)
@MainActor
struct CadenceFirstLaunchEmptyStoreTests {

    // MARK: - The sequence

    /// The replay is only worth anything while it matches. This reads
    /// `performStartupMaintenance`'s own body — comments blanked, so the prose describing the
    /// passes cannot stand in for the calls — and pins that the five calls are present *and* in
    /// this order, because `syncAllNoteTagsFromMarkdown` resolves tags `seedDefaultTags` may have
    /// just created and the repair pass is last so it sees the migrated shape.
    @Test func theStartupSequenceThisSuiteReplaysIsTheOneLaunchActuallyRuns() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Services/PersistenceController.swift")
        )
        let body = try #require(
            CadenceSourceScan.functionBody(named: "performStartupMaintenance", in: source),
            "performStartupMaintenance is gone or its braces do not balance; the replay below is stale"
        )
        #expect(body.count > 200, "the stripped body is too small to be the real one")

        let expectedOrder = [
            "PursuitToGoalMigration.runIfNeeded",
            "NoteMigrationService.migrateAndRecordFailure",
            "TagSupport.seedDefaultTags",
            "TagSupport.syncAllNoteTagsFromMarkdown",
            "DataIntegrityRepairService.repairAndRecordFailure",
        ]
        var cursor = body.startIndex
        for needle in expectedOrder {
            let found = try #require(
                body.range(of: needle, range: cursor..<body.endIndex),
                "startup maintenance no longer calls \(needle) here, or calls it out of order"
            )
            cursor = found.upperBound
        }

        // Non-vacuity for the ordering itself: a body that contained the needles in any order
        // would pass a set-membership check, so prove the reader can see order by looking for one
        // that is genuinely later than where the walk finished.
        #expect(body.range(of: "PursuitToGoalMigration.runIfNeeded", range: cursor..<body.endIndex) == nil)
    }

    // MARK: - What a first launch leaves in the store

    /// **A first launch writes to the store, and the only thing it writes is the seven default
    /// tags.** Schema-driven rather than a hand-list: a model added to `CadenceSchema` and not to
    /// this count fails the first expectation instead of quietly going unchecked.
    @Test func aFirstLaunchAgainstAnEmptyStoreCreatesTheDefaultTagsAndNothingElse() throws {
        let context = try Self.makeEmptyContext()

        try withTemporaryDefaults("CadenceTests.firstLaunch") { defaults in
            Self.replayStartupMaintenance(in: context, defaults: defaults)
        }

        let counts = try Self.rowCountsByEntityName(in: context)
        #expect(
            Set(counts.keys) == Set(CadenceSchema.schema.entities.map(\.name)),
            "this test counts \(Set(counts.keys).symmetricDifference(Set(CadenceSchema.schema.entities.map(\.name))).sorted()) differently from the schema"
        )
        #expect(counts["Tag"] == TagSupport.defaultTags.count)
        for (name, count) in counts where name != "Tag" {
            #expect(count == 0, "a first launch created a \(name) row")
        }
    }

    /// Which pass makes the first launch dirty. Three of the four are written to do nothing to an
    /// empty store; the tag seed is the one that inserts *because* the store is empty. That
    /// asymmetry is the subject of `theTagSeedCannotTellAnEmptyStoreFromOneCloudKitHasNotFilledYet`.
    @Test func onlyTheTagSeedReportsAChangeOnAFirstLaunch() throws {
        let context = try Self.makeEmptyContext()

        try withTemporaryDefaults("CadenceTests.firstLaunchPasses") { defaults in
            PursuitToGoalMigration.runIfNeeded(modelContext: context, defaults: defaults)
            let migrationReport = NoteMigrationService.migrateAndRecordFailure(
                in: context, source: "empty-store-test", saveChanges: false
            )
            let seeded = TagSupport.seedDefaultTags(in: context, saveChanges: false)
            let synced = TagSupport.syncAllNoteTagsFromMarkdown(in: context, saveChanges: false)
            let repairReport = DataIntegrityRepairService.repairAndRecordFailure(
                in: context, source: "empty-store-test", saveChanges: false
            )

            #expect(migrationReport?.insertedTotal == 0)
            #expect(seeded)
            #expect(!synced)
            #expect(repairReport?.changed == false)
        }
    }

    // MARK: - The seed's reading of "empty"

    /// **The seed treats "no tags in the store" as "this user has never had tags".** On a device
    /// where CloudKit has not landed yet — a reinstall, a second device, a restore — those are the
    /// same store, and the seed runs synchronously the instant the container opens.
    ///
    /// So the fresh device mints an *active* `bug` while the user's own archived, recoloured `bug`
    /// is still in flight. When it arrives, `deduplicateTags` merges the pair and
    /// `mergeTagMetadata` resolves the archive flag as `target.isArchived && source.isArchived`
    /// with the freshly seeded row as the target — so the answer is `false`. The tag the user
    /// archived is back, active, in its default colour, on every synced device.
    ///
    /// Measured here, not reasoned about: this test fails the moment the seed learns to tell the
    /// two stores apart.
    @Test func theTagSeedCannotTellAnEmptyStoreFromOneCloudKitHasNotFilledYet() throws {
        let context = try Self.makeEmptyContext()

        // Launch 1 on the fresh device: the store is empty, so the seed fills it.
        #expect(TagSupport.seedDefaultTags(in: context, saveChanges: false))

        // CloudKit then delivers the row the user actually owns.
        let usersOwnTag = Cadence.Tag(
            name: "bug",
            slug: "bug",
            desc: "Retired last spring.",
            colorHex: "#123456",
            order: 4,
            isArchived: true,
            createdAt: Date(timeIntervalSince1970: 1_600_000_000)
        )
        context.insert(usersOwnTag)

        // Launch 2 — or any later call, the seed is not latched.
        TagSupport.seedDefaultTags(in: context, saveChanges: false)

        let bugTags = try context.fetch(FetchDescriptor<Cadence.Tag>()).filter { $0.slug == "bug" }
        #expect(bugTags.count == 1, "the merge should leave exactly one row per slug")
        let survivor = try #require(bugTags.first)
        #expect(survivor.isArchived == false, "the user's archived tag came back active")
        #expect(survivor.colorHex == "#ff6b6b", "and in the seed's colour, not the user's")
    }

    /// The same missing latch, reachable on a single device with no CloudKit at all: renaming a
    /// default tag changes its slug, the seed finds the old slug absent, and the original is back
    /// as an eighth tag on the next launch. Renaming is a first-class action in macOS
    /// Settings > Tags (`SettingsTagsSection.saveEdits`).
    @Test func renamingADefaultTagBringsTheOriginalBackOnTheNextLaunch() throws {
        let context = try Self.makeEmptyContext()
        TagSupport.seedDefaultTags(in: context, saveChanges: false)

        let bug = try #require(
            try context.fetch(FetchDescriptor<Cadence.Tag>()).first { $0.slug == "bug" }
        )
        // Exactly what `SettingsTagsSection.saveEdits` writes.
        bug.name = "Defect"
        bug.slug = TagSupport.slug(for: "Defect")

        TagSupport.seedDefaultTags(in: context, saveChanges: false)

        let slugs = try context.fetch(FetchDescriptor<Cadence.Tag>()).map(\.slug).sorted()
        #expect(slugs.count == TagSupport.defaultTags.count + 1)
        #expect(slugs.contains("defect"))
        #expect(slugs.contains("bug"), "the renamed tag's original was re-seeded beside it")
    }

    /// The counterexample that keeps the two tests above honest about *which* signal is wrong:
    /// archiving a tag on a store the seed can already see is respected forever. It is only the
    /// empty store that is misread.
    @Test func archivingADefaultTagSurvivesEveryLaterLaunchOnADeviceThatCanSeeIt() throws {
        let context = try Self.makeEmptyContext()
        TagSupport.seedDefaultTags(in: context, saveChanges: false)

        let polish = try #require(
            try context.fetch(FetchDescriptor<Cadence.Tag>()).first { $0.slug == "polish" }
        )
        polish.isArchived = true

        TagSupport.seedDefaultTags(in: context, saveChanges: false)
        TagSupport.seedDefaultTags(in: context, saveChanges: false)

        let all = try context.fetch(FetchDescriptor<Cadence.Tag>())
        let polishRows = all.filter { $0.slug == "polish" }
        let everyPolishRowIsArchived = polishRows.allSatisfy { $0.isArchived }
        #expect(all.count == TagSupport.defaultTags.count)
        #expect(polishRows.count == 1)
        #expect(everyPolishRowIsArchived)
    }

    // MARK: - What the surfaces show

    /// Every widget a new tester can add before entering any data reports `.empty` — not `.ready`
    /// with nothing in it, and not `.unavailable`, which claims a setup problem that is not there.
    ///
    /// Driven off the empty container's own rows, and with the app-group suppression caches passed
    /// in explicitly as empty rather than read: a unit test has no business pruning the shipping
    /// app's shared defaults.
    @Test func everyWidgetSnapshotOnAnEmptyStoreSaysEmptyRatherThanReadyOrUnavailable() throws {
        let context = try Self.makeEmptyContext()
        let todayKey = "2026-08-30"

        let today = CadenceTodayWidgetSupport.snapshot(
            from: try context.fetch(FetchDescriptor<AppTask>()),
            todayKey: todayKey,
            limit: 3,
            suppressedTaskIDs: []
        )
        #expect(today.state == .empty)
        #expect(!today.isUnavailable)
        #expect(today.totalCount == 0)
        #expect(today.overdueCount + today.dueTodayCount + today.scheduledTodayCount == 0)

        let habits = CadenceHabitWidgetSupport.snapshot(
            from: try context.fetch(FetchDescriptor<Habit>()),
            limit: 4,
            recentCompletionStates: [:]
        )
        #expect(habits.state == .empty)
        #expect(!habits.isUnavailable)
        // The one place an empty store could have rendered "0/0 checked in".
        #expect(habits.completionLabel == "No habits due")
        #expect(habits.openCount == 0)

        let milestones = CadenceMilestoneWidgetSupport.snapshot(
            from: try context.fetch(FetchDescriptor<Goal>()),
            limit: 3
        )
        #expect(milestones.state == .empty)
        #expect(!milestones.isUnavailable)

        let calendar = CadenceCalendarWidgetSupport.snapshot(
            from: try context.fetch(FetchDescriptor<AppTask>()),
            dayCount: 14
        )
        #expect(calendar.state == .empty)
        #expect(!calendar.isUnavailable)
        #expect(calendar.overdueCount == 0)
        #expect(calendar.upcomingTitle == nil)
        // The strip is a calendar, not a data list: it still draws its days.
        #expect(calendar.days.count == 14)
    }

    /// No badge anywhere in the sidebar or the More list renders a zero. `badgeCount` and the three
    /// `> 0 ? … : nil` arms are what make that true; this states it for the store that would break
    /// it if anything went back to reporting the raw count.
    @Test func noSidebarBadgeRendersAZeroOnAnEmptyStore() throws {
        let snapshot = CadenceFeatureBadgeSupport.Snapshot(
            tasks: [],
            todayKey: "2026-08-30",
            activeGoalCount: 0,
            habitCount: 0,
            activeListCount: 0
        )
        for destination in CadenceFeatureDestination.allCases {
            #expect(snapshot.count(for: destination) == nil, "\(destination) badged an empty store")
        }
        #expect(CadenceCompactShellSupport.habitProgress(for: []) == nil)
    }

    /// A goal with no contributing work reads 0%, not 100%. `Double(0) / Double(0)` is `nan`, and
    /// `min(1.0, .nan)` answers `1.0` — so the `totalTasks > 0` guard in `GoalContributionSummary`
    /// is the difference between "nothing done" and "complete". Stated because a new tester's
    /// first goal is exactly this shape for as long as it takes them to add a task to it.
    @Test func aGoalWithNothingUnderItReadsZeroPercentRatherThanComplete() throws {
        let subtasks = GoalContributionSummary(
            progressType: .subtasks,
            targetHours: 0,
            totalTasks: 0,
            completedTasks: 0,
            directTaskCount: 0,
            linkedListCount: 0,
            focusMinutes: 0,
            overdueTaskIDs: [],
            recentCompletedCount: 0,
            nextActionTitle: nil,
            nextActionDueDate: nil
        )
        #expect(subtasks.progress == 0)
        #expect(subtasks.percentLabel == "0%")

        let hours = GoalContributionSummary(
            progressType: .hours,
            targetHours: 0,
            totalTasks: 0,
            completedTasks: 0,
            directTaskCount: 0,
            linkedListCount: 0,
            focusMinutes: 0,
            overdueTaskIDs: [],
            recentCompletedCount: 0,
            nextActionTitle: nil,
            nextActionDueDate: nil
        )
        #expect(hours.progress == 0)
        #expect(hours.percentLabel == "0%")

        // The unguarded arithmetic both guards stand in front of, so the guards are not decorative.
        #expect(min(1.0, Double(0) / Double(0)).isNaN == false)
        #expect(min(1.0, Double(0) / Double(0)) == 1.0)
    }

    // MARK: - Fixtures

    private static func makeEmptyContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: CadenceSchema.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    /// `PersistenceController.performStartupMaintenance`, minus the `private`. Pinned to the real
    /// one by `theStartupSequenceThisSuiteReplaysIsTheOneLaunchActuallyRuns`.
    private static func replayStartupMaintenance(in context: ModelContext, defaults: UserDefaults) {
        PursuitToGoalMigration.runIfNeeded(modelContext: context, defaults: defaults)
        _ = NoteMigrationService.migrateAndRecordFailure(in: context, source: "empty-store-test", saveChanges: false)
        _ = TagSupport.seedDefaultTags(in: context, saveChanges: false)
        _ = TagSupport.syncAllNoteTagsFromMarkdown(in: context, saveChanges: false)
        _ = DataIntegrityRepairService.repairAndRecordFailure(in: context, source: "empty-store-test", saveChanges: false)
        try? context.save()
    }

    private static func rowCountsByEntityName(in context: ModelContext) throws -> [String: Int] {
        let counters: [EmptyStoreRowCounter] = [
            emptyStoreRowCounter(Context.self),
            emptyStoreRowCounter(Area.self),
            emptyStoreRowCounter(Project.self),
            emptyStoreRowCounter(Pursuit.self),
            emptyStoreRowCounter(Cadence.Tag.self),
            emptyStoreRowCounter(AppTask.self),
            emptyStoreRowCounter(TaskBundle.self),
            emptyStoreRowCounter(Subtask.self),
            emptyStoreRowCounter(DailyNote.self),
            emptyStoreRowCounter(WeeklyNote.self),
            emptyStoreRowCounter(PermNote.self),
            emptyStoreRowCounter(Document.self),
            emptyStoreRowCounter(Note.self),
            emptyStoreRowCounter(SavedLink.self),
            emptyStoreRowCounter(EventNote.self),
            emptyStoreRowCounter(MarkdownImageAsset.self),
            emptyStoreRowCounter(Goal.self),
            emptyStoreRowCounter(GoalListLink.self),
            emptyStoreRowCounter(Habit.self),
            emptyStoreRowCounter(HabitCompletion.self),
        ]
        var result: [String: Int] = [:]
        for counter in counters {
            result[counter.name] = try counter.count(context)
        }
        return result
    }
}

// MARK: - Schema-driven row counting

private struct EmptyStoreRowCounter {
    let name: String
    let count: @MainActor (ModelContext) throws -> Int
}

@MainActor
private func emptyStoreRowCounter<T: PersistentModel>(_ type: T.Type) -> EmptyStoreRowCounter {
    EmptyStoreRowCounter(
        name: String(describing: T.self),
        count: { try $0.fetchCount(FetchDescriptor<T>()) }
    )
}
