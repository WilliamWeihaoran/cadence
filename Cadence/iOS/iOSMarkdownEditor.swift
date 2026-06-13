#if os(iOS)
import SwiftUI
import UIKit

struct iOSMarkdownEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool

    func makeUIView(context: UIViewRepresentableContext<iOSMarkdownEditor>) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.keyboardDismissMode = .interactive
        textView.alwaysBounceVertical = true
        textView.isScrollEnabled = true
        textView.textContainerInset = UIEdgeInsets(top: 14, left: 14, bottom: 18, right: 14)
        textView.textContainer.lineFragmentPadding = 2
        textView.autocorrectionType = .yes
        textView.autocapitalizationType = .sentences
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.tintColor = UIColor(Theme.blue)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.coordinator.applyMarkdownStyle(to: textView, text: text)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: UIViewRepresentableContext<iOSMarkdownEditor>) {
        context.coordinator.parent = self

        if textView.text != text {
            let selection = textView.selectedRange
            context.coordinator.applyMarkdownStyle(to: textView, text: text)
            textView.selectedRange = context.coordinator.clamped(selection, in: textView.textStorage)
        } else {
            context.coordinator.refreshThemeIfNeeded(on: textView)
        }

        if isFocused, !textView.isFirstResponder {
            textView.becomeFirstResponder()
        } else if !isFocused, textView.isFirstResponder {
            textView.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: iOSMarkdownEditor
        private var isApplyingStyle = false
        private var themeSignature = iOSMarkdownThemeSignature.current

        init(parent: iOSMarkdownEditor) {
            self.parent = parent
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.isFocused = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.isFocused = false
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingStyle else { return }
            let updatedText = textView.text ?? ""
            parent.text = updatedText

            let selection = textView.selectedRange
            applyMarkdownStyle(to: textView, text: updatedText)
            textView.selectedRange = clamped(selection, in: textView.textStorage)
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText replacement: String
        ) -> Bool {
            guard replacement == "\n" else { return true }
            guard let currentText = textView.text as NSString? else { return true }
            let prefix = currentText.substring(to: min(range.location, currentText.length))
            guard let currentLine = prefix.components(separatedBy: "\n").last else { return true }
            guard let continuation = iOSMarkdownListContinuation.continuation(after: currentLine) else { return true }

            let replacementText = "\n\(continuation)"
            guard let textRange = textView.textRange(from: range) else { return true }
            textView.replace(textRange, withText: replacementText)
            textViewDidChange(textView)
            return false
        }

        func refreshThemeIfNeeded(on textView: UITextView) {
            let current = iOSMarkdownThemeSignature.current
            guard current != themeSignature else { return }
            themeSignature = current
            let selection = textView.selectedRange
            applyMarkdownStyle(to: textView, text: textView.text ?? "")
            textView.selectedRange = clamped(selection, in: textView.textStorage)
        }

        func applyMarkdownStyle(to textView: UITextView, text: String) {
            isApplyingStyle = true
            defer { isApplyingStyle = false }

            let storage = textView.textStorage
            let styled = iOSMarkdownStyler.attributedString(for: text)
            storage.setAttributedString(styled)
            textView.typingAttributes = iOSMarkdownStyler.baseTypingAttributes
        }

        func clamped(_ range: NSRange, in storage: NSTextStorage) -> NSRange {
            let location = min(max(0, range.location), storage.length)
            let length = min(range.length, max(0, storage.length - location))
            return NSRange(location: location, length: length)
        }
    }
}

struct iOSMarkdownPreview: View {
    let markdown: String

    private var trimmedMarkdown: String {
        markdown.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var renderedMarkdown: AttributedString {
        if let rendered = try? AttributedString(markdown: markdown) {
            return rendered
        }
        return AttributedString(markdown)
    }

    var body: some View {
        ScrollView {
            if trimmedMarkdown.isEmpty {
                Text("Nothing to preview")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.dim.opacity(0.62))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 18)
            } else {
                Text(renderedMarkdown)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Theme.text)
                    .lineSpacing(5)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 18)
            }
        }
        .scrollIndicators(.hidden)
        .background(Theme.surface)
    }
}

