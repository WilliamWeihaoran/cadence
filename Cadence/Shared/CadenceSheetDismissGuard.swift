import Foundation

/// [[T-5174]]: the [[T-3171]] rule — "a swipe cannot discard an unsaved draft" — for **every** iOS
/// Cancel/Save sheet, edit and creation alike.
///
/// (a) brought the Edit List and Edit Context sheets under the rule and left the creation sheets
/// out, because whether a half-typed *new* item should hold its sheet was a taste call. The owner
/// answered it on 2026-10-24 — **one rule for every sheet**, the third time in that session they
/// chose never to lose typed text — so the `isEditing` gate is gone rather than inverted, and the
/// creation sheets (New Task, New List, New Context, Calendar quick-create) snapshot what they
/// opened as and refuse the swipe once the draft differs from it. A "Discard new task?" prompt was
/// declined: it puts a dialog in the way of a reflexive gesture.
///
/// `opened` is the draft as the sheet's own opening pass left it; `nil` until then, so a first
/// render with `@State` defaults — and the normalisation a capture sheet runs in `onAppear` before
/// the user has touched anything — cannot read as an edit. Typing a field back to its opened value
/// releases the swipe.
///
/// **It lives in `Shared/` rather than beside the sheets, and the `iOS` prefix went with the move**
/// — the shape `CalendarRecurrenceEditScope` already has. `Cadence/iOS/` is entirely inside
/// `#if os(iOS)` and therefore invisible to `CadenceTests`, which builds for macOS: the suite that
/// pinned (a) was the one whole-file `#if os(iOS)` file in the test target, so its five tests
/// compiled to nothing and had never run in a `CadenceTests` run or in CI. Nothing here is UI, so
/// nothing was keeping it over there. See [[T-6222]] for the sweep that would have caught it.
nonisolated enum CadenceSheetDismissGuard {
    static func blocksSwipe<Draft: Equatable>(opened: Draft?, current: Draft) -> Bool {
        guard let opened else { return false }
        return opened != current
    }
}

/// Every field `iOSListEditorSheet.save()` writes back, as the sheet holds it.
///
/// A column's completed/archived flags are deliberately absent: `applyColumnWindDown` and
/// `reopenColumn` write those to the model at once, so they are never an unsaved edit.
struct CadenceListEditorDraftSnapshot: Equatable {
    struct Column: Equatable {
        var id: UUID
        var name: String
        var colorHex: String
        var dueDate: String

        init(_ draft: CadenceSectionDraft) {
            id = draft.id
            name = draft.name
            colorHex = draft.colorHex
            dueDate = draft.dueDate
        }
    }

    var name: String
    var details: String
    var icon: String
    var colorHex: String
    var selectedContextID: String
    var selectedAreaID: String
    /// The date key Save would write, `""` for none — the form Save compares, so a `Date` that
    /// moved within its day is not an edit.
    var dueDateKey: String
    var hideEmptyDueDates: Bool
    var hideEmptySectionDueDates: Bool
    var columns: [Column]
}

/// Every field `iOSContextEditorSheet.save()` writes back, as the sheet holds it.
struct CadenceContextEditorDraftSnapshot: Equatable {
    var name: String
    var icon: String
    var colorHex: String
}

/// Everything `iOSCreateTaskSheet.create()` would write, as that sheet holds it ([[T-5174]] (b)).
///
/// The tag selection is in it because the capture card edits it beside the draft and `create()`
/// applies it: a tag picked and nothing typed is still work a swipe would drop. `actionError` and
/// `cardHeight` are not — neither is written anywhere, and `cardHeight` changes on every layout
/// pass, which would hold the sheet over nothing at all.
///
/// `iOSCalendarQuickCreateSheet` needs no type of its own: the draft is the whole of what it holds.
struct CadenceCreateTaskDraftSnapshot: Equatable {
    var draft: CadenceScheduleDraft
    var tagIDs: Set<String>
}
