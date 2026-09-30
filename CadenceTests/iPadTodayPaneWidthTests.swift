import AppKit
import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import Cadence

/// The two-pane Today layout puts a fixed-width task column beside a 1pt `Divider()` and an
/// inspector that declares a `minWidth`. An `HStack` will not shrink a fixed `.frame(width:)` to
/// make room — it lets the content overflow, and the shell hard-sizes the pane and clips it. So the
/// one property that matters is that **all three** fit: task + divider + floor never exceed the
/// pane.
///
/// It has been wrong in both directions. First the task column asked for 420 where 312 remained and
/// the capture field's leading edge ran off the screen. Then, more quietly, the divider went
/// uncounted and the row asked for exactly one point more than it had.
///
/// **These call the real functions.** They used to re-implement `taskPaneWidth` and the inspector
/// floor, because both were `private` on a `#if os(iOS)` view this target cannot see — so the file
/// tested a copy, the copy drifted, and the assertion below omitted the same divider the code did.
/// A test that mirrors the bug cannot catch the bug. Both rules now live on
/// `CadenceTodayLayoutSupport`, beside the floor they have to agree with.
@MainActor
struct iPadTodayPaneWidthTests {
    private func inspectorFloor(for paneWidth: CGFloat) -> CGFloat {
        CadenceTodayLayoutSupport.inspectorPaneFloor(forPaneWidth: paneWidth)
    }

    private func taskPaneWidth(for paneWidth: CGFloat) -> CGFloat {
        CadenceTodayLayoutSupport.taskPaneWidth(forPaneWidth: paneWidth)
    }

    /// Pane widths that reach the two-pane layout at all — i.e. clear the 761pt floor. The shell
    /// sidebar is 188pt when it is out and 0 when the user folds it, and the fold is what puts a
    /// full-screen portrait iPad in this list.
    ///
    /// The unlovely ones are the boundaries of the two bands where `available` is the binding clamp
    /// and the missing divider therefore showed: [761, 841) and [900, 928). 840 and 927 are the last
    /// widths that overflowed; 841 and 928 are the first that did not.
    fileprivate static let panes: [CGFloat] = [
        761,   // twoPaneMinimumWidth — the narrowest pane this layout renders in at all
        795,   // 2/3 Split View, landscape, sidebar folded
        834,   // iPad Pro 11" portrait, full screen, sidebar folded
        840, 841,   // first band's upper boundary
        900, 927, 928, // second band — only a resized window lands here
        1_022, // iPad Pro 11" landscape, full screen, sidebar out (1210 − 188)
        1_210, // iPad Pro 11" landscape, full screen, sidebar folded — the widest pane there is
    ]

