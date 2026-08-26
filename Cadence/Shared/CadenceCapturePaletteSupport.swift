import CoreGraphics
import Foundation
import SwiftUI

// MARK: - What a press to the capture button can turn into

/// The three things one touch on the blue `+` can become, and the one state it starts in.
///
/// **This is a value, not a gesture closure, because telling the three apart is the whole feature.**
/// A long-press that opens a palette and a drag that carries a new task to a list want the same
/// touch, and iOS recognizers starve each other happily: `UIDragInteraction`'s lift is a long press
/// of its own (measured 326–349ms here — see `AGENTS.md`), which is the *same* window the palette
/// wants, and it refuses to lift at all when the finger moves first. So the system drag cannot host
/// this and the disambiguation has to be ours. Written as a value it can be mutated and watched to
/// fail; written inside `onChanged` it could only be verified by feel.
///
/// The transitions are deliberately one-way. `.dragging` is terminal: once the finger has escaped,
/// no later event — including the hold timer firing late — may open the palette on top of it. That
/// arm is the one worth mutating, because "the palette opened during a drag" is the exact shape of
/// the starvation this design exists to avoid.
nonisolated enum CadenceCapturePressPhase: Equatable, Sendable {
    /// No live touch.
    case idle
    /// A finger is down and has neither escaped nor held still long enough.
    case pressing
    /// The hold elapsed with the finger still. The palette is showing and owns local movement.
    case palette
    /// The finger travelled far enough to be a drag. Terminal.
    case dragging
}

/// What lifting the finger commits to.
nonisolated enum CadenceCapturePressOutcome: Equatable, Sendable {
    /// Pressed and released without moving or waiting — the plain `+` tap.
    case tap
    /// A palette segment was under the finger.
    case action(CadenceCaptureAction)
    /// The palette was open but the finger was in the dead zone, or below the arc. Nothing happens.
    case dismissed
    /// The finger escaped; whatever it is over is the drop.
    case drop
    /// There was no live touch.
    case none
}

// MARK: - The numbers

/// The two figures T-171 says to settle by feel, plus the slop and the radii they imply.
///
/// `holdDelay` is UIKit's own lift window rounded to the figure the ticket names, so the palette
/// opens at the moment a finger that has decided to stay put expects *something* to happen.
///
/// `escapeRadius` **must exceed** `outerRadius`, and that is the one relationship here that is not a
/// taste call: the palette's segments have to be reachable without the reach itself converting into
/// a drag mid-choice. `theEscapeRadiusClearsThePalettesOwnReach` fails if they ever cross.
nonisolated enum CadenceCapturePaletteMetrics: Sendable {
    /// Still this long and the palette opens. UIKit's drag lift is 326–349ms; T-171 names ~350ms.
    static let holdDelay: TimeInterval = 0.35
    /// Movement past this before the hold elapses is a drag, immediately, and the palette is
    /// forfeit. Small enough that "press then move" never waits, large enough to survive the
    /// wobble of a thumb landing on a 44pt target.
    static let dragSlop: CGFloat = 12
    /// Inside this, no segment is selected: the palette's own centre is the cancel.
    static let innerRadius: CGFloat = 34
    /// Where a segment tile is centred.
    static let layoutRadius: CGFloat = 92
    /// The palette's visual reach — the outer edge of the drawn arc.
    static let outerRadius: CGFloat = 128
    /// Past this the palette gives up and the touch becomes a drag.
    static let escapeRadius: CGFloat = 172
    /// The width of one segment's tile. Published because the *spacing* between segment centres has
    /// to clear it — `noTwoSegmentTilesOverlapAtEitherPlacement` is the check, and it can only be
    /// written against a number both the drawing and the test read. The view draws this; it does not
    /// spell 52 a second time.
    static let segmentTileDiameter: CGFloat = 52

    /// How far the outer radius and the escape ring sit beyond wherever the tiles are laid out.
    ///
    /// The corner placement moves `layoutRadius` (see `CadenceCapturePalettePlacement`), and these
    /// two follow it rather than being re-chosen — the relationship "the arc is drawn out to here,
    /// and the touch escapes a comfortable distance past that" is the same relationship at both
    /// placements, so only one number is a placement decision.
    static let outerRadiusMargin: CGFloat = outerRadius - layoutRadius
    static let escapeRadiusMargin: CGFloat = escapeRadius - layoutRadius
}

