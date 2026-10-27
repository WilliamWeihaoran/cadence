import Foundation
import SwiftData
import Testing
@testable import Cadence

#if os(macOS)
@MainActor
struct TaskBundleTests {
    // The T-628 refusal pair, aRefusedBundleCompletionLeavesTheBlockItsMembersAndTheSuccessorAlone
    // and aRefusedUnbundleLeavesTheBlockAndItsMembersAlone, was declared here. Both drove the
    // Mac's caller-less block wrappers, which [[T-3170]] deleted. The commit boundary they reached
    // is the shared CadenceTaskMutationSupport.deleteBundle's, still pinned directly by
    // CadenceTrackingEditorSaveCommitTests and CadenceDeleteSurvivorRestoreTests.

    // `addingTaskToBundleUsesBundleDateWithoutTaskTime` and
    // `reassigningTaskBetweenBundlesRemovesOldMembership` were declared here. Both exercised
    // SchedulingActions.addTask(_:to:) itself -- the Mac's "drop a task onto an existing block" --
    // which [[T-3170]]'s trio pass deleted with the canvas arm that could express that drop. The
    // tests below that still need a member build one with `CadenceTestBundleFixture.place`.

    @Test func droppingBundledTaskOntoTimelineRemovesBundleMembership() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Pull report")
        let bundle = TaskBundle(title: "Batch", dateKey: "2026-05-01", startMin: 600, durationMinutes: 30)
        context.insert(task)
        context.insert(bundle)
        CadenceTestBundleFixture.place(task, in: bundle)

        SchedulingActions.dropTask(task, to: "2026-05-03", startMin: 720)

