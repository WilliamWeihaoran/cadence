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
