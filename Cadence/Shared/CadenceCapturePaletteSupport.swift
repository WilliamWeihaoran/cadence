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

/// How a region-sized drop target turns *where in it* the finger came down into the minute it
/// seeds.
///
/// Every other drop target answers the same thing wherever you release inside it — a task row's
/// list does not change halfway down the row. A calendar day column is the exception the vocabulary
/// had no room for: its whole vertical axis **is** a time, so one registration has to be able to
/// give a different answer per pixel. Carrying the geometry as a value rather than a closure is
/// what keeps the answer testable off-device and identical to the one the column's own tap gives —
/// both go through `CadenceScheduleSupport.timelineMinute(atY:…)`.
///
/// `offsetY` is measured from the **top of the registered frame**, which is what the registry can
/// compute from a global finger position without the column being asked anything.
struct CadenceCaptureDropSlotRule: Equatable, Sendable {
    var hourHeight: CGFloat
    var snapMinutes: Int
    var startHour: Int
    var endHour: Int

    init(
        hourHeight: CGFloat,
        snapMinutes: Int = 15,
        startHour: Int = CadenceScheduleSupport.calendarStartHour,
        endHour: Int = CadenceScheduleSupport.calendarEndHour
    ) {
        self.hourHeight = hourHeight
        self.snapMinutes = snapMinutes
        self.startHour = startHour
        self.endHour = endHour
    }

    func minute(atOffsetY offsetY: CGFloat) -> Int {
        CadenceScheduleSupport.timelineMinute(
            atY: offsetY,
            hourHeight: hourHeight,
            snapMinutes: snapMinutes,
            startHour: startHour,
            endHour: endHour
        )
    }

    /// Where the ghost for `minute` sits inside the frame — the inverse, so the block a drop draws
    /// and the minute it seeds cannot drift apart.
    func offsetY(forMinute minute: Int) -> CGFloat {
        CGFloat(minute - startHour * 60) / 60 * hourHeight
    }
}

// MARK: - Where every drop target is

/// Where every create-task drop target is on screen, and what it would seed.
///
/// The system drag resolves its own hit-testing; a custom one cannot, so the targets publish
/// themselves here and `iOSNewTaskDropFrameRegistry` holds the one live instance.
///
/// **The bookkeeping lives in Shared rather than beside that registry on purpose.** What it has to
/// get right is not a layout question and leaves no trace on a screenshot: it is which of a
/// target's three published facts survive the view going away, and the answer is the difference
/// between every drop on a surface inheriting what it landed on and every drop on it silently
/// inheriting nothing — see `retire(_:)`. `Cadence/iOS/` is behind `#if os(iOS)` while
/// `CadenceTests` builds on macOS, so a state machine kept in there can only be pinned by a source
/// scan, and a source scan is exactly what T-3008 walked past.
struct CadenceNewTaskDropFrameStore {
    struct Placement: Equatable {
        var dropKey: String
        var listName: String
        /// Non-nil only where the vertical position inside the frame is itself part of the answer —
        /// a calendar day column, whose axis is a time. See `CadenceCaptureDropSlotRule`.
        var slot: CadenceCaptureDropSlotRule?

        init(dropKey: String, listName: String, slot: CadenceCaptureDropSlotRule? = nil) {
            self.dropKey = dropKey
            self.listName = listName
            self.slot = slot
        }
    }

    private var frames: [UUID: CGRect] = [:]
    /// The global Y of the **whole** target, before the enclosing scroll view clipped `frames`.
    /// Only a slotted target reads it, and only it could: a minute measured from a clipped top
    /// would slide by a whole scroll offset. See `setFrame(_:slotOriginY:for:)`.
    private var slotOrigins: [UUID: CGFloat] = [:]
    private var placements: [UUID: Placement] = [:]
    /// Ids whose surface is currently the one on screen. See `iOSNewTaskDropTargetsAreLive`.
    private var live: Set<UUID> = []
    /// Registration order, so `CadenceCaptureDropHitTest`'s tie-break resolves to the later one.
    private var order: [UUID] = []

    init() {}

    /// `frame` is what a finger can reach — clipped to the scroll view showing it — and
    /// `slotOriginY` is the top of the target itself. They differ only inside a scroller, and only
    /// a slotted target cares that they do.
    mutating func setFrame(_ frame: CGRect, slotOriginY: CGFloat, for id: UUID) {
        if frames[id] == nil { order.append(id) }
        frames[id] = frame
        slotOrigins[id] = slotOriginY
    }

    mutating func setPlacement(
        dropKey: String,
        listName: String,
        slot: CadenceCaptureDropSlotRule? = nil,
        for id: UUID
    ) {
        placements[id] = Placement(dropKey: dropKey, listName: listName, slot: slot)
    }

