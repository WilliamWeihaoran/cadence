import Foundation

enum MarkdownReferenceDisplayKind: String, Equatable {
    case note
    case task
}

struct MarkdownReferenceDisplayTarget: Hashable, Identifiable {
    let kind: MarkdownReferenceDisplayKind
    let referenceID: UUID?
    let title: String

    var identity: String {
        "\(kind.rawValue):\(referenceID?.uuidString ?? title)"
    }

    var id: String { identity }
}

struct MarkdownReferenceDisplay: Equatable {
    let kind: MarkdownReferenceDisplayKind
    let displayText: String
    let hiddenPrefixUTF16Length: Int
    let target: MarkdownReferenceDisplayTarget
}

struct MarkdownReferenceInlineSegment: Equatable {
    let text: String
    let target: MarkdownReferenceDisplayTarget?
}

struct MarkdownReferenceDisplayRange: Equatable {
    let fullRange: NSRange
    let displayRange: NSRange
    let display: MarkdownReferenceDisplay

    nonisolated var target: MarkdownReferenceDisplayTarget {
        display.target
    }
}

enum MarkdownReferenceDisplaySupport {
    nonisolated static func referenceRanges(in markdown: String) -> [MarkdownReferenceDisplayRange] {
        guard let regex = try? NSRegularExpression(pattern: #"\[\[([^\[\]]+?)\]\]"#) else {
            return []
        }

        let nsMarkdown = markdown as NSString
        return regex.matches(in: markdown, range: NSRange(location: 0, length: nsMarkdown.length)).compactMap { match in
            guard match.numberOfRanges >= 2 else { return nil }
            let fullRange = match.range(at: 0)
            let labelRange = match.range(at: 1)
            guard fullRange.location != NSNotFound,
                  labelRange.location != NSNotFound else {
                return nil
            }

            let display = display(forWikiLabel: nsMarkdown.substring(with: labelRange))
            let displayRange = NSRange(
                location: labelRange.location + display.hiddenPrefixUTF16Length,
                length: max(0, labelRange.length - display.hiddenPrefixUTF16Length)
            )

            return MarkdownReferenceDisplayRange(
                fullRange: fullRange,
                displayRange: displayRange.length > 0 ? displayRange : labelRange,
                display: display
            )
        }
    }

    nonisolated static func target(
        atUTF16Location location: Int,
        in markdown: String,
        includesHiddenSyntax: Bool = false
    ) -> MarkdownReferenceDisplayTarget? {
        referenceRanges(in: markdown).first { reference in
            let range = includesHiddenSyntax ? reference.fullRange : reference.displayRange
            return NSLocationInRange(location, range)
        }?.target
    }

    nonisolated static func display(forWikiLabel label: String) -> MarkdownReferenceDisplay {
        let target = target(forWikiLabel: label)
        let hiddenPrefixLength = referencePrefixLength(in: label)
        let nsLabel = label as NSString
        let displayText: String
        if hiddenPrefixLength > 0, hiddenPrefixLength < nsLabel.length {
            displayText = nsLabel.substring(from: hiddenPrefixLength)
        } else {
            displayText = label
        }

        return MarkdownReferenceDisplay(
            kind: target.kind,
            displayText: displayText,
            hiddenPrefixUTF16Length: hiddenPrefixLength < nsLabel.length ? hiddenPrefixLength : 0,
            target: target
        )
    }

