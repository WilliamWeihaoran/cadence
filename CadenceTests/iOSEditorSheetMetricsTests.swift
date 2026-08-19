import Foundation
import Testing
@testable import Cadence

/// Four surfaces host the same markdown editing surface as a *well* — the task inspector, the
/// Settings template editor, `iOSCalendarEventEditSheet` and `iOSCalendarQuickCreateSheet` — and
/// they gave it four resting heights, two of them ramped by the width of the screen behind the
/// sheet: 340, 340, `300 : 240` and `280 : 230`.
///
/// `Cadence/iOS/` is inside `#if os(iOS)` and invisible to this macOS-built target, so what these
/// pin is the thing worth pinning: the decisions themselves. `iOSEditorSheetMetrics` lives outside
/// the platform guard for exactly that reason, as `iOSTaskInspectorMetrics` and
/// `CadencePageHeaderMetrics` already do.
struct iOSEditorSheetMetricsTests {

    // MARK: - The markdown well

    /// One resting height, at every width and on every sheet. 340 is the height the two surfaces
    /// that never ramped already agreed on, and the tallest of the four — not a split of them.
    /// A well inside a scroll view grows with its content, so the minimum's only job is to be a
    /// canvas worth tapping into, and the largest existing spelling is the one that does that.
    @Test func aMarkdownWellHasOneRestingHeight() {
        #expect(iOSEditorSheetMetrics.notesMinHeight == 340)
    }

    /// A canvas, not a field: the well has to hold enough lines that writing into it does not feel
    /// like typing into a caption. Measured against the sheet's own title line, which is the tallest
    /// line of text on it — anything under a handful of those is a text field with a big border.
    @Test func theWellIsACanvasRatherThanAField() {
        #expect(iOSEditorSheetMetrics.notesMinHeight > iOSTaskInspectorMetrics.titleLineHeight * 6)
    }

    /// The inspector reads the same number rather than keeping its own copy of it — which is what
    /// let two of these four drift in the first place.
    @Test func theInspectorsWellIsTheSameWell() {
        #expect(iOSTaskInspectorMetrics.notesMinHeight == iOSEditorSheetMetrics.notesMinHeight)
    }

    // MARK: - The one thing that varies

    /// The gutter is a fact about the *host*: what is left between the sheet's edge and a content
    /// column that has already stopped growing. It stays a ramp, and it is now the same ramp for
    /// the inspector and both calendar sheets instead of three copies of one ternary.
    @Test func theGutterIsTheOnlyFigureThatTakesAWidth() {
        let regular = iOSEditorSheetMetrics.gutter(isRegularWidth: true)
        let compact = iOSEditorSheetMetrics.gutter(isRegularWidth: false)

        #expect(regular == 20)
        #expect(compact == 18)
        #expect(regular > compact)
    }

