import Testing
@testable import Cadence

#if os(macOS)
/// **T-1036 / T-1037.** `macOSRootShellViews.swift`'s `SidebarResizeHandleView` used to compute its
/// accent tint inline — `isDragging ? 0.26 : (isHovered ? 0.18 : 0)` — on a private `NSView` with no
/// seam a test could reach. `SidebarResizeHandleAppearance` is that seam: a plain, non-private value
/// type the view's `updateHandleAppearance()` now defers to.
///
/// **T-1036, the latch.** `isDragging` used to clear only in `mouseUp` and `isHovered` only in
/// `mouseExited`, and `updateTrackingAreas()` rebuilds the tracking area on every geometry change —
/// continuously during a resize drag — while AppKit suppresses enter/exit for a rebuilt area. Ending
/// a drag with the pointer outside the handle's clamped new frame left a permanent accent band with
/// no `mouseExited` ever arriving to clear it. Neither half of that has a pure-function seam either
/// (it lives entirely in AppKit event callbacks), so those two fixes —
/// `refreshHoverFromCurrentMouseLocation()` polling `window.mouseLocationOutsideOfEventStream`
/// whenever tracking areas rebuild, and clearing `isDragging` on `NSWindow.didResignKeyNotification`
/// as well as `mouseUp` — are pinned by source scan below rather than unit-tested directly.
///
/// **T-1037, the fourth state.** `.focused` is new: a keyboard-only user tabbing onto the handle
/// gets a dim, distinct tint since `focusRingMaskBounds` was measured empty (AppKit draws nothing
/// for this view's native focus ring, with or without Full Keyboard Access) — plus arrow-key
/// resizing and an accessibility role/label/value, also pinned by source scan.
struct CadenceSidebarResizeHandleAppearanceTests {

    // MARK: - Priority order (the property this whole file is about)

    @Test func restIsTheDefaultWithNoFlagsSet() {
        let appearance = SidebarResizeHandleAppearance.resolve(isDragging: false, isHovered: false, isFocused: false)
        #expect(appearance == .rest)
        #expect(appearance.accentAlpha == 0)
    }

    @Test func hoverAloneShowsTheHoverTint() {
        let appearance = SidebarResizeHandleAppearance.resolve(isDragging: false, isHovered: true, isFocused: false)
        #expect(appearance == .hovered)
        #expect(appearance.accentAlpha == 0.18)
    }

    @Test func dragAloneShowsTheDragTint() {
        let appearance = SidebarResizeHandleAppearance.resolve(isDragging: true, isHovered: false, isFocused: false)
        #expect(appearance == .dragging)
        #expect(appearance.accentAlpha == 0.26)
    }

    @Test func focusAloneShowsAFourthTintDistinctFromRestHoverAndDrag() {
        let appearance = SidebarResizeHandleAppearance.resolve(isDragging: false, isHovered: false, isFocused: true)
        #expect(appearance == .focused)
        let alpha = appearance.accentAlpha
        #expect(alpha != SidebarResizeHandleAppearance.rest.accentAlpha)
        #expect(alpha != SidebarResizeHandleAppearance.hovered.accentAlpha)
        #expect(alpha != SidebarResizeHandleAppearance.dragging.accentAlpha)
    }

