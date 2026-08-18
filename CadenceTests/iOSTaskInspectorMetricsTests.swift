import Foundation
import Testing
@testable import Cadence

/// The iOS task inspector styled itself by the width of the screen behind it: a 24/21pt title, a
/// 26/24pt completion circle, an indent that restated the circle's size a third time, a 5/3pt nudge
/// on the circle and a 360/340 notes well. It is a *sheet* — its content column is capped at 640pt
/// at every width — so none of those five was a width difference; each was a number written twice.
///
/// `Cadence/iOS/` is inside `#if os(iOS)` and invisible to this macOS-built target, so what these
/// pin is the thing worth pinning anyway: the figures themselves, and the single ramp that
/// survived. `iOSTaskInspectorMetrics` lives outside the platform guard for exactly that reason.
struct iOSTaskInspectorMetricsTests {

    // MARK: - The one thing that varies

    /// The gutter is a fact about the host, not about the card: it is what is left between the
    /// sheet's edge and a column that has already stopped growing. It stays a ramp, and it stays
    /// the pair `iOSCalendarEventEditSheet` uses, so the app's sheets share one margin.
    @Test func theSheetGutterIsTheOnlyFigureThatTakesAWidth() {
        let regular = iOSTaskInspectorMetrics.sheetGutter(isRegularWidth: true)
        let compact = iOSTaskInspectorMetrics.sheetGutter(isRegularWidth: false)

        #expect(regular == 20)
        #expect(compact == 18)
        #expect(regular > compact)
    }

    /// A gutter that ate into a 640pt column would stop being a margin and start being layout.
    @Test func theGutterNeverCrowdsTheContentColumn() {
        for isRegular in [true, false] {
            let gutter = iOSTaskInspectorMetrics.sheetGutter(isRegularWidth: isRegular)

            #expect(gutter > 0, "regular=\(isRegular)")
            #expect(gutter * 2 < iOSTaskInspectorMetrics.contentMaxWidth, "regular=\(isRegular)")
        }
    }

    // MARK: - What must not vary

    /// 22, because `iOSCalendarEventEditSheet` and `iOSCalendarQuickCreateSheet` already set 22pt
    /// bold for the same text — the name of the thing the sheet edits. The inspector's ramp went
    /// *above* both of them on one device and *below* both on the other.
    @Test func theTitleIsTheSizeTheAppsOtherEditorSheetsUse() {
        #expect(iOSTaskInspectorMetrics.titleSize == 22)
    }

    /// A long name is long on both devices, and past the gutter the card is the same width on both.
    @Test func aTitleWrapsToTheSameNumberOfLinesEverywhere() {
        #expect(iOSTaskInspectorMetrics.titleLineLimit == 3)
    }

    /// The sheet's circle sits at the **top of the existing scale** rather than above it: 24 is
    /// `CadenceTaskRowMetrics.regularWidth.completionGlyphSize`, the largest completion glyph the
    /// app already draws. The 26 the inspector used on iPad was an invented step.
    @Test func theCompletionCircleIsTheLargestGlyphTheAppAlreadyDraws() {
        #expect(iOSTaskInspectorMetrics.completionGlyphSize == CadenceTaskRowMetrics.regularWidth.completionGlyphSize)
        #expect(iOSTaskInspectorMetrics.completionGlyphSize >= CadenceTaskRowMetrics.compactWidth.completionGlyphSize)
    }

    /// One resting height for the notes well — and, since T-111, not the inspector's own. The same
    /// markdown surface is a well on four sheets; the height is `iOSEditorSheetMetrics`'s to state,
    /// and `iOSEditorSheetMetricsTests` is where the choice of 340 is argued.
    @Test func theNotesWellIsTheSameWellEveryOtherSheetDraws() {
        #expect(iOSTaskInspectorMetrics.notesMinHeight == iOSEditorSheetMetrics.notesMinHeight)
    }

    // MARK: - What is derived, and must stay derived

    /// The indent under the title *is* the circle plus the gap. Stating it separately is how
    /// `(isRegularWidth ? 26 : 24) + 12` came to restate, in another file, a ramp the circle owned.
    @Test func theTitleIndentFollowsTheCircleItClears() {
        #expect(
            iOSTaskInspectorMetrics.titleColumnInset
                == iOSTaskInspectorMetrics.completionGlyphSize + iOSTaskInspectorMetrics.titleRowSpacing
        )
        #expect(iOSTaskInspectorMetrics.titleColumnInset > iOSTaskInspectorMetrics.completionGlyphSize)
    }

    /// The row is `.top`-aligned, so the circle is nudged down onto the first line of a title that
    /// may wrap to three. That nudge is whatever centres it — not a third hand-set number.
    @Test func theCircleIsCentredOnTheFirstLineOfTheTitle() {
        let occupied = iOSTaskInspectorMetrics.completionGlyphSize
            + iOSTaskInspectorMetrics.completionTopPadding * 2

        #expect(iOSTaskInspectorMetrics.completionTopPadding >= 0)
        #expect(iOSTaskInspectorMetrics.completionGlyphSize <= iOSTaskInspectorMetrics.titleLineHeight)
        #expect(abs(occupied - iOSTaskInspectorMetrics.titleLineHeight) < 0.001)
    }

    @Test func theLineHeightFollowsTheTitleSize() {
        #expect(iOSTaskInspectorMetrics.titleLineHeight == iOSTaskInspectorMetrics.titleSize * 1.2)
        #expect(iOSTaskInspectorMetrics.titleLineHeight > iOSTaskInspectorMetrics.titleSize)
    }

    // MARK: - Sanity

    /// A zero anywhere in here draws as a collapsed sheet rather than as an error — the failure
    /// mode a set of ternaries invites.
    @Test func everyMeasurementIsPositive() {
        #expect(iOSTaskInspectorMetrics.cardPadding > 0)
        #expect(iOSTaskInspectorMetrics.contentMaxWidth > 0)
        #expect(iOSTaskInspectorMetrics.sectionSpacing > 0)
        #expect(iOSTaskInspectorMetrics.titleSize > 0)
        #expect(iOSTaskInspectorMetrics.titleLineLimit > 0)
        #expect(iOSTaskInspectorMetrics.completionGlyphSize > 0)
        #expect(iOSTaskInspectorMetrics.titleRowSpacing > 0)
        #expect(iOSTaskInspectorMetrics.notesMinHeight > 0)
    }

    /// The title is the loudest text in the sheet: it outranks the 13pt secondary type the rows
    /// that open it are built from, at either width.
    @Test func theInspectorTitleOutranksTheRowThatOpensIt() {
        #expect(iOSTaskInspectorMetrics.titleSize > CadenceTaskRowMetrics.regularWidth.secondaryFontSize)
        #expect(iOSTaskInspectorMetrics.titleSize > CadenceTaskRowMetrics.compactWidth.secondaryFontSize)
    }
}
