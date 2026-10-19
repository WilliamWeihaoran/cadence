import Foundation

/// The facts a task row states as a glyph rather than as content (T-2058).
///
/// The owner asked for them by what they are, not by how they look: *"for tasks with subtasks,
/// comments, and tags, show corresponding icons after the title"*. **"Comments" is `AppTask.notes`**
/// — a plain `String` at `AppTask.swift:206`, labelled "Notes" in every sheet that edits it
/// (`CreateTaskSheet`, `iOSCalendarEventEditSheet`). There is no comment model in this app, and
/// inventing one to satisfy the word would have been a schema change nobody asked for.
///
/// **There were three; there are two. `case notes` -> `note.text` came off both rows in
/// [[T-3231]], because both rows now draw the notes themselves.** A glyph earns its place by
/// saying something the row cannot say in words, and this one stopped doing that: iOS has printed
/// a notes excerpt under the title throughout, and macOS gained the same excerpt in [[T-1467]]
/// (`MacTaskRow.inlineDetail`), which is the precondition [[T-3196]]'s 2026-10-16 decision gated
/// the drop on — *"give the macOS row a notes preview too, so both platforms can drop the glyph"*.
/// The owner's own words for it: *"since we're showing the notes of a task under the title, we can
/// probably just remove the notes icon right?"*
///
/// **Both platforms at once, and that is the point rather than a convenience.** The glyph was kept
/// through the whole of T-3196 precisely because dropping it on iOS alone would have left one row
/// vocabulary spelled two ways. Removing the case here is the entire change on both rows: each
/// asks `indicators(for:)` and draws what it answers, so neither row file needs a line.
///
/// **`.subtasks` and `.tags` STAY, and the asymmetry is real rather than an oversight.** Neither
/// row draws what those stand for: the tag glyph *replaced* the named chips outright (you cannot
/// see which tags without opening the task), and the subtask lists both rows now draw are
/// `listedSubtasks` — unfinished only, capped at three, empty under a finished task — so a task
/// whose boxes are all ticked shows a checklist glyph and no list. The notes excerpt has no such
/// gap, which is why it is the only one that could go.
///
/// **This does not touch the app's NOTES FEATURE.** `note.text` still names it at
/// `CadenceFeatureDestination.swift:201`, `iPadTodaySupportViews.swift:158`,
/// `iOSSearchSupportViews.swift:32` and `FocusNotesPanel.swift:14`. Dropping the task-row reading
/// REDUCES that symbol's double duty rather than creating a gap — which is the answer to the
/// owner's stated worry that *"the notes icon is used elsewhere in the app for task notes, so it'd
/// be inconsistent"*.
///
/// **Why an enum and not a `Bool` per fact on a view.** The question "does this task have a
/// checklist, tags" is a fact about an `AppTask` with no platform in it; only the row's layout is
/// per-platform. (It read "a note, a checklist, tags" until [[T-3231]]; the argument is the same
/// one short, and the case list shrinking without either row changing is the argument working.)
/// `CompactTagStrip` is this repo's own record of what the other answer costs — three
/// hand-written copies of one strip, de-duplicated three times. So the answer is a value, the value
/// is testable without SwiftUI, and `CadenceTaskRowIndicatorStrip` is the only thing that draws it.
///
/// `allCases` is the **draw order**, and `CadenceTaskRowIndicatorSupport.indicators(for:)` builds
/// its answer in that order, so the row and the accessibility label cannot disagree about which
/// glyph comes first.
enum CadenceTaskRowIndicator: String, CaseIterable, Hashable, Sendable {
    case subtasks
    case tags

    /// Symbols already in this tree rather than new ones: `checklist` is the app's subtask glyph
    /// and `tag` is what the chips it replaced were dotted with.
    var symbolName: String {
        switch self {
        case .subtasks: return "checklist"
        case .tags:     return "tag"
        }
    }