    /// `mouseDown` calls `window?.makeFirstResponder(self)` before setting `isDragging = true`, so a
    /// drag always carries focus too. Without this ordering a drag would render the dimmer focus
    /// tint instead of its own — regressing exactly what T-1036 measured (`#14315C`).
    @Test func dragOutranksHoverAndFocusWhenAllThreeAreTrue() {
        #expect(
            SidebarResizeHandleAppearance.resolve(isDragging: true, isHovered: true, isFocused: true) == .dragging
        )
        #expect(
            SidebarResizeHandleAppearance.resolve(isDragging: true, isHovered: false, isFocused: true) == .dragging
        )
    }

    @Test func hoverOutranksFocusWhenBothAreTrueButNotDragging() {
        #expect(
            SidebarResizeHandleAppearance.resolve(isDragging: false, isHovered: true, isFocused: true) == .hovered
        )
    }

    // MARK: - The alphas themselves, pinned as values rather than just an order

    @Test func theFourAlphasAreAllDistinct() {
        let alphas = Set([
            SidebarResizeHandleAppearance.rest.accentAlpha,
            SidebarResizeHandleAppearance.focused.accentAlpha,
            SidebarResizeHandleAppearance.hovered.accentAlpha,
            SidebarResizeHandleAppearance.dragging.accentAlpha,
        ])
        #expect(alphas.count == 4, "two states share an alpha and are indistinguishable on screen")
    }

    @Test func restIsFullyTransparent() {
        #expect(SidebarResizeHandleAppearance.rest.accentAlpha == 0)
    }

    // MARK: - T-1036: source-scan pins for the two fixes with no pure-function seam

    @Test func trackingAreaRebuildRePollsTheLiveMouseLocation() throws {
        let source = try shellSource()
        let body = try #require(
            CadenceSourceScan.declarationBody("override func updateTrackingAreas()", in: source)
        )
        #expect(
            body.contains("refreshHoverFromCurrentMouseLocation()"),
            "updateTrackingAreas() no longer re-derives hover, so a rebuild mid-drag can re-latch it"
        )
    }

    @Test func hoverIsReDerivedFromTheWindowsLiveMouseLocation() throws {
        let source = try shellSource()
        let body = try #require(
            CadenceSourceScan.declarationBody("private func refreshHoverFromCurrentMouseLocation()", in: source)
        )
        #expect(body.contains("window.mouseLocationOutsideOfEventStream"))
        #expect(body.contains("bounds.contains("))
    }

    @Test func aDraggingViewObservesItsWindowResigningKey() throws {
        let source = try shellSource()
        #expect(
            CadenceSourceScan.matchCount("NSWindow\\.didResignKeyNotification", in: source) == 2,
            "expected one removeObserver and one addObserver naming NSWindow.didResignKeyNotification"
        )
        let handler = try #require(
            CadenceSourceScan.declarationBody("private func handleWindowDidResignKey()", in: source)
        )
        #expect(handler.contains("isDragging = false"))
        #expect(handler.contains("coordinator.endDrag()"))
    }

    // MARK: - T-1037: source-scan pins for keyboard resizing, accessibility, and the forbidden fix

    @Test func arrowKeysResizeThroughTheCoordinator() throws {
        let source = try shellSource()
        let body = try #require(
            CadenceSourceScan.declarationBody("override func keyDown(with event: NSEvent)", in: source)
        )
        #expect(body.contains(".leftArrow"))
        #expect(body.contains(".rightArrow"))
        #expect(
            CadenceSourceScan.matchCount("coordinator\\.adjustWidth\\(by:", in: body) == 2,
            "expected one adjustWidth call per arrow direction"
        )
        // Not just "both arrows call adjustWidth", but that they carry opposite signs — the whole
        // point of an arrow-key resize control. `-Self.arrowKeyStepWidth` (with the leading `-`)
        // and `Self.arrowKeyStepWidth` (without one) are each other's near-miss: a substring match
        // for the un-dashed form fails to find it inside the dashed one, so a mutation that flips
        // either arrow onto the wrong sign drops one of these to zero.
        #expect(
            CadenceSourceScan.matchCount("adjustWidth\\(by: -Self\\.arrowKeyStepWidth\\)", in: body) == 1,
            "expected exactly one arrow case to narrow (negative delta)"
        )
        #expect(
            CadenceSourceScan.matchCount("adjustWidth\\(by: Self\\.arrowKeyStepWidth\\)", in: body) == 1,
            "expected exactly one arrow case to widen (positive delta) -- a same-sign pair or a swap both fail this"
        )
    }

    @Test func accessibilityRoleLabelAndValueAreAllDeclared() throws {
        let source = try shellSource()
        #expect(source.contains("override func accessibilityRole() -> NSAccessibility.Role?"))
        #expect(source.contains("override func accessibilityLabel() -> String?"))
        #expect(source.contains("\"Sidebar width\""))
        #expect(source.contains("override func accessibilityValue() -> Any?"))
        #expect(source.contains("override func isAccessibilityElement() -> Bool"))
    }

    @Test func accessibilityIncrementAndDecrementAlsoResizeThroughTheCoordinator() throws {
        let source = try shellSource()
        let increment = try #require(
            CadenceSourceScan.declarationBody("override func accessibilityPerformIncrement() -> Bool", in: source)
        )
        let decrement = try #require(
            CadenceSourceScan.declarationBody("override func accessibilityPerformDecrement() -> Bool", in: source)
        )
        #expect(increment.contains("coordinator.adjustWidth(by:"))
        #expect(decrement.contains("coordinator.adjustWidth(by:"))
    }

    /// The ticket names this exact non-fix: `focusRingType = .none` is a measured no-op on this
    /// view (`focusRingMaskBounds` is already empty), so it must not appear as a "fix".
    @Test func focusRingTypeIsNeverSetToNone() throws {
        let source = try shellSource()
        #expect(CadenceSourceScan.matchCount("focusRingType\\s*=\\s*\\.none", in: source) == 0)
    }

    /// The seam itself: not `private`, so a test can reach it, and declared once.
    @Test func theAppearanceTypeIsNotPrivate() throws {
        let source = try shellSource()
        #expect(source.contains("enum SidebarResizeHandleAppearance"))
        #expect(!source.contains("private enum SidebarResizeHandleAppearance"))
        #expect(CadenceSourceScan.matchCount("enum SidebarResizeHandleAppearance", in: source) == 1)
    }
}

/// Comment-stripped rather than `codeOnly`: some assertions above check for a specific string
/// literal (`"Sidebar width"`), and `codeOnly` blanks string-literal contents along with comments.
private func shellSource() throws -> String {
    CadenceSourceScan.strippingComments(
        try CadenceSourceScan.sourceFile("Cadence/macOS/Views/macOSRootShellViews.swift")
    )
}
#endif
