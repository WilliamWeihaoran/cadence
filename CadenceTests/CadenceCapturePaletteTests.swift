import CoreGraphics
import Foundation
import Testing
@testable import Cadence

/// T-171: the blue `+` has to tell three touches apart, and the telling is a value.
///
/// The three cases are the specification the user wrote: a quick press then a move is a drag with no
/// palette; stillness for ~350ms opens the palette; movement inside the palette's radius slides
/// between segments while movement past it hands the touch back to the drag. Every one of those is
/// an arm of `CadenceCapturePressResolver`, so every one can be mutated and watched to fail — which
/// is the whole reason the disambiguation is not a gesture closure.
@MainActor
@Suite("Capture palette")
struct CadenceCapturePaletteTests {
    private let metrics = CadenceCapturePaletteMetricsValues.standard

    // MARK: - Case 1: quick press then move

    /// The case `UIDragInteraction` cannot serve at all: its lift needs the finger stationary for
    /// 326–349ms first, so under the system drag "press and go" produced nothing.
    @Test func aPressThatMovesBeforeTheHoldIsADragImmediately() {
        let escaped = CadenceCapturePressResolver.phase(
            afterMovingTo: metrics.dragSlop + 0.5,
            from: .pressing
        )
        #expect(escaped == .dragging)

        // And the far side of the same arm: a thumb settling on a 44pt target wobbles, and that
        // wobble must not start a drag.
        #expect(CadenceCapturePressResolver.phase(afterMovingTo: 0, from: .pressing) == .pressing)
        #expect(
            CadenceCapturePressResolver.phase(afterMovingTo: metrics.dragSlop, from: .pressing) == .pressing
        )
    }

    /// **The starvation guard.** The hold timer is armed at touch-down and cannot be un-armed
    /// synchronously with a movement SwiftUI delivers on a later runloop turn, so it *will* fire
    /// during drags. If this arm ever opened the palette, T-171's first bullet — "the palette never
    /// appears" — would be false for every fast drag.
    @Test func theHoldCannotOpenThePaletteOnTopOfADrag() {
        #expect(
            CadenceCapturePressResolver.phase(afterHoldFrom: .dragging, distance: 0) == .dragging
        )
        #expect(
            CadenceCapturePressResolver.phase(afterHoldFrom: .dragging, distance: 400) == .dragging
        )
    }

    /// A drag is terminal in the other direction too: no amount of coming back toward the button
    /// re-opens the palette under a finger already carrying a task.
    @Test func aDragNeverGoesBackToPressingOrPalette() {
        for distance in [CGFloat(0), 1, metrics.dragSlop, metrics.escapeRadius, 900] {
            #expect(CadenceCapturePressResolver.phase(afterMovingTo: distance, from: .dragging) == .dragging)
        }
    }

    // MARK: - Case 2: hold still

    @Test func holdingStillOpensThePalette() {
        #expect(CadenceCapturePressResolver.phase(afterHoldFrom: .pressing, distance: 0) == .palette)
        #expect(
            CadenceCapturePressResolver.phase(afterHoldFrom: .pressing, distance: metrics.dragSlop) == .palette
        )
    }

    /// The hold fires late on a touch that had already escaped but whose phase had not caught up —
    /// the distance is the second guard, and it is not decoration.
    @Test func theHoldRefusesAPressThatHasAlreadyTravelled() {
        #expect(
            CadenceCapturePressResolver.phase(
                afterHoldFrom: .pressing,
                distance: metrics.dragSlop + 0.5
            ) == .pressing
        )
    }

    @Test func theHoldIsTheDurationTheTicketNames() {
        #expect(CadenceCapturePaletteMetrics.holdDelay == 0.35)
    }

    // MARK: - Case 3: sliding inside the palette, and escaping it

    /// "Palette open, finger moving **within** its radius → slides between segments." Local movement
    /// belongs to the palette, all the way out to the escape radius — including the whole band past
    /// the drawn arc, which is what stops the choice flickering off in the last stretch before a
    /// drag begins.
    @Test func slidingInsideTheEscapeRadiusStaysWithThePalette() {
        for distance in [CGFloat(0), metrics.innerRadius, metrics.layoutRadius, metrics.outerRadius, metrics.escapeRadius] {
            #expect(
                CadenceCapturePressResolver.phase(afterMovingTo: distance, from: .palette) == .palette,
                "\(distance)pt from the button converted the choice into a drag"
            )
        }
    }

    @Test func travellingBeyondTheEscapeRadiusHandsTheTouchToTheDrag() {
        #expect(
            CadenceCapturePressResolver.phase(
                afterMovingTo: metrics.escapeRadius + 0.5,
                from: .palette
            ) == .dragging
        )
    }

    /// The one relationship in `CadenceCapturePaletteMetrics` that is not a taste call. T-171 states
    /// it directly: the escape radius "must be larger than the palette's own reach or segment
    /// selection will convert to a drag mid-choice".
    /// Every placement, not just the one the tab bar uses. The corner `+` moves `layoutRadius`,
    /// so this relationship is the thing that has to survive the move.
    @Test func theEscapeRadiusClearsThePalettesOwnReachAtEveryPlacement() {
        for placement in CadenceCapturePalettePlacement.allCases {
            let values = placement.metrics
            #expect(values.escapeRadius > values.outerRadius, "\(placement) can escape before it is reached")
            #expect(values.outerRadius > values.layoutRadius, "\(placement) draws its tiles past its own edge")
            #expect(values.innerRadius < values.layoutRadius)
        }
    }

    @Test func theEscapeRadiusClearsThePalettesOwnReach() {
        #expect(metrics.escapeRadius > metrics.outerRadius)
        #expect(metrics.outerRadius > metrics.layoutRadius)
        #expect(metrics.layoutRadius > metrics.innerRadius)
        #expect(metrics.innerRadius > metrics.dragSlop)
    }

    /// The escape radius is what separates sliding from dragging — not the number 172. Varying the
    /// metrics is why the resolver takes them rather than reading the statics.
    @Test func theBoundaryFollowsTheMetricsRatherThanTheShippingNumbers() {
        var tight = metrics
        tight.escapeRadius = 50
        tight.outerRadius = 40

        #expect(CadenceCapturePressResolver.phase(afterMovingTo: 45, from: .palette, metrics: tight) == .palette)
        #expect(CadenceCapturePressResolver.phase(afterMovingTo: 60, from: .palette, metrics: tight) == .dragging)
        // The same 60pt is still comfortably inside the shipping palette.
        #expect(CadenceCapturePressResolver.phase(afterMovingTo: 60, from: .palette) == .palette)
    }

    // MARK: - What lifting the finger commits to

    @Test func eachPhaseCommitsToItsOwnOutcome() {
        #expect(CadenceCapturePressResolver.outcome(atEndOf: .pressing, selection: nil) == .tap)
        #expect(CadenceCapturePressResolver.outcome(atEndOf: .dragging, selection: nil) == .drop)
        #expect(CadenceCapturePressResolver.outcome(atEndOf: .idle, selection: nil) == .none)
        #expect(CadenceCapturePressResolver.outcome(atEndOf: .palette, selection: nil) == .dismissed)
        #expect(
            CadenceCapturePressResolver.outcome(atEndOf: .palette, selection: .note) == .action(.note)
        )
    }

    /// A tap is a press that neither escaped nor waited. It has to survive, because it is the thing
    /// nearly every use of this button reaches for — and it is now synthesised rather than a
    /// `Button`'s, so it is worth stating.
    @Test func aPressThatDidNothingIsStillATap() {
        var phase = CadenceCapturePressPhase.pressing
        phase = CadenceCapturePressResolver.phase(afterMovingTo: 3, from: phase)
        #expect(CadenceCapturePressResolver.outcome(atEndOf: phase, selection: nil) == .tap)
    }

    /// A drag that started as a palette still ends as a drop, so "the palette gives up and it
    /// becomes a drag, so dropping onto a task list still works" holds end to end.
    @Test func aPaletteThatEscapedEndsAsADrop() {
        var phase = CadenceCapturePressPhase.pressing
        phase = CadenceCapturePressResolver.phase(afterHoldFrom: phase, distance: 0)
        #expect(phase == .palette)
        phase = CadenceCapturePressResolver.phase(afterMovingTo: metrics.escapeRadius + 20, from: phase)
        #expect(phase == .dragging)
        #expect(CadenceCapturePressResolver.outcome(atEndOf: phase, selection: .task) == .drop)
    }

    // MARK: - Where the segments are

    @Test func thePaletteIsASemicircleOfTheThreeThingsThisAppCaptures() {
        #expect(CadenceCaptureAction.allCases == [.task, .event, .note])
        #expect(CadenceCapturePaletteGeometry.segmentCount == 3)
        #expect(CadenceCapturePaletteGeometry.arcDegrees == 180)
        #expect(CadenceCapturePaletteGeometry.segmentDegrees == 60)
    }

    /// The load-bearing round trip: every segment's own drawn position selects that segment. A
    /// layout that disagreed with the hit test would light one tile and commit another.
    @Test func everySegmentsDrawnPositionSelectsIt() {
        for index in 0..<CadenceCapturePaletteGeometry.segmentCount {
            let offset = CadenceCapturePaletteGeometry.offset(forSegment: index)
            #expect(
                CadenceCapturePaletteGeometry.segmentIndex(atOffset: offset) == index,
                "segment \(index) is drawn where segment \(String(describing: CadenceCapturePaletteGeometry.segmentIndex(atOffset: offset))) is selected"
            )
            #expect(
                CadenceCapturePaletteGeometry.action(atOffset: offset) == CadenceCaptureAction.allCases[index]
            )
        }
    }

    /// The arc opens **upward** and runs left to right, because the control it surrounds is pinned
    /// to the bottom of the screen. `dy` grows downward in view coordinates, so every segment sits
    /// at a negative one.
    @Test func theArcOpensUpwardAndRunsLeftToRight() {
        let offsets = (0..<CadenceCapturePaletteGeometry.segmentCount)
            .map { CadenceCapturePaletteGeometry.offset(forSegment: $0) }

        #expect(offsets.allSatisfy { $0.height < 0 })
        #expect(offsets[0].width < 0, "the first segment should be to the left of the button")
        #expect(offsets[2].width > 0, "the last segment should be to the right of the button")
        #expect(abs(offsets[1].width) < 0.001, "the middle segment should be straight up")
        #expect(offsets[0].width < offsets[1].width)
        #expect(offsets[1].width < offsets[2].width)
    }

    /// The palette's own centre is its cancel: let go there and nothing happens.
    @Test func theDeadZoneSelectsNothing() {
        #expect(CadenceCapturePaletteGeometry.segmentIndex(atOffset: .zero) == nil)
        #expect(
            CadenceCapturePaletteGeometry.segmentIndex(
                atOffset: CGSize(width: 0, height: -(metrics.innerRadius - 1))
            ) == nil
        )
        // One point outside it, and the middle segment is live.
        #expect(
            CadenceCapturePaletteGeometry.segmentIndex(
                atOffset: CGSize(width: 0, height: -(metrics.innerRadius + 1))
            ) == 1
        )
    }

    /// The arc does not reach below the button — that is under the palm.
    @Test func nothingBelowTheButtonSelectsASegment() {
        for width in [CGFloat(-80), 0, 80] {
            #expect(
                CadenceCapturePaletteGeometry.segmentIndex(
                    atOffset: CGSize(width: width, height: 80)
                ) == nil,
                "an offset below the button selected a segment"
            )
        }
    }

    /// There is deliberately no outer cutoff on selection: past the drawn arc but short of the
    /// escape, the finger is still choosing. Dropping the selection out there would flicker the
    /// choice off for the last stretch of travel.
    @Test func theSelectionSurvivesPastTheDrawnReach() {
        let radians = CadenceCapturePaletteGeometry.centreDegrees(forSegment: 2) * .pi / 180
        let far = CGSize(
            width: CGFloat(cos(radians)) * (metrics.escapeRadius - 1),
            height: -CGFloat(sin(radians)) * (metrics.escapeRadius - 1)
        )
        #expect(CadenceCapturePaletteGeometry.segmentIndex(atOffset: far) == 2)
    }

    /// The extremes of the sweep still resolve, rather than falling off the end of the index maths.
    @Test func theEndsOfTheSweepClampIntoTheArc() {
        let radius = metrics.layoutRadius
        #expect(
            CadenceCapturePaletteGeometry.segmentIndex(atOffset: CGSize(width: -radius, height: 0)) == 0
        )
        #expect(
            CadenceCapturePaletteGeometry.segmentIndex(atOffset: CGSize(width: radius, height: 0))
                == CadenceCapturePaletteGeometry.segmentCount - 1
        )
    }

    // MARK: - T-282: the corner `+` has the same palette, pointing the only way it can

    /// **The placement decides the arc and nothing else.** iPhone and iPad differ in *layout* — a
    /// tab bar against a floating corner — and a size-class branch may pick a placement, never
    /// whether a control exists. So this asserts the whole value: the corner's metrics are the
    /// standard's with three fields moved, and every field that governs how the gesture *feels* is
    /// untouched.
    @Test func theTwoPlacementsDifferInTheArcAndTheRadiusItForces() {
        let bar = CadenceCapturePalettePlacement.bottomCentre.metrics
        let corner = CadenceCapturePalettePlacement.bottomTrailing.metrics

        #expect(bar == CadenceCapturePaletteMetricsValues.standard)

        // The feel of the press is identical, or the two `+`s are two controls again.
        #expect(corner.holdDelay == bar.holdDelay)
        #expect(corner.dragSlop == bar.dragSlop)
        #expect(corner.innerRadius == bar.innerRadius)

        // What a corner legitimately changes: the sweep folds into the quadrant that is on screen.
        #expect(bar.arcStartDegrees == 0)
        #expect(bar.arcSweepDegrees == 180)
        #expect(corner.arcStartDegrees == 90)
        #expect(corner.arcSweepDegrees == 90)

        // And the two rings follow the layout radius by the semicircle's own margins rather than
        // being re-chosen. Compared as differences so the claim is the relationship, not 118.
        let barOuterMargin = bar.outerRadius - bar.layoutRadius
        let cornerOuterMargin = corner.outerRadius - corner.layoutRadius
        #expect(cornerOuterMargin == barOuterMargin)

        let barEscapeMargin = bar.escapeRadius - bar.layoutRadius
        let cornerEscapeMargin = corner.escapeRadius - corner.layoutRadius
        #expect(cornerEscapeMargin == barEscapeMargin)
    }

    /// The load-bearing round trip again, at the corner. A layout that disagreed with the hit test
    /// would light one tile and commit another — and the corner is the placement where the two
    /// could drift apart, because it is the one that moved.
    @Test func everySegmentsDrawnPositionSelectsItAtTheCorner() {
        let corner = CadenceCapturePalettePlacement.bottomTrailing.metrics
        for index in 0..<CadenceCapturePaletteGeometry.segmentCount {
            let offset = CadenceCapturePaletteGeometry.offset(forSegment: index, metrics: corner)
            #expect(
                CadenceCapturePaletteGeometry.segmentIndex(atOffset: offset, metrics: corner) == index,
                "corner segment \(index) is drawn where a different segment is selected"
            )
            #expect(
                CadenceCapturePaletteGeometry.action(atOffset: offset, metrics: corner)
                    == CadenceCaptureAction.allCases[index]
            )
        }
    }

    /// **Every tile is up and to the left of the button, because that is where the screen is.** The
    /// corner `+` sits ~50pt from the trailing edge; the semicircle's rightmost segment would be
    /// drawn 80pt further right, i.e. off the display. This is the test that fails if anyone
    /// "unifies" the two placements by giving the corner the bar's sweep.
    @Test func theCornersSegmentsStayInTheQuadrantThatIsOnScreen() {
        let corner = CadenceCapturePalettePlacement.bottomTrailing.metrics
        let offsets = (0..<CadenceCapturePaletteGeometry.segmentCount)
            .map { CadenceCapturePaletteGeometry.offset(forSegment: $0, metrics: corner) }

        #expect(offsets.allSatisfy { $0.height < 0 }, "a corner segment was drawn below the button")
        #expect(offsets.allSatisfy { $0.width < 0 }, "a corner segment was drawn past the trailing edge")
        // Left to right in the same reading order as the semicircle: index 0 is still the leftmost.
        #expect(offsets[0].width < offsets[1].width)
        #expect(offsets[1].width < offsets[2].width)
    }

    /// Nothing to the right of a corner button selects a segment: the arc does not reach there, so
    /// a finger that drifts that way is in the same "let go and nothing happens" state as the dead
    /// zone. The bar's palette, which does have segments out there, still selects one.
    @Test func nothingToTheRightOfACornerButtonSelectsASegment() {
        let corner = CadenceCapturePalettePlacement.bottomTrailing.metrics
        let toTheRight = CGSize(width: corner.layoutRadius, height: -10)

        #expect(CadenceCapturePaletteGeometry.segmentIndex(atOffset: toTheRight, metrics: corner) == nil)
        #expect(CadenceCapturePaletteGeometry.segmentIndex(atOffset: toTheRight, metrics: metrics) != nil)
    }

    /// The reason the corner's `layoutRadius` is not simply the semicircle's: three tiles in 90°
    /// instead of 180° sit half as far apart, and at 92pt they would visibly overlap. Asserted
    /// against the tile's own published width so neither number can move alone.
    @Test func noTwoSegmentTilesOverlapAtEitherPlacement() {
        for placement in CadenceCapturePalettePlacement.allCases {
            let values = placement.metrics
            let first = CadenceCapturePaletteGeometry.offset(forSegment: 0, metrics: values)
            let second = CadenceCapturePaletteGeometry.offset(forSegment: 1, metrics: values)
            let spacing = hypot(first.width - second.width, first.height - second.height)
            let tile = CadenceCapturePaletteMetrics.segmentTileDiameter
            #expect(spacing >= tile, "\(placement) draws overlapping tiles")
        }
    }

    /// A drag off the corner `+` that fizzles over blank space still opens the composer that
    /// button's page would have opened — it does not fall back to a bare Inbox one. The tab bar's
    /// `+` is unscoped, so for it the same rule resolves to the same empty seed it always had.
    @Test func aCaptureDragThatLandsOnNothingKeepsTheButtonsOwnSeed() {
        let areaID = UUID()
        let base = CadenceTaskComposerSeed(doDateKey: "2026-08-20", container: .area(areaID))

        for key in [String?.none, ""] {
            let seed = CadenceTaskDropSupport.seed(forDropKey: key, todayKey: "2026-08-17", base: base)
            #expect(seed.container == .area(areaID))
            #expect(seed.doDateKey == "2026-08-20")
        }

        let unscoped = CadenceTaskDropSupport.seed(
            forDropKey: nil,
            todayKey: "2026-08-17",
            base: CadenceTaskComposerSeed()
        )
        #expect(unscoped.container == .inbox)
        #expect(unscoped.doDateKey.isEmpty)
    }

    /// And a drag that *does* land takes the placement it landed on, base or no base. The row is
    /// the more specific answer; the button's own seed is only the fallback.
    @Test func aCaptureDragThatLandsSomewhereTakesThePlacementOverTheBase() {
        let landedOn = UUID()
        let base = CadenceTaskComposerSeed(container: .area(UUID()))

        let seed = CadenceTaskDropSupport.seed(
            forDropKey: "list:a_\(landedOn.uuidString)|section:Backlog|date:today",
            todayKey: "2026-08-17",
            base: base
        )

        #expect(seed.container == .area(landedOn))
        #expect(seed.sectionName == "Backlog")
        #expect(seed.doDateKey == "2026-08-17")
    }

    // MARK: - The segments borrow their vocabulary

    /// Neither the glyph nor the tint is spelled here. `CadenceFeatureDestination.defaultColorHex`
    /// documents why at length — this app has already paid once for a palette decision written a
    /// second time, in two ambers for one destination.
    @Test func theSegmentsBorrowGlyphAndTintFromTheirDestination() {
        #expect(CadenceCaptureAction.task.destination == .allTasks)
        #expect(CadenceCaptureAction.event.destination == .calendar)
        #expect(CadenceCaptureAction.note.destination == .notes)

        for action in CadenceCaptureAction.allCases {
            #expect(action.systemImage == action.destination.systemImage)
            #expect(action.tint == action.destination.tint)
        }

        // Distinct destinations, or two segments would be the same colour and the same glyph.
        let destinations = CadenceCaptureAction.allCases.map(\.destination)
        #expect(Set(destinations).count == destinations.count)
    }

    @Test func thePaletteSpellsNoColourOfItsOwn() throws {
        let code = try strippingComments(sourceFile("Cadence/Shared/CadenceCapturePaletteSupport.swift"))
        #expect(code.contains("CadenceCapturePressResolver"), "scanned the wrong file")
        #expect(code.contains("Color(hex:") == false)
        #expect(code.contains(".white") == false)
        #expect(code.contains(".black") == false)
    }

    // MARK: - Where a released drag lands

    @Test func theSmallestContainingFrameWinsAHitTest() {
        let outer = UUID()
        let inner = UUID()
        let candidates = [
            CadenceCaptureDropHitTest.Candidate(id: outer, frame: CGRect(x: 0, y: 0, width: 400, height: 400)),
            CadenceCaptureDropHitTest.Candidate(id: inner, frame: CGRect(x: 10, y: 10, width: 100, height: 44))
        ]
        #expect(CadenceCaptureDropHitTest.target(at: CGPoint(x: 40, y: 30), among: candidates) == inner)
        #expect(CadenceCaptureDropHitTest.target(at: CGPoint(x: 300, y: 300), among: candidates) == outer)
    }

    @Test func aPointOverNothingHitsNothing() {
        let candidates = [
            CadenceCaptureDropHitTest.Candidate(id: UUID(), frame: CGRect(x: 0, y: 0, width: 50, height: 50))
        ]
        #expect(CadenceCaptureDropHitTest.target(at: CGPoint(x: 200, y: 200), among: candidates) == nil)
        #expect(CadenceCaptureDropHitTest.target(at: .zero, among: []) == nil)
    }

    /// Equal-sized overlapping targets go to the later registration, which is the one drawn on top.
    @Test func aTieGoesToTheLaterCandidate() {
        let first = UUID()
        let second = UUID()
        let frame = CGRect(x: 0, y: 0, width: 100, height: 44)
        let candidates = [
            CadenceCaptureDropHitTest.Candidate(id: first, frame: frame),
            CadenceCaptureDropHitTest.Candidate(id: second, frame: frame)
        ]
        #expect(CadenceCaptureDropHitTest.target(at: CGPoint(x: 5, y: 5), among: candidates) == second)
    }

    // MARK: - The wiring

    /// T-161's rule: a test that passes when the call site is reverted has not pinned the
    /// consolidation. The centre `+` used `.iOSNewTaskDragSource()` — a `UIDragInteraction` — and
    /// that is precisely the mechanism T-171 cannot be built on, so its absence here is the fix.
    @Test func theCompactCaptureButtonNoLongerCarriesTheSystemDrag() throws {
        let shell = try strippingComments(sourceFile("Cadence/iOS/iOSCompactTabShell.swift"))
        let button = try cadenceFunctionBody("private struct iOSCompactCaptureButton: View", in: shell)

        #expect(button.contains("iOSCaptureRadialMenuButton("))
        #expect(button.contains("iOSNewTaskDragSource") == false)
    }

    /// The centre control is not a tab, and nothing in it may learn about selection — the three
    /// absences that stop it ever rendering a selected state.
    @Test func theCentreControlStillKnowsNothingAboutTabSelection() throws {
        let shell = try strippingComments(sourceFile("Cadence/iOS/iOSCompactTabShell.swift"))
        let button = try cadenceFunctionBody("private struct iOSCompactCaptureButton: View", in: shell)

        #expect(button.contains("isSelected") == false)
        #expect(button.contains("CadenceCompactTab") == false)
        #expect(button.contains("selection") == false)
        // And the shell still has exactly four tabs to choose between.
        #expect(CadenceCompactTab.allCases.count == 4)
    }

    // MARK: - T-282: the corner `+` is wired to the same gesture and the same composers

    /// **The capability, at the call site.** Before T-282 this button was
    /// `iOSCircularAddButton { isPresented = true }` plus `.iOSNewTaskDragSource()` — a tap into
    /// one sheet and a system drag, with no palette at any width. It now renders the same
    /// `iOSCaptureRadialMenuButton` the tab bar does. Scoped to the modifier's own `body`, not to
    /// the file and not to the struct: a matching call anywhere else in either would pass a looser
    /// scan while the corner button still did nothing.
    @Test func theCornerButtonCarriesTheGestureAndNotATapIntoASheet() throws {
        let file = try strippingComments(sourceFile("Cadence/iOS/iOSFloatingCreateTaskButton.swift"))
        let layer = try cadenceFunctionBody(
            "private struct iOSFloatingCreateTaskLayer: ViewModifier",
            in: file
        )
        let body = try cadenceFunctionBody("func body(content: Content) -> some View", in: layer)

        #expect(body.contains("iOSCaptureRadialMenuButton("))
        #expect(body.contains(".iOSCaptureHost("))
        // The page's own seed still reaches the composer a tap opens.
        #expect(body.contains("baseSeed: seed"))

        // And the three things it replaced are gone rather than left beside it.
        #expect(body.contains("iOSNewTaskDragSource") == false)
        #expect(body.contains(".sheet(") == false)
        #expect(body.contains("isPresented") == false)
    }

    /// Each placement says which one it is, and the two say different things — the arc is the only
    /// thing that may differ, so it has to actually differ.
    @Test func eachPlacementDeclaresItsOwnArc() throws {
        let corner = try strippingComments(sourceFile("Cadence/iOS/iOSFloatingCreateTaskButton.swift"))
        let layer = try cadenceFunctionBody(
            "private struct iOSFloatingCreateTaskLayer: ViewModifier",
            in: corner
        )
        #expect(layer.contains("iOSCaptureInteraction(placement: .bottomTrailing)"))

        let shell = try strippingComments(sourceFile("Cadence/iOS/iOSCompactTabShell.swift"))
        let root = try cadenceFunctionBody("struct iOSCompactRootShell: View", in: shell)
        #expect(root.contains("iOSCaptureInteraction(placement: .bottomCentre)"))
    }

    /// **The tab bar's tap stays unscoped and the page's does not, and that is a difference in what
    /// the two buttons *know*, not in what they can do.** You press the bar's `+` from any tab and
    /// file the task afterwards; a corner `+` is already standing on a list or on today.
    @Test func onlyThePageButtonSeedsItsTap() throws {
        let shell = try strippingComments(sourceFile("Cadence/iOS/iOSCompactTabShell.swift"))
        let button = try cadenceFunctionBody("private struct iOSCompactCaptureButton: View", in: shell)

        #expect(button.contains("iOSCaptureRadialMenuButton("))
        #expect(button.contains("baseSeed") == false)
    }

    /// **One routing for the three composers.** The shell used to own `handle(_:)`, a `sheet(item:)`
    /// over the three request kinds and a `fullScreenCover` for the note it had to create first;
    /// giving the iPad the same palette by copying that block is exactly the near-copy this repo
    /// keeps paying for. It moved into `iOSCaptureHostModifier`, so the shell now names none of it.
    @Test func neitherPlacementSpellsTheComposersItself() throws {
        let shell = try strippingComments(sourceFile("Cadence/iOS/iOSCompactTabShell.swift"))
        #expect(shell.contains(".iOSCaptureHost("))
        for spelling in ["iOSCreateTaskSheet(", "iOSCalendarQuickCreateSheet(", "iOSNoteEditorCover(", "NoteMigrationService"] {
            #expect(shell.contains(spelling) == false, "the compact shell still spells \(spelling)")
        }

        let corner = try strippingComments(sourceFile("Cadence/iOS/iOSFloatingCreateTaskButton.swift"))
        #expect(corner.contains(".iOSCaptureHost("))
        for spelling in ["iOSCreateTaskSheet(", "iOSCalendarQuickCreateSheet(", "iOSNoteEditorCover(", "NoteMigrationService"] {
            #expect(corner.contains(spelling) == false, "the corner button still spells \(spelling)")
        }

        // And there is one implementation of each behind them both.
        let host = try strippingComments(sourceFile("Cadence/iOS/iOSCaptureRadialMenu.swift"))
        for spelling in ["iOSCreateTaskSheet(", "iOSCalendarQuickCreateSheet(", "iOSNoteEditorCover(", "NoteMigrationService"] {
            #expect(host.components(separatedBy: spelling).count - 1 == 1, "\(spelling) is not stated once")
        }
    }

    /// The host is applied once per placement and nowhere else — two `+`s, two hosts. A third would
    /// be a third capture button nobody decided on.
    @Test func theCaptureHostIsAppliedOncePerPlacement() throws {
        var perFile: [String: Int] = [:]
        for file in try iOSSourceFiles() {
            let code = try strippingComments(String(contentsOf: file, encoding: .utf8))
            let count = code.components(separatedBy: ".iOSCaptureHost(").count - 1
            if count > 0 { perFile[file.lastPathComponent] = count }
        }

        #expect(perFile == [
            "iOSCompactTabShell.swift": 1,
            "iOSFloatingCreateTaskButton.swift": 1
        ])
    }

    /// The palette is installed once, above every tab, for the reason `iOSTaskInspectorHost()` is:
    /// it has to draw outside the 46pt bar row the button lives in. Since T-282 that one install is
    /// inside `iOSCaptureHostModifier`, which is what both placements apply — so the count is still
    /// one, and now it is one *implementation* rather than one call site that happened to be alone.
    @Test func thePaletteLayerIsInstalledExactlyOnce() throws {
        let files = try iOSSourceFiles()
        #expect(files.count > 50, "the iOS folder scan found almost nothing")

        var installs = 0
        for file in files {
            let code = try strippingComments(String(contentsOf: file, encoding: .utf8))
            installs += code.components(separatedBy: ".iOSCaptureRadialMenuLayer(").count - 1
        }
        #expect(installs == 1)
    }

    /// A tab kept alive at zero opacity still lays its rows out. The system drag never noticed;
    /// a custom one hit-tests published frames, so the shell has to say which surface is reachable.
    @Test func hiddenTabsAreNotDropTargets() throws {
        let shell = try strippingComments(sourceFile("Cadence/iOS/iOSCompactTabShell.swift"))
        let stack = try cadenceFunctionBody(
            "private func stack(for tab: CadenceCompactTab) -> some View",
            in: shell
        )
        #expect(stack.contains("iOSNewTaskDropTargetsAreLive"))
        #expect(stack.contains("tab == selectedTab"))
    }

    /// The gesture asks the resolver; it does not re-decide. Both live events route through it, and
    /// a second body for either is what the value exists to prevent.
    @Test func theGestureDefersToTheSharedResolver() throws {
        let source = try strippingComments(sourceFile("Cadence/iOS/iOSCaptureRadialMenu.swift"))

        let moved = try cadenceFunctionBody("func moved(to location: CGPoint)", in: source)
        #expect(moved.contains("CadenceCapturePressResolver.phase(afterMovingTo:"))

        let armed = try cadenceFunctionBody("private func armHold()", in: source)
        // The call wraps over four lines, so the label is checked beside the callee rather than
        // glued to it — pinning the whole one-line spelling would only pin the formatter.
        #expect(armed.contains("CadenceCapturePressResolver.phase("))
        #expect(armed.contains("afterHoldFrom: self.phase"))
        // The delay is read from the placement's own metrics rather than the static, so a
        // placement that ever needed a different hold could not get one by accident here.
        #expect(armed.contains("let delay = metrics.holdDelay"))
        #expect(armed.contains(".seconds(delay)"))
        #expect(armed.contains("metrics: self.metrics"))

        let moving = try cadenceFunctionBody("func moved(to location: CGPoint)", in: source)
        #expect(moving.contains("metrics: metrics"))

        let ended = try cadenceFunctionBody("func ended() -> CadenceCapturePressOutcome", in: source)
        #expect(ended.contains("CadenceCapturePressResolver.outcome(atEndOf:"))
    }
}

// MARK: - Source access

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func iOSSourceFiles() throws -> [URL] {
    let root = repositoryRoot().appendingPathComponent("Cadence/iOS")
    return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "swift" }
}

private func sourceFile(_ relativePath: String) throws -> String {
    try String(contentsOf: repositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
}

/// Blanks out `//` line comments and `/* */` block comments so the assertions read code rather than
/// prose. Crude on purpose: a `//` inside a string literal is blanked too, which can only make
/// these checks stricter about what counts as a comment, never looser about live code.
private func strippingComments(_ source: String) throws -> String {
    var result = source
    for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            result.replaceSubrange(range, with: String(repeating: " ", count: result.distance(from: range.lowerBound, to: range.upperBound)))
        }
    }
    return result
}
