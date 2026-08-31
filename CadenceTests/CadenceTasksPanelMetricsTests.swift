import CoreGraphics
import Foundation
import Testing
@testable import Cadence

/// macOS Today's panel had five chips on one row and three section headings, and none of them read
/// a metrics type (`docs/TODO.md` T-597).
///
/// Two shapes, one cause. The Cancelled chip set its own `10` and `6/3` while the four chips beside
/// it — the do-date pill, the due-date pill, the bundle badge, the estimate chip — all read
/// `CadenceTaskRowMetrics.desktop.secondaryFontSize` at `4/2`; and two *adjacent* section headings
/// were padded identically except for one point of bottom inset, over a gutter typed out as a bare
/// `16` at six sites in two files. iOS puts every one of these in `CadenceTodaySectionMetrics`,
/// keyed on layout. This is that shape for the Mac.
///
/// The value assertions and the source assertions are both here because either alone goes quietly
/// green: a value test cannot see a *sixth* chip added with its own literals, and a source test
/// cannot see the shared figure being retuned.
struct CadenceTasksPanelMetricsTests {
    private static func panelSource() throws -> String {
        CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TasksPanel.swift")
        )
    }

    private static func sectionSource() throws -> String {
        CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TasksPanelSectionViews.swift")
        )
    }

    // MARK: - The row's fifth chip

    /// The four chips this one sits beside all read the same two figures. `.desktop` exists so they
    /// do not drift, and the one chip that never read it was drawing a point smaller and two points
    /// wider than the rest of the row.
    @Test func theCancelledChipIsDrawnLikeTheFourChipsBesideIt() throws {
        #expect(CadenceTaskRowMetrics.desktop.secondaryFontSize == 11)

        let row = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TasksPanelComponents.swift")
        )

        // Non-vacuity: the right file, past the comment stripper, still drawing the chip.
        #expect(row.contains("struct MacTaskRow: View"))
        let chip = try #require(row.range(of: #"Text("Cancelled")"#))
        let window = String(row[chip.lowerBound...].prefix(400))

        #expect(window.contains("size: metrics.secondaryFontSize"))
        #expect(window.contains(".padding(.horizontal, 4)"))
        #expect(window.contains(".padding(.vertical, 2)"))
        #expect(!window.contains("size: 10"))
        #expect(!window.contains(".padding(.horizontal, 6)"))
        #expect(!window.contains(".padding(.vertical, 3)"))

        // Counted rather than only present: five chips read the secondary size now (the do-date
        // pill spells it twice, once on the hidden `Text` that reserves its width), and a sixth
        // chip arriving with its own literal has to change this number to land.
        #expect(
            CadenceSourceScan.matchCount("size: metrics\\.secondaryFontSize", in: row) == 6
        )
        #expect(CadenceSourceScan.matchCount("size: 10", in: row) == 0)
    }

    // MARK: - The panel's headings

    /// **Two adjacent headings, one point apart.** The intent groups closed at 5 and the Completed
    /// group under them at 6, on the same page, in the same file. Neither number carried a reason,
    /// so 6 wins on the only count available: `.padding(.bottom, 6)` stands at five sites under
    /// `Cadence/macOS/` against one for `5`.
    @Test func thePanelsTwoSectionHeadingsAreOneHeading() throws {
        #expect(TasksPanelMetrics.sectionHeaderTopInset == 16)
        #expect(TasksPanelMetrics.sectionHeaderBottomInset == 6)
        #expect(TasksPanelMetrics.sectionHeaderTopInset > TasksPanelMetrics.sectionHeaderBottomInset)

        let sections = try Self.sectionSource()
        #expect(sections.contains("struct TasksPanelIntentSectionView: View"))
        #expect(sections.contains("struct TasksPanelCompletedSectionView: View"))

        // Two headings, both reading both figures.
        #expect(
            CadenceSourceScan.matchCount("TasksPanelMetrics\\.sectionHeaderTopInset", in: sections) == 2
        )
        #expect(
            CadenceSourceScan.matchCount("TasksPanelMetrics\\.sectionHeaderBottomInset", in: sections) == 2
        )
        #expect(!sections.contains(".padding(.bottom, 5)"))
        #expect(!sections.contains(".padding(.bottom, 6)"))
        #expect(!sections.contains(".padding(.top, 16)"))
    }

    /// The gutter, at all six sites that were typing it: two headings, the controls bar, the
    /// overdue heading, and the two overdue card stacks — plus the row inset, which is the same
    /// number *by rule* rather than by coincidence.
    @Test func thePanelStatesItsGutterOnce() throws {
        #expect(TasksPanelMetrics.horizontalInset == 16)

        let panel = try Self.panelSource()
        #expect(panel.contains("struct TasksPanel"))
        #expect(
            CadenceSourceScan.matchCount("TasksPanelMetrics\\.horizontalInset", in: panel) == 4
        )
        #expect(!panel.contains(".padding(.horizontal, 16)"))

        let sections = try Self.sectionSource()
        // Three: the two headings, and the row inset that is documented as matching them.
        #expect(
            CadenceSourceScan.matchCount("TasksPanelMetrics\\.horizontalInset", in: sections) == 3
        )
        #expect(!sections.contains(".padding(.horizontal, 16)"))
        #expect(!sections.contains("todayRowLeadingInset: CGFloat = 16"))
    }

    /// **And it is deliberately not the list detail's**, which is the half of the ticket that is a
    /// judgement rather than a hoist. `TaskListDisplayMetrics.headerHorizontalInset` is 24 over rows
    /// indented 52 to clear their own leading furniture; the panel's rows start at `MacTaskRow`'s
    /// own horizontal padding, so a 24pt heading over them would be indented from the rows it heads
    /// — the defect `CadencePageHeaderMetrics` keeps its own gutter to avoid.
    @Test func thePanelGutterIsThePanesAndNotThePages() {
        let row = CadenceTaskRowMetrics.desktop.horizontalPadding

        #expect(TasksPanelMetrics.horizontalInset < TaskListDisplayMetrics.headerHorizontalInset)
        #expect(abs(TasksPanelMetrics.horizontalInset - row) <= 2, "the heading sits over its rows")
        #expect(
            TaskListDisplayMetrics.headerHorizontalInset - row > 2,
            "the list detail's inset stopped clearing its own furniture; re-decide the panel's"
        )
    }
}
