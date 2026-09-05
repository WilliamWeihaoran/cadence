import Foundation

/// The accessibility identifiers a UI test addresses a surface by, spelled **once**.
///
/// Cadence has almost none of these — nine `accessibilityIdentifier` call sites across the whole
/// macOS surface when this was written, all in the sidebar and the settings list — and that is
/// exactly as far as its UI tests reach. A surface with no identifier is not untestable, but it is
/// only addressable by its *label*, and a label is user-visible text: renaming a heading then
/// silently unhooks the test that was watching it, which is the same failure as a `-only-testing:`
/// aimed at a filename.
///
/// So identifiers added for the composed-window tests live here rather than as string literals at
/// the view, and the test target — which cannot import the app module — restates them in exactly
/// one place of its own. Two copies, both named, is the best a test-bundle boundary allows; a
/// literal typed at each use is not.
nonisolated enum CadenceAccessibilityIdentifiers {

    /// Lowercased, non-alphanumerics collapsed to single hyphens: `"Alpha Area"` → `"alpha-area"`.
    ///
    /// **This is the sidebar's existing rule, restated — and there are deliberately two copies.**
    /// `SidebarSupportViews` has it as a private function of its own. Folding that one into this is
    /// a strict improvement and is *not* done here, because it would be a rewrite of a file two
    /// other agents were editing at the time; it is written down in [[T-1068]] instead of being
    /// smuggled into a test change.
    ///
    /// The pair is not unpinned while it waits. One UI run asserts an identifier from **each**
    /// copy — `sidebar.list.area.alpha-area` from the sidebar's (`CadenceUITests`) and
    /// `today.task.row.overdue-one` from this one (`CadenceTodayCompositionUITests`) — so a change
    /// to either spelling turns a test red rather than drifting quietly.
    static func slug(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }

    /// One of Today's list group headings, by the list's name.
    static func todayTaskSectionHeader(title: String) -> String {
        "today.tasks.section.\(slug(title))"
    }

    /// A task row on Today, by the task's title.
    ///
    /// **By title, not by `id`.** A UUID is not knowable to a test that did not create the row, and
    /// every UI test here reads a store it seeded by name. Two tasks sharing a title share an
    /// identifier; that is a real limitation and the seeded fixtures avoid it rather than the
    /// identifier pretending otherwise.
    static func todayTaskRow(title: String) -> String {
        "today.task.row.\(slug(title))"
    }

    /// Today's rollover banner — the offer to move yesterday's unfinished plans onto today.
    static let todayRolloverBanner = "today.rollover.banner"

    /// Today's notes column. **Present only in the three-pane layout** —
    /// `CadenceDesktopSplitLayout.todayLayout` drops it below 1092pt of pane width — which is
    /// exactly why a test needs to be able to ask: an assertion about the note's contents means
    /// nothing at a width where the column is not drawn, and "the picture is missing" and "the
    /// column is missing" are different findings.
    static let todayNotesPane = "today.notes.pane"
}
