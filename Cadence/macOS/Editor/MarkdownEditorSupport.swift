#if os(macOS)
import AppKit

extension NSAttributedString.Key {
    static let cadenceMarkdownHidden = NSAttributedString.Key("CadenceMarkdownHidden")
    static let cadenceMarkdownDivider = NSAttributedString.Key("CadenceMarkdownDivider")
    static let cadenceMarkdownQuoteDepth = NSAttributedString.Key("CadenceMarkdownQuoteDepth")
}

enum MarkdownListPrefixKind {
    case bullet
    case dash
    case plus
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
    static func normalizedMarkdownListPrefixes(in text: String) -> String {
        var changed = false
        let lines = text.components(separatedBy: "\n").map { line -> String in
            guard let normalized = normalizedMarkdownListLine(line) else { return line }
            changed = true
            return normalized
        }
        return changed ? lines.joined(separator: "\n") : text
    }

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

    static func orderedLevel(forIndentation indentation: String) -> Int {
        min(normalizedIndentation(indentation).count / 4, 4)
    }

    static func visualLevel(forIndentation indentation: String) -> Int {
        let width = indentationWidth(indentation)
        guard width > 0 else { return 0 }
        return min(max(1, (width + 3) / 4), 4)
    }

    static func orderedIndex(for marker: String) -> Int? {
        let normalized = marker.trimmingCharacters(in: .whitespaces)
        let bare = normalized.hasSuffix(".") ? String(normalized.dropLast()) : normalized
        if let number = Int(bare) {
            return number
        }
        if let romanValue = MarkdownStylist.romanToInt(bare.lowercased()) {
            return romanValue
        }
        if bare.count == 1, let scalar = bare.lowercased().unicodeScalars.first,
           (97...122).contains(scalar.value) {
            return Int(scalar.value - 96)
        }
        return nil
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
            ("* ", .bullet, "* "),
            ("- ", .bullet, "- "),
            ("– ", .dash, "– "),
            ("+ ", .plus, "+ "),
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

        let updatedLevel = orderedLevel(forIndentation: updatedMatch.indentation)
        let targetIndex = orderedIndex(for: updatedMatch.marker) ?? 1
        let targetMarker = MarkdownStylist.orderedMarker(for: updatedLevel, index: targetIndex)
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

    private static func indentationWidth(_ indentation: String) -> Int {
        indentation.reduce(into: 0) { width, character in
            width += character == "\t" ? 4 : 1
        }
    }

    private static func normalizedMarkdownListLine(_ line: String) -> String? {
        let indentation = rawIndentation(in: line)
        let trimmed = String(line.dropFirst(indentation.count))
        guard !isMarkdownDividerLine(trimmed) else { return nil }

        guard let regex = try? NSRegularExpression(pattern: #"^([*+-])\s+(?:\[([ xX])\]\s+)?"#),
              let match = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: (trimmed as NSString).length)) else {
            return nil
        }

        let prefix = (trimmed as NSString).substring(with: match.range)
        let rest = String(trimmed.dropFirst(prefix.count))
        let checkboxRange = match.range(at: 2)
        if checkboxRange.location != NSNotFound {
            let state = (trimmed as NSString).substring(with: checkboxRange)
            return indentation + (state.lowercased() == "x" ? "● " : "○ ") + rest
        }

        return indentation + "• " + rest
    }

    private static func isMarkdownDividerLine(_ line: String) -> Bool {
        let compact = line
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { !$0.isWhitespace }
        guard compact.count >= 3 else { return false }
        return compact.allSatisfy { $0 == "-" } ||
            compact.allSatisfy { $0 == "*" } ||
            compact.allSatisfy { $0 == "_" }
    }
}

enum MarkdownHiddenRangeSupport {
    static func hiddenRange(containing location: Int, in storage: NSTextStorage?) -> NSRange? {
        guard let storage, storage.length > 0 else { return nil }
        let clamped = max(0, min(location, storage.length - 1))
        var effectiveRange = NSRange(location: NSNotFound, length: 0)
        let isHidden = (storage.attribute(.cadenceMarkdownHidden, at: clamped, effectiveRange: &effectiveRange) as? Bool) == true
        guard isHidden,
              effectiveRange.location != NSNotFound,
              effectiveRange.length > 0 else { return nil }
        return effectiveRange
    }