    /// The property the whole file exists for, **including the divider**. Without that term this
    /// passed at 834 and 840 while the row asked for `pane + 1`.
    @Test
    func theThreeColumnsNeverAskForMoreThanThePaneTheyAreGiven() {
        for pane in Self.panes {
            let task = taskPaneWidth(for: pane)
            let total = task + CadenceTodayLayoutSupport.paneDividerWidth + inspectorFloor(for: pane)
            #expect(
                total <= pane,
                "pane \(pane): task \(task) + divider + floor \(inspectorFloor(for: pane)) = \(total)"
            )
        }
    }

    /// The two widths an off-by-one is likeliest to miss, spelled out rather than swept: 840 is the
    /// last pane in the first band, and 927 the last in the second. Both used to come to `pane + 1`.
    @Test
    func theTwoBandBoundariesFitToThePoint() {
        for pane in [CGFloat(840), 927] {
            #expect(
                taskPaneWidth(for: pane) + CadenceTodayLayoutSupport.paneDividerWidth
                    + inspectorFloor(for: pane) <= pane,
                "pane \(pane) still overflows"
            )
        }
    }

    /// And the fix is not "shrink the task column until nothing overflows": at the two-pane floor
    /// the column lands on its own declared minimum exactly, which is what that floor is a sum of.
    @Test
    func theNarrowestTwoPaneLayoutGivesTheTaskColumnExactlyItsDeclaredMinimum() {
        #expect(
            taskPaneWidth(for: CadenceTodayLayoutSupport.twoPaneMinimumWidth)
                == CadenceTodayLayoutSupport.taskPaneMinWidth
        )
    }

    @Test
    func theTaskColumnIsNeverWiderThanThePaneItself() {
        for pane in Self.panes {
            #expect(taskPaneWidth(for: pane) <= pane)
            #expect(taskPaneWidth(for: pane) > 0)
        }
    }

    @Test
    func roomyPanesStillGetThePreferredProportionRatherThanTheFloor() {
        // 1022pt of pane: 60% is 613, comfortably inside what is available, so the preference
        // should win rather than being clamped away.
        #expect(taskPaneWidth(for: 1_022) == 1_022 * 0.60)
    }

    /// Replaces an assertion that pinned the old 760pt cap at a 2000pt pane — a width no target
    /// device produces. The widest is 1210: an 11" Pro in landscape with the shell sidebar folded.
    /// What has to hold there is the property the cap was standing in for.
    @Test
    func theWidestReachablePaneKeepsItsProportionAndStillPaysTheInspector() {
        #expect(taskPaneWidth(for: 1_210) == 1_210 * 0.60)
        #expect(1_210 - taskPaneWidth(for: 1_210) >= inspectorFloor(for: 1_210))
    }

    /// **Both inspector floors are live**, which is why `inspectorPaneFloor(forPaneWidth:)` still
    /// has two values. 834 is a full-screen portrait iPad with the sidebar folded: past the 761pt
    /// two-pane floor, so this layout renders, and under 900, so it takes the narrow floor. Fold the
    /// sidebar in landscape instead and the same device is 1210, which takes the wide one.
    @Test
    func aFoldedPortraitPaneIsWhatKeepsTheNarrowInspectorFloorAlive() {
        #expect(834 >= CadenceTodayLayoutSupport.twoPaneMinimumWidth)
        #expect(inspectorFloor(for: 834) == CadenceTodayLayoutSupport.inspectorPaneMinWidth)
        #expect(inspectorFloor(for: 1_210) == CadenceTodayLayoutSupport.inspectorPaneWideMinWidth)
        // With the sidebar out the same portrait window is 646pt of pane, which is one column.
        #expect(CadenceTodayLayoutSupport.layout(isRegularWidth: true, paneWidth: 646) == .compact)
        #expect(CadenceTodayLayoutSupport.layout(isRegularWidth: true, paneWidth: 834) == .twoPane)
    }

    /// The inspector's ideal never asks for more than the pane has left either, at any width the
    /// layout actually renders at.
    @Test
    func theInspectorsIdealNeverExceedsWhatIsLeftBesideTheTaskColumn() {
        for pane in Self.panes {
            let remaining = pane - taskPaneWidth(for: pane) - CadenceTodayLayoutSupport.paneDividerWidth
            #expect(
                CadenceTodayLayoutSupport.inspectorPaneIdealWidth(forPaneWidth: pane) >= inspectorFloor(for: pane)
            )
            #expect(remaining >= inspectorFloor(for: pane), "pane \(pane) left the inspector \(remaining)")
        }
    }

    /// A pane narrower than the inspector's own floor has no good answer; what matters is that it
    /// produces a sane one rather than a negative width. A zero-width pane correctly yields zero —
    /// the first version of this test asserted `> 0` there, which was the assertion being wrong
    /// rather than the code.
    @Test
    func adegeneratePaneDoesNotProduceANegativeWidth() {
        for pane in [CGFloat(0), 100, 320, 321, 760] {
            let result = taskPaneWidth(for: pane)
            #expect(result >= 0)
            #expect(result <= max(pane, 0))
        }
    }
}

/// **T-586.** The iPad Today rail is one surface, whichever half is selected.
///
/// The switcher strip drew `Theme.bg`, the Timeline half drew `Theme.bg`, and the Notes half drew
/// `Theme.surface` — so tapping the switcher changed the pane's background colour, and whichever
/// half was showing either matched the strip above it or the task column across the divider, never
/// both. `Theme.surface` is the side that wins: it is what the task column beside the rail draws
/// from its own header down, and `iOSNotesView` is hosted standalone as well as here, so it is the
/// one of the two halves that could not be changed without changing a page outside Today.
///
/// A scan, because all four files are behind `#if os(iOS)` and this target builds for macOS.
@MainActor
struct iPadTodayRailSurfaceTests {
    private func source(_ path: String) throws -> String {
        let raw = try CadenceSourceScan.sourceFile(path)
        #expect(raw.count > 400, "\(path) read as \(raw.count) characters")
        let stripped = CadenceSourceScan.strippingComments(raw)
        #expect(stripped != raw, "non-vacuity: \(path) carries no comments to strip")
        return stripped
    }

    private func dense(_ text: String) -> String {
        text.filter { !$0.isWhitespace }
    }

