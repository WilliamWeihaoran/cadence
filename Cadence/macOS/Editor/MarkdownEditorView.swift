#if os(macOS)
import SwiftUI
import AppKit

// MARK: - CadenceTextView
// Subclass to handle checkbox toggle on mouse click.

final class CadenceTextView: NSTextView {
    override func mouseDown(with event: NSEvent) {
        // Convert from window → view → text-container coordinates
        let viewPoint = convert(event.locationInWindow, from: nil)
        let containerPoint = NSPoint(
            x: viewPoint.x - textContainerInset.width,
            y: viewPoint.y - textContainerInset.height
        )
        if let lm = layoutManager, let tc = textContainer {
            let glyphIdx = lm.glyphIndex(for: containerPoint, in: tc, fractionOfDistanceThroughGlyph: nil)
            if glyphIdx < lm.numberOfGlyphs {
                let charIdx = lm.characterIndexForGlyph(at: glyphIdx)
                let nsStr = string as NSString
                // Check clicked char and the start of its line (gives a generous hit area)
                let lineRange = nsStr.lineRange(for: NSRange(location: charIdx, length: 0))
                let lineStartChar = lineRange.length > 0 ? nsStr.character(at: lineRange.location) : 0
                let clickedChar   = charIdx < nsStr.length ? nsStr.character(at: charIdx) : 0
                let isCircle: (unichar) -> Bool = { c in c == 0x25CB || c == 0x25CF }
                if isCircle(clickedChar) || (isCircle(lineStartChar) && charIdx <= lineRange.location + 2) {
                    let targetIdx = isCircle(clickedChar) ? charIdx : lineRange.location
                    let targetChar = nsStr.character(at: targetIdx)
                    let replacement = targetChar == 0x25CB ? "●" : "○"
                    let range = NSRange(location: targetIdx, length: 1)
                    if shouldChangeText(in: range, replacementString: replacement) {
                        textStorage?.replaceCharacters(in: range, with: replacement)
                        didChangeText()
                        return
                    }
                }
            }
        }
        super.mouseDown(with: event)
    }
}

// MARK: - MarkdownEditorView

struct MarkdownEditorView: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: NSViewRepresentableContext<MarkdownEditorView>) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(hex: "#0f1117")
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = CadenceTextView()
        let contentSize = scrollView.contentSize
        textView.frame = NSRect(origin: .zero, size: CGSize(width: contentSize.width, height: 0))
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: contentSize.width,
                                                        height: CGFloat.greatestFiniteMagnitude)

        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isRichText = true       // must be true to preserve custom attributes
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.backgroundColor = NSColor(hex: "#0f1117")
        textView.insertionPointColor = NSColor(hex: "#4a9eff")
        textView.textContainerInset = NSSize(width: 20, height: 20)
        textView.font = MarkdownStylist.baseFont
        textView.typingAttributes = MarkdownStylist.baseAttributes

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: NSViewRepresentableContext<MarkdownEditorView>) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            let sel = textView.selectedRange()
            textView.string = text
            MarkdownStylist.apply(to: textView)
            let safe = NSRange(location: min(sel.location, (text as NSString).length), length: 0)
            textView.setSelectedRange(safe)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditorView
        init(_ parent: MarkdownEditorView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            applyInputTransforms(to: textView)
            parent.text = textView.string
            MarkdownStylist.apply(to: textView)
            textView.typingAttributes = MarkdownStylist.baseAttributes
        }

        // Intercept Return on list lines — continue the list on the next line with same prefix.
        // If the current list item is empty (just the prefix), exit the list instead.
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            let s = textView.string as NSString
            let sel = textView.selectedRange()
            let lineRange = s.lineRange(for: NSRange(location: sel.location, length: 0))
            let rawLine = s.substring(with: NSRange(location: lineRange.location,
                                                    length: min(lineRange.length, s.length - lineRange.location)))
            let line = rawLine.trimmingCharacters(in: .newlines)

            // Determine which list prefix is active
            let prefix: String
            if line.hasPrefix("• ")      { prefix = "• " }
            else if line.hasPrefix("– ") { prefix = "– " }
            else if line.hasPrefix("○ ") || line.hasPrefix("● ") { prefix = "○ " }
            else { return false }

            // If the line has only the prefix (empty item), exit list — delete prefix + insert plain newline
            let contentAfterPrefix = line.hasPrefix(prefix) ? String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces) : line
            if contentAfterPrefix.isEmpty {
                let deleteRange = NSRange(location: lineRange.location,
                                         length: min(lineRange.length, s.length - lineRange.location))
                guard textView.shouldChangeText(in: deleteRange, replacementString: "\n") else { return false }
                textView.textStorage?.replaceCharacters(in: deleteRange, with: "\n")
                textView.setSelectedRange(NSRange(location: lineRange.location + 1, length: 0))
                textView.typingAttributes = MarkdownStylist.baseAttributes
                textView.didChangeText()
                return true
            }

            // Otherwise continue the list — insert newline + same prefix
            let insertStr = "\n" + prefix
            guard textView.shouldChangeText(in: sel, replacementString: insertStr) else { return false }
            textView.textStorage?.replaceCharacters(in: sel, with: insertStr)
            let newPos = sel.location + (insertStr as NSString).length
            textView.setSelectedRange(NSRange(location: newPos, length: 0))
            textView.typingAttributes = MarkdownStylist.baseAttributes
            textView.didChangeText()
            return true
        }

        // MARK: - Input transforms

        // Converts trigger sequences into display characters on the fly:
        //   "* " at line start  → "• "  (bullet)
        //   "- " at line start  → "– "  (en-dash list)
        //   "[ ]" at line start → "○ "  (unchecked todo circle)
        //   "[x]" at line start → "● "  (checked todo circle)
        private func applyInputTransforms(to textView: NSTextView) {
            let s = textView.string as NSString
            let cursor = textView.selectedRange().location
            guard cursor > 0 else { return }

            if cursor >= 2 {
                let r = NSRange(location: cursor - 2, length: 2)
                let snippet = s.substring(with: r)
                if snippet == "* ", isLineStart(s, cursor - 2) {
                    return swap(textView, r, "• ")
                }
                if snippet == "- ", isLineStart(s, cursor - 2) {
                    return swap(textView, r, "– ")
                }
            }

            if cursor >= 3 {
                let r = NSRange(location: cursor - 3, length: 3)
                let snippet = s.substring(with: r)
                if snippet == "[ ]", isLineStart(s, cursor - 3) {
                    swap(textView, r, "○ ")
                    textView.setSelectedRange(NSRange(location: cursor - 1, length: 0))
                    return
                }
                if snippet == "[x]", isLineStart(s, cursor - 3) {
                    swap(textView, r, "● ")
                    textView.setSelectedRange(NSRange(location: cursor - 1, length: 0))
                    return
                }
            }
        }

        private func isLineStart(_ s: NSString, _ pos: Int) -> Bool {
            s.lineRange(for: NSRange(location: pos, length: 0)).location == pos
        }

        private func swap(_ tv: NSTextView, _ range: NSRange, _ str: String) {
            guard tv.shouldChangeText(in: range, replacementString: str) else { return }
            tv.textStorage?.replaceCharacters(in: range, with: str)
            tv.didChangeText()
        }
    }
}

