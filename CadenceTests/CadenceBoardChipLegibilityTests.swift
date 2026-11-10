import Foundation
import SwiftUI
import Testing

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@testable import Cadence

/// **[[T-14151]]: the Calendar Board event card's ink is floored to legibility, on both boards.**
///
/// The card's time / `Repeats` / `All day` chips and its leading clock glyph drew the RAW calendar
/// colour, so `#3d0000` put `9:15 AM - 10:15 AM` on its own pill at about 1.1:1 and `#0000ff` at
/// about 2:1 (seen on `Cadence-iPhone15`). The fix keeps the raw colour on the pill wash and floors
/// the ink in the same hue. Every ratio below is recomputed here from `Theme` and the opacity
/// ladders through this file's own composite, rather than read back from the helper under test.
///
/// **One appearance ships.** `Theme.preferredColorScheme` is a hardcoded dark and there is one
/// neutral ramp, so "light mode" exists only as the helper's contract:
/// `lightSurfacesDarkenTheInkInsteadOfLiftingIt` holds `legibleTint` to the same floor over a white
/// and a pale pill, so the rule is right against any surface it is handed.
@Suite("Board chip legibility (T-14151)")
struct CadenceBoardChipLegibilityTests {

    /// The ticket's two hues, black, and the other deep corners a user-chosen calendar reaches.
    private static let darkHues = ["#3d0000", "#0000ff", "#000000", "#1a0033", "#002200", "#4a0040"]
    /// The Mac card's three plate states: rest, hover, selected (popover open).
    private static let states: [(selected: Bool, active: Bool)] = [(false, false), (false, true), (true, false), (true, true)]

    @Test func aDarkCalendarsChipInkClearsTextContrastOnItsOwnPill() {
        for hex in Self.darkHues {
            let calendar = Color(hex: hex)
            for state in Self.states {
                let pill = Self.pill(calendar, selected: state.selected, active: state.active)
                let ink = CadenceCalendarEventStyle.boardChipLabelColor(
                    for: calendar,
                    isSelected: state.selected,
                    isActive: state.active
                )
                let ratio = Self.ratio(Self.luminance(Self.components(ink)), Self.luminance(pill))
                #expect(ratio >= 4.5, "\(hex) \(state): chip ink is \(ratio):1 on its pill")
                // And the raw colour is the defect being fixed: it must NOT have cleared the floor.
                let raw = Self.ratio(Self.luminance(Self.components(calendar)), Self.luminance(pill))
                #expect(raw < 4.5, "\(hex) was never illegible, so this hue proves nothing")
            }
        }
    }

    @Test func aDarkCalendarsLeadingGlyphClearsNonTextContrastOnTheCard() {
        for hex in Self.darkHues {
            let calendar = Color(hex: hex)
            for state in Self.states {
                let plate = Self.plate(calendar, selected: state.selected, active: state.active)
                let glyph = CadenceCalendarEventStyle.boardCardGlyphColor(
                    for: calendar,
                    isSelected: state.selected,
                    isActive: state.active
                )
                let ratio = Self.ratio(Self.luminance(Self.components(glyph)), Self.luminance(plate))
                #expect(ratio >= 3.0, "\(hex) \(state): leading glyph is \(ratio):1 on the card")
            }
        }
    }

    /// The hue survives the lift: the blue calendar's ink is still blue, not a grey that happens to
    /// be legible. Its blue channel leads both others by a wide margin.
    @Test func theLiftKeepsTheCalendarsHue() {
        let blue = Self.components(CadenceCalendarEventStyle.boardChipLabelColor(for: Color(hex: "#0000ff")))
        #expect(blue.b - max(blue.r, blue.g) > 0.2, "blue ink came back as \(blue)")
        let red = Self.components(CadenceCalendarEventStyle.boardChipLabelColor(for: Color(hex: "#3d0000")))
        #expect(red.r - max(red.g, red.b) > 0.2, "deep-red ink came back as \(red)")
    }

