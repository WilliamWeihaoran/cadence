import Foundation

extension NSAttributedString.Key {
    static let cadenceMarkdownHidden = NSAttributedString.Key("CadenceMarkdownHidden")
    static let cadenceMarkdownDivider = NSAttributedString.Key("CadenceMarkdownDivider")
    static let cadenceMarkdownQuoteDepth = NSAttributedString.Key("CadenceMarkdownQuoteDepth")
    static let cadenceMarkdownImage = NSAttributedString.Key("CadenceMarkdownImage")
    static let cadenceMarkdownInlineCode = NSAttributedString.Key("CadenceMarkdownInlineCode")
    static let cadenceMarkdownCodeBlock = NSAttributedString.Key("CadenceMarkdownCodeBlock")
    static let cadenceMarkdownReference = NSAttributedString.Key("CadenceMarkdownReference")
    static let cadenceMarkdownTableRow = NSAttributedString.Key("CadenceMarkdownTableRow")
    static let cadenceMarkdownHighlight = NSAttributedString.Key("CadenceMarkdownHighlight")
    static let cadenceMarkdownTaskEmbed = NSAttributedString.Key("CadenceMarkdownTaskEmbed")
    /// Marks the hidden `- [x] ` prefix of a GitHub-syntax checklist line, carrying its done state.
    ///
    /// AppKit only turns an `.attachment` attribute into a glyph on `NSAttachmentCharacter`, so the
    /// macOS editor cannot swap the prefix for a checkbox image the way the iOS styler does. The
    /// prefix is hidden instead and the box is drawn over the gutter the paragraph style reserves,
    /// which is the same shape as the quote bar and divider rule. This attribute is how the layout
    /// manager finds those prefixes, and how a click finds the box it drew.
    static let cadenceMarkdownChecklistBox = NSAttributedString.Key("CadenceMarkdownChecklistBox")
    /// Marks the YAML frontmatter block at the head of a note.
    ///
    /// Distinct from `cadenceMarkdownHidden` because the two need opposite caret rules. A hidden
    /// *marker* (`**`, a backtick, a code fence) is inline syntax with visible text on both sides,
    /// so a caret resting at its leading edge is a legitimate position. A hidden frontmatter
    /// *block* is anchored at location 0 with nothing visible before it, so every position inside
    /// it — including 0 — is unreachable and the caret must be pushed past it.
    static let cadenceMarkdownFrontmatter = NSAttributedString.Key("CadenceMarkdownFrontmatter")
}

enum MarkdownHiddenRangeSupport {
    /// The hidden frontmatter block at the head of `storage`, if one is styled.
    ///
    /// Always anchored at 0 — a `---` fence anywhere else in the document is not frontmatter — so
    /// this only probes location 0 rather than scanning. It asks for the *longest* effective range:
    /// a plain `effectiveRange:` probe stops at the first attribute-run boundary, and the styled
    /// block is full of them (the fences are dividers, the property lines are not), so it would
    /// report only the opening `---` and leave the caret free to land inside the hidden YAML.
    static func frontmatterRange(in storage: NSAttributedString?) -> NSRange? {
        guard let storage, storage.length > 0 else { return nil }
        var effectiveRange = NSRange(location: NSNotFound, length: 0)
        let isFrontmatter = (storage.attribute(
            .cadenceMarkdownFrontmatter,
            at: 0,
            longestEffectiveRange: &effectiveRange,
            in: NSRange(location: 0, length: storage.length)
        ) as? Bool) == true
        guard isFrontmatter, effectiveRange.location == 0, effectiveRange.length > 0 else { return nil }
        return effectiveRange
    }

    /// First caret position that is not inside the hidden frontmatter block.
    static func bodyStartLocation(in storage: NSAttributedString?) -> Int {
        guard let storage else { return 0 }
        guard let frontmatter = frontmatterRange(in: storage) else { return 0 }
        return min(NSMaxRange(frontmatter), storage.length)
    }

    static func hiddenRange(containing location: Int, in storage: NSAttributedString?) -> NSRange? {
        guard let storage, storage.length > 0 else { return nil }
        let clamped = max(0, min(location, storage.length - 1))
        var effectiveRange = NSRange(location: NSNotFound, length: 0)
        let isHidden = (storage.attribute(.cadenceMarkdownHidden, at: clamped, effectiveRange: &effectiveRange) as? Bool) == true
        guard isHidden,
              effectiveRange.location != NSNotFound,
              effectiveRange.length > 0 else { return nil }
        return effectiveRange
    }

    static func snappedCaretLocation(_ location: Int, in storage: NSAttributedString?, preferringForward: Bool = true) -> Int {
        guard let storage else { return location }
        let length = storage.length
        guard length > 0 else { return 0 }

        // Frontmatter first, and unconditionally forward. There is no visible text before the
        // block, so unlike an inline marker its leading edge is not a resting place — a caret
        // left at 0 would look like it was at the top of the note while actually sitting inside
        // the YAML, and the next keystroke would break the block.
        let bodyStart = bodyStartLocation(in: storage)
        if location < bodyStart { return bodyStart }

        // A caret sitting exactly at the start of a hidden range (e.g. right before a
        // closing "`"/"**" marker) is a normal, valid resting place — not "stuck inside"
        // the hidden run — so it must not be snapped. Only snap when the caret is
        // strictly past the start, i.e. genuinely inside the hidden span.
        if location < length, let hidden = hiddenRange(containing: location, in: storage), location > hidden.location {
            return preferringForward ? NSMaxRange(hidden) : hidden.location
        }
        if location > 0, let hidden = hiddenRange(containing: location - 1, in: storage), location < NSMaxRange(hidden) {
            return preferringForward ? NSMaxRange(hidden) : hidden.location
        }
        return min(location, length)
    }

    static func nextVisibleCaretLocation(from location: Int, movingForward: Bool, in storage: NSAttributedString?) -> Int {
        guard let storage else { return location }
        let length = storage.length
        guard length > 0 else { return 0 }

        // Arrowing left off the first body character stops at the body's first character rather
        // than walking backwards into the hidden block.
        let bodyStart = bodyStartLocation(in: storage)
        var candidate = min(max(location, bodyStart), length)
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
            if candidate > bodyStart { candidate -= 1 }
            while candidate > bodyStart {
                if let hidden = hiddenRange(containing: candidate, in: storage) {
                    let nextCandidate = max(hidden.location, bodyStart)
                    if nextCandidate >= candidate {
                        candidate -= 1
                    } else {
                        candidate = nextCandidate
                    }
                } else {
                    break
                }
            }
            return max(candidate, bodyStart)
        }
    }
}
