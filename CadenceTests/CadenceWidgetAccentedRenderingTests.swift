import Foundation
import Testing

/// **Both widgets survive the accented (Tinted / Clear) rendering mode (T-18201).**
///
/// In `.accented` WidgetKit paints every view that is not `widgetAccentable` in one tint while
/// keeping its opacity, so an opaque card fill turns the text drawn on it into the same tint. The
/// widget target is not linked into the test host, so these read the widget sources: every opaque
/// fill goes through `cadenceWidgetCardBackground`, that modifier answers `.accented` with a plate
/// rather than the fill, and the marks that carry meaning (status badge, complete glyph, today)
/// are accentable.
struct CadenceWidgetAccentedRenderingTests {
    static let chrome = "CadenceWidgets/WidgetChrome.swift"

    /// A bare `.background(<opaque fill>)` anywhere in the widget target is a card that turns into
    /// a blank tinted block. The badge's own `tint.opacity(0.20)` is the one admitted fill: it is
    /// already a low-alpha plate of the badge's tint.
    @Test func noWidgetCardPaintsAnOpaqueFillOutsideTheAccentedAwareModifier() throws {
        let files = try CadenceSourceScan.swiftFiles(under: "CadenceWidgets")
        #expect(files.contains(Self.chrome), "the widget walk did not find WidgetChrome.swift, so it read nothing")
        var bare: [String] = []
        var routed = 0
        for path in files {
            let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            routed += source.components(separatedBy: ".cadenceWidgetCardBackground(").count - 1
            for match in source.matches(of: #/\.background\s*(\(|\{)\s*([^\n]*)/#) {
                let argument = String(match.2)
                if argument.hasPrefix("tint.opacity(") { continue }
                if path == Self.chrome, argument.hasPrefix("Rectangle()") || source[match.range].hasSuffix("{") { continue }
                bare.append("\(path): .background\(match.1)\(argument)")
            }
        }
        #expect(bare.isEmpty, "opaque widget fills bypass cadenceWidgetCardBackground, so they go solid in the accented mode: \(bare)")
        // Today's row, focus tile, container pill and priority card; Calendar's day cell; the
        // shared metric card, footer link and panel. A count FLOOR, so a new card adds, never reds.
        #expect(routed >= 8, "only \(routed) widget fills go through cadenceWidgetCardBackground")
    }

    @Test func theCardModifierAnswersTheAccentedModeWithAPlate() throws {
        let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(Self.chrome))
        let resolve = try #require(
            CadenceSourceScan.functionBody(named: "resolved", in: source),
            "CadenceWidgetCardFill.resolved is gone"
        )
        #expect(resolve.contains("renderingMode == .accented"), "the card fill no longer tells the accented mode apart")
        #expect(resolve.contains("return fill"), "the full-colour fill is no longer passed through unchanged")
        let modifier = try #require(
            CadenceSourceScan.declarationBody("private struct CadenceWidgetCardBackground", in: source),
            "the card background modifier is gone"
        )
        #expect(modifier.contains("@Environment(\\.widgetRenderingMode)"), "the card modifier does not read the rendering mode")
        #expect(modifier.contains("CadenceWidgetCardFill.resolved("), "the card modifier paints the fill without resolving it")

        // The plate must be a plate: well under half opacity, and today's heavier than a card's so
        // it is still told apart in one tint.
        let card = try #require(source.firstMatch(of: #/accentedPlateOpacity: Double = ([0-9.]+)/#).flatMap { Double($0.1) })
        let today = try #require(source.firstMatch(of: #/accentedEmphasizedPlateOpacity: Double = ([0-9.]+)/#).flatMap { Double($0.1) })
        #expect(card > 0 && card < 0.5)
        #expect(today > card && today < 0.5)
    }

    @Test func theMarksThatCarryMeaningAreAccentable() throws {
        let chrome = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(Self.chrome))
        let badge = try #require(CadenceSourceScan.declarationBody("struct CadenceWidgetBadge", in: chrome))
        #expect(badge.contains(".widgetAccentable()"), "the status badge is painted in the body tint, so overdue reads like everything else")

        let today = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile("CadenceWidgets/TodayTasksWidgetView.swift"))
        let complete = try #require(CadenceSourceScan.functionBody(named: "completeButton", in: today))
        #expect(complete.contains(".widgetAccentable()"), "the complete glyph is not accentable")

        let calendar = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile("CadenceWidgets/CalendarSnapshotWidget.swift"))
        let cell = try #require(CadenceSourceScan.functionBody(named: "dayCell", in: calendar))
        #expect(cell.contains(".widgetAccentable(day.isToday)"), "today's weekday label is not accentable")
        #expect(cell.contains("emphasized: day.isToday"), "today's cell takes the same plate as every other day")
    }
}
