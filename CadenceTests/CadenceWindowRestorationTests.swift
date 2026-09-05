import CoreGraphics
import Testing
@testable import Cadence

/// **T-1038.** Measured 2026-09-05: launching against the user's own `UserDefaults` restored the
/// main window at `X = -2899`, entirely off every connected display — invisible, though still
/// composited and screenshot-able, which reads to a user as "the app did not open." AppKit's own
/// window-restoration path runs before `CadenceAppDelegate.applicationDidFinishLaunching` returns,
/// with no seam of ours in it, so the fix is applied afterward: clamp any window whose restored
/// frame does not overlap a connected screen back onto one.
///
/// `CadenceWindowRestorationSupport.clampedFrame(_:toFit:)` is the pure half — plain `CGRect`s, no
/// `NSScreen`/`NSWindow` — and is what every test below exercises. The one AppKit-facing call,
/// `clampWindowsOntoConnectedScreens`, is pinned only by a source scan: it has no seam to unit test
/// short of standing up real `NSScreen`s, which a test host cannot do.
#if os(macOS)
struct CadenceWindowRestorationTests {

    // MARK: - Already reachable frames are left alone

    @Test func aFrameFullyInsideItsScreenIsUnchanged() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let frame = CGRect(x: 100, y: 100, width: 900, height: 600)
        #expect(CadenceWindowRestorationSupport.clampedFrame(frame, toFit: [screen]) == frame)
    }

    @Test func aFrameStraddlingTheEdgeOfItsScreenIsUnchanged() {
        // Pokes 40pt past the trailing edge — reachable, and not the defect this ticket is about.
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let frame = CGRect(x: 1472, y: 100, width: 900, height: 600)
        #expect(frame.intersects(screen))
        #expect(CadenceWindowRestorationSupport.clampedFrame(frame, toFit: [screen]) == frame)
    }

    @Test func aFrameOverlappingOnlyTheSecondScreenIsUnchanged() {
        let primary = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let secondary = CGRect(x: 1512, y: 0, width: 1512, height: 982)
        let frame = CGRect(x: 1600, y: 100, width: 900, height: 600)
        #expect(CadenceWindowRestorationSupport.clampedFrame(frame, toFit: [primary, secondary]) == frame)
    }

    @Test func emptyScreenListLeavesTheFrameUntouched() {
        let frame = CGRect(x: -2899, y: 100, width: 900, height: 600)
        #expect(CadenceWindowRestorationSupport.clampedFrame(frame, toFit: []) == frame)
    }

    // MARK: - The measured defect: a frame with zero connected screens under it

    @Test func theMeasuredOffScreenFrameIsRepositionedOntoTheFirstScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        // The ticket's own measurement.
        let offScreen = CGRect(x: -2899, y: 200, width: 1200, height: 800)
        #expect(!offScreen.intersects(screen))

        let clamped = CadenceWindowRestorationSupport.clampedFrame(offScreen, toFit: [screen])

        #expect(clamped.intersects(screen))
        // Size is preserved when it already fits.
        #expect(clamped.width == 1200)
        #expect(clamped.height == 800)
        // Centered on the screen, not just nudged to its edge.
        #expect(clamped.midX == screen.midX)
        #expect(clamped.midY == screen.midY)
    }

    @Test func aFrameOffEveryScreenChoosesTheFirstScreenOfSeveral() {
        let first = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let second = CGRect(x: -3000, y: 0, width: 1200, height: 800)
        let offScreen = CGRect(x: 9000, y: 9000, width: 900, height: 600)
        #expect(!offScreen.intersects(first))
        #expect(!offScreen.intersects(second))

        let clamped = CadenceWindowRestorationSupport.clampedFrame(offScreen, toFit: [first, second])
        #expect(clamped.midX == first.midX)
        #expect(clamped.midY == first.midY)
    }

    @Test func aFrameLargerThanTheScreenIsClampedDownToFit() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 700)
        let offScreen = CGRect(x: -5000, y: 0, width: 1400, height: 900)

        let clamped = CadenceWindowRestorationSupport.clampedFrame(offScreen, toFit: [screen])

        #expect(clamped.width == 1000)
        #expect(clamped.height == 700)
        #expect(clamped == screen)
    }

    // MARK: - Wiring: the one AppKit-facing call site

    /// `clampWindowsOntoConnectedScreens` has no seam a unit test can drive without a real
    /// `NSScreen`, so its wiring into launch is pinned by source scan instead: exactly one call, in
    /// `applicationDidFinishLaunching`, reading the live window list and the live screen list
    /// rather than anything hardcoded.
    @Test func applicationDidFinishLaunchingCallsTheClampExactlyOnce() throws {
        let source = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Services/CadenceAppDelegate.swift")
        )
        #expect(
            CadenceSourceScan.matchCount(
                "CadenceWindowRestorationSupport\\.clampWindowsOntoConnectedScreens\\(",
                in: source
            ) == 1
        )

        let launch = try #require(
            CadenceSourceScan.functionBody(named: "applicationDidFinishLaunching", in: source),
            "applicationDidFinishLaunching is gone from CadenceAppDelegate.swift"
        )
        #expect(launch.contains("CadenceWindowRestorationSupport.clampWindowsOntoConnectedScreens("))
        #expect(launch.contains("NSApplication.shared.windows"))
        #expect(launch.contains("NSScreen.screens"))
    }
}
#endif
