import CoreGraphics
import Foundation
import Testing
@testable import Cadence

/// **What a create-task drop target has to survive** (T-3008).
///
/// The defect this suite exists for was found by dragging the `+` on a phone, not by reading
/// source, and it was invisible in every way a test had been looking. Drop the `+` on the
/// `UI TEST WORKSPACE` eyebrow in the Tasks index and you get a **New List** in that context,
/// which is right. Tap a list, tap back, repeat the identical drag, and you get an unscoped
/// **New task** in **Inbox** — not a wrong target, *no* target: `candidates()` returned an empty
/// array, and it did so for every row, header and region on the surface, for the rest of the
/// session. Nothing errored and nothing looked different; the `+` still opened a composer.
///
/// **Why one push and back was enough.** A target publishes three things and they do not come back
/// together. `setPlacement` and `setLive` are `.onChange(…, initial: true)`, so a restored copy
/// re-runs them by itself. `setFrame` is `onGeometryChange`, which reports a *change* — and a
/// surface that comes back has rows in exactly the places they were, so it never fires again. The
/// `onDisappear` SwiftUI sends while tearing the pre-pop copy down was deleting the frame, which is
/// the one fact nothing would ever republish. The registry was left holding a healthy-looking
/// placement, a healthy-looking liveness flag, and no way to be a candidate again.
///
/// That is the argument `iOSNewTaskDropTargetsAreLive` already makes one level up, and the file
/// that holds it had written the argument down — for liveness — while leaving `onDisappear`
/// exposed to the identical one.
///
/// **Why this suite can exist at all.** `Cadence/iOS/` is behind `#if os(iOS)` and this target
/// builds on macOS, so the bookkeeping moved to `CadenceNewTaskDropFrameStore` in Shared with the
/// fix. The surface's only previous view-layer pin was a source scan over the keys each layer
/// registers — which is true both before and after the bug, and is why a defect reaching every
/// drop surface in the app survived a full green run.
struct CadenceNewTaskDropRegistrationTests {

    // MARK: - Fixtures

    /// A row, a section header and the region under them: the three layers of the iPad/iPhone
    /// sidebar, nested the way `CadenceCaptureDropHitTest` expects, smallest last.
    private enum Surface {
        static let region = CGRect(x: 0, y: 120, width: 393, height: 600)
        static let section = CGRect(x: 8, y: 280, width: 377, height: 180)
        static let row = CGRect(x: 16, y: 310, width: 361, height: 44)

        static let regionKey = "newlist:"
        static let sectionKey = "newlist:11111111-1111-1111-1111-111111111111"
        static let rowKey = "list:a_22222222-2222-2222-2222-222222222222"
    }

    /// Registers the three layers exactly as the modifier does on a first appearance: a frame, a
    /// placement, and liveness.
    private static func seedSidebar(
        into store: inout CadenceNewTaskDropFrameStore
    ) -> (region: UUID, section: UUID, row: UUID) {
        let ids = (region: UUID(), section: UUID(), row: UUID())
        let layers = [
            (ids.region, Surface.region, Surface.regionKey, ""),
            (ids.section, Surface.section, Surface.sectionKey, "UI Test Workspace"),
            (ids.row, Surface.row, Surface.rowKey, "Alpha Area")
        ]
        for (id, frame, key, name) in layers {
            store.setFrame(frame, slotOriginY: frame.minY, for: id)
            store.setPlacement(dropKey: key, listName: name, for: id)
            store.setLive(true, for: id)
        }
        return ids
    }

    /// **The measured order of a pop**, read off `simctl launch --console` with the registry
    /// instrumented, and the only ordering this fix is allowed to assume.
    ///
    /// The three steps are deliberately in the order the device produced them, including the one
    /// that makes candidate (b) — re-publishing a remembered frame from `onAppear` — unsafe: the
    /// teardown's `onDisappear` arrives **after** the frames have already been republished, so a
    /// restoration that runs before it would simply be undone again.
    private static func replayPushAndBack(
        _ ids: (region: UUID, section: UUID, row: UUID),
        in store: inout CadenceNewTaskDropFrameStore
    ) {
        let layers = [
            (ids.region, Surface.region, Surface.regionKey, ""),
            (ids.section, Surface.section, Surface.sectionKey, "UI Test Workspace"),
            (ids.row, Surface.row, Surface.rowKey, "Alpha Area")
        ]
        // 1. The targets republish their frames, unchanged, on the way out.
        for (id, frame, _, _) in layers {
            store.setFrame(frame, slotOriginY: frame.minY, for: id)
        }
        // 2. SwiftUI tears the pre-pop copy down, after that.
        for (id, _, _, _) in layers { store.retire(id) }
        // 3. The restored copy re-runs its body. Both `.onChange(…, initial: true)` fire again;
        //    `onGeometryChange` does NOT, because nothing moved. That omission is the point.
        for (id, _, key, name) in layers {
            store.setPlacement(dropKey: key, listName: name, for: id)
            store.setLive(true, for: id)
        }
    }

