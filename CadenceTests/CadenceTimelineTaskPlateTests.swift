// T-3244: compiled for macOS only. This suite reaches AppKit directly, and `CadenceTests` now
// also builds for an iOS destination, where that import does not resolve. The gate preserves
// exactly the coverage this file had before; narrowing it so the cross-platform half runs on iOS
// too is follow-up, not part of making the target iOS-capable.
#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Cadence

/// T-3160: the macOS timeline **task** block wears the solved plate, and wears nothing else.
///
/// The swap this suite pins is half visual-vocabulary and half arithmetic, and both halves can
/// land silently half-done:
///
/// - **The negative had nothing holding it.** A task block that took the plate fill *and kept its
///   leading colour rail* compiles, renders, and looks almost right — it just reads as neither
///   treatment. Nothing in the repo asserted the absence of the rail, so the positive assertion
///   alone is not enough; `theScheduledTaskBlockHasNoLeadingColourRail` is the half that catches a
///   half-finished swap, and it self-checks its needle against the rail `TimelineBundleBlock.swift`
///   drew until [[T-3170]] deleted it, kept as a fixture.
/// - **The plate changed what ink is affordable, and the old ink was not re-measured anywhere.**
///   `Theme.dim`, `Theme.text` and `CadenceDueUrgency.tint` were all chosen against a near-black
///   `Theme.surfaceElevated`. Against a fill solved to Y = 0.098–0.150 they are 1.48–4.61:1. The
///   two arithmetic tests below are the record of that: one says what the block *does* use clears
///   AA on every list colour the app offers, the other says why no tint could have.
///
/// Every ratio here is computed from the live `CadenceCalendarEventStyle` solve and the live
/// `Theme` tokens. There is no table of remembered numbers, for the reason
/// `CadenceContrastFloorTests` gives at length.
@MainActor
struct CadenceTimelineTaskPlateTests {

    // MARK: - What the block wears