    @Test func everySheetSharesTheOneGutter() {
        for isRegular in [true, false] {
            #expect(
                iOSTaskInspectorMetrics.sheetGutter(isRegularWidth: isRegular)
                    == iOSEditorSheetMetrics.gutter(isRegularWidth: isRegular),
                "regular=\(isRegular)"
            )
        }
    }

    // MARK: - The gap between two groups, and the frame around them

    /// The split T-112 closed. Three surfaces said 16 — `iOSCalendarEventEditSheet`,
    /// `iOSCalendarQuickCreateSheet` and `iOSTrackingEditorShell` — and two said 14: the task
    /// inspector and the Settings template editor.
    ///
    /// 16 is not a vote. It is that the two structural families here do not line up with the split:
    /// quick-create is the inspector's twin (ruled sections inside one sheet card, six groups each)
    /// and says 16, and the two free-standing-card sheets say 16 as well. Whichever way the five are
    /// grouped, 14 is the odd one out.
    @Test func twoGroupsOfFieldsAreOneDistanceApart() {
        #expect(iOSEditorSheetMetrics.groupSpacing == 16)
        #expect(iOSTaskInspectorMetrics.sectionSpacing == iOSEditorSheetMetrics.groupSpacing)
    }

    /// **The rule, not just the number: a sheet does not buy density with this figure.**
    ///
    /// The inspector's 14 read like a density allowance — it carries more groups than the template
    /// editor and was the densest-looking of the five — and it was not one. What a sheet writes here
    /// is not the gap the eye sees: `iOSEditorSection(style: .ruled)` adds 12pt of its own above
    /// every group's hairline, so the inspector's visible gap was 26 against quick-create's 28,
    /// while the two card-section sheets sat at a flat 16. The families that *do* differ differ by
    /// 12, which is the shared section's doing; the sheets' own figures differed by 2, which is
    /// nobody's.
    ///
    /// So density is `iOSEditorSection`'s decision — it is the thing that knows whether a group is
    /// separated by a hairline or by a card edge — and a sheet only says how far apart two groups
    /// are. The sheet with the strongest claim to an exception takes none: one figure for its group
    /// gap and for the card framing them, and it is every other sheet's figure.
    @Test func noSheetKeepsADensityAllowanceOfItsOwn() {
        #expect(iOSTaskInspectorMetrics.sectionSpacing == iOSEditorSheetMetrics.groupSpacing)
        #expect(iOSTaskInspectorMetrics.cardPadding == iOSEditorSheetMetrics.groupSpacing)
    }

    /// The card is the frame around the form, so it leaves the same gap on the outside that the form
    /// leaves between its own groups. Both sheets that draw such a card had already set these two
    /// equal, independently — the inspector at 14/14 and quick-create at 16/16 — which is what makes
    /// it one figure rather than two that happen to match.
    @Test func theCardsFrameIsOneMoreGapOfTheSameSize() {
        #expect(iOSEditorSheetMetrics.cardPadding == iOSEditorSheetMetrics.groupSpacing)
        #expect(iOSTaskInspectorMetrics.cardPadding == iOSEditorSheetMetrics.cardPadding)
    }

    /// The gutter is outside the card and the padding is inside it, so a gutter that dropped below
    /// the padding would make the sheet look glued to the edge of a screen it is floating above.
    @Test func theCardSitsFurtherFromTheScreenThanItsFormSitsFromTheCard() {
        for isRegular in [true, false] {
            #expect(
                iOSEditorSheetMetrics.gutter(isRegularWidth: isRegular) >= iOSEditorSheetMetrics.cardPadding,
                "regular=\(isRegular)"
            )
        }
    }

    // MARK: - The name of the thing being edited

    /// A task title, an event title and a quick-create title are the same thing — the one field the
    /// sheet exists to fill in — and all three sheets already drew it at 22pt bold. They drew it
    /// from three separate literals, so the agreement was a coincidence any one of them could end.
    @Test func everyEditorSheetNamesItsSubjectAtOneSize() {
        #expect(iOSEditorSheetMetrics.titleSize == 22)
        #expect(iOSTaskInspectorMetrics.titleSize == iOSEditorSheetMetrics.titleSize)
    }

    @Test func aTitleWrapsToTheSameNumberOfLinesEverywhere() {
        #expect(iOSEditorSheetMetrics.titleLineLimit == 3)
        #expect(iOSTaskInspectorMetrics.titleLineLimit == iOSEditorSheetMetrics.titleLineLimit)
    }

    /// The title is the loudest text on the sheet — it outranks the secondary type of the rows that
    /// open it, at either width.
    @Test func theSheetTitleOutranksTheRowThatOpensIt() {
        #expect(iOSEditorSheetMetrics.titleSize > CadenceTaskRowMetrics.regularWidth.secondaryFontSize)
        #expect(iOSEditorSheetMetrics.titleSize > CadenceTaskRowMetrics.compactWidth.secondaryFontSize)
    }

    // MARK: - Splitting into two columns

    /// Both calendar sheets had written these five widths down independently, byte for byte. The
    /// trailing column is the wider one because it is the one carrying the markdown well.
    @Test func theTwoColumnFormIsStatedOnce() {
        #expect(iOSEditorSheetMetrics.primaryColumnMinWidth == 340)
        #expect(iOSEditorSheetMetrics.primaryColumnMaxWidth == 440)
        #expect(iOSEditorSheetMetrics.secondaryColumnMinWidth == 360)
        #expect(iOSEditorSheetMetrics.secondaryColumnMaxWidth == 520)
        #expect(iOSEditorSheetMetrics.twoColumnMaxWidth == 980)
    }

    /// A column whose minimum exceeded its maximum would resolve to a fixed width and silently stop
    /// being a range — the failure mode a pile of loose literals invites.
    @Test func everyColumnRangeIsARange() {
        #expect(iOSEditorSheetMetrics.primaryColumnMinWidth < iOSEditorSheetMetrics.primaryColumnMaxWidth)
        #expect(iOSEditorSheetMetrics.secondaryColumnMinWidth < iOSEditorSheetMetrics.secondaryColumnMaxWidth)
        #expect(iOSEditorSheetMetrics.secondaryColumnMaxWidth > iOSEditorSheetMetrics.primaryColumnMaxWidth)
    }

    /// Both columns at their widest, plus the gap between them, must fit inside the cap — otherwise
    /// the cap is what sets the column widths and the two ranges above are decoration.
    @Test func bothColumnsFitInsideTheSheetsCap() {
        let widest = iOSEditorSheetMetrics.primaryColumnMaxWidth + iOSEditorSheetMetrics.secondaryColumnMaxWidth
        #expect(widest < iOSEditorSheetMetrics.twoColumnMaxWidth)
    }

    /// A gutter that ate into the content would stop being a margin and start being layout.
    @Test func theGutterNeverCrowdsTheColumns() {
        for isRegular in [true, false] {
            let gutter = iOSEditorSheetMetrics.gutter(isRegularWidth: isRegular)
            let narrowest = iOSEditorSheetMetrics.primaryColumnMinWidth
                + iOSEditorSheetMetrics.secondaryColumnMinWidth

            #expect(gutter > 0, "regular=\(isRegular)")
            #expect(gutter * 2 < narrowest, "regular=\(isRegular)")
        }
    }

    // MARK: - Sanity

    /// A zero anywhere in here draws as a collapsed sheet rather than as an error.
    @Test func everyMeasurementIsPositive() {
        #expect(iOSEditorSheetMetrics.notesMinHeight > 0)
        #expect(iOSEditorSheetMetrics.groupSpacing > 0)
        #expect(iOSEditorSheetMetrics.cardPadding > 0)
        #expect(iOSEditorSheetMetrics.titleSize > 0)
        #expect(iOSEditorSheetMetrics.titleLineLimit > 0)
        #expect(iOSEditorSheetMetrics.primaryColumnMinWidth > 0)
        #expect(iOSEditorSheetMetrics.primaryColumnMaxWidth > 0)
        #expect(iOSEditorSheetMetrics.secondaryColumnMinWidth > 0)
        #expect(iOSEditorSheetMetrics.secondaryColumnMaxWidth > 0)
        #expect(iOSEditorSheetMetrics.twoColumnMaxWidth > 0)
    }
}
