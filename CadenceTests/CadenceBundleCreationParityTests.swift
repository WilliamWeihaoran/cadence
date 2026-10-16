import Foundation
import SwiftData
import Testing
@testable import Cadence

#if os(macOS)
/// T-190: "drop a task on a task and the two become a block" existed only on the Mac timeline.
/// SchedulingActions.createBundle(from:adding:) sat inside `#if os(macOS)` in a file that imports
/// no AppKit, so the gesture was macOS-only by accident rather than by anything about the platform.
/// The mutation is now `try CadenceTaskMutationSupport.insertBundle(from:adding:)` in `Shared/`; the Mac
/// delegates to it and iOS's Calendar Board calls it.
///
/// **The ticket's premise was already false when this was written, and that is worth recording.**
/// It said `TaskBundle(` is constructed "only at `macOS/Services/SchedulingService.swift:32` and
/// `:125`" and that iOS "never creates" bundles. There was a third constructor in
/// `Shared/CadenceTaskMutationSupport.insertBundle(title:…)`, unguarded, which
/// `iOSCalendarQuickCreateSheet` has been calling from its `Block` segment all along. What was
/// genuinely missing was only this one gesture.
///
/// **Two kinds of test here.** The behavioural half runs the real mutation, which is reachable
/// because it lives in `Shared/`. The source half pins that iOS *reaches* it: `Cadence/iOS/` is
/// entirely inside `#if os(iOS)` and this target builds for macOS, so there is no iOS symbol to
/// reference and a source scan is the only tool. Per T-161 the wiring is what gets pinned, not just
/// the helper — a shared mutation with no call site is exactly the shape this ticket describes.
///
/// **[[T-3170]] retired the gesture on two of its three surfaces.** The Mac timeline
/// (`TimelineTaskBlock`'s "drop here to bundle" shelf and the canvas's formBundle) and the
/// iOS day timeline (`iOSTimelineTaskBlock`'s drag and drop, `iOSCalendarTimelineGrid.formBundle`)
/// no longer form a Block, and `SchedulingActions`' two Mac spellings went with their only caller.
/// What a drop of a task on a task does now differs by surface, because each surface already had
/// a different thing underneath it: on the Mac the block has no drop target of its own, so the
/// release falls through to the canvas's reschedule drop; on the iOS timeline the column has no
/// drop target at all, so the block is no longer draggable and nothing is accepted. iOS's Calendar
/// *Board* still calls the shared mutation — that file is Codex-leased — so the mutation and its
/// behavioural pins stay, and so do the Board's wiring pins.
@MainActor
struct CadenceBundleCreationParityTests {

    // MARK: - Fixtures

    private func scheduledTask(_ title: String, dateKey: String, startMin: Int, estimate: Int) -> AppTask {
        let task = AppTask(title: title)
        task.scheduledDate = dateKey
        task.scheduledStartMin = startMin
        task.estimatedMinutes = estimate
        return task
    }

    // MARK: - The shared mutation

    @Test func droppingATaskOnAScheduledTaskFormsABlockHoldingBoth() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let target = scheduledTask("Target", dateKey: "2026-08-21", startMin: 600, estimate: 25)
        let dragged = scheduledTask("Dragged", dateKey: "2026-08-24", startMin: 300, estimate: 10)
        context.insert(target)
        context.insert(dragged)

