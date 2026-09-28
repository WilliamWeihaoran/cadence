import Foundation
import SwiftUI
import Testing
@testable import Cadence

#if os(macOS)

/// T-1480: opening *Do* on the macOS task inspector drew the date panel on top of the inspector
/// that opened it and cut that inspector's own rows into fragments — the Due row surviving as the
/// word "Set", Repeat as "er", the Subtasks and Notes headings as "SUB" and "NOT".
///
/// **Why this is a test and not a screenshot.** A macOS popover is its own `NSWindow`. A capture
/// of the app's main window cannot see it at all, and a capture of one popover's window cannot see
/// the other — so no pixel fixture can show these two frames together (T-1487). What the defect
/// *is*, though, is two rectangles: a panel narrower than the inspector's content column, centred
/// inside it. That is arithmetic, and arithmetic is what this file asserts.
///
/// **It is a placement defect, not a size one**, and
/// `shrinkingThePanelWidensTheSliversInsteadOfClosingThem` is the half of this file that says so
/// out loud: every point taken off the panel's width is a point *added* to the fragments either
/// side of it. [[T-1440]] made the panel taller by folding the weekday headings inside its bounded
/// height, which is how an overlap that was always there became legible; it did not create one.
///
/// **Scope.** All three rows of the inspector's Schedule well — Do, Due, Repeat — not only the one
/// the screenshot caught. Each opens a panel narrower than the same column, off a row with the
/// same bounds, so they are one defect and take one rule. The inspector's two *header* controls
/// (the priority tile and the estimate chip) are deliberately **not** here: their anchors are a
/// 28pt tile at the leading edge and a chip at the trailing one, so the same `.trailing` answer is
/// right for one and wrong for the other. That is [[T-1510]].
///
/// **Failing-first.** Flipping `TaskInspectorChildPopoverPlacement.besideInspector.arrowEdge` back
/// to `.bottom` turns `theShippedPlacementLeavesTheInspectorsRowsIntact` red, and dropping
/// `childPlacement: .besideInspector` from any call site turns
/// `everyRowInTheScheduleWellAsksForTheBesideInspectorPlacement` red.
struct CadenceInspectorChildPopoverPlacementTests {

    // MARK: - Fixtures

    /// The inspector's row band. `x` is the content inset and the width is the column the field
    /// rows span — they carry their own inner inset so a hover can wash the full width of the
    /// well, so a row's bounds *are* this column's bounds.
    ///
    /// The height is a fixture, not a claim: it is whatever leaves rows below the anchor for a
    /// panel to land on, which is the situation the defect describes.
    private static func contentColumn(below anchor: CGRect, panelHeight: CGFloat) -> CGRect {
        CGRect(
            x: TaskInspectorPopoverMetrics.contentInset,
            y: 0,
            width: TaskInspectorPopoverMetrics.contentColumnWidth,
            height: anchor.maxY + panelHeight
        )
    }

    /// The *Do* row: full width of the content column, a field row tall, a few rows down from the
    /// top of the inspector. Only its edges matter here — which rows sit above it is the part the
    /// screenshot shows and the geometry does not need.
    private static var anchorRow: CGRect {
        CGRect(
            x: TaskInspectorPopoverMetrics.contentInset,
            y: TaskInspectorFieldRowMetrics.minHeight * 3,
            width: TaskInspectorPopoverMetrics.contentColumnWidth,
            height: TaskInspectorFieldRowMetrics.minHeight
        )
    }

    /// The date panel as the inspector presents it: the shared month-grid width, over a height
    /// that only has to be enough to reach the rows under the anchor.
    private static var datePanelSize: CGSize {
        CGSize(
            width: CadenceDateSelectionMetrics.width(at: .large),
            height: CadenceDateSelectionMetrics.quickViewportHeight(at: .large, inlineStyle: false)
        )
    }

    private static func occlusion(
        _ placement: TaskInspectorChildPopoverPlacement,
        panelSize: CGSize = datePanelSize
    ) -> InspectorColumnOcclusion {
        let panel = placement.panelFrame(anchoredTo: anchorRow, panelSize: panelSize)
        let column = contentColumn(below: anchorRow, panelHeight: panelSize.height)
        return TaskInspectorChildPopoverPlacement.occlusion(ofColumn: column, byPanel: panel)
    }

    // MARK: - The overlap, as geometry

    /// The precondition that makes slicing possible at all, asserted as a relation rather than as
    /// either number: the panel is narrower than the band of rows it opens over.
    @Test
    func theDatePanelIsNarrowerThanTheInspectorsContentColumn() {
        #expect(Self.datePanelSize.width < TaskInspectorPopoverMetrics.contentColumnWidth)
    }

    /// The defect, reproduced. Anchored under its own row, the panel lands strictly inside the
    /// content column and strands a sliver of every row beneath it on **both** sides.
    @Test
    func anchoringTheDatePanelUnderItsRowSlicesTheInspectorsOwnRows() {
        #expect(Self.occlusion(.belowRow) == .sliced)
    }

    /// The fix. Hung off the row's trailing edge — which is the content column's trailing edge —
    /// the panel opens clear of every row the inspector draws.
    ///
    /// This reads `besideInspector`'s own `arrowEdge` through `panelFrame`, so it is the shipped
    /// placement being asserted and not a restatement of it.
    @Test
    func theShippedPlacementLeavesTheInspectorsRowsIntact() {
        #expect(Self.occlusion(.besideInspector) == .clear)
        #expect(TaskInspectorChildPopoverPlacement.besideInspector.arrowEdge == .trailing)
    }

