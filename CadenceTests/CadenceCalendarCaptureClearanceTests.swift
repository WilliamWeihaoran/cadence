import Foundation
import Testing
@testable import Cadence

/// The three statements the iPad Calendar page's capture `+` had to make ([[T-2066]]), and the two
/// of them that look removable.
///
/// **What landed.** `iOSCalendarView` took `.iOSFloatingCreateTaskButton()` so the drag-onto-a-day-
/// column gesture T-2065 gave the phone has a `+` to start from on a tablet too. The layer that
/// modifier installs writes `contentMargins(.bottom, iOSCircularAddButton.scrollClearance, for:
/// .scrollContent)` once, on the page, which is enough on every other host — a page's bottom-
/// reaching list is the first scroll view the inherited value meets. The Calendar page is the one
/// where it is not, in both directions at once:
///
/// - the timed canvas is a **vertical** scroll view nested inside the grid's **horizontal** one, and
///   the outer scroller consumes the value before it arrives. With the page-level write alone the
///   grid stopped dead on midnight and the `+` sat over Saturday 22:37–23:35. So
///   `iOSCalendarTimelineGrid.gridScroller` restates the clearance on the canvas itself.
/// - the toolbar's wrapped control run is a short **horizontal** scroll view that inherited the
///   100pt as cross-axis content region, grew the toolbar by that much, and pushed Month's whole
///   grid down under a band of nothing. So `iOSCalendarToolbar.wrappedToolbar` resets it.
///
/// **Why this file exists at all: neither of those two fails in Week.** The toolbar reset guards a
/// view `ViewThatFits` does not even build at Week's width — it accepts the single row above it —
/// and the nesting defect only shows at the bottom of the timed grid. Someone deleting either line
/// and opening Week, which is the mode anyone checking would open first, would see nothing wrong.
/// A one-line modifier whose absence is invisible in the obvious mode is exactly what a source scan
/// is for.
///
/// **Why source scans and not behaviour.** All four files read here are inside `#if os(iOS)`, so a
/// macOS unit-test host compiles not one of their symbols — there is nothing to instantiate, and
/// where a `contentMargins` value is consumed is a SwiftUI layout fact no test host here can ask
/// about anyway. The house form is `CadenceCodexPageCompletionTypographyTests` and
/// `CadenceListDetailTabStripMarginTests`: scoped declaration slices, comment-stripped source, a
/// self-checking detector, and a non-vacuity guard.
///
/// **What is asserted is position and equality, not a figure.** The restatement is pinned by *where
/// it sits* — inside the horizontal scroller's closure, on the nested canvas's own modifier chain —
/// and by being **the same text** as the layer's own write, rather than by naming 100 or 56. The
/// arithmetic behind that number (56 + 22×2) is already pinned once, in
/// `CadenceListDetailTabStripMarginTests`, and is deliberately not restated here: a decision to
/// resize the button should move one number, not three.
struct CadenceCalendarCaptureClearanceTests {

    // MARK: - (1) The page carries the button

    /// **The fifth host.** Without this the owner's drag has nothing to pick up on iPad, which is
    /// the whole of T-2066. Counted rather than merely found, so a second `+` on one page would
    /// fail too, and run against three files that must **not** carry one — including the file that
    /// *declares* the modifier, which is the nearest thing in the tree to a false positive.
    @Test func theCalendarPageIsAHostOfTheFloatingCaptureButtonAlongsideTheOtherFour() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let takesTheButton = try CadenceScanInstrument(
            "takesTheFloatingCaptureButton",
            fires: "        .iOSFloatingCreateTaskButton()\n",
            andNotOn: "    func iOSFloatingCreateTaskButton(\n"
        ) { $0.contains(".iOSFloatingCreateTaskButton()") }

