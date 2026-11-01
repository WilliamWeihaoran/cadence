import Foundation

/// **The one section vocabulary search results are divided into, on both platforms** ([[T-8765]],
/// owner decision 2026-10-31 under [[T-8201]]).
///
/// Before this existed the two surfaces each spelled their own list. The Mac palette had eight
/// hand-written cases in `GlobalSearchCategory`; iOS Search passed five string literals —
/// "Pages", "Tasks", "Lists", "Notes", "Calendar Events" — straight into its section builder. So
/// one query read **Lists** on the phone and **Areas** / **Projects** on the Mac, and an event
/// note sat under **Notes** on the phone and **Event Notes** on the Mac.
///
/// **The Mac's vocabulary won**, for one reason: it loses no information. "Lists" is `Area` and
/// `Project` merged, and "Notes" with event notes folded in is two kinds merged; going the other
/// way is a rename, going this way is a split that cannot be undone from the merged label. The
/// declaration order *is* the display order, and it is the order the Mac palette already drew.
///
/// **`.commands` is the one section a touch surface does not draw**, and that is a platform
/// difference with an input constraint behind it ([[T-8201]]): the rows it holds — New Task,
/// Focus, Today — are the keyboard palette's idiom, reached by typing a verb into Cmd+K, and iOS
/// has no palette. Every *other* case is drawn on both. `touchSections` is what iOS iterates, so
/// a case added here reaches the phone unless it is deliberately held back in one place.
///
/// `rawValue` is the heading the user reads, which is also the section's identity in the Mac
/// palette's expanded-section state (`GlobalSearchKeyboardRow.continuationID(forSection:)`).
/// That state is per-presentation and nothing persists it, so a raw value here is safe to change
/// in a way `TaskSortField`'s is not.
enum CadenceSearchSection: String, CaseIterable, Identifiable, Hashable, Sendable {
    case commands = "Commands"
    case pages = "Pages"
    case areas = "Areas"
    case projects = "Projects"
    case tasks = "Tasks"
    case events = "Calendar Events"
    /// Notes whose `kind` is `.meeting`. The case keeps its older name because it is the Mac
    /// palette's and renaming it would touch every call site for no reader-visible gain; the
    /// heading the user reads is the raw value, "Event Notes".
    case meetingNotes = "Event Notes"
    case notes = "Notes"

    var id: String { rawValue }

    /// The heading drawn above the section's rows, on both platforms.
    var title: String { rawValue }

    /// Every section a touch surface draws, in display order — `allCases` minus `.commands`.
    static let touchSections: [CadenceSearchSection] = allCases.filter { $0 != .commands }
}
