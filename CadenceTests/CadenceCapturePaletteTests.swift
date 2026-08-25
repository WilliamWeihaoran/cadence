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

    /// The palette is installed once, above every tab, for the reason `iOSTaskInspectorHost()` is:
    /// it has to draw outside the 46pt bar row the button lives in.
    @Test func thePaletteLayerIsInstalledExactlyOnce() throws {
        let root = repositoryRoot().appendingPathComponent("Cadence/iOS")
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
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
        #expect(armed.contains("CadenceCapturePressResolver.phase(afterHoldFrom:"))
        #expect(armed.contains("CadenceCapturePaletteMetrics.holdDelay"))

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
