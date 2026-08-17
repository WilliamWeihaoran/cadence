import Foundation
import Testing
@testable import Cadence

/// The create-task sheet's height, held against the software keyboard.
///
/// This suite exists because a *comment* claiming the sheet fit was what shipped last time, and it
/// was wrong: the Tags row sat about 70pt under the fold on a 390pt phone. `CadenceTaskComposerLayout`
/// composes its answer from the same constants the sheet lays itself out with and from
/// `CadenceValueTileMetrics`, so if someone grows a tile or adds a field, the number moves and these
/// tests are what notice.
///
/// The device figures are **measured**, on iPhone 17e with the software keyboard actually raised:
/// its top edge at 508pt down a 844pt screen, and the sheet's scroll viewport starting ~118pt down.
/// They correct the 452pt this redesign was specified against, which subtracted a navigation bar
/// from the 508 but not the ~50pt a sheet is inset from the top of the screen.
@MainActor
struct CadenceTaskComposerLayoutTests {
    @Test("Every field clears the keyboard fold, section tile or not")
    func contentFitsAboveTheFold() {
        for showsSection in [false, true] {
            let height = CadenceTaskComposerLayout.contentHeight(showsSectionTile: showsSection)
            #expect(height <= CadenceTaskComposerLayout.keyboardVisibleContentHeight)
            #expect(CadenceTaskComposerLayout.slackBelowFold(showsSectionTile: showsSection) >= 0)
        }
    }

    /// The shape was chosen for a margin, not a squeak: anything that eats most of the headroom has
    /// undone the redesign even if it still technically fits. 40pt is most of a tile.
    @Test("The sheet keeps a real margin, not a hairline")
    func sheetKeepsHeadroom() {
        #expect(CadenceTaskComposerLayout.slackBelowFold() >= 40)
    }

    /// The point of putting the conditional field in the last row's spare half rather than on a row
    /// of its own: picking a list with sections must not push anything toward the keyboard.
    @Test("The section tile costs no height at all")
    func sectionTileCostsNoHeight() {
        #expect(CadenceTaskComposerLayout.contentHeight(showsSectionTile: true)
            == CadenceTaskComposerLayout.contentHeight(showsSectionTile: false))
        #expect(CadenceTaskComposerLayout.tileCount(showsSectionTile: true)
            - CadenceTaskComposerLayout.tileCount(showsSectionTile: false) == 1)
        // Six tiles across three rows of two is what makes that free.
        #expect(CadenceTaskComposerLayout.tileCount(showsSectionTile: true)
            == CadenceTaskComposerLayout.gridRowCount * 2)
    }

    /// The whole argument for tiles over rows, against the height the shape they replaced actually
    /// measured at. It did not fit; this has to, with room to spare.
    @Test("The grid is decisively shorter than the rows it replaced")
    func gridBeatsTheRowsItReplaced() {
        let rowsHeight = CadenceTaskComposerLayout.supersededRowLayoutHeight
        #expect(rowsHeight > CadenceTaskComposerLayout.keyboardVisibleContentHeight)
        #expect(CadenceTaskComposerLayout.contentHeight() < rowsHeight - 100)
    }

    /// The tile's own geometry is the sheet's input, so the two must not be able to drift.
    @Test("The sheet counts the tile the tile actually draws")
    func tileHeightComesFromTheTile() {
        #expect(CadenceTaskComposerLayout.tileHeight == CadenceValueTileMetrics.minHeight)
        // Caption line + gap + value line + padding both sides has to fit inside the tile, or the
        // frame's `minHeight` stops being what the tile measures.
        let intrinsic = 2 * CadenceValueTileMetrics.verticalPadding
            + 12
            + CadenceValueTileMetrics.captionValueSpacing
            + CadenceValueTileMetrics.valueFontSize + 3
        #expect(intrinsic <= CadenceValueTileMetrics.minHeight)
    }

    @Test("The stated device figures are the ones the fold is measured against")
    func deviceAssumptionsAreExplicit() {
        #expect(CadenceTaskComposerLayout.keyboardVisibleContentHeight
            == CadenceTaskComposerLayout.keyboardTopFromScreenTop
            - CadenceTaskComposerLayout.scrollViewportTop)
        // 844pt of screen less the 508pt the keyboard's top edge was measured at is a 336pt
        // keyboard, which is what an iPhone this size has.
        #expect(844 - CadenceTaskComposerLayout.keyboardTopFromScreenTop == 336)
    }
}

