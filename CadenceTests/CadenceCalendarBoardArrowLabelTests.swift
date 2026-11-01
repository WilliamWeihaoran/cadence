import Foundation
import Testing
@testable import Cadence

/// **[[T-9672]].** The Calendar toolbar's ghost buttons take their name and tooltip from the
/// caller, and nothing stacks a second `.accessibilityLabel` / `.help` over one.
///
/// `CalendarIconGhostButton` guessed its name from the glyph ("Previous" / "Next" for either
/// chevron) and `CadenceIconButton` applies it as both label and tooltip; the Board's arrows then
/// stacked "Previous 7 days", "Board starts at today" and "Next 7 days" on top. Which of two nested
/// modifiers SwiftUI honours is not this app's to decide, so the arrows' words are now passed in.
@Suite struct CadenceCalendarBoardArrowLabelTests {
    private static func code(_ path: String) throws -> String {
        CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
    }

    @Test func theBoardArrowsPassTheirWordsIn() throws {
        let source = try Self.code("Cadence/macOS/Views/CalendarPageSupportViews.swift")
        let control = try #require(CadenceSourceScan.declarationBody(
            "private struct CalendarBoardWindowNavigationControl: View", in: source
        ))
        #expect(control.contains("accessibilityLabel: \"Previous 7 days\""))
        #expect(control.contains("accessibilityLabel: \"Next 7 days\""))
        #expect(control.contains("help: canMoveBack ? nil : \"Board starts at today\""))
        #expect(!control.contains(".accessibilityLabel("), "a label stacked over the button's own")
        #expect(!control.contains(".help("), "a tooltip stacked over the button's own")
        #expect(!control.contains(".cadenceControlLabel("), "a label and tooltip stacked over the button's own")

        let button = try #require(CadenceSourceScan.declarationBody(
            "private struct CalendarIconGhostButton: View", in: source
        ))
        #expect(!button.contains("case \"chevron.left\""), "the button guesses its name from the glyph again")
        #expect(button.contains("help: help"))
    }

    @Test func theIconButtonsTooltipFallsBackToItsName() throws {
        let source = try Self.code("Cadence/macOS/Views/CadenceButtons.swift")
        let button = try #require(CadenceSourceScan.declarationBody("struct CadenceIconButton: View", in: source))
        #expect(button.contains(".help(help ?? accessibilityLabel)"))
        #expect(button.components(separatedBy: ".help(").count - 1 == 1, "one tooltip on the icon button")
    }
}
