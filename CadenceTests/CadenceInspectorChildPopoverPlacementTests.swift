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
/// same bounds, so they are one defect and take one rule.
///
/// **[[T-1722]] — what this file is NOT evidence about, stated before anything below is read.**
/// Every assertion here runs `TaskInspectorChildPopoverPlacement`'s own arithmetic. That is worth
/// having and it is not a reading of the running app: on a real Mac the side a popover opens on is
/// `NSPopover`'s choice, and this suite was green — 14 tests — for the whole of the time the
/// estimate chip's roller was opening across four of the inspector's rows. T-1510 closed on it.
/// The reading of the surface is `CadenceInspectorHeaderPanelPlacementUITests`, which takes the
/// frames off `app.popovers` after a real click, and **that** is the guard for where a panel lands.
///
/// So the claims below were rewritten to be ones a model can honestly make. The old header section
/// asserted that a panel leaves by the end its anchor is pinned to; measured, it does not, and the
/// per-anchor end it asserted no longer exists. What is left is the condition that made the
/// Schedule rows right all along and the header controls wrong: **a column-spanning anchor clears
/// the column at either end, and a pinned one does not.**
///
/// **Failing-first.** Flipping `TaskInspectorChildPopoverPlacement.besideInspector.arrowEdge` to
/// `.bottom` turns `aColumnSpanningAnchorClearsTheColumnAtEitherEnd`'s companion
/// `theShippedPlacementLeavesTheInspectorsRowsIntact` red; dropping
/// `childPlacement: .besideInspector` from any call site turns
/// `everyRowInTheScheduleWellAsksForTheBesideInspectorPlacement` red; and presenting either header
/// panel from its own control again turns `theHeaderPanelsArePresentedFromTheTitleRow` red.
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

    /// The fix, on the edge the placement asks for. Hung off the row's trailing edge — which is
    /// the content column's trailing edge — the panel opens clear of every row the inspector
    /// draws.
    ///
    /// This reads `besideInspector`'s own `arrowEdge` through `panelFrame`, so it is the shipped
    /// request being asserted and not a restatement of it. What it is **not** is a statement about
    /// which edge the panel actually leaves by — see `aColumnSpanningAnchorClearsTheColumnAtEitherEnd`
    /// for the claim that does not depend on that, and the UI suite for the reading.
    @Test
    func theShippedPlacementLeavesTheInspectorsRowsIntact() {
        #expect(Self.occlusion(.besideInspector) == .clear)
        #expect(TaskInspectorChildPopoverPlacement.besideInspector.arrowEdge == .trailing)
    }

    /// **The T-1722 rule.** A field row spans the content column, so *both* of its ends are the
    /// column's ends and a panel hung off either one lands outside every row — whichever end
    /// `NSPopover` picks, and whatever the panel measures.
    ///
    /// This is the assertion the three Schedule rows were always relying on without naming it, and
    /// it is why they survived an inversion that put both header panels over the rows. Swept over
    /// panel widths either side of the column so it is not an artefact of the date panel's.
    @Test
    func aColumnSpanningAnchorClearsTheColumnAtEitherEnd() {
        let row = Self.anchorRow
        for panelWidth in Self.headerPanelWidths {
            let panelSize = CGSize(width: panelWidth, height: Self.datePanelSize.height)
            let column = Self.contentColumn(below: row, panelHeight: panelSize.height)
            #expect(TaskInspectorChildPopoverPlacement.anchorSpansColumn(row, in: column))

            for edge in [Edge.leading, .trailing] {
                let panel = TaskInspectorChildPopoverPlacement
                    .panelFrame(anchoredTo: row, panelSize: panelSize, leavingBy: edge)
                #expect(
                    TaskInspectorChildPopoverPlacement.occlusion(ofColumn: column, byPanel: panel) == .clear,
                    "a \(panelWidth)pt panel leaving a column-spanning row by its \(edge) end still reaches the inspector's rows"
                )
            }
        }
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

    // MARK: - The header controls (T-1510, corrected by T-1722)

    /// A header anchor's *outer* edge is the column's; its inner edge is not. That asymmetry is
    /// why the two header controls could not present their own panels (T-1722): with only one end
    /// safe, the placement depended on a choice the platform makes and the platform chose the
    /// other one. It is asserted before anything is derived from it.
    private static let headerAnchorHeight: CGFloat = 28

    /// The priority tile: the **leading** element of the title row, pinned at the content inset,
    /// sized by the priority mark it draws. The width is swept rather than pinned because the mark
    /// is text and text measures differently across toolchains (T-1492).
    private static func priorityTile(width: CGFloat) -> CGRect {
        CGRect(
            x: TaskInspectorPopoverMetrics.contentInset,
            y: 0,
            width: width,
            height: headerAnchorHeight
        )
    }

    /// The estimate chip: the **trailing**-most element of the same row. It is `.fixedSize()`, so
    /// its width is whatever "Est" or "1h 30m" measures — swept, for the same reason.
    private static func estimateChip(width: CGFloat) -> CGRect {
        CGRect(
            x: TaskInspectorPopoverMetrics.contentInset
                + TaskInspectorPopoverMetrics.contentColumnWidth - width,
            y: 0,
            width: width,
            height: headerAnchorHeight
        )
    }

    /// The column of rows a header panel opens over, made tall enough that the panel always
    /// overlaps it vertically whichever edge it is anchored on. That is deliberate: it means every
    /// `.clear` below is a statement about **x** alone, which is the strongest form of the claim —
    /// "this panel cannot reach the rows however far down the inspector they run".
    private static func headerColumn(panelHeight: CGFloat) -> CGRect {
        CGRect(
            x: TaskInspectorPopoverMetrics.contentInset,
            y: -panelHeight,
            width: TaskInspectorPopoverMetrics.contentColumnWidth,
            height: panelHeight * 3
        )
    }

    /// Plausible widths for a control that sits at one end of the title row, swept so no assertion
    /// below rests on a measured glyph width.
    private static var headerAnchorWidths: [CGFloat] { [24, 28, 36, 52, 80, 120] }

    /// Panel widths swept across every picker the header can open, including the roller's own
    /// `EstimateRollerMetrics.panelWidth` and widths either side of the content column, so the
    /// conclusions are not an artefact of one number.
    private static var headerPanelWidths: [CGFloat] {
        [80, 160, EstimateRollerMetrics.panelWidth, 320, 400]
    }

    private static let headerPanelHeight: CGFloat = 200

    /// The precondition, and after T-1722 the reason the anchor moved: neither header control
    /// spans the content column. The tile reaches the column's leading edge and stops short of its
    /// trailing one; the chip does the reverse.
    @Test
    func neitherHeaderControlSpansTheContentColumn() {
        let column = Self.headerColumn(panelHeight: Self.headerPanelHeight)

        for width in Self.headerAnchorWidths {
            let tile = Self.priorityTile(width: width)
            #expect(tile.minX == column.minX)
            #expect(tile.maxX < column.maxX)
            #expect(!TaskInspectorChildPopoverPlacement.anchorSpansColumn(tile, in: column))

            let chip = Self.estimateChip(width: width)
            #expect(chip.maxX == column.maxX)
            #expect(chip.minX > column.minX)
            #expect(!TaskInspectorChildPopoverPlacement.anchorSpansColumn(chip, in: column))
        }
    }

    /// **Why a header control cannot present its own panel, stated without naming a side.** For
    /// each of the two anchors there is an end that opens back across the inspector's rows. Which
    /// end that is, and which end a running `NSPopover` picks, are different questions — the whole
    /// of T-1722 is that the app does not get to answer the second one — so the claim asserted
    /// here is only that a bad end exists. That is enough to disqualify the anchor.
    @Test
    func eachHeaderControlHasAnEndThatOpensBackAcrossTheRows() {
        let panelHeight = Self.headerPanelHeight
        let column = Self.headerColumn(panelHeight: panelHeight)

        for anchorWidth in Self.headerAnchorWidths {
            for panelWidth in Self.headerPanelWidths {
                let panelSize = CGSize(width: panelWidth, height: panelHeight)

                for anchor in [Self.priorityTile(width: anchorWidth), Self.estimateChip(width: anchorWidth)] {
                    let occlusions = [Edge.leading, .trailing].map { edge in
                        TaskInspectorChildPopoverPlacement.occlusion(
                            ofColumn: column,
                            byPanel: TaskInspectorChildPopoverPlacement
                                .panelFrame(anchoredTo: anchor, panelSize: panelSize, leavingBy: edge)
                        )
                    }
                    #expect(
                        occlusions.contains(where: { $0 != .clear }),
                        "a \(panelWidth)pt panel off a \(anchorWidth)pt header control clears the column at BOTH ends, which would mean the control was a safe anchor after all"
                    )
                }
            }
        }
    }

    /// The fix's call sites. Both header panels are presented from `TaskDetailHeaderSection`'s
    /// title row, on one placement, and neither control presents one of its own — a `.popover` back
    /// on the tile or the chip is the defect returning, because those anchors are the ones the test
    /// above disqualifies.
    @Test
    func theHeaderPanelsArePresentedFromTheTitleRow() throws {
        let headerSource = try CadenceCommitSurfaceScan.scanned(
            "Cadence/macOS/Views/SchedulePanelPopoverSupportViews.swift"
        )
        let header = try #require(
            CadenceSourceScan.declarationBody("struct TaskDetailHeaderSection: View", in: headerSource),
            "TaskDetailHeaderSection no longer reads as a declaration this scan can scope to"
        )

        #expect(
            CadenceSourceScan.matchCount(#"\.popover\("#, in: header) == 1,
            "TaskDetailHeaderSection no longer presents its header panels from exactly one anchor. Two .popover modifiers on one row do not both present — measured, the second one showed nothing — and a panel presented anywhere else is anchored on a control that does not span the content column (T-1722)"
        )
        #expect(
            CadenceSourceScan.matchCount(#"\.popover\(item: presentedPanel"#, in: header) == 1,
            "the header panels no longer share one optional state, so the two can race for the row's anchor again (T-1722)"
        )
        #expect(
            CadenceSourceScan.matchCount(#"arrowEdge:\s*Self\.headerPanelPlacement\.arrowEdge"#, in: header) == 1,
            "the header panel no longer opens on the section's one placement (T-1722)"
        )
        #expect(
            CadenceSourceScan.matchCount(#"arrowEdge:\s*\.[a-z]"#, in: header) == 0,
            "a header picker hand-types an arrow edge again (T-1510)"
        )
        #expect(
            CadenceSourceScan.matchCount(#"\.besideInspector\("#, in: headerSource) == 0,
            "a call site picks the end a panel leaves by again — measured, the platform ignores it (T-1722)"
        )

        let chipSource = try CadenceCommitSurfaceScan.scanned(
            "Cadence/macOS/Views/TaskInspectorFieldSupportViews.swift"
        )
        let chip = try #require(
            CadenceSourceScan.declarationBody("struct TaskInspectorEstimateChip: View", in: chipSource),
            "TaskInspectorEstimateChip no longer reads as a declaration this scan can scope to"
        )
        #expect(
            CadenceSourceScan.matchCount(#"\.popover\("#, in: chip) == 0,
            "TaskInspectorEstimateChip presents a panel off its own bounds again, and its own bounds are the anchor T-1722 measured opening across four of the inspector's rows"
        )
    }

    /// **The ticket's correction, as arithmetic.** T-1510 described both header pickers as
    /// stranding a sliver "per side", which is what a panel centred *in the column* does. A header
    /// control is centred on itself at one end of the column, so a panel at least as wide as its
    /// own anchor reaches past that end and **covers** the column from it — the two-sided `.sliced`
    /// case never arises. Stated as a relation between the panel's width and the anchor's, so it
    /// holds for every picker either control could ever open.
    @Test
    func belowRowCoversAHeaderControlsEndOfTheColumnRatherThanSlicingIt() {
        let panelHeight = Self.headerPanelHeight
        let column = Self.headerColumn(panelHeight: panelHeight)

        for anchorWidth in Self.headerAnchorWidths {
            for panelWidth in Self.headerPanelWidths where panelWidth >= anchorWidth {
                let panelSize = CGSize(width: panelWidth, height: panelHeight)

                for anchor in [Self.priorityTile(width: anchorWidth), Self.estimateChip(width: anchorWidth)] {
                    let panel = TaskInspectorChildPopoverPlacement.belowRow
                        .panelFrame(anchoredTo: anchor, panelSize: panelSize)
                    #expect(
                        TaskInspectorChildPopoverPlacement.occlusion(ofColumn: column, byPanel: panel) == .covered,
                        "a \(panelWidth)pt panel below a \(anchorWidth)pt header control should cover the column from that control's end, not slice it"
                    )
                }
            }
        }
    }

}
#endif