    /// Both halves of the rail, and the same background on each — down to the safe area, which the
    /// timeline half used to stop at while the notes half did not.
    @Test func bothHalvesOfTheTodayRailDrawTheSameBackground() throws {
        let timeline = try source("Cadence/iOS/iOSTodaySchedulePanel.swift")
        #expect(timeline.contains("struct iOSSchedulePanel: View {"), "non-vacuity: wrong file read")
        #expect(dense(timeline).contains(".background(Theme.surface.ignoresSafeArea())"))
        #expect(
            CadenceSourceScan.matchCount(#"\.background\(Theme\.bg"#, in: timeline) == 0,
            "the Today timeline pane is drawing the page background again (T-586)"
        )

        let notes = try source("Cadence/iOS/iOSNotesView.swift")
        #expect(notes.contains("struct iOSNotesView: View {"), "non-vacuity: wrong file read")
        #expect(dense(notes).contains(".background(Theme.surface.ignoresSafeArea())"))
    }

    /// And the strip that selects between them, which is the rail's header. A column is one surface
    /// from its header down — which is exactly what `todayTaskColumn` does on the other side of the
    /// divider, and the comparison the choice was made against.
    @Test func theRailsSwitcherStripSitsOnTheSameSurfaceAsTheHalvesItSelects() throws {
        let support = try source("Cadence/iOS/iPadTodaySupportViews.swift")
        let signature = try #require(
            support.range(of: "struct iPadTodayInspectorSwitcher: View {"),
            "iPadTodayInspectorSwitcher is gone"
        )
        let switcher = try #require(
            CadenceSourceScan.matchedBody(after: signature.lowerBound, in: support, open: "{", close: "}"),
            "iPadTodayInspectorSwitcher's braces never balanced"
        )
        #expect(dense(switcher).contains(".background(Theme.surface)"))
        #expect(
            CadenceSourceScan.matchCount(#"Theme\.bg"#, in: switcher) == 0,
            "the rail's header is back on the page background while its panes are not (T-586)"
        )

        let today = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTodayView.swift")
        )
        #expect(today.contains("struct iOSTodayView: View {"), "non-vacuity: wrong file read")
        // The reference the choice was made against: the task column across the divider draws
        // `Theme.surface` under its header and under its list.
        #expect(CadenceSourceScan.matchCount(#"\.background\(Theme\.surface\)"#, in: today) >= 2)
    }

    // MARK: - T-1277: the Notes half opens a note in place

    /// **Tapping a note in Today's right-hand pane used to leave Today.**
    ///
    /// The owner: *"when i click on the notes here shown in the picture, it opens up a whole new
    /// page to edit the notes. i dont want that. i want it to open that note right in that right
    /// panel."* `open(_:)` in `iOSNotesView` sent every one-column host to `presentedNote`, and Today's
    /// inspector is a one-column host — 320pt at its floor is under
    /// `CadenceNotesListMetrics.twoColumnMinimumWidth` — so a `.fullScreenCover` covered the task
    /// column that is the entire reason the split exists.
    ///
    /// The fork is on the **size class**, not the layout, and that is the half worth pinning: a
    /// phone's one-column form must still present a cover, because there the list is the whole
    /// screen and there is nothing behind it to keep.
    ///
    /// Source shape rather than behaviour, for this suite's usual reason — `Cadence/iOS/` is behind
    /// `#if os(iOS)` and this target builds for macOS.
    @Test func aRegularWidthOneColumnPaneOpensANoteInItselfAndAPhoneStillPushesOne() throws {
        let notes = try source("Cadence/iOS/iOSNotesView.swift")
        #expect(notes.contains("struct iOSNotesView: View {"), "non-vacuity: wrong file read")

        let signature = try #require(
            notes.range(of: "private func open(_ note: Note) {"),
            "iOSNotesView.open(_:) is gone"
        )
        let open = try #require(
            CadenceSourceScan.matchedBody(after: signature.lowerBound, in: notes, open: "{", close: "}"),
            "open(_:)'s braces never balanced"
        )

        // The layout guard first — a two-column host still just selects, because the editor beside
        // the list is already showing what was tapped.
        #expect(dense(open).contains("guardnotesLayout==.oneColumnelse{return}"))
        // Then the size class. The regular-width arm sets the flag and returns before either
        // presentation state below it can be written.
        #expect(dense(open).contains("guardisCompactWidthelse{showsInlineEditor=truereturn}"))
        // And the phone's two presentations are still there, on the far side of that guard.
        #expect(open.contains("selectedMeetingNote = note"))
        #expect(open.contains("presentedNote = note"))
        #expect(
            CadenceSourceScan.matchCount(#"presentedNote = note"#, in: notes) == 1,
            "a second site presents the cover; the size-class fork is no longer the only way in"
        )

        // The pane draws the note instead of the index, rather than over it.
        #expect(dense(notes).contains("case.oneColumn:ifisShowingInlineEditor{editorPane}else{sidebar}"))
        #expect(
            notes.contains(
                "showsInlineEditor && notesLayout == .oneColumn && !isCompactWidth && selectedNote != nil"
            ),
            "the inline editor no longer checks all three of the conditions it may draw under"
        )
    }

    /// **The way back, and why it cannot be the system's.** Nothing is pushed — the pane swapped its
    /// own contents — so there is no navigation stack to pop, and `iPadTodayInspectorSwitcher` is
    /// the only row above this pane. The header's existing back control is what returns the index,
    /// and the inline case is ordered *first* so it wins over the pushed-compact-screen case.
    ///
    /// Switching tabs also returns the index: the tab strip is the one control on that header that
    /// names a destination, so it must not land inside an editor for a note nobody tapped.
    @Test func theNotesHeaderCarriesTheWayBackOutOfTheInlineEditor() throws {
        let notes = try source("Cadence/iOS/iOSNotesView.swift")

        #expect(
            notes.contains("onBack: backAction,"),
            "the notes header no longer takes the resolved back action"
        )

        let signature = try #require(
            notes.range(of: "private var backAction: (() -> Void)? {"),
            "backAction is gone"
        )
        let action = try #require(
            CadenceSourceScan.matchedBody(after: signature.lowerBound, in: notes, open: "{", close: "}"),
            "backAction's braces never balanced"
        )
        #expect(dense(action).contains("ifisShowingInlineEditor{returncloseInlineEditor}"))
        #expect(dense(action).contains("guardisCompactWidth,!isCompactTabRootelse{returnnil}"))
        // Order, not just presence: the inline arm must be the one that answers when both could.
        let inline = try #require(action.range(of: "isShowingInlineEditor"))
        let pushed = try #require(action.range(of: "isCompactTabRoot"))
        #expect(inline.lowerBound < pushed.lowerBound, "the pushed-screen arm now answers first")

        // Leaving drops first responder before the view that owns the text view goes away.
        let closeSignature = try #require(
            notes.range(of: "private func closeInlineEditor() {"),
            "closeInlineEditor is gone"
        )
        let close = try #require(
            CadenceSourceScan.matchedBody(after: closeSignature.lowerBound, in: notes, open: "{", close: "}"),
            "closeInlineEditor's braces never balanced"
        )
        #expect(dense(close).contains("isEditorFocused=false"))
        #expect(dense(close).contains("showsInlineEditor=false"))

        // The tab strip is the other way out.
        #expect(
            dense(notes).contains(".onChange(of:activeTab){_,_inisEditorFocused=falseshowsInlineEditor=falseselectDefaultNote()}"),
            "switching tabs no longer returns the index"
        )
    }

    /// **A note keeps its chrome whichever column it was reached from**, which is
    /// `iOSNoteEditorCover`'s own stated rule. The cover carries the AI and export controls in its
    /// navigation bar; the inline pane has no navigation bar, so the header carries them instead —
    /// otherwise deleting the cover from this host would quietly delete two of the note's actions.
    @Test func aNoteOpenedInThePaneKeepsTheControlsTheCoverWouldHaveGivenIt() throws {
        let notes = try source("Cadence/iOS/iOSNotesView.swift")
        let condition = "if showsHeaderTemplateMenu || isShowingInlineEditor, let note = selectedNote {"
        #expect(
            CadenceSourceScan.matchCount(
                #"if showsHeaderTemplateMenu \|\| isShowingInlineEditor, let note = selectedNote \{"#,
                in: notes
            ) == 2,
            "the AI and export controls are not both offered to the in-pane editor"
        )
        #expect(notes.contains(condition))
        #expect(notes.contains("iOSNoteAIActionsMenu(note: note, area: note.area, project: note.project)"))
        #expect(notes.contains("iOSNoteExportMenu(note: note)"))

        // The template control is deliberately *not* in that pair: `editorPane` hands it to the
        // editor's own format row whenever the header is not carrying it, so it moves rather than
        // disappearing. Pinned so a later pass does not "fix" the asymmetry into a duplicate.
        #expect(notes.contains("templateKind: showsHeaderTemplateMenu ? nil : activeTab.coreTab?.noteKind"))
        #expect(
            notes.contains("if showsHeaderTemplateMenu, let coreTab = activeTab.coreTab, let note = selectedNote {"),
            "the header template menu changed gate; recheck it against the editor's format row"
        )
    }
}

