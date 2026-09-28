import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Cadence

/// **T-1449: the macOS create-task sheet's fill, and the layer behind it.**
///
/// The ticket reported two defects — a translucent panel, and no dimming layer — from a
/// screenshot. Both readings were wrong, and this suite exists because the *measurement* that
/// settled it lives nowhere a future reader can re-run it.
///
/// Measured 2026-09-28 at `632ce987`, on a live `Cadence.app` launched through
/// `scripts/run-macos-app.sh` with `CADENCE_UI_TEST_SCENARIO=today-geometry`, captured by window
/// id, two shots two seconds apart byte-identical:
///
/// - the panel's interior is `rgb(19,19,23)` and `rgb(26,26,30)` — `Theme.surface` `#131316` and
///   `Theme.surfaceElevated` `#1a1a1e`, exactly, with no trace of the rows behind it anywhere
///   inside its bounds;
/// - every bright pixel of the list *outside* the panel reads `rgb(156,156,158)`, which is
///   `Theme.text` `#ededef` multiplied by `0.66` — i.e. `Theme.scrim` (black at `0.34`) composited
///   over it. The scrim is drawn and it is doing its arithmetic.
///
/// What the screenshot actually showed was the row title `Today One` **clipped flat** by the
/// panel's opaque rounded top edge (the panel's first row of fill is at y=694 of the capture and
/// the glyphs stop at y=687), and `Tod…` clipped by its left edge. A near-black panel over a
/// near-black page at a glance reads as transparency; at native resolution it is a cut.
///
/// ### What these tests can and cannot see
///
/// They cannot see drawing. A fill's alpha is not geometry and not in the accessibility tree —
/// that is the ticket's own point, and it stays true. What they pin is the three source-level
/// facts that *would* produce the reported appearance, each of which was checked by hand to close
/// the ticket and none of which was checked by anything that runs:
///
/// 1. the tokens the panel is filled with resolve fully opaque, and the one behind it does not;
/// 2. nothing in the two-view presentation chain introduces a `Material` or a
///    `.presentationBackground`;
/// 3. the modal layer still puts `Theme.scrim` *behind* the panel rather than beside or above it.
@MainActor
struct CadenceCreateTaskSheetSurfaceTests {

    // MARK: - Values

    /// **The fill is opaque; the layer behind it is not.**
    ///
    /// A value assertion rather than a scan of `Theme.swift`, for the reason
    /// `CadenceAccentPaletteTests` gives: a scan catches a token being respelled, a value catches a
    /// token no longer resolving. `Theme.surface` is written as a six-digit hex today, and
    /// `Color(hex:)` accepts eight — so the defect this refuses is a literal growing an alpha pair,
    /// which no spelling check would notice.
    @Test func theSurfacesTheSheetIsFilledWithAreOpaqueAndTheScrimIsNot() {
        for (name, colour) in [
            ("surface", Theme.surface),
            ("surfaceElevated", Theme.surfaceElevated),
            ("bg", Theme.bg),
        ] {
            #expect(
                alpha(of: colour) == 1,
                "Theme.\(name) resolves at alpha \(alpha(of: colour)); the create sheet is filled with it "
                + "and would let the task list read through — re-read T-1449"
            )
        }