// MARK: - Where the button is, and so which way the arc can open

/// Where on the screen the capture button the palette surrounds is pinned.
///
/// **This is the one thing that legitimately differs between the two `+`s.** iPhone and iPad share
/// the control, the gesture, the hold, the slop and the three segments; what they cannot share is
/// which way the arc opens, because that is a consequence of the placement and nothing else. A
/// button centred in the tab bar has the whole upper half of the screen above it. A button pinned
/// to a page's bottom-trailing corner has 50pt of screen to its right, so two thirds of a semicircle
/// would be drawn off the edge — the arc has to fold into the quadrant that exists.
///
/// Everything else is deliberately equal: the hold delay, the drag slop, the dead zone and the
/// margins the outer and escape rings keep beyond the tiles. A placement may choose *where* the
/// control's affordances are; it may not choose whether they exist or how they feel.
nonisolated enum CadenceCapturePalettePlacement: String, CaseIterable, Sendable {
    /// The iPhone tab bar's centre `+`. A full upward semicircle.
    case bottomCentre
    /// A page's floating corner `+`. A quadrant opening up and to the left.
    case bottomTrailing

    var metrics: CadenceCapturePaletteMetricsValues {
        switch self {
        case .bottomCentre: return .standard
        case .bottomTrailing: return .corner
        }
    }
}

// MARK: - The state machine

/// The three-way disambiguation, as three pure functions over a phase and a distance.
///
/// Distances are the straight-line travel from where the finger landed, in points. Nothing here
/// knows about views, gestures or time beyond "the hold elapsed", which is the only event a
/// still finger can generate.
nonisolated enum CadenceCapturePressResolver: Sendable {
    /// What a movement event does.
    ///
    /// From `.pressing` this is the "quick press then move" arm: past the slop it is a drag **now**,
    /// and because `.dragging` is terminal the palette can no longer appear. From `.palette` it is
    /// the "local dragging belongs to the palette" arm: everything short of the escape radius keeps
    /// the palette, which is what lets a finger slide between segments without the choice turning
    /// into a drag underneath it.
    static func phase(
        afterMovingTo distance: CGFloat,
        from phase: CadenceCapturePressPhase,
        metrics: CadenceCapturePaletteMetricsValues = .standard
    ) -> CadenceCapturePressPhase {
        switch phase {
        case .idle:
            return .idle
        case .pressing:
            return distance > metrics.dragSlop ? .dragging : .pressing
        case .palette:
            return distance > metrics.escapeRadius ? .dragging : .palette
        case .dragging:
            return .dragging
        }
    }

    /// What the hold timer does when it fires.
    ///
    /// **The `.dragging` arm is the point of this function.** The timer is armed at touch-down and
    /// cannot be un-armed synchronously with a movement that SwiftUI delivers on a later runloop
    /// turn, so it *will* fire during drags. Returning `.dragging` unchanged is what stops a palette
    /// blooming under a finger that is already carrying a task across the screen.
    static func phase(
        afterHoldFrom phase: CadenceCapturePressPhase,
        distance: CGFloat,
        metrics: CadenceCapturePaletteMetricsValues = .standard
    ) -> CadenceCapturePressPhase {
        guard phase == .pressing, distance <= metrics.dragSlop else { return phase }
        return .palette
    }

    /// What lifting the finger commits to.
    static func outcome(
        atEndOf phase: CadenceCapturePressPhase,
        selection: CadenceCaptureAction?
    ) -> CadenceCapturePressOutcome {
        switch phase {
        case .idle:
            return .none
        case .pressing:
            return .tap
        case .palette:
            return selection.map(CadenceCapturePressOutcome.action) ?? .dismissed
        case .dragging:
            return .drop
        }
    }
}