/// **T-1702: what the Today header's eyebrow line is actually given, against what it is asked to
/// draw.**
///
/// The owner photographed an iPad Pro 11" in portrait (834×1210) with the shell sidebar folded.
/// Unfolded the pane is 646pt, Today is one full-width column, and the header reads `TUESDAY,
/// SEPTEMBER 29 · 3 timed · 1 done` in full. Folded, the detail gets the whole 834pt window, the
/// layout turns two-pane, and the same header clips to `TUESDAY, SEPTEMBER 29 · 3 ti…` — dropping
/// the only statement of the day's counts anywhere on the page.
///
/// **The budget is not the pane, and it is not the column either.** `iOSPageHeader` at
/// `role: .pane` is one `HStack`: title column, `Spacer(minLength: 8)`, count capsule, then
/// `trailing()` carrying `.layoutPriority(1)` — on Today, `iOSTaskViewOptionsBar`'s two chips. The
/// eyebrow receives what is left *after* those have taken their intrinsic widths. At 834 the column
/// is 513pt and the eyebrow line gets about 160 of it, against roughly 250 for the full line. So a
/// width-driven rule in `CadenceTodayLayoutSupport` would have been keyed on the wrong number;
/// `CadencePageHeaderEyebrow` takes no width at all and lets `ViewThatFits` do the measuring.
///
/// **What is asserted is a relation, never a point figure** (T-1279/T-1296: CI runs Xcode 26 and
/// this Mac 27.0, and system font advances are not a constant to pin). Every term is read from the
/// metrics types — `CadencePageHeaderMetrics`, `SectionEyebrowLabel`, `CadenceTodayLayoutSupport`,
/// `CadenceTaskSortMode` — except the three figures `iOSTaskViewOptionsBar` keeps `private` behind
/// `#if os(iOS)`, which are restated here and pinned against that source below.
@MainActor
struct iPadTodayHeaderEyebrowBudgetTests {

