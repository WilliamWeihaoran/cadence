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

    @Test func settingsCalendarChoicesReadTheSameGlyphs() throws {
        let view = try Self.compactBody("private var calendarViewRow: some View", in: Self.settingsPath)
        #expect(view.contains("title:mode.rawValue,systemImage:mode.systemImage,"),
                "each Calendar view choice wears its mode's toolbar glyph")
        let style = try Self.compactBody("private var calendarStyleRow: some View", in: Self.settingsPath)
        #expect(style.contains("systemImage:CadenceCalendarPresentation.boardSystemImage,"),
                "the Board choice wears the toolbar Board pill's glyph")
        #expect(!style.contains("square.grid.2x2\",color:"), "no second Board glyph among the choices")
    }
}