// MARK: - MarkdownStylist

enum MarkdownStylist {

    // MARK: Colors
    static let bgColor        = NSColor(hex: "#0f1117")
    static let textColor      = NSColor(hex: "#e2e8f0")
    static let dimColor       = NSColor(hex: "#6b7a99")
    static let codeBackground = NSColor(hex: "#1f2235")
    static let blueColor      = NSColor(hex: "#4a9eff")
    static let greenColor     = NSColor(hex: "#4ecb71")

    // MARK: Fonts
    static let baseFont   = NSFont.systemFont(ofSize: 14)
    static let monoFont   = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    /// 0.01pt font — effectively invisible and takes zero horizontal space
    static let hiddenFont = NSFont.systemFont(ofSize: 0.01)

    static let baseAttributes: [NSAttributedString.Key: Any] = [
        .font: baseFont,
        .foregroundColor: textColor
    ]

    // MARK: - Apply

    static func apply(to textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let text = textView.string
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: storage.length)

        storage.beginEditing()

        // Reset to base style
        storage.setAttributes([
            .font: baseFont,
            .foregroundColor: textColor,
            .paragraphStyle: baseParagraphStyle
        ], range: fullRange)

        // Line-level markup
        var pos = 0
        for line in text.components(separatedBy: "\n") {
            let len = (line as NSString).length
            applyLine(storage: storage, line: line, lineRange: NSRange(location: pos, length: len), lineStart: pos)
            pos += len + 1
        }

        // Inline markup (order matters: bold before italic)
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

