#if os(macOS)
import AppKit

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

enum MarkdownReferenceKind: Hashable {
    case note
    case task
}

struct MarkdownReferenceTarget: Hashable {
    let kind: MarkdownReferenceKind
    let id: UUID?
    let title: String
}

struct MarkdownReferenceSuggestion: Identifiable, Hashable {
    let kind: MarkdownReferenceKind
    let targetID: UUID
    let title: String
    let subtitle: String
    let markdown: String

    var id: String {
        "\(kind)-\(targetID.uuidString)"
    }

    static func note(_ note: Note) -> MarkdownReferenceSuggestion {
        MarkdownReferenceSuggestion(
            kind: .note,
            targetID: note.id,
            title: note.displayTitle,
            subtitle: note.kind.rawValue.capitalized,
            markdown: NoteReferenceParser.noteReferenceMarkdown(for: note)
        )
    }

    static func task(_ task: AppTask) -> MarkdownReferenceSuggestion {
        MarkdownReferenceSuggestion(
            kind: .task,
            targetID: task.id,
            title: task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Task" : task.title,
            subtitle: task.containerName.isEmpty ? task.status.rawValue.capitalized : task.containerName,
            markdown: NoteReferenceParser.taskReferenceMarkdown(for: task)
        )
    }
}

struct MarkdownTagSuggestion: Identifiable, Hashable {
    let name: String
    let slug: String
    let desc: String
    let colorHex: String
    let isArchived: Bool

    var id: String { slug }

    static func tag(_ tag: Tag) -> MarkdownTagSuggestion {
        MarkdownTagSuggestion(
            name: tag.name,
            slug: tag.slug,
            desc: tag.desc,
            colorHex: tag.colorHex,
            isArchived: tag.isArchived
        )
    }
}

struct MarkdownImageLayoutInfo {
    let id: UUID
    let altText: String
    let image: NSImage?
    let displayWidth: CGFloat
    let pixelSize: CGSize

    func fittedSize(maxWidth: CGFloat) -> CGSize {
        let width = min(max(1, displayWidth), max(1, maxWidth))
        let aspect = pixelSize.height / max(pixelSize.width, 1)
        return CGSize(width: width, height: max(60, width * aspect))
    }
}

struct MarkdownTaskEmbedSubtaskRenderInfo: Hashable {
    let id: UUID
    let title: String
    let isDone: Bool
    let order: Int
}

struct MarkdownTaskEmbedRenderInfo: Hashable {
    static let untitledTaskTitle = "Untitled Task"
    static let compactCardHeight: CGFloat = 68
    static let subtaskCardHeight: CGFloat = 96
    static let lineHeightPadding: CGFloat = 12
    static let maxCardWidth: CGFloat = 640

    let id: UUID
    let title: String
    let statusRaw: String
    let priorityRaw: String
    let sectionName: String
    let containerName: String
    let containerColorHex: String
    let dueDate: String
    let scheduledDate: String
    let scheduledStartMin: Int
    let estimatedMinutes: Int
    let actualMinutes: Int
    let recurrenceRaw: String
    let isDone: Bool
    let isCancelled: Bool
    let isMissing: Bool
    let subtasks: [MarkdownTaskEmbedSubtaskRenderInfo]

    var subtaskTotalCount: Int {
        subtasks.count
    }

    var completedSubtaskCount: Int {
        subtasks.filter(\.isDone).count
    }

    var visibleSubtasks: [MarkdownTaskEmbedSubtaskRenderInfo] {
        Array(subtasks.prefix(3))
    }

    var hiddenSubtaskCount: Int {
        max(0, subtasks.count - visibleSubtasks.count)
    }

    var hasSubtasks: Bool {
        !subtasks.isEmpty
    }

    var cardHeight: CGFloat {
        hasSubtasks ? Self.subtaskCardHeight : Self.compactCardHeight
    }

    var paragraphLineHeight: CGFloat {
        cardHeight + Self.lineHeightPadding
    }

    static func task(_ task: AppTask) -> MarkdownTaskEmbedRenderInfo {
        let subtaskInfos = (task.subtasks ?? [])
            .sorted {
                if $0.order == $1.order {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return $0.order < $1.order
            }
            .map {
                MarkdownTaskEmbedSubtaskRenderInfo(
                    id: $0.id,
                    title: $0.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    isDone: $0.isDone,
                    order: $0.order
                )
            }

        return MarkdownTaskEmbedRenderInfo(
            id: task.id,
            title: task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? untitledTaskTitle : task.title,
            statusRaw: task.statusRaw,
            priorityRaw: task.priorityRaw,
            sectionName: task.resolvedSectionName,
            containerName: task.containerName,
            containerColorHex: task.containerColor,
            dueDate: task.dueDate,
            scheduledDate: task.scheduledDate,
            scheduledStartMin: task.scheduledStartMin,
            estimatedMinutes: task.estimatedMinutes,
            actualMinutes: task.actualMinutes,
            recurrenceRaw: task.recurrenceRaw,
            isDone: task.isDone,
            isCancelled: task.isCancelled,
            isMissing: false,
            subtasks: subtaskInfos
        )
    }

    static func missing(reference: MarkdownTaskEmbedReference) -> MarkdownTaskEmbedRenderInfo {
        let title = reference.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return MarkdownTaskEmbedRenderInfo(
            id: reference.id,
            title: title.isEmpty ? "Missing Task" : title,
            statusRaw: TaskStatus.cancelled.rawValue,
            priorityRaw: TaskPriority.none.rawValue,
            sectionName: "",
            containerName: "",
            containerColorHex: TaskSectionDefaults.defaultColorHex,
            dueDate: "",
            scheduledDate: "",
            scheduledStartMin: -1,
            estimatedMinutes: 0,
            actualMinutes: 0,
            recurrenceRaw: TaskRecurrenceRule.none.rawValue,
            isDone: false,
            isCancelled: false,
            isMissing: true,
            subtasks: []
        )
    }
}

struct MarkdownTaskEmbedLayoutInfo: Hashable {
    let task: MarkdownTaskEmbedRenderInfo
}

enum MarkdownTaskEmbedField: Hashable {
    case title
    case status
    case priority
    case container
    case section
    case scheduledDate
    case dueDate
    case estimate
    case recurrence
}

struct MarkdownTaskEmbedHitRects {
    let card: NSRect
    let checkbox: NSRect
}

struct MarkdownTaskEmbedSubtaskHitRect: Hashable {
    let subtaskID: UUID?
    let checkbox: NSRect?
    let text: NSRect
    let full: NSRect