enum iOSMarkdownEditorMode: String, CaseIterable, Identifiable {
    case edit = "Edit"
    case preview = "Preview"

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .edit: return "pencil"
        case .preview: return "doc.richtext"
        }
    }
}

struct iOSMarkdownModePicker: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var mode: iOSMarkdownEditorMode
    var compact = false

    private var showsLabels: Bool {
        horizontalSizeClass == .regular && !compact
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(iOSMarkdownEditorMode.allCases) { candidate in
                Button {
                    mode = candidate
                } label: {
                    modeLabel(for: candidate)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(candidate.rawValue)
            }
        }
        .padding(2)
        .background(Theme.surfaceElevated.opacity(0.56))
        .clipShape(RoundedRectangle(cornerRadius: compact ? 8 : 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: compact ? 8 : 9, style: .continuous)
                .strokeBorder(Theme.borderSubtle.opacity(0.46), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func modeLabel(for candidate: iOSMarkdownEditorMode) -> some View {
        if showsLabels {
            Label(candidate.rawValue, systemImage: candidate.systemImage)
                .labelStyle(.titleAndIcon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(mode == candidate ? Theme.text : Theme.dim)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(mode == candidate ? Theme.blue.opacity(0.18) : Color.clear)
                )
        } else {
            Image(systemName: candidate.systemImage)
                .font(.system(size: compact ? 11 : 12, weight: .semibold))
                .foregroundStyle(mode == candidate ? Theme.text : Theme.dim)
                .frame(width: compact ? 27 : 30, height: compact ? 26 : 28)
                .background(
                    RoundedRectangle(cornerRadius: compact ? 6 : 7, style: .continuous)
                        .fill(mode == candidate ? Theme.blue.opacity(0.18) : Color.clear)
                )
        }
    }
}

struct iOSMarkdownEditingSurface: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var text: String
    @Binding var isFocused: Bool
    @Binding var mode: iOSMarkdownEditorMode
    let placeholder: String

    var body: some View {
        VStack(spacing: 0) {
            if mode == .preview {
                iOSMarkdownPreview(markdown: text)
            } else {
                ZStack(alignment: .topLeading) {
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isFocused {
                        iOSMarkdownEmptyPrompt(placeholder: placeholder)
                    }

                    iOSMarkdownEditor(text: $text, isFocused: $isFocused)
                        .background(Color.clear)
                }
                .background(Theme.surface)
            }

            Divider().background(Theme.borderSubtle.opacity(0.65))

            iOSMarkdownStatusBar(
                wordCount: wordCount,
                lineCount: lineCount,
                isPreviewing: mode == .preview,
                isRegularWidth: horizontalSizeClass == .regular
            )
        }
        .background(Theme.surface)
    }

    private var wordCount: Int {
        text
            .split { $0.isWhitespace || $0.isNewline }
            .count
    }

    private var lineCount: Int {
        max(1, text.components(separatedBy: .newlines).count)
    }
}

private struct iOSMarkdownEmptyPrompt: View {
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(placeholder)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text.opacity(0.74))

            VStack(alignment: .leading, spacing: 5) {
                iOSMarkdownHintRow(text: "# Heading")
                iOSMarkdownHintRow(text: "- [ ] Task")
                iOSMarkdownHintRow(text: "**Bold** · [[Link]] · #tag")
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
    }
}

private struct iOSMarkdownHintRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(Theme.dim.opacity(0.76))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Theme.surfaceElevated.opacity(0.38))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct iOSMarkdownStatusBar: View {
    let wordCount: Int
    let lineCount: Int
    let isPreviewing: Bool
    let isRegularWidth: Bool

