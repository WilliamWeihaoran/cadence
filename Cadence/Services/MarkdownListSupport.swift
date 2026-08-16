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
    /// Which checklist spelling the line uses, or nil when it is not a checklist at all.
    ///
    /// A `.todo`/`.done` kind alone does not say: `- [x] ` and `✓ ` are the same kind of item
    /// written two ways, and they render differently — the GitHub form hides a six-character
    /// prefix and draws a box, the legacy form styles one visible glyph. Callers used to tell them
    /// apart by testing `marker` against a `["○", "●", "✓"]` literal at each site.
    let checklistSyntax: MarkdownChecklistSyntax?

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
    /// Lettered markers are a *single* letter ("a.", "b."); anything longer has to spell a roman
    /// numeral. Allowing any run of letters turned every "Mr. ", "Fig. " and "Note. " at the left
    /// margin into a list item.
    static let orderedMarkerPattern = #"(?:\d+|[A-Za-z]|[ivxlcdmIVXLCDM]+)[.)]"#

    /// Every character Cadence accepts as an unordered list marker: markdown's own `- * +`, plus
    /// the `• ◦ ▪` glyphs `unorderedMarker(forLevel:)` emits and the `–` some notes carry.
    ///
    /// It is a shared constant because `MarkdownChecklistSupport` has to agree with it. `- ` is
    /// rewritten to `• ` the instant it is typed, so a checkbox typed into a Cadence list is
    /// almost never spelled `- [x] ` on disk — it is `• [x] `, and a checklist matcher that only
    /// knows `[-*+]` reads that as a plain bullet with a literal `[x]` after it.
    static let unorderedMarkerCharacters = "-*+•◦▪–"

    private static let orderedMarkerRegex = try! NSRegularExpression(pattern: #"^("# + orderedMarkerPattern + #")\s"#)
    private static let bulletCheckboxRegex = try! NSRegularExpression(pattern: #"^([*+-])\s+(?:\[([ xX])\]\s+)?"#)

    /// Renumbers ordered-list markers so each run reads 1, 2, 3… at every nesting level.
    ///
    /// This lived in `macOS/Editor/MarkdownEditorInteractionSupport` as a complete renumbering
    /// algorithm — level counters, level-transition resets, counter pruning, marker substitution —
    /// running on every keystroke with no tests and no iOS equivalent, which is why ordered lists
    /// renumber on macOS and not on iOS. `macOS/Editor/AGENTS.md` says markdown logic belongs
    /// here, so here it is, shaped exactly like `normalizedMarkdownListPrefixes` above and sharing
    /// its caret adjustment rather than the near-clone with different clamping it used to carry.
    static func normalizedOrderedListMarkers(in text: String, selection: NSRange) -> MarkdownListNormalizationResult {
        let originalLines = text.components(separatedBy: "\n")
        var rebuiltLines: [String] = []
        var counters: [Int: Int] = [:]
        var previousOrderedLevel: Int?
        var changed = false

        for line in originalLines {
            guard let match = listPrefixMatch(in: line), match.kind == .ordered else {
                rebuiltLines.append(line)
                // Any non-ordered line ends the run, so the next one starts at 1 again.
                counters.removeAll()
                previousOrderedLevel = nil
                continue
            }

            let level = orderedLevel(forIndentation: match.indentation)
            let nextIndex: Int
            if let previousOrderedLevel {
                nextIndex = level > previousOrderedLevel ? 1 : (counters[level] ?? 0) + 1
            } else {
                nextIndex = 1
            }

            // Drop the deeper levels: a sublist that has been left restarts if it comes back.
            counters = counters.filter { $0.key <= level }
            counters[level] = nextIndex
            previousOrderedLevel = level

            let expectedMarker = orderedMarker(for: level, index: nextIndex)
            guard match.marker != expectedMarker else {
                rebuiltLines.append(line)
                continue
            }

            let markerStart = line.index(line.startIndex, offsetBy: match.indentation.count)
            let markerEnd = line.index(markerStart, offsetBy: match.marker.count)
            rebuiltLines.append(String(line[..<markerStart]) + expectedMarker + String(line[markerEnd...]))
            changed = true
        }

        guard changed else {
            return MarkdownListNormalizationResult(text: text, selection: clampedSelection(selection, in: text))
        }

        let rebuiltText = rebuiltLines.joined(separator: "\n")
        let rebuiltLength = (rebuiltText as NSString).length
        let adjustedStart = adjustedOffset(
            selection.location,
            originalLines: originalLines,
            normalizedLines: rebuiltLines,
            normalizedTextLength: rebuiltLength
        )
        let adjustedEnd = adjustedOffset(
            NSMaxRange(selection),
            originalLines: originalLines,
            normalizedLines: rebuiltLines,
            normalizedTextLength: rebuiltLength
        )
        return MarkdownListNormalizationResult(
            text: rebuiltText,
            selection: NSRange(location: adjustedStart, length: max(0, adjustedEnd - adjustedStart))
        )
    }

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
                return remapListMarkerIfNeeded(in: indentedLine, originalMatch: prefixMatch)
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
            return remapListMarkerIfNeeded(in: outdentedLine, originalMatch: prefixMatch)
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
        orderedMarker(for: orderedLevel(forIndentation: indentation), index: 1)
    }

    static func orderedLevel(forIndentation indentation: String) -> Int {
        min(normalizedIndentation(indentation).count / 4, 4)
    }

    static func visualLevel(forIndentation indentation: String) -> Int {
        let width = indentationWidth(indentation)
        guard width > 0 else { return 0 }
        return min(max(1, (width + 3) / 4), 4)
    }

    /// `c`, `d`, `i`, `l`, `m`, `v` and `x` are both list letters and roman numerals, so a lone
    /// letter is ambiguous: "c." is the third item of an `a. b. c.` list and also roman 100.
    /// Three things can settle it, in descending order of how much they actually know:
    ///   1. the marker directly above it in the same run — "b." before "c." means letters, "iv."
    ///      before "v." means roman, because only one reading continues the count;
    ///   2. the level's own alphabet, at the levels that have one;
    ///   3. failing both, "i." — the one lone letter a hand-written outline plausibly opens with,
    ///      where every other lone letter reads as a lettered list.
    /// Level alone is not enough: it says nothing at the numeric levels, which is where both an
    /// `a. b. c.` list and an `i. ii. iii.` outline get written.
    private static func readsAsRomanNumeral(
        _ bare: String,
        atLevel level: Int?,
        precededBy previousMarker: String?
    ) -> Bool {
        guard let roman = romanToInt(bare.lowercased()) else { return false }
        guard let letter = letterIndex(for: bare) else { return true }

        if let previousMarker, let previousIndex = orderedIndex(for: previousMarker, atLevel: level) {
            if previousIndex + 1 == letter { return false }
            if previousIndex + 1 == roman { return true }
        }
        if let levelPrefersRoman = levelAlphabetPrefersRomanNumerals(level) {
            return levelPrefersRoman
        }
        return bare.lowercased() == "i"
    }

    /// Whether a level's own markers are roman ("i.") or letters ("a."); nil at the numeric
    /// levels, where neither alphabet is native and the level is no evidence either way.
    private static func levelAlphabetPrefersRomanNumerals(_ level: Int?) -> Bool? {
        guard let level else { return nil }
        switch orderedMarker(for: level, index: 1) {
        case "i.": return true
        case "a.": return false
        default: return nil
        }
    }

    private static func letterIndex(for bare: String) -> Int? {
        guard bare.count == 1, let scalar = bare.lowercased().unicodeScalars.first,
              (97...122).contains(scalar.value) else {
            return nil
        }
        return Int(scalar.value - 96)
    }

    private static func bareMarker(_ marker: String) -> String {
        let normalized = marker.trimmingCharacters(in: .whitespaces)
        return normalized.hasSuffix(".") || normalized.hasSuffix(")") ? String(normalized.dropLast()) : normalized
    }

    /// The marker the line at `lineRange` is continuing from: the closest ordered item above it at
    /// the same indentation level, stepping over any nested sublist between them. A run ends at the
    /// first line that is not an ordered item, so anything above that belongs to a different list.
    static func precedingOrderedMarker(in text: NSString, before lineRange: NSRange, atLevel level: Int) -> String? {
        var location = min(max(0, lineRange.location), text.length)
        while location > 0 {
            let previousRange = text.lineRange(for: NSRange(location: location - 1, length: 0))
            let previousLine = text.substring(with: previousRange).trimmingCharacters(in: .newlines)
            guard let match = listPrefixMatch(in: previousLine), match.kind == .ordered else { return nil }
            let previousLevel = orderedLevel(forIndentation: match.indentation)
            if previousLevel == level { return match.marker }
            if previousLevel < level { return nil }
            location = previousRange.location
        }
        return nil
    }

    static func orderedIndex(for marker: String, atLevel level: Int? = nil, precededBy previousMarker: String? = nil) -> Int? {
        let bare = bareMarker(marker)
        if let number = Int(bare) {
            return number
        }
        if readsAsRomanNumeral(bare, atLevel: level, precededBy: previousMarker) {
            return romanToInt(bare.lowercased())
        }
        return letterIndex(for: bare) ?? romanToInt(bare.lowercased())
    }

    static func nextOrderedMarker(after marker: String, atLevel level: Int? = nil, precededBy previousMarker: String? = nil) -> String {
        let normalized = marker.trimmingCharacters(in: .whitespaces)
        let delimiter = normalized.hasSuffix(")") ? ")" : "."
        let bare = bareMarker(normalized)
        if let number = Int(bare) {
            return "\(number + 1)\(delimiter)"
        }
        if !readsAsRomanNumeral(bare, atLevel: level, precededBy: previousMarker),
           let next = nextLetterMarker(after: bare, delimiter: delimiter) {
            return next
        }
        if let romanValue = romanToInt(bare.lowercased()) {
            let next = intToRoman(romanValue + 1)
            return bare.first?.isUppercase == true ? "\(next.uppercased())\(delimiter)" : "\(next)\(delimiter)"
        }
        return nextLetterMarker(after: bare, delimiter: delimiter) ?? marker
    }

    private static func nextLetterMarker(after bare: String, delimiter: String) -> String? {
        guard bare.count == 1, let scalar = bare.unicodeScalars.first else { return nil }
        let value = scalar.value
        if (65...90).contains(value), let next = UnicodeScalar(min(value + 1, 90)) {
            return String(next).lowercased() + delimiter
        }
        if (97...122).contains(value), let next = UnicodeScalar(min(value + 1, 122)) {
            return String(next) + delimiter
        }
        return nil
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
            ("◦ ", .bullet, "◦ "),
            ("▪ ", .bullet, "▪ "),
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
            let markerRange = checklist.syntax == .legacy
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
                markerWidth: 2,
                checklistSyntax: checklist.syntax
            )
        }

        let trimmed = String(line.dropFirst(indentation.count))
        let nsTrimmed = trimmed as NSString
        let simplePrefixes: [(String, MarkdownListPrefixKind, String, Int)] = [
            ("• ", .bullet, "•", 2),
            ("◦ ", .bullet, "◦", 2),
            ("▪ ", .bullet, "▪", 2),
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
                markerWidth: markerWidth,
                checklistSyntax: nil
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
            markerWidth: marker.count + 1,
            checklistSyntax: nil
        )
    }

    static func remapListMarkerIfNeeded(in line: String, originalMatch: MarkdownListPrefixMatch) -> String {
        guard let updatedMatch = listPrefixMatch(in: line) else { return line }

        let targetMarker: String
        switch originalMatch.kind {
        case .ordered:
            let updatedLevel = orderedLevel(forIndentation: updatedMatch.indentation)
            // The marker still belongs to the level the line came *from*, so that is the alphabet
            // it has to be read in before being rewritten into the new level's.
            let originalLevel = orderedLevel(forIndentation: originalMatch.indentation)
            let targetIndex = orderedIndex(for: updatedMatch.marker, atLevel: originalLevel) ?? 1
            targetMarker = orderedMarker(for: updatedLevel, index: targetIndex)
        case .bullet, .dash, .plus:
            // Unlike the ordered marker (e.g. "1.", no trailing space), listPrefixMatch's
            // bullet marker already includes the trailing space (e.g. "• ") — the
            // replacement must match that shape or the splice below drops the space.
            let updatedLevel = visualLevel(forIndentation: updatedMatch.indentation)
            targetMarker = unorderedMarker(forLevel: updatedLevel) + " "
        case .todo, .done:
            return line
        }
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

    static func unorderedMarker(forLevel level: Int) -> String {
        switch level % 3 {
        case 0: return "•"
        case 1: return "◦"
        default: return "▪"
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

        // A GitHub checkbox (`- [x] `) is left exactly as written. It used to be rewritten into
        // Cadence's own `✓ ` glyph on the keystroke after it appeared, which meant markdown pasted
        // in from anywhere else lost its checkboxes on arrival and markdown exported out could
        // never carry them — the whole point of the syntax is that it round-trips. Both platforms
        // now render it as a checkbox in place, so there is nothing left for the rewrite to buy.
        guard match.range(at: 2).location == NSNotFound else { return nil }

        let prefix = (trimmed as NSString).substring(with: match.range)
        let rest = String(trimmed.dropFirst(prefix.count))
        let level = visualLevel(forIndentation: indentation)
        return indentation + unorderedMarker(forLevel: level) + " " + rest
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
