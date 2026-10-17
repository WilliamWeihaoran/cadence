import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Cadence

/// T-3160: which of the two calendar treatments each **timeline block** wears, on both platforms,
/// asserted in both directions.
///
/// `CadenceContrastFloorTests` proves the two treatments are each internally sound;
/// `CadenceTimelineTaskPlateTests` covers the macOS task block. This suite covers the blocks the
/// swap is *about* — the macOS and iOS event blocks, which take Apple Calendar's rail treatment,
/// and the iOS task block, which takes the solved plate they gave up.
///
/// **The negatives are the reason this file exists.** A swap like this fails silently rather than
/// loudly: an event that takes the dark plate but keeps drawing its title in `Theme.onColor` still
/// compiles, still clears AA, and still looks like *a* calendar block — it is simply not the one
/// that was asked for. A task that takes the plate and keeps its leading rail is the same failure
/// mirrored. Before this suite nothing in the repo asserted that an event block **has** a rail or
/// that a task block has **none**, which is exactly how half a swap lands and stays landed.
///
/// Every ratio below is computed from the live `CadenceCalendarEventStyle` solve and the live
/// `Theme` tokens. There is no table of remembered numbers.
@MainActor
struct CadenceTimelineBlockTreatmentTests {

    // MARK: - The macOS event block

    @Test func theMacEventBlockWearsTheRailTreatment() throws {
        let source = try t3160EventSource()

        #expect(
            CadenceSourceScan.matchCount(#"CadenceCalendarEventStyle\.railFill\(\s*for: item\.calendarColor"#, in: source) == 1,
            "the macOS event block no longer fills itself with the rail treatment's tinted plate"
        )
        for tier in ["railTitleColor", "railSecondaryLabelColor", "railTertiaryLabelColor", "railColor"] {
            #expect(
                CadenceSourceScan.matchCount(#"CadenceCalendarEventStyle\.\#(tier)\("#, in: source) == 1,
                "the macOS event block reads \(tier) \(CadenceSourceScan.matchCount(#"CadenceCalendarEventStyle\.\#(tier)\("#, in: source)) times, not once"
            )
        }
        #expect(
            CadenceSourceScan.matchCount(#"CadenceCalendarEventStyle\.railBorderOpacity\("#, in: source) == 3,
            "the block's edge no longer reads the rail treatment's own opacity ladder in all three states"
        )
    }

    /// **The negative.** An event still wearing the plate — or still reading it through the legacy
    /// unprefixed spelling, which after this ticket means the *wrong* treatment at an event call
    /// site — is the silent half-swap.
    @Test func theMacEventBlockWearsNothingFromThePlateTreatment() throws {
        let source = try t3160EventSource()

        #expect(
            CadenceSourceScan.matchCount(#"CadenceCalendarEventStyle\.plate"#, in: source) == 0,
            "the macOS event block is calling the plate treatment, which now belongs to tasks"
        )
        // The seven legacy spellings forward to `plate*`, so a bare `fill(` or `primaryLabelColor`
        // at an event call site is the old treatment under its historical name.
        #expect(
            CadenceSourceScan.matchCount(#"CalendarEventVisualStyle\."#, in: source) == 0,
            "the macOS event block still reads the legacy forwarder, which resolves to the plate treatment"
        )
        // The white accent hairline. It was a bare `Theme.onColor` wash at 0.18-0.48 laid across
        // the top of the block; over a plate solved to Y = 0.030-0.060 it composites brighter than
        // the rail itself, so it would have been a second, colourless accent marker competing with
        // the one that names the calendar.
        #expect(
            CadenceSourceScan.matchCount(#"Theme\.onColor(?![A-Za-z(])"#, in: source) == 0,
            "the white accent wash is still drawn on the rail treatment's dark plate"
        )
        #expect(
            CadenceSourceScan.matchCount(#"blockAccentOpacity"#, in: source) == 0,
            "the block still reads the accent-wash opacity ladder"
        )
    }

