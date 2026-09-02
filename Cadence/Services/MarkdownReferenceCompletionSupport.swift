import Foundation

nonisolated enum MarkdownReferenceKind: Hashable {
    case note
    case task
}

nonisolated struct MarkdownReferenceCompletionContext {
    let range: NSRange
    let kind: MarkdownReferenceKind
    let query: String
    let cursorLocation: Int
}

nonisolated enum MarkdownReferenceCompletionSupport {
    nonisolated static func context(in text: String, selection: NSRange) -> MarkdownReferenceCompletionContext? {
        guard selection.length == 0 else { return nil }

        let nsText = text as NSString
        let safeCursor = min(max(selection.location, 0), nsText.length)
        let lineRange = nsText.lineRange(for: NSRange(location: max(0, safeCursor - 1), length: 0))
        guard safeCursor >= lineRange.location else { return nil }

        let prefixRange = NSRange(location: lineRange.location, length: safeCursor - lineRange.location)
        let prefix = nsText.substring(with: prefixRange)
        let nsPrefix = prefix as NSString
        let openRange = nsPrefix.range(of: "[[", options: .backwards)
        guard openRange.location != NSNotFound else { return nil }

        let tokenStart = NSMaxRange(openRange)
        let token = nsPrefix.substring(with: NSRange(location: tokenStart, length: max(0, nsPrefix.length - tokenStart)))
        guard isValidToken(token) else { return nil }

        let lowercased = token.lowercased()
        let kind: MarkdownReferenceKind
        let query: String
        if lowercased.hasPrefix("task:") {
            kind = .task
            query = String(token.dropFirst(5))
        } else if lowercased.hasPrefix("note:") {
            kind = .note
            query = String(token.dropFirst(5))
        } else {
            kind = .note
            query = token
        }

        // The replacement range runs from the `[[` **through any `]]` the caret is sitting in front
        // of**, not merely up to the caret. `/task` and `/link` insert the whole snippet
        // (`[[task:]]`, `[[]]`) and park the caret inside it, so by the time this picker opens the
        // closing brackets already exist; the suggestion it will insert is itself a complete
        // `[[…]]`. Stopping at the caret left the snippet's own `]]` behind as literal text after
        // the rendered reference (T-734, seen on iPhone 17 Pro). Exactly two characters, and only
        // when they are on this line — one `]` is not a close.
        let openLocation = lineRange.location + openRange.location
        var length = safeCursor - openLocation
        let lineEnd = NSMaxRange(lineRange)
        if safeCursor + 2 <= min(lineEnd, nsText.length),
           nsText.substring(with: NSRange(location: safeCursor, length: 2)) == "]]" {
            length += 2
        }

        return MarkdownReferenceCompletionContext(
            range: NSRange(location: openLocation, length: length),
            kind: kind,
            query: query,
            cursorLocation: safeCursor
        )
    }

    // MARK: - Candidates
    //
    // What a `[[` or `[[task:` completion offers, and in what order. This lived twice under
    // `Cadence/iOS/` — byte-identical filter and comparator in `iOSMarkdownEditingSurface`'s
    // inline completion menu and `iOSMarkdownAccessoryViews`' picker sheet — where the macOS test
    // target cannot see it. It belongs beside `context(in:selection:)`: that decides *whether* a
    // completion is being typed, this decides what it may complete to.

    /// Whether one candidate field answers a picker query. The query is trimmed, matching is
    /// case-insensitive, and an empty query matches everything.
    nonisolated static func matches(_ value: String, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return value.localizedCaseInsensitiveContains(trimmed)
    }

    /// The notes a `[[` completion offers: most recently edited first, then title.
    ///
    /// `updatedAt` is a `Date` and `id` is unique, so this pair is already total.
    nonisolated static func candidateNotes(from notes: [Note], query: String) -> [Note] {
        notes
            .filter { matches($0.displayTitle, query: query) || matches($0.content, query: query) }
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
                let titleComparison = lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle)
                if titleComparison != .orderedSame { return titleComparison == .orderedAscending }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    /// The tasks a `[[task:` completion offers: open before done, then priority, then the total
    /// tie-break.
    ///
    /// The inline menu truncates this with `.prefix(6)`, so an incomplete tie-break did not merely
    /// reorder the menu — it changed *which six tasks were offered* between one keystroke and the
    /// next. `order` is per-container and these candidates come from every list, so equal `order`
    /// is the normal case rather than the edge one; `TaskOrdering.fallbackPrecedes` closes it.
    nonisolated static func candidateTasks(from tasks: [AppTask], query: String) -> [AppTask] {
        tasks
            .filter { !$0.isCancelled }
            .filter {
                matches($0.title, query: query)
                    || matches($0.notes, query: query)
                    || matches($0.containerName, query: query)
            }
            .sorted { lhs, rhs in
                if lhs.isDone != rhs.isDone { return !lhs.isDone && rhs.isDone }
                if lhs.priority.rank != rhs.priority.rank {
                    return lhs.priority.rank > rhs.priority.rank
                }
                if lhs.order != rhs.order { return lhs.order < rhs.order }
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                return TaskOrdering.fallbackPrecedes(lhs, rhs)
            }
    }

    nonisolated private static func isValidToken(_ token: String) -> Bool {
        token.count <= 80 &&
            !token.contains("[") &&
            !token.contains("]") &&
            !token.contains("\n")
    }
}