    static func snappedCaretLocation(_ location: Int, in storage: NSTextStorage?, preferringForward: Bool = true) -> Int {
        guard let storage else { return location }
        let length = storage.length
        guard length > 0 else { return 0 }

        if location < length, let hidden = hiddenRange(containing: location, in: storage) {
            return preferringForward ? NSMaxRange(hidden) : hidden.location
        }
        if location > 0, let hidden = hiddenRange(containing: location - 1, in: storage), location < NSMaxRange(hidden) {
            return preferringForward ? NSMaxRange(hidden) : hidden.location
        }
        return min(location, length)
    }

    static func nextVisibleCaretLocation(from location: Int, movingForward: Bool, in storage: NSTextStorage?) -> Int {
        guard let storage else { return location }
        let length = storage.length
        guard length > 0 else { return 0 }

        var candidate = min(max(location, 0), length)
        if movingForward {
            if candidate < length { candidate += 1 }
            while candidate < length {
                if let hidden = hiddenRange(containing: candidate, in: storage) {
                    candidate = NSMaxRange(hidden)
                } else {
                    break
                }
            }
            return min(candidate, length)
        } else {
            if candidate > 0 { candidate -= 1 }
            while candidate > 0 {
                if let hidden = hiddenRange(containing: candidate, in: storage) {
                    let nextCandidate = hidden.location
                    if nextCandidate >= candidate {
                        candidate -= 1
                    } else {
                        candidate = nextCandidate
                    }
                } else {
                    break
                }
            }
            return max(candidate, 0)
        }
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
                    pattern: "\\*\\*\\*(.+?)\\*\\*\\*", markerLen: 3,
                    contentStyle: { range, s in
                        let existing = s.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? baseFont
                        let italic = NSFontManager.shared.convert(existing, toHaveTrait: .italicFontMask)
                        s.addAttribute(.font, value: NSFontManager.shared.convert(italic, toHaveTrait: .boldFontMask), range: range)
                    })
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
        applyInline(storage: storage, text: nsText,
                    pattern: "==(.+?)==", markerLen: 2,
                    contentStyle: { range, s in
                        s.addAttribute(.backgroundColor, value: blueColor.withAlphaComponent(0.18), range: range)
                    })
        applyLinks(storage, text: nsText)
        applyWikiLinks(storage, text: nsText)
        applyCodeFences(storage, text: nsText)