    // MARK: - The rails themselves

    /// Each event block draws exactly one rail, at the shared constant rather than a hand-typed
    /// `3`, and the task block draws none.
    @Test func eachEventBlockDrawsOneRailAtTheSharedWidthAndTheTaskBlockDrawsNone() throws {
        // Self-check the needle against a block that still draws this rail, so a `== 0` below
        // cannot pass by the pattern having stopped matching anything anywhere.
        let bundle = try t3160Source(t3160BundleBlockFile)
        #expect(
            CadenceSourceScan.matchCount(t3160RailNeedle, in: bundle) >= 1,
            "non-vacuity: the rail needle no longer finds the bundle block's own rail"
        )

        let surfaces: [(name: String, body: String, rails: Int)] = [
            ("the macOS event block", try t3160EventSource(), 1),
            ("the iOS event block", try t3160IOSEventBlock(), 1),
            ("the iOS task block", try t3160IOSTaskBlock(), 0),
        ]
        for surface in surfaces {
            // Since T-3167 an event rail is a plain strip shaped by its block's clip, so the
            // self-cornered spelling the bundle block still draws is no rail on any block here.
            #expect(
                CadenceSourceScan.matchCount(t3167EventRailNeedle, in: surface.body) == surface.rails,
                "\(surface.name) draws \(CadenceSourceScan.matchCount(t3167EventRailNeedle, in: surface.body)) rails, expected \(surface.rails)"
            )
            #expect(
                CadenceSourceScan.matchCount(t3160RailNeedle, in: surface.body) == 0,
                "\(surface.name) still draws a rail that rounds its own corners instead of being clipped by the block"
            )
            #expect(
                CadenceSourceScan.matchCount(#"CadenceCalendarEventStyle\.railWidth"#, in: surface.body) == surface.rails,
                "\(surface.name) does not read the shared rail width exactly \(surface.rails) time(s)"
            )
            // The audit that motivated `railWidth` found the rail hand-rolled five times as a bare
            // `3`. No surface here may add a sixth.
            #expect(
                CadenceSourceScan.matchCount(#"\.frame\(width: 3\)"#, in: surface.body) == 0,
                "\(surface.name) spells the rail width as a bare 3"
            )
        }
    }

    /// **The cascade's requirement on the rail.** T-3161 gave both platforms an overlap layout in
    /// which a later-starting block is *indented* over the body of the one it overlaps, so an
    /// indented block's leading rail is drawn on top of a differently-coloured plate. A rail drawn
    /// as a translucent wash would show that neighbour's hue through the one element whose whole
    /// job is to name *this* event's calendar, and the deeper the cascade the more wrong it gets.
    /// So the rail is an opaque fill, at every depth, on both platforms.
    @Test func theRailIsOpaqueSoACascadedBlockDoesNotShowItsNeighbourThroughIt() throws {
        for (name, body) in [("the macOS event block", try t3160EventSource()), ("the iOS event block", try t3160IOSEventBlock())] {
            #expect(
                CadenceSourceScan.matchCount(#"\.fill\(railColor\)"#, in: body) == 1,
                "\(name) does not fill its rail with the opaque rail colour"
            )
            #expect(
                CadenceSourceScan.matchCount(#"\.fill\(railColor\.opacity\("#, in: body) == 0,
                "\(name) draws its rail as a translucent wash, so a cascaded block shows its neighbour through it"
            )
        }

        // And the layout really does indent, which is what makes the above matter rather than be
        // a precaution against nothing. Depth 0 is flush; each further depth is strictly deeper.
        let slotWidth: CGFloat = 200
        let indents = (0...2).map { CadenceCalendarOverlapLayout.cascadeIndent(slotWidth: slotWidth, depth: $0) }
        #expect(indents[0] == 0, "a depth-0 block is indented by \(indents[0])pt")
        #expect(indents[1] > CadenceCalendarEventStyle.railWidth, "a depth-1 rail at \(indents[1])pt does not clear the rail beneath it")
        #expect(indents[2] > indents[1], "depth 2 is not deeper than depth 1")
        // Even squeezed to the floor a cascaded block is several times the rail's own width, so
        // the rail never eats the block it marks.
        #expect(
            CadenceCalendarOverlapLayout.minimumCascadedWidth > CadenceCalendarEventStyle.railWidth * 4,
            "the narrowest cascaded block is \(CadenceCalendarOverlapLayout.minimumCascadedWidth)pt against a \(CadenceCalendarEventStyle.railWidth)pt rail"
        )
    }

    // MARK: - The rail is clipped to the block (T-3167)

    /// **Why the clip is required, as geometry.** A shape's corner radii are clamped to half its
    /// own width, so a strip `railWidth` wide cannot carry the plate's corner radius: rounding the
    /// rail's own corners leaves it standing proud of the plate. How proud is the plate corner's
    /// height at the rail's trailing edge — positive on both platforms, which is the overhang the
    /// ticket photographed (~2.3pt at macOS's 9pt `TimelineBlockStyle.calendar` corner, ~5px at 2x).
    @Test func aRailNarrowerThanThePlateCornerOverhangsItUnlessTheBlockClipsIt() {
        let rail = CadenceCalendarEventStyle.railWidth
        for (name, radius) in [
            ("macOS Calendar page", TimelineBlockStyle.calendar.cornerRadius),
            ("macOS Schedule panel", TimelineBlockStyle.schedule.cornerRadius),
            ("iOS timeline", Theme.radiusControl),
        ] {
            #expect(radius > rail / 2, "\(name): a \(rail)pt rail can carry a \(radius)pt corner by itself")
            let inset: CGFloat = radius - rail
            let overhang: CGFloat = radius - (radius * radius - inset * inset).squareRoot()
            #expect(overhang > 1, "\(name): an unclipped rail stands only \(overhang)pt proud of the plate corner")
        }
    }

    /// **One construction on both platforms.** Each event block names one `blockShape`, fills or
    /// rims its plate with it, and clips its whole content — rail included — to it. A rectangular
    /// `.clipped()` is what let the macOS rail overhang; a self-cornered rail is the construction
    /// that could not follow the corner.
    @Test func bothEventBlocksClipTheirRailToTheOneShapeThePlateIsDrawnIn() throws {
        let blocks: [(name: String, body: String)] = [
            ("the macOS event block", try t3160EventSource()),
            ("the iOS event block", try t3160IOSEventBlock()),
        ]
        for block in blocks {
            #expect(
                CadenceSourceScan.matchCount(#"\.clipShape\(blockShape\)"#, in: block.body) == 1,
                "\(block.name) does not clip its content, rail included, to the block's own shape"
            )
            #expect(
                CadenceSourceScan.matchCount(#"\.clipped\(\)"#, in: block.body) == 0,
                "\(block.name) clips to its bounding box, which leaves the rail proud of the rounded corners"
            )
            #expect(
                CadenceSourceScan.matchCount(#"blockShape\s*\.strokeBorder\("#, in: block.body) == 1,
                "\(block.name) rims its plate with a shape other than the one it clips to"
            )
            // One declaration of the shape, so the clip and the plate cannot drift apart.
            #expect(
                CadenceSourceScan.matchCount(#"RoundedRectangle\(cornerRadius:"#, in: block.body) == 1,
                "\(block.name) spells its rounded rectangle more than once"
            )
            #expect(
                CadenceSourceScan.matchCount(#"UnevenRoundedRectangle"#, in: block.body) == 0,
                "\(block.name) still shapes a part of itself with corners of its own"
            )
        }
    }

    // MARK: - The iOS blocks

    @Test func theIOSEventBlockWearsTheRailTreatmentAndTheTaskBlockWearsThePlate() throws {
        let event = try t3160IOSEventBlock()
        for tier in ["railTitleColor", "railSecondaryLabelColor", "railTertiaryLabelColor", "railColor", "railBorderOpacity"] {
            #expect(
                CadenceSourceScan.matchCount(#"CadenceCalendarEventStyle\.\#(tier)\("#, in: event) == 1,
                "the iOS event block does not read \(tier) exactly once"
            )
        }
        #expect(
            CadenceSourceScan.matchCount(#"CadenceCalendarEventStyle\.plate"#, in: event) == 0,
            "the iOS event block is calling the plate treatment, which now belongs to tasks"
        )
        // The unprefixed legacy spellings forward to `plate*`; at an event call site they are the
        // treatment this ticket took away.
        for legacy in ["primaryLabelColor", "secondaryLabelColor", "tertiaryLabelColor", "chipBorderOpacity"] {
            #expect(
                CadenceSourceScan.matchCount(#"CadenceCalendarEventStyle\.\#(legacy)"#, in: event) == 0,
                "the iOS event block still reads \(legacy), a legacy spelling of the plate treatment"
            )
        }

        // The plate reaches the block through its own support helper, so the swap is one edit
        // rather than one per call site.
        let support = try t3160Source(t3160IOSEventSupportFile)
        #expect(
            CadenceSourceScan.matchCount(#"CadenceCalendarEventStyle\.railFill\("#, in: support) == 1,
            "iOSCalendarEventSupport.fillColor no longer returns the rail treatment's plate"
        )
        #expect(
            CadenceSourceScan.matchCount(#"CadenceCalendarEventStyle\.fill\("#, in: support) == 0,
            "iOSCalendarEventSupport.fillColor still returns the plate treatment through its legacy spelling"
        )

        let task = try t3160IOSTaskBlock()
        #expect(
            // [[T-1475]]: a block lifted for a move or resize reads the same plate's selected rung,
            // so the one fill call may carry `isSelected:` — still one call, still the plate.
            CadenceSourceScan.matchCount(#"CadenceCalendarEventStyle\.plateFill\(for: listColor(, isSelected: isLifted)?\)"#, in: task) == 1,
            "the iOS task block no longer fills itself with the solved plate in its list's hue"
        )
        #expect(
            CadenceSourceScan.matchCount(#"CadenceCalendarEventStyle\.rail"#, in: task) == 0,
            "the iOS task block is calling the rail treatment, which belongs to events"
        )
        // Ink chosen for the near-black surface the plate replaced. `Theme.dim` reads about 2:1 on
        // it and `Theme.surfaceElevated` is the surface itself.
        for retired in [#"Theme\.dim"#, #"Theme\.text(?![A-Za-z])"#, #"Theme\.surfaceElevated"#, #"Theme\.borderSubtle"#] {
            #expect(
                CadenceSourceScan.matchCount(retired, in: task) == 0,
                "\(retired) is still drawn on the iOS task block's solved plate, where it was never measured"
            )
        }
    }

    // MARK: - What the paint is, measured

    /// **The heart of the swap, as arithmetic rather than as a call-site count.** An event's title
    /// is now drawn *in the calendar's own hue*; a task's is `Theme.onColor`. A refactor that put
    /// the rail on the event but left its title white would pass every scan above and still be the
    /// wrong screen, so this measures the chroma that each treatment's primary tier actually has.
    @Test func theEventTitleIsInItsCalendarsHueAndTheTaskTitleIsNot() {
        #expect(
            t3160Saturation(CadenceCalendarEventStyle.platePrimaryLabelColor) == 0,
            "the plate treatment's primary tier is no longer achromatic, so 'the task title is white' has stopped being true"
        )

        var measured = 0
        for hex in t3160ChromaticCalendarHues {
            let swatch = Color(hex: hex)
            let sourceHue = t3160Hue(swatch)
            for state in t3160BlockStates {
                measured += 1
                let title = CadenceCalendarEventStyle.railTitleColor(
                    for: swatch,
                    isSelected: state.isSelected,
                    isActive: state.isActive
                )
                #expect(
                    t3160Saturation(title) > 0.2,
                    "the event title on a \(hex) calendar is \(t3160Rounded(t3160Saturation(title))) saturated \(state.name) — it has washed out into white"
                )
                #expect(
                    abs(t3160Hue(title) - sourceHue) < 0.005,
                    "the event title on a \(hex) calendar has drifted off its hue \(state.name)"
                )
            }
        }
        #expect(measured == 15, "non-vacuity: five chromatic hues in three states, \(measured) measured")
    }

    /// Every tier each block actually draws, in the states it actually draws them in, against the
    /// plate it actually lands on.
    @Test func everyTierTheseBlocksDrawClearsItsFloorOnItsOwnPlate() {
        var measured = 0
        for hex in t3160CalendarHues {
            let swatch = Color(hex: hex)
            // The macOS event block passes hover and selection through; the iOS one carries no
            // interaction state and reads the same functions at rest, which is the first row here.
            for state in t3160BlockStates {
                let plate = CadenceCalendarEventStyle.railFill(
                    for: swatch,
                    isSelected: state.isSelected,
                    isActive: state.isActive
                )
                let tiers: [(name: String, color: Color, floor: Double)] = [
                    ("title", CadenceCalendarEventStyle.railTitleColor(for: swatch, isSelected: state.isSelected, isActive: state.isActive), 4.5),
                    // The time range, the calendar name and the "calendar" glyph all read this one.
                    ("secondary", CadenceCalendarEventStyle.railSecondaryLabelColor(for: swatch, isSelected: state.isSelected, isActive: state.isActive), 4.5),
                    // The recurrence marker: a glyph, so it owes the 3:1 non-text bar.
                    ("recurrence glyph", CadenceCalendarEventStyle.railTertiaryLabelColor(for: swatch, isSelected: state.isSelected, isActive: state.isActive), 3),
                ]
                for tier in tiers {
                    measured += 1
                    let ratio = t3160Ratio(tier.color, on: plate)
                    #expect(
                        ratio >= tier.floor,
                        "the event block's \(tier.name) reads \(t3160Rounded(ratio)):1 on a \(hex) plate, \(state.name)"
                    )
                }
            }
        }
        #expect(measured == t3160CalendarHues.count * 9, "non-vacuity: \(measured) event-block measurements")

        // The iOS task block: both tiers at rest, on every colour a list can be.
        let listColours = CadenceColorPalette.colors
        #expect(listColours.count == 12, "non-vacuity: the list colour menu is \(listColours.count) swatches")
        for hex in listColours {
            let plate = CadenceCalendarEventStyle.plateFill(for: Color(hex: hex))
            for tier in [
                ("title", CadenceCalendarEventStyle.platePrimaryLabelColor),
                ("time range / completed title", CadenceCalendarEventStyle.plateSecondaryLabelColor()),
            ] {
                let ratio = t3160Ratio(tier.1, on: plate)
                #expect(
                    ratio >= 4.5,
                    "the iOS task block's \(tier.0) reads \(t3160Rounded(ratio)):1 on a \(hex) plate"
                )
            }
            // The control that sends a block back to Today's tasks sits on that same plate. It
            // used to be the list colour on a wash of itself, which the plate made hue-on-hue.
            let well = t3160Flatten(Theme.onColorBorder, on: plate)
            #expect(
                t3160Ratio(CadenceCalendarEventStyle.platePrimaryLabelColor, on: well) >= 3,
                "the clear-time glyph reads \(t3160Rounded(t3160Ratio(CadenceCalendarEventStyle.platePrimaryLabelColor, on: well))):1 in its well on a \(hex) plate"
            )
        }
    }

    // MARK: - Paint moved, affordances did not

    @Test func theTimelineSwapMovedPaintAndNotTheAffordances() throws {
        let macEvent = try t3160EventSource()
        // The recurrence marker, the two resize handles, the move drag, the tap, the popover and
        // the recurrence-scope dialog: every one of them is what tells an event from a task once
        // the two plates are closest, and none of them is paint.
        #expect(CadenceSourceScan.matchCount(#"isRecurringSeriesMember"#, in: macEvent) == 2)
        #expect(CadenceSourceScan.matchCount(#"Image\(systemName: "repeat"\)"#, in: macEvent) == 1)
        #expect(CadenceSourceScan.matchCount(#"resizeHandle\(edge: \."#, in: macEvent) == 2)
        #expect(CadenceSourceScan.matchCount(#"\.popover\("#, in: macEvent) == 1)
        #expect(CadenceSourceScan.matchCount(#"\.confirmationDialog\("#, in: macEvent) == 1)

        let iosEvent = try t3160IOSEventBlock()
        #expect(CadenceSourceScan.matchCount(#"Image\(systemName: "calendar"\)"#, in: iosEvent) == 1)
        #expect(
            CadenceSourceScan.matchCount(#"iOSTaskCompletionCircle"#, in: iosEvent) == 0,
            "the event block grew a completion circle, which is the task's affordance"
        )

        let iosTask = try t3160IOSTaskBlock()
        #expect(
            CadenceSourceScan.matchCount(#"iOSTaskCompletionCircle"#, in: iosTask) == 1,
            "the task block lost its completion circle"
        )
        // [[T-3170]] took the block-forming drag and drop off this block on purpose — that is the
        // retirement of a gesture, not paint — so the lift, the drop and the targeted tint are gone.
        #expect(CadenceSourceScan.matchCount(#"\.draggable\("#, in: iosTask) == 0)
        #expect(CadenceSourceScan.matchCount(#"\.dropDestination\("#, in: iosTask) == 0)
        #expect(CadenceSourceScan.matchCount(#"isBundleFormingTargeted"#, in: iosTask) == 0)
        #expect(CadenceSourceScan.matchCount(#"taskInspector\(task\)"#, in: iosTask) == 1)
        #expect(CadenceSourceScan.matchCount(#"onClearTime"#, in: iosTask) >= 3)
    }
}

