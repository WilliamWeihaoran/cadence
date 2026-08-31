import Foundation
import Testing
@testable import Cadence

/// `CadenceOrderReassignment` is where an **existing** row's `order` comes from once the user
/// rearranges the list — the sibling of `CadenceOrderAllocation`, which answers the same question
/// for a row being created.
///
/// **The bug these pin (T-581): contexts reordered on macOS and not on iPhone**, while
/// `Context.order` drives both platforms' sidebars and both settings cards. macOS had a drag
/// handle; iOS had no move path at all, so an iPhone-only user was stuck with creation order,
/// which `nextContextOrder()`'s append guarantees.
///
/// The fix could have been a second copy of macOS's four lines of index arithmetic on the iOS
/// side. It is not, because those four lines are wrong in two ways if written from memory, and a
/// second copy is a second chance to write them that way:
///
/// - "insert before the target" is `toIndex` when the drag went **up** and `toIndex - 1` when it
///   went **down**, because removing the dragged element shifts everything after it. Written
///   without the adjustment, a downward move lands one place short — in one direction only.
/// - a one-step move **down** is not "put me in the next slot". It is *move the row below me above
///   me*. The other spelling reads correctly and does nothing.
///
/// Both are asserted below, and both fail loudly if the helper is rewritten the naive way.
@MainActor
struct CadenceOrderReassignmentTests {

    // MARK: - The insert-before adjustment

    /// A **downward** move: the dragged row lands immediately before the target, not after it.
    ///
    /// This is the assertion the missing `- 1` fails. Naive `insert(at: toIndex)` gives
    /// `[b, c, a, d]` — `a` on the far side of the row it was dropped onto.
    @Test func aDownwardMoveLandsImmediatelyBeforeTheTarget() {
        let rows = ["a", "b", "c", "d"].map(Row.init)

        let moved = CadenceOrderReassignment.moved(rows, "a", before: "c")

        #expect(moved?.map(\.id) == ["b", "a", "c", "d"])
    }

    /// An **upward** move, where no adjustment is wanted. A helper that subtracted one in both
    /// directions passes the test above and fails this one.
    @Test func anUpwardMoveLandsImmediatelyBeforeTheTargetToo() {
        let rows = ["a", "b", "c", "d"].map(Row.init)

        let moved = CadenceOrderReassignment.moved(rows, "d", before: "b")

        #expect(moved?.map(\.id) == ["a", "d", "b", "c"])
    }

