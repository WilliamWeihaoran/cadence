import Foundation

struct MarkdownOutlineItem: Identifiable, Hashable {
    let id: Int
    let level: Int
    let title: String
    let location: Int
}

enum MarkdownOutlineParser {
    nonisolated static func items(in content: String) -> [MarkdownOutlineItem] {
        let nsContent = content as NSString
        var items: [MarkdownOutlineItem] = []
        var location = 0

        for line in content.components(separatedBy: "\n") {
            defer { location += (line as NSString).length + 1 }
            let nsLine = line as NSString
            guard let regex = try? NSRegularExpression(pattern: #"^(#{1,6})\s+(.+?)\s*$"#),
                  let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)),
                  match.numberOfRanges >= 3 else {
                continue
            }

            let marker = nsLine.substring(with: match.range(at: 1))
            let title = nsLine.substring(with: match.range(at: 2))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            items.append(MarkdownOutlineItem(
                id: location,
                level: marker.count,
                title: title,
                location: min(location, nsContent.length)
            ))
        }

        return items
    }
}

struct MarkdownFrontmatter: Equatable {
    let properties: [String: String]
    let range: NSRange?
}

struct MarkdownNoteMetadata: Equatable {
    let frontmatter: MarkdownFrontmatter
    let tags: [String]
}

enum MarkdownMetadataParser {
    nonisolated static func metadata(in content: String) -> MarkdownNoteMetadata {
        let frontmatter = parseFrontmatter(in: content)
        let tags = orderedUnique(frontmatterTags(from: frontmatter.properties) + inlineTags(in: content, excluding: frontmatter.range))
        return MarkdownNoteMetadata(frontmatter: frontmatter, tags: tags)
    }

    nonisolated static func inlineTagNames(in content: String) -> [String] {
        let frontmatter = parseFrontmatter(in: content)
        return orderedUnique(inlineTags(in: content, excluding: frontmatter.range))
    }

    nonisolated static func content(_ content: String, replacingFrontmatterTags tags: [String]) -> String {
        let frontmatter = parseFrontmatter(in: content)
        let tagLine = "tags: [\(orderedUnique(tags).map { "\"\($0.replacingOccurrences(of: "\"", with: "'"))\"" }.joined(separator: ", "))]"

        guard let range = frontmatter.range else {
            return """
            ---
            \(tagLine)
            ---

            \(content)
            """
        }

        let nsContent = content as NSString
        let frontmatterText = nsContent.substring(with: range)
        let lines = frontmatterText.components(separatedBy: "\n")
        var replaced = false
        let updatedLines = lines.map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("tags:") || trimmed.lowercased().hasPrefix("tag:") {
                replaced = true
                return tagLine
            }
            return line
        }

        let updatedFrontmatter: String
        if replaced {
            updatedFrontmatter = updatedLines.joined(separator: "\n")
        } else if let closingIndex = updatedLines.lastIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "---" }), closingIndex > 0 {
            var inserted = updatedLines
            inserted.insert(tagLine, at: closingIndex)
            updatedFrontmatter = inserted.joined(separator: "\n")
        } else {
            updatedFrontmatter = frontmatterText
        }

        return nsContent.replacingCharacters(in: range, with: updatedFrontmatter)
    }

    nonisolated static func frontmatterInsertion(title: String) -> String {
        let cleanedTitle = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "'")
        let displayTitle = cleanedTitle.isEmpty ? "Untitled" : cleanedTitle
        return """
        ---
        title: "\(displayTitle)"
        tags: []
        status: active
        ---

        """
    }

    nonisolated private static func parseFrontmatter(in content: String) -> MarkdownFrontmatter {
        let nsContent = content as NSString
        guard content.hasPrefix("---\n") || content == "---" else {
            return MarkdownFrontmatter(properties: [:], range: nil)
        }

        let lines = content.components(separatedBy: "\n")
        guard lines.first == "---" else {
            return MarkdownFrontmatter(properties: [:], range: nil)
        }

        var properties: [String: String] = [:]
        var offset = (lines[0] as NSString).length + 1
        for index in 1..<lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespacesAndNewlines) == "---" {
                let end = min(nsContent.length, offset + (line as NSString).length + (index < lines.count - 1 ? 1 : 0))
                return MarkdownFrontmatter(
                    properties: properties,
                    range: NSRange(location: 0, length: end)
                )
            }

            if let separator = line.firstIndex(of: ":") {
                let key = String(line[..<separator])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                let value = String(line[line.index(after: separator)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                if !key.isEmpty {
                    properties[key] = value
                }
            }
            offset += (line as NSString).length + 1
        }

        return MarkdownFrontmatter(properties: properties, range: nil)
    }

    nonisolated private static func frontmatterTags(from properties: [String: String]) -> [String] {
        guard let raw = properties["tags"] ?? properties["tag"] else { return [] }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = trimmed.hasPrefix("[") && trimmed.hasSuffix("]")
            ? String(trimmed.dropFirst().dropLast())
            : trimmed
        return content
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
            .filter { !$0.isEmpty }
    }

    nonisolated private static func inlineTags(in content: String, excluding excludedRange: NSRange?) -> [String] {
        var tags: [String] = []
        var location = 0
        var inCodeFence = false
        let regex = try? NSRegularExpression(pattern: #"(?<![\p{L}\p{N}_])#([A-Za-z0-9][A-Za-z0-9_-]*)"#)

        for line in content.components(separatedBy: "\n") {
            defer { location += (line as NSString).length + 1 }
            let lineRange = NSRange(location: location, length: (line as NSString).length)
            if let excludedRange, NSIntersectionRange(lineRange, excludedRange).length > 0 {
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                inCodeFence.toggle()
                continue
            }
            if inCodeFence || MarkdownMetadataParser.isMarkdownHeading(trimmed) {
                continue
            }

            let nsLine = line as NSString
            regex?.enumerateMatches(in: line, range: NSRange(location: 0, length: nsLine.length)) { match, _, _ in
                guard let match, match.numberOfRanges > 1 else { return }
                tags.append(nsLine.substring(with: match.range(at: 1)))
            }
        }

        return tags
    }

    nonisolated private static func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { continue }
            let key = normalized.lowercased()
            if seen.insert(key).inserted {
                result.append(normalized)
            }
        }
        return result
    }

    nonisolated private static func isMarkdownHeading(_ line: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #"^#{1,6}\s+"#) else { return false }
        return regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil
    }
}