// MARK: - Fixtures

private let t3160EventBlockFile = "Cadence/macOS/Views/TimelineEventBlock.swift"
private let t3160BundleBlockFile = "Cadence/macOS/Views/TimelineBundleBlock.swift"
private let t3160IOSTimelineFile = "Cadence/iOS/iOSCalendarTimelineViews.swift"
private let t3160IOSEventSupportFile = "Cadence/iOS/iOSCalendarEventSupport.swift"

/// A rail is an `UnevenRoundedRectangle` whose *leading* corners are the ones given a radius — it
/// follows the block's rounding on the outside and is square where it meets the label column.
private let t3160RailNeedle = #"UnevenRoundedRectangle\(\s*topLeadingRadius:"#

/// An event rail since T-3167: a plain opaque strip, shaped by the block's own clip.
private let t3167EventRailNeedle = #"Rectangle\(\)\s*\.fill\(railColor\)"#

private let t3160BlockStates: [(name: String, isSelected: Bool, isActive: Bool)] = [
    ("at rest", false, false),
    ("hovered", false, true),
    ("selected", true, false),
]

/// The hues a calendar colour sweep has to cover: the palette's bright end, a raw white calendar,
/// and the degenerate corners a stored `colorHex` can reach.
private let t3160CalendarHues = ["#ffc857", "#4fd6e0", "#ffffff", "#4a9eff", "#3d0000", "#0000ff", "#000000"]