        storage.endEditing()
    }

    // MARK: - Line styling

    private static func applyLine(storage: NSTextStorage, line: String, lineRange: NSRange, lineStart: Int) {
        if line.hasPrefix("### ") {
            heading(storage, lineRange, lineStart, prefixLen: 4, size: 16)
        } else if line.hasPrefix("## ") {
            heading(storage, lineRange, lineStart, prefixLen: 3, size: 19)
        } else if line.hasPrefix("# ") {
            heading(storage, lineRange, lineStart, prefixLen: 2, size: 24)
        } else if line.hasPrefix("> ") {
            hide(storage, NSRange(location: lineStart, length: 2))
            let rest = NSRange(location: lineStart + 2, length: max(0, lineRange.length - 2))
            storage.addAttribute(.foregroundColor, value: NSColor(hex: "#c4d4e8"), range: rest)
        } else if line.hasPrefix("• ") {
            let ps = listStyle(firstLine: 24, indent: 56)
            storage.addAttribute(.paragraphStyle, value: ps, range: lineRange)
            let bulletRange = NSRange(location: lineStart, length: min(1, lineRange.length))
            storage.addAttribute(.foregroundColor, value: blueColor, range: bulletRange)
            storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 20), range: bulletRange)
        } else if line.hasPrefix("– ") {
            let ps = listStyle(firstLine: 24, indent: 56)
            storage.addAttribute(.paragraphStyle, value: ps, range: lineRange)
            storage.addAttribute(.foregroundColor, value: dimColor,
                                  range: NSRange(location: lineStart, length: min(2, lineRange.length)))
        } else if line.hasPrefix("○ ") || line.hasPrefix("● ") {
            let checked = line.hasPrefix("●")
            let ps = listStyle(firstLine: 24, indent: 60)
            storage.addAttribute(.paragraphStyle, value: ps, range: lineRange)
            let circleRange = NSRange(location: lineStart, length: min(1, lineRange.length))
            storage.addAttribute(.foregroundColor, value: checked ? greenColor : dimColor, range: circleRange)
            storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 19), range: circleRange)
            if checked && lineRange.length > 2 {
                let textRange = NSRange(location: lineStart + 2, length: lineRange.length - 2)
                storage.addAttribute(.foregroundColor, value: dimColor, range: textRange)
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: textRange)
            }
        } else if line == "---" || line == "***" || line == "___" {
            // Render as a full-width horizontal rule via NSTextBlock background
            let block = NSTextBlock()
            block.backgroundColor = NSColor(hex: "#252a3d")
            let ps = NSMutableParagraphStyle()
            ps.textBlocks = [block]
            ps.minimumLineHeight = 1
            ps.maximumLineHeight = 1
            ps.paragraphSpacingBefore = 8
            ps.paragraphSpacing = 8
            storage.addAttribute(.paragraphStyle, value: ps, range: lineRange)
            storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 0.01), range: lineRange)
            storage.addAttribute(.foregroundColor, value: NSColor.clear, range: lineRange)
        }
    }

    // MARK: - Heading

    private static func heading(_ storage: NSTextStorage, _ lineRange: NSRange, _ lineStart: Int, prefixLen: Int, size: CGFloat) {
        storage.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: size), range: lineRange)
        storage.addAttribute(.foregroundColor, value: textColor, range: lineRange)
        hide(storage, NSRange(location: lineStart, length: prefixLen))
    }

    // MARK: - Generic inline helper

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
            let full    = m.range
            let open    = NSRange(location: full.location, length: markerLen)
            let close   = NSRange(location: full.location + full.length - markerLen, length: markerLen)
            let content = NSRange(location: full.location + markerLen, length: full.length - markerLen * 2)
            contentStyle(content, storage)
            hide(storage, open)
            hide(storage, close)
        }
    }

    // MARK: - Code (special: needs background + mono font on full range including markers)

    private static func applyCode(_ storage: NSTextStorage, text: NSString) {
        guard let regex = try? NSRegularExpression(pattern: "`([^`\n]+)`") else { return }
        regex.enumerateMatches(in: text as String, range: NSRange(location: 0, length: text.length)) { match, _, _ in
            guard let m = match, m.range.length >= 3 else { return }
            let full    = m.range
            let open    = NSRange(location: full.location, length: 1)
            let close   = NSRange(location: full.location + full.length - 1, length: 1)
            let content = NSRange(location: full.location + 1, length: full.length - 2)
            storage.addAttribute(.font, value: monoFont, range: content)
            storage.addAttribute(.backgroundColor, value: codeBackground, range: content)
            storage.addAttribute(.foregroundColor, value: greenColor, range: content)
            hide(storage, open)
            hide(storage, close)
        }
    }

    // MARK: - Helpers

    /// Makes characters invisible and zero-width by using a 0.01pt font + clear color.
    private static func hide(_ storage: NSTextStorage, _ range: NSRange) {
        guard range.length > 0 else { return }
        storage.addAttribute(.font, value: hiddenFont, range: range)
        storage.addAttribute(.foregroundColor, value: NSColor.clear, range: range)
    }

    static let baseParagraphStyle: NSParagraphStyle = {
        let ps = NSMutableParagraphStyle()
        ps.lineSpacing = 4
        return ps
    }()

    private static func listStyle(firstLine: CGFloat, indent: CGFloat) -> NSParagraphStyle {
        let ps = NSMutableParagraphStyle()
        ps.firstLineHeadIndent = firstLine
        ps.headIndent = indent
        ps.lineSpacing = 4
        return ps
    }
}

// MARK: - NSColor hex init

extension NSColor {
    convenience init(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h = String(h.dropFirst()) }
        var rgb: UInt64 = 0
        Scanner(string: h).scanHexInt64(&rgb)
        let r = CGFloat((rgb >> 16) & 0xFF) / 255
        let g = CGFloat((rgb >> 8)  & 0xFF) / 255
        let b = CGFloat(rgb         & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}
#endif
