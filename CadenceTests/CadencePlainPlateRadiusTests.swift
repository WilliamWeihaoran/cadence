import CoreGraphics
import Foundation
import Testing
@testable import Cadence

/// **[[T-9535]].** `.cadencePlain`'s hover wash is drawn at the radius of the plate it surrounds.
///
/// The style always filled and stroked a `Theme.radiusControl` (10pt) rounded rectangle, so on ~40
/// Mac controls whose label paints its own plate at another radius (the board's 7/8pt rows, Cmd+K's
/// 12pt rows, the add-column rail's 14, Settings' 6/8...) the pointer lit a second outline whose
/// corners did not meet the plate's -- against AGENTS.md's one-hover-layer-at-one-radius rule. The
/// style now takes the radius (`.cadencePlain(cornerRadius:)`); the default stays 10pt for a label
/// with no plate of its own.
@Suite struct CadencePlainPlateRadiusTests {
    private static func code(_ path: String) throws -> String {
        CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
    }

    /// The wash, its stroke and both hit shapes are drawn in the style's own plate, never at a
    /// hard-coded token and never in a shape the plate did not ask for.
    ///
    /// **[[T-9601]] widened this from a radius to a shape**, so the counting half changed with it:
    /// a rounded rectangle is one of three cases rather than the only one, and what has to hold is
    /// that every shape the body draws comes out of a `switch` over `plate`.
    @Test func theWashIsDrawnInTheStylesPlate() throws {
        let source = try Self.code("Cadence/Shared/CadenceHoverStyles.swift")
        let body = try #require(CadenceSourceScan.declarationBody(
            "private struct CadencePlainButtonBody: View", in: source
        ))

        // Six shapes and no more: three plate cases, filled once and stroked once. A seventh
        // would be a shape nothing in the plate asked for, which is the defect itself.
        let shapes = ["RoundedRectangle(", "Circle()", "Capsule()"]
            .map { body.components(separatedBy: $0).count - 1 }
            .reduce(0, +)
        #expect(shapes == 6, "the style draws \(shapes) shapes, not the three plates' fill and stroke")
        #expect(body.components(separatedBy: "switch plate {").count - 1 == 2, "the wash is not switched on the plate")
        for arm in ["case .roundedRectangle(let radius)", "case .circle", "case .capsule"] {
            #expect(body.components(separatedBy: arm).count - 1 == 2, "\(arm) is not drawn twice")
        }
        #expect(body.components(separatedBy: "RoundedRectangle(cornerRadius: radius)").count - 1 == 2,
                "a rounded plate is drawn at something other than its own radius")
        // The fill sits below the label and the stroke above it, where both have always been, so
        // T-9601 moves the shape and nothing else.
        #expect(body.contains(".background {"))
        #expect(body.contains(".overlay {"))
        #expect(body.contains("fill(Theme.blue.opacity(backgroundOpacity))"))
        #expect(body.contains("strokeBorder(Theme.blue.opacity(strokeOpacity))"))
        // Both platforms take their hit shape from the plate rather than re-spelling one.
        #expect(body.components(separatedBy: ".contentShape(plate.hitShape)").count - 1 == 2)
        #expect(!body.contains("radiusControl"), "the style's body pins a radius token")

        // The hit shape answers all three plates, so a round control's TAP area is round too --
        // the half of this that reaches iOS, where there is no wash to look at.
        let plate = try #require(CadenceSourceScan.declarationBody(
            "enum CadencePlainButtonPlate: Equatable", in: source
        ))
        #expect(plate.contains("AnyShape(RoundedRectangle(cornerRadius: radius))"))
        #expect(plate.contains("AnyShape(Circle())"))
        #expect(plate.contains("AnyShape(Capsule())"))

        #expect(CadencePlainButtonStyle().plate == .roundedRectangle(Theme.radiusControl))
        let plated = CadencePlainButtonStyle.cadencePlain(cornerRadius: Theme.radiusControlCompact)
        #expect(plated.plate == .roundedRectangle(Theme.radiusControlCompact))
        #expect(plated.plate != CadencePlainButtonStyle.cadencePlain.plate)
        #expect(CadencePlainButtonStyle.cadencePlain(.circle).plate == .circle)
        #expect(CadencePlainButtonStyle.cadencePlain(.capsule).plate == .capsule)
    }

    /// **[[T-9601]]. A round plate takes a round wash.** Every `.cadencePlain` button whose label
    /// clips or hit-shapes to a `Circle` or a `Capsule` passes that shape to the style, so the
    /// pointer does not light a 10pt rounded rectangle round a circle.
    @Test func everyRoundPlatedButtonPassesItsPlatesShape() throws {
        var round = 0
        var offenders: [String] = []
        for path in try CadenceSourceScan.swiftFiles(under: "Cadence") {
            let lines = try Self.code(path).components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix(".buttonStyle(.cadencePlain") else { continue }
                guard let start = Self.buttonStart(above: index, in: lines) else { continue }
                guard let shape = Self.roundPlate(of: Array(lines[start..<index])) else { continue }
                round += 1
                let expected = ".buttonStyle(.cadencePlain(\(shape)))"
                if trimmed != expected {
                    offenders.append("\(path):\(index + 1) plate \(shape), style \(trimmed)")
                }
            }
        }
        #expect(round >= 10, "non-vacuity: only \(round) round-plated .cadencePlain buttons found")
        #expect(offenders.isEmpty, "a rounded-rectangle wash round a round plate: \(offenders)")
    }

    /// **[[T-9603]].** `.cadencePlain` IS the hover layer: no button wearing it may also brighten
    /// its own plate under the pointer, or one pointer lights two layers.
    ///
    /// The three the ticket named -- the Focus picker's and sidebar's task rows and the board's
    /// add-card row -- were already fixed by [[T-9945]] and [[T-9946]], which moved them to
    /// `.plain` with their own plate as the single layer. This keeps that settled. A hover flag
    /// read for a TINT or an underline is not a second plate and is deliberately allowed: the
    /// rule is about `background` / `overlay` / `fill` / `strokeBorder`.
    @Test func noPlainButtonAlsoBrightensItsOwnPlateOnHover() throws {
        var scanned = 0
        var offenders: [String] = []
        for path in try CadenceSourceScan.swiftFiles(under: "Cadence") {
            let lines = try Self.code(path).components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix(".buttonStyle(.cadencePlain") else { continue }
                guard let start = Self.buttonStart(above: index, in: lines) else { continue }
                scanned += 1
                for (offset, labelLine) in lines[start..<index].enumerated()
                where Self.paintsAHoverPlate(labelLine) {
                    offenders.append("\(path):\(start + offset + 1) \(labelLine.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        // A floor, not a census: it was `> 80` until T-12623 moved New Context to SettingsActionButton.
        #expect(scanned >= 70, "non-vacuity: only \(scanned) .cadencePlain buttons scanned")
        #expect(offenders.isEmpty, "a second hover layer under the style's wash: \(offenders)")
    }

    /// A plate painter whose argument reads a hover flag.
    static func paintsAHoverPlate(_ line: String) -> Bool {
        let painters = [".background(", ".overlay(", ".fill(", ".strokeBorder("]
        guard painters.contains(where: { line.contains($0) }) else { return false }
        return line.range(of: #"\bis[A-Za-z]*[Hh]overed\b"#, options: .regularExpression) != nil
    }

    /// The label's outermost ROUND plate, spelled the way a call site passes it, or `nil` when the
    /// outermost shape is a rounded rectangle (which `plateRadius` answers instead) or none.
    /// Modifiers wrap outward, so the last shape in the label is the outermost one.
    static func roundPlate(of label: [String]) -> String? {
        let text = label.joined(separator: "\n")
        var outermost: (position: String.Index, spelling: String?)?
        for candidate in [("RoundedRectangle(cornerRadius:", nil), ("Circle()", ".circle"), ("Capsule()", ".capsule")]
            as [(String, String?)] {
            guard let range = text.range(of: candidate.0, options: .backwards) else { continue }
            if outermost == nil || range.lowerBound > outermost!.position {
                outermost = (range.lowerBound, candidate.1)
            }
        }
        return outermost?.spelling
    }

    /// Every `.cadencePlain` button whose label paints its own rounded plate passes that plate's
    /// radius to the style, spelled the same way the plate spells it.
    @Test func everyPlatedButtonPassesItsPlatesRadius() throws {
        var scanned = 0
        var plated = 0
        var offenders: [String] = []
        for path in try CadenceSourceScan.swiftFiles(under: "Cadence") {
            let lines = try Self.code(path).components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix(".buttonStyle(.cadencePlain") else { continue }
                guard let start = Self.buttonStart(above: index, in: lines) else { continue }
                scanned += 1
                let label = Array(lines[start..<index])
                // [[T-9601]]: a round outermost plate is the shape census's, not this one's.
                if Self.roundPlate(of: label) != nil { continue }
                guard let radius = Self.plateRadius(of: label, declarations: Array(lines[max(0, start - 4)..<start]))
                    ?? Self.forwardedPlateRadius(of: label, buttonStart: start, in: lines) else {
                    continue
                }
                if radius == "Theme.radiusControl" || radius == "10" {
                    continue
                }
                plated += 1
                let expected = ".buttonStyle(.cadencePlain(cornerRadius: \(radius)))"
                if trimmed != expected {
                    offenders.append("\(path):\(index + 1) plate \(radius), style \(trimmed)")
                }
            }
        }
        // A floor, not a census: it was `> 80` until T-12623 moved New Context to SettingsActionButton.
        #expect(scanned >= 70, "non-vacuity: only \(scanned) .cadencePlain buttons scanned")
        #expect(plated >= 30, "non-vacuity: only \(plated) plated .cadencePlain buttons found")
        #expect(offenders.isEmpty, "a hover wash at a radius its plate does not have: \(offenders)")
    }

    private static func indent(_ line: String) -> Int {
        line.prefix(while: { $0 == " " }).count
    }

    /// The line opening the `Button` the style is applied to: the nearest line above at the
    /// style's indentation or less that is not a modifier or a closing bracket.
    private static func buttonStart(above index: Int, in lines: [String]) -> Int? {
        let depth = indent(lines[index])
        var cursor = index - 1
        while cursor >= 0 {
            let trimmed = lines[cursor].trimmingCharacters(in: .whitespaces)
            if let first = trimmed.first, indent(lines[cursor]) <= depth, !".})".contains(first) {
                return lines[cursor].contains("Button") ? cursor : nil
            }
            cursor -= 1
        }
        return nil
    }

    /// The radius of the label's outermost rounded shape: a `let shape = RoundedRectangle(...)`
    /// declared just above the button when the label draws with `shape`, else the last literal
    /// `RoundedRectangle(cornerRadius:` in the label, since modifiers wrap outward.
    private static func plateRadius(of label: [String], declarations: [String]) -> String? {
        let needle = "RoundedRectangle(cornerRadius:"
        let text = label.joined(separator: "\n")
        if text.range(of: #"\bshape\b"#, options: .regularExpression) != nil,
           let declaration = declarations.last(where: { $0.contains("let shape = \(needle)") }),
           let range = declaration.range(of: needle) {
            return argument(after: range.upperBound, in: declaration)
        }
        guard let range = text.range(of: needle, options: .backwards) else { return nil }
        return argument(after: range.upperBound, in: text)
    }

    /// **[[T-9671]].** The plate of a label that is a bare property name -- `label: { trigger }` --
    /// read off that property's own `var <name>: some View {` body in the same file: the nearest
    /// such declaration above the button, else the first below it. The scan above read only the
    /// label closure, so the Calendar Board's event card (`label`) and the task composer's list and
    /// section badges (`trigger`) kept a 10pt wash around their 7pt plates after T-9535.
    static func forwardedPlateRadius(of label: [String], buttonStart: Int, in lines: [String]) -> String? {
        let names = label.compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil ? trimmed : nil
        }
        for name in names {
            let pattern = #"^\s*(private |fileprivate )?var "# + name + #": some View \{"#
            let isDeclaration = { (line: String) in line.range(of: pattern, options: .regularExpression) != nil }
            let above = (0..<buttonStart).reversed().first { isDeclaration(lines[$0]) }
            guard let declaration = above ?? (buttonStart..<lines.count).first(where: { isDeclaration(lines[$0]) }) else {
                continue
            }
            var depth = 0
            var body: [String] = []
            for line in lines[declaration...] {
                body.append(line)
                depth += line.filter { $0 == "{" }.count - line.filter { $0 == "}" }.count
                if depth <= 0, body.count > 1 { break }
            }
            if let radius = plateRadius(of: body, declarations: []) { return radius }
        }
        return nil
    }

    /// The forwarded read finds a plate behind a bare property name, above or below the button,
    /// and finds nothing behind a name that declares no plate.
    @Test func aForwardedLabelIsReadThroughItsDeclaration() {
        let below = [
            "        Button { open() } label: {",
            "            label",
            "        }",
            "        .buttonStyle(.cadencePlain)",
            "    }",
            "    private var label: some View {",
            "        Text(\"x\")",
            "            .clipShape(RoundedRectangle(cornerRadius: kanbanCardCornerRadius, style: .continuous))",
            "    }",
        ]
        #expect(Self.forwardedPlateRadius(of: Array(below[0..<3]), buttonStart: 0, in: below) == "kanbanCardCornerRadius")

        let above = [
            "    private var trigger: some View {",
            "        Text(\"x\").clipShape(RoundedRectangle(cornerRadius: Theme.radiusControlCompact))",
            "    }",
            "    var body: some View {",
            "        Button { toggle() } label: {",
            "            trigger",
            "        }",
            "        .buttonStyle(.cadencePlain)",
        ]
        #expect(Self.forwardedPlateRadius(of: Array(above[4..<7]), buttonStart: 4, in: above) == "Theme.radiusControlCompact")

        let unplated = [
            "    private var glyph: some View {",
            "        Image(systemName: \"plus\")",
            "    }",
            "        Button { add() } label: {",
            "            glyph",
            "        }",
        ]
        #expect(Self.forwardedPlateRadius(of: Array(unplated[3..<6]), buttonStart: 3, in: unplated) == nil)
    }

    /// The expression from `start` up to the first `,` or unmatched `)` at its own depth.
    private static func argument(after start: String.Index, in text: String) -> String {
        var depth = 0
        var result = ""
        for character in text[start...] {
            if "([".contains(character) {
                depth += 1
            } else if ")]".contains(character) {
                if depth == 0 { break }
                depth -= 1
            } else if character == ",", depth == 0 {
                break
            }
            result.append(character)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