    nonisolated static func inlineSegments(in markdown: String) -> [MarkdownReferenceInlineSegment] {
        guard let regex = try? NSRegularExpression(pattern: #"\[\[([^\[\]]+?)\]\]"#) else {
            return [MarkdownReferenceInlineSegment(text: markdown, target: nil)]
        }
        let nsMarkdown = markdown as NSString
        let matches = regex.matches(in: markdown, range: NSRange(location: 0, length: nsMarkdown.length))
        guard !matches.isEmpty else {
            return [MarkdownReferenceInlineSegment(text: markdown, target: nil)]
        }

        var segments: [MarkdownReferenceInlineSegment] = []
        var cursor = 0
        for match in matches {
            guard match.numberOfRanges >= 2 else { continue }
            let fullRange = match.range(at: 0)
            let labelRange = match.range(at: 1)
            guard fullRange.location != NSNotFound,
                  labelRange.location != NSNotFound,
                  fullRange.location >= cursor else {
                continue
            }

            if fullRange.location > cursor {
                segments.append(MarkdownReferenceInlineSegment(
                    text: nsMarkdown.substring(with: NSRange(location: cursor, length: fullRange.location - cursor)),
                    target: nil
                ))
            }

            let display = display(forWikiLabel: nsMarkdown.substring(with: labelRange))
            segments.append(MarkdownReferenceInlineSegment(
                text: display.displayText,
                target: display.target
            ))
            cursor = fullRange.location + fullRange.length
        }

        if cursor < nsMarkdown.length {
            segments.append(MarkdownReferenceInlineSegment(
                text: nsMarkdown.substring(with: NSRange(location: cursor, length: nsMarkdown.length - cursor)),
                target: nil
            ))
        }

        return segments.filter { !$0.text.isEmpty }
    }

    nonisolated static func replacingWikiLinksWithDisplayText(in markdown: String) -> String {
        inlineSegments(in: markdown).map(\.text).joined()
    }

    nonisolated static func target(forWikiLabel label: String) -> MarkdownReferenceDisplayTarget {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()
        if lowercased.hasPrefix("task:") {
            return target(kind: .task, payload: String(trimmed.dropFirst(5)))
        }
        if lowercased.hasPrefix("note:") {
            return target(kind: .note, payload: String(trimmed.dropFirst(5)))
        }
        return MarkdownReferenceDisplayTarget(kind: .note, referenceID: UUID(uuidString: trimmed), title: trimmed)
    }

    nonisolated static func url(for target: MarkdownReferenceDisplayTarget) -> URL? {
        var components = URLComponents()
        components.scheme = "cadence-reference"
        components.host = target.kind.rawValue
        components.queryItems = [
            URLQueryItem(name: "title", value: target.title)
        ]
        if let id = target.referenceID {
            components.queryItems?.append(URLQueryItem(name: "id", value: id.uuidString))
        }
        return components.url
    }

    nonisolated static func target(from url: URL) -> MarkdownReferenceDisplayTarget? {
        guard url.scheme == "cadence-reference",
              let host = url.host,
              let kind = MarkdownReferenceDisplayKind(rawValue: host) else {
            return nil
        }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let idText = components?.queryItems?.first(where: { $0.name == "id" })?.value ?? ""
        let title = components?.queryItems?.first(where: { $0.name == "title" })?.value ?? ""
        return MarkdownReferenceDisplayTarget(kind: kind, referenceID: UUID(uuidString: idText), title: title)
    }

    nonisolated private static func target(
        kind: MarkdownReferenceDisplayKind,
        payload rawPayload: String
    ) -> MarkdownReferenceDisplayTarget {
        let payload = rawPayload.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = payload.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        if parts.count == 2 {
            let idText = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            let title = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            return MarkdownReferenceDisplayTarget(kind: kind, referenceID: UUID(uuidString: idText), title: title)
        }
        return MarkdownReferenceDisplayTarget(kind: kind, referenceID: UUID(uuidString: payload), title: payload)
    }

    nonisolated private static func referencePrefixLength(in label: String) -> Int {
        let nsLabel = label as NSString
        let fullRange = NSRange(location: 0, length: nsLabel.length)
        guard let regex = try? NSRegularExpression(
            pattern: #"^\s*(?:task|note):(?:[^\|\]]*\|)?"#,
            options: [.caseInsensitive]
        ),
            let match = regex.firstMatch(in: label, range: fullRange) else {
            return 0
        }
        return match.range.length
    }
}