    // MARK: - The bug

    /// **The headline pin.** Before the fix this left `candidates()` empty, which is what a user
    /// met as "the `+` stopped inheriting anything".
    @Test func aPushAndBackLeavesEveryCreateTaskDropTargetReachable() {
        var store = CadenceNewTaskDropFrameStore()
        let ids = Self.seedSidebar(into: &store)

        // Non-vacuity: the surface really is reachable to begin with, so an empty array below is
        // about the pop rather than about a fixture that never registered anything.
        #expect(store.candidates().count == 3)

        Self.replayPushAndBack(ids, in: &store)

        let candidates = store.candidates()
        #expect(candidates.count == 3, "a push and back emptied the surface's drop targets")
        #expect(Set(candidates.map(\.id)) == Set([ids.region, ids.section, ids.row]))
    }

    /// The user-facing half, stated as the hit test the drop actually runs: a `+` released on the
    /// section eyebrow has to still resolve to the **section**, and the section's key has to still
    /// be the one that makes a list in that context rather than a task in Inbox.
    @Test func aRestoredSectionTargetStillSeedsTheContextItWasDroppedOn() {
        var store = CadenceNewTaskDropFrameStore()
        let ids = Self.seedSidebar(into: &store)
        Self.replayPushAndBack(ids, in: &store)

        // A point on the eyebrow strip: inside the section and the region, outside the row.
        let eyebrow = CGPoint(x: 197, y: 290)
        let target = CadenceCaptureDropHitTest.target(at: eyebrow, among: store.candidates())
        #expect(target == ids.section, "a drop on a restored context eyebrow no longer finds it")
        #expect(store.placement(for: ids.section)?.dropKey == Surface.sectionKey)
        #expect(store.placement(for: ids.section)?.listName == "UI Test Workspace")

        // And the inner layer still wins where it is, which is the rule a surviving-but-stale
        // registration could also have broken.
        let onRow = CGPoint(x: 197, y: 330)
        #expect(CadenceCaptureDropHitTest.target(at: onRow, among: store.candidates()) == ids.row)
    }

