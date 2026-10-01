import Foundation

nonisolated struct MarkdownOutlineItem: Identifiable, Hashable {
    let id: Int
    let level: Int
    let title: String
    let location: Int
}

nonisolated enum MarkdownOutlineParser {
    /// **The outline heading pattern, compiled once per process rather than once per line.**
    ///
    /// It used to be a `try? NSRegularExpression(pattern:)` expression *inside* the `for line in`
    /// loop below, so outlining an N-line note compiled the same unvarying literal N times. This is
    /// the spelling `nonProseRegex`, `inlineTagRegex` and `headingPrefixRegex` further down this
    /// file already use; the literal here is byte-identical to the one that sat in the loop, which
    /// matters because the outline's `level` is `marker.count` and its `title` is capture 2 — a
    /// character lost in the hoist changes which lines become rows and what they are called.
    ///
    /// Measured ([[T-1444]], Apple M3 Pro / Mac15,6, 11 cores, 18 GB, `-O`, medians of 101 calls per
    /// point): the per-line cost of `items(in:)` is **3.15µs before and 0.66µs after**, flat from 3
    /// to 1,000 lines in both, so a 400-line note's outline goes **1,276µs -> 264µs** and a
    /// 1,000-line one 3,175µs -> 666µs. Spread is tight — p10/p90 at 400 lines are 1,258/1,355µs
    /// before and 259/273µs after.
    ///
    /// The ~2.5µs a line that goes away is **not** the ~100µs a fresh compile cost in [[T-1366]]'s
    /// sweep: `NSRegularExpression` caches compiled patterns internally, so after the first line
    /// every rebuild of this one literal is a cache lookup rather than a parse. It is still
    /// four-fifths of the pass, and the pass runs on the main actor 150ms after the user stops
    /// typing (`MarkdownEditorSyncTiming.derivedStateRefreshDelay`), once per keystroke burst, in
    /// both `NoteEditorPane` and `ListNotesSupportViews`.
    ///
    /// `NSRegularExpression` is immutable once built and its matching methods are documented as
    /// thread-safe, which is the property the three stored patterns below already rely on.
    nonisolated private static let outlineHeadingRegex = try? NSRegularExpression(
        pattern: #"^(#{1,6})\s+(.+?)\s*$"#
    )

    nonisolated static func items(in content: String) -> [MarkdownOutlineItem] {
        let nsContent = content as NSString
        var items: [MarkdownOutlineItem] = []
        var location = 0

        for line in content.components(separatedBy: "\n") {
            defer { location += (line as NSString).length + 1 }
            let nsLine = line as NSString
            guard let regex = outlineHeadingRegex,
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

nonisolated struct MarkdownFrontmatter: Equatable {
    let properties: [String: String]
    let range: NSRange?
}

nonisolated struct MarkdownNoteMetadata: Equatable {
    let frontmatter: MarkdownFrontmatter
    let tags: [String]
}

nonisolated enum MarkdownMetadataParser {
    nonisolated static func metadata(in content: String) -> MarkdownNoteMetadata {
        let frontmatter = parseFrontmatter(in: content)
        let tags = orderedUnique(frontmatterTags(from: frontmatter.properties) + inlineTags(in: content, excluding: frontmatter.range))
        return MarkdownNoteMetadata(frontmatter: frontmatter, tags: tags)
    }

    /// Character range of the leading frontmatter block, or `nil` when the note has none.
    ///
    /// The editor uses this to render the block at zero height: the YAML stays in the file for
    /// portability, but nothing in Cadence reads `title`/`status` back and tags round-trip through
    /// the note header's `Tag` chips, so showing it in the body is noise.
    nonisolated static func frontmatterRange(in content: String) -> NSRange? {
        parseFrontmatter(in: content).range
    }

    /// The range a *renderer* should suppress: the parsed block plus the blank lines that
    /// conventionally follow it, so the body starts at the top of the surface instead of under a
    /// stack of empty rows.
    ///
    /// Both editors call this. It used to be spelled out inside macOS's `applyFrontmatter`, and
    /// iOS — which suppressed nothing — would have had to re-derive the same "swallow the trailing
    /// newlines" rule to match. A block hidden to two different extents on two platforms puts the
    /// caret in two different places for the same note, which is exactly the drift this repo keeps
    /// paying for.
    nonisolated static func hiddenFrontmatterRange(in content: String) -> NSRange? {
        guard let parsed = frontmatterRange(in: content), parsed.length > 0 else { return nil }
        let nsContent = content as NSString
        var end = min(NSMaxRange(parsed), nsContent.length)
        while end < nsContent.length, nsContent.character(at: end) == 10 { end += 1 }
        guard end > 0 else { return nil }
        return NSRange(location: 0, length: end)
    }

    /// How many leading *lines* the frontmatter block occupies, for line-indexed consumers.
    ///
    /// The preview parser hands `lineIndex` back to its caller so a tapped checklist box can be
    /// toggled in the original markdown, so it cannot simply be handed a frontmatter-stripped
    /// string — every index after the block would be wrong. It starts its scan at this index
    /// instead, and its line numbering stays the note's own.
    nonisolated static func frontmatterLineCount(in content: String) -> Int {
        let block = splitFrontmatter(in: content).frontmatter
        guard !block.isEmpty else { return 0 }
        let newlines = block.reduce(into: 0) { count, character in
            if character == "\n" { count += 1 }
        }
        return block.hasSuffix("\n") ? newlines : newlines + 1
    }

    /// Splits a note into its frontmatter block (empty string when there is none) and the body
    /// after it.
    ///
    /// Callers that rewrite a note wholesale — applying a template, checking whether the note is
    /// "empty" — must go through this. The block is invisible in the editor, so anything that
    /// reasons about `content` as if it were all body will either refuse to treat a freshly tagged
    /// note as empty, or quietly overwrite the tags.
    nonisolated static func splitFrontmatter(in content: String) -> (frontmatter: String, body: String) {
        guard let range = frontmatterRange(in: content) else { return ("", content) }
        let nsContent = content as NSString
        let end = min(NSMaxRange(range), nsContent.length)
        return (nsContent.substring(to: end), nsContent.substring(from: end))
    }

    /// Reassembles a note from a (possibly empty) frontmatter block and a new body, restoring the
    /// blank line that conventionally separates the two.
    nonisolated static func content(frontmatter: String, body: String) -> String {
        guard !frontmatter.isEmpty else { return body }
        return frontmatter + "\n" + body
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

    /// Frontmatter is **read** here, never offered as something to add.
    ///
    /// The note editor used to have an "Add frontmatter" button that seeded a
    /// `--- / title / tags: [] / status --- ` block. Nothing in Cadence reads `title` or `status`
    /// back, and tagging already has a first-class `Tag` model with its own picker in the note
    /// header, so the button was a second, parallel tagging system the app ignored. It is gone.
    ///
    /// This parser stays because notes that already carry a block still depend on it:
    /// `metadata(in:)` feeds `TagSupport.syncNoteTagsFromMarkdown`, which turns a block's
    /// `tags:` line into real `Tag` rows; `content(_:replacingFrontmatterTags:)` writes tag edits
    /// back into an existing block; and `inlineTagNames(in:)` uses the parsed range to keep the
    /// block itself out of the inline `#tag` scan.
    ///
    /// **`---` is also this editor's horizontal-rule syntax** (alongside `***` and `___`), so a
    /// note that opens with a divider and drops another one further down is indistinguishable from
    /// a frontmatter block to a parser that only matches fences — and the parsed range is hidden
    /// outright, with no reveal-on-caret and no toggle, so guessing wrong erases every line
    /// between the two rules. A block therefore has to earn the name: it must sit at the very
    /// start of the note, and it must carry at least one well-formed `key: value` property, with
    /// nothing between the fences that is not YAML. Every block Cadence writes has a `tags:` line,
    /// and a propertyless block holds nothing worth hiding, so nothing real is lost by being
    /// strict. When in doubt this returns "not frontmatter", which shows content rather than
    /// hiding it.
    nonisolated private static func parseFrontmatter(in content: String) -> MarkdownFrontmatter {
        let notFrontmatter = MarkdownFrontmatter(properties: [:], range: nil)
        let nsContent = content as NSString
        guard content.hasPrefix("---\n") else { return notFrontmatter }

        let lines = content.components(separatedBy: "\n")
        var properties: [String: String] = [:]
        var offset = (lines[0] as NSString).length + 1
        for index in 1..<lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespacesAndNewlines) == "---" {
                guard !properties.isEmpty else { return notFrontmatter }
                let end = min(nsContent.length, offset + (line as NSString).length + (index < lines.count - 1 ? 1 : 0))
                return MarkdownFrontmatter(
                    properties: properties,
                    range: NSRange(location: 0, length: end)
                )
            }

            if let property = yamlProperty(in: line) {
                properties[property.key] = property.value
            } else if !isYAMLFiller(line, hasProperty: !properties.isEmpty) {
                return notFrontmatter
            }
            offset += (line as NSString).length + 1
        }

        return notFrontmatter
    }

    /// A `key: value` line whose key is a bare YAML scalar.
    ///
    /// The key may not contain spaces, so a prose line that merely happens to have a colon in it —
    /// "One more thing: be kind" — does not qualify a divider pair as frontmatter.
    nonisolated private static func yamlProperty(in line: String) -> (key: String, value: String)? {
        guard let separator = line.firstIndex(of: ":") else { return nil }
        let key = String(line[..<separator])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !key.isEmpty, key.unicodeScalars.allSatisfy(yamlKeyCharacters.contains) else { return nil }
        let value = String(line[line.index(after: separator)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        return (key, value)
    }

    /// Lines a real block can carry besides properties: blank spacers, and the indented
    /// continuation of a multi-line value (`tags:` followed by `  - a`), which blocks written by
    /// other markdown tools use. An indented line with no property above it is continuing nothing,
    /// so it reads as prose.
    nonisolated private static func isYAMLFiller(_ line: String, hasProperty: Bool) -> Bool {
        if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return hasProperty && line.first?.isWhitespace == true
    }

    nonisolated private static let yamlKeyCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-."))

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

            let scannable = maskingNonProse(in: line)
            let nsLine = scannable as NSString
            inlineTagRegex?.enumerateMatches(in: scannable, range: NSRange(location: 0, length: nsLine.length)) { match, _, _ in
                guard let match, match.numberOfRanges > 1 else { return }
                tags.append(nsLine.substring(with: match.range(at: 1)))
            }
        }

        return tags
    }

    /// **The inline-tag pattern, compiled once per process rather than once per note.**
    ///
    /// `nonProseRegex` below has been a stored `static let` since it was written; this one and
    /// `headingPrefixRegex` were `try? NSRegularExpression(pattern:)` expressions *inside* the
    /// functions that use them, so `inlineTags` rebuilt this pattern for every note it parsed and
    /// `isMarkdownHeading` rebuilt its own for every line of every note. Nothing about either
    /// pattern varies — they are string literals — so the rebuild was pure repetition.
    ///
    /// It was found by measurement, not by reading ([[T-1366]]): the launch's tag sweep costs
    /// ~93µs per note on a store whose notes have **no tags and no body at all**, which is a
    /// per-note constant that cannot be about tag bytes, and ~3.6µs per additional line at a fixed
    /// note size. Compiling this pattern is ~100µs on the machine that measured it.
    ///
    /// `NSRegularExpression` is immutable once built and its matching methods are documented as
    /// thread-safe, which is the same property `nonProseRegex` already relies on here. That is
    /// what lets three readers share the one compiled object below ([[T-1660]]).
    ///
    /// The 46 bytes were written three times ([[T-1660]]): here, in
    /// `MarkdownInlineMarkerRanges.hashtagPattern`, and again inside
    /// `MarkdownInlinePreviewSupport.inlineMatches`, which compiled its copy on every inline
    /// string. The owner has to be *this* file rather than the styler's, and the reason is the
    /// target boundary [[T-1521]] established: `MarkdownMetadataSupport.swift` is in the app's
    /// synchronized folder **and** in `CadenceMCPServer`'s and `CadenceWidgets`' Sources phases,
    /// while `MarkdownStyleRangeSupport.swift` is in none of the explicit ones — so a constant
    /// declared there would not link in the two extra targets this file compiles into. No file
    /// moved between targets and `project.pbxproj` was not edited.
    ///
    /// The lookbehind is what keeps `C#` and `id_#4` from becoming tags; the tag body deliberately
    /// starts with an alphanumeric so a bare `#-` or `#_` is not one either.
    nonisolated static let inlineTagPattern = #"(?<![\p{L}\p{N}_])#([A-Za-z0-9][A-Za-z0-9_-]*)"#

    /// The compiled form, read by the launch tag sweep above, by the stylers through
    /// `MarkdownInlineMarkerRanges.hashtagRegex`, and by the inline preview's tag rule — one
    /// object, not three built from the same string.
    nonisolated static let inlineTagRegex = try? NSRegularExpression(pattern: inlineTagPattern)

    /// Link destinations, autolinks, raw HTML tags and inline code are not prose, so a `#` inside
    /// them is a URL fragment or a hex colour rather than a tag. Tag sync runs unattended at launch
    /// and *inserts* what it finds, so anything it misreads becomes a `Tag` row the user never
    /// created.
    ///
    /// The autolink branch cannot cover an HTML tag that carries attributes, because those contain
    /// spaces — hence the separate branch for `<a href="#quickstart">`. That branch insists on a
    /// tag name straight after the `<` and on an `=` inside, so comparisons stay prose: `a < b` and
    /// `1<2` have no tag name after the `<`, and `<y and z>` has no attribute.
    nonisolated private static let nonProseRegex = try? NSRegularExpression(
        pattern: #"`[^`\n]*`|\]\([^)\n]*\)|<[^>\s]+>|<[A-Za-z][A-Za-z0-9-]*\s[^<>\n]*=[^<>\n]*>|https?://[^\s)]+"#
    )

    nonisolated private static func maskingNonProse(in line: String) -> String {
        guard let nonProseRegex else { return line }
        let nsLine = line as NSString
        let matches = nonProseRegex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
        guard !matches.isEmpty else { return line }

        let masked = NSMutableString(string: line)
        for match in matches.reversed() {
            masked.replaceCharacters(in: match.range, with: String(repeating: " ", count: match.range.length))
        }
        return masked as String
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

    /// **The one `^#{1,6}\s+` in the app target.** `private` until [[T-1484]], which found
    /// `MarkdownFormatCommandSupport.headingPrefix(in:)` building the same ten bytes per call four
    /// files away; that call site reads this now. Kept here rather than moved because this is
    /// where it already was and because `MarkdownMetadataSupport.swift` is one of the few files
    /// `CadenceMCPServer` also compiles, so a new home would have to be in that target too.
    nonisolated static let headingPrefixRegex = try? NSRegularExpression(pattern: #"^#{1,6}\s+"#)

    nonisolated private static func isMarkdownHeading(_ line: String) -> Bool {
        guard let headingPrefixRegex else { return false }
        return headingPrefixRegex.firstMatch(
            in: line,
            range: NSRange(location: 0, length: (line as NSString).length)
        ) != nil
    }
}
