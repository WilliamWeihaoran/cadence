import Foundation

/// Which of the two checklist spellings a line is written in.
///
/// `github` is the portable `- [ ] ` / `- [x] ` form every other markdown tool reads and writes.
/// `legacy` is Cadence's own `○` / `●` / `✓` glyph, which pre-dates it, still fills existing
/// notes, and is still what the editor's own to-do affordances produce. Both render as a
/// checkbox; only the GitHub form survives a round trip through another tool, which is why the
/// editor no longer rewrites it into the glyph.
enum MarkdownChecklistSyntax: Equatable {
    case github
    case legacy
}

struct MarkdownChecklistLine: Equatable {
    let syntax: MarkdownChecklistSyntax
    let markerRange: NSRange
    let stateRange: NSRange
    let contentRange: NSRange
    let isDone: Bool
    let content: String
}

/// The single-character edit that flips a checklist line: where its state marker is, and what it
/// becomes.
struct MarkdownChecklistToggle: Equatable {
    let stateRange: NSRange
    let replacement: String
}

enum MarkdownChecklistSupport {
    private static let githubChecklistRegex = try! NSRegularExpression(pattern: #"^([ \t]*[-*+]\s+\[)([ xX])(\]\s+)"#)
    private static let legacyChecklistRegex = try! NSRegularExpression(pattern: #"^([ \t]*)([○●✓])\s+"#)

    static func lineInfo(in line: String) -> MarkdownChecklistLine? {
        githubLineInfo(in: line) ?? legacyLineInfo(in: line)
    }

    /// The one-character edit that flips a checklist line, as a range into `line` plus its
    /// replacement.
    ///
    /// Exposed separately from `toggledLine` because the macOS editor toggles by splicing a
    /// single character into an `NSTextStorage` — it needs the range, not a rebuilt line, and
    /// used to derive the replacement itself by comparing a raw UTF-16 code point.
    static func toggledState(in line: String) -> MarkdownChecklistToggle? {
        guard let info = lineInfo(in: line) else { return nil }
        let replacement = info.isDone ? uncheckedMarker(for: line, info: info) : checkedMarker(for: line, info: info)
        return MarkdownChecklistToggle(stateRange: info.stateRange, replacement: replacement)
    }

    static func toggledLine(_ line: String) -> String? {
        guard let toggle = toggledState(in: line) else { return nil }
        return (line as NSString).replacingCharacters(in: toggle.stateRange, with: toggle.replacement)
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

    /// The same line with its box emptied, keeping whichever spelling it already uses.
    ///
    /// Pressing return on `- [x] shipped` used to open the next item as `○ `, which left one list
    /// written in two spellings and put GitHub syntax back out of the document a line at a time.
    static func emptiedPrefix(in prefix: String) -> String? {
        guard let info = lineInfo(in: prefix) else { return nil }
        return (prefix as NSString).replacingCharacters(
            in: info.stateRange,
            with: info.syntax == .github ? " " : "○"
        )
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
            syntax: .github,
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
            syntax: .legacy,
            markerRange: markerRange,
            stateRange: stateRange,
            isDone: state == "●" || state == "✓"
        )
    }

    private static func lineInfo(
        line: String,
        syntax: MarkdownChecklistSyntax,
        markerRange: NSRange,
        stateRange: NSRange,
        isDone: Bool
    ) -> MarkdownChecklistLine {
        let nsLine = line as NSString
        let contentStart = min(nsLine.length, NSMaxRange(markerRange))
        let contentRange = NSRange(location: contentStart, length: max(0, nsLine.length - contentStart))
        return MarkdownChecklistLine(
            syntax: syntax,
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