        let bundle = try #require(
            try CadenceTaskMutationSupport.insertBundle(from: target, adding: dragged, modelContext: context)
        )

        #expect(bundle.dateKey == "2026-08-21")
        #expect(bundle.startMin == 600)
        #expect(bundle.durationMinutes == 35)
        // The card that was dropped *on* supplies the slot; the dragged task comes to it, which is
        // why its own date and time are overwritten rather than negotiated.
        #expect(bundle.sortedTasks.map(\.title) == ["Target", "Dragged"])
        #expect(target.scheduledStartMin == -1)
        #expect(dragged.scheduledDate == "2026-08-21")
        #expect(dragged.scheduledStartMin == -1)
        #expect(dragged.bundle?.id == bundle.id)
    }

    /// A `TaskBundle` *is* a timeline block — a day plus a start minute. A target that has neither,
    /// or has a day but no time of day, has nothing for a block to sit on, so the drop is refused
    /// rather than resolved by inventing a start minute on one platform that the other refuses to.
    @Test func aDropThatCannotBecomeABlockIsRefusedRatherThanGuessedAt() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)

        let sameTask = scheduledTask("Only one", dateKey: "2026-08-21", startMin: 600, estimate: 30)
        context.insert(sameTask)
        #expect(try CadenceTaskMutationSupport.insertBundle(from: sameTask, adding: sameTask, modelContext: context) == nil)

        let undated = AppTask(title: "No day")
        let dragged = scheduledTask("Dragged", dateKey: "2026-08-21", startMin: 600, estimate: 10)
        context.insert(undated)
        context.insert(dragged)
        #expect(try CadenceTaskMutationSupport.insertBundle(from: undated, adding: dragged, modelContext: context) == nil)

        let doDatedOnly = AppTask(title: "Day but no slot")
        doDatedOnly.scheduledDate = "2026-08-21"
        doDatedOnly.scheduledStartMin = -1
        context.insert(doDatedOnly)
        #expect(try CadenceTaskMutationSupport.insertBundle(from: doDatedOnly, adding: dragged, modelContext: context) == nil)

        #expect(try context.fetch(FetchDescriptor<TaskBundle>()).isEmpty)
    }

    /// The members' own slots are gone once the bundle owns the block, so any stale calendar link
    /// they still carry goes with them. `SchedulingActions.addTask` always did this;
    /// `CadenceTaskMutationSupport.addTask` — the copy iOS's board has been calling — did not, and
    /// that was the one field on which the two platforms' add-to-bundle paths disagreed.
    @Test func formingABlockClearsStaleCalendarLinksOnBothMembers() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let target = scheduledTask("Target", dateKey: "2026-08-21", startMin: 600, estimate: 20)
        let dragged = scheduledTask("Dragged", dateKey: "2026-08-21", startMin: 660, estimate: 20)
        target.calendarEventID = "stale-target"
        dragged.calendarEventID = "stale-dragged"
        context.insert(target)
        context.insert(dragged)

        _ = try CadenceTaskMutationSupport.insertBundle(from: target, adding: dragged, modelContext: context)

        #expect(target.calendarEventID.isEmpty)
        #expect(dragged.calendarEventID.isEmpty)
    }

    /// The one deliberate behaviour change the extraction makes. macOS took `targetTask.scheduledStartMin`
    /// unclamped, so a corrupt slot near midnight produced a block ending after the day did — while
    /// its sibling `insertBundle(title:…)` in the same shared enum clamped. Both clamp now.
    @Test func formingABlockClampsAStartMinuteThatWouldOverflowTheDay() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let target = scheduledTask("Late", dateKey: "2026-08-21", startMin: 1439, estimate: 25)
        let dragged = scheduledTask("Later", dateKey: "2026-08-21", startMin: 1439, estimate: 10)
        context.insert(target)
        context.insert(dragged)

        let bundle = try #require(
            try CadenceTaskMutationSupport.insertBundle(from: target, adding: dragged, modelContext: context)
        )

        #expect(bundle.startMin == 1435)
        #expect(bundle.durationMinutes == 5)
        #expect(bundle.endMin == CadenceTaskMutationSupport.bundleDayEndMin)
    }

    /// `AppTask.estimatedMinutes` defaults to 30, so the floor only shows on a task whose estimate
    /// was explicitly cleared or set very low — which is exactly the case that would otherwise
    /// produce a block too short to see or hit.
    @Test func everyMemberGetsAtLeastTheMinimumSlotSoATinyBlockIsStillHittable() {
        let tiny = [AppTask(title: "A"), AppTask(title: "B")]
        tiny[0].estimatedMinutes = 0
        tiny[1].estimatedMinutes = 2
        #expect(CadenceTaskMutationSupport.bundleDuration(startingAt: 600, tasks: tiny) == 10)

        let mixed = [AppTask(title: "A"), AppTask(title: "B")]
        mixed[0].estimatedMinutes = 45
        mixed[1].estimatedMinutes = 0
        #expect(CadenceTaskMutationSupport.bundleDuration(startingAt: 600, tasks: mixed) == 50)

        // An empty block gets the floor rather than zero height.
        #expect(CadenceTaskMutationSupport.bundleDuration(startingAt: 600, tasks: []) == 5)
    }

    /// `Shared/` cannot see `TimelineDayRange` — it lives in `macOS/Views/TimelineMetrics.swift` and
    /// `Shared/` does not compile the timeline — so the day bounds are spelled twice on purpose.
    /// This is the seam that keeps them equal. The timeline clamp already existed four times with
    /// three different bounds once; a second silent divergence is not worth the risk of a doc note.
    @Test func theSharedBundleClampsMatchTheTimelineDayRange() {
        #expect(CadenceTaskMutationSupport.bundleDayEndMin == TimelineDayRange.endMin)
        #expect(CadenceTaskMutationSupport.bundleMinimumDuration == TimelineDayRange.minimumDuration)
        #expect(CadenceTaskMutationSupport.clampedBundleStart(1439) == TimelineDayRange.clampStart(1439))
        #expect(CadenceTaskMutationSupport.clampedBundleStart(-7) == TimelineDayRange.clampStart(-7))
    }

    // MARK: - [[T-3170]]: the gesture is gone from both timelines

    /// The Mac's spellings had one caller, the timeline canvas, and went with it. The shared mutation
    /// is what survives, for the Board alone.
    @Test func theMacTimelineNoLongerFormsABlockFromATaskDroppedOnATask() throws {
        let service = try strippingBundleTestComments(sourceFile("Cadence/macOS/Services/SchedulingService.swift"))
        #expect(occurrences(of: "func createBundle(", in: service) == 0)
        #expect(occurrences(of: "func insertBundle(", in: service) == 0)
        #expect(occurrences(of: "BundleMembership", in: service) == 0)

        let canvas = try strippingBundleTestComments(sourceFile("Cadence/macOS/Views/TimelineDayCanvas.swift"))
        #expect(occurrences(of: "formBundle", in: canvas) == 0)
        #expect(occurrences(of: "bundleCreateFailed", in: canvas) == 0)
        #expect(occurrences(of: "onCreateBundleFromTasks", in: canvas) == 0)

        let layers = try strippingBundleTestComments(sourceFile("Cadence/macOS/Views/TimelineDayCanvasSupportLayers.swift"))
        #expect(occurrences(of: "onCreateBundleFromTasks", in: layers) == 0)
        #expect(occurrences(of: "onCreateBundleWithTask", in: layers) == 0)

        let block = try strippingBundleTestComments(sourceFile("Cadence/macOS/Views/TimelineTaskBlock.swift"))
        #expect(occurrences(of: "TimelineTaskBundleDropShelf", in: block) == 0)
        #expect(occurrences(of: "TimelineTaskBundleDropDelegate", in: block) == 0)
        #expect(occurrences(of: "Drop here to bundle", in: block) == 0)
        // Non-vacuity: this is still the block that lifts a task off the canvas.
        #expect(occurrences(of: "struct TimelineTaskBlock: View", in: block) == 1)
        #expect(occurrences(of: ".onDrag {", in: block) == 1)
    }

    /// **The chosen behaviour on the Mac: a task released over a task is rescheduled.** The block
    /// carries no `.onDrop` any more, so the release reaches the canvas's `TimelineDropDelegate`,
    /// and the only thing that delegate ever stood aside for — a bundle shelf's rect — is now an
    /// empty set. Its task arm is guarded on `!landedOnBundleShelf`, which an empty set can never
    /// make true, so the payload goes to `onDropTaskAtMinute` like any other release.
    @Test func onTheMacATaskDroppedOnATaskFallsThroughToTheRescheduleDrop() throws {
        let block = try strippingBundleTestComments(sourceFile("Cadence/macOS/Views/TimelineTaskBlock.swift"))
        #expect(occurrences(of: ".onDrop(", in: block) == 0)

        let canvas = try strippingBundleTestComments(sourceFile("Cadence/macOS/Views/TimelineDayCanvas.swift"))
        #expect(occurrences(of: "bundleShelfFrames: [],", in: canvas) == 1)
        #expect(occurrences(of: "bundleShelfFrames:", in: canvas) == 1)
        #expect(occurrences(of: "onDropTaskAtMinute: onDropTaskAtMinute,", in: canvas) == 1)

        // The delegate's own guard, read rather than assumed: the task arm is the reschedule, and
        // it yields only to a shelf rect.
        let delegate = try strippingBundleTestComments(sourceFile("Cadence/macOS/Views/TimelineDropInteractionSupport.swift"))
        #expect(occurrences(of: "blockedFrames: bundleShelfFrames", in: delegate) == 1)
        #expect(occurrences(of: "!landedOnBundleShelf, let uuid = taskID(from: payloadString)", in: delegate) == 1)
        #expect(occurrences(of: "onDropTaskAtMinute(task, startMin)", in: delegate) == 1)

        // And the geometry that guard asks: with no shelf rects, no point on the canvas — the top
        // of a block where the shelf used to sit included — is inside one.
        for point in [CGPoint(x: 0, y: 0), CGPoint(x: 120, y: 540), CGPoint(x: 299, y: 1_439)] {
            #expect(!TimelineMetricsSupport.isInsideBlockedBlock(point: point, blockedFrames: []))
        }
    }

    /// **The chosen behaviour on the iOS day timeline: the drop is not accepted.** The day column has
    /// no `dropDestination` of its own, so with the block-forming drop gone there is nothing for a
    /// lift to land on — and the block stops offering the lift rather than offering a drag that
    /// does nothing.
    @Test func theDayTimelineNoLongerFormsABlockAndAcceptsNoTaskDrop() throws {
        let source = try strippingBundleTestComments(sourceFile("Cadence/iOS/iOSCalendarTimelineViews.swift"))

        #expect(occurrences(of: "CadenceTaskMutationSupport.insertBundle(", in: source) == 0)
        #expect(occurrences(of: "TaskBundle(", in: source) == 0)
        #expect(occurrences(of: "formBundle", in: source) == 0)
        #expect(occurrences(of: "onFormBundleFromTasks", in: source) == 0)
        #expect(occurrences(of: "bundleFormingDrop", in: source) == 0)
        #expect(occurrences(of: "iOSBundleFormingDrop", in: source) == 0)
        #expect(occurrences(of: "bundleCreateFailed", in: source) == 0)
        #expect(occurrences(of: ".draggable(", in: source) == 0)
        #expect(occurrences(of: ".dropDestination(", in: source) == 0)
        // Non-vacuity: the block and the column are still here, and still drawn.
        #expect(occurrences(of: "struct iOSTimelineTaskBlock: View", in: source) == 1)
        #expect(occurrences(of: "iOSTimelineTaskBlock(", in: source) == 1)
    }

    // MARK: - The wiring (source scans)

    /// An exact count. `SchedulingService` used to construct one legitimate `TaskBundle` in
    /// createBundle(title:dateKey:startMin:endMin:), the drag-out-a-range gesture, and the count
    /// was 1; [[T-3170]] removed that gesture, so the count is 0. The task-onto-task path's one
    /// forward to the shared mutation went in [[T-3170]]'s next pass, so that count is 0 too.
    @Test func theMacTimelineNoLongerKeepsItsOwnBundleFormingBody() throws {
        let source = try strippingBundleTestComments(sourceFile("Cadence/macOS/Services/SchedulingService.swift"))

        #expect(occurrences(of: "TaskBundle(", in: source) == 0)
        #expect(occurrences(of: "CadenceTaskMutationSupport.insertBundle(", in: source) == 0)
        // The arithmetic went with the body rather than being left behind unused.
        #expect(occurrences(of: "clampedBundleDuration", in: source) == 0)
    }

    /// **The Calendar Board is the last surface to lose the gesture ([[T-3170]]).** It was the one
    /// T-190 built the shared mutation *for*; with the Block feature gone the board forms nothing,
    /// offers no opt-in and names no refusal, and a task dropped on a card falls through to the
    /// column's own reschedule.
    @Test func thecalendarBoardNoLongerFormsABlockFromATaskDroppedOnACard() throws {
        let board = try strippingBundleTestComments(sourceFile("Cadence/iOS/iOSCalendarBoardView.swift"))
        let cards = try strippingBundleTestComments(sourceFile("Cadence/iOS/iOSBoardCards.swift"))

        for source in [board, cards] {
            #expect(occurrences(of: "CadenceTaskMutationSupport.insertBundle(", in: source) == 0)
            #expect(occurrences(of: "TaskBundle(", in: source) == 0)
            #expect(occurrences(of: "formBundle", in: source) == 0)
            #expect(occurrences(of: "bundleFormingDrop", in: source) == 0)
            #expect(occurrences(of: "iOSBundleFormingDrop", in: source) == 0)
            #expect(occurrences(of: "bundleCreateFailed", in: source) == 0)
        }
        // The Block card itself is gone, and with it the only other nested drop target a column
        // card could own — so the column arbitrates nothing and suppresses nothing.
        #expect(occurrences(of: "iOSCalendarBoardBundleCard", in: cards) == 0)
        #expect(occurrences(of: "nestedDropTargetID", in: board) == 0)
        #expect(occurrences(of: "recentlyBundledTaskID", in: board) == 0)
        // Non-vacuity: the column and its task card are still here, and the day drop still works.
        #expect(occurrences(of: "struct iOSCalendarBoardDayColumn: View", in: board) == 1)
        #expect(occurrences(of: "onDropTaskOnDay(task)", in: board) == 1)
        #expect(occurrences(of: "struct iOSBoardTaskCard: View", in: cards) == 1)
    }

    /// **Today's schedule pane draws no block of its own at all, which is the stronger form of the
    /// same decision.**
    ///
    /// It used to draw `iOSTimelineTaskBlock` itself, stacked inside hour rows, and was deliberately
    /// passed no `bundleFormingDrop`: the opt-in is an `if let` rather than an always-on closure
    /// returning `false` because `isTargeted` fires whether or not a drop is accepted, so an
    /// always-attached version would light up blocks on a pane with nothing to bundle them with.
    ///
    /// [[T-3081]] replaced the hour rows with `iOSCalendarTimelineGrid` pinned to today, so the
    /// pane now builds no block, installs no recognizer and makes no opt-in decision — the grid
    /// does, once, for both of its spans. The assertion is therefore the same three absences plus a
    /// fourth, and the non-vacuity moves to the grid the pane builds. Since [[T-3170]] the grid
    /// installs no drag mesh either (`theDayTimelineNoLongerFormsABlockAndAcceptsNoTaskDrop`).
    @Test func todaysSchedulePaneInstallsNoDragMeshOfItsOwn() throws {
        let source = try strippingBundleTestComments(sourceFile("Cadence/iOS/iOSTodaySchedulePanel.swift"))

        #expect(occurrences(of: "bundleFormingDrop", in: source) == 0)
        #expect(occurrences(of: ".draggable(", in: source) == 0)
        #expect(occurrences(of: ".dropDestination(", in: source) == 0)
        #expect(occurrences(of: "iOSTimelineTaskBlock(", in: source) == 0)
        // Non-vacuity: it really does draw the grid.
        #expect(occurrences(of: "iOSCalendarTimelineGrid(", in: source) == 1)
    }

    // [[T-3170]] retired `aTaskCardClaimingADragSuppressesTheDayDropTheSameWayABundleCardDoes`.
    // It pinned the column's nested-drop-target arbitration, which existed only because a Block
    // card and a block-forming task card could claim a drag. Neither can, so the column reads
    // every release as the reschedule it is — pinned by the absence test above.

    /// Non-vacuity. Every absence assertion above passes trivially against an empty string, so the
    /// reader itself is checked: a needle that is certainly present must be found, and a needle that
    /// is certainly absent must not be.
    @Test func theSourceReaderActuallyReadsTheseFilesInBundleCreationParity() throws {
        for path in [
            "Cadence/macOS/Services/SchedulingService.swift",
            "Cadence/iOS/iOSCalendarBoardView.swift",
            "Cadence/iOS/iOSBoardCards.swift",
            "Cadence/iOS/iOSCalendarTimelineViews.swift",
            "Cadence/iOS/iOSTodaySchedulePanel.swift",
            "Cadence/macOS/Views/TimelineDayCanvas.swift",
            "Cadence/macOS/Views/TimelineDayCanvasSupportLayers.swift",
            "Cadence/macOS/Views/TimelineTaskBlock.swift",
            "Cadence/macOS/Views/TimelineDropInteractionSupport.swift"
        ] {
            let source = try strippingBundleTestComments(sourceFile(path))
            #expect(source.count > 2_000)
            #expect(source.contains("import SwiftUI"))
            #expect(occurrences(of: "ThisSymbolDoesNotExistAnywhere", in: source) == 0)
        }

        // Comment stripping works, and it is what makes the counts above read code rather than the
        // prose around it — every one of these files documents the gesture in comments that name
        // the same symbols.
        let stripped = try strippingBundleTestComments("let a = 1 // TaskBundle(\n/* TaskBundle( */ let b = 2")
        #expect(occurrences(of: "TaskBundle(", in: stripped) == 0)
        #expect(stripped.contains("let a = 1"))
        #expect(stripped.contains("let b = 2"))
    }
}

private func bundleTestRepositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func sourceFile(_ relativePath: String) throws -> String {
    try String(contentsOf: bundleTestRepositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
}

/// Non-overlapping count. Deliberately a count and not a `contains`: several of the assertions
/// above need to say "this call site exists exactly once" or "the second body is gone while the
/// first survives", and neither is expressible with membership.
private func occurrences(of needle: String, in haystack: String) -> Int {
    guard !needle.isEmpty else { return 0 }
    var count = 0
    var searchStart = haystack.startIndex
    while searchStart < haystack.endIndex,
          let range = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
        count += 1
        searchStart = range.upperBound
    }
    return count
}

/// Blanks `//` and `/* */` comments so the counts above read code rather than the prose around it.
/// Crude on purpose: a `//` inside a string literal is blanked too, which can only ever make these
/// checks stricter about what counts as a comment, never looser about live code.
private func strippingBundleTestComments(_ source: String) throws -> String {
    // T-1269/T-1270: one pass per pattern, in CadenceSourceScan, on the guarded
    // `(?<!:)//` that the slashes in a URL cannot trigger.
    return CadenceSourceScan.strippingComments(source)
}
#endif
