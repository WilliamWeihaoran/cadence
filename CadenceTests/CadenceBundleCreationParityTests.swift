import Foundation
import SwiftData
import Testing
@testable import Cadence

#if os(macOS)
/// T-190: "drop a task on a task and the two become a block" existed only on the Mac timeline.
/// `SchedulingActions.createBundle(from:adding:)` sat inside `#if os(macOS)` in a file that imports
/// no AppKit, so the gesture was macOS-only by accident rather than by anything about the platform.
/// The mutation is now `CadenceTaskMutationSupport.insertBundle(from:adding:)` in `Shared/`; the Mac
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
            CadenceTaskMutationSupport.insertBundle(from: target, adding: dragged, modelContext: context)
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
        #expect(CadenceTaskMutationSupport.insertBundle(from: sameTask, adding: sameTask, modelContext: context) == nil)

        let undated = AppTask(title: "No day")
        let dragged = scheduledTask("Dragged", dateKey: "2026-08-21", startMin: 600, estimate: 10)
        context.insert(undated)
        context.insert(dragged)
        #expect(CadenceTaskMutationSupport.insertBundle(from: undated, adding: dragged, modelContext: context) == nil)

        let doDatedOnly = AppTask(title: "Day but no slot")
        doDatedOnly.scheduledDate = "2026-08-21"
        doDatedOnly.scheduledStartMin = -1
        context.insert(doDatedOnly)
        #expect(CadenceTaskMutationSupport.insertBundle(from: doDatedOnly, adding: dragged, modelContext: context) == nil)

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

        _ = CadenceTaskMutationSupport.insertBundle(from: target, adding: dragged, modelContext: context)

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
            CadenceTaskMutationSupport.insertBundle(from: target, adding: dragged, modelContext: context)
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

    /// The Mac's spelling stays — the timeline reads better in `SchedulingActions`' vocabulary — but
    /// it must forward rather than keep a body, or the two platforms drift again.
    @Test func theMacGestureStillProducesTheSameBlockThroughTheSharedMutation() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let target = scheduledTask("Target", dateKey: "2026-08-21", startMin: 600, estimate: 25)
        let dragged = scheduledTask("Dragged", dateKey: "2026-08-21", startMin: 630, estimate: 10)
        context.insert(target)
        context.insert(dragged)

        let bundle = try #require(SchedulingActions.createBundle(from: target, adding: dragged, in: context))

        #expect(bundle.startMin == 600)
        #expect(bundle.durationMinutes == 35)
        #expect(bundle.sortedTasks.map(\.title) == ["Target", "Dragged"])
    }

    // MARK: - The wiring (source scans)

    /// An exact count, not an absence: `SchedulingService` legitimately still constructs a
    /// `TaskBundle` in `createBundle(title:dateKey:startMin:endMin:)`, the drag-out-a-range gesture.
    /// What must be gone is the *second* one, in the task-onto-task path. An `!contains` assertion
    /// here would fail on the surviving legitimate call and a `contains` would pass either way, so
    /// the count is the only spelling that says what is meant.
    @Test func theMacTimelineNoLongerKeepsItsOwnBundleFormingBody() throws {
        let source = try strippingBundleTestComments(sourceFile("Cadence/macOS/Services/SchedulingService.swift"))

        #expect(occurrences(of: "TaskBundle(", in: source) == 1)
        #expect(occurrences(of: "CadenceTaskMutationSupport.insertBundle(", in: source) == 1)
        // The arithmetic went with the body rather than being left behind unused.
        #expect(occurrences(of: "clampedBundleDuration", in: source) == 0)
    }

    /// The point of the ticket. A shared mutation with no iOS call site is the defect, not the fix.
    @Test func theCalendarBoardWiresTheSharedBundleFormingMutation() throws {
        let source = try strippingBundleTestComments(sourceFile("Cadence/iOS/iOSCalendarBoardView.swift"))

        #expect(occurrences(of: "CadenceTaskMutationSupport.insertBundle(from:", in: source) == 1)
        #expect(occurrences(of: "bundleFormingDrop:", in: source) == 1)
        // The board must not grow its own `TaskBundle(` — that would be the near-copy this ticket
        // exists to avoid.
        #expect(occurrences(of: "TaskBundle(", in: source) == 0)
    }

    /// The card offers the gesture only where a block can sit, so a do-dated-only card declines and
    /// the day column still reads the release as the reschedule it is. Without this guard the drop
    /// would light up amber and then silently do nothing, because the shared mutation returns `nil`.
    @Test func theBoardOffersTheGestureOnlyOnCardsThatOccupyASlot() throws {
        let source = try strippingBundleTestComments(sourceFile("Cadence/iOS/iOSCalendarBoardView.swift"))

        #expect(source.contains("guard task.scheduledStartMin >= 0 else { return nil }"))
        #expect(occurrences(of: "iOSBoardTaskCardBundleDrop(", in: source) == 1)
    }

    /// A nested card that claimed the drag has to tell the column, or the column's own
    /// `dropDestination` reads the same release as a drop onto the day and reschedules the task out
    /// of the block it was just put in. The bundle card already needed this; a task card needs the
    /// identical thing, so the state is named for the mechanism rather than for one of its users.
    @Test func aTaskCardClaimingADragSuppressesTheDayDropTheSameWayABundleCardDoes() throws {
        let source = try strippingBundleTestComments(sourceFile("Cadence/iOS/iOSCalendarBoardView.swift"))

        #expect(occurrences(of: "nestedDropTargetID", in: source) == 5)
        #expect(occurrences(of: "updateNestedDropTarget(", in: source) == 3)
        // The bundle-specific name is gone rather than surviving beside the general one.
        #expect(occurrences(of: "targetedBundleID", in: source) == 0)
    }

    /// Non-vacuity. Every absence assertion above passes trivially against an empty string, so the
    /// reader itself is checked: a needle that is certainly present must be found, and a needle that
    /// is certainly absent must not be.
    @Test func theSourceReaderActuallyReadsTheseFiles() throws {
        for path in [
            "Cadence/macOS/Services/SchedulingService.swift",
            "Cadence/iOS/iOSCalendarBoardView.swift",
            "Cadence/iOS/iOSBoardCards.swift"
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
    var result = source
    for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            result.replaceSubrange(
                range,
                with: String(repeating: " ", count: result.distance(from: range.lowerBound, to: range.upperBound))
            )
        }
    }
    return result
}
#endif
