import Foundation
import SwiftUI

/// **A dragged task names itself on the item it hands over, so a drop target can read it while the
/// finger is still down** ([[T-8451]]).
///
/// The iOS timeline's hover plate is meant to say where the block will land -- the dragged task's
/// own block, at its own length, titled, the same plate the Mac canvas draws
/// (`CadenceTimelineTaskDropHover`, `TimelineDraggedTaskPreview`). To draw that, the column has to
/// know *which* task is over it. It could not: `NSItemProvider`'s data is loaded asynchronously and
/// UIKit withholds it for the **whole** hover on this surface, handing it over only at the release,
/// so the plate was one grid step tall and untitled and named an end the drop would not produce --
/// a 60-minute task hovered `7 PM - 7:15 PM` and landed `7 PM - 8 PM` ([[T-8302]], seen on
/// `Cadence-iPadPro11`). `suggestedName` is metadata rather than data: it is on the provider object
/// the drop target is handed, readable **synchronously**, with no load to await.
///
/// **Why this and not macOS's drag session.** [[T-8451]] proposed a local drag registry, and macOS
/// has one -- `TimelineTaskDragSession`, which its `.onDrag` writes at the lift. That was built and
/// driven on screen first, and it does not work here: **SwiftUI caches a view's drag item**, so the
/// closure that would record the lift runs on a view's FIRST lift and is never called again.
/// Measured on `Cadence-iPadPro11` 2026-10-29, with the registry wired through the shell's
/// environment: a row's first drag recorded its task and drew the full plate, and the same row's
/// second drag recorded nothing, leaving the plate back at one grid step -- and, had the registry
/// not been cleared at the drop, leaving it naming whichever row had dragged last. Both
/// `.draggable` and `.onDrag` behave this way. A registry that cannot be written on every lift is
/// the wrong shape for this surface; the item the drag actually carries cannot go stale, needs no
/// clearing, and leaks nothing when a drag is cancelled.
///
/// The Mac needs none of this: its providers answer during the hover, and the one thing its session
/// still holds -- the pointer's grab offset down a moved block's length -- is pointer-shaped and
/// has no touch counterpart ([[T-1475]]: a touch block moves inside its own press recognizer, never
/// through a system drag). So this is not a second answer to a question macOS answers differently;
/// it is the same plate, reaching the same fact through the only channel that is open here.
nonisolated enum CadenceTimelineTaskDrag {

    /// The name a dragged task's item carries: its id, the same id the payload string spells
    /// (`TaskDragPayload.string(for:)`). One task, one spelling, two places on one item -- not a
    /// second wire format, which is why the payload itself is untouched and every drop target that
    /// already decodes it keeps working.
    static func itemName(for taskID: UUID) -> String {
        taskID.uuidString
    }

    /// The task a hovering item names, or `nil` for an item that is not a Cadence task drag -- text
    /// dragged in from another app, say, which names nothing and leaves the plate claiming only the
    /// start minute.
    static func taskID(itemNamed name: String?) -> UUID? {
        guard let name else { return nil }
        return UUID(uuidString: name)
    }

    /// The item a lifted task hands over: the payload every drop target already decodes, plus the
    /// name a hovering drop target can read without waiting.
    static func itemProvider(for taskID: UUID) -> NSItemProvider {
        let provider = NSItemProvider(object: TaskDragPayload.string(for: taskID) as NSString)
        provider.suggestedName = itemName(for: taskID)
        return provider
    }

    /// The task the drag now over a drop target names, from the providers it is carrying.
    static func hoveringTaskID(in providers: [NSItemProvider]) -> UUID? {
        for provider in providers {
            if let taskID = taskID(itemNamed: provider.suggestedName) { return taskID }
        }
        return nil
    }
}

/// The lift half, for a view whose job is to hand a task to a timeline.
///
/// **`.onDrag` and not `.draggable`**, because the provider is what carries the name and
/// `draggable(_:)` builds its own. Both install the same drag interaction, so the lift, its
/// negotiation with a row's context menu ([[T-8141]]) and the system preview are unchanged, and the
/// payload is byte-for-byte the string the drag has always carried -- vended as the `NSString` the
/// Mac's own `TimelineTaskBlock` vends.
private struct TimelineTaskDragSourceModifier: ViewModifier {
    let taskID: UUID

    func body(content: Content) -> some View {
        content.onDrag { CadenceTimelineTaskDrag.itemProvider(for: taskID) }
    }
}

extension View {
    /// Offer this view's task to a timeline, naming it on the item so the column's hover plate can
    /// be the task's own length and title ([[T-8451]]).
    func timelineTaskDragSource(taskID: UUID) -> some View {
        modifier(TimelineTaskDragSourceModifier(taskID: taskID))
    }
}