    /// **The ticket's central claim, as arithmetic.** A narrower panel does not help: the stranded
    /// fragments are what the column has *left over*, so taking width off the panel gives it back
    /// to them. Asserted as a strict relation between two panel widths, so it holds whatever the
    /// month grid measures on the machine running it.
    @Test
    func shrinkingThePanelWidensTheSliversInsteadOfClosingThem() {
        let full = Self.datePanelSize
        let shrunk = CGSize(width: full.width / 2, height: full.height)

        let column = Self.contentColumn(below: Self.anchorRow, panelHeight: full.height)
        let fullPanel = TaskInspectorChildPopoverPlacement.belowRow
            .panelFrame(anchoredTo: Self.anchorRow, panelSize: full)
        let shrunkPanel = TaskInspectorChildPopoverPlacement.belowRow
            .panelFrame(anchoredTo: Self.anchorRow, panelSize: shrunk)

        #expect(Self.occlusion(.belowRow, panelSize: shrunk) == .sliced)
        #expect(shrunkPanel.minX - column.minX > fullPanel.minX - column.minX)
        #expect(column.maxX - shrunkPanel.maxX > column.maxX - fullPanel.maxX)
    }

    /// The classifier earns its third case: a panel that reaches a side of the column covers what
    /// it overlaps rather than fragmenting it. Without this, `.sliced` would just be a synonym for
    /// "overlaps" and the tests above would say less than they appear to.
    @Test
    func aPanelThatReachesASideOfTheColumnCoversRatherThanSlices() {
        let column = Self.contentColumn(below: Self.anchorRow, panelHeight: Self.datePanelSize.height)
        let wider = CGRect(
            x: column.minX - 1,
            y: Self.anchorRow.maxY,
            width: column.width + 2,
            height: Self.datePanelSize.height
        )
        #expect(TaskInspectorChildPopoverPlacement.occlusion(ofColumn: column, byPanel: wider) == .covered)

        let flushTrailing = CGRect(
            x: column.midX,
            y: Self.anchorRow.maxY,
            width: column.width,
            height: Self.datePanelSize.height
        )
        #expect(
            TaskInspectorChildPopoverPlacement.occlusion(ofColumn: column, byPanel: flushTrailing) == .covered
        )
    }

    // MARK: - The call sites

    /// **Every** row in the inspector's Schedule well asks for the beside-inspector placement, not
    /// just the one the screenshot caught. *Do* is the row that opened the panel; *Due* and
    /// *Repeat* are two of the rows it sliced ("Set" and "er"), and each of them opens a panel of
    /// its own that is narrower than the same column. One well, one rule.
    ///
    /// Counted as a **relation between two counts** rather than against a fixed three, so a fourth
    /// row added to this well is caught rather than ignored.
    @Test
    func everyRowInTheScheduleWellAsksForTheBesideInspectorPlacement() throws {
        let source = try CadenceCommitSurfaceScan.scanned(
            "Cadence/macOS/Views/SchedulePanelPopoverSupportViews.swift"
        )
        let body = try #require(
            CadenceSourceScan.declarationBody("struct TaskDetailScheduleGroupSection: View", in: source),
            "TaskDetailScheduleGroupSection no longer reads as a declaration this scan can scope to"
        )

        let controls = CadenceSourceScan.matchCount(
            #"TaskInspector(DateControl|RecurrenceControl)\("#, in: body
        )
        let placements = CadenceSourceScan.matchCount(
            #"childPlacement:\s*\.besideInspector"#, in: body
        )
        #expect(controls >= 3, "expected at least the Do, Due and Repeat rows, found \(controls)")
        #expect(
            placements == controls,
            "a row in the inspector's Schedule well no longer asks for .besideInspector, so its panel slices the rows below it (T-1480)"
        )
    }

    /// Each control presents its panel on the placement it was handed, not on an edge typed into
    /// the modifier. A hand-typed `arrowEdge:` there would make the parameter decorative and the
    /// geometry tests above vacuous — the call sites would read as fixed while the panel kept
    /// opening wherever the literal said.
    @Test
    func theScheduleControlsPresentOnThePlacementTheyWereHanded() throws {
        let sites = [
            ("Cadence/macOS/Views/TaskInspectorFieldSupportViews.swift", "struct TaskInspectorDateControl: View"),
            ("Cadence/macOS/Views/TaskInspectorWorkflowSupportViews.swift", "struct TaskInspectorRecurrenceControl: View"),
        ]

        for (path, declaration) in sites {
            let source = try CadenceCommitSurfaceScan.scanned(path)
            let body = try #require(
                CadenceSourceScan.declarationBody(declaration, in: source),
                "\(declaration) no longer reads as a declaration this scan can scope to"
            )

            #expect(
                CadenceSourceScan.matchCount(#"arrowEdge:\s*childPlacement\.arrowEdge"#, in: body) == 1,
                "\(declaration) no longer presents its panel on the placement it was handed (T-1480)"
            )
            #expect(
                CadenceSourceScan.matchCount(#"arrowEdge:\s*\.[a-z]"#, in: body) == 0,
                "\(declaration) hand-types an arrow edge again, so childPlacement no longer decides where the panel lands (T-1480)"
            )
        }
    }
}
#endif
