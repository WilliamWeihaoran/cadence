import Foundation
import Observation

/// [[T-18158]]: where the user was inside Notes and Lists, held above the size-class shell switch so
/// a Split View or Stage Manager resize carries it into the shell that is arriving.
///
/// `iOSRootView` builds one of two whole shells from `horizontalSizeClass`, so crossing the
/// compact/regular boundary destroys every page and builds it again from its `@State` defaults.
/// [[T-334]] carried WHICH FEATURE was showing across that swap and [[T-335]] carried Settings'
/// category; the place inside Notes (tab, day, note, whether it was open) and the selected list were
/// still rebuilt from defaults, so narrowing out of an older Notepad note landed on today's Daily
/// note and widening Lists picked the first list.
///
/// **Scene-scoped, never persisted.** The root holds this in `@State`, so it lives exactly as long
/// as the window and a relaunch starts clean -- the Notes header resets its tab and day per LAUNCH on
/// purpose (the stored-day trap), and a resize is not a launch.
///
/// **A place is restored only by the OTHER shell.** Each record is stamped with the width class it
/// was written under, and a page asks for a place only across that boundary: a Notes page rebuilt
/// at the same width (Notes, then Today, then Notes again in one shell) keeps its own reset rules
/// untouched. A page that restores re-records at its own width at once, which is what makes the round
/// trip work: regular -> compact -> regular hands the place back each time.
///
/// In `Shared/` because `Cadence/iOS/` is invisible to `CadenceTests`; the decision is pinned by
/// `CadenceShellPlaceCarryTests`.
@Observable
final class CadenceShellPlaceCarry {
    /// One recorded place and the width class it was recorded under.
    struct Recorded<Place: Equatable>: Equatable {
        let place: Place
        let isRegularWidth: Bool
    }

    private(set) var notes: Recorded<CadenceNotesShellPlace>?
    private(set) var list: Recorded<CadenceCarriedListRoute>?

    init() {}

    func recordNotes(_ place: CadenceNotesShellPlace, isRegularWidth: Bool) {
        let next = Recorded(place: place, isRegularWidth: isRegularWidth)
        if notes != next { notes = next }
    }

    func recordList(_ route: CadenceCarriedListRoute, isRegularWidth: Bool) {
        let next = Recorded(place: route, isRegularWidth: isRegularWidth)
        if list != next { list = next }
    }

    /// The Notes place a page being built at `isRegularWidth` should open on, or `nil` to keep its
    /// own defaults.
    func notesPlaceToRestore(isRegularWidth: Bool) -> CadenceNotesShellPlace? {
        Self.restorable(notes, isRegularWidth: isRegularWidth)
    }

    /// The list a Lists page being built at `isRegularWidth` should select, or `nil` to keep its own
    /// default.
    func listToRestore(isRegularWidth: Bool) -> CadenceCarriedListRoute? {
        Self.restorable(list, isRegularWidth: isRegularWidth)
    }

    /// The one rule: only a place recorded by the other width's shell answers.
    static func restorable<Place>(
        _ recorded: Recorded<Place>?,
        isRegularWidth: Bool
    ) -> Place? {
        guard let recorded, recorded.isRegularWidth != isRegularWidth else { return nil }
        return recorded.place
    }
}

/// Where a Notes page was: which tab, which day the date picker pointed at, which note was selected,
/// and whether that note was OPEN -- in the compact cover, in the regular one-column pane's inline
/// editor, or chosen in the two-column pane -- rather than merely the tab's default selection.
struct CadenceNotesShellPlace: Equatable {
    var tab: CadenceNotesTabVocabulary
    var dayKey: String
    var noteID: UUID?
    var isOpen: Bool

    /// Whether the page is showing its selected note rather than its index, in each of the three
    /// forms a Notes page takes: compact width presents the editor over the list (cover or event
    /// sheet); a regular one-column pane swaps the editor into the list's place; a regular
    /// two-column pane always stands a note beside the list, so there it is "open" only once the
    /// user chose one -- the tab's default Daily note is not a place anyone went to.
    static func isOpen(
        isRegularWidth: Bool,
        layout: CadenceNotesLayout,
        compactEditorIsUp: Bool,
        inlineEditorIsShown: Bool,
        noteWasChosen: Bool
    ) -> Bool {
        guard isRegularWidth else { return compactEditorIsUp }
        return layout == .oneColumn ? inlineEditorIsShown : noteWasChosen
    }

    /// The note a restoring page selects: the carried one while its tab still holds it, otherwise
    /// `nil`, which leaves the page to its own default (a note deleted in between must not be
    /// selected by id).
    func noteToSelect(amongTabNoteIDs ids: [UUID]) -> UUID? {
        guard let noteID, ids.contains(noteID) else { return nil }
        return noteID
    }
}

/// The selected list, in a vocabulary `Shared/` can hold (`iOSListRoute` is iOS-only).
enum CadenceCarriedListRoute: Hashable {
    case area(UUID)
    case project(UUID)
}

/// [[T-18729]] / [[T-18730]]: what the iPad sidebar selects when the compact shell widens, now that a
/// specific LIST can be the answer and not only a feature.
///
/// `CadenceShellNavigationBridge` reads the compact shell back as a feature, and a list has no
/// feature of its own: `iOSSidebarItem.featureDestination` folds `.area` / `.project` into `.lists`.
/// Comparing sidebar ITEMS against that answer lost the list both ways round. A list opened from the
/// sidebar narrowed into More > Lists and widened back as the bare Lists row (the list replaced by
/// the Lists page's first list); a list pushed on the compact Tasks tab's index answered nothing at
/// all, so the bridge fell back to the tab's segment -- Today -- or to a feature pushed and already
/// popped on that tab.
///
/// In `Shared/` for the reason `CadenceShellPlaceCarry` is; pinned by `CadenceShellListArrivalTests`.
enum CadenceShellListArrival: Equatable {
    /// Leave the sidebar's selection as it is.
    case keep
    /// Select this feature's row (the root writes it only when it differs).
    case feature(CadenceFeatureDestination)
    /// Select this list's own sidebar row.
    case list(CadenceCarriedListRoute)

    /// - Parameters:
    ///   - compactShows: the bridge's reading of the compact shell, `nil` for the More menu.
    ///   - pushedList: the list on top of the selected compact tab's stack, when the top is a list.
    ///   - selectedList: the sidebar's selection while it is a list row.
    ///   - carriedList: the list the compact Lists page last recorded (`listToRestore(isRegularWidth:
    ///     true)`), `nil` when it recorded none.
    static func resolve(
        compactShows: CadenceFeatureDestination?,
        pushedList: CadenceCarriedListRoute?,
        selectedList: CadenceCarriedListRoute?,
        carriedList: CadenceCarriedListRoute?
    ) -> CadenceShellListArrival {
        // A list on top of the stack is what the user is looking at; a feature mirrored for the
        // same tab is older than it, so it cannot out-vote it ([[T-18730]]).
        if let pushedList { return .list(pushedList) }
        guard let compactShows else { return .keep }
        // The sidebar's list narrowed into Lists and came back from Lists: it is still the list the
        // user chose, unless the compact Lists page went on to a different one ([[T-18729]]).
        if compactShows == .lists, let selectedList, carriedList == nil || carriedList == selectedList {
            return .keep
        }
        return .feature(compactShows)
    }
}