    static func subtask(id: UUID, checkbox: NSRect, text: NSRect, full: NSRect) -> MarkdownTaskEmbedSubtaskHitRect {
        MarkdownTaskEmbedSubtaskHitRect(subtaskID: id, checkbox: checkbox, text: text, full: full)
    }

    static func overflow(text: NSRect, full: NSRect) -> MarkdownTaskEmbedSubtaskHitRect {
        MarkdownTaskEmbedSubtaskHitRect(subtaskID: nil, checkbox: nil, text: text, full: full)
    }
}

enum MarkdownTaskEmbedSubtaskHitTarget: Hashable {
    case checkbox(UUID)
    case openInspector
}

enum MarkdownTaskEmbedSubtaskHitTesting {
    static func hit(
        at point: NSPoint,
        in rects: [MarkdownTaskEmbedSubtaskHitRect],
        checkboxPadding: CGFloat = 4
    ) -> MarkdownTaskEmbedSubtaskHitTarget? {
        for rect in rects {
            if let subtaskID = rect.subtaskID,
               let checkbox = rect.checkbox,
               checkbox.insetBy(dx: -checkboxPadding, dy: -checkboxPadding).contains(point) {
                return .checkbox(subtaskID)
            }

            if rect.text.insetBy(dx: -3, dy: -3).contains(point) {
                return .openInspector
            }
        }

        return nil
    }
}

struct MarkdownTaskEmbedReference: Hashable {
    let id: UUID
    let title: String
    let range: NSRange
}

enum MarkdownTaskEmbedParser {
    nonisolated static func draftTitle(in line: String) -> String? {
        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)
        let patterns = [
            #"^\s*\(\s*\)\s+(.+)$"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: line, range: fullRange),
                  match.numberOfRanges > 1,
                  match.range(at: 1).location != NSNotFound else { continue }

            let title = nsLine.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty { return title }
        }
        return nil
    }

    nonisolated static func standaloneTaskReference(in line: String, lineStart: Int = 0) -> MarkdownTaskEmbedReference? {
        guard let regex = try? NSRegularExpression(pattern: #"^\s*\[\[task:([0-9A-Fa-f-]{36})\|([^\]\n]+)\]\]\s*$"#) else {
            return nil
        }
        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)
        guard let match = regex.firstMatch(in: line, range: fullRange),
              match.numberOfRanges >= 3,
              match.range(at: 1).location != NSNotFound,
              match.range(at: 2).location != NSNotFound,
              let id = UUID(uuidString: nsLine.substring(with: match.range(at: 1))) else {
            return nil
        }

        let title = nsLine.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
        return MarkdownTaskEmbedReference(
            id: id,
            title: title,
            range: NSRange(location: lineStart + match.range.location, length: match.range.length)
        )
    }

    nonisolated static func referenceTitleRange(in markdown: String, lineStart: Int = 0) -> NSRange? {
        guard let regex = try? NSRegularExpression(pattern: #"^\s*\[\[task:[0-9A-Fa-f-]{36}\|([^\]\n]+)\]\]\s*$"#) else {
            return nil
        }
        let nsMarkdown = markdown as NSString
        let match = regex.firstMatch(in: markdown, range: NSRange(location: 0, length: nsMarkdown.length))
        guard let match, match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound else {
            return nil
        }
        return NSRange(location: lineStart + match.range(at: 1).location, length: match.range(at: 1).length)
    }

    nonisolated static func legacyChecklistMarkerRange(in line: String, lineStart: Int = 0) -> NSRange? {
        let nsLine = line as NSString
        guard nsLine.length > 0,
              let regex = try? NSRegularExpression(pattern: #"^[ \t]*[○●✓]\s+"#),
              let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)) else {
            return nil
        }

        let prefix = nsLine.substring(with: match.range)
        guard let markerOffset = prefix.firstIndex(where: { $0 == "○" || $0 == "●" || $0 == "✓" }) else {
            return nil
        }
        let distance = prefix.distance(from: prefix.startIndex, to: markerOffset)
        return NSRange(location: lineStart + distance, length: 1)
    }

    nonisolated static func isLegacyChecklistMarkerCharacter(_ characterIndex: Int, in line: String, lineStart: Int = 0) -> Bool {
        guard let markerRange = legacyChecklistMarkerRange(in: line, lineStart: lineStart) else { return false }
        return NSLocationInRange(characterIndex, markerRange)
    }
}

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