    @Test func theScheduledTaskBlockWearsTheSolvedPlateAndNotANeutralSurface() throws {
        let body = try t3160TaskBlockBody()

        // The state arguments are part of the needle on purpose: a `plateFill(for: taskColor)`
        // that forgot them still compiles, still looks like the plate, and silently drops hover
        // and selection feedback — the ladder is the only thing carrying either now that the
        // white hover wash is gone.
        #expect(
            CadenceSourceScan.matchCount(
                #"CadenceCalendarEventStyle\.plateFill\(\s*for: taskColor,\s*isSelected: showSelection,\s*isActive: showHover\s*\)"#,
                in: body
            ) == 1,
            "the task block no longer fills itself with the solved plate on its own state ladder"
        )
        #expect(
            CadenceSourceScan.matchCount(#"Theme\.surfaceElevated"#, in: body) == 0,
            "the task block is still painting the neutral surface the plate replaced"
        )
        #expect(
            CadenceSourceScan.matchCount(#"taskColor\.opacity\("#, in: body) == 0,
            "the task block is still washing its list colour over a surface instead of solving a fill"
        )
    }

    /// **The negative.** A rail left behind on a plated task is the silent half-swap.
    @Test func theScheduledTaskBlockHasNoLeadingColourRail() throws {
        let needle = #"UnevenRoundedRectangle\(\s*topLeadingRadius:"#

        // Self-check the needle on the spelling it hunts, so a `== 0` below cannot pass by the
        // pattern having stopped matching anything anywhere.
        #expect(
            CadenceSourceScan.matchCount(needle, in: t3160RetiredBundleRailSpelling) == 1,
            "non-vacuity: the rail needle no longer finds the retired bundle block's rail"
        )

        let body = try t3160TaskBlockBody()
        #expect(CadenceSourceScan.matchCount(needle, in: body) == 0, "the task block still draws a leading colour rail")
        #expect(
            CadenceSourceScan.matchCount(#"\.frame\(width: 3\)"#, in: body) == 0,
            "the task block still draws a 3pt leading strip"
        )
        #expect(
            CadenceSourceScan.matchCount(#"CadenceCalendarEventStyle\.rail"#, in: body) == 0,
            "the task block is calling the rail treatment, which belongs to events"
        )
    }

    /// Nothing drawn on the plate may be ink chosen for a near-black surface.
    @Test func theTaskBlockDrawsNoInkThatWasSolvedForANeutralSurface() throws {
        let body = try t3160TaskBlockBody()

        for retired in [#"Theme\.dim"#, #"Theme\.text"#, #"dueUrgency\?\.tint"#] {
            #expect(
                CadenceSourceScan.matchCount(retired, in: body) == 0,
                "\(retired) is still drawn on the solved plate, where it was never measured"
            )
        }
        #expect(
            CadenceSourceScan.matchCount(#"CadenceCalendarEventStyle\.plate(Primary|Secondary)LabelColor"#, in: body) >= 2,
            "non-vacuity: the block no longer reads the plate's own ink tiers"
        )
    }

    // MARK: - The arithmetic behind that ink

    /// Every tier the block actually draws, against every colour a list can be.
    @Test func everyInkTierTheTaskBlockUsesClearsAAOnEveryListColour() {
        let listColours = CadenceColorPalette.colors
        #expect(listColours.count == 12, "non-vacuity: the list colour menu is \(listColours.count) swatches")

        for hex in listColours {
            let tint = Color(hex: hex)
            for state in t3160PlateStates {
                let plate = CadenceCalendarEventStyle.plateFill(
                    for: tint,
                    isSelected: state.isSelected,
                    isActive: state.isActive
                )

                let primary = t3160Ratio(CadenceCalendarEventStyle.platePrimaryLabelColor, on: plate)
                #expect(
                    primary >= 4.5,
                    "the title reads \(t3160Rounded(primary)):1 on a \(hex) plate, \(state.name)"
                )

                let secondary = t3160Ratio(
                    CadenceCalendarEventStyle.plateSecondaryLabelColor(
                        isSelected: state.isSelected,
                        isActive: state.isActive
                    ),
                    on: plate
                )
                #expect(
                    secondary >= 4.5,
                    "the time range / duration / non-urgent due line reads \(t3160Rounded(secondary)):1 on a \(hex) plate, \(state.name)"
                )
            }
        }
    }

    /// **Why the due-urgency hue could not come along.**
    ///
    /// `CadenceDueUrgency.tint` is `Theme.red` / `Theme.amber` / `Theme.dim`, and the deadline is
    /// the one line on this block the user is meant to act on — so the tint was measured against
    /// the plate rather than carried over on the assumption that a colour that worked on
    /// `Theme.surfaceElevated` works anywhere.
    ///
    /// No accent in any shipped palette clears 4.5:1 in *every* state (Glacier's amber clears it
    /// at rest alone and falls to 3.41:1 when selected), and the overdue tint — the most urgent
    /// thing this block can say — misses even the 3:1 non-text bar on all three stops. Urgency
    /// therefore moves to the white tier ladder, which the wording can carry because
    /// `CadenceWidgetDateSupport.dueLabel` already writes "Overdue …" and "Due today" out.
    @Test func noAccentHueCouldHaveCarriedUrgencyOnThisPlate() {
        let palettes = CadenceAccentPalette.all
        #expect(palettes.count == 3, "non-vacuity: the app ships \(palettes.count) accent palettes")

        for palette in palettes {
            for hex in palette.swatchHexes {
                let worst = t3160PlateStates
                    .map { state in
                        t3160Ratio(
                            Color(hex: hex),
                            on: CadenceCalendarEventStyle.plateFill(
                                for: Color(hex: CadenceColorPalette.areaDefault),
                                isSelected: state.isSelected,
                                isActive: state.isActive
                            )
                        )
                    }
                    .min() ?? 0
                #expect(
                    worst < 4.5,
                    "\(palette.id) \(hex) now clears AA on the plate in every state — the tier-based urgency this block ships can be reconsidered"
                )
            }
        }

        // The specific tint the block used to draw, and the reason this is not a close call.
        for state in t3160PlateStates {
            let plate = CadenceCalendarEventStyle.plateFill(
                for: Color(hex: CadenceColorPalette.areaDefault),
                isSelected: state.isSelected,
                isActive: state.isActive
            )
            let overdue = t3160Ratio(CadenceDueUrgency.overdue.tint, on: plate)
            #expect(
                overdue < 3,
                "the overdue tint reads \(t3160Rounded(overdue)):1 on the plate, \(state.name) — above the 3:1 non-text bar it was asserted to miss"
            )
            // Dark ink is not an escape hatch either: the plate is bright enough that black fails too.
            #expect(t3160Ratio(.black, on: plate) < 4.5, "non-vacuity: black ink would have cleared AA on this plate")
        }
    }

    // MARK: - The two layers that are not ink

    /// **The resize grip is an affordance, and the plate nearly took it.**
    ///
    /// `Theme.onColorHandleActive` is white at 0.42 and was solved against the near-black
    /// `Theme.surfaceElevated` this block used to sit on. On the plate it falls to roughly 2.2:1 —
    /// under the 3:1 WCAG asks of a non-text UI component, which is the floor a drag handle owes.
    /// The block now draws the emphasized grip in the plate's own incidental-glyph tier instead,
    /// and both halves of that claim are measured here: the tier clears 3:1 on every list colour,
    /// and the token it replaced does not.
    ///
    /// The *idle* grip keeps `Theme.onColorHandle` and is deliberately left under the bar. It is
    /// not an affordance until the pointer is on the block — `isEmphasized` covers hover,
    /// selection and an in-flight resize — and it was below the bar on the old surface too.
    @Test func theEmphasizedResizeHandleStaysFindableOnThePlate() throws {
        let wrapper = try t3160Source("Cadence/macOS/Views/TimelineTaskBlock.swift")
        #expect(
            CadenceSourceScan.matchCount(#"Theme\.onColorHandleActive"#, in: wrapper) == 0,
            "the task block's emphasized resize grip still uses the alpha solved for a near-black surface"
        )
        #expect(
            CadenceSourceScan.matchCount(
                #"CadenceCalendarEventStyle\.plateTertiaryLabelColor\(isActive: true\)"#,
                in: wrapper
            ) == 1,
            "the emphasized resize grip no longer reads a tier solved against this plate"
        )

        let emphasized = CadenceCalendarEventStyle.plateTertiaryLabelColor(isActive: true)
        for hex in CadenceColorPalette.colors {
            // Only the two bright stops: the grip is emphasized exactly when the block is hovered,
            // selected or being dragged, and those are the plates it is drawn on.
            for state in t3160PlateStates.filter({ $0.isSelected || $0.isActive }) {
                let plate = CadenceCalendarEventStyle.plateFill(
                    for: Color(hex: hex),
                    isSelected: state.isSelected,
                    isActive: state.isActive
                )
                let ratio = t3160Ratio(emphasized, on: plate)
                #expect(
                    ratio >= 3,
                    "the emphasized resize grip reads \(t3160Rounded(ratio)):1 on a \(hex) plate, \(state.name) — under the 3:1 non-text floor"
                )
                #expect(
                    t3160Ratio(Theme.onColorHandleActive, on: plate) < 3,
                    "non-vacuity: Theme.onColorHandleActive now clears 3:1 on this plate, so the swap above can be reconsidered"
                )
            }
        }
    }

    /// **The decorative layer over the plate, measured rather than assumed.**
    ///
    /// A finished task is struck through with `DiagonalStripeOverlay`, which strokes
    /// `Theme.onColorBorder` — white at 0.14 — across the whole block, title included. A wash over
    /// a solved plate spends contrast margin, so this one was measured on the way through rather
    /// than waved past as "a bigger surface is more forgiving".
    ///
    /// Both the title and the plate under it are lifted by the same 0.14, so the ratio compresses
    /// rather than collapsing: the done title lands at about **3.6:1** where a stripe crosses it,
    /// under AA. **That is a pre-existing miss and the plate made it better, not worse** — on the
    /// old neutral surface the same overlay put the same title at about 3.4:1. It is left as it
    /// is, and pinned, for two reasons: moving the stripes *behind* the text would lift only the
    /// background and make the ratio worse, and the band is held here so a future change to either
    /// the overlay's alpha or the plate ladder has to come past this number.
    @Test func theDoneStripeOverlayCompressesTheTitleButNoLongerThanItAlreadyDid() {
        for hex in CadenceColorPalette.colors {
            for state in t3160PlateStates {
                let plate = CadenceCalendarEventStyle.plateFill(
                    for: Color(hex: hex),
                    isSelected: state.isSelected,
                    isActive: state.isActive
                )
                let title = CadenceCalendarEventStyle.plateSecondaryLabelColor(
                    isSelected: state.isSelected,
                    isActive: state.isActive
                )
                let struckTitle = t3160Composited(Theme.onColorBorder, over: t3160Composited(title, over: plate))
                let struckPlate = t3160Composited(Theme.onColorBorder, over: plate)
                let ratio = t3160Ratio(struckTitle, on: struckPlate)
                #expect(
                    ratio >= 3.5,
                    "a struck-through done title reads \(t3160Rounded(ratio)):1 on a \(hex) plate, \(state.name) — below the band this overlay has always held"
                )
            }
        }

        // Non-vacuity: the overlay really does change the answer, so the band above is about
        // something. An unstruck title on the same plate is the AA-clearing number.
        let plate = CadenceCalendarEventStyle.plateFill(for: Color(hex: CadenceColorPalette.areaDefault))
        let plain = t3160Ratio(CadenceCalendarEventStyle.plateSecondaryLabelColor(), on: plate)
        let struck = t3160Ratio(
            t3160Composited(Theme.onColorBorder, over: t3160Composited(CadenceCalendarEventStyle.plateSecondaryLabelColor(), over: plate)),
            on: t3160Composited(Theme.onColorBorder, over: plate)
        )
        #expect(plain >= 4.5)
        #expect(struck < plain, "non-vacuity: the stripe overlay did not change the title's contrast at all")
    }

    // MARK: - The completion circle ([[T-8393]])

    /// The block's circle asks the manager the same three questions the task row and the Kanban
    /// card do — what to draw, how far it has filled, what a click does — so a cancellation
    /// started on the row draws on the block, and a second click mid-fill starts a cancellation
    /// instead of taking the fill back.
    @Test func theTimelineBlockCircleRunsTheSharedThreeTapWalk() throws {
        let block = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TimelineTaskBlock.swift"))
        let content = try #require(CadenceSourceScan.functionBody(named: "blockContent", in: block), "non-vacuity: blockContent moved")
        #expect(content.contains("onToggleDone: { taskCompletionAnimationManager.advanceCompletionControl(for: task) }"),
                "the block's circle is not on the three-tap walk")
        #expect(!block.contains("toggleCompletion(for: task)"), "the block still calls the two-state toggle")
        #expect(content.contains("completionGlyph: taskCompletionAnimationManager.glyph(for: task)"),
                "the block's glyph cannot see a pending cancellation")
        #expect(content.contains("completionProgress: now.flatMap { taskCompletionAnimationManager.pendingProgress(for: task, now: $0) } ?? 0"),
                "the block's fill cannot run a cancellation's progress")
        let gate = try #require(CadenceSourceScan.declarationBody("private var hasPendingFill: Bool", in: block))
        #expect(gate.contains("isPendingCompletion || taskCompletionAnimationManager.isPendingCancel(task)"),
                "the block animates only a completion's fill")
        let core = try #require(CadenceSourceScan.declarationBody("private var coreBlock: some View", in: block))
        // [[T-8412]]: the gate is both pending states AND Reduce Motion off.
        let motion = try #require(CadenceSourceScan.declarationBody("private var animatesPendingFill: Bool", in: block), "the block lost its motion gate")
        #expect(motion.contains("!reduceMotion && hasPendingFill"), "the block animates under Reduce Motion")
        #expect(block.contains("@Environment(\\.accessibilityReduceMotion) private var reduceMotion"), "the block does not read Reduce Motion")
        #expect(core.contains("if animatesPendingFill {"), "the block's TimelineView is not gated on either pending state and Reduce Motion")
        #expect(content.contains("isPendingCompletion: animatesPendingFill && isPendingCompletion"),
                "the still block draws a frozen fill and sweep instead of the pending glyph")

        let body = try t3160TaskBlockBody()
        #expect(body.contains("let glyph = completionGlyph ?? CadenceTaskCompletionGlyph.resolve(task: task)"))
        #expect(body.contains("progress: isPendingCompletion || isPendingCancellation ? clampedProgress : nil"),
                "the ring draws only a completion's fill")
        #expect(content.contains("isPendingCancellation: animatesPendingFill && taskCompletionAnimationManager.isPendingCancel(task)"),
                "the block's sweep cannot see a pending cancellation")
        #expect(body.contains("if isPendingCompletion || isPendingCancellation {"), "a cancellation draws no sweep on the block")
        #expect(body.contains("tint: isPendingCompletion ? Theme.green : secondaryInk"),
                "the cancellation sweep is not the plate's neutral ink")
    }
}