    // MARK: - The three restated figures

    /// `iOSTaskViewOptionsBar.fontSize`. Private, and behind `#if os(iOS)`, so this target cannot
    /// read it; `theRestatedOptionsBarFiguresStillMatchTheSource` is what stops the copy drifting.
    private static let optionsChipFontSize: CGFloat = 13
    /// `iOSTaskViewOptionsBar.horizontalPadding`, per side.
    private static let optionsChipHorizontalPadding: CGFloat = 12
    /// The bar's own `HStack(spacing:)` between its two chips.
    private static let optionsChipSpacing: CGFloat = 10
    /// The gap SwiftUI's own `Label` leaves between its icon and its title. Not a Cadence figure
    /// and not readable from one, so it is an allowance — deliberately generous, since overstating
    /// the trailing controls understates the budget and can only make the relation below harder.
    private static let labelIconGap: CGFloat = 6

    // MARK: - Measurement

    private static func width(_ text: String, size: CGFloat, weight: NSFont.Weight, kerning: CGFloat = 0) -> CGFloat {
        var attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight)]
        if kerning != 0 { attributes[.kern] = kerning }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        return CTLineGetTypographicBounds(line, nil, nil, nil)
    }

    /// `SectionEyebrowLabel` uppercases its own text and tracks it by the one ratio.
    private static func eyebrowWidth(_ text: String, _ metrics: CadencePageHeaderMetrics) -> CGFloat {
        width(
            text.uppercased(),
            size: metrics.eyebrowSize,
            weight: .semibold,
            kerning: metrics.eyebrowSize * SectionEyebrowLabel.kerningRatio
        )
    }

    /// The detail clause, drawn as the view draws it — with the middle dot the view prepends.
    private static func detailWidth(_ text: String, _ metrics: CadencePageHeaderMetrics) -> CGFloat {
        width("· \(text)", size: metrics.eyebrowSize, weight: .medium)
    }

    /// The widest run a wrapping `Text` cannot break, which is what the stacked rung actually needs.
    private static func longestDetailRun(_ text: String, _ metrics: CadencePageHeaderMetrics) -> CGFloat {
        ("· " + text)
            .split(separator: " ")
            .map { width(String($0), size: metrics.eyebrowSize, weight: .medium) }
            .max() ?? 0
    }

    private static func countCapsuleWidth(_ count: Int, _ metrics: CadencePageHeaderMetrics) -> CGFloat {
        width("\(count)", size: metrics.countSize, weight: .bold) + metrics.countPaddingH * 2
    }

    /// `iOSTaskViewOptionsBar(spreads: false)`: a sort chip carrying a `Label`, then the completed
    /// chip. The sort title is whichever the user last chose, so the widest one is the honest term.
    private static func optionsBarWidth(completedCount: Int) -> CGFloat {
        let widestSortTitle = CadenceTaskSortMode.allCases
            .map { width($0.title, size: optionsChipFontSize, weight: .semibold) }
            .max() ?? 0
        let glyph = NSImage(systemSymbolName: "arrow.up.arrow.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: optionsChipFontSize, weight: .semibold))?
            .size.width ?? 0
        let sortChip = widestSortTitle + glyph + labelIconGap + optionsChipHorizontalPadding * 2
        let completedLabel = completedCount > 0 ? "Completed \(completedCount)" : "Completed"
        let completedChip = width(completedLabel, size: optionsChipFontSize, weight: .semibold)
            + optionsChipHorizontalPadding * 2
        return sortChip + optionsChipSpacing + completedChip
    }

    /// Everything the `.pane` header's row spends before the eyebrow is measured, subtracted from
    /// the column `CadenceTodayLayoutSupport` hands it. Four children, so three `rowSpacing` gaps,
    /// plus the `Spacer`'s own declared minimum.
    private static func eyebrowBudget(paneWidth: CGFloat, summary: CadenceTodaySummary) -> CGFloat {
        let metrics = CadencePageHeaderMetrics.metrics(role: .pane, isRegularWidth: true)
        return CadenceTodayLayoutSupport.taskPaneWidth(forPaneWidth: paneWidth)
            - metrics.horizontalPadding * 2
            - metrics.rowSpacing * 3
            - 8
            - countCapsuleWidth(summary.activeCount, metrics)
            - optionsBarWidth(completedCount: summary.completedCount)
    }

    private static func rungWidth(_ rung: CadencePageHeaderEyebrowCandidate, _ metrics: CadencePageHeaderMetrics) -> CGFloat {
        let eyebrow = rung.eyebrow.map { eyebrowWidth($0, metrics) } ?? 0
        guard let detail = rung.detail else { return eyebrow }
        if rung.stacks {
            // The stacked rung is the one `ViewThatFits` renders whether it fits or not, so its
            // detail wraps rather than clipping: what it needs is the widest unbreakable run.
            return max(eyebrow, longestDetailRun(detail, metrics))
        }
        return eyebrow + CadencePageHeaderEyebrow.spacing + detailWidth(detail, metrics)
    }

    // MARK: - The content the relation is asserted over

    /// The longest spelling of a weekday-plus-date in a year, in both forms. The eyebrow is today's
    /// date and nobody chooses it, so the guard takes the worst day rather than a convenient one.
    private static func worstDates() -> (long: String, compact: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let metrics = CadencePageHeaderMetrics.metrics(role: .pane, isRegularWidth: true)
        var start = DateComponents()
        start.year = 2_026
        start.month = 1
        start.day = 1
        guard let first = calendar.date(from: start) else { return ("Wednesday, September 30", "Wed, Sep 30") }
        var long = ("", CGFloat(0))
        var compact = ("", CGFloat(0))
        for offset in 0..<365 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: first) else { continue }
            let l = DateFormatters.longDate.string(from: day)
            let c = DateFormatters.compactLongDate.string(from: day)
            if eyebrowWidth(l, metrics) > long.1 { long = (l, eyebrowWidth(l, metrics)) }
            if eyebrowWidth(c, metrics) > compact.1 { compact = (c, eyebrowWidth(c, metrics)) }
        }
        return (long.0, compact.0)
    }

    /// Days the header has to be able to state. The first is the one the owner photographed; the
    /// rest carry the two-digit counts that make the line longest and the capsule and chip beside
    /// it wider at the same time.
    private static let summaries: [CadenceTodaySummary] = [
        CadenceTodaySummary(activeCount: 3, timedCount: 3, completedCount: 1),
        CadenceTodaySummary(activeCount: 12, timedCount: 12, completedCount: 34),
        CadenceTodaySummary(activeCount: 24, timedCount: 24, completedCount: 18),
        CadenceTodaySummary(activeCount: 7, timedCount: 0, completedCount: 0),
        CadenceTodaySummary(activeCount: 0, timedCount: 0, completedCount: 0),
    ]

    // MARK: - The guard

    /// **The relation.** At every pane width the two-pane layout renders at, some rung of the
    /// header's ladder fits the width the row actually leaves the eyebrow — so the day and its
    /// summary are both stated, in one spelling or another, rather than clipped.
    ///
    /// Red before the `ViewThatFits` landed: with only the full single-line spelling to offer, the
    /// ladder's every rung was 250-odd points against a budget of about 160 at 834.
    @Test
    func everyTwoPaneWidthCanStateTheDayAndItsSummaryInFull() {
        let metrics = CadencePageHeaderMetrics.metrics(role: .pane, isRegularWidth: true)
        let dates = Self.worstDates()
        for summary in Self.summaries {
            let ladder = CadencePageHeaderEyebrow.ladder(
                eyebrow: dates.long,
                compactEyebrow: dates.compact,
                detail: summary.line
            )
            for pane in iPadTodayPaneWidthTests.panes {
                let budget = Self.eyebrowBudget(paneWidth: pane, summary: summary)
                let best = ladder.rungs.map { Self.rungWidth($0, metrics) }.min() ?? .infinity
                #expect(
                    best <= budget,
                    """
                    pane \(pane): the narrowest spelling of "\(dates.long) · \(summary.line ?? "")" \
                    needs \(best) and the row leaves \(budget)
                    """
                )
            }
        }
    }

    /// **Non-vacuity, and the defect itself.** The relation above is worth nothing if the full
    /// single-line spelling already fitted everywhere — it would then pass over a ladder that never
    /// narrows. It does not fit in the band the owner photographed, and it does fit once the pane
    /// is wide enough, which is the other half: the header must not abbreviate a date it has room
    /// to spell.
    @Test
    func theFullSpellingOverflowsTheFoldedPortraitBandAndNotTheWideOne() {
        let metrics = CadencePageHeaderMetrics.metrics(role: .pane, isRegularWidth: true)
        let dates = Self.worstDates()
        let reported = CadenceTodaySummary(activeCount: 3, timedCount: 3, completedCount: 1)
        let ladder = CadencePageHeaderEyebrow.ladder(
            eyebrow: dates.long,
            compactEyebrow: dates.compact,
            detail: reported.line
        )
        let widest = Self.rungWidth(ladder.widest, metrics)
        let middle = Self.rungWidth(ladder.middle, metrics)

        // 834pt of pane, sidebar folded — the device and orientation in the report.
        let narrowBand = Self.eyebrowBudget(paneWidth: 834, summary: reported)
        #expect(widest > narrowBand, "the full line fits at 834 and there is nothing to fix")
        #expect(middle <= narrowBand, "the middle rung does not answer the width it was written for")

        // 1210pt — the same device in landscape with the sidebar folded, the widest pane there is.
        let wideBand = Self.eyebrowBudget(paneWidth: 1_210, summary: reported)
        #expect(widest <= wideBand, "the header would abbreviate a date it has room to spell")
    }

    /// The ladder narrows monotonically. A middle rung wider than the one above it would make
    /// `ViewThatFits` skip it, which is the shape [[T-1492]] found in `CadenceQuickDatePopover`.
    @Test
    func eachRungAsksForNoMoreThanTheOneAboveIt() {
        let metrics = CadencePageHeaderMetrics.metrics(role: .pane, isRegularWidth: true)
        let dates = Self.worstDates()
        for summary in Self.summaries {
            let ladder = CadencePageHeaderEyebrow.ladder(
                eyebrow: dates.long,
                compactEyebrow: dates.compact,
                detail: summary.line
            )
            let widths = ladder.rungs.map { Self.rungWidth($0, metrics) }
            #expect(widths[1] <= widths[0], "the middle rung is wider than the full spelling")
            #expect(widths[2] <= widths[1], "the stacked rung is wider than the middle one")
        }
    }

    /// **No rung drops the day's counts.** The summary appears nowhere else on the page, so the
    /// ladder may respell it and may move it onto its own line; it may not give it up. This is the
    /// assertion that stops a later "fix" from simply deleting the clause at narrow widths.
    @Test
    func noRungOfTheLadderGivesUpTheSummary() {
        let ladder = CadencePageHeaderEyebrow.ladder(
            eyebrow: "Tuesday, September 29",
            compactEyebrow: "Tue, Sep 29",
            detail: "3 timed · 1 done"
        )
        #expect(ladder.rungs.count == 3)
        for rung in ladder.rungs {
            #expect(rung.detail == "3 timed · 1 done")
            #expect(rung.eyebrow != nil)
        }
        #expect(ladder.widest.eyebrow == "Tuesday, September 29")
        #expect(ladder.middle.eyebrow == "Tue, Sep 29")
        #expect(ladder.narrowest.eyebrow == "Tue, Sep 29")
        #expect(ladder.widest.stacks == false)
        #expect(ladder.middle.stacks == false)
        #expect(ladder.narrowest.stacks, "the fallback rung clips instead of wrapping")
    }

    /// A header with no second spelling — "SETTINGS" does not abbreviate — still gets three rungs,
    /// because a `ViewThatFits` builder with a conditional candidate produces an **empty** one, and
    /// an empty candidate fits every width and draws nothing.
    @Test
    func aHeaderWithoutAnAbbreviationStillGetsThreeRungs() {
        let ladder = CadencePageHeaderEyebrow.ladder(eyebrow: "Settings", compactEyebrow: nil, detail: nil)
        #expect(ladder.rungs.count == 3)
        for rung in ladder.rungs {
            #expect(rung.eyebrow == "Settings")
            #expect(rung.detail == nil)
        }
        // Whitespace is absence said twice, on both halves.
        let blank = CadencePageHeaderEyebrow.ladder(eyebrow: "Settings", compactEyebrow: "   ", detail: "  ")
        #expect(blank.middle.eyebrow == "Settings")
        #expect(blank.widest.detail == nil)
    }

    /// The abbreviated spelling is `longDate`'s, and the two must name the same day.
    @Test
    func theCompactFormatterIsTheLongOneAbbreviated() {
        var components = DateComponents()
        components.year = 2_026
        components.month = 9
        components.day = 29
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let day = calendar.date(from: components)
        #expect(day != nil)
        guard let day else { return }
        #expect(DateFormatters.longDate.string(from: day) == "Tuesday, September 29")
        #expect(DateFormatters.compactLongDate.string(from: day) == "Tue, Sep 29")
        #expect(DateFormatters.compactLongDate.locale.identifier == "en_US_POSIX")
    }

    // MARK: - Non-vacuity of the restated figures

    /// The three `iOSTaskViewOptionsBar` figures the budget restates, checked against the file that
    /// declares them. This target builds for macOS and the bar is behind `#if os(iOS)`, so a scan
    /// is the only reach there is — and without it the budget above would be three numbers nobody
    /// would notice going stale.
    @Test
    func theRestatedOptionsBarFiguresStillMatchTheSource() throws {
        let source = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTaskViews.swift")
        #expect(source.contains("struct iOSTaskViewOptionsBar: View {"), "non-vacuity: wrong file read")
        #expect(
            source.contains("private static let fontSize: CGFloat = \(Int(Self.optionsChipFontSize))"),
            "iOSTaskViewOptionsBar.fontSize moved off \(Self.optionsChipFontSize)"
        )
        #expect(
            source.contains("private static let horizontalPadding: CGFloat = \(Int(Self.optionsChipHorizontalPadding))"),
            "iOSTaskViewOptionsBar.horizontalPadding moved off \(Self.optionsChipHorizontalPadding)"
        )
        #expect(
            source.contains("AnyLayout(HStackLayout(spacing: \(Int(Self.optionsChipSpacing))))"),
            "the options bar's chip spacing moved off \(Self.optionsChipSpacing)"
        )
        // And the half of the budget that is a layout fact rather than a figure: the trailing
        // control takes its intrinsic width before the eyebrow is measured at all.
        let header = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSFeatureComponents.swift")
        #expect(header.contains(".layoutPriority(1)"))
        #expect(header.contains("Spacer(minLength: 8)"))
        #expect(header.contains("ViewThatFits(in: .horizontal)"), "the eyebrow ladder is gone (T-1702)")
    }

    /// The measuring itself has to produce numbers, or every relation above is `0 <= something`.
    @Test
    func theTextMeasurementActuallyMeasures() {
        let metrics = CadencePageHeaderMetrics.metrics(role: .pane, isRegularWidth: true)
        let long = Self.eyebrowWidth("Tuesday, September 29", metrics)
        let short = Self.eyebrowWidth("Tue, Sep 29", metrics)
        #expect(long > short)
        #expect(short > 0)
        #expect(Self.detailWidth("3 timed · 1 done", metrics) > 0)
        #expect(Self.optionsBarWidth(completedCount: 1) > Self.optionsBarWidth(completedCount: 0))
        #expect(Self.eyebrowBudget(paneWidth: 1_210, summary: Self.summaries[0])
            > Self.eyebrowBudget(paneWidth: 834, summary: Self.summaries[0]))
    }
}
