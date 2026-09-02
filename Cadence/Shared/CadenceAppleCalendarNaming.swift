import Foundation

/// The three places the app has to write the words "Apple Calendar", kept apart on purpose.
///
/// **T-547.** One literal was serving at least two concepts across seven files, which is why
/// [[T-524]] refused to hoist it: a single shared constant for two meanings is not a
/// de-duplication, it is a coupling that renames one screen when somebody edits another. The
/// literal appeared as a **section label** in four sheets and inspectors, and as a **fallback** in
/// four rows for two *different* nil cases — `event.calendar?.title` and `calendar.source?.title`
/// are not the same absence, and they are not shown in the same slot.
///
/// So the split comes first and the hoist second. The three constants below are byte-identical
/// today and that is the whole point: each names one concept, so any one of them can be reworded
/// without dragging the other two along. A future pass that decides an account with no name should
/// read "iCloud" or "Other" edits `unnamedAccountTitle` alone — see [[T-692]], which is the
/// divergence that finding turned up.
///
/// `nonisolated` for the reason `CadenceSettingsSectionCopy` carries the same keyword: the project
/// sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so a bare enum here would be main-actor
/// isolated and reading it from a `nonisolated` context warns today and is an error under Swift 6.
/// Constants have no state to protect.
nonisolated enum CadenceAppleCalendarNaming {

    /// **The label.** The eyebrow over the controls that read or write the system calendar — the
    /// calendar section of the quick-create sheet and the event edit sheet, the calendar group in
    /// the day inspector, and the list editor's link row. It names the *integration*, so it is
    /// singular and it never depends on what EventKit returned.
    ///
    /// Not `CadenceCalendarSettingsCopy.appleCalendarsSectionTitle`, which is the **plural**
    /// eyebrow over Settings → Calendar's list of every calendar EventKit vends (T-599(e)). One
    /// heads a feature, the other heads a list; they were already two strings and stay two.
    static let integrationSectionTitle = "Apple Calendar"

    /// **A calendar with no name.** `EKEvent.calendar` is optional and `EKCalendar.title` can come
    /// back empty, so a row that prints which calendar an event belongs to needs something to
    /// print. Shown where a calendar's own name goes: a board card's meta line, a search result's
    /// subtitle.
    ///
    /// Distinct from `unnamedAccountTitle` below even though the English matches: this answers
    /// "which calendar", that one answers "which account".
    static let unnamedCalendarTitle = "Apple Calendar"

    /// **An account with no name.** `EKCalendar.source` is the account a calendar came from —
    /// iCloud, an Exchange server, On My Mac — and Settings → Calendar prints it under the
    /// calendar's name. This is what that line says when the source is missing or unnamed.
    ///
    /// The app currently disagrees with itself here and this constant does not resolve it:
    /// `CadenceCalendarPicker` groups by the same `source?.title` and falls back to "Other"
    /// instead. That is a copy decision, filed as [[T-692]] rather than settled by a refactor.
    static let unnamedAccountTitle = "Apple Calendar"
}