    mutating func setLive(_ isLive: Bool, for id: UUID) {
        if isLive { live.insert(id) } else { live.remove(id) }
    }

    /// The target's view went away — which is **not** the same as the target being gone, and
    /// `onDisappear` cannot tell you which of the two happened.
    ///
    /// **Why this clears liveness instead of deleting the entry (T-3008).** Pushing a detail page
    /// and popping back sends `onDisappear` to the whole index subtree, and the restored copy then
    /// re-runs its body: `setPlacement` and `setLive` fire again, because both are
    /// `.onChange(…, initial: true)`. **`setFrame` does not**, because `onGeometryChange` reports a
    /// geometry *change* and nothing moved — the rows are exactly where they were. So a teardown
    /// that deleted the frame left a target whose key and liveness looked perfectly healthy and
    /// which `candidates()` could never return again. One push-and-back emptied every drop target
    /// on the surface, with no error and no visual difference: the `+` still opened a composer, it
    /// just stopped inheriting the list, group or day it had been dropped on.
    ///
    /// This is the argument `iOSNewTaskDropTargetsAreLive` already makes one level up — a surface
    /// coming back produces no geometry change, so anything a target can only publish *on* a
    /// geometry change must survive its absence. Liveness is the one of the three facts the
    /// restored copy republishes by itself, so liveness is the one this is allowed to take away.
    ///
    /// **The cost, taken deliberately — and still paid today.** A view that really was destroyed
    /// leaves its frame and placement behind for the life of the process. They are unreachable —
    /// `candidates()` passes over anything not in `live`, and nothing but a restored view sets that
    /// again — so the price is memory, while deleting them prices correctness.
    ///
    /// `destroy(_:)` below is T-3011's remedy, and it is **not wired yet**: no production target
    /// owns a `CadenceNewTaskDropRegistrationLifetime`, so nothing calls it. When one does, only
    /// final destruction may call it; a count or time limit cannot tell destruction from a push.
    mutating func retire(_ id: UUID) {
        live.remove(id)
    }

    /// Final destruction, never a visibility event. Remove every retained fact and its tie-break
    /// position so neither memory nor the per-drag candidate walk grows with destroyed targets.
    mutating func destroy(_ id: UUID) {
        guard frames[id] != nil || placements[id] != nil || live.contains(id) else { return }
        live.remove(id)
        frames.removeValue(forKey: id)
        slotOrigins.removeValue(forKey: id)
        placements.removeValue(forKey: id)
        order.removeAll { $0 == id }
    }

    var retainedFrameCount: Int { frames.count }

    /// **A target with nothing to hand over is not a target.** The empty key is how a call site
    /// says "not today" about a destination it still draws — the calendar timeline's columns are
    /// the case: the same view is a live target on a future day and no target at all on a day that
    /// has gone by, and re-registering it under a new id every time the grid scrolls would be a
    /// view-identity change to express a fact about a date. It is the same rule
    /// `CadenceTaskDropSupport.dropKey(forGroup:)` states with `nil`, applied one layer down.
    func candidates() -> [CadenceCaptureDropHitTest.Candidate] {
        order.compactMap { id in
            guard live.contains(id),
                  let frame = frames[id],
                  !frame.isNull,
                  let placement = placements[id],
                  !placement.dropKey.isEmpty
            else { return nil }
            return CadenceCaptureDropHitTest.Candidate(id: id, frame: frame)
        }
    }

    func placement(for id: UUID) -> Placement? { placements[id] }

    /// The minute `point` picks out inside a slotted target, or `nil` when the target has no slot
    /// rule. The offset is taken from the registered frame, which is the only thing here that knows
    /// where the column starts on screen — so no view has to be asked anything at drop time.
    func slotMinute(for id: UUID, at point: CGPoint) -> Int? {
        guard let rule = placements[id]?.slot, let originY = slotOrigins[id] else { return nil }
        return rule.minute(atOffsetY: point.y - originY)
    }
}

/// Stored in a drop target's `@State`, not in its transient view value. SwiftUI copies retaining
/// the same state share this owner, so an old copy disappearing cannot destroy a restored frame.
@MainActor
final class CadenceNewTaskDropRegistrationLifetime {
    private let id: UUID
    private let onDestroy: @MainActor @Sendable (UUID) -> Void
    private var isActivated = false

    init(id: UUID = UUID(), onDestroy: @escaping @MainActor @Sendable (UUID) -> Void) {
        self.id = id
        self.onDestroy = onDestroy
    }

    func activate() -> UUID {
        isActivated = true
        return id
    }

    deinit {
        // State's unadopted initial values never published an entry. Do not enqueue work for them.
        guard isActivated else { return }
        let id = id
        let onDestroy = onDestroy
        Task { @MainActor in onDestroy(id) }
    }
}