    var body: some View {
        HStack(spacing: 8) {
            Label(isPreviewing ? "Rendered" : "Markdown", systemImage: isPreviewing ? "doc.richtext" : "pencil")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isPreviewing ? Theme.green : Theme.blue)

            Spacer(minLength: 8)

            if isRegularWidth {
                Text("\(lineCount) \(lineCount == 1 ? "line" : "lines")")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.dim)
            }

            Text("\(wordCount) \(wordCount == 1 ? "word" : "words")")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.dim)
        }
        .padding(.horizontal, isRegularWidth ? 14 : 12)
        .frame(height: isRegularWidth ? 34 : 32)
        .background(Theme.bg.opacity(0.34))
    }
}

private enum iOSMarkdownStyler {
    static var baseFont: UIFont { .preferredFont(forTextStyle: .body) }
    static var monoFont: UIFont { .monospacedSystemFont(ofSize: 14, weight: .regular) }

    static var baseTypingAttributes: [NSAttributedString.Key: Any] {
        [
            .font: baseFont,
            .foregroundColor: UIColor(Theme.text),
            .paragraphStyle: baseParagraphStyle
        ]
    }

    private static var baseParagraphStyle: NSMutableParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.paragraphSpacing = 5
        return paragraph
    }

    static func attributedString(for markdown: String) -> NSAttributedString {
        let storage = NSMutableAttributedString(string: markdown)
        let fullRange = NSRange(location: 0, length: storage.length)
        guard fullRange.length > 0 else {
            return NSAttributedString(string: "", attributes: baseTypingAttributes)
        }

        storage.setAttributes(baseTypingAttributes, range: fullRange)

        let tableRows = MarkdownTableParser.rowStyles(in: markdown)
        var location = 0
        for (lineIndex, line) in markdown.components(separatedBy: "\n").enumerated() {
            let length = (line as NSString).length
            let range = NSRange(location: location, length: length)
            styleLine(storage, line: line, lineIndex: lineIndex, range: range, tableRows: tableRows)
            location += length + 1
        }

        styleInline(storage, markdown: markdown)
        return storage
    }

    private static func styleLine(
        _ storage: NSMutableAttributedString,
        line: String,
        lineIndex: Int,
        range: NSRange,
        tableRows: [Int: MarkdownTableRowStyle]
    ) {
        guard range.length > 0 else { return }

        if let heading = headingMatch(in: line) {
            let size = headingSize(for: heading.level)
            storage.addAttributes([
                .font: UIFont.systemFont(ofSize: size, weight: .bold),
                .foregroundColor: UIColor(Theme.text)
            ], range: range)
            storage.addAttribute(.foregroundColor, value: UIColor(Theme.dim), range: heading.markerRange.shifted(by: range.location))
            return
        }

        if tableRows[lineIndex] != nil {
            storage.addAttributes([
                .font: monoFont,
                .foregroundColor: UIColor(Theme.muted),
                .backgroundColor: UIColor(Theme.surfaceElevated).withAlphaComponent(0.24)
            ], range: range)
            return
        }

        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if isDivider(trimmed) {
            storage.addAttributes([
                .foregroundColor: UIColor(Theme.borderSubtle),
                .font: monoFont
            ], range: range)
            return
        }

        if let quote = quotePrefixRange(in: line) {
            let paragraph = baseParagraphStyle
            paragraph.firstLineHeadIndent = 18
            paragraph.headIndent = 18
            storage.addAttributes([
                .paragraphStyle: paragraph,
                .foregroundColor: UIColor(Theme.muted),
                .font: italicFont(from: baseFont)
            ], range: range)
            storage.addAttribute(.foregroundColor, value: UIColor(Theme.blue), range: quote.shifted(by: range.location))
            return
        }

        if let prefix = listPrefixRange(in: line) {
            storage.addAttributes([
                .foregroundColor: UIColor(Theme.muted)
            ], range: prefix.shifted(by: range.location))
        }
    }

    private static func styleInline(_ storage: NSMutableAttributedString, markdown: String) {
        let nsText = markdown as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        applyRegex(#"\*\*\*(.+?)\*\*\*"#, in: markdown) { match in
            guard match.numberOfRanges >= 2 else { return }
            let content = match.range(at: 1)
            storage.addAttribute(.font, value: italicFont(from: boldFont(at: content.location, in: storage)), range: content)
            storage.addAttribute(.foregroundColor, value: UIColor(Theme.dim), range: match.markerRange(contentRange: content))
        }

        applyRegex(#"\*\*(.+?)\*\*"#, in: markdown) { match in
            guard match.numberOfRanges >= 2 else { return }
            let content = match.range(at: 1)
            storage.addAttribute(.font, value: boldFont(at: content.location, in: storage), range: content)
            storage.addAttribute(.foregroundColor, value: UIColor(Theme.dim), range: match.markerRange(contentRange: content))
        }

        applyRegex(#"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#, in: markdown) { match in
            guard match.numberOfRanges >= 2 else { return }
            let content = match.range(at: 1)
            storage.addAttribute(.font, value: italicFont(from: font(at: content.location, in: storage)), range: content)
            storage.addAttribute(.foregroundColor, value: UIColor(Theme.dim), range: match.markerRange(contentRange: content))
        }

        applyRegex(#"~~(.+?)~~"#, in: markdown) { match in
            guard match.numberOfRanges >= 2 else { return }
            let content = match.range(at: 1)
            storage.addAttributes([
                .foregroundColor: UIColor(Theme.dim),
                .strikethroughStyle: NSUnderlineStyle.single.rawValue
            ], range: content)
        }

        applyRegex(#"`([^`\n]+?)`"#, in: markdown) { match in
            guard match.numberOfRanges >= 2 else { return }
            storage.addAttributes([
                .font: monoFont,
                .foregroundColor: UIColor(Theme.amberLight),
                .backgroundColor: UIColor(Theme.surfaceElevated).withAlphaComponent(0.65)
            ], range: match.range(at: 1))
        }

        applyRegex(#"==(.+?)=="#, in: markdown) { match in
            guard match.numberOfRanges >= 2 else { return }
            storage.addAttributes([
                .foregroundColor: UIColor(Theme.amberLight),
                .backgroundColor: UIColor(Theme.amber).withAlphaComponent(0.18)
            ], range: match.range(at: 1))
        }

        applyRegex(#"(\[[^\]]+\]\([^)]+\))"#, in: markdown) { match in
            storage.addAttributes([
                .foregroundColor: UIColor(Theme.blueLight),
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ], range: match.range(at: 1))
        }

        applyRegex(#"(\[\[[^\]]+\]\])"#, in: markdown) { match in
            storage.addAttributes([
                .foregroundColor: UIColor(Theme.blueLight),
                .backgroundColor: UIColor(Theme.blue).withAlphaComponent(0.10)
            ], range: match.range(at: 1))
        }

        applyRegex(#"(?<![\p{L}\p{N}_])#([A-Za-z0-9][A-Za-z0-9_-]*)"#, in: markdown) { match in
            storage.addAttributes([
                .foregroundColor: UIColor(Theme.greenLight),
                .backgroundColor: UIColor(Theme.green).withAlphaComponent(0.10)
            ], range: match.range)
        }

        applyRegex(#"(?s)(```.*?```)"#, in: markdown) { match in
            storage.addAttributes([
                .font: monoFont,
                .foregroundColor: UIColor(Theme.muted),
                .backgroundColor: UIColor(Theme.surfaceElevated).withAlphaComponent(0.48)
            ], range: NSIntersectionRange(match.range(at: 1), fullRange))
        }
    }

    private static func applyRegex(
        _ pattern: String,
        in text: String,
        handler: (NSTextCheckingResult) -> Void
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let range = NSRange(location: 0, length: (text as NSString).length)
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match else { return }
            handler(match)
        }
    }

    private static func headingMatch(in line: String) -> (level: Int, markerRange: NSRange)? {
        guard let regex = try? NSRegularExpression(pattern: #"^(#{1,6})\s+"#) else { return nil }
        let nsLine = line as NSString
        guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)),
              match.numberOfRanges >= 2 else { return nil }
        return (match.range(at: 1).length, match.range(at: 1))
    }

    private static func headingSize(for level: Int) -> CGFloat {
        switch level {
        case 1: return 28
        case 2: return 24
        case 3: return 21
        case 4: return 18
        case 5: return 16
        default: return 15
        }
    }

    private static func quotePrefixRange(in line: String) -> NSRange? {
        guard let regex = try? NSRegularExpression(pattern: #"^\s*>+\s?"#) else { return nil }
        return regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length))?.range
    }

    private static func listPrefixRange(in line: String) -> NSRange? {
        guard let regex = try? NSRegularExpression(pattern: #"^\s*(?:[-*+]|\d+[.)]|\[[ xX]\])\s+"#) else { return nil }
        return regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length))?.range
    }

    private static func isDivider(_ line: String) -> Bool {
        guard line.count >= 3 else { return false }
        return line.allSatisfy { $0 == "-" || $0 == "*" || $0 == "_" }
    }

    private static func font(at location: Int, in storage: NSAttributedString) -> UIFont {
        guard storage.length > 0 else { return baseFont }
        let clampedLocation = min(max(0, location), storage.length - 1)
        return storage.attribute(.font, at: clampedLocation, effectiveRange: nil) as? UIFont ?? baseFont
    }

    private static func boldFont(at location: Int, in storage: NSAttributedString) -> UIFont {
        let current = font(at: location, in: storage)
        return UIFont.systemFont(ofSize: current.pointSize, weight: .bold)
    }

    private static func italicFont(from font: UIFont) -> UIFont {
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(.traitItalic)) else {
            return UIFont.italicSystemFont(ofSize: font.pointSize)
        }
        return UIFont(descriptor: descriptor, size: font.pointSize)
    }
}