/// What each tile says, given what the draft currently holds.
///
/// A tile that only *displays* is the failure mode this sheet has already been caught in once, so
/// the labels are pinned here and the write-back is pinned by the view holding a `Binding` into
/// `CadenceTaskComposerFields` — there is no second copy of the value for a tile to render instead.
@MainActor
struct CadenceTaskComposerTileValueTests {
    @Test("A date tile names today and tomorrow and dates everything else")
    func dateValueLabels() {
        let today = DateFormatters.todayKey()
        let tomorrow = CadenceTaskComposerSupport.dateKey(for: .tomorrow)
        let farOff = "2031-03-04"

        #expect(CadenceTaskComposerSupport.dateValueLabel("") == "None")
        #expect(CadenceTaskComposerSupport.dateValueLabel(today) == "Today")
        #expect(CadenceTaskComposerSupport.dateValueLabel(tomorrow) == "Tomorrow")
        #expect(CadenceTaskComposerSupport.dateValueLabel(farOff) == DateFormatters.shortDateString(from: farOff))
    }

    /// Yesterday is a real answer for a due date and must not be swallowed by the "Today" branch.
    @Test("A past date is stated, not rounded to today")
    func pastDateIsStated() {
        let yesterday = CadenceTaskComposerSupport.dateKey(for: .today, from: Date().addingTimeInterval(-86_400))
        #expect(CadenceTaskComposerSupport.dateValueLabel(yesterday) == DateFormatters.shortDateString(from: yesterday))
    }

    /// The full-width tags tile spells two names; the half-width default spells one.
    @Test("The tags tile spells names up to its limit, then counts")
    func tagsValueLabelHonoursItsLimit() {
        #expect(CadenceTaskComposerSupport.tagsValueLabel(names: [], limit: 2) == "None")
        #expect(CadenceTaskComposerSupport.tagsValueLabel(names: ["urgent"], limit: 2) == "urgent")
        #expect(CadenceTaskComposerSupport.tagsValueLabel(names: ["urgent", "home"], limit: 2) == "urgent, home")
        #expect(CadenceTaskComposerSupport.tagsValueLabel(names: ["urgent", "home", "errand"], limit: 2) == "3 tags")
        // The default is unchanged, so the row-era call sites still read the same.
        #expect(CadenceTaskComposerSupport.tagsValueLabel(names: ["urgent", "home"]) == "2 tags")
        // A limit below one cannot make the label meaningless.
        #expect(CadenceTaskComposerSupport.tagsValueLabel(names: ["urgent"], limit: 0) == "urgent")
    }

    /// The section tile is full width *below* the grid precisely so that its appearing cannot move
    /// anything else; this pins the rule it appears by.
    @Test("The section tile appears only when there is something to choose")
    func sectionTileVisibility() {
        #expect(CadenceTaskComposerSupport.showsSectionRow(
            container: .inbox,
            availableSections: ["Default", "Doing"]
        ) == false)

        #expect(CadenceTaskComposerSupport.showsSectionRow(
            container: .area(UUID()),
            availableSections: [TaskSectionDefaults.defaultName]
        ) == false)

        #expect(CadenceTaskComposerSupport.showsSectionRow(
            container: .area(UUID()),
            availableSections: [TaskSectionDefaults.defaultName, "Doing"]
        ))
    }
}
