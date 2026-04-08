#if os(macOS)
import AppKit

enum MarkdownListPrefixKind {
    case bullet
    case dash
    case todo
    case done
    case ordered
}

struct MarkdownListPrefixMatch {
    let kind: MarkdownListPrefixKind
    let indentation: String
    let marker: String
    let prefix: String
}

enum MarkdownListSupport {
    static func indentationPrefix(in text: NSString, replacingRange: NSRange) -> String? {
        let lineRange = text.lineRange(for: replacingRange)
        let prefixRange = NSRange(location: lineRange.location, length: replacingRange.location - lineRange.location)
        let prefix = text.substring(with: prefixRange)
        guard prefix.allSatisfy({ $0 == " " || $0 == "\t" }) else { return nil }
        return normalizedIndentation(prefix)
    }

    static func orderedMarker(forIndentation indentation: String) -> String {
        let level = min(indentation.count / 4, 4)
        return MarkdownStylist.orderedMarker(for: level, index: 1)
    }

    static func nextOrderedMarker(after marker: String) -> String {
        let normalized = marker.trimmingCharacters(in: .whitespaces)
        let bare = normalized.hasSuffix(".") ? String(normalized.dropLast()) : normalized
        if let number = Int(bare) {
            return "\(number + 1)."
        }
        if let romanValue = MarkdownStylist.romanToInt(bare.lowercased()) {
            return MarkdownStylist.intToRoman(romanValue + 1) + "."
        }
        if bare.count == 1, let scalar = bare.unicodeScalars.first {
            let value = scalar.value
            if (65...90).contains(value), let next = UnicodeScalar(min(value + 1, 90)) {
                return String(next).lowercased() + "."
            }
            if (97...122).contains(value), let next = UnicodeScalar(min(value + 1, 122)) {
                return String(next) + "."
            }
        }
        return marker
    }

    static func listPrefixMatch(in line: String) -> MarkdownListPrefixMatch? {
        let indentation = rawIndentation(in: line)
        let trimmed = String(line.dropFirst(indentation.count))

        let simplePrefixes: [(String, MarkdownListPrefixKind, String)] = [
            ("• ", .bullet, "• "),
            ("– ", .dash, "– "),
            ("○ ", .todo, "○ "),
            ("● ", .done, "● ")
        ]
        for (prefix, kind, marker) in simplePrefixes where trimmed.hasPrefix(prefix) {
            return MarkdownListPrefixMatch(kind: kind, indentation: indentation, marker: marker, prefix: indentation + prefix)
        }

        guard let regex = try? NSRegularExpression(pattern: #"^((?:\d+|[A-Za-z]+|[ivxlcdmIVXLCDM]+)\.)\s"#),
              let match = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: (trimmed as NSString).length)) else {
            return nil
        }

        let markerRange = match.range(at: 1)
        let marker = (trimmed as NSString).substring(with: markerRange)
        let prefix = indentation + (trimmed as NSString).substring(with: NSRange(location: 0, length: match.range.length))
        return MarkdownListPrefixMatch(kind: .ordered, indentation: indentation, marker: marker, prefix: prefix)
    }

    static func remapOrderedMarkerIfNeeded(in line: String, originalMatch: MarkdownListPrefixMatch) -> String {
        guard originalMatch.kind == .ordered,
              let updatedMatch = listPrefixMatch(in: line) else { return line }

        let updatedLevel = min(normalizedIndentation(updatedMatch.indentation).count / 4, 4)
        let targetMarker = MarkdownStylist.orderedMarker(for: updatedLevel, index: 1)
        guard updatedMatch.marker != targetMarker else { return line }

        let indentationCount = updatedMatch.indentation.count
        let markerStart = line.index(line.startIndex, offsetBy: indentationCount)
        let markerEnd = line.index(markerStart, offsetBy: updatedMatch.marker.count)
        return String(line[..<markerStart]) + targetMarker + String(line[markerEnd...])
    }

    private static func rawIndentation(in line: String) -> String {
        String(line.prefix { $0 == " " || $0 == "\t" })
    }

    private static func normalizedIndentation(_ indentation: String) -> String {
        indentation.replacingOccurrences(of: "\t", with: String(repeating: " ", count: 4))
    }
}

enum MarkdownStylist {
    static let bgColor        = NSColor(hex: "#0f1117")
    static let textColor      = NSColor(hex: "#e2e8f0")
    static let dimColor       = NSColor(hex: "#6b7a99")
    static let codeBackground = NSColor(hex: "#1f2235")
    static let blueColor      = NSColor(hex: "#4a9eff")
    static let greenColor     = NSColor(hex: "#4ecb71")

    static let baseFont   = NSFont.systemFont(ofSize: 14)
    static let monoFont   = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    static let hiddenFont = NSFont.systemFont(ofSize: 0.01)

    static let baseAttributes: [NSAttributedString.Key: Any] = [
        .font: baseFont,
        .foregroundColor: textColor
    ]

    static func apply(to textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let text = textView.string
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: storage.length)

        storage.beginEditing()