enum MarkdownListSupport {
    static func normalizedMarkdownListPrefixes(in text: String) -> String {
        var changed = false
        let lines = text.components(separatedBy: "\n").map { line -> String in
            guard let normalized = normalizedMarkdownListLine(line) else { return line }
            changed = true
            return normalized
        }
        return changed ? lines.joined(separator: "\n") : text
    }

    static func indentationPrefix(in text: NSString, replacingRange: NSRange) -> String? {
        let lineRange = text.lineRange(for: replacingRange)
        let prefixRange = NSRange(location: lineRange.location, length: replacingRange.location - lineRange.location)
        let prefix = text.substring(with: prefixRange)
        guard prefix.allSatisfy({ $0 == " " || $0 == "\t" }) else { return nil }
        return normalizedIndentation(prefix)
    }

    static func orderedMarker(forIndentation indentation: String) -> String {
        let level = min(indentation.count / 4, 4)
        return MarkdownStylist.orderedMarker(for: level, index: 1)
    }

    static func orderedLevel(forIndentation indentation: String) -> Int {
        min(normalizedIndentation(indentation).count / 4, 4)
    }

    static func visualLevel(forIndentation indentation: String) -> Int {
        let width = indentationWidth(indentation)
        guard width > 0 else { return 0 }
        return min(max(1, (width + 3) / 4), 4)
    }

    static func orderedIndex(for marker: String) -> Int? {
        let normalized = marker.trimmingCharacters(in: .whitespaces)
        let bare = normalized.hasSuffix(".") ? String(normalized.dropLast()) : normalized
        if let number = Int(bare) {
            return number
        }
        if let romanValue = MarkdownStylist.romanToInt(bare.lowercased()) {
            return romanValue
        }
        if bare.count == 1, let scalar = bare.lowercased().unicodeScalars.first,
           (97...122).contains(scalar.value) {
            return Int(scalar.value - 96)
        }
        return nil
    }

    static func nextOrderedMarker(after marker: String) -> String {
        let normalized = marker.trimmingCharacters(in: .whitespaces)
        let bare = normalized.hasSuffix(".") ? String(normalized.dropLast()) : normalized
        if let number = Int(bare) {
            return "\(number + 1)."
        }
        if let romanValue = MarkdownStylist.romanToInt(bare.lowercased()) {
            return MarkdownStylist.intToRoman(romanValue + 1) + "."
        }
        if bare.count == 1, let scalar = bare.unicodeScalars.first {
            let value = scalar.value
            if (65...90).contains(value), let next = UnicodeScalar(min(value + 1, 90)) {
                return String(next).lowercased() + "."
            }
            if (97...122).contains(value), let next = UnicodeScalar(min(value + 1, 122)) {
                return String(next) + "."
            }
        }
        return marker
    }

    static func listPrefixMatch(in line: String) -> MarkdownListPrefixMatch? {
        let indentation = rawIndentation(in: line)
        let trimmed = String(line.dropFirst(indentation.count))

        let simplePrefixes: [(String, MarkdownListPrefixKind, String)] = [
            ("• ", .bullet, "• "),
            ("* ", .bullet, "* "),
            ("- ", .bullet, "- "),
            ("– ", .dash, "– "),
            ("+ ", .plus, "+ "),
            ("○ ", .todo, "○ "),
            ("✓ ", .done, "✓ "),
            ("● ", .done, "● ")
        ]
        for (prefix, kind, marker) in simplePrefixes where trimmed.hasPrefix(prefix) {
            return MarkdownListPrefixMatch(kind: kind, indentation: indentation, marker: marker, prefix: indentation + prefix)
        }

        guard let regex = try? NSRegularExpression(pattern: #"^((?:\d+|[A-Za-z]+|[ivxlcdmIVXLCDM]+)\.)\s"#),
              let match = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: (trimmed as NSString).length)) else {
            return nil
        }