/// The metrics as a value, so a test can vary them and a call site cannot pick its own.
///
/// The app only ever uses `.standard`; the parameter exists because a resolver that reads statics
/// directly can only be tested at the shipping numbers, and "the escape radius is what separates
/// sliding from dragging" is a claim about the *relationship*, not about 172.
nonisolated struct CadenceCapturePaletteMetricsValues: Equatable, Sendable {
    var holdDelay: TimeInterval
    var dragSlop: CGFloat
    var innerRadius: CGFloat
    var layoutRadius: CGFloat
    var outerRadius: CGFloat
    var escapeRadius: CGFloat
    /// The low end of the sweep, in degrees counter-clockwise from pointing right.
    var arcStartDegrees: Double
    /// How far the sweep runs from `arcStartDegrees`.
    var arcSweepDegrees: Double

    static let standard = CadenceCapturePaletteMetricsValues(
        holdDelay: CadenceCapturePaletteMetrics.holdDelay,
        dragSlop: CadenceCapturePaletteMetrics.dragSlop,
        innerRadius: CadenceCapturePaletteMetrics.innerRadius,
        layoutRadius: CadenceCapturePaletteMetrics.layoutRadius,
        outerRadius: CadenceCapturePaletteMetrics.outerRadius,
        escapeRadius: CadenceCapturePaletteMetrics.escapeRadius,
        arcStartDegrees: 0,
        arcSweepDegrees: 180
    )

    /// The corner placement's numbers. **Only two of them are chosen**: the sweep folds to the
    /// quadrant that is on screen, and `layoutRadius` grows because three tiles packed into 90°
    /// instead of 180° would otherwise overlap — 118pt puts adjacent centres 61pt apart, clear of
    /// the 52pt tile. Everything else either is the standard value or is derived from
    /// `layoutRadius` by the standard's own margins, so the feel of the gesture cannot drift
    /// between the two placements while nobody is looking.
    static let corner = CadenceCapturePaletteMetricsValues(
        holdDelay: CadenceCapturePaletteMetrics.holdDelay,
        dragSlop: CadenceCapturePaletteMetrics.dragSlop,
        innerRadius: CadenceCapturePaletteMetrics.innerRadius,
        layoutRadius: cornerLayoutRadius,
        outerRadius: cornerLayoutRadius + CadenceCapturePaletteMetrics.outerRadiusMargin,
        escapeRadius: cornerLayoutRadius + CadenceCapturePaletteMetrics.escapeRadiusMargin,
        arcStartDegrees: 90,
        arcSweepDegrees: 90
    )

    private static let cornerLayoutRadius: CGFloat = 118

    /// The high end of the sweep.
    var arcEndDegrees: Double { arcStartDegrees + arcSweepDegrees }

    /// One segment's share of the sweep.
    var segmentDegrees: Double { arcSweepDegrees / Double(CadenceCapturePaletteGeometry.segmentCount) }
}

// MARK: - What the palette offers

/// The palette's segments: the three things this app captures.
///
/// T-171 names "task, calendar, note, and possibly a fourth". It is three. Each of these has a real
/// composer already standing behind it — `iOSCreateTaskSheet`, `iOSCalendarQuickCreateSheet`'s Event
/// segment, and a fresh notepad note in `iOSNoteEditorCover` — and a fourth would have had to be a
/// habit, which is a recurring commitment you set up rather than something you jot down on the way
/// past. Three 60° sectors on a semicircle is also the more forgiving thumb target than four 45°
/// ones, so the count that had a reason behind it is the count that reads better.
///
/// **The glyph and the tint are not spelled here.** Both come from the `CadenceFeatureDestination`
/// the segment leads to, for the reason `defaultColorHex` documents at length: an app-defined
/// palette decision written a second time is a palette decision that drifts, and this app has
/// already paid for that once with two ambers for one destination.
nonisolated enum CadenceCaptureAction: String, CaseIterable, Identifiable, Sendable {
    case task
    case event
    case note

    var id: String { rawValue }

    /// The destination whose vocabulary this segment borrows. Not a navigation target — nothing
    /// pushes it — only the one place its glyph and tint are already decided.
    var destination: CadenceFeatureDestination {
        switch self {
        case .task: return .allTasks
        case .event: return .calendar
        case .note: return .notes
        }
    }

    var title: String {
        switch self {
        case .task: return "Task"
        case .event: return "Event"
        case .note: return "Note"
        }
    }

    var systemImage: String { destination.systemImage }

    var tint: Color { destination.tint }
}

// MARK: - Where the segments sit, and which one a finger is over