    /// A floor, not a target: a calendar that is already legible keeps exactly the colour it chose.
    @Test func anAlreadyLegibleCalendarKeepsItsOwnColour() {
        for hex in ["#ffc857", "#4fd6e0", "#ffffff"] {
            let calendar = Color(hex: hex)
            let raw = Self.components(calendar)
            let ink = Self.components(CadenceCalendarEventStyle.boardChipLabelColor(for: calendar))
            #expect(abs(raw.r - ink.r) < 0.001 && abs(raw.g - ink.g) < 0.001 && abs(raw.b - ink.b) < 0.001,
                    "\(hex) was legible and still moved to \(ink)")
        }
    }

    @Test func lightSurfacesDarkenTheInkInsteadOfLiftingIt() {
        for background in [1.0, 0.80] {
            for hex in ["#ffc857", "#4fd6e0", "#ffffff", "#ff3b30"] {
                let calendar = Color(hex: hex)
                let ink = CadenceCalendarEventStyle.legibleTint(
                    for: calendar,
                    againstLuminance: background,
                    ratio: CadenceCalendarEventStyle.boardChipLabelContrastFloor
                )
                let inkLuminance = Self.luminance(Self.components(ink))
                #expect(Self.ratio(inkLuminance, background) >= 4.5, "\(hex) on Y=\(background)")
                #expect(inkLuminance < background, "\(hex) on Y=\(background) was lifted, not darkened")
            }
        }
    }

    /// Both boards' cards read the floored ink; neither paints its glyph or chips the raw colour.
    @Test func bothBoardCardsDrawTheFlooredInk() throws {
        let chip = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/Shared/Components/CadenceBoardMetadataChip.swift")
        )
        #expect(chip.contains("CadenceCalendarEventStyle.boardChipLabelColor("))
        #expect(!chip.contains(".foregroundStyle(tint)"))

        let iOS = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSBoardCards.swift"))
        let iOSCard = try #require(CadenceSourceScan.declarationBody("struct iOSCalendarBoardEventCard: View", in: iOS))
        #expect(iOSCard.contains("CadenceCalendarEventStyle.boardCardGlyphColor(for: item.color)"))
        #expect(!iOSCard.contains(".foregroundStyle(item.color)"))

        let mac = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/CalendarBoardItemSupportViews.swift")
        )
        let macCard = try #require(CadenceSourceScan.declarationBody("struct CalendarBoardEventCard: View", in: mac))
        #expect(macCard.contains("CadenceCalendarEventStyle.boardCardGlyphColor("))
        #expect(!macCard.contains(".foregroundStyle(tint)"))
        #expect(macCard.components(separatedBy: "isCardActive: isHovered").count - 1 == 2,
                "the Mac's chips must read the card's hover state for their pill")
    }

    // MARK: - Independent WCAG arithmetic

    private typealias RGB = (r: Double, g: Double, b: Double)

    private static func components(_ color: Color) -> RGB {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        #if canImport(AppKit)
        let resolved = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #elseif canImport(UIKit)
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #endif
        return (Double(red), Double(green), Double(blue))
    }

    private static func over(_ top: RGB, _ alpha: Double, _ under: RGB) -> RGB {
        (top.r * alpha + under.r * (1 - alpha), top.g * alpha + under.g * (1 - alpha), top.b * alpha + under.b * (1 - alpha))
    }

    /// The card as both boards paint it: `Theme.surfaceElevated` over `Theme.bg`, then the tint.
    private static func plate(_ calendar: Color, selected: Bool, active: Bool) -> RGB {
        let surface = over(
            components(Theme.surfaceElevated),
            CadenceCalendarEventStyle.surfaceOpacity(isActive: active || selected),
            components(Theme.bg)
        )
        return over(
            components(calendar),
            CadenceCalendarEventStyle.tintOpacity(isSelected: selected, isActive: active),
            surface
        )
    }

    private static func pill(_ calendar: Color, selected: Bool, active: Bool) -> RGB {
        over(components(calendar), CadenceCalendarEventStyle.chipTintOpacity(), plate(calendar, selected: selected, active: active))
    }

    private static func luminance(_ c: RGB) -> Double {
        func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
    }

    private static func ratio(_ a: Double, _ b: Double) -> Double {
        (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}
