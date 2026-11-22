#if os(macOS)
import AppKit
import SwiftUI

/// [[T-19029]]: what a Mac editor popover keeps when a click outside it closes it.
///
/// The task inspector (`TaskDetailPopover`) and the event editor (`CalendarEventEditPopover`) hold
/// their title, placement and schedule in view `@State` that reaches the store only through Save,
/// and AppKit closes every popover on a click outside it -- so a casual click threw away the edit
/// the iOS sheets refuse to lose to a swipe-down. The iOS answer (refuse the dismissal) was
/// declined by the owner for the quick-capture panel ("a panel that will not go away when you
/// click", [[T-5302]] (b)); this is that panel's answer instead: **a click-away keeps the draft,
/// keyed by the item's id, and the next open of the same item restores it.** Save, Cancel and
/// Escape are asked-for closes and keep nothing.
///
/// The rules, each pinned by `CadencePopoverDraftStashTests`:
/// - **Keep** only what `keeps(draft, opened)` calls work -- the iOS sheets' own "is anything
///   unsaved" answers, so an untouched popover keeps nothing.
/// - **Restore** only onto the item it was taken from: the opened value the draft was edited
///   against must still be what the item opens as (`base` says which fields count). A Save that
///   landed, a sync or another window moving the item first makes the kept draft stale, and a
///   stale draft is dropped rather than painted over the newer stored value.
/// - **Clear** on a close marked as a cancel (`markCancel`) -- Save, Cancel, Escape.
@MainActor
final class CadencePopoverDraftStash<Draft: Equatable> {
    private struct Entry {
        var draft: Draft
        var opened: Draft
    }

    private var entries: [String: Entry] = [:]
    private var cancelMarks: Set<String> = []
    private let keeps: (_ draft: Draft, _ opened: Draft) -> Bool
    private let base: (Draft) -> Draft
    private let carry: (_ restored: inout Draft, _ current: Draft) -> Void

    /// - Parameters:
    ///   - keeps: whether `draft` holds work worth keeping against the value it opened as.
    ///   - base: the part of an opened value that must be unchanged for a kept draft to come back.
    ///   - carry: fields the restored draft takes from the item as it opens now -- mirrors no
    ///     field edits, which `base` leaves out.
    init(
        keeps: @escaping (_ draft: Draft, _ opened: Draft) -> Bool,
        base: @escaping (Draft) -> Draft = { $0 },
        carry: @escaping (_ restored: inout Draft, _ current: Draft) -> Void = { _, _ in }
    ) {
        self.keeps = keeps
        self.base = base
        self.carry = carry
    }

    /// The kept draft for `id`, if it was edited against what the item still opens as. A peek:
    /// a SwiftUI `init` runs on every host render, so reading must not consume the entry; the
    /// close that ends this presentation replaces or clears it.
    func restored(for id: String, opened current: Draft) -> Draft? {
        guard let entry = entries[id], base(entry.opened) == base(current) else { return nil }
        var restored = entry.draft
        carry(&restored, current)
        return restored
    }

    /// The popover for `id` closed. A cancel-marked close, or one with nothing to keep, clears.
    func close(id: String, draft: Draft, opened: Draft) {
        if cancelMarks.remove(id) != nil || !keeps(draft, opened) {
            entries[id] = nil
        } else {
            entries[id] = Entry(draft: draft, opened: opened)
        }
    }

    /// Marks (or unmarks) the coming close of `id` as asked for -- Save, Cancel or Escape.
    func markCancel(id: String, _ isCancel: Bool = true) {
        if isCancel {
            cancelMarks.insert(id)
        } else {
            cancelMarks.remove(id)
        }
    }

    /// How many drafts are kept -- for the tests' "an untouched popover keeps nothing".
    var keptCount: Int { entries.count }
}

/// The three stashes the two Mac editor popovers use.
@MainActor
enum CadencePopoverDrafts {
    /// The inspector's title, placement, schedule and repeat. Kept by the iOS task sheet's own
    /// test ([[T-5359]]), which leaves the completion mirror out; restored with the live mirror.
    static let taskSchedule = CadencePopoverDraftStash<CadenceScheduleDraft>(
        keeps: { CadenceTaskSheetUnsavedWork.draftDiffers($0, from: $1) },
        base: { var base = $0; base.isSettled = false; return base },
        carry: { $0.isSettled = $1.isSettled }
    )

    /// Text typed into the inspector's "Add subtask" and not yet sent ([[T-5175]]'s rule).
    static let taskSubtaskEntry = CadencePopoverDraftStash<String>(
        keeps: { draft, _ in CadenceTaskSheetUnsavedWork.hasPendingComposerEntry(draft) }
    )

    /// The event editor's schedule. `draft.notes` is no edit ([[T-8572]]): the Notes field commits
    /// as it is typed and mirrors into `EKEvent.notes`, so the event's notes moving is not the
    /// event moving, and the restored draft takes the notes the event has now.
    static let eventSchedule = CadencePopoverDraftStash<CadenceScheduleDraft>(
        keeps: { CadenceEventEditDismissGuard.blocksSwipe(opened: $1, current: $0, notesHavePendingEdit: false) },
        base: { var base = $0; base.notes = ""; return base },
        carry: { $0.notes = $1.notes }
    )

    static func taskKey(_ id: UUID) -> String { id.uuidString }

    /// Save, Cancel or Escape on a task's inspector: neither of its stashes keeps anything.
    static func markTaskCancel(_ id: UUID, _ isCancel: Bool = true) {
        taskSchedule.markCancel(id: taskKey(id), isCancel)
        taskSubtaskEntry.markCancel(id: taskKey(id), isCancel)
    }
}

/// Whether the event that closes a popover was Escape.
///
/// `onExitCommand` does not reach a popover's content -- measured on the inspector's child panels,
/// whose Escape arrives with the main window key (`TaskInspectorChildPanelEscapeDismissal`) -- and a
/// popover's `isPresented` setter cannot tell Escape from a click outside. So the popover watches
/// the app's own key and mouse events without consuming any: an Escape key-down marks its coming
/// close as a cancel, and any other key-down or click unmarks it. A click outside reaches the
/// monitor before it closes the popover, so it always closes unmarked; an Escape something inside
/// the popover consumed (a child panel, a confirmation dialog) is unmarked by the next event.
enum CadencePopoverEscapeIntent {
    static let escapeKeyCode: UInt16 = 53

    static func marksCancel(type: NSEvent.EventType, keyCode: UInt16?) -> Bool {
        type == .keyDown && keyCode == escapeKeyCode
    }

    static let watchedEvents: NSEvent.EventTypeMask = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
}

struct CadencePopoverEscapeWatch: ViewModifier {
    let mark: (Bool) -> Void

    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: CadencePopoverEscapeIntent.watchedEvents) { event in
                    mark(CadencePopoverEscapeIntent.marksCancel(
                        type: event.type,
                        keyCode: event.type == .keyDown ? event.keyCode : nil
                    ))
                    return event
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }
}

extension View {
    /// See `CadencePopoverEscapeIntent`.
    func cadencePopoverEscapeWatch(mark: @escaping (Bool) -> Void) -> some View {
        modifier(CadencePopoverEscapeWatch(mark: mark))
    }
}
#endif