/// The semicircle: where each segment is drawn, and which one a given offset selects.
///
/// The arc opens **upward**, because the control it surrounds is pinned to the bottom of the screen
/// and a segment drawn below it would be under the palm. Offsets are in view coordinates — `dy`
/// grows downward — so "up" is negative `dy`; the trigonometry is done in the ordinary
/// counter-clockwise convention and flipped once, here, rather than at each call site.
///
/// Selection is decided by **angle alone** once the finger is past the dead zone. There is no outer
/// selection cutoff on purpose: past `outerRadius` the finger has left the drawn arc but has not
/// escaped, and a radial menu that dropped the selection in that band would flicker the choice off
/// and on for the last 40pt before a drag begins. What ends the selection out there is the escape,
/// and that is `CadenceCapturePressResolver`'s job, not this one's.
nonisolated enum CadenceCapturePaletteGeometry: Sendable {
    static var segmentCount: Int { CadenceCaptureAction.allCases.count }

    /// The full sweep at the tab bar's placement, in degrees. A semicircle, per T-171. The corner
    /// `+` folds this into a quadrant — see `CadenceCapturePalettePlacement`.
    static var arcDegrees: Double { CadenceCapturePaletteMetricsValues.standard.arcSweepDegrees }

    static var segmentDegrees: Double { CadenceCapturePaletteMetricsValues.standard.segmentDegrees }

    /// The centre angle of segment `index`, in degrees, measured counter-clockwise from pointing
    /// right. Index 0 is the leftmost segment, so it takes the largest angle.
    static func centreDegrees(
        forSegment index: Int,
        metrics: CadenceCapturePaletteMetricsValues = .standard
    ) -> Double {
        metrics.arcEndDegrees - (Double(index) + 0.5) * metrics.segmentDegrees
    }

    /// Where segment `index`'s tile is centred, relative to the button.
    static func offset(
        forSegment index: Int,
        metrics: CadenceCapturePaletteMetricsValues = .standard
    ) -> CGSize {
        let radians = centreDegrees(forSegment: index, metrics: metrics) * .pi / 180
        return CGSize(
            width: CGFloat(cos(radians)) * metrics.layoutRadius,
            height: -CGFloat(sin(radians)) * metrics.layoutRadius
        )
    }

    /// Which segment — if any — a finger at this offset from the button has chosen.
    ///
    /// `nil` in two cases, and both mean "let go and nothing happens": inside the dead zone, which
    /// is the palette's own cancel, and anywhere below the button's horizontal, where the arc does
    /// not reach.
    static func segmentIndex(
        atOffset offset: CGSize,
        metrics: CadenceCapturePaletteMetricsValues = .standard
    ) -> Int? {
        let distance = hypot(offset.width, offset.height)
        guard distance >= metrics.innerRadius else { return nil }

        var degrees = atan2(Double(-offset.height), Double(offset.width)) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        guard degrees >= metrics.arcStartDegrees, degrees <= metrics.arcEndDegrees else { return nil }

        let index = Int(((metrics.arcEndDegrees - degrees) / metrics.segmentDegrees).rounded(.down))
        return min(max(index, 0), segmentCount - 1)
    }

    /// The same answer as the segment itself.
    static func action(
        atOffset offset: CGSize,
        metrics: CadenceCapturePaletteMetricsValues = .standard
    ) -> CadenceCaptureAction? {
        segmentIndex(atOffset: offset, metrics: metrics).map { CadenceCaptureAction.allCases[$0] }
    }
}

// MARK: - Where a released drag lands

/// Which registered drop target a point is over.
///
/// The system drag resolves this for you; a custom one has to, and the rule is worth stating once
/// rather than inside a loop. **Smallest area wins**: a task row sitting inside anything larger is
/// the more specific answer, and the caller registers frames without knowing what encloses them.
/// Ties go to the later registration, which is the one drawn on top.
nonisolated enum CadenceCaptureDropHitTest: Sendable {
    struct Candidate: Equatable, Sendable {
        let id: UUID
        let frame: CGRect

        init(id: UUID, frame: CGRect) {
            self.id = id
            self.frame = frame
        }
    }

    static func target(at point: CGPoint, among candidates: [Candidate]) -> UUID? {
        var best: Candidate?
        for candidate in candidates where candidate.frame.contains(point) {
            guard let current = best else {
                best = candidate
                continue
            }
            let area = candidate.frame.width * candidate.frame.height
            let currentArea = current.frame.width * current.frame.height
            if area <= currentArea { best = candidate }
        }
        return best?.id
    }
}