private enum iOSMarkdownListContinuation {
    static func continuation(after line: String) -> String? {
        let indentation = String(line.prefix { $0 == " " || $0 == "\t" })
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        if let checkbox = match(#"^[-*+]\s+\[[ xX]\]\s+"#, in: trimmed), !checkbox.isEmpty {
            return indentation + "- [ ] "
        }

        if let bullet = match(#"^[-*+]\s+"#, in: trimmed), !bullet.isEmpty {
            return indentation + "- "
        }

        if let ordered = orderedPrefix(in: trimmed) {
            return indentation + "\(ordered + 1). "
        }

        return nil
    }

    private static func orderedPrefix(in text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"^(\d+)[.)]\s+"#) else { return nil }
        let nsText = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)),
              match.numberOfRanges >= 2 else { return nil }
        return Int(nsText.substring(with: match.range(at: 1)))
    }

    private static func match(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsText = text as NSString
        guard let result = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)) else { return nil }
        return nsText.substring(with: result.range)
    }
}

private struct iOSMarkdownThemeSignature: Equatable {
    let theme: String

    static var current: iOSMarkdownThemeSignature {
        iOSMarkdownThemeSignature(theme: ThemeManager.shared.selectedTheme.rawValue)
    }
}

private extension UITextView {
    func textRange(from nsRange: NSRange) -> UITextRange? {
        let start = position(from: beginningOfDocument, offset: nsRange.location) ?? beginningOfDocument
        let end = position(from: start, offset: nsRange.length) ?? start
        return textRange(from: start, to: end)
    }
}

private extension NSRange {
    func shifted(by offset: Int) -> NSRange {
        NSRange(location: location + offset, length: length)
    }
}

private extension NSTextCheckingResult {
    func markerRange(contentRange: NSRange) -> NSRange {
        NSRange(location: range.location, length: max(0, contentRange.location - range.location))
    }
}
#endif
