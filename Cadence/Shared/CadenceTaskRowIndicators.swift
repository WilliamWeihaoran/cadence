import Foundation

/// The three facts a task row states as a glyph rather than as content (T-2058).
///
/// The owner asked for them by what they are, not by how they look: *"for tasks with subtasks,
/// comments, and tags, show corresponding icons after the title"*. **"Comments" is `AppTask.notes`**
/// — a plain `String` at `AppTask.swift:206`, labelled "Notes" in every sheet that edits it
/// (`CreateTaskSheet`, `iOSCalendarEventEditSheet`). There is no comment model in this app, and
/// inventing one to satisfy the word would have been a schema change nobody asked for.
///
/// **Why an enum and not three `Bool`s on a view.** The question "does this task have a note, a
/// checklist, tags" is a fact about an `AppTask` with no platform in it; only the row's layout is
/// per-platform. `CompactTagStrip` is this repo's own record of what the other answer costs — three
/// hand-written copies of one strip, de-duplicated three times. So the answer is a value, the value
/// is testable without SwiftUI, and `CadenceTaskRowIndicatorStrip` is the only thing that draws it.
///
/// `allCases` is the **draw order**, and `CadenceTaskRowIndicatorSupport.indicators(for:)` builds
/// its answer in that order, so the row and the accessibility label cannot disagree about which
/// glyph comes first.
enum CadenceTaskRowIndicator: String, CaseIterable, Hashable, Sendable {
    case notes
    case subtasks
    case tags

    /// Symbols already in this tree rather than three new ones: `note.text` is what
    /// `FocusNotesPanel` heads itself with and `checklist` is `FocusBundleTaskSupportViews`'.
    var symbolName: String {
        switch self {
        case .notes:    return "note.text"
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
        case .notes:    return "Has notes"
        case .subtasks: return "Has subtasks"
        case .tags:     return "Has tags"
        }
    }
}

/// Which indicators a task earns, and what a screen reader hears when it has any.
///
/// Not `nonisolated`, and that is a measurement rather than an oversight: the notes predicate goes
/// through `CadenceTaskPresentationSupport.plainPreviewText`, which is itself
/// `CadenceMarkdownPresentationSupport.plainPreviewText` (`:13`) and carries no `nonisolated` of
/// its own. Under this project's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` a `nonisolated` caller
/// cannot reach it, so this type is isolated exactly as `CadenceTaskPresentationSupport` is — which
/// is also the type `CadenceTaskPresentationSupportTests` already exercises from the test target.
enum CadenceTaskRowIndicatorSupport {

    /// **`plainPreviewText(...).isEmpty`, not `notes.isEmpty`.** This is the predicate
    /// `iOSTaskRow.secondaryLine` already uses to decide whether a row has a notes line to draw, so
    /// a row whose glyph says "note" and whose preview line is blank is impossible by construction.
    /// A `notes` field holding only markdown punctuation — a stray `---`, an empty bullet left by
    /// the editor — renders as nothing and must light nothing.
    ///
    /// No `limit:`. The limit only truncates the string the parser has already built, so it cannot
    /// change emptiness; passing one would be a figure this predicate does not use.
    static func hasNotes(_ task: AppTask) -> Bool {
        !CadenceTaskPresentationSupport.plainPreviewText(from: task.notes).isEmpty
    }

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
            case .notes:    return hasNotes(task)
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
