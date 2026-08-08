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
}

enum MarkdownHiddenRangeSupport {
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