        let markerRange = match.range(at: 1)
        let marker = (trimmed as NSString).substring(with: markerRange)
        let prefix = indentation + (trimmed as NSString).substring(with: NSRange(location: 0, length: match.range.length))
        return MarkdownListPrefixMatch(kind: .ordered, indentation: indentation, marker: marker, prefix: prefix)
    }

    static func remapOrderedMarkerIfNeeded(in line: String, originalMatch: MarkdownListPrefixMatch) -> String {
        guard originalMatch.kind == .ordered,
              let updatedMatch = listPrefixMatch(in: line) else { return line }

        let updatedLevel = orderedLevel(forIndentation: updatedMatch.indentation)
        let targetIndex = orderedIndex(for: updatedMatch.marker) ?? 1
        let targetMarker = MarkdownStylist.orderedMarker(for: updatedLevel, index: targetIndex)
        guard updatedMatch.marker != targetMarker else { return line }

        let indentationCount = updatedMatch.indentation.count
        let markerStart = line.index(line.startIndex, offsetBy: indentationCount)
        let markerEnd = line.index(markerStart, offsetBy: updatedMatch.marker.count)
        return String(line[..<markerStart]) + targetMarker + String(line[markerEnd...])
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

    private static func normalizedMarkdownListLine(_ line: String) -> String? {
        let indentation = rawIndentation(in: line)
        let trimmed = String(line.dropFirst(indentation.count))
        guard !isMarkdownDividerLine(trimmed) else { return nil }
        if trimmed.hasPrefix("● ") {
            return indentation + "✓ " + String(trimmed.dropFirst(2))
        }

        guard let regex = try? NSRegularExpression(pattern: #"^([*+-])\s+(?:\[([ xX])\]\s+)?"#),
              let match = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: (trimmed as NSString).length)) else {
            return nil
        }

        let prefix = (trimmed as NSString).substring(with: match.range)
        let rest = String(trimmed.dropFirst(prefix.count))
        let checkboxRange = match.range(at: 2)
        if checkboxRange.location != NSNotFound {
            let state = (trimmed as NSString).substring(with: checkboxRange)
            return indentation + (state.lowercased() == "x" ? "✓ " : "○ ") + rest
        }

        return indentation + "• " + rest
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

enum MarkdownHiddenRangeSupport {
    static func hiddenRange(containing location: Int, in storage: NSTextStorage?) -> NSRange? {
        guard let storage, storage.length > 0 else { return nil }
        let clamped = max(0, min(location, storage.length - 1))
        var effectiveRange = NSRange(location: NSNotFound, length: 0)
        let isHidden = (storage.attribute(.cadenceMarkdownHidden, at: clamped, effectiveRange: &effectiveRange) as? Bool) == true
        guard isHidden,
              effectiveRange.location != NSNotFound,
              effectiveRange.length > 0 else { return nil }
        return effectiveRange
    }

    static func snappedCaretLocation(_ location: Int, in storage: NSTextStorage?, preferringForward: Bool = true) -> Int {
        guard let storage else { return location }
        let length = storage.length
        guard length > 0 else { return 0 }

        if location < length, let hidden = hiddenRange(containing: location, in: storage) {
            return preferringForward ? NSMaxRange(hidden) : hidden.location
        }
        if location > 0, let hidden = hiddenRange(containing: location - 1, in: storage), location < NSMaxRange(hidden) {
            return preferringForward ? NSMaxRange(hidden) : hidden.location
        }
        return min(location, length)
    }

    static func nextVisibleCaretLocation(from location: Int, movingForward: Bool, in storage: NSTextStorage?) -> Int {
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

enum MarkdownStylist {
    static let bgColor        = NSColor(hex: "#0f1117")
    static let textColor      = NSColor(hex: "#e2e8f0")
    static let dimColor       = NSColor(hex: "#6b7a99")
    static let codeBackground = NSColor(hex: "#1f2235")
    static let codeBorder     = NSColor(hex: "#39405f")
    static let blueColor      = NSColor(hex: "#4a9eff")
    static let greenColor     = NSColor(hex: "#4ecb71")
    static let highlightFillColor = NSColor(hex: "#f6c343")
    static let highlightBorderColor = NSColor(hex: "#ffd66b")

    static let baseFont   = NSFont.systemFont(ofSize: 14)
    static let monoFont   = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    static let baseAttributes: [NSAttributedString.Key: Any] = [
        .font: baseFont,
        .foregroundColor: textColor
    ]

    static func apply(to textView: NSTextView) {
        let cadenceTextView = textView as? CadenceTextView
        let imageAssets = cadenceTextView?.markdownImageAssets ?? [:]
        let taskEmbeds = cadenceTextView?.markdownTaskEmbeds ?? [:]
        cadenceTextView?.markdownTaskEmbedRects.removeAll()
        apply(to: textView, imageAssets: imageAssets, taskEmbeds: taskEmbeds)
    }

    static func apply(
        to textView: NSTextView,
        imageAssets: [UUID: MarkdownImageRenderAsset],
        taskEmbeds: [UUID: MarkdownTaskEmbedRenderInfo] = [:]
    ) {
        guard let storage = textView.textStorage else { return }
        let text = textView.string
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: storage.length)
        let tableStyles = MarkdownTableParser.rowStyles(in: text)

        storage.beginEditing()

        storage.setAttributes([
            .font: baseFont,
            .foregroundColor: textColor,
            .paragraphStyle: baseParagraphStyle
        ], range: fullRange)

        var pos = 0
        for (lineIndex, line) in text.components(separatedBy: "\n").enumerated() {
            let len = (line as NSString).length
            applyLine(
                storage: storage,
                line: line,
                lineRange: NSRange(location: pos, length: len),
                lineStart: pos,
                tableRowStyle: tableStyles[lineIndex],
                imageAssets: imageAssets,
                taskEmbeds: taskEmbeds,
                textView: textView
            )
            pos += len + 1
        }

        applyInline(storage: storage, text: nsText,
                    pattern: "\\*\\*\\*(.+?)\\*\\*\\*", markerLen: 3,
                    contentStyle: { range, s in
                        let existing = s.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? baseFont
                        let italic = NSFontManager.shared.convert(existing, toHaveTrait: .italicFontMask)
                        s.addAttribute(.font, value: NSFontManager.shared.convert(italic, toHaveTrait: .boldFontMask), range: range)
                    })
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
        applyInline(storage: storage, text: nsText,
                    pattern: "==(.+?)==", markerLen: 2,
                    contentStyle: { range, s in
                        s.addAttributes([
                            .cadenceMarkdownHighlight: true,
                            .foregroundColor: NSColor(hex: "#fff4c2")
                        ], range: range)
                    })
        applyLinks(storage, text: nsText)
        applyWikiLinks(storage, text: nsText)
        applyCodeFences(storage, text: nsText)

        storage.endEditing()
    }

    private static func applyLine(
        storage: NSTextStorage,
        line: String,
        lineRange: NSRange,
        lineStart: Int,
        tableRowStyle: MarkdownTableRowStyle?,
        imageAssets: [UUID: MarkdownImageRenderAsset],
        taskEmbeds: [UUID: MarkdownTaskEmbedRenderInfo],
        textView: NSTextView
    ) {
        if let embed = standaloneTaskEmbed(in: line, taskEmbeds: taskEmbeds) {
            applyTaskEmbedBlock(storage: storage, lineRange: lineRange, embed: embed)
            return
        }

        if let image = standaloneImage(in: line, imageAssets: imageAssets) {
            applyImageBlock(storage: storage, lineRange: lineRange, image: image, textView: textView)
            return
        }

        if let tableRowStyle {
            applyTableRow(storage: storage, line: line, lineRange: lineRange, lineStart: lineStart, style: tableRowStyle)
        } else if line.hasPrefix("###### ") {
            heading(storage, lineRange, lineStart, prefixLen: 7, size: 15)
        } else if line.hasPrefix("##### ") {
            heading(storage, lineRange, lineStart, prefixLen: 6, size: 17)
        } else if line.hasPrefix("#### ") {
            heading(storage, lineRange, lineStart, prefixLen: 5, size: 19)
        } else if line.hasPrefix("### ") {
            heading(storage, lineRange, lineStart, prefixLen: 4, size: 22)
        } else if line.hasPrefix("## ") {
            heading(storage, lineRange, lineStart, prefixLen: 3, size: 26)
        } else if line.hasPrefix("# ") {
            heading(storage, lineRange, lineStart, prefixLen: 2, size: 30)
        } else if let quote = blockquoteMatch(in: line) {
            let paragraph = NSMutableParagraphStyle()
            let levelInset = CGFloat(max(quote.depth - 1, 0)) * 12
            paragraph.lineSpacing = 4
            paragraph.firstLineHeadIndent = 18 + levelInset
            paragraph.headIndent = 18 + levelInset
            paragraph.paragraphSpacingBefore = 4
            paragraph.paragraphSpacing = 4

            storage.addAttribute(.paragraphStyle, value: paragraph, range: lineRange)
            storage.addAttribute(.cadenceMarkdownQuoteDepth, value: quote.depth, range: lineRange)
            hide(storage, NSRange(location: lineStart + quote.indentation.count, length: quote.prefix.count - quote.indentation.count))

            let restStart = lineStart + quote.prefix.count
            let rest = NSRange(location: restStart, length: max(0, lineRange.length - quote.prefix.count))
            if rest.length > 0 {
                storage.addAttribute(.foregroundColor, value: NSColor(hex: "#c4d4e8"), range: rest)
                let existing = storage.attribute(.font, at: rest.location, effectiveRange: nil) as? NSFont ?? baseFont
                let italic = NSFontManager.shared.convert(existing, toHaveTrait: .italicFontMask)
                storage.addAttribute(.font, value: italic, range: rest)
            }
        } else if let ordered = orderedListMatch(in: line) {
            let level = MarkdownListSupport.visualLevel(forIndentation: ordered.indentation)
            let ps = listStyle(for: level, markerWidth: ordered.marker.count + 1)
            storage.addAttribute(.paragraphStyle, value: ps, range: lineRange)
            let markerRange = NSRange(location: lineStart + ordered.indentation.count, length: min(ordered.marker.count, lineRange.length))
            storage.addAttribute(.foregroundColor, value: textColor, range: markerRange)
            storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 13, weight: .semibold), range: markerRange)
            addListMarkerSpacing(storage, markerRange: markerRange)
        } else if let bullet = unorderedListMatch(in: line) {
            let level = MarkdownListSupport.visualLevel(forIndentation: bullet.indentation)
            let ps = listStyle(for: level, markerWidth: 2)
            storage.addAttribute(.paragraphStyle, value: ps, range: lineRange)
            let markerLocation = lineStart + bullet.indentation.count
            switch bullet.marker {
            case "•", "*":
                let bulletRange = NSRange(location: markerLocation, length: min(1, lineRange.length))
                storage.addAttribute(.foregroundColor, value: textColor, range: bulletRange)
                storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 20), range: bulletRange)
                addListMarkerSpacing(storage, markerRange: bulletRange)
            case "–", "-", "+":
                let markerRange = NSRange(location: markerLocation, length: min(1, max(0, lineRange.length - bullet.indentation.count)))
                storage.addAttribute(.foregroundColor, value: textColor, range: markerRange)
                addListMarkerSpacing(storage, markerRange: markerRange)
            case "○", "●", "✓":
                let checked = bullet.marker == "●" || bullet.marker == "✓"
                let markerRange = NSRange(location: markerLocation, length: min(1, lineRange.length))
                storage.addAttribute(.foregroundColor, value: checked ? greenColor : dimColor, range: markerRange)
                storage.addAttribute(.font, value: NSFont.systemFont(ofSize: checked ? 16 : 18, weight: checked ? .bold : .regular), range: markerRange)
                addListMarkerSpacing(storage, markerRange: markerRange)
                if checked && lineRange.length > bullet.indentation.count + 2 {
                    let textRange = NSRange(location: markerLocation + 2, length: lineRange.length - bullet.indentation.count - 2)
                    storage.addAttribute(.foregroundColor, value: dimColor, range: textRange)
                    storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: textRange)
                }
            default:
                break
            }
        } else if isDividerLine(line) {
            let ps = NSMutableParagraphStyle()
            ps.alignment = .center
            ps.paragraphSpacingBefore = 8
            ps.paragraphSpacing = 8
            storage.addAttribute(.paragraphStyle, value: ps, range: lineRange)
            storage.addAttribute(.cadenceMarkdownDivider, value: true, range: lineRange)
            storage.addAttribute(.foregroundColor, value: NSColor.clear, range: lineRange)
        }
    }

    private static func applyTableRow(
        storage: NSTextStorage,
        line: String,
        lineRange: NSRange,
        lineStart: Int,
        style: MarkdownTableRowStyle
    ) {
        guard lineRange.length > 0 else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.firstLineHeadIndent = 14
        paragraph.headIndent = 14
        paragraph.lineSpacing = 2
        paragraph.paragraphSpacingBefore = style.isHeader ? 8 : 0
        paragraph.paragraphSpacing = style.isDelimiter ? 2 : 0

        storage.addAttributes([
            .paragraphStyle: paragraph,
            .cadenceMarkdownTableRow: style,
            .font: style.isHeader ? NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold) : monoFont,
            .foregroundColor: style.isDelimiter ? dimColor : textColor
        ], range: lineRange)

        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)
        guard let regex = try? NSRegularExpression(pattern: #"\|"#) else { return }
        regex.enumerateMatches(in: line, range: fullRange) { match, _, _ in
            guard let match else { return }
            storage.addAttribute(.foregroundColor, value: blueColor.withAlphaComponent(0.72), range: NSRange(location: lineStart + match.range.location, length: match.range.length))
        }
    }

    private static func standaloneImage(
        in line: String,
        imageAssets: [UUID: MarkdownImageRenderAsset]
    ) -> MarkdownImageLayoutInfo? {
        guard let regex = try? NSRegularExpression(pattern: #"^!\[([^\]\n]*)\]\(cadence-image://([0-9A-Fa-f-]{36})\)\s*$"#) else {
            return nil
        }
        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)
        guard let match = regex.firstMatch(in: line, range: fullRange),
              let id = UUID(uuidString: nsLine.substring(with: match.range(at: 2)))
        else { return nil }

        let asset = imageAssets[id]
        return MarkdownImageLayoutInfo(
            id: id,
            altText: nsLine.substring(with: match.range(at: 1)),
            image: asset?.image,
            displayWidth: asset?.displayWidth ?? MarkdownImageAssetService.defaultDisplayWidth,
            pixelSize: asset?.pixelSize ?? CGSize(width: 640, height: 360)
        )
    }

    private static func standaloneTaskEmbed(
        in line: String,
        taskEmbeds: [UUID: MarkdownTaskEmbedRenderInfo]
    ) -> MarkdownTaskEmbedLayoutInfo? {
        guard let reference = MarkdownTaskEmbedParser.standaloneTaskReference(in: line) else {
            return nil
        }
        let task = taskEmbeds[reference.id] ?? MarkdownTaskEmbedRenderInfo.missing(reference: reference)
        return MarkdownTaskEmbedLayoutInfo(task: task)
    }

    private static func applyTaskEmbedBlock(
        storage: NSTextStorage,
        lineRange: NSRange,
        embed: MarkdownTaskEmbedLayoutInfo
    ) {
        guard lineRange.length > 0 else { return }

        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = embed.task.paragraphLineHeight
        paragraph.maximumLineHeight = embed.task.paragraphLineHeight
        paragraph.lineBreakMode = .byClipping
        paragraph.paragraphSpacingBefore = 4
        paragraph.paragraphSpacing = 4

        storage.addAttribute(.paragraphStyle, value: paragraph, range: lineRange)
        storage.addAttribute(.cadenceMarkdownTaskEmbed, value: embed, range: lineRange)
        hide(storage, lineRange)
    }

    private static func applyImageBlock(
        storage: NSTextStorage,
        lineRange: NSRange,
        image: MarkdownImageLayoutInfo,
        textView: NSTextView
    ) {
        guard lineRange.length > 0 else { return }
        let contentWidth = max(1, textView.bounds.width - (textView.textContainerInset.width * 2) - 24)
        let imageSize = image.fittedSize(maxWidth: contentWidth)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = imageSize.height + 18
        paragraph.maximumLineHeight = imageSize.height + 18
        paragraph.lineBreakMode = .byClipping
        paragraph.paragraphSpacingBefore = 8
        paragraph.paragraphSpacing = 2

        storage.addAttribute(.paragraphStyle, value: paragraph, range: lineRange)
        storage.addAttribute(.cadenceMarkdownHidden, value: true, range: lineRange)
        storage.addAttribute(.cadenceMarkdownImage, value: image, range: lineRange)
    }

    private static func unorderedListMatch(in line: String) -> (indentation: String, marker: String)? {
        let indentation = String(line.prefix { $0 == " " || $0 == "\t" })
        let trimmed = String(line.dropFirst(indentation.count))
        let markers = ["• ", "* ", "- ", "– ", "+ ", "○ ", "✓ ", "● "]
        guard let prefix = markers.first(where: { trimmed.hasPrefix($0) }) else { return nil }
        return (indentation, String(prefix.prefix(1)))
    }

    private static func blockquoteMatch(in line: String) -> (indentation: String, prefix: String, depth: Int)? {
        guard let regex = try? NSRegularExpression(pattern: #"^([ \t]*)(>\s*)+"#),
              let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) else {
            return nil
        }

        let prefixRange = match.range(at: 0)
        let indentationRange = match.range(at: 1)
        let nsLine = line as NSString
        let indentation = indentationRange.location != NSNotFound ? nsLine.substring(with: indentationRange) : ""
        let prefix = nsLine.substring(with: prefixRange)
        let depth = prefix.filter { $0 == ">" }.count
        return depth > 0 ? (indentation, prefix, depth) : nil
    }

    private static func isDividerLine(_ line: String) -> Bool {
        let trimmed = line
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { !$0.isWhitespace }
        guard trimmed.count >= 3 else { return false }
        return trimmed.allSatisfy { $0 == "-" } ||
            trimmed.allSatisfy { $0 == "*" } ||
            trimmed.allSatisfy { $0 == "_" }
    }

    private static func orderedListMatch(in line: String) -> (indentation: String, marker: String)? {
        let indentation = String(line.prefix { $0 == " " || $0 == "\t" })
        let trimmed = String(line.dropFirst(indentation.count))
        guard let regex = try? NSRegularExpression(pattern: #"^((?:\d+|[A-Za-z]+|[ivxlcdmIVXLCDM]+)\.)\s"#),
              let match = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: (trimmed as NSString).length)) else {
            return nil
        }
        let marker = (trimmed as NSString).substring(with: match.range(at: 1))
        return (indentation, marker)
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

    private static func heading(_ storage: NSTextStorage, _ lineRange: NSRange, _ lineStart: Int, prefixLen: Int, size: CGFloat) {
        let markerRange = NSRange(location: lineStart, length: min(prefixLen, lineRange.length))
        let contentLength = max(0, lineRange.length - prefixLen)
        let contentRange = NSRange(location: lineStart + prefixLen, length: contentLength)
        let content = contentLength > 0 ? (storage.string as NSString).substring(with: contentRange) : ""
        let hasVisibleContent = !content.trimmingCharacters(in: .whitespaces).isEmpty

        guard hasVisibleContent else {
            storage.addAttribute(.font, value: baseFont, range: lineRange)
            storage.addAttribute(.foregroundColor, value: dimColor, range: markerRange)
            storage.addAttribute(.paragraphStyle, value: baseParagraphStyle, range: lineRange)
            return
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.firstLineHeadIndent = 0
        paragraph.headIndent = 0
        paragraph.paragraphSpacingBefore = 4
        paragraph.paragraphSpacing = 4

        storage.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: size), range: lineRange)
        storage.addAttribute(.foregroundColor, value: textColor, range: lineRange)
        storage.addAttribute(.paragraphStyle, value: paragraph, range: lineRange)
        hide(storage, markerRange)
    }

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
            let full = m.range
            let open = NSRange(location: full.location, length: markerLen)
            let close = NSRange(location: full.location + full.length - markerLen, length: markerLen)
            let content = NSRange(location: full.location + markerLen, length: full.length - markerLen * 2)
            contentStyle(content, storage)
            hide(storage, open)
            hide(storage, close)
        }
    }

    private static func applyCode(_ storage: NSTextStorage, text: NSString) {
        guard let regex = try? NSRegularExpression(pattern: "`([^`\n]+)`") else { return }
        regex.enumerateMatches(in: text as String, range: NSRange(location: 0, length: text.length)) { match, _, _ in
            guard let m = match, m.range.length >= 3 else { return }
            let full = m.range
            let open = NSRange(location: full.location, length: 1)
            let close = NSRange(location: full.location + full.length - 1, length: 1)
            let content = NSRange(location: full.location + 1, length: full.length - 2)
            storage.addAttribute(.font, value: monoFont, range: content)
            storage.addAttribute(.foregroundColor, value: greenColor, range: content)
            storage.addAttribute(.cadenceMarkdownInlineCode, value: true, range: content)
            hide(storage, open)
            hide(storage, close)
        }
    }

    private static func applyLinks(_ storage: NSTextStorage, text: NSString) {
        guard let regex = try? NSRegularExpression(pattern: #"(?<!\!)\[(.+?)\]\((.+?)\)"#) else { return }
        regex.enumerateMatches(in: text as String, range: NSRange(location: 0, length: text.length)) { match, _, _ in
            guard let match, match.numberOfRanges >= 3 else { return }

            let labelRange = match.range(at: 1)
            let urlRange = match.range(at: 2)
            let fullRange = match.range(at: 0)
            guard labelRange.location != NSNotFound, urlRange.location != NSNotFound else { return }

            storage.addAttribute(.foregroundColor, value: blueColor, range: labelRange)
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: labelRange)
            storage.addAttribute(.foregroundColor, value: dimColor, range: urlRange)
            storage.addAttribute(.font, value: monoFont, range: urlRange)

            let hiddenRanges = [
                NSRange(location: fullRange.location, length: 1),
                NSRange(location: labelRange.location + labelRange.length, length: 2),
                NSRange(location: urlRange.location + urlRange.length, length: 1)
            ]
            hiddenRanges.forEach { hide(storage, $0) }
        }
    }

    private static func applyWikiLinks(_ storage: NSTextStorage, text: NSString) {
        guard let regex = try? NSRegularExpression(pattern: #"\[\[([^\[\]]+?)\]\]"#) else { return }
        regex.enumerateMatches(in: text as String, range: NSRange(location: 0, length: text.length)) { match, _, _ in
            guard let match, match.numberOfRanges >= 2 else { return }
            let fullRange = match.range(at: 0)
            let labelRange = match.range(at: 1)
            guard labelRange.location != NSNotFound else { return }
            if storage.attribute(.cadenceMarkdownTaskEmbed, at: fullRange.location, effectiveRange: nil) is MarkdownTaskEmbedLayoutInfo {
                return
            }

            let label = text.substring(with: labelRange).trimmingCharacters(in: .whitespacesAndNewlines)
            let kind = wikiLinkKind(for: label)
            let displayRange = wikiLinkDisplayRange(label: text.substring(with: labelRange), labelRange: labelRange)

            storage.addAttribute(.foregroundColor, value: kind == .task ? greenColor : blueColor, range: displayRange)
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: displayRange)
            storage.addAttribute(.cadenceMarkdownReference, value: wikiLinkTarget(for: label), range: displayRange)
            if kind == .task {
                storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 13, weight: .semibold), range: displayRange)
            }

            hide(storage, NSRange(location: fullRange.location, length: 2))
            hide(storage, NSRange(location: fullRange.location + fullRange.length - 2, length: 2))
            if displayRange.location > labelRange.location {
                hide(storage, NSRange(location: labelRange.location, length: displayRange.location - labelRange.location))
            }
        }
    }

    private enum WikiLinkKind {
        case note
        case task
    }

    private static func wikiLinkKind(for label: String) -> WikiLinkKind {
        label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("task:") ? .task : .note
    }

    private static func wikiLinkDisplayRange(label: String, labelRange: NSRange) -> NSRange {
        let nsLabel = label as NSString
        let fullRange = NSRange(location: 0, length: nsLabel.length)
        guard let regex = try? NSRegularExpression(pattern: #"^\s*(?:task|note):(?:[^\|\]]*\|)?"#, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: label, range: fullRange) else {
            return labelRange
        }

        let displayLocation = labelRange.location + match.range.length
        let displayLength = max(0, labelRange.length - match.range.length)
        guard displayLength > 0 else { return labelRange }
        return NSRange(location: displayLocation, length: displayLength)
    }

    private static func wikiLinkTarget(for label: String) -> MarkdownReferenceTarget {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()
        if lowercased.hasPrefix("task:") {
            let payload = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = payload.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2 {
                let idText = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
                let title = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                return MarkdownReferenceTarget(kind: .task, id: UUID(uuidString: idText), title: title)
            }
            return MarkdownReferenceTarget(kind: .task, id: UUID(uuidString: payload), title: payload)
        }

        if lowercased.hasPrefix("note:") {
            let payload = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = payload.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2 {
                let idText = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
                let title = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                return MarkdownReferenceTarget(kind: .note, id: UUID(uuidString: idText), title: title)
            }
            return MarkdownReferenceTarget(kind: .note, id: UUID(uuidString: payload), title: payload)
        }

        return MarkdownReferenceTarget(kind: .note, id: UUID(uuidString: trimmed), title: trimmed)
    }

    private static func applyCodeFences(_ storage: NSTextStorage, text: NSString) {
        guard let regex = try? NSRegularExpression(pattern: #"(?s)```([^\n`]*)\n(.*?)\n?```"#) else { return }
        regex.enumerateMatches(in: text as String, range: NSRange(location: 0, length: text.length)) { match, _, _ in
            guard let match, match.numberOfRanges >= 3 else { return }

            let fullRange = match.range(at: 0)
            let languageRange = match.range(at: 1)
            let codeRange = match.range(at: 2)

            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 4
            paragraph.firstLineHeadIndent = 14
            paragraph.headIndent = 14
            paragraph.paragraphSpacingBefore = 6
            paragraph.paragraphSpacing = 6

            storage.addAttributes([
                .font: monoFont,
                .foregroundColor: greenColor,
                .paragraphStyle: paragraph,
                .cadenceMarkdownCodeBlock: true
            ], range: codeRange)

            if languageRange.location != NSNotFound, languageRange.length > 0 {
                storage.addAttribute(.foregroundColor, value: dimColor, range: languageRange)
                storage.addAttribute(.font, value: monoFont, range: languageRange)
            }

            let snippet = text.substring(with: fullRange)
            guard let firstFenceRange = snippet.range(of: "```"),
                  let lastFenceRange = snippet.range(of: "```", options: .backwards) else { return }

            let firstFenceLocation = fullRange.location + snippet.distance(from: snippet.startIndex, to: firstFenceRange.lowerBound)
            let lastFenceLocation = fullRange.location + snippet.distance(from: snippet.startIndex, to: lastFenceRange.lowerBound)
            hide(storage, NSRange(location: firstFenceLocation, length: 3))
            hide(storage, NSRange(location: lastFenceLocation, length: 3))
        }
    }

    private static func hide(_ storage: NSTextStorage, _ range: NSRange) {
        guard range.length > 0 else { return }
        storage.addAttribute(.cadenceMarkdownHidden, value: true, range: range)
        storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 0.1), range: range)
        storage.addAttribute(.foregroundColor, value: NSColor.clear, range: range)
        storage.removeAttribute(.kern, range: range)
    }

    static let baseParagraphStyle: NSParagraphStyle = {
        let ps = NSMutableParagraphStyle()
        ps.lineSpacing = 4
        return ps
    }()

    private static func listStyle(for level: Int, markerWidth: Int) -> NSParagraphStyle {
        let unit: CGFloat = 12
        let markerInset: CGFloat = 8
        let contentGap: CGFloat = 8
        let base = CGFloat(level) * unit
        let ps = NSMutableParagraphStyle()
        ps.firstLineHeadIndent = base + markerInset
        ps.headIndent = base + markerInset + CGFloat(Double(markerWidth) * 5.5) + contentGap
        ps.lineSpacing = 4
        return ps
    }

    private static func addListMarkerSpacing(_ storage: NSTextStorage, markerRange: NSRange) {
        guard markerRange.length > 0 else { return }
        storage.addAttribute(.kern, value: 4.0, range: markerRange)
    }
}

extension NSColor {
    convenience init(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h = String(h.dropFirst()) }
        var rgb: UInt64 = 0
        Scanner(string: h).scanHexInt64(&rgb)
        let r = CGFloat((rgb >> 16) & 0xFF) / 255
        let g = CGFloat((rgb >> 8) & 0xFF) / 255
        let b = CGFloat(rgb & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}
#endif