// MARK: - Fixtures

/// File scope rather than `static let` on the suite: the suite is `@MainActor`, and the source
/// helpers below are not — a `Self.taskBlockFile` read from one of them is a Swift 6 error in
/// waiting and a warning today, which this repo's baseline does not allow.
private let t3160TaskBlockFile = "Cadence/macOS/Views/TimelineTaskBlockSupportViews.swift"
/// The leading rail `TimelineBundleBlock` drew, kept verbatim as the needle's self-check after
/// [[T-3170]]'s trio pass deleted that file -- the last product view that drew this spelling. A
/// fixture rather than another product file, so the check cannot start passing by a live view
/// happening to stop (or start) drawing one.
private let t3160RetiredBundleRailSpelling = """
accent
    .frame(width: 3)
    .clipShape(UnevenRoundedRectangle(
        topLeadingRadius: style.cornerRadius,
        bottomLeadingRadius: style.cornerRadius
    ))
"""

private let t3160PlateStates: [(name: String, isSelected: Bool, isActive: Bool)] = [
    ("at rest", false, false),
    ("hovered", false, true),
    ("selected", true, false),
]

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

/// `foreground` on `background`, with an alpha foreground composited onto it first — the
/// `Theme.onColor*` tiers are white at 1.0 / 0.75 / 0.6 and have no ratio until they are told what
/// they are drawn on.
private func t3160Ratio(_ foreground: Color, on background: Color) -> Double {
    let top = t3160Components(foreground)
    let under = t3160Components(background)
    let flattened = Color(
        .sRGB,
        red: top.r * top.a + under.r * (1 - top.a),
        green: top.g * top.a + under.g * (1 - top.a),
        blue: top.b * top.a + under.b * (1 - top.a),
        opacity: 1
    )
    let lighter = max(t3160Luminance(flattened), t3160Luminance(background))
    let darker = min(t3160Luminance(flattened), t3160Luminance(background))
    return (lighter + 0.05) / (darker + 0.05)
}

/// `color` flattened onto `base`, as an opaque `Color` — so a wash can be stacked and then
/// measured, rather than measured as if it were opaque.
private func t3160Composited(_ color: Color, over base: Color) -> Color {
    let top = t3160Components(color)
    let under = t3160Components(base)
    return Color(
        .sRGB,
        red: top.r * top.a + under.r * (1 - top.a),
        green: top.g * top.a + under.g * (1 - top.a),
        blue: top.b * top.a + under.b * (1 - top.a),
        opacity: 1
    )
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

/// Scoped to `timelineBlockBody`'s own body. A whole-file scan here would be answered by
/// `TimelineDraggedTaskPreview`'s drag chrome, which is a different object with its own paint.
private func t3160TaskBlockBody() throws -> String {
    let source = try t3160Source(t3160TaskBlockFile)
    let body = try #require(
        CadenceSourceScan.functionBody(named: "timelineBlockBody", in: source),
        "timelineBlockBody( was not found in \(t3160TaskBlockFile)"
    )
    #expect(body.count > 1_000, "non-vacuity: timelineBlockBody read as \(body.count) characters")
    return body
}

#endif
