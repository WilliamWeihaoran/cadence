#if os(macOS)
import AppKit
import Foundation

/// T-1038. AppKit restores a `WindowGroup`'s window frame from the user's own defaults before
/// `applicationDidFinishLaunching` returns, with no seam of ours in that path — so a frame saved
/// against a display that is no longer connected (docking/undocking, an external monitor unplugged
/// while the app was closed) comes back exactly as saved. Measured 2026-09-05: a debug build
/// against the user's own `UserDefaults` restored the main window at `X = -2899`, entirely off
/// every connected display. The window is still composited (it can be screenshotted), it is just
/// nowhere a person can see or reach it — indistinguishable, to the user, from the app failing to
/// open at all.
///
/// The pure geometry lives in `clampedFrame(_:toFit:)` so it can be asserted on without an
/// `NSScreen`; `clampWindowsOntoConnectedScreens` is the one AppKit-facing call site, invoked from
/// `CadenceAppDelegate.applicationDidFinishLaunching`.
enum CadenceWindowRestorationSupport {
    /// Returns `frame` unchanged if it already overlaps at least one screen in `screens`.
    /// Otherwise repositions it onto the first screen (its size preserved, unless the screen is
    /// smaller than the frame, in which case size is clamped down to fit).
    ///
    /// "Overlaps" rather than "is fully contained" is deliberate: a window straddling two displays,
    /// or one that pokes a few points past a screen's edge, is reachable and must be left alone —
    /// this only rescues a window with **zero** connected screens under it.
    static func clampedFrame(_ frame: CGRect, toFit screens: [CGRect]) -> CGRect {
        guard !screens.isEmpty else { return frame }
        if screens.contains(where: { $0.intersects(frame) }) {
            return frame
        }
        guard let target = screens.first else { return frame }
        let width = min(frame.width, target.width)
        let height = min(frame.height, target.height)
        let x = target.midX - width / 2
        let y = target.midY - height / 2
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// The AppKit-facing call site. Repositions any window whose restored frame does not overlap a
    /// connected screen; leaves every other window's frame untouched.
    @MainActor
    static func clampWindowsOntoConnectedScreens(_ windows: [NSWindow], screens: [NSScreen]) {
        let screenFrames = screens.map(\.frame)
        guard !screenFrames.isEmpty else { return }
        for window in windows {
            let clamped = clampedFrame(window.frame, toFit: screenFrames)
            guard clamped != window.frame else { continue }
            window.setFrame(clamped, display: true)
        }
    }
}
#endif
