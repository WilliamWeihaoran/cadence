import Foundation

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

struct MarkdownListLineInfo: Equatable {
    let kind: MarkdownListPrefixKind
    let indentation: String
    let marker: String
    let markerRange: NSRange
    let contentRange: NSRange
    let prefixRange: NSRange
    let visualLevel: Int
    let markerWidth: Int

    var contentStart: Int {
        contentRange.location
    }
}

struct MarkdownListNormalizationResult: Equatable {
    let text: String
    let selection: NSRange
}

struct MarkdownListIndentationResult: Equatable {
    let text: String
    let selection: NSRange
    let replacementRange: NSRange
    let replacement: String
}

enum MarkdownListSupport {
    private static let orderedMarkerRegex = try! NSRegularExpression(pattern: #"^((?:\d+|[A-Za-z]+|[ivxlcdmIVXLCDM]+)[.)])\s"#)
    private static let bulletCheckboxRegex = try! NSRegularExpression(pattern: #"^([*+-])\s+(?:\[([ xX])\]\s+)?"#)

    static func normalizedMarkdownListPrefixes(in text: String) -> String {
        normalizedMarkdownListPrefixes(in: text, selection: NSRange(location: 0, length: 0)).text
    }

    static func normalizedMarkdownListPrefixes(in text: String, selection: NSRange) -> MarkdownListNormalizationResult {
        let originalLines = text.components(separatedBy: "\n")
        var changed = false
        let normalizedLines = originalLines.map { line -> String in
            guard let normalized = normalizedMarkdownListLine(line) else { return line }
            changed = true
            return normalized
        }

        guard changed else {
            return MarkdownListNormalizationResult(text: text, selection: clampedSelection(selection, in: text))
        }

        let normalizedText = normalizedLines.joined(separator: "\n")
        let adjustedStart = adjustedOffset(
            selection.location,
            originalLines: originalLines,
            normalizedLines: normalizedLines,
            normalizedTextLength: (normalizedText as NSString).length
        )
        let adjustedEnd = adjustedOffset(
            NSMaxRange(selection),
            originalLines: originalLines,
            normalizedLines: normalizedLines,
            normalizedTextLength: (normalizedText as NSString).length
        )
        return MarkdownListNormalizationResult(
            text: normalizedText,
            selection: NSRange(location: adjustedStart, length: max(0, adjustedEnd - adjustedStart))
        )
    }

    static func continuation(after line: String) -> String? {
        guard let match = listPrefixMatch(in: line) else { return nil }
        switch match.kind {
        case .todo, .done:
            return match.indentation + "○ "
        case .bullet, .dash, .plus:
            return match.indentation + "• "
        case .ordered:
            return match.indentation + nextOrderedMarker(after: match.marker) + " "
        }
    }

    static func adjustedListIndentation(
        in text: String,
        selection: NSRange,
        increase: Bool
    ) -> MarkdownListIndentationResult? {
        let nsText = text as NSString
        let safeSelection = clampedSelection(selection, in: text)
        let targetRange = effectiveLineRange(for: safeSelection, in: nsText)
        guard targetRange.location != NSNotFound,
              targetRange.location <= nsText.length,
              NSMaxRange(targetRange) <= nsText.length else {
            return nil
        }

        let original = nsText.substring(with: targetRange)
        let lines = original.components(separatedBy: "\n")
        var changed = false
        let updatedLines = lines.map { line -> String in
            guard let prefixMatch = listPrefixMatch(in: line) else { return line }

            if increase {
                changed = true
                let indentedLine = String(repeating: " ", count: 4) + line
                return remapOrderedMarkerIfNeeded(in: indentedLine, originalMatch: prefixMatch)
            }

            let indentation = rawIndentation(in: line)
            let normalizedIndentWidth = indentationWidth(indentation)
            if normalizedIndentWidth == 0 {
                changed = true
                return String(line.dropFirst(prefixMatch.prefix.count))
            }

            let charactersToDrop: Int
            if indentation.first == "\t" {
                charactersToDrop = 1
            } else {
                charactersToDrop = min(4, indentation.count)
            }

            changed = true
            let outdentedLine = String(line.dropFirst(charactersToDrop))
            return remapOrderedMarkerIfNeeded(in: outdentedLine, originalMatch: prefixMatch)
        }

        guard changed else { return nil }

        let replacement = updatedLines.joined(separator: "\n")
        let updatedText = nsText.replacingCharacters(in: targetRange, with: replacement)
        let replacementLength = (replacement as NSString).length
        let targetDelta = replacementLength - targetRange.length
        let selectionOffset = increase ? 4 : -min(4, safeSelection.location - targetRange.location)

        let updatedSelection: NSRange
        if safeSelection.length == 0 {
            let originalCaretOffset = max(0, safeSelection.location - targetRange.location)
            let originalFirstLine = String(original.split(separator: "\n", omittingEmptySubsequences: false).first ?? "")
            let replacementFirstLine = String(replacement.split(separator: "\n", omittingEmptySubsequences: false).first ?? "")

            if !originalFirstLine.isEmpty,
               let originalPrefix = listPrefixMatch(in: originalFirstLine),
               let updatedPrefix = listPrefixMatch(in: replacementFirstLine) {
                let originalPrefixLength = originalPrefix.prefix.count
                let updatedPrefixLength = updatedPrefix.prefix.count
                let adjustedOffset: Int
                if originalCaretOffset <= originalPrefixLength {
                    adjustedOffset = updatedPrefixLength
                } else {
                    adjustedOffset = min(
                        replacementLength,
                        max(updatedPrefixLength, originalCaretOffset + targetDelta)
                    )
                }
                updatedSelection = NSRange(location: targetRange.location + adjustedOffset, length: 0)
            } else {
                let adjustedOffset = max(0, min(replacementLength, originalCaretOffset + selectionOffset))
                updatedSelection = NSRange(location: targetRange.location + adjustedOffset, length: 0)
            }
        } else {
            updatedSelection = NSRange(
                location: max(targetRange.location, safeSelection.location + selectionOffset),
                length: max(0, safeSelection.length + targetDelta)
            )
        }

        return MarkdownListIndentationResult(
            text: updatedText,
            selection: clampedSelection(updatedSelection, in: updatedText),
            replacementRange: targetRange,
            replacement: replacement
        )
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
        return orderedMarker(for: level, index: 1)
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
        let bare = normalized.hasSuffix(".") || normalized.hasSuffix(")") ? String(normalized.dropLast()) : normalized
        if let number = Int(bare) {
            return number
        }
        if let romanValue = romanToInt(bare.lowercased()) {
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
        let delimiter = normalized.hasSuffix(")") ? ")" : "."
        let bare = normalized.hasSuffix(".") || normalized.hasSuffix(")") ? String(normalized.dropLast()) : normalized
        if let number = Int(bare) {
            return "\(number + 1)\(delimiter)"
        }
        if let romanValue = romanToInt(bare.lowercased()) {
            let next = intToRoman(romanValue + 1)
            return bare.first?.isUppercase == true ? "\(next.uppercased())\(delimiter)" : "\(next)\(delimiter)"
        }
        if bare.count == 1, let scalar = bare.unicodeScalars.first {
            let value = scalar.value
            if (65...90).contains(value), let next = UnicodeScalar(min(value + 1, 90)) {
                return String(next).lowercased() + delimiter
            }
            if (97...122).contains(value), let next = UnicodeScalar(min(value + 1, 122)) {
                return String(next) + delimiter
            }
        }
        return marker
    }

    static func listPrefixMatch(in line: String) -> MarkdownListPrefixMatch? {
        let indentation = rawIndentation(in: line)
        let trimmed = String(line.dropFirst(indentation.count))

        if let checklist = MarkdownChecklistSupport.lineInfo(in: line) {
            let marker = (line as NSString).substring(with: checklist.stateRange)
            return MarkdownListPrefixMatch(
                kind: checklist.isDone ? .done : .todo,
                indentation: indentation,
                marker: marker,
                prefix: (line as NSString).substring(with: checklist.markerRange)
            )
        }

        let simplePrefixes: [(String, MarkdownListPrefixKind, String)] = [
            ("• ", .bullet, "• "),
            ("* ", .bullet, "* "),
            ("- ", .bullet, "- "),
            ("– ", .dash, "– "),
            ("+ ", .plus, "+ ")
        ]
        for (prefix, kind, marker) in simplePrefixes where trimmed.hasPrefix(prefix) {
            return MarkdownListPrefixMatch(kind: kind, indentation: indentation, marker: marker, prefix: indentation + prefix)
        }

        guard let match = orderedMarkerRegex.firstMatch(in: trimmed, range: NSRange(location: 0, length: (trimmed as NSString).length)) else {
            return nil
        }

        let markerRange = match.range(at: 1)
        let marker = (trimmed as NSString).substring(with: markerRange)
        let prefix = indentation + (trimmed as NSString).substring(with: NSRange(location: 0, length: match.range.length))
        return MarkdownListPrefixMatch(kind: .ordered, indentation: indentation, marker: marker, prefix: prefix)
    }

    static func lineInfo(in line: String) -> MarkdownListLineInfo? {
        let nsLine = line as NSString
        let indentation = rawIndentation(in: line)
        let indentationLength = (indentation as NSString).length

        if let checklist = MarkdownChecklistSupport.lineInfo(in: line) {
            let marker = nsLine.substring(with: checklist.stateRange)
            let usesLegacyMarker = ["○", "●", "✓"].contains(marker)
            let markerRange = usesLegacyMarker
                ? checklist.stateRange
                : NSRange(
                    location: indentationLength,
                    length: max(0, NSMaxRange(checklist.markerRange) - indentationLength)
                )

            return MarkdownListLineInfo(
                kind: checklist.isDone ? .done : .todo,
                indentation: indentation,
                marker: marker,
                markerRange: markerRange,
                contentRange: checklist.contentRange,
                prefixRange: checklist.markerRange,
                visualLevel: visualLevel(forIndentation: indentation),
                markerWidth: 2
            )
        }

        let trimmed = String(line.dropFirst(indentation.count))
        let nsTrimmed = trimmed as NSString
        let simplePrefixes: [(String, MarkdownListPrefixKind, String, Int)] = [
            ("• ", .bullet, "•", 2),
            ("* ", .bullet, "*", 2),
            ("- ", .bullet, "-", 2),
            ("– ", .dash, "–", 2),
            ("+ ", .plus, "+", 2)
        ]
        for (prefix, kind, marker, markerWidth) in simplePrefixes where trimmed.hasPrefix(prefix) {
            let prefixLength = (prefix as NSString).length
            return MarkdownListLineInfo(
                kind: kind,
                indentation: indentation,
                marker: marker,
                markerRange: NSRange(location: indentationLength, length: (marker as NSString).length),
                contentRange: NSRange(location: indentationLength + prefixLength, length: max(0, nsLine.length - indentationLength - prefixLength)),
                prefixRange: NSRange(location: 0, length: indentationLength + prefixLength),
                visualLevel: visualLevel(forIndentation: indentation),
                markerWidth: markerWidth
            )
        }

        guard let match = orderedMarkerRegex.firstMatch(in: trimmed, range: NSRange(location: 0, length: nsTrimmed.length)) else {
            return nil
        }

        let markerRange = match.range(at: 1)
        guard markerRange.location != NSNotFound else { return nil }
        let marker = nsTrimmed.substring(with: markerRange)
        let prefixLength = match.range.length
        return MarkdownListLineInfo(
            kind: .ordered,
            indentation: indentation,
            marker: marker,
            markerRange: NSRange(location: indentationLength + markerRange.location, length: markerRange.length),
            contentRange: NSRange(location: indentationLength + prefixLength, length: max(0, nsLine.length - indentationLength - prefixLength)),
            prefixRange: NSRange(location: 0, length: indentationLength + prefixLength),
            visualLevel: visualLevel(forIndentation: indentation),
            markerWidth: marker.count + 1
        )
    }

    static func remapOrderedMarkerIfNeeded(in line: String, originalMatch: MarkdownListPrefixMatch) -> String {
        guard originalMatch.kind == .ordered,
              let updatedMatch = listPrefixMatch(in: line) else { return line }

        let updatedLevel = orderedLevel(forIndentation: updatedMatch.indentation)
        let targetIndex = orderedIndex(for: updatedMatch.marker) ?? 1
        let targetMarker = orderedMarker(for: updatedLevel, index: targetIndex)
        guard updatedMatch.marker != targetMarker else { return line }

        let indentationCount = updatedMatch.indentation.count
        let markerStart = line.index(line.startIndex, offsetBy: indentationCount)
        let markerEnd = line.index(markerStart, offsetBy: updatedMatch.marker.count)
        return String(line[..<markerStart]) + targetMarker + String(line[markerEnd...])
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

    private static func clampedSelection(_ selection: NSRange, in text: String) -> NSRange {
        let length = (text as NSString).length
        let location = min(max(0, selection.location), length)
        return NSRange(location: location, length: min(selection.length, max(0, length - location)))
    }

    private static func effectiveLineRange(for selection: NSRange, in text: NSString) -> NSRange {
        guard text.length > 0 else { return NSRange(location: 0, length: 0) }

        let startLocation = min(max(selection.location, 0), text.length - 1)
        let startLine = text.lineRange(for: NSRange(location: startLocation, length: 0))

        if selection.length == 0 {
            return startLine
        }

        let rawEnd = NSMaxRange(selection)
        let endLocation: Int
        if rawEnd > selection.location,
           rawEnd <= text.length,
           text.character(at: rawEnd - 1) == 10 {
            endLocation = max(selection.location, rawEnd - 1)
        } else {
            endLocation = min(max(selection.location, rawEnd), text.length - 1)
        }

        let endLine = text.lineRange(for: NSRange(location: endLocation, length: 0))
        return NSUnionRange(startLine, endLine)
    }

    private static func adjustedOffset(
        _ offset: Int,
        originalLines: [String],
        normalizedLines: [String],
        normalizedTextLength: Int
    ) -> Int {
        var runningOriginal = 0
        var runningNormalized = 0

        for (originalLine, normalizedLine) in zip(originalLines, normalizedLines) {
            let originalLength = (originalLine as NSString).length
            let normalizedLength = (normalizedLine as NSString).length
            if offset <= runningOriginal + originalLength {
                let offsetWithinLine = max(0, offset - runningOriginal)
                let delta = normalizedLength - originalLength
                return min(
                    normalizedTextLength,
                    max(0, runningNormalized + min(normalizedLength, max(0, offsetWithinLine + delta)))
                )
            }
            runningOriginal += originalLength + 1
            runningNormalized += normalizedLength + 1
        }

        return min(normalizedTextLength, max(0, offset))
    }

    private static func normalizedMarkdownListLine(_ line: String) -> String? {
        let indentation = rawIndentation(in: line)
        let trimmed = String(line.dropFirst(indentation.count))
        guard !isMarkdownDividerLine(trimmed) else { return nil }
        if trimmed.hasPrefix("● ") {
            return indentation + "✓ " + String(trimmed.dropFirst(2))
        }

        guard let match = bulletCheckboxRegex.firstMatch(in: trimmed, range: NSRange(location: 0, length: (trimmed as NSString).length)) else {
            return nil
        }

        let prefix = (trimmed as NSString).substring(with: match.range)
        let rest = String(trimmed.dropFirst(prefix.count))
        let checkboxRange = match.range(at: 2)
        if checkboxRange.location != NSNotFound {
            let state = (trimmed as NSString).substring(with: checkboxRange)
            return indentation + (state.lowercased() == "x" ? "✓ " : "○ ") + rest
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