    /// Both directions, over every ordered pair in a four-row list: whatever else moves, the
    /// dragged row ends up directly ahead of its target and no row is lost or duplicated.
    @Test func everyMoveLeavesTheDraggedRowDirectlyAheadOfItsTarget() {
        let ids = ["a", "b", "c", "d"]
        let rows = ids.map(Row.init)

        for dragged in ids {
            for target in ids where target != dragged {
                let moved = CadenceOrderReassignment.moved(rows, dragged, before: target)
                let result = moved?.map(\.id)

                #expect(result?.count == ids.count, "\(dragged) before \(target) changed the row count")
                #expect(Set(result ?? []) == Set(ids), "\(dragged) before \(target) lost or duplicated a row")

                guard let result,
                      let draggedIndex = result.firstIndex(of: dragged),
                      let targetIndex = result.firstIndex(of: target) else {
                    Issue.record("\(dragged) before \(target) produced nothing")
                    continue
                }
                #expect(
                    targetIndex == draggedIndex + 1,
                    "\(dragged) before \(target) produced \(result)"
                )
            }
        }
    }

    /// Nothing to do is `nil`, so a caller can skip the renumber and the commit rather than
    /// writing an identical array back to the store.
    @Test func aMoveWithNothingToDoReturnsNil() {
        let rows = ["a", "b", "c"].map(Row.init)

        #expect(CadenceOrderReassignment.moved(rows, "a", before: "a") == nil)
        #expect(CadenceOrderReassignment.moved(rows, "z", before: "a") == nil)
        #expect(CadenceOrderReassignment.moved(rows, "a", before: "z") == nil)
        #expect(CadenceOrderReassignment.moved([Row](), "a", before: "b") == nil)
    }

    // MARK: - One step, in the list the user can see

    /// Moving **down** hands back the row *below* as the dragged one. The obvious spelling —
    /// `(dragged: id, target: next)` — means "put me immediately before the row that is already
    /// immediately after me", which is a no-op, so this assertion is the whole point of the
    /// helper existing.
    @Test func aStepDownMovesTheRowBelowAboveThisOne() {
        let visible = ["a", "b", "c"]

        let step = CadenceOrderReassignment.neighbourStep(moving: "b", by: 1, within: visible)

        #expect(step?.dragged == "c")
        #expect(step?.target == "b")

        // And it is not a no-op: applying it actually reorders.
        let rows = visible.map(Row.init)
        let moved = CadenceOrderReassignment.moved(rows, step?.dragged ?? "", before: step?.target ?? "")
        #expect(moved?.map(\.id) == ["a", "c", "b"])
    }

    /// Moving **up** is the row itself, ahead of the one above it.
    @Test func aStepUpMovesThisRowAboveTheOneAboveIt() {
        let visible = ["a", "b", "c"]

        let step = CadenceOrderReassignment.neighbourStep(moving: "b", by: -1, within: visible)

        #expect(step?.dragged == "b")
        #expect(step?.target == "a")

        let rows = visible.map(Row.init)
        let moved = CadenceOrderReassignment.moved(rows, step?.dragged ?? "", before: step?.target ?? "")
        #expect(moved?.map(\.id) == ["b", "a", "c"])
    }

    /// The two ends, and anything that is not one step. `nil` is what greys the menu item.
    @Test func aStepOffEitherEndOfTheVisibleListIsNil() {
        let visible = ["a", "b", "c"]

        #expect(CadenceOrderReassignment.neighbourStep(moving: "a", by: -1, within: visible) == nil)
        #expect(CadenceOrderReassignment.neighbourStep(moving: "c", by: 1, within: visible) == nil)
        #expect(CadenceOrderReassignment.neighbourStep(moving: "z", by: -1, within: visible) == nil)
        #expect(CadenceOrderReassignment.neighbourStep(moving: "b", by: 0, within: visible) == nil)
        #expect(CadenceOrderReassignment.neighbourStep(moving: "b", by: 2, within: visible) == nil)
        #expect(CadenceOrderReassignment.neighbourStep(moving: "a", by: -1, within: ["a"]) == nil)
        #expect(CadenceOrderReassignment.neighbourStep(moving: "a", by: 1, within: ["a"]) == nil)
    }

    /// A step, then the opposite step, is where you started. Round-tripping is the property a
    /// user actually checks, and an asymmetric off-by-one breaks it.
    @Test func aStepAndItsOppositeReturnTheListToWhereItStarted() {
        let ids = ["a", "b", "c", "d"]

        for (index, id) in ids.enumerated() where index + 1 < ids.count {
            let rows = ids.map(Row.init)
            guard let down = CadenceOrderReassignment.neighbourStep(moving: id, by: 1, within: ids),
                  let afterDown = CadenceOrderReassignment.moved(rows, down.dragged, before: down.target) else {
                Issue.record("no downward step for \(id)")
                continue
            }
            #expect(afterDown.map(\.id) != ids, "moving \(id) down changed nothing")

            let visibleAfter = afterDown.map(\.id)
            guard let up = CadenceOrderReassignment.neighbourStep(moving: id, by: -1, within: visibleAfter),
                  let afterUp = CadenceOrderReassignment.moved(afterDown, up.dragged, before: up.target) else {
                Issue.record("no upward step for \(id)")
                continue
            }
            #expect(afterUp.map(\.id) == ids, "\(id) down then up landed on \(afterUp.map(\.id))")
        }
    }

    // MARK: - Renumbering real contexts, archived ones included

    /// **The renumber runs over the whole collection, not over the visible slice.** This is what
    /// the iOS move does with `contexts` while the card shows only the unarchived ones.
    ///
    /// Numbering only the visible rows hands them indices the archived rows already hold, and
    /// `@Query(sort: \Context.order)` then sorts on ties — unstable, so two rows can swap between
    /// launches with nothing edited. That is `CadenceOrderAllocation`'s lesson applied to a move.
    @Test func renumberingAllContextsLeavesNoTwoSharingAnOrder() {
        let contexts = ["Work", "Home", "Errands", "Someday"].enumerated().map { index, name -> Context in
            let context = Context(name: name)
            context.order = index
            return context
        }
        contexts[1].isArchived = true

        let visible = contexts.filter { !$0.isArchived }
        #expect(visible.map(\.name) == ["Work", "Errands", "Someday"])

        // "Move Errands up" — past Work, which is two places away in the full collection because
        // archived Home sits between them.
        let step = CadenceOrderReassignment.neighbourStep(
            moving: contexts[2].id,
            by: -1,
            within: visible.map(\.id)
        )
        #expect(step?.target == contexts[0].id)

        guard let step,
              let reordered = CadenceOrderReassignment.moved(contexts, step.dragged, before: step.target) else {
            Issue.record("the move produced nothing")
            return
        }
        for (index, context) in reordered.enumerated() {
            context.order = index
        }

        #expect(reordered.map(\.name) == ["Errands", "Work", "Home", "Someday"])
        #expect(Set(contexts.map(\.order)).count == contexts.count, "two contexts share an order")
        #expect(contexts.sorted { $0.order < $1.order }.map(\.name) == ["Errands", "Work", "Home", "Someday"])
        // The archived row kept a distinct order rather than colliding with a visible one.
        #expect(contexts[1].order == 2)
    }

    // MARK: - Both platforms read the one helper

    /// macOS's drop handler no longer carries its own copy of the arithmetic.
    ///
    /// The body, not the file: `SettingsView.swift` has a sidebar-tab move a few lines above that
    /// legitimately does its own `remove`/`insert` over a `[SidebarStaticDestination]` held in
    /// `@AppStorage`, and a file-wide check would either fail on it or be loosened until it saw
    /// nothing.
    @Test func theMacOSContextDropReadsTheSharedReassignment() throws {
        let source = try CadenceCommitSurfaceScan.scanned("Cadence/macOS/Views/SettingsView.swift")
        let body = try #require(
            CadenceSourceScan.functionBody(named: "moveContext", in: source),
            "SettingsView.moveContext(_:before:) is gone"
        )

        #expect(body.contains("CadenceOrderReassignment.moved("))
        #expect(!body.contains("insert(moved, at:"), "the hand-written insert index is back")
        #expect(body.contains("context.order = index"), "non-vacuity: still the renumbering body")
    }

    /// And the iPhone has a move path at all — the thing T-581 is about.
    ///
    /// A source scan because `Cadence/iOS/` is entirely inside `#if os(iOS)` and this target
    /// builds for macOS, so there is no symbol here to call. Four separate facts, because three of
    /// them can be true while the feature is still missing: the function can exist with nothing
    /// calling it, the menu items can exist over a function that does not commit, and the commit
    /// can be a swallowed `try?` that leaves the card showing an order the store refused.
    @Test func theIOSContextsCardOffersAMoveAndCommitsItWhereTheUserCanSee() throws {
        let source = try CadenceCommitSurfaceScan.scanned("Cadence/iOS/iOSSettingsView.swift")

        // 1. The affordance, in the menu the row already has.
        #expect(source.contains("\"Move Up\""), "the iPhone contexts card offers no move up")
        #expect(source.contains("\"Move Down\""), "the iPhone contexts card offers no move down")
        // 2. Reached from the rows, in both directions, and greyed at the ends.
        #expect(CadenceSourceScan.matchCount("moveContext\\(context, by: -1\\)", in: source) == 1)
        #expect(CadenceSourceScan.matchCount("moveContext\\(context, by: 1\\)", in: source) == 1)
        #expect(CadenceSourceScan.matchCount("canMoveContext\\(context, by: ", in: source) == 2)

        // 3. It reads the same helper macOS does rather than a second copy of the arithmetic.
        let body = try #require(
            CadenceSourceScan.functionBody(named: "moveContext", in: source),
            "iOSSettingsView.moveContext(_:by:) is gone"
        )
        #expect(body.contains("CadenceOrderReassignment.neighbourStep("))
        #expect(body.contains("CadenceOrderReassignment.moved("))
        #expect(!body.contains("insert(moved, at:"), "a second copy of the insert index is back")

        // 4. The commit is reported, not swallowed — and the undo runs before the report, so the
        //    sentence "nothing was changed" is true when the user reads it.
        #expect(!body.contains("try? modelContext.save()"), "the iPhone reorder swallows its save")
        #expect(body.contains("CadencePendingChangePersistence.commitEdit(in: modelContext)"))
        #expect(
            CadenceCommitSurfaceScan.reportFollowsTheCatch("contextOrderFailureNotice =", in: body),
            "the reorder reports success or failure above its own catch"
        )
        #expect(source.contains("CadenceInlineFailureNotice(text: contextOrderFailureNotice)"))
    }

    // MARK: - The contexts pane commits everything it writes

    /// **Archiving a context is a write, so it commits (T-583).**
    ///
    /// macOS handed the section `{ $0.isArchived = true }` and `{ $0.isArchived = false }` — two
    /// field writes with no commit anywhere in reach — twelve lines above `moveContext`,
    /// `reopenArea` and `reopenProject`, which all save. Autosave is not the answer that makes both
    /// halves right: `CadenceSavedLinkPersistence` records what "flushes eventually" costs when the
    /// app quits first (T-327), and iOS's own `archive(_:)`/`restore(_:)` already commit.
    ///
    /// The `try?` is deliberate and is what `AGENTS.md`'s rule leaves alone: no insert, no delete,
    /// nothing after it claiming success. `CadenceSaveCommitDisciplineTests` is what would fail if
    /// that ever stopped being true, which is why this test asserts the commit exists rather than
    /// re-deriving the rule.
    @Test func theMacOSContextsPaneCommitsItsArchiveAndRestore() throws {
        let source = try CadenceCommitSurfaceScan.scanned("Cadence/macOS/Views/SettingsView.swift")

        for name in ["archiveContext", "restoreContext"] {
            let body = try CadenceCommitSurfaceScan.declarationBody(named: name, in: source)
            #expect(body.contains("isArchived = "), "non-vacuity: \(name) no longer writes the field")
            #expect(
                body.contains("try? modelContext.save()"),
                "\(name) leaves its write for autosave to flush"
            )
        }

        // Reached from the section, by name rather than by a closure that could grow a body again.
        #expect(source.contains("onArchiveContext: archiveContext(_:)"))
        #expect(source.contains("onRestoreContext: restoreContext(_:)"))
        // And those two functions are the *only* places the field is written here, so an inline
        // closure cannot come back beside them in any spelling.
        #expect(
            CadenceSourceScan.matchCount("isArchived = ", in: source) == 2,
            "a context is archived somewhere other than archiveContext/restoreContext"
        )
    }
}

/// A bare `Identifiable` row, so the arithmetic is tested without a `ModelContext` in the way.
private struct Row: Identifiable {
    let id: String
}
