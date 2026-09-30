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

    /// The **title** of a task row, and the **due-date chip** beside it, by the task's title.
    ///
    /// **Spelled `task.row.` rather than `today.task.row.`, and the difference is not an
    /// oversight.** `todayTaskRow(title:)` above is applied by Today's section view, so it is only
    /// ever on a row Today drew. These two are applied inside `MacTaskRow` itself, which Today and
    /// a list's detail pane both draw from one call site — naming them `today.` would be false on
    /// half their occurrences. A test that means *Today's* copy scopes its query to the row
    /// element, which is what `.accessibilityElement(children: .contain)` on that row is for.
    ///
    /// They exist because a row's title is **not addressable by its label when it matters**. The
    /// defect these were added for ([[T-1432]]) is a title truncated to about ten characters, and a
    /// test that looked the title up by its text would stop finding the element at exactly the
    /// moment the defect appeared — reporting "no such element" where the finding is "it is 70pt
    /// wide". An identifier survives truncation; the string it draws does not.
    static func taskRowTitle(title: String) -> String {
        "task.row.\(slug(title)).title"
    }

    /// The due-date chip on a task row. Its **height** is the reading T-1432 wanted: the chip that
    /// filed that ticket had wrapped `51 days ago` onto three lines and taken the row's height with
    /// it, and a chip's height is a fact about layout that no source scan can reach.
    static func taskRowDueChip(title: String) -> String {
        "task.row.\(slug(title)).due"
    }

    /// One of the task inspector's **panel-opening** controls, named by the field it edits:
    /// Priority, Estimate, Do, Due, Repeat.
    ///
    /// These five exist so a UI test can read where the panel each one opens actually lands
    /// (T-1722). They are not addressable any other way: four of the five are composed rows whose
    /// accessibility label is assembled from a field name *and its current value* — "Do" and "Due"
    /// share a prefix, and a row's value changes the moment the panel under test sets it — so a
    /// query by label is a query that stops matching for reasons that are not the defect.
    ///
    /// Applied at the control, not at the well, because the reading is about the **anchor**: the
    /// whole of T-1722 is that a 28pt tile at one end of the column and a full-width field row
    /// spanning it are different anchors and were assumed to behave the same way.
    static func inspectorPanelControl(_ field: String) -> String {
        "inspector.control.\(slug(field))"
    }

    /// A **board card** — the one `KanbanCard` type both the list Kanban and the Calendar Board
    /// draw — by the task's title.
    ///
    /// The card is itself the `attachmentAnchor: .rect(.bounds)` of three of the app's
    /// `arrowEdge: .trailing` popovers, so a UI test measuring where those land needs the card's
    /// own frame and not merely a point inside it (T-1740).
    static func boardCard(title: String) -> String {
        "board.card.\(slug(title))"
    }

    /// One of a board card's **popover-opening** chips, named by the field it edits. Three carry
    /// one today — the list chip, the tag strip and the duration badge — because those are the
    /// three the T-1740 sweep clicks; the do and due chips take one the same way if anyone needs
    /// to read where their pickers land.
    ///
    /// Same reason as `inspectorPanelControl(_:)` and it is not a coincidence: every one of these
    /// carries the field's current **value** in its accessibility value, and two of them (the list
    /// chip and the tag strip) draw the value as their only text. A query by label is a query that
    /// stops matching when the panel under test changes the field.
    static func boardCardControl(title: String, field: String) -> String {
        "\(boardCard(title: title)).control.\(slug(field))"
    }

    /// A **block** card on the Calendar Board, by the block's title. The card is the whole anchor
    /// of its own detail popover, so the test reads its frame the same way it reads a task card's.
    static func boardBundleCard(title: String) -> String {
        "board.bundle.\(slug(title))"
    }

    /// Today's rollover banner — the offer to move yesterday's unfinished plans onto today.
    static let todayRolloverBanner = "today.rollover.banner"

    /// Today's notes column. **Present only in the three-pane layout** —
    /// `CadenceDesktopSplitLayout.todayLayout` drops it below 1092pt of pane width — which is
    /// exactly why a test needs to be able to ask: an assertion about the note's contents means
    /// nothing at a width where the column is not drawn, and "the picture is missing" and "the
    /// column is missing" are different findings.
    static let todayNotesPane = "today.notes.pane"

    /// A page header's eyebrow line — the uppercase date and the clause after it.
    ///
    /// Added for [[T-1702]], and for `taskRowTitle(title:)`'s reason one ticket further along: the
    /// defect there *is* a truncated string, so the element cannot be looked up by the text it
    /// draws. "TUESDAY, SEPTEMBER 29 · 3 ti…" is not findable by either half of what it was asked
    /// to say. There is no width in the name because this is one row per screen and the reading a
    /// test wants from it is exactly that width.
    static let pageHeaderEyebrow = "page.header.eyebrow"
}