/// The subset with a hue to keep. A white or black calendar has no chroma for a title to be drawn
/// in, so asking one to produce a saturated title is asking the impossible rather than asserting
/// the rule.
private let t3160ChromaticCalendarHues = ["#ffc857", "#4fd6e0", "#4a9eff", "#3d0000", "#0000ff"]

// MARK: - WCAG arithmetic

private func t3160Components(_ color: Color) -> (r: Double, g: Double, b: Double, a: Double) {
    let resolved = NSColor(color)
    let srgb = resolved.usingColorSpace(.sRGB) ?? resolved
    return (Double(srgb.redComponent), Double(srgb.greenComponent), Double(srgb.blueComponent), Double(srgb.alphaComponent))
}

private func t3160Luminance(_ color: Color) -> Double {
    let (r, g, b, _) = t3160Components(color)
    let linear = [r, g, b].map { channel in
        channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
}

/// `top` composited onto `under`, so an alpha colour has something to be a colour *on*.
private func t3160Flatten(_ top: Color, on under: Color) -> Color {
    let foreground = t3160Components(top)
    let background = t3160Components(under)
    return Color(
        .sRGB,
        red: foreground.r * foreground.a + background.r * (1 - foreground.a),
        green: foreground.g * foreground.a + background.g * (1 - foreground.a),
        blue: foreground.b * foreground.a + background.b * (1 - foreground.a),
        opacity: 1
    )
}

private func t3160Ratio(_ foreground: Color, on background: Color) -> Double {
    let flattened = t3160Flatten(foreground, on: background)
    let lighter = max(t3160Luminance(flattened), t3160Luminance(background))
    let darker = min(t3160Luminance(flattened), t3160Luminance(background))
    return (lighter + 0.05) / (darker + 0.05)
}

private func t3160Hue(_ color: Color) -> Double {
    var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
    let resolved = NSColor(color)
    let srgb = resolved.usingColorSpace(.sRGB) ?? resolved
    srgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
    return Double(hue)
}

private func t3160Saturation(_ color: Color) -> Double {
    var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
    let resolved = NSColor(color)
    let srgb = resolved.usingColorSpace(.sRGB) ?? resolved
    srgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
    return Double(saturation)
}

private func t3160Rounded(_ value: Double) -> Double {
    (value * 100).rounded() / 100
}

// MARK: - Source reading

private func t3160Source(_ path: String) throws -> String {
    let raw = try CadenceSourceScan.sourceFile(path)
    #expect(raw.count > 400, "\(path) read as \(raw.count) characters")
    let stripped = CadenceSourceScan.strippingComments(raw)
    #expect(stripped.count == raw.count, "\(path): the stripper changed the length")
    #expect(stripped != raw, "\(path): nothing was stripped, so the stripper is not running")
    return stripped
}

/// Whole-file for the Mac event block: the file declares exactly one view, and the paint it is
/// asserted on is spread between `eventBlockBody` and the two computed colours it reads.
private func t3160EventSource() throws -> String {
    let source = try t3160Source(t3160EventBlockFile)
    #expect(
        CadenceSourceScan.matchCount(#"\nstruct [A-Za-z]+: View \{"#, in: source) == 1,
        "non-vacuity: \(t3160EventBlockFile) no longer holds exactly one view, so a whole-file scan has stopped being scoped to the event block"
    )
    return source
}

private func t3160IOSEventBlock() throws -> String {
    let source = try t3160Source(t3160IOSTimelineFile)
    let body = try #require(
        CadenceSourceScan.declarationBody("private struct iOSCalendarEventBlock: View", in: source),
        "iOSCalendarEventBlock was not found in \(t3160IOSTimelineFile)"
    )
    #expect(body.count > 600, "non-vacuity: iOSCalendarEventBlock read as \(body.count) characters")
    return body
}

private func t3160IOSTaskBlock() throws -> String {
    let source = try t3160Source(t3160IOSTimelineFile)
    let body = try #require(
        CadenceSourceScan.declarationBody("struct iOSTimelineTaskBlock: View", in: source),
        "iOSTimelineTaskBlock was not found in \(t3160IOSTimelineFile)"
    )
    #expect(body.count > 1_000, "non-vacuity: iOSTimelineTaskBlock read as \(body.count) characters")
    return body
}
