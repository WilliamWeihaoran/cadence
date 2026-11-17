import Foundation
import SwiftUI
import Testing
@testable import Cadence

/// **[[T-10041]]: the Mac's window-level overlay cards drew four chromes for one kind of surface.**
///
/// The delete confirmation, the Shift+T / Shift+D date panel and Cmd+K were each 22 with their own
/// hairline and shadow, and the New Task panel (with the quick-capture success card that replaces
/// it) a literal 16. Owner decision 2026-11-02: one shared overlay-card modifier at
/// `Theme.radiusPanel`, one hairline and one shadow for all of them; the New Task panel keeps its
/// blue glow.
@MainActor
struct CadenceOverlayCardChromeTests {
    private static let cards: [(path: String, declaration: String)] = [
        ("Cadence/macOS/Views/macOSRootSupportViews.swift", "struct DeleteConfirmationOverlay: View"),
        ("Cadence/macOS/Views/macOSRootSupportViews.swift", "struct HoveredTaskDatePickerOverlay: View"),
        ("Cadence/macOS/Views/GlobalSearchOverlayShellViews.swift", "struct GlobalSearchOverlayShell<Content: View>: View"),
        ("Cadence/macOS/Sheets/CreateTaskSheetSupportViews.swift", "struct CreateTaskPanelSurface: View"),
        ("Cadence/macOS/Services/QuickTaskPanelController.swift", "private struct QuickTaskCaptureSuccessView: View"),
    ]

    private static func compactBody(_ declaration: String, in path: String) throws -> String {
        let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
        let body = try #require(CadenceSourceScan.declarationBody(declaration, in: source),
                                "\(declaration) not found in \(path)")
        return body.filter { !$0.isWhitespace }
    }

    @Test func theSharedChromeIsThePanelRadius() {
        #expect(CadenceOverlayCardStyle.cornerRadius == Theme.radiusPanel)
    }

    @Test func everyWindowLevelCardWearsTheSharedChromeAndNoneOfItsOwn() throws {
        #expect(Self.cards.count == 5)
        for card in Self.cards {
            let body = try Self.compactBody(card.declaration, in: card.path)
            #expect(body.components(separatedBy: ".cadenceOverlayCard(").count - 1 == 1,
                    "\(card.declaration) applies the shared overlay-card chrome exactly once")
            #expect(!body.contains("Theme.overlayCardShadow"),
                    "\(card.declaration) still casts its own overlay shadow")
            #expect(!body.contains(".strokeBorder(Theme.borderSubtle"),
                    "\(card.declaration) still draws its own hairline")
            #expect(!body.contains("RoundedRectangle(cornerRadius:16"),
                    "\(card.declaration) still spells the literal 16")
        }
    }

    /// The glow is an affordance, not chrome drift: only the card that takes input (and the success
    /// card standing in its place) carries one.
    @Test func onlyTheNewTaskPanelAndItsSuccessCardGlow() throws {
        for card in Self.cards {
            let body = try Self.compactBody(card.declaration, in: card.path)
            let glows = body.contains(".cadenceOverlayCard(glow:")
            let expected = card.declaration.contains("CreateTaskPanelSurface")
                || card.declaration.contains("QuickTaskCaptureSuccessView")
            #expect(glows == expected, "\(card.declaration): glow \(glows), expected \(expected)")
        }
    }
}

#if os(macOS)
import AppKit

/// **[[T-18355]]: the Cmd+K card fits the window it is drawn in.** It was a fixed 760x620 card in a
/// window whose floor is 600pt (`CadenceApp`'s `minHeight: 600`), so a short window cut away its
/// corners, outline and shadow at both edges. The shell is laid out in a real `NSHostingView` at
/// the window's floor width, and the content reports the bounds it was placed in.
@MainActor
struct CadenceGlobalSearchOverlayFitTests {
    private final class PlacedBounds: @unchecked Sendable {
        var last: CGRect?
    }

    /// A content view that records where the shell placed it, the card's own bounds.
    private struct BoundsRecorder: Layout {
        let placed: PlacedBounds

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            proposal.replacingUnspecifiedDimensions()
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            placed.last = bounds
        }
    }

    private func cardBounds(inWindowHeight height: CGFloat) throws -> CGRect {
        let placed = PlacedBounds()
        let host = NSHostingView(rootView: GlobalSearchOverlayShell(onDismiss: {}) {
            BoundsRecorder(placed: placed) { Color.clear }
        })
        host.frame = CGRect(x: 0, y: 0, width: 960, height: height)
        host.layoutSubtreeIfNeeded()
        return try #require(placed.last, "the shell never placed its content")
    }

    /// Every reachable window height, from the 600pt floor up: the card plus a margin above and
    /// below fits, and the card never grows past its 620pt ceiling.
    @Test func theCardKeepsAMarginInsideEveryWindowHeight() throws {
        let margin = GlobalSearchOverlayLayout.windowMargin
        #expect(margin > 0)
        for windowHeight: CGFloat in [600, 620, 640, 668, 700, 1000] {
            let card = try cardBounds(inWindowHeight: windowHeight)
            #expect(card.height + 2 * margin <= windowHeight,
                    "at \(windowHeight)pt the card is \(card.height)pt and leaves no \(margin)pt margin")
            #expect(card.height == min(GlobalSearchOverlayLayout.maxCardHeight, windowHeight - 2 * margin),
                    "at \(windowHeight)pt the card is \(card.height)pt")
            #expect(card.width == GlobalSearchOverlayLayout.cardWidth)
        }
    }
}
#endif