        storage.setAttributes([
            .font: baseFont,
            .foregroundColor: textColor,
            .paragraphStyle: baseParagraphStyle
        ], range: fullRange)

        var pos = 0
        for line in text.components(separatedBy: "\n") {
            let len = (line as NSString).length
            applyLine(storage: storage, line: line, lineRange: NSRange(location: pos, length: len), lineStart: pos)
            pos += len + 1
        }

        applyInline(storage: storage, text: nsText,
                    pattern: "\\*\\*(.+?)\\*\\*", markerLen: 2,
                    contentStyle: { range, s in
                        let existing = s.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? baseFont
                        s.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: existing.pointSize), range: range)
                    })
        applyInline(storage: storage, text: nsText,
                    pattern: "(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)", markerLen: 1,
                    contentStyle: { range, s in
                        let existing = s.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? baseFont
                        let italic = NSFontManager.shared.convert(existing, toHaveTrait: .italicFontMask)
                        s.addAttribute(.font, value: italic, range: range)
                    })
        applyCode(storage, text: nsText)
        applyInline(storage: storage, text: nsText,
                    pattern: "~~(.+?)~~", markerLen: 2,
                    contentStyle: { range, s in
                        s.addAttribute(.foregroundColor, value: dimColor, range: range)
                        s.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                    })

        storage.endEditing()
    }

    private static func applyLine(storage: NSTextStorage, line: String, lineRange: NSRange, lineStart: Int) {
        if line.hasPrefix("### ") {
            heading(storage, lineRange, lineStart, prefixLen: 4, size: 16)
        } else if line.hasPrefix("## ") {
            heading(storage, lineRange, lineStart, prefixLen: 3, size: 19)
        } else if line.hasPrefix("# ") {
            heading(storage, lineRange, lineStart, prefixLen: 2, size: 24)
        } else if line.hasPrefix("> ") {
            hide(storage, NSRange(location: lineStart, length: 2))
            let rest = NSRange(location: lineStart + 2, length: max(0, lineRange.length - 2))
            storage.addAttribute(.foregroundColor, value: NSColor(hex: "#c4d4e8"), range: rest)
        } else if let ordered = orderedListMatch(in: line) {
            let level = min(ordered.indentation.count / 4, 4)
            let ps = listStyle(for: level, markerWidth: ordered.marker.count + 1)
            storage.addAttribute(.paragraphStyle, value: ps, range: lineRange)
            let markerRange = NSRange(location: lineStart + ordered.indentation.count, length: min(ordered.marker.count, lineRange.length))
            storage.addAttribute(.foregroundColor, value: blueColor, range: markerRange)
            storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 13, weight: .semibold), range: markerRange)
        } else if let bullet = unorderedListMatch(in: line) {
            let level = min(bullet.indentation.count / 4, 4)
            let ps = listStyle(for: level, markerWidth: 2)
            storage.addAttribute(.paragraphStyle, value: ps, range: lineRange)
            let markerLocation = lineStart + bullet.indentation.count
            switch bullet.marker {
            case "•":
                let bulletRange = NSRange(location: markerLocation, length: min(1, lineRange.length))
                storage.addAttribute(.foregroundColor, value: blueColor, range: bulletRange)
                storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 20), range: bulletRange)
            case "–":
                storage.addAttribute(.foregroundColor, value: dimColor,
                                     range: NSRange(location: markerLocation, length: min(2, max(0, lineRange.length - bullet.indentation.count))))
            case "○", "●":
                let checked = bullet.marker == "●"
                let circleRange = NSRange(location: markerLocation, length: min(1, lineRange.length))
                storage.addAttribute(.foregroundColor, value: checked ? greenColor : dimColor, range: circleRange)
                storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 19), range: circleRange)
                if checked && lineRange.length > bullet.indentation.count + 2 {
                    let textRange = NSRange(location: markerLocation + 2, length: lineRange.length - bullet.indentation.count - 2)
                    storage.addAttribute(.foregroundColor, value: dimColor, range: textRange)
                    storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: textRange)
                }
            default:
                break
            }
        } else if line == "---" || line == "***" || line == "___" {
            let block = NSTextBlock()
            block.backgroundColor = NSColor(hex: "#252a3d")
            let ps = NSMutableParagraphStyle()
            ps.textBlocks = [block]
            ps.minimumLineHeight = 1
            ps.maximumLineHeight = 1
            ps.paragraphSpacingBefore = 8
            ps.paragraphSpacing = 8
            storage.addAttribute(.paragraphStyle, value: ps, range: lineRange)
            storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 0.01), range: lineRange)
            storage.addAttribute(.foregroundColor, value: NSColor.clear, range: lineRange)
        }
    }

    private static func unorderedListMatch(in line: String) -> (indentation: String, marker: String)? {
        let indentation = String(line.prefix { $0 == " " || $0 == "\t" })
        let trimmed = String(line.dropFirst(indentation.count))
        let markers = ["• ", "– ", "○ ", "● "]
        guard let prefix = markers.first(where: { trimmed.hasPrefix($0) }) else { return nil }
        return (indentation, String(prefix.prefix(1)))
    }

    private static func orderedListMatch(in line: String) -> (indentation: String, marker: String)? {
        let indentation = String(line.prefix { $0 == " " || $0 == "\t" })
        let trimmed = String(line.dropFirst(indentation.count))
        guard let regex = try? NSRegularExpression(pattern: #"^((?:\d+|[A-Za-z]+|[ivxlcdmIVXLCDM]+)\.)\s"#),
              let match = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: (trimmed as NSString).length)) else {
            return nil
        }
        let marker = (trimmed as NSString).substring(with: match.range(at: 1))
        return (indentation, marker)
    }

    static func orderedMarker(for level: Int, index: Int) -> String {
        switch level {
        case 0, 3:
            return "\(index)."
        case 1, 4:
            let scalar = UnicodeScalar(96 + max(1, min(index, 26))) ?? "a"
            return "\(Character(scalar))."
        case 2:
            return intToRoman(index) + "."
        default:
            return "\(index)."
        }
    }

    static func romanToInt(_ roman: String) -> Int? {
        let values: [Character: Int] = ["i": 1, "v": 5, "x": 10, "l": 50, "c": 100, "d": 500, "m": 1000]
        var total = 0
        var previous = 0
        for character in roman.reversed() {
            guard let value = values[character] else { return nil }
            if value < previous {
                total -= value
            } else {
                total += value
                previous = value
            }
        }
        return total > 0 ? total : nil
    }

    static func intToRoman(_ number: Int) -> String {
        let values: [(Int, String)] = [
            (1000, "m"), (900, "cm"), (500, "d"), (400, "cd"),
            (100, "c"), (90, "xc"), (50, "l"), (40, "xl"),
            (10, "x"), (9, "ix"), (5, "v"), (4, "iv"), (1, "i")
        ]
        var remaining = max(1, number)
        var result = ""
        for (value, symbol) in values {
            while remaining >= value {
                result += symbol
                remaining -= value
            }
        }
        return result
    }

    private static func heading(_ storage: NSTextStorage, _ lineRange: NSRange, _ lineStart: Int, prefixLen: Int, size: CGFloat) {
        storage.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: size), range: lineRange)
        storage.addAttribute(.foregroundColor, value: textColor, range: lineRange)
        hide(storage, NSRange(location: lineStart, length: prefixLen))
    }

    private static func applyInline(
        storage: NSTextStorage,
        text: NSString,
        pattern: String,
        markerLen: Int,
        contentStyle: (NSRange, NSTextStorage) -> Void
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        regex.enumerateMatches(in: text as String, range: NSRange(location: 0, length: text.length)) { match, _, _ in
            guard let m = match, m.range.length > markerLen * 2 else { return }
            let full = m.range
            let open = NSRange(location: full.location, length: markerLen)
            let close = NSRange(location: full.location + full.length - markerLen, length: markerLen)
            let content = NSRange(location: full.location + markerLen, length: full.length - markerLen * 2)
            contentStyle(content, storage)
            hide(storage, open)
            hide(storage, close)
        }
    }

    private static func applyCode(_ storage: NSTextStorage, text: NSString) {
        guard let regex = try? NSRegularExpression(pattern: "`([^`\n]+)`") else { return }
        regex.enumerateMatches(in: text as String, range: NSRange(location: 0, length: text.length)) { match, _, _ in
            guard let m = match, m.range.length >= 3 else { return }
            let full = m.range
            let open = NSRange(location: full.location, length: 1)
            let close = NSRange(location: full.location + full.length - 1, length: 1)
            let content = NSRange(location: full.location + 1, length: full.length - 2)
            storage.addAttribute(.font, value: monoFont, range: content)
            storage.addAttribute(.backgroundColor, value: codeBackground, range: content)
            storage.addAttribute(.foregroundColor, value: greenColor, range: content)
            hide(storage, open)
            hide(storage, close)
        }
    }

    private static func hide(_ storage: NSTextStorage, _ range: NSRange) {
        guard range.length > 0 else { return }
        storage.addAttribute(.font, value: hiddenFont, range: range)
        storage.addAttribute(.foregroundColor, value: NSColor.clear, range: range)
    }

    static let baseParagraphStyle: NSParagraphStyle = {
        let ps = NSMutableParagraphStyle()
        ps.lineSpacing = 4
        return ps
    }()

    private static func listStyle(for level: Int, markerWidth: Int) -> NSParagraphStyle {
        let unit: CGFloat = 22
        let markerInset: CGFloat = 18
        let base = CGFloat(level) * unit
        let ps = NSMutableParagraphStyle()
        ps.firstLineHeadIndent = base + markerInset
        ps.headIndent = base + markerInset + CGFloat(markerWidth * 8)
        ps.lineSpacing = 4
        return ps
    }
}

extension NSColor {
    convenience init(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h = String(h.dropFirst()) }
        var rgb: UInt64 = 0
        Scanner(string: h).scanHexInt64(&rgb)
        let r = CGFloat((rgb >> 16) & 0xFF) / 255
        let g = CGFloat((rgb >> 8) & 0xFF) / 255
        let b = CGFloat(rgb & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}
#endif