    /// **The blast radius was never the sidebar.** One modifier is behind every drop surface, so
    /// the same pop reaches a calendar day column — where the restored frame is also what turns the
    /// finger's height into the minute the event composer opens at (T-2065). A column that came
    /// back without its frame could not answer that at all.
    @Test func aRestoredDayColumnStillResolvesTheMinuteUnderTheFinger() {
        var store = CadenceNewTaskDropFrameStore()
        let id = UUID()
        let column = CGRect(x: 60, y: 200, width: 300, height: 480)
        let rule = CadenceCaptureDropSlotRule(hourHeight: 60, snapMinutes: 15)
        // A scrolled column: what a finger can reach is clipped, the slot origin is not.
        let slotOriginY: CGFloat = 80

        store.setFrame(column, slotOriginY: slotOriginY, for: id)
        store.setPlacement(dropKey: "newevent:", listName: "", slot: rule, for: id)
        store.setLive(true, for: id)

        let finger = CGPoint(x: 200, y: 420)
        let before = store.slotMinute(for: id, at: finger)
        #expect(before != nil, "non-vacuity: the fixture column never resolved a minute")

        store.setFrame(column, slotOriginY: slotOriginY, for: id)
        store.retire(id)
        store.setPlacement(dropKey: "newevent:", listName: "", slot: rule, for: id)
        store.setLive(true, for: id)

        #expect(store.candidates().map(\.id) == [id], "a restored day column stopped being a target")
        #expect(store.slotMinute(for: id, at: finger) == before,
                "a restored day column seeds a different minute than the one under the finger")
    }

    // MARK: - What retiring still has to do

    /// The fix must not become "nothing is ever hidden". While the surface is genuinely away — no
    /// restored copy, so no `setLive` — the target has to be unreachable, or a hidden page's rows
    /// would sit on top of the visible one's. That is the same invariant
    /// `iOSNewTaskDropTargetsAreLive` exists for.
    @Test func aRetiredDropTargetIsUnreachableUntilItsSurfaceComesBack() {
        var store = CadenceNewTaskDropFrameStore()
        let ids = Self.seedSidebar(into: &store)
        #expect(store.candidates().count == 3)

        for id in [ids.region, ids.section, ids.row] { store.retire(id) }

        #expect(store.candidates().isEmpty, "a torn-down surface is still offering drop targets")
        #expect(CadenceCaptureDropHitTest.target(at: CGPoint(x: 197, y: 290), among: store.candidates()) == nil)

        // Liveness is the one fact a restored copy republishes by itself, so it is the one that
        // brings the target back — without any new frame, which is all the pop ever supplies.
        store.setLive(true, for: ids.section)
        #expect(store.candidates().map(\.id) == [ids.section])
    }

    /// A target that still has nothing to hand over stays out of `candidates()` after a pop too —
    /// the catch-all "Other" sidebar section and a day column on a day that has gone by both
    /// register with an empty key on purpose, and reviving them would light up a destination that
    /// seeds nothing.
    @Test func aRestoredTargetWithAnEmptyKeyIsStillNotACandidate() {
        var store = CadenceNewTaskDropFrameStore()
        let id = UUID()
        store.setFrame(Surface.section, slotOriginY: Surface.section.minY, for: id)
        store.setPlacement(dropKey: "", listName: "Other", for: id)
        store.setLive(true, for: id)
        #expect(store.candidates().isEmpty)

        store.setFrame(Surface.section, slotOriginY: Surface.section.minY, for: id)
        store.retire(id)
        store.setPlacement(dropKey: "", listName: "Other", for: id)
        store.setLive(true, for: id)
        #expect(store.candidates().isEmpty, "a keyless target became a candidate by being restored")
    }

    // MARK: - The wiring the view layer owns

    /// The store above can only be right if the modifier calls it. This is the one link a macOS
    /// target cannot execute, so it is scanned — and it is scanned for the *shape* of the fix
    /// rather than its name: that the teardown hook hands the registry a retirement, and that
    /// nothing in the modifier deletes a registration.
    @Test func theCreateTaskDropModifierRetiresOnDisappearRatherThanDeletingItsFrame() throws {
        let code = CadenceSourceScan.codeOnly(
            try cadenceTestSource("Cadence/iOS/iOSFloatingCreateTaskButton.swift")
        )
        let modifier = try cadenceFunctionBody(
            "private struct iOSNewTaskDropTargetModifier: ViewModifier",
            in: code
        )

        // Non-vacuity: the modifier still publishes all three facts, so the needles below are
        // about which of them the teardown takes away.
        #expect(modifier.contains("iOSNewTaskDropFrameRegistry.shared.setFrame("))
        #expect(modifier.contains("iOSNewTaskDropFrameRegistry.shared.setPlacement("))
        #expect(modifier.contains("iOSNewTaskDropFrameRegistry.shared.setLive("))

        let disappear = try cadenceFunctionBody(".onDisappear", in: modifier)
        #expect(disappear.contains("iOSNewTaskDropFrameRegistry.shared.retire(registrationID)"),
                "the drop target's teardown no longer retires its registration")
        #expect(!modifier.contains("unregister("),
                "the drop target modifier deletes a registration again — T-3008's exact shape")

        // The frame is the fact nothing republishes, so it must be the one the teardown leaves
        // alone. `setFrame` reached only from the geometry reader is what makes that true.
        #expect(!disappear.contains("setFrame"),
                "the teardown now touches the frame, which only a geometry change can restore")
    }

    /// And the registry really is the Shared store rather than a second copy of the bookkeeping,
    /// which is what would let the tested rule and the shipped rule drift apart.
    @Test func theIOSDropRegistryIsBackedByTheSharedFrameStore() throws {
        let code = CadenceSourceScan.codeOnly(
            try cadenceTestSource("Cadence/iOS/iOSCaptureRadialMenu.swift")
        )
        let registry = try cadenceFunctionBody(
            "final class iOSNewTaskDropFrameRegistry",
            in: code
        )

        #expect(registry.contains("private var store = CadenceNewTaskDropFrameStore()"),
                "the iOS drop registry keeps bookkeeping of its own again")
        #expect(registry.contains("store.retire(id)"))
        #expect(registry.contains("store.candidates()"))
        // Nothing in the registry may hold the state the store owns.
        for shadowed in ["var frames", "var placements", "var live", "var order"] {
            #expect(!registry.contains(shadowed),
                    "the iOS drop registry shadows `\(shadowed)`, which the Shared store owns")
        }
    }
}
