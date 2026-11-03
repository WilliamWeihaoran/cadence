import Foundation
import Testing
@testable import Cadence

/// **[[T-10221]]: iOS Settings drew the Calendar modes with other glyphs than the Calendar page.**
///
/// The Calendar toolbar's pills draw Week as `rectangle.split.3x1`, Month as `calendar` and Board
/// as `rectangle.grid.2x2`. Settings > Navigation's "Calendar view" choices drew `calendar` on
/// Week and Month alike, and its "Calendar style" Board choice drew `square.grid.2x2`. One glyph
/// per mode now lives on the shared enums and both iOS surfaces read it.
struct CadenceIOSCalendarModeGlyphTests {
    private static let toolbarPath = "Cadence/iOS/iOSCalendarChromeViews.swift"
    private static let settingsPath = "Cadence/iOS/iOSSettingsOverviewSections.swift"

    private static func compactBody(_ declaration: String, in path: String) throws -> String {
        let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
        let body = try #require(CadenceSourceScan.declarationBody(declaration, in: source))
        return body.filter { !$0.isWhitespace }
    }

    @Test func eachPickerModeHasItsOwnGlyph() {
        let glyphs = CadenceCalendarViewMode.pickerCases.map(\.systemImage)
        #expect(Set(glyphs).count == CadenceCalendarViewMode.pickerCases.count,
                "Week and Month must not share a glyph: \(glyphs)")
        #expect(!glyphs.contains(CadenceCalendarPresentation.boardSystemImage))
    }

    @Test func theToolbarPillsReadTheSharedGlyphs() throws {
        let control = try Self.compactBody("private var modeControl: some View", in: Self.toolbarPath)
        #expect(control.contains("systemImage:mode.systemImage,"))
        #expect(control.contains("systemImage:CadenceCalendarPresentation.boardSystemImage,"))
        #expect(!control.contains("systemImage:\""), "no literal glyph left in the mode control")
    }

    /// [[T-7074]] folded "Calendar style" into "Calendar view", so the three choices are one
    /// `CadenceCalendarPageView` list and the glyphs come from that type, which reads the same two
    /// constants the toolbar pills do.
    @Test func settingsCalendarChoicesReadTheSameGlyphs() throws {
        let view = try Self.compactBody("private var calendarViewRow: some View", in: Self.settingsPath)
        #expect(view.contains("systemImage:choice.systemImage,"),
                "each Calendar view choice wears its choice's glyph")
        #expect(!view.contains("square.grid.2x2"), "no second Board glyph among the choices")
        #expect(CadenceCalendarPageView.week.systemImage == CadenceCalendarViewMode.week.systemImage)
        #expect(CadenceCalendarPageView.month.systemImage == CadenceCalendarViewMode.month.systemImage)
        #expect(CadenceCalendarPageView.board.systemImage == CadenceCalendarPresentation.boardSystemImage,
                "the Board choice wears the toolbar Board pill's glyph")
    }
}
