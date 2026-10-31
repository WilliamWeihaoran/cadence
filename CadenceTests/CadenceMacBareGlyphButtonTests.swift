import Foundation
import Testing

/// **[[T-9501]].** A Mac icon button is not its bare glyph.
///
/// Seven buttons labelled a lone `Image(systemName:)` with no frame, padding or content shape, so
/// the glyph's own ink box was the whole hit area and the whole hover wash: the 9pt "x" that
/// removes a subtask (task-row subtask list and the New Task sheet's draft rows) was a ~9x11pt
/// target, and the saved-link row's Open / Delete, the Links header's add / close and the note
/// embed's Clear time were each the size of a 13pt glyph.
@Suite struct CadenceMacBareGlyphButtonTests {
    /// Every `Button` whose label is only a glyph and its paint, closed by `}` right before the
    /// `.buttonStyle(...)` line.
    static func bareGlyphButtons(in source: String) -> [Int] {
        let lines = source.components(separatedBy: "\n")
        func indent(_ line: String) -> Int { line.prefix { $0 == " " }.count }
        var found: [Int] = []
        for (index, line) in lines.enumerated() where line.contains(".buttonStyle(") {
            var close = index - 1
            while close > 0, lines[close].trimmingCharacters(in: .whitespaces).isEmpty { close -= 1 }
            guard close > 0, lines[close].trimmingCharacters(in: .whitespaces) == "}" else { continue }
            let depth = indent(lines[close])
            var label: [String] = []
            var cursor = close - 1
            while cursor > 0 {
                let candidate = lines[cursor]
                let trimmed = candidate.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && indent(candidate) <= depth { break }
                if !trimmed.isEmpty { label.insert(trimmed, at: 0) }
                cursor -= 1
            }
            guard let first = label.first, first.hasPrefix("Image(systemName") else { continue }
            if label.contains(where: { $0.hasPrefix(".frame") || $0.hasPrefix(".padding") || $0.hasPrefix(".contentShape") }) { continue }
            if label.contains(where: { $0.hasPrefix("Text(") || $0.hasPrefix("HStack") || $0.hasPrefix("VStack") }) { continue }
            found.append(index + 1)
        }
        return found
    }

    @Test func noMacButtonIsItsBareGlyph() throws {
        var offenders: [String] = []
        var scanned = 0
        for path in try CadenceSourceScan.swiftFiles(under: "Cadence/macOS") {
            let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            scanned += source.components(separatedBy: ".buttonStyle(").count - 1
            offenders += Self.bareGlyphButtons(in: source).map { "\(path):\($0)" }
        }
        #expect(scanned > 100, "non-vacuity: only \(scanned) button styles under Cadence/macOS")
        #expect(offenders.isEmpty, "a Mac button whose hit area is its bare glyph: \(offenders)")
    }

    /// The scanner itself: it finds the shape and lets a framed glyph through.
    @Test func theScannerFindsABareGlyphAndPassesAFramedOne() {
        let bare = """
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
            }
            .buttonStyle(.cadencePlain)
        """
        let framed = """
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
                    .frame(minWidth: 18, minHeight: 16)
            }
            .buttonStyle(.cadencePlain)
        """
        #expect(Self.bareGlyphButtons(in: bare) == [5])
        #expect(Self.bareGlyphButtons(in: framed).isEmpty)
    }
}