// MARK: - What a finished press seeds

/// What a finished press actually makes.
///
/// **The `+` made one kind of thing until the sidebar became a destination**, so the gesture could
/// hand back a seed and the host could present one composer. A context group in the iPad sidebar is
/// not a place a task goes — it is a place a *list* goes — and the owner's rule for the whole
/// feature is that the `+` creates whatever the region it was dropped on implies. That makes "what
/// is being created" a second answer the drop has to carry, and it is carried as a value here
/// rather than as a branch at the button, so the one place that decides is testable without a view.
///
/// There is deliberately no `.note` case: a note is a *palette* choice, which the button already
/// routes by segment and which no drop target can name. This enum is what a **destination**
/// implies, and the three destinations that imply anything are a task surface, the iPad sidebar's
/// context groups, and a calendar day column.
///
/// **`.event` is here because a calendar timeline is not a place work goes — it is a place time
/// goes** (T-2065). The owner's rule for the whole feature is that the `+` creates whatever the
/// region it was dropped on implies, and a day column at 2:15 PM implies a 2:15 PM commitment, not
/// a task that happens to carry one. It is the same reading that made a sidebar context group
/// produce a list rather than a task filed into one.
enum CadenceCaptureCreation: Equatable {
    case task(CadenceTaskComposerSeed)
    /// A list in the named group, or — `nil` — in none. See `CadenceTaskDropSupport.NewListDrop`.
    case list(contextID: UUID?)
    /// An event on the named day, starting at the minute the drop resolved — or, with no minute,
    /// on that day at the composer's own default hour. See `CadenceTaskDropSupport.NewEventDrop`.
    case event(dateKey: String, startMinute: Int?)
}

/// The composer seed a finished capture press commits to.
///
/// **T-337: context comes from where you drop it, not from where you started.** A tap is just a
/// task. A palette segment is just a task, an event or a note. Only a drag that came down on a
/// registered target inherits anything, and a drag that came down on nothing is a tap that
/// travelled. So the drop key is the *only* input that can put a list, a section or a date into a
/// new task, and this function is where that is said once.
///
/// It takes the outcome rather than only the key so the rule is a value the wrong answer can be
/// mutated into: a `.tap` arm that consulted `dropKey` would compile, would look reasonable, and
/// would restore exactly the page-seeding this ticket removed. That reversal is the one worth a
/// failing test — see `T-282`, which seeded a page's corner `+` for reasons this supersedes.
/// Main-actor isolated, unlike everything above it in this file, because it reaches
/// `CadenceTaskDropSupport` — and a seed is only ever built while presenting a composer, which is
/// main-actor work anyway. The gesture values above stay `nonisolated` because they are pure
/// geometry and arithmetic with nothing to reach.
enum CadenceCaptureSeedResolver {
    static func seed(
        for outcome: CadenceCapturePressOutcome,
        dropKey: String?,
        todayKey: String
    ) -> CadenceTaskComposerSeed {
        switch outcome {
        case .drop:
            // `base` is empty because the button has nothing of its own to contribute any more —
            // which is also what makes a fizzled drop identical to a tap rather than a fallback to
            // the page. See `CadenceTaskDropSupport.seed(forDropKey:todayKey:base:)`.
            return CadenceTaskDropSupport.seed(
                forDropKey: dropKey,
                todayKey: todayKey,
                base: CadenceTaskComposerSeed()
            )
        case .tap, .action, .dismissed, .none:
            return CadenceTaskComposerSeed()
        }
    }

    /// What this press commits to: a seeded task, a new list in the group a drop landed on, or an
    /// event at the minute a calendar day column resolved.
    ///
    /// **Only a `.drop` can ask for a list or an event.** A tap and a palette segment name the
    /// thing being created and nothing about where it goes — that is T-337's rule, that the button
    /// contributes nothing and the target contributes everything — so a key reaching this function
    /// by any other route is a key no destination produced, and it is ignored rather than
    /// honoured. The gate is written once, around both branches, so a third destination kind
    /// cannot be added outside it by accident.
    static func creation(
        for outcome: CadenceCapturePressOutcome,
        dropKey: String?,
        todayKey: String
    ) -> CadenceCaptureCreation {
        if case .drop = outcome, let dropKey {
            if let newList = CadenceTaskDropSupport.newListDrop(forDropKey: dropKey) {
                return .list(contextID: newList.contextID)
            }
            if let newEvent = CadenceTaskDropSupport.newEventDrop(forDropKey: dropKey, todayKey: todayKey) {
                return .event(dateKey: newEvent.dateKey, startMinute: newEvent.startMinute)
            }
        }
        return .task(seed(for: outcome, dropKey: dropKey, todayKey: todayKey))
    }
}
