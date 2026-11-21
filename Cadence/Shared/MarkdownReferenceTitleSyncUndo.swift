import Foundation
import ObjectiveC

/// **[[T-18594]]: a note's reference-title sync is never an undo step of its own.**
///
/// A task embed's title is stored twice: on the task, which the card is drawn from, and inside the
/// note's `[[task:UUID|Title]]` text. When the task is renamed somewhere other than the note's own
/// text -- the Mac task popover, inline panel or field-chip popover, a hover-exit refresh after a
/// rename elsewhere, the iOS task sheet or inline panel -- the editor rewrites the hidden title to
/// match. That rewrite used to land as an ordinary undoable edit, so the user's next undo was spent
/// on text nobody can see (the card never moves), and on the Mac a hover-exit rewrite after an undo
/// emptied the redo stack.
///
/// **Why not register the sync, and why not leave it unregistered.** The rename itself stays out of
/// the note's history (keeper's call in [[T-18710]]: renaming back to the reference's
/// display-normalised copy would be lossy). Writing the text with undo registration disabled is not
/// an option either: every `NSTextView` / `UITextView` record already on the stack describes the
/// text by offset, so a lengthened or shortened title earlier in the note would replay the user's
/// older typing at shifted offsets -- the [[T-17181]] corruption.
///
/// **What it does instead: the sync rides on the step before it.** The rewrite is registered as
/// usual, in its own group, so every record stays on the text it was recorded against. That group
/// also carries a marker; when an undo takes the marked group back, the same press goes on to undo
/// the step beneath it, and the matching redo press redoes both. One press therefore always moves
/// something the user can see, and the menu names that step: the sync group borrows the action name
/// of the step it rides on. The text an undo lands on carries the reference title as it was at that
/// point -- exactly the text the user had there -- and the next sync brings it back in line.
///
/// Rules at the edges:
/// - **Nothing to ride on** (an empty undo stack): written with registration off, which can leave
///   no record stale because the redo stack, whose records it would, is emptied with it -- as a
///   registered edit would have emptied it.
/// - **Inside a group someone else opened**: written as part of that group, unmarked. It is already
///   not a standalone step, and a marker there would carry the press one step too far.
/// - **While undoing or redoing**: not written; the replay owns the text.
///
/// One instance per undo manager, attached to it (`attached(to:)`); it observes only that manager.
@MainActor
final class MarkdownReferenceTitleSyncUndo: NSObject {
    private weak var manager: UndoManager?
    /// Set by a marker while an undo takes its group back; read once that undo finishes.
    private var markedGroupWasUndone = false
    /// Set across this object's own follow-on undo or redo, so it is not counted as a press.
    private var isChaining = false
    /// One entry per redoable press, newest last: how many groups that press undid. Mirrors the
    /// manager's redo stack, which a new registration empties.
    private var redoPressSpans: [Int] = []

    nonisolated(unsafe) private static var associationKey: UInt8 = 0

    /// The instance for `manager`, created on first use and kept alive by the manager itself.
    static func attached(to manager: UndoManager) -> MarkdownReferenceTitleSyncUndo {
        if let existing = objc_getAssociatedObject(manager, &associationKey) as? MarkdownReferenceTitleSyncUndo {
            return existing
        }
        let sync = MarkdownReferenceTitleSyncUndo(manager: manager)
        objc_setAssociatedObject(manager, &associationKey, sync, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return sync
    }

    private init(manager: UndoManager) {
        self.manager = manager
        super.init()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(managerDidUndo), name: .NSUndoManagerDidUndoChange, object: manager)
        center.addObserver(self, selector: #selector(managerDidRedo), name: .NSUndoManagerDidRedoChange, object: manager)
        center.addObserver(self, selector: #selector(managerDidCloseGroup), name: .NSUndoManagerDidCloseUndoGroup, object: manager)
    }

    /// Runs `edit`, the text write of a reference-title sync, under the rules above. Call it only
    /// when the write would change the text. `edit` returns whether it did; this returns the same,
    /// or `false` when a replay kept it from running.
    @discardableResult
    func perform(_ edit: () -> Bool) -> Bool {
        guard let manager else { return edit() }
        if manager.isUndoing || manager.isRedoing { return false }
        if manager.groupingLevel > 0 { return edit() }
        guard manager.canUndo else {
            manager.disableUndoRegistration()
            let changed = edit()
            manager.enableUndoRegistration()
            if changed { manager.removeAllActions() }
            return changed
        }
        let ridesOn = manager.undoActionName
        manager.beginUndoGrouping()
        registerMarker(on: manager)
        let changed = edit()
        if !ridesOn.isEmpty { manager.setActionName(ridesOn) }
        // A refused write leaves a group holding only the marker. That is harmless: a press on it
        // goes straight on to the step beneath, so it still never lands on nothing.
        manager.endUndoGrouping()
        return changed
    }

    /// The marker re-registers itself each way, so the group keeps its mark through any number of
    /// undo/redo cycles. Holds `self` strongly: `UndoManager` does not retain its target.
    private func registerMarker(on manager: UndoManager) {
        manager.registerUndo(withTarget: self) { [weak manager] sync in
            guard let manager else { return }
            if manager.isUndoing { sync.markedGroupWasUndone = true }
            sync.registerMarker(on: manager)
        }
    }

    @objc private func managerDidUndo(_ notification: Notification) {
        guard !isChaining, let manager else { return }
        isChaining = true
        var span = 1
        while markedGroupWasUndone, manager.canUndo {
            markedGroupWasUndone = false
            manager.undo()
            span += 1
        }
        markedGroupWasUndone = false
        isChaining = false
        redoPressSpans.append(span)
    }

    @objc private func managerDidRedo(_ notification: Notification) {
        guard !isChaining, let manager else { return }
        let span = redoPressSpans.popLast() ?? 1
        guard span > 1 else { return }
        isChaining = true
        for _ in 1..<span where manager.canRedo { manager.redo() }
        isChaining = false
    }

    /// A group closed outside a replay is a new registration, and a new registration empties the
    /// manager's redo stack -- so the mirror of it empties too.
    @objc private func managerDidCloseGroup(_ notification: Notification) {
        guard let manager, !manager.isUndoing, !manager.isRedoing else { return }
        redoPressSpans.removeAll()
    }
}
