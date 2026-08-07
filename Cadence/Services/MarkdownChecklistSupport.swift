import Foundation

struct MarkdownChecklistLine: Equatable {
    let markerRange: NSRange
    let stateRange: NSRange
    let contentRange: NSRange
    let isDone: Bool
    let content: String
}

enum MarkdownChecklistSupport {
    private static let githubChecklistRegex = try! NSRegularExpression(pattern: #"^([ \t]*[-*+]\s+\[)([ xX])(\]\s+)"#)
    private static let legacyChecklistRegex = try! NSRegularExpression(pattern: #"^([ \t]*)([○●✓])\s+"#)

    static func lineInfo(in line: String) -> MarkdownChecklistLine? {
        githubLineInfo(in: line) ?? legacyLineInfo(in: line)
    }

    static func toggledLine(_ line: String) -> String? {
        guard let info = lineInfo(in: line) else { return nil }
        let replacement = info.isDone ? uncheckedMarker(for: line, info: info) : checkedMarker(for: line, info: info)
        return (line as NSString).replacingCharacters(in: info.stateRange, with: replacement)
    }

    static func toggledText(_ text: String, lineIndex: Int) -> String? {
        var lines = text.components(separatedBy: "\n")
        guard lines.indices.contains(lineIndex),
              let toggled = toggledLine(lines[lineIndex]) else {
            return nil
        }
        lines[lineIndex] = toggled
        return lines.joined(separator: "\n")
    }

    private static func githubLineInfo(in line: String) -> MarkdownChecklistLine? {
        let regex = githubChecklistRegex
        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)
        guard let match = regex.firstMatch(in: line, range: fullRange),
              match.numberOfRanges >= 4 else {
            return nil
        }

        let markerRange = match.range(at: 0)
        let stateRange = match.range(at: 2)
        guard markerRange.location != NSNotFound, stateRange.location != NSNotFound else {
            return nil
        }
        return lineInfo(
            line: line,
            markerRange: markerRange,
            stateRange: stateRange,
            isDone: nsLine.substring(with: stateRange).lowercased() == "x"
        )
    }

    private static func legacyLineInfo(in line: String) -> MarkdownChecklistLine? {
        let regex = legacyChecklistRegex
        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)
        guard let match = regex.firstMatch(in: line, range: fullRange),
              match.numberOfRanges >= 3 else {
            return nil
        }

        let markerRange = match.range(at: 0)
        let stateRange = match.range(at: 2)
        guard markerRange.location != NSNotFound, stateRange.location != NSNotFound else {
            return nil
        }
        let state = nsLine.substring(with: stateRange)
        return lineInfo(
            line: line,
            markerRange: markerRange,
            stateRange: stateRange,
            isDone: state == "●" || state == "✓"
        )
    }

    private static func lineInfo(
        line: String,
        markerRange: NSRange,
        stateRange: NSRange,
        isDone: Bool
    ) -> MarkdownChecklistLine {
        let nsLine = line as NSString
        let contentStart = min(nsLine.length, NSMaxRange(markerRange))
        let contentRange = NSRange(location: contentStart, length: max(0, nsLine.length - contentStart))
        return MarkdownChecklistLine(
            markerRange: markerRange,
            stateRange: stateRange,
            contentRange: contentRange,
            isDone: isDone,
            content: nsLine.substring(with: contentRange)
        )
    }

    private static func checkedMarker(for line: String, info: MarkdownChecklistLine) -> String {
        let current = (line as NSString).substring(with: info.stateRange)
        return current == "○" ? "●" : "x"
    }

    private static func uncheckedMarker(for line: String, info: MarkdownChecklistLine) -> String {
        let current = (line as NSString).substring(with: info.stateRange)
        return current == "●" || current == "✓" ? "○" : " "
    }
}
