import Foundation

/// One count-noun phrase, everywhere the app pluralises by count.
///
/// **T-844.** Four sites typed the count and the noun by hand and got the count-of-one case
/// wrong: "1 selected tasks" (`FocusLogSessionPopovers`), "1 tasks" (`FocusSidebarSupportViews`),
/// "Collapsed, 1 notes" (`CadenceNotesListSupport`), "1 milestones" / "1 habits"
/// (`iOSFeatureViews`). `Cadence/Shared/CadenceListDeletionSummary.swift` and
/// `CadenceNoteActionSupport.swift` already had this exact function as a private `line(_:_:_:)`,
/// word for word — this is that function, given one home so a fifth site cannot retype it a third
/// way. The two existing copies now call through to this rather than keep their own.
enum CadencePluralization {
    /// `"N \(singular)"` at exactly one, `"N \(plural)"` otherwise — including zero, which this
    /// always shows rather than omits. A caller that wants to omit the phrase entirely at zero
    /// (`CadenceListDeletionSummary`'s cascade lines, `CadenceNoteActionSupport`'s backlink line)
    /// guards on `count > 0` before calling this, rather than this function guessing what "zero"
    /// should mean for every caller.
    static func phrase(_ count: Int, singular: String, plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }
}
