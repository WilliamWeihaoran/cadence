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
/// **T-528 turned that record into a rule.** The suite used to state, as measured fact, that the
/// tag seed could not tell the two stores apart — one launch pass that inserted *because* the
/// store was empty, sitting among three written to be inert against exactly that. There is no
/// local signal that separates "never had tags" from "tags have not arrived yet", so the seed did
/// not get a better guard on the insert: it lost every unprompted caller. Seeding is a user action
/// now, and the tests below say so instead of recording the defect.
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
    /// passes cannot stand in for the calls — and pins that the four calls are present *and* in
    /// this order, the repair pass last so it sees the migrated shape.
    ///
    /// The comment blanking earns its keep twice here since T-528: the body carries a long comment
    /// naming `TagSupport.seedDefaultTags` and explaining why it is gone, and the absence check
    /// below would match that prose and fail on a correct file if it read the raw source.
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

        // T-528. Stated on the launch path itself rather than left to the sweep below, because
        // this is the one call site the ticket is about: whatever else `performStartupMaintenance`
        // grows, it does not seed tags.
        #expect(
            !body.contains("TagSupport.seedDefaultTags"),
            "startup maintenance seeds the default tags again; an empty store is not evidence the user has never had them"
        )
    }

    // MARK: - What a first launch leaves in the store

    /// **A first launch writes nothing at all.** It used to write the seven default tags, and that
    /// single insert was the whole of T-528: the launch cannot tell an empty store from an unsynced
    /// one, so the only safe number of rows for it to create is zero.
    ///
    /// Schema-driven rather than a hand-list: a model added to `CadenceSchema` and not to this
    /// count fails the first expectation instead of quietly going unchecked.
    @Test func aFirstLaunchAgainstAnEmptyStoreCreatesNothingAtAll() throws {
        let context = try Self.makeEmptyContext()

        try withTemporaryDefaults("CadenceTests.firstLaunch") { defaults in
            Self.replayStartupMaintenance(in: context, defaults: defaults)
        }

        let counts = try Self.rowCountsByEntityName(in: context)
        #expect(
            Set(counts.keys) == Set(CadenceSchema.schema.entities.map(\.name)),
            "this test counts \(Set(counts.keys).symmetricDifference(Set(CadenceSchema.schema.entities.map(\.name))).sorted()) differently from the schema"
        )
        for (name, count) in counts {
            #expect(count == 0, "a first launch created a \(name) row")
        }

        // Non-vacuity: the counter really can see a `Tag`, so the seven zeroes above are the
        // launch's doing and not a reader that cannot count tags. This is what pressing
        // "Add Defaults" would have left, and the launch left none of it.
        context.insert(Cadence.Tag(name: "bug", slug: "bug"))
        try context.save()
        #expect(try Self.rowCountsByEntityName(in: context)["Tag"] == 1)
    }

    /// Which pass makes the first launch dirty: **none of them.** All four are now written to be
    /// inert against a store that is empty only because sync has not landed — the symmetry
    /// `DataIntegrityRepairService`'s own doc comment argues for, and that the tag seed was the
    /// single exception to.
    @Test func noStartupPassReportsAChangeOnAFirstLaunch() throws {
        let context = try Self.makeEmptyContext()

        try withTemporaryDefaults("CadenceTests.firstLaunchPasses") { defaults in
            PursuitToGoalMigration.runIfNeeded(modelContext: context, defaults: defaults)
            let migrationReport = NoteMigrationService.migrateAndRecordFailure(
                in: context, source: "empty-store-test", saveChanges: false
            )
            let synced = TagSupport.syncAllNoteTagsFromMarkdown(in: context, saveChanges: false)
            let repairReport = DataIntegrityRepairService.repairAndRecordFailure(
                in: context, source: "empty-store-test", saveChanges: false
            )

            #expect(migrationReport?.insertedTotal == 0)
            #expect(!synced)
            #expect(repairReport?.changed == false)
            #expect(!context.hasChanges, "a first launch left the store dirty")
        }
    }

    // MARK: - The seed's reading of "empty"

    /// **A launch on a device whose tags have not arrived yet leaves the user's archive alone.**
    ///
    /// This is the replacement for `theTagSeedCannotTellAnEmptyStoreFromOneCloudKitHasNotFilledYet`,
    /// which stated the defect: launch 1 on a reinstall or a second device found an empty store,
    /// minted an *active* `bug`, and when the user's own archived, recoloured `bug` landed,
    /// `deduplicateTags` merged the pair. `mergeTagMetadata` resolves the flag as
    /// `target.isArchived && source.isArchived` with the freshly seeded row as target, so the
    /// answer was `false` — the tag came back active, in the seed's colour, and CloudKit carried
    /// that to every device.
    ///
    /// The `&&` was never the bug and is untouched: an active duplicate legitimately un-archives.
    /// The bug was minting the duplicate. So the launch inserts nothing, and the row that arrives
    /// is the only `bug` there has ever been on this device — still archived, still `#123456`.
    @Test func aLaunchBeforeCloudKitLandsLeavesTheUsersArchivedTagArchived() throws {
        let context = try Self.makeEmptyContext()

        // Launch 1 on the fresh device. The store is empty and stays empty.
        try withTemporaryDefaults("CadenceTests.unsyncedLaunch") { defaults in
            Self.replayStartupMaintenance(in: context, defaults: defaults)
        }
        #expect(try context.fetchCount(FetchDescriptor<Cadence.Tag>()) == 0)

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

        // Launch 2, and every launch after it.
        try withTemporaryDefaults("CadenceTests.unsyncedLaunch2") { defaults in
            Self.replayStartupMaintenance(in: context, defaults: defaults)
            Self.replayStartupMaintenance(in: context, defaults: defaults)
        }

        let bugTags = try context.fetch(FetchDescriptor<Cadence.Tag>()).filter { $0.slug == "bug" }
        #expect(bugTags.count == 1)
        let survivor = try #require(bugTags.first)
        #expect(survivor.isArchived, "the user's archived tag came back active")
        #expect(survivor.colorHex == "#123456", "and in the seed's colour, not the user's")
        #expect(survivor.desc == "Retired last spring.")
    }

    /// **A rename survives every later launch.** This is the replacement for
    /// `renamingADefaultTagBringsTheOriginalBackOnTheNextLaunch`, the half of T-528 that needed no
    /// CloudKit at all: renaming rewrites the slug (`SettingsTagsSection.saveEdits` writes both),
    /// the seed found the old slug absent, and `bug` was back as an eighth tag on the next launch.
    /// Confirmed against the built macOS app before the fix — seven tags in, eight tags out.
    ///
    /// The second half is what keeps this from being satisfiable by breaking the seed: pressing
    /// **Add Defaults** after a rename still brings the original back, because that is what the
    /// button means. The defect was never the seed's behaviour, only who was allowed to ask for it.
    @Test func renamingADefaultTagSurvivesEveryLaterLaunch() throws {
        let context = try Self.makeEmptyContext()
        // The store the user actually has: seven tags, because they once pressed Add Defaults.
        TagSupport.seedDefaultTags(in: context, saveChanges: false)

        let bug = try #require(
            try context.fetch(FetchDescriptor<Cadence.Tag>()).first { $0.slug == "bug" }
        )
        // Exactly what `SettingsTagsSection.saveEdits` writes.
        bug.name = "Defect"
        bug.slug = TagSupport.slug(for: "Defect")

        try withTemporaryDefaults("CadenceTests.renameSurvives") { defaults in
            Self.replayStartupMaintenance(in: context, defaults: defaults)
            Self.replayStartupMaintenance(in: context, defaults: defaults)
        }

        let slugs = try context.fetch(FetchDescriptor<Cadence.Tag>()).map(\.slug).sorted()
        #expect(slugs.count == TagSupport.defaultTags.count)
        #expect(slugs.contains("defect"))
        #expect(!slugs.contains("bug"), "the renamed tag's original was re-seeded beside it")

        // And the button still does its job, which is why the seed itself was left alone.
        TagSupport.seedDefaultTags(in: context, saveChanges: false)
        let afterPressingAddDefaults = try context.fetch(FetchDescriptor<Cadence.Tag>()).map(\.slug).sorted()
        #expect(afterPressingAddDefaults.count == TagSupport.defaultTags.count + 1)
        #expect(afterPressingAddDefaults.contains("bug"))
        #expect(afterPressingAddDefaults.contains("defect"))
    }

    /// The counterexample that keeps the two tests above honest about *which* signal was wrong.
    /// Archiving is respected by the seed itself, on a store the seed can see — so pressing
    /// **Add Defaults** repeatedly never resurrects an archived tag, and never has. It was only
    /// the store the seed *could not* see that produced the resurrection.
    @Test func pressingAddDefaultsNeverResurrectsATagTheUserArchived() throws {
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

    /// **Nothing in the app seeds without being asked.** The launch path is pinned above, on
    /// `performStartupMaintenance` itself; this is the general form, because the two Settings tag
    /// screens made the same misreading one layer up — "the tag list is empty" is what a second
    /// device renders for as long as sync takes, and both seeded from `.onAppear`.
    ///
    /// The instrument's negative witness is the call it must leave alone: the same call, in a
    /// button's action. That is the whole distinction the rule draws, so the two fixtures differ
    /// only by the enclosing hook.
    @Test func noUnpromptedCodePathSeedsTheDefaultTags() throws {
        let instrument = try CadenceScanInstrument(
            "seedsDefaultTagsWithoutBeingAsked",
            fires: """
            var body: some View {
                tagCatalog(activeTags)
                    .onAppear {
                        try? TagSupport.seedDefaultTagsCommitting(in: modelContext)
                    }
            }
            """,
            andNotOn: """
            var body: some View {
                Button("Add Defaults") {
                    try? TagSupport.seedDefaultTagsCommitting(in: modelContext)
                }
            }
            """
        ) { source in
            Self.seedCallOffsets(in: source).contains { offset in
                let windowStart = source.index(offset, offsetBy: -200, limitedBy: source.startIndex)
                    ?? source.startIndex
                let window = source[windowStart..<offset]
                return Self.unpromptedHooks.contains { window.contains($0) }
            }
        }

        let read = CadenceSourceScan.strippedSourceReader()
        let paths = try CadenceSourceScan.swiftFiles(under: "Cadence")
        let offenders = try instrument.sweep(
            paths,
            atLeast: 200,
            including: "Cadence/macOS/Views/SettingsTagsSection.swift",
            read: read
        )
        #expect(offenders.isEmpty, "these seed the default tags unprompted: \(offenders)")

        // Non-vacuity for the *sweep*, not just the walk: the needle is genuinely present in the
        // tree, so `offenders.isEmpty` is the hooks being absent rather than the call being gone.
        // A rename of `seedDefaultTags` that left an unguarded caller behind would fail here.
        let callers = try paths.filter { !Self.seedCallOffsets(in: try read($0)).isEmpty }.sorted()
        #expect(
            callers == [
                "Cadence/iOS/iOSSettingsTagsSection.swift",
                "Cadence/iOS/iOSTaskDetailComponents.swift",
                "Cadence/macOS/Views/SettingsTagsSection.swift",
                // T-532: the macOS pickers' shared placeholder row, in a Button action.
                "Cadence/macOS/Views/TagPickerSupportViews.swift",
            ],
            "the set of files that may seed the default tags changed: \(callers)"
        )
    }

    // MARK: - The route back to the default set

    /// **The cost T-528 accepted, paid off on macOS** (T-532).
    ///
    /// Seeding is a user action now, so a brand-new store's first `#` picker is genuinely empty —
    /// and both macOS pickers answered that with a bare `"No tags"`, which offers the reader
    /// nothing. iOS already had the better answer in the same place: `iOSTaskTagPickerPopover`
    /// offers **Add Default Tags** whenever its catalogue is empty.
    ///
    /// `TagPickerPlaceholder.resolve` is the decision both macOS pickers now ask, and the reason it
    /// is a function rather than a condition spelled twice is the distinction it draws: **an empty
    /// catalogue is not a query that matched nothing.** The old condition read the *filtered* list
    /// and so could not tell them apart.
    @Test func anEmptyTagCatalogueOffersTheDefaultSetAndANarrowQueryDoesNot() {
        // A fresh store, picker just opened: no tags, nothing typed.
        #expect(
            TagPickerPlaceholder.resolve(hasActiveTags: false, matchCount: 0, canCreate: false)
                == .offerDefaultTags
        )

        // Tags exist and this query reached none of them. "No tags" was false here.
        #expect(
            TagPickerPlaceholder.resolve(hasActiveTags: true, matchCount: 0, canCreate: false)
                == .noMatches
        )

        // The picker is already drawing something: rows, a create row, or a restore row. In
        // particular a fresh store where the user has started typing gets the create row, not an
        // offer stacked on top of it.
        #expect(
            TagPickerPlaceholder.resolve(hasActiveTags: true, matchCount: 3, canCreate: false)
                == .none
        )
        #expect(
            TagPickerPlaceholder.resolve(hasActiveTags: false, matchCount: 0, canCreate: true)
                == .none
        )
        #expect(
            TagPickerPlaceholder.resolve(
                hasActiveTags: false,
                matchCount: 0,
                canCreate: false,
                canRestore: true
            ) == .none,
            "the picker drew Restore \"…\" and No tags one above the other"
        )
    }

    /// The same decision driven by a real store rather than by hand, closing the loop the ticket
    /// is actually about: **the offer appears on an empty store, the button's own call fills it,
    /// and the offer goes away.**
    ///
    /// The two `hasActiveTags:` arguments are computed the way both pickers compute them — from
    /// `TagSupport.uniqueBySlug(allTags.filter { !$0.isArchived })` — so this fails if the seed
    /// stops producing unarchived tags as much as if `resolve` stops answering.
    @Test func pressingTheOfferOnAFreshStoreLeavesThePickerWithNothingToOffer() throws {
        let context = try Self.makeEmptyContext()

        func hasActiveTags() throws -> Bool {
            let all = try context.fetch(FetchDescriptor<Cadence.Tag>())
            return !TagSupport.uniqueBySlug(all.filter { !$0.isArchived }).isEmpty
        }

        #expect(try hasActiveTags() == false)
        #expect(
            TagPickerPlaceholder.resolve(
                hasActiveTags: try hasActiveTags(),
                matchCount: 0,
                canCreate: false
            ) == .offerDefaultTags
        )

        // Exactly what the row's Button action runs.
        TagSupport.seedDefaultTags(in: context, saveChanges: false)

        let seeded = try context.fetch(FetchDescriptor<Cadence.Tag>())
        #expect(seeded.count == TagSupport.defaultTags.count)
        #expect(try hasActiveTags())
        #expect(
            TagPickerPlaceholder.resolve(
                hasActiveTags: try hasActiveTags(),
                matchCount: seeded.count,
                canCreate: false
            ) == .none
        )
    }

    /// Both macOS pickers go through the one placeholder, and neither keeps its own copy of the
    /// sentence. The bare `"No tags"` was already two spellings that had to stay in step.
    ///
    /// Source-shape: a SwiftUI `body` is not callable from here, so what a picker *renders* is read
    /// rather than run. The decision it renders is covered behaviourally above.
    @Test func bothMacOSTagPickersRouteTheirEmptyStateThroughTheOnePlaceholder() throws {
        let read = CadenceSourceScan.strippedSourceReader()

        for path in [
            "Cadence/macOS/Views/TagPickerPopoverViews.swift",
            "Cadence/macOS/Views/TaskTitleInlineTagPicker.swift",
        ] {
            let code = try read(path)
            #expect(code.count > 400, "non-vacuity: \(path) read as \(code.count) characters")
            #expect(
                code.contains("TagPickerPlaceholderRow("),
                "\(path) does not draw the shared placeholder"
            )
            #expect(
                code.contains("TagPickerPlaceholder.resolve("),
                "\(path) does not ask the shared decision"
            )
            #expect(
                code.contains("\"No tags\"") == false,
                "\(path) kept its own copy of the retired sentence"
            )
        }

        // The offer, and the seed call it owns, live in exactly one place.
        let host = try read("Cadence/macOS/Views/TagPickerSupportViews.swift")
        #expect(host.contains("struct TagPickerPlaceholderRow: View"))
        #expect(host.contains("case offerDefaultTags"))
        #expect(host.contains("Text(\"Add Default Tags\")"))
        #expect(
            Self.seedCallOffsets(in: host).count == 1,
            "the placeholder row is not the only seed call in its file"
        )

        // `TaskTitleInlineTagPicker` is handed the catalogue's emptiness rather than inferring it
        // from the filtered list, which is the whole distinction `resolve` exists to make.
        let entry = try read("Cadence/macOS/Views/TaskTitleEntryField.swift")
        #expect(entry.contains("hasActiveTags: !activeTags.isEmpty"))
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

    /// The enclosing spellings that mean "nobody asked for this": a SwiftUI lifecycle hook.
    ///
    /// `.onAppear` is the one both shipped tag screens used, and `.task` is its async twin. The
    /// list is deliberately this short — a longer one of plausible-looking hooks would widen a
    /// 200-character lookbehind into false positives on dense SwiftUI, and two other checks in the
    /// same test cover what it leaves out: the caller-set pin catches a seed appearing in any new
    /// file, and `theStartupSequenceThisSuiteReplaysIsTheOneLaunchActuallyRuns` reads the launch
    /// pass's own body directly.
    ///
    /// **`"performStartupMaintenance"` was in this list and could never have fired.** Comments are
    /// blanked to spaces rather than removed, so that function's signature sits well over 200
    /// characters behind the call it introduces — outside the window. Measured rather than
    /// reasoned about: mutation M1 put the seed back at launch and this detector stayed silent
    /// while the other two checks killed the run. A needle that cannot fire is worse than no
    /// needle, because it reads like coverage.
    private static let unpromptedHooks = [".onAppear", ".task {"]

    /// Where `TagSupport.seedDefaultTagsCommitting(` is called in `source`. Spelled fully qualified
    /// because that is how every real call site spells it, and a bare `seedDefaultTagsCommitting(`
    /// would also match the declaration in `TagSupport` itself.
    ///
    /// **T-653: this used to key on `TagSupport.seedDefaultTags(`.** Every UI caller now goes
    /// through `seedDefaultTagsCommitting(in:commit:)` instead — the raw `seedDefaultTags` is
    /// called with `saveChanges: false` only from there and from tests, so a needle on the old name
    /// would have read every button as having stopped seeding rather than as having started
    /// committing.
    private static func seedCallOffsets(in source: String) -> [String.Index] {
        var offsets: [String.Index] = []
        var cursor = source.startIndex
        while let found = source.range(
            of: "TagSupport.seedDefaultTagsCommitting(",
            range: cursor..<source.endIndex
        ) {
            offsets.append(found.lowerBound)
            cursor = found.upperBound
        }
        return offsets
    }

    private static func makeEmptyContext() throws -> ModelContext {
        let container = try CadenceTestStore.container()
        return ModelContext(container)
    }

    /// `PersistenceController.performStartupMaintenance`, minus the `private`. Pinned to the real
    /// one by `theStartupSequenceThisSuiteReplaysIsTheOneLaunchActuallyRuns`.
    private static func replayStartupMaintenance(in context: ModelContext, defaults: UserDefaults) {
        PursuitToGoalMigration.runIfNeeded(modelContext: context, defaults: defaults)
        _ = NoteMigrationService.migrateAndRecordFailure(in: context, source: "empty-store-test", saveChanges: false)
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
            emptyStoreRowCounter(FocusSessionLog.self),
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