        for host in [
            "iOSCalendarView.swift",
            "iOSInboxView.swift",
            "iOSListDetailView.swift",
            "iOSTaskCollectionViews.swift",
            "iOSTodayView.swift"
        ] {
            let source = try read("Cadence/iOS/" + host)
            #expect(takesTheButton.fires(on: source), "\(host) no longer takes the floating capture button")
            #expect(
                source.components(separatedBy: ".iOSFloatingCreateTaskButton()").count - 1 == 1,
                "\(host) does not apply the floating capture button exactly once"
            )
        }

        for bystander in [
            "iOSFloatingCreateTaskButton.swift",
            "iOSCalendarTimelineViews.swift",
            "iOSCalendarChromeViews.swift"
        ] {
            #expect(
                takesTheButton.fires(on: try read("Cadence/iOS/" + bystander)) == false,
                "\(bystander) applies a capture button nobody decided on"
            )
        }
    }

    // MARK: - (2) The nested canvas restates what the page's write cannot reach

    /// **Position is the assertion.** A `contentMargins` written on the *outer* horizontal scroller
    /// is the no-op the measurement ruled out, and it would read identically in a `contains` over
    /// the file. So the write is placed by slicing: it is inside the horizontal scroller's trailing
    /// closure — a modifier on that scroller would be outside it — and it is **not** inside the
    /// nested vertical scroller's content closure, which leaves the canvas's own modifier chain.
    ///
    /// **Value is an equality, not a number.** The restatement must be the same text as the one
    /// `iOSFloatingCreateTaskLayer` writes, so the canvas can never drift to a second constant, a
    /// second gate, or a literal of its own — and resizing the button stays a one-line change.
    @Test func theNestedTimedCanvasRestatesTheLayersOwnBottomClearance() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let timeline = try read("Cadence/iOS/iOSCalendarTimelineViews.swift")
        let scroller = try #require(CadenceSourceScan.declarationBody("private func gridScroller(", in: timeline))

        // Scope proof: the slice is the function, not the file. `formBundle(from:adding:)` is the
        // declaration directly above it and gridScroller only passes its *reference*.
        //
        // The needle is `dayColumn(for:`, not `iOSCalendarTimelineDayColumn(`: since [[T-3081]] the
        // grid draws two spans — a scrolling run of days and Today's single pinned column — and
        // builds the column itself in one shared helper so the two cannot drift. The scroller
        // calls that helper; the helper names the view.
        #expect(scroller.contains("dayColumn(for: "))
        #expect(scroller.contains("CadenceTaskMutationSupport.insertBundle") == false)
        #expect(
            timeline.contains("iOSCalendarTimelineDayColumn("),
            "non-vacuity: the helper the scroller calls no longer builds the column"
        )

        #expect(scroller.components(separatedBy: ".contentMargins(").count - 1 == 1)

        let insideHorizontal = try #require(
            CadenceSourceScan.declarationBody("return ScrollView(.horizontal)", in: scroller)
        )
        #expect(
            insideHorizontal.components(separatedBy: ".contentMargins(").count - 1 == 1,
            "the clearance is a modifier on the outer horizontal scroller, where it is consumed and reaches nothing"
        )

        let canvasContent = try #require(
            CadenceSourceScan.declarationBody("ScrollView(.vertical)", in: insideHorizontal)
        )
        #expect(canvasContent.contains("dayColumn(for: "))
        #expect(
            canvasContent.contains(".contentMargins(") == false,
            "the clearance is inside the canvas's content rather than on the canvas"
        )

        let restated = try #require(contentMarginsArgument(in: scroller))
        let layer = try read("Cadence/iOS/iOSFloatingCreateTaskButton.swift")
        let pageLevel = try #require(contentMarginsArgument(in: layer))
        #expect(restated == pageLevel, "the canvas states its own clearance instead of the layer's")
        #expect(restated.contains("iOSCircularAddButton.scrollClearance"))
        #expect(restated.contains("isRegularWidth"))
    }

    // MARK: - (3) The wrapped control run cancels what it inherits

    /// **`D-104`, fourth instance.** Same reset and same reasoning as `iOSListDetailPagePicker`: a
    /// short single-row horizontal scroll view is never a page's bottom-reaching content, so it
    /// must not keep a clearance for a button it does not sit under. The needles are loose on
    /// purpose — `, 0, for: .scrollContent)` accepts `.vertical`, `.bottom` or `.top`; any zero
    /// reset scoped to scroll content is the fix and only the absence of one is the bug.
    ///
    /// The reset is scoped to the `VStack` the control run lives in, so a reset that drifted onto
    /// the `VStack` itself — a whole-toolbar compensation, which is exactly what the layer exists
    /// to prevent — could not satisfy this.
    ///
    /// The last expectation is the one that says why the file exists: the wrapped toolbar is
    /// `ViewThatFits`'s **fallback**, so Week takes the single row and never builds it. That is a
    /// structural fact, not prose, so it is asserted.
    @Test func theCalendarToolbarsWrappedControlRunCancelsTheClearanceAndWeekNeverBuildsIt() throws {
        let chrome = try CadenceSourceScan.strippedSourceReader()("Cadence/iOS/iOSCalendarChromeViews.swift")
        let wrapped = try #require(
            CadenceSourceScan.declarationBody("private var wrappedToolbar: some View", in: chrome)
        )

        // Scope proof: the fallback, not the `ViewThatFits` above it.
        #expect(wrapped.contains("singleRowToolbar") == false)

        let stack = try #require(CadenceSourceScan.declarationBody("VStack(alignment: .leading", in: wrapped))
        #expect(stack.contains("ScrollView(.horizontal"))
        #expect(stack.components(separatedBy: ".contentMargins(").count - 1 == 1)
        #expect(stack.contains(", 0, for: .scrollContent)"))

        let controlRun = try #require(CadenceSourceScan.declarationBody("ScrollView(.horizontal)", in: stack))
        #expect(controlRun.contains("modeControl"))
        #expect(
            controlRun.contains(".contentMargins(") == false,
            "the reset is inside the control run rather than on it"
        )

        // One in the file, so no second compensation crept in beside it.
        #expect(chrome.components(separatedBy: ".contentMargins(").count - 1 == 1)

        // Week's mode: the single row is offered first, so the reset above guards a view the
        // obvious check never renders.
        let toolbar = try #require(CadenceSourceScan.declarationBody("private var toolbar: some View", in: chrome))
        let fits = try #require(CadenceSourceScan.declarationBody("ViewThatFits(in: .horizontal)", in: toolbar))
        let singleRow = try #require(fits.range(of: "singleRowToolbar {"))
        let fallback = try #require(fits.range(of: "wrappedToolbar"))
        #expect(singleRow.lowerBound < fallback.lowerBound)
    }

    // MARK: - Guard on the scans above

    /// **Non-vacuity, and proof the stripper ran.** Every `contains(…) == false` and every
    /// `count - 1 == 1` above is answerable by an empty string, which is what a missing file or a
    /// path mismatch on an isolated build tree produces.
    ///
    /// The stripper is not decoration here: both calendar files carry a comment that *quotes the
    /// very modifier the scans count*, so a scan reading raw text would see two `contentMargins(`
    /// where the code has one, and both per-file counts above would be wrong in the direction that
    /// passes. Asserting raw > stripped is asserting that the comment was removed.
    @Test func theCalendarClearanceScansReadRealSourceThroughARealStripper() throws {
        let read = CadenceSourceScan.strippedSourceReader()

        for (path, declaration, prose) in [
            (
                "Cadence/iOS/iOSCalendarTimelineViews.swift",
                "private func gridScroller(",
                "scroller consumes the inherited value"
            ),
            (
                "Cadence/iOS/iOSCalendarChromeViews.swift",
                "private var wrappedToolbar: some View",
                "Week never showed it"
            )
        ] {
            let raw = try CadenceSourceScan.sourceFile(path)
            #expect(raw.count > 3_000, "\(path) read as \(raw.count) characters")
            #expect(raw.contains(declaration))

            let stripped = try read(path)
            #expect(stripped.count == raw.count, "the stripper is not length-preserving")
            #expect(stripped.contains(declaration))

            let rawWrites = raw.components(separatedBy: "contentMargins(").count - 1
            let codeWrites = stripped.components(separatedBy: "contentMargins(").count - 1
            #expect(codeWrites == 1)
            #expect(rawWrites > codeWrites, "\(path) no longer explains the clearance it states")
            #expect(raw.contains(prose), "\(path) no longer explains the clearance it states")
            #expect(stripped.contains(prose) == false, "the stripper left prose in \(path)")
        }

        let calendar = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarView.swift")
        #expect(calendar.count > 3_000, "iOSCalendarView.swift read as \(calendar.count) characters")
        #expect(calendar.contains("struct iOSCalendarView: View"))
    }
}

// MARK: - Helpers

/// The balanced argument list of the **first** `.contentMargins(` in `source`, braces of the call
/// included, or `nil` when there is none.
///
/// Brace-matched rather than read to the end of the line: the comparison these scans make is
/// between two call sites in two files, and a line-based read would make that comparison depend on
/// where a formatter happened to wrap.
private func contentMarginsArgument(in source: String) -> String? {
    guard let opening = source.range(of: ".contentMargins(") else { return nil }
    return CadenceSourceScan.matchedBody(
        after: source.index(before: opening.upperBound),
        in: source,
        open: "(",
        close: ")"
    )
}