        #expect(task.bundle == nil)
        #expect(bundle.sortedTasks.isEmpty)
        #expect(task.scheduledDate == "2026-05-03")
        #expect(task.scheduledStartMin == 720)
    }

    // deletingBundleKeepsTasksOnBundleDate, deletingBundleAlsoDetachesCancelledHiddenMembers and
    // completingBundleMarksMemberTasksDoneAndRemovesBundle were declared here. They pinned the
    // Mac's delete and complete wrappers, which [[T-3170]] deleted with no production caller left.
    // The detach itself is pinned on the shared mutation by CadenceBundleInspectorHostTests.

    @Test func rollingOverLastActiveBundledTaskDetachesItAndRemovesOldBundle() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Carry me")
        let bundle = TaskBundle(title: "Yesterday", dateKey: "2026-05-01", startMin: 600, durationMinutes: 30)
        context.insert(task)
        context.insert(bundle)
        CadenceTestBundleFixture.place(task, in: bundle)

        SchedulingActions.rollOverTaskToToday(task, todayKey: "2026-05-02", in: context)

        #expect(task.bundle == nil)
        #expect(task.scheduledDate == "2026-05-02")
        #expect(task.scheduledStartMin == -1)
        #expect(try context.fetch(FetchDescriptor<TaskBundle>()).isEmpty)
    }

    @Test func rollingOverOneBundledTaskKeepsBundleWhenOtherActiveTasksRemain() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let first = AppTask(title: "Carry me")
        let second = AppTask(title: "Stay bundled")
        let bundle = TaskBundle(title: "Yesterday", dateKey: "2026-05-01", startMin: 600, durationMinutes: 30)
        [first, second].forEach(context.insert)
        context.insert(bundle)
        [first, second].forEach { CadenceTestBundleFixture.place($0, in: bundle) }

        SchedulingActions.rollOverTaskToToday(first, todayKey: "2026-05-02", in: context)

        #expect(first.bundle == nil)
        #expect(first.scheduledDate == "2026-05-02")
        #expect(first.scheduledStartMin == -1)
        #expect(second.bundle?.id == bundle.id)
        #expect(bundle.sortedTasks.map(\.id) == [second.id])
        #expect(try context.fetch(FetchDescriptor<TaskBundle>()).map(\.id) == [bundle.id])
    }

    @Test func removingTaskFromBundleKeepsItOnBundleDateWithoutCalendarSlot() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Loose item")
        let bundle = TaskBundle(title: "Batch", dateKey: "2026-05-01", startMin: 600, durationMinutes: 30)
        context.insert(task)
        context.insert(bundle)
        CadenceTestBundleFixture.place(task, in: bundle)

        SchedulingActions.removeTaskFromBundle(task)

        #expect(task.bundle == nil)
        #expect(task.scheduledDate == "2026-05-01")
        #expect(task.scheduledStartMin == -1)
        #expect(bundle.sortedTasks.isEmpty)
    }

    /// [[T-6483]]: two rows sharing an `id` until repair merges them. Taking one out of the block
    /// must leave the other in it; the `id` filter this replaced emptied the block.
    @Test func removingOneOfTwoSameIDTasksFromABlockLeavesItsTwinThere() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let bundle = TaskBundle(title: "Batch", dateKey: "2026-05-01", startMin: 600, durationMinutes: 30)
        let survivor = AppTask(title: "Survivor")
        let copy = AppTask(title: "Copy")
        copy.id = survivor.id
        context.insert(bundle)
        context.insert(survivor)
        context.insert(copy)
        survivor.bundle = bundle
        copy.bundle = bundle
        copy.bundleOrder = 1
        try context.save()
        try #require((bundle.tasks ?? []).count == 2, "fixture: both copies must start in the block")

        SchedulingActions.removeTaskFromBundle(copy)

        #expect(copy.bundle == nil)
        #expect((bundle.tasks ?? []).count == 1 && bundle.tasks?.first === survivor, "the twin left the block")
        #expect(survivor.bundle === bundle)
    }

    // `bundleOrderCanBeChangedManually` was declared here. It pinned
    // SchedulingActions.moveTaskInBundle, which [[T-3213]] deleted with no caller left.

    // `creatingBundleFromTwoTimedTasksUsesTargetSlotAndMembersLoseIndividualTimes` was declared
    // here. It pinned CadenceTaskMutationSupport.insertBundle(from:adding:), which [[T-3170]]
    // deleted once no surface could form a block any more.

    // unbundlingKeepsTasksOnBundleDateAndPreservesListMetadata was declared here. It pinned the
    // Mac's unbundle wrapper, which [[T-3170]] deleted with no production caller left.

    // `bundleTimesAreClampedInsideOneDay` was declared here, last re-pointed at
    // SchedulingActions.updateBundleTime -- the block's resize handle. [[T-3170]]'s trio pass
    // deleted that with `TimelineBundleBlock`, its only caller, so no path resizes a block.

    /// `AppTask.calendarEventID` is documented as write-only-empty: attaching a task to a calendar
    /// event is not a feature that exists, the readers that remain are there to *clear* values an
    /// earlier build left on disk, and the field survives only because removing a stored SwiftData
    /// property with no migration plan would drop data. That invariant was held purely by
    /// convention — nothing asserted it, so the first entry point to start writing an identifier
    /// would have reintroduced half a feature silently.
    @Test func noSchedulingEntryPointEverGivesATaskACalendarEventID() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let area = Area(name: "Ops")
        context.insert(area)

        // 1. The shared creation sheet / quick capture path.
        TaskCreationService(areas: [area], projects: []).insertTask(
            from: TaskCreationDraft(
                title: "From the sheet",
                notes: "",
                priority: .none,
                container: .area(area.id),
                sectionName: TaskSectionDefaults.defaultName,
                dueDateKey: "",
                scheduledDateKey: "2026-05-01",
                subtaskTitles: [],
                tags: [],
                scheduledStartMin: 800
            ),
            into: context
        )
        // 2. The generic scheduled-insert helper the shared surfaces use.
        _ = try CadenceTaskMutationSupport.insertScheduledTask(
            title: "Inserted",
            allTasks: try context.fetch(FetchDescriptor<AppTask>()),
            modelContext: context,
            scheduledDate: "2026-05-01",
            scheduledStartMin: 900,
            estimatedMinutes: 30
        )

        let created = try context.fetch(FetchDescriptor<AppTask>())
        #expect(created.count == 2)
        #expect(created.allSatisfy { $0.calendarEventID.isEmpty })

        // And every path that *moves* a task must clear an identifier an older build left behind,
        // rather than carrying it onto the new slot.
        func stale(_ title: String) -> AppTask {
            let task = AppTask(title: title)
            task.scheduledDate = "2026-05-01"
            task.scheduledStartMin = 540
            task.estimatedMinutes = 30
            task.calendarEventID = "legacy-event-id"
            context.insert(task)
            return task
        }

        let rolled = stale("Rolled over")
        SchedulingActions.rollOverTaskToToday(rolled, todayKey: "2026-05-02", in: context)
        #expect(rolled.calendarEventID.isEmpty)

        let detached = stale("Detached")
        SchedulingActions.removeFromCalendar(detached)
        #expect(detached.calendarEventID.isEmpty)

        // The unbundle step went with the Mac's unbundle wrapper ([[T-3170]]); the shared delete's
        // clearing of a legacy identifier is pinned by CadenceBundleInspectorHostTests.

        // Duplicating must not hand a second task the same event identifier.
        let source = stale("Original")
        let copy = try CadenceTaskMutationSupport.duplicate(
            source,
            allTasks: try context.fetch(FetchDescriptor<AppTask>()),
            modelContext: context
        )
        #expect(copy.calendarEventID.isEmpty)
    }

    // [[T-3170]] retired `bundleFocusLoggingDistributesByEstimate`. It reached the weighting
    // through FocusSessionSupport.distributeBundleMinutes, the Mac's delegating spelling, which
    // went with Block Focus. The weighting itself is pinned without a Block by
    // `CadenceFocusDistributionTests.asessionSplitsItsMinutesByEstimateAndLosesNoneOfThem`.
    /// **T-567.** An untitled block was called "Task Bundle" — the *type's* name, and a word the
    /// app never says to a user. Everything around it on that screen said **Block**: the segment,
    /// "Block title", "Edit Block", "Delete Block", "No tasks in this block". The literal was
    /// typed at nine sites across both platforms, three of which *stored* it rather than merely
    /// drawing it, so the noun could be renamed in one place and left behind in eight.
    ///
    /// One constant now, on the model that owns the concept, with the store/display split
    /// `CadenceEventTitleSupport` already draws: `storedTitle` for a create form about to save,
    /// `displayTitle` for a row reading a block an older build may have stored blank.
    @Test func anUntitledBlockIsNamedWithTheNounTheAppUses() throws {
        #expect(TaskBundle.defaultDisplayTitle == "Block")
        #expect(TaskBundle.storedTitle("") == TaskBundle.defaultDisplayTitle)
        // A title of spaces is not a title — the same trim `displayTitle` has always done, now on
        // the storing side too, so the blank never reaches the store in the first place.
        #expect(TaskBundle.storedTitle("   ") == TaskBundle.defaultDisplayTitle)
        #expect(TaskBundle.storedTitle("  Deep work  ") == "Deep work")

        let blank = TaskBundle(title: " \n ", dateKey: "2026-05-01", startMin: 600, durationMinutes: 30)
        #expect(blank.displayTitle == TaskBundle.defaultDisplayTitle)
        #expect(TaskBundle(title: "Admin", dateKey: "2026-05-01", startMin: 600, durationMinutes: 30).displayTitle == "Admin")
        // The two empty-slot creation paths this also drove through the store went with
        // [[T-3170]]; no surface mints a titled block from a form any more.
    }

    /// **T-843.** The rest of the "Block" vocabulary, pinned by value beside the noun each one
    /// stands in for on screen. `shortLabel` covered three call sites at once (a Focus status chip,
    /// a mode-picker button — gone with [[T-3170]] — and the unlabelled facts row), which is
    /// exactly why it needed to be a constant: three re-typings is three chances for one to drift.
    @Test func theRestOfTheBlockVocabularyIsOneWordEach() throws {
        #expect(TaskBundle.shortLabel == "Block")
        #expect(TaskBundle.titleFieldPlaceholder == "Block title")
        #expect(TaskBundle.deleteConfirmationTitle == "Delete Block?")
        #expect(TaskBundle.deleteConfirmationButtonTitle == "Delete Block")

        // None of the four collides with another — a copy/paste that reused the wrong constant
        // would still read as "Block" somewhere, but the wrong sentence. It was seven until
        // [[T-3170]] deleted `tasksSectionLabel`, `focusEyebrowTitle` and `logSessionTitle` with
        // the Block Focus surfaces that were each one's only reader.
        let values = [
            TaskBundle.shortLabel,
            TaskBundle.titleFieldPlaceholder,
            TaskBundle.deleteConfirmationTitle,
            TaskBundle.deleteConfirmationButtonTitle,
        ]
        #expect(Set(values).count == values.count)
    }

    // `everyKnownBundleSiteReadsTheSharedVocabulary` was declared here: the live sites T-843
    // found, each pinned to read the shared constant rather than a re-typed literal. It was
    // eleven; Block Focus took five in [[T-3170]], the iOS pass took the detail sheet's, and the
    // trio pass took the last three with `TimelineBundleBlock.swift` and
    // `TimelineBundleBlockSupportViews.swift`. No product file reads those constants any more, so
    // there is no site left to pin; `theRestOfTheBlockVocabularyIsOneWordEach` above still holds
    // their values, and `noNewSurfaceTypesTheRetiredBundleNounEither` below still guards against
    // the noun coming back.

    /// The other eight sites, which no behavioural test can reach: they are literals inside `View`
    /// bodies and one AppKit-side service. The iOS create sheet is not in this list because it
    /// never typed the noun — its half of T-567 is `canCreate`, two tests below.
    ///
    /// **`CadenceTaskBundleMutationSupport.swift` is listed beside its own extension file, and the
    /// pairing is the point (T-1122).** That file is where `enum CadenceTaskMutationSupport` is now
    /// *declared* — the block constructor and its clamps moved there so `CadenceMCPServer` can
    /// compile them without the notification and WidgetKit stacks the rest of the enum reaches.
    /// Listing only the extension file would have let the split quietly halve this rule's reach:
    /// `insertBundle(title:…)`, the one member here that minted a title, went with the declaration.
    /// **[[T-3170]] took that constructor out**, along with SchedulingActions.createBundle(title:…)
    /// and the quick-create popover's Block tab, so `CadenceTaskBundleMutationSupport.swift`,
    /// `SchedulingService.swift` and `QuickCreateChoicePopover.swift` mint no title and have left
    /// this list; `noNewSurfaceTypesTheRetiredBundleNounEither` still sweeps all three.
    @Test func noSurfaceStillTypesTheRetiredBundleNoun() throws {
        for path in [
            // [[T-3170]]'s trio pass took two entries out: `TimelineBundleBlockSupportViews.swift`
            // is deleted, and `CadenceTaskMutationSupport.swift` read `defaultDisplayTitle` only
            // inside `insertBundle`, which went with it. The two views left draw no Block now;
            // their display-title reads are a task draft's and an event's, and they stay listed
            // for the half that matters -- neither types "Task Bundle".
            "Cadence/Models/AppTask.swift",
            "Cadence/macOS/Views/TimelineDayCanvas.swift",
            "Cadence/macOS/Views/CalendarPageMonthSupportViews.swift",
        ] {
            let source = try CadenceCommitSurfaceScan.scanned(path)
            #expect(
                CadenceSourceScan.matchCount(#""Task Bundle""#, in: source) == 0,
                "\(path) still types the retired bundle noun"
            )
            #expect(
                CadenceSourceScan.matchCount(
                    #"TaskBundle\.(defaultDisplayTitle|storedTitle)|\bdisplayTitle\b"#,
                    in: source
                ) >= 1,
                "\(path) reads neither the shared constant nor the model's own display title"
            )
        }

        // Non-vacuity for the stripper these reads go through: it blanks a comment and keeps a
        // string literal, which is exactly what an assertion about a literal needs.
        let raw = try CadenceSourceScan.sourceFile("Cadence/Models/AppTask.swift")
        let stripped = CadenceSourceScan.strippingComments(raw)
        #expect(raw.contains("the *type's* name"), "the tombstone comment this pins is gone")
        #expect(!stripped.contains("the *type's* name"))
        #expect(stripped.contains(#"static let defaultDisplayTitle = "Block""#))
    }

    /// T-567's first half, and the reason the fallback was reachable from a create form at all:
    /// `canCreate` returned `true` unconditionally for `.bundle` while Task and Event both
    /// required a title, so two taps on an empty slot made a block the user had not named. The
    /// `.bundle` arm is gone ([[T-3170]]); what is left is that both remaining arms ask.
    ///
    /// Scoped to the `canCreate` body rather than the file: `showsTimedControls` below has its own
    /// `case .task: return hasTime`, which is correct and must stay outside this read.
    @Test func theIOSQuickCreateSheetAsksForATitleForEveryKindItCreates() throws {
        let source = try CadenceCommitSurfaceScan.scanned("Cadence/iOS/iOSCalendarQuickCreateSheet.swift")
        let anchor = try #require(source.range(of: "var canCreate: Bool"))
        let body = try #require(
            CadenceSourceScan.matchedBody(after: anchor.upperBound, in: source, open: "{", close: "}")
        )

        #expect(CadenceSourceScan.matchCount(#"return true"#, in: body) == 0)
        #expect(CadenceSourceScan.matchCount(#"TaskTitleSupport\.isEmpty\(title\)"#, in: body) == 1)
        #expect(CadenceSourceScan.matchCount(#"\.trimmingCharacters\(in: \.whitespacesAndNewlines\)\.isEmpty"#, in: body) == 1)
        #expect(CadenceSourceScan.matchCount(#"case \.(task|bundle|event):"#, in: body) == 2)
        #expect(CadenceSourceScan.matchCount(#"case \.bundle:"#, in: body) == 0)

        // The read really was one declaration's body, and not the whole file. The negative used
        // to be `showsTimedControls`/`isTimed`'s own `case .task: return hasTime`; [[T-3171]]'s
        // seventh adoption slice deleted that pair when the sheet moved to the capture
        // presentation, whose `CadenceCaptureKindMemory` remembers each kind's draft instead. The
        // discriminator follows to a sibling that is still there: the two writes in `create()`,
        // which switch on the same `draft.kind` this body does and must stay outside this read.
        #expect(!body.contains("hasTime"))
        #expect(!body.contains("iOSScheduleDraftCreation.createTask("))
        #expect(
            CadenceSourceScan.matchCount(#"case \.task:\s*failure = iOSScheduleDraftCreation\.createTask\("#, in: source) == 1,
            "create() no longer holds the negative this scan is discriminated against"
        )
    }

    /// **T-843.** T-567 gave the untitled-block fallback one home and left the rest of the "Block"
    /// vocabulary to be re-typed by hand — which is exactly how "Bundle" came back at eleven sites
    /// across nine files. All eleven read one of the constants added beside `defaultDisplayTitle`
    /// above; [[T-3170]] has since removed the Focus and quick-create surfaces among them, leaving
    /// the block inspector sheet, `TimelineBundleBlock` and `TimelineBundleBlockSupportViews` --
    /// and its trio pass then deleted both of those files, along with
    /// `TaskBundlePickerSupportViews`, whose `existingBundle` interpolation was the one false
    /// positive this sweep exempted.
    ///
    /// This is the forward guard for a twelfth: every `.swift` file under the three product roots,
    /// comment-stripped so a doc comment cannot trip it, checked for a string literal containing
    /// "Bundle". A literal at any site not named in `allowedLiteralsByPath` below is the noun
    /// drifting back, and this goes red.
    ///
    /// The survivors are all technical, not product vocabulary, which is the line T-843 draws:
    /// SwiftData's schema-entity key (`"TaskBundle"`), a debug-only `assertionFailure` no user
    /// reads, the drag-payload's internal `"taskBundle:"` prefix, two Info.plist keys read through
    /// `Bundle.main`, and
    /// Settings' technical **"Bundle ID"** on both platforms — the ticket's explicit exemption.
    @Test func noNewSurfaceTypesTheRetiredBundleNounEither() throws {
        let allowedLiteralsByPath: [String: Set<String>] = [
            "Cadence/Services/CadenceDataExportService.swift": [
                "\"TaskBundle\""
            ],
            // The importer reads the same schema-entity key the exporter writes, in the
            // per-table validation errors and the destination index. Technical, not vocabulary:
            // it names a SwiftData entity in a diagnostic, and never reaches a surface.
            "Cadence/Services/CadenceArchiveImportService.swift": [
                "\"TaskBundle\""
            ],
            "Cadence/Shared/TaskDragPayload.swift": [
                "\"taskBundle:\""
            ],
            "Cadence/Shared/AppStoreReviewReadiness.swift": [
                "\"CFBundleShortVersionString\"",
                "\"CFBundleVersion\""
            ],
            "Cadence/iOS/iOSSettingsOverviewSections.swift": [
                "\"Bundle ID\""
            ],
            "Cadence/macOS/Views/SettingsAboutSection.swift": [
                "\"Bundle ID\""
            ],
        ]

        // Not `CadenceCommitSurfaceScan.scanned`: its `raw.count > 400` guard is right for a
        // single named file the caller knows is substantial, and wrong here — a bulk sweep over
        // every product file legitimately includes small ones, and that floor would report each
        // as a scan failure rather than as "no Bundle literal found", which is a false red.
        let readStripped = CadenceSourceScan.strippedSourceReader()
        var filesScanned = 0
        var offenders: [String: [String]] = [:]
        for root in ["Cadence", "CadenceWidgets", "CadenceMCPServer"] {
            for path in try CadenceSourceScan.swiftFiles(under: root) {
                filesScanned += 1
                let stripped = try readStripped(path)
                let literals = Set(
                    CadenceSourceScan.captures(#"("[^"\n]*Bundle[^"\n]*")"#, in: stripped)
                        .map(\.text)
                )
                let allowed = allowedLiteralsByPath[path] ?? []
                let unexpected = literals.subtracting(allowed)
                if !unexpected.isEmpty {
                    offenders[path] = unexpected.sorted()
                }
            }
        }

        #expect(filesScanned >= 300, "swept only \(filesScanned) files — the walk found nothing")
        #expect(offenders.isEmpty, "unexpected \"Bundle\" literal(s): \(offenders)")

        // Non-vacuity: an exempted literal really is still present, so the sweep is reading real
        // files rather than silently matching zero and passing by construction.
        let exportSource = try CadenceCommitSurfaceScan.scanned(
            "Cadence/Services/CadenceDataExportService.swift"
        )
        #expect(exportSource.contains(#""TaskBundle""#))
    }
}
#endif
