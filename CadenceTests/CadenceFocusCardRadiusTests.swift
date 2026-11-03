import Foundation
import Testing
@testable import Cadence

/// **[[T-9654]].** The Mac Focus session's two stacked cards -- the timer above, the notes below --
/// clip at one radius, read from `Theme.radiusFocusCard`, the radius the rest of the Focus surface
/// already uses. The timer used to clip at `Theme.radiusPanel` (22) over an 8pt notes card, so the
/// two read as different components; the timer keeps its shadow, which is what sets it apart.
@Suite struct CadenceFocusCardRadiusTests {
    private static func body(_ declaration: String, in path: String) throws -> String {
        let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
        return try #require(CadenceSourceScan.declarationBody(declaration, in: source))
    }

    @Test func theTimerAndNotesCardsShareTheFocusCardRadius() throws {
        let timer = try Self.body("struct FocusTimerPanel<Controls: View>: View", in: "Cadence/macOS/Views/FocusChromeSupportViews.swift")
        let notes = try Self.body("struct FocusNotesPanel: View", in: "Cadence/macOS/Views/FocusNotesPanel.swift")

        for (name, body) in [("FocusTimerPanel", timer), ("FocusNotesPanel", notes)] {
            let shapes = body.components(separatedBy: "RoundedRectangle(cornerRadius:").count - 1
            let atToken = body.components(separatedBy: "RoundedRectangle(cornerRadius: Theme.radiusFocusCard").count - 1
            #expect(shapes >= 1, "non-vacuity: \(name) draws \(shapes) rounded rectangles")
            #expect(atToken == shapes, "\(shapes - atToken) of \(name)'s card shapes are not at Theme.radiusFocusCard")
            #expect(!body.contains("radiusPanel"), "\(name) still clips at the panel radius")
        }

        #expect(timer.contains(".shadow(color: Theme.cardElevationShadow"), "the timer card lost the shadow that sets it apart")
        #expect(Theme.radiusFocusCard == 8)
        #expect(Theme.radiusFocusCard < Theme.radiusPanel)
    }
}