    /// One phrase per glyph, folded into a single spoken string by
    /// `CadenceTaskRowIndicatorSupport.accessibilityLabel(for:)`.
    ///
    /// Deliberately **not** a count. The glyph does not say how many subtasks or which tags — that
    /// is the trade the owner accepted when the tag glyph replaced the named chips — so a label
    /// saying "3 tags" would promise VoiceOver a precision the screen does not show.
    var accessibilityPhrase: String {
        switch self {
        case .subtasks: return "Has subtasks"
        case .tags:     return "Has tags"
        }
    }
}

/// Which indicators a task earns, and what a screen reader hears when it has any.
///
/// Still not `nonisolated`, and that is now a choice rather than a constraint. It was a
/// measurement while `hasNotes` was here: that predicate reached
/// `CadenceTaskPresentationSupport.plainPreviewText`, which carries no `nonisolated` of its own,
/// and under this project's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` a `nonisolated` caller
/// cannot reach it. [[T-3231]] removed that call, so nothing left in this type forces the
/// isolation. It is kept because both remaining predicates read `AppTask` relationships
/// (`subtasks`, `sortedTags`) off a SwiftData model the rows touch on the main actor, and marking
/// the type `nonisolated` to serve no caller would be a change with a migration cost and no
/// benefit. `CadenceTaskPresentationSupportTests` already exercises this isolation from the test
/// target, which is where the guarantee is checked.
enum CadenceTaskRowIndicatorSupport {

    // `hasNotes` lived here until [[T-3231]], answering
    // `!CadenceTaskPresentationSupport.plainPreviewText(from: task.notes).isEmpty` — deliberately
    // the preview parser rather than `notes.isEmpty`, so a field holding only `---` lit nothing.
    // **The predicate is not lost, it is the one each row draws its excerpt from:** iOS's
    // `secondaryLine` and `MacTaskRow.notesPreview` both ask `plainPreviewText` and both return
    // `nil` on the same input the glyph used to go dark on. That is why the glyph could go without
    // a replacement check — the excerpt is the check, one layer up, and it shows the note as well
    // as reporting it.

    /// Any subtask at all, finished or not.
    ///
    /// **Not `CadenceTaskPresentationSupport.listedSubtasks`**, which is the *row list's* question
    /// and answers `[]` for a finished task and for a task whose subtasks are all done. The glyph
    /// answers "is there a checklist on this task", which stays true once you tick the last box.
    static func hasSubtasks(_ task: AppTask) -> Bool {
        !(task.subtasks ?? []).isEmpty
    }

    /// `sortedTags`, which is `TagSupport.sorted(tags ?? [])` — the same accessor both rows read, so
    /// the glyph and the chips it replaced answer out of one place.
    static func hasTags(_ task: AppTask) -> Bool {
        !task.sortedTags.isEmpty
    }

    static func indicators(for task: AppTask) -> [CadenceTaskRowIndicator] {
        CadenceTaskRowIndicator.allCases.filter { indicator in
            switch indicator {
            case .subtasks: return hasSubtasks(task)
            case .tags:     return hasTags(task)
            }
        }
    }

    /// One element, phrases folded with `", "` — `CadenceSidebarLayout.rowAccessibilityLabel`'s
    /// shape, for its reason. Three bare `Image`s are three unlabelled elements a screen reader
    /// stops on and reads nothing at; one labelled element is one stop that says what it means.
    ///
    /// `nil` when the task has none, so a row with no indicators adds no element at all rather than
    /// an empty one — the same call `CadenceSidebarLayout.badge` makes about ", 0".
    static func accessibilityLabel(for task: AppTask) -> String? {
        accessibilityLabel(for: indicators(for: task))
    }

    static func accessibilityLabel(for indicators: [CadenceTaskRowIndicator]) -> String? {
        guard !indicators.isEmpty else { return nil }
        return indicators.map(\.accessibilityPhrase).joined(separator: ", ")
    }
}
