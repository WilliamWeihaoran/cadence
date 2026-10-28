#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// The Mac sidebar's list drag keeps the dragged list in `SidebarDragContext` because SwiftUI
/// never reports a drag's end (T-7701). A list dropped back on its own row kept it there, and the
/// next task dropped on a list row reordered that old list and drew the T-7255 insertion line.
@MainActor
struct CadenceSidebarListDragEndTests {
    private let first = SidebarListDragItem(kind: .area, id: UUID())
    private let second = SidebarListDragItem(kind: .project, id: UUID())

    /// Releasing a list on its own row is the ordinary way to abandon the drag: it moves nothing
    /// AND ends the drag, so nothing is left for a later text drag to be mistaken for.
    @Test func aListDroppedBackOnItsOwnRowEndsTheDrag() {
        let context = SidebarDragContext()
        context.draggedListItem = first
        #expect(context.endDrag(onto: first) == nil)
        #expect(context.draggedListItem == nil)
        // The next drop on a row, with no list drag started since, is not a reorder.
        #expect(context.endDrag(onto: second) == nil)
    }

    /// A real reorder still hands back the dragged list, and ends the drag too.
    @Test func aListDroppedOnAnotherRowMovesItAndEndsTheDrag() {
        let context = SidebarDragContext()
        context.draggedListItem = first
        #expect(context.endDrag(onto: second) == first)
        #expect(context.draggedListItem == nil)
    }

    /// Among payloads that loaded, only the list's own confirms a reorder: a task's payload or
    /// foreign text is refused even while a stale list is held.
    @Test func onlyTheListsOwnPayloadConfirmsAReorder() {
        let taskPayload = TaskDragPayload.string(for: UUID())
        #expect(SidebarListDropPlacement.confirmedListDrag(payload: first.providerText as String, dragged: first) == first)
        #expect(SidebarListDropPlacement.confirmedListDrag(payload: taskPayload, dragged: first) == nil)
        #expect(SidebarListDropPlacement.confirmedListDrag(payload: second.providerText as String, dragged: first) == nil)
        #expect(SidebarListDropPlacement.confirmedListDrag(payload: "plain text", dragged: first) == nil)
        #expect(SidebarListDropPlacement.confirmedListDrag(payload: "", dragged: first) == nil)
        #expect(SidebarListDropPlacement.confirmedListDrag(payload: first.providerText as String, dragged: nil) == nil)
    }

    /// A payload that never loaded (no provider, or `loadObject` failed mid-drag) is no evidence
    /// against the list in flight, so the reorder falls back to it instead of forgetting it and
    /// failing every Mac list reorder (T-7892). With nothing in flight it is still no reorder.
    @Test func aPayloadThatNeverLoadedFallsBackToTheListInFlight() {
        #expect(SidebarListDropPlacement.confirmedListDrag(payload: nil, dragged: first) == first)
        #expect(SidebarListDropPlacement.confirmedListDrag(payload: nil, dragged: second) == second)
        #expect(SidebarListDropPlacement.confirmedListDrag(payload: nil, dragged: nil) == nil)
    }

    /// A row that sees a non-list payload forgets the stale list, but never a newer list drag
    /// that has replaced it in the meantime.
    @Test func aStaleListIsForgottenButANewerDragIsKept() {
        let context = SidebarDragContext()
        context.draggedListItem = first
        context.forgetStale(first)
        #expect(context.draggedListItem == nil)

        context.draggedListItem = second
        context.forgetStale(first)
        #expect(context.draggedListItem == second)
    }
}
#endif