        storage.endEditing()
    }

    private static func applyLine(storage: NSTextStorage, line: String, lineRange: NSRange, lineStart: Int) {
        if line.hasPrefix("###### ") {
            heading(storage, lineRange, lineStart, prefixLen: 7, size: 15)
        } else if line.hasPrefix("##### ") {
            heading(storage, lineRange, lineStart, prefixLen: 6, size: 17)
        } else if line.hasPrefix("#### ") {
            heading(storage, lineRange, lineStart, prefixLen: 5, size: 19)
        } else if line.hasPrefix("### ") {
            heading(storage, lineRange, lineStart, prefixLen: 4, size: 22)
        } else if line.hasPrefix("## ") {
            heading(storage, lineRange, lineStart, prefixLen: 3, size: 26)
        } else if line.hasPrefix("# ") {
            heading(storage, lineRange, lineStart, prefixLen: 2, size: 30)
        } else if let quote = blockquoteMatch(in: line) {
            let paragraph = NSMutableParagraphStyle()
            let levelInset = CGFloat(max(quote.depth - 1, 0)) * 12
            paragraph.lineSpacing = 4
            paragraph.firstLineHeadIndent = 18 + levelInset
            paragraph.headIndent = 18 + levelInset
            paragraph.paragraphSpacingBefore = 4
            paragraph.paragraphSpacing = 4

            storage.addAttribute(.paragraphStyle, value: paragraph, range: lineRange)
            storage.addAttribute(.cadenceMarkdownQuoteDepth, value: quote.depth, range: lineRange)
            hide(storage, NSRange(location: lineStart + quote.indentation.count, length: quote.prefix.count - quote.indentation.count))

            let restStart = lineStart + quote.prefix.count
            let rest = NSRange(location: restStart, length: max(0, lineRange.length - quote.prefix.count))
            if rest.length > 0 {
                storage.addAttribute(.foregroundColor, value: NSColor(hex: "#c4d4e8"), range: rest)
                let existing = storage.attribute(.font, at: rest.location, effectiveRange: nil) as? NSFont ?? baseFont
                let italic = NSFontManager.shared.convert(existing, toHaveTrait: .italicFontMask)
                storage.addAttribute(.font, value: italic, range: rest)
            }
        } else if let ordered = orderedListMatch(in: line) {
            let level = MarkdownListSupport.visualLevel(forIndentation: ordered.indentation)
            let ps = listStyle(for: level, markerWidth: ordered.marker.count + 1)
            storage.addAttribute(.paragraphStyle, value: ps, range: lineRange)
            let markerRange = NSRange(location: lineStart + ordered.indentation.count, length: min(ordered.marker.count, lineRange.length))
            storage.addAttribute(.foregroundColor, value: blueColor, range: markerRange)
            storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 13, weight: .semibold), range: markerRange)
        } else if let bullet = unorderedListMatch(in: line) {
            let level = MarkdownListSupport.visualLevel(forIndentation: bullet.indentation)
            let ps = listStyle(for: level, markerWidth: 2)
            storage.addAttribute(.paragraphStyle, value: ps, range: lineRange)
            let markerLocation = lineStart + bullet.indentation.count
            switch bullet.marker {
            case "•", "*":
                let bulletRange = NSRange(location: markerLocation, length: min(1, lineRange.length))
                storage.addAttribute(.foregroundColor, value: blueColor, range: bulletRange)
                storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 20), range: bulletRange)
            case "–", "-", "+":
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
        } else if isDividerLine(line) {
            let ps = NSMutableParagraphStyle()
            ps.alignment = .center
            ps.paragraphSpacingBefore = 8
            ps.paragraphSpacing = 8
            storage.addAttribute(.paragraphStyle, value: ps, range: lineRange)
            storage.addAttribute(.cadenceMarkdownDivider, value: true, range: lineRange)
            storage.addAttribute(.foregroundColor, value: NSColor.clear, range: lineRange)
        }
    }

    private static func unorderedListMatch(in line: String) -> (indentation: String, marker: String)? {
        let indentation = String(line.prefix { $0 == " " || $0 == "\t" })
        let trimmed = String(line.dropFirst(indentation.count))
        let markers = ["• ", "* ", "- ", "– ", "+ ", "○ ", "● "]
        guard let prefix = markers.first(where: { trimmed.hasPrefix($0) }) else { return nil }
        return (indentation, String(prefix.prefix(1)))
    }

    private static func blockquoteMatch(in line: String) -> (indentation: String, prefix: String, depth: Int)? {
        guard let regex = try? NSRegularExpression(pattern: #"^([ \t]*)(>\s*)+"#),
              let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) else {
            return nil
        }

        let prefixRange = match.range(at: 0)
        let indentationRange = match.range(at: 1)
        let nsLine = line as NSString
        let indentation = indentationRange.location != NSNotFound ? nsLine.substring(with: indentationRange) : ""
        let prefix = nsLine.substring(with: prefixRange)
        let depth = prefix.filter { $0 == ">" }.count
        return depth > 0 ? (indentation, prefix, depth) : nil
    }

    private static func isDividerLine(_ line: String) -> Bool {
        let trimmed = line
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { !$0.isWhitespace }
        guard trimmed.count >= 3 else { return false }
        return trimmed.allSatisfy { $0 == "-" } ||
            trimmed.allSatisfy { $0 == "*" } ||
            trimmed.allSatisfy { $0 == "_" }
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
        let markerRange = NSRange(location: lineStart, length: min(prefixLen, lineRange.length))
        let contentLength = max(0, lineRange.length - prefixLen)
        let contentRange = NSRange(location: lineStart + prefixLen, length: contentLength)
        let content = contentLength > 0 ? (storage.string as NSString).substring(with: contentRange) : ""
        let hasVisibleContent = !content.trimmingCharacters(in: .whitespaces).isEmpty

        guard hasVisibleContent else {
            storage.addAttribute(.font, value: baseFont, range: lineRange)
            storage.addAttribute(.foregroundColor, value: dimColor, range: markerRange)
            storage.addAttribute(.paragraphStyle, value: baseParagraphStyle, range: lineRange)
            return
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.firstLineHeadIndent = 0
        paragraph.headIndent = 0
        paragraph.paragraphSpacingBefore = 4
        paragraph.paragraphSpacing = 4

        storage.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: size), range: lineRange)
        storage.addAttribute(.foregroundColor, value: textColor, range: lineRange)
        storage.addAttribute(.paragraphStyle, value: paragraph, range: lineRange)
        hide(storage, markerRange)
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

    private static func applyLinks(_ storage: NSTextStorage, text: NSString) {
        guard let regex = try? NSRegularExpression(pattern: #"(?<!\!)\[(.+?)\]\((.+?)\)"#) else { return }
        regex.enumerateMatches(in: text as String, range: NSRange(location: 0, length: text.length)) { match, _, _ in
            guard let match, match.numberOfRanges >= 3 else { return }

            let labelRange = match.range(at: 1)
            let urlRange = match.range(at: 2)
            let fullRange = match.range(at: 0)
            guard labelRange.location != NSNotFound, urlRange.location != NSNotFound else { return }

            storage.addAttribute(.foregroundColor, value: blueColor, range: labelRange)
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: labelRange)
            storage.addAttribute(.foregroundColor, value: dimColor, range: urlRange)
            storage.addAttribute(.font, value: monoFont, range: urlRange)

            let hiddenRanges = [
                NSRange(location: fullRange.location, length: 1),
                NSRange(location: labelRange.location + labelRange.length, length: 2),
                NSRange(location: urlRange.location + urlRange.length, length: 1)
            ]
            hiddenRanges.forEach { hide(storage, $0) }
        }
    }

    private static func applyWikiLinks(_ storage: NSTextStorage, text: NSString) {
        guard let regex = try? NSRegularExpression(pattern: #"\[\[([^\[\]]+?)\]\]"#) else { return }
        regex.enumerateMatches(in: text as String, range: NSRange(location: 0, length: text.length)) { match, _, _ in
            guard let match, match.numberOfRanges >= 2 else { return }
            let fullRange = match.range(at: 0)
            let labelRange = match.range(at: 1)
            guard labelRange.location != NSNotFound else { return }

            let label = text.substring(with: labelRange).trimmingCharacters(in: .whitespacesAndNewlines)
            let isTaskReference = label.lowercased().hasPrefix("task:")

            storage.addAttribute(.foregroundColor, value: isTaskReference ? greenColor : blueColor, range: labelRange)
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: labelRange)
            if isTaskReference {
                storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 13, weight: .semibold), range: labelRange)
            }

            hide(storage, NSRange(location: fullRange.location, length: 2))
            hide(storage, NSRange(location: fullRange.location + fullRange.length - 2, length: 2))
        }
    }

    private static func applyCodeFences(_ storage: NSTextStorage, text: NSString) {
        guard let regex = try? NSRegularExpression(pattern: #"(?s)```([^\n`]*)\n(.*?)\n?```"#) else { return }
        regex.enumerateMatches(in: text as String, range: NSRange(location: 0, length: text.length)) { match, _, _ in
            guard let match, match.numberOfRanges >= 3 else { return }

            let fullRange = match.range(at: 0)
            let languageRange = match.range(at: 1)
            let codeRange = match.range(at: 2)

            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 4
            paragraph.firstLineHeadIndent = 14
            paragraph.headIndent = 14
            paragraph.paragraphSpacingBefore = 6
            paragraph.paragraphSpacing = 6

            storage.addAttributes([
                .font: monoFont,
                .foregroundColor: greenColor,
                .backgroundColor: codeBackground,
                .paragraphStyle: paragraph
            ], range: codeRange)

            if languageRange.location != NSNotFound, languageRange.length > 0 {
                storage.addAttribute(.foregroundColor, value: dimColor, range: languageRange)
                storage.addAttribute(.font, value: monoFont, range: languageRange)
            }

            let snippet = text.substring(with: fullRange)
            guard let firstFenceRange = snippet.range(of: "```"),
                  let lastFenceRange = snippet.range(of: "```", options: .backwards) else { return }

            let firstFenceLocation = fullRange.location + snippet.distance(from: snippet.startIndex, to: firstFenceRange.lowerBound)
            let lastFenceLocation = fullRange.location + snippet.distance(from: snippet.startIndex, to: lastFenceRange.lowerBound)
            hide(storage, NSRange(location: firstFenceLocation, length: 3))
            hide(storage, NSRange(location: lastFenceLocation, length: 3))
        }
    }

    private static func hide(_ storage: NSTextStorage, _ range: NSRange) {
        guard range.length > 0 else { return }
        storage.addAttribute(.cadenceMarkdownHidden, value: true, range: range)
        storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 0.1), range: range)
        storage.addAttribute(.foregroundColor, value: NSColor.clear, range: range)
        storage.removeAttribute(.kern, range: range)
    }

    static let baseParagraphStyle: NSParagraphStyle = {
        let ps = NSMutableParagraphStyle()
        ps.lineSpacing = 4
        return ps
    }()

    private static func listStyle(for level: Int, markerWidth: Int) -> NSParagraphStyle {
        let unit: CGFloat = 12
        let markerInset: CGFloat = 8
        let base = CGFloat(level) * unit
        let ps = NSMutableParagraphStyle()
        ps.firstLineHeadIndent = base + markerInset
        ps.headIndent = base + markerInset + CGFloat(Double(markerWidth) * 5.5)
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