        // Non-vacuity, and the second half of the pair: the assertion above is only worth
        // something if this file can tell an opaque token from a translucent one at all.
        let scrimAlpha = alpha(of: Theme.scrim)
        #expect(
            scrimAlpha > 0 && scrimAlpha < 1,
            "Theme.scrim resolves at alpha \(scrimAlpha) — at 0 it dims nothing and the sheet stops "
            + "reading as modal; at 1 it hides the page instead of dimming it"
        )
    }

    // MARK: - The presentation chain

    /// **No material, and no second background bolted on top of one.**
    ///
    /// The second half is the one worth stating. A translucent panel "fixed" by adding another
    /// `.background(...)` outside it looks fixed and leaves two fills in the chain, which is how
    /// the next reader inherits the question rather than the answer. `CreateTaskPanelSurface` adds
    /// clip, stroke and shadow and deliberately adds no fill of its own — the fill is
    /// `CreateTaskSheet`'s, at its root, and there is exactly one.
    @Test func theCreateSheetsPresentationChainAddsNoTranslucency() throws {
        let sheetBody = try body(
            of: "var body: some View",
            inside: "struct CreateTaskSheet: View",
            of: "Cadence/macOS/Sheets/CreateTaskSheet.swift"
        )
        #expect(
            sheetBody.contains(".background(Theme.surface)"),
            "the create sheet no longer fills itself with Theme.surface at its root — re-read T-1449"
        )
        assertNoTranslucency(in: sheetBody, named: "CreateTaskSheet.body")

        let panelBody = try body(
            of: "var body: some View",
            inside: "struct CreateTaskPanelSurface: View",
            of: "Cadence/macOS/Sheets/CreateTaskSheetSupportViews.swift"
        )
        assertNoTranslucency(in: panelBody, named: "CreateTaskPanelSurface.body")
        #expect(
            panelBody.contains(".background(") == false,
            "CreateTaskPanelSurface now carries a background of its own. The sheet inside it already "
            + "has one, so this is either a duplicate or a cover over a translucency that is still "
            + "there — T-1449 is explicit that the second is the trap"
        )
    }

    /// **The scrim is behind the panel, not beside it.**
    ///
    /// Ordering rather than presence, because presence is the weaker half: `Theme.scrim` named
    /// anywhere in the layer passes a `contains` while sitting *above* the panel, which would dim
    /// the sheet and leave the page bright — the exact inversion of what the layer is for.
    @Test func theModalLayerDrawsItsScrimUnderThePanel() throws {
        let layerBody = try body(
            of: "var body: some View",
            inside: "struct TaskCreationLayerView: View",
            of: "Cadence/macOS/Views/macOSRootSupportViews.swift"
        )

        let scrim = try #require(
            layerBody.range(of: "Theme.scrim"),
            "the create-task layer draws no scrim, so the sheet does not read as modal — re-read T-1449"
        )
        let panel = try #require(
            layerBody.range(of: "CreateTaskPanelSurface"),
            "non-vacuity: the layer no longer presents CreateTaskPanelSurface, so the ordering below "
            + "is about something else"
        )
        #expect(
            scrim.lowerBound < panel.lowerBound,
            "the scrim is drawn after the panel in the ZStack, so it dims the sheet and not the page"
        )
        #expect(
            layerBody.contains(".ignoresSafeArea()"),
            "the scrim stopped reaching past its container's safe area, so a band of the page stays "
            + "undimmed"
        )
    }

    // MARK: - Helpers

    private func alpha(of colour: Color) -> Double {
        let resolved = NSColor(colour)
        let srgb = resolved.usingColorSpace(.sRGB) ?? resolved
        return (srgb.alphaComponent * 10000).rounded() / 10000
    }

    private func body(of declaration: String, inside type: String, of path: String) throws -> String {
        let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
        return try cadenceFunctionBody(declaration, in: try cadenceFunctionBody(type, in: source))
    }

    /// The needles for the presentation defect the ticket named: a material, or a presentation
    /// background handed a translucent style. `.opacity(` is deliberately **not** among them —
    /// `CreateTaskPanelSurface` spells its stroke and both shadows with it, and a needle that fires
    /// on a colour's opacity cannot also mean a view's.
    private func assertNoTranslucency(in body: String, named name: String) {
        for needle in ["Material", ".presentationBackground", ".blendMode("] {
            #expect(
                body.contains(needle) == false,
                "\(name) now contains `\(needle)`. The create sheet is a modal panel over the task "
                + "list and its fill has to be opaque — re-read T-1449"
            )
        }
    }
}
