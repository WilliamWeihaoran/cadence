import Foundation

struct NoteLinkReference: Hashable {
    let rawValue: String
    let noteID: UUID?
    let title: String

    nonisolated var fallbackTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct NoteTaskReference: Hashable {
    let rawValue: String
    let taskID: UUID?
    let title: String

    nonisolated var fallbackTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum NoteReferenceParser {
    nonisolated static func noteLinks(in content: String) -> [String] {
        noteReferences(in: content).map(\.fallbackTitle)
    }

    nonisolated static func noteReferences(in content: String) -> [NoteLinkReference] {
        matches(in: content, pattern: #"\[\[([^\[\]]+?)\]\]"#)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !isTaskReferencePayload($0) }
            .map(parseNoteReference)
            .filter { !$0.fallbackTitle.isEmpty }
    }

    nonisolated static func taskReferences(in content: String) -> [NoteTaskReference] {
        matches(in: content, pattern: #"\[\[task:(.+?)\]\]"#)
            .map(parseTaskReference)
            .filter { !$0.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    static func taskReferenceMarkdown(for task: AppTask) -> String {
        let displayTitle = sanitizedReferenceTitle(task.title, fallback: "Untitled Task")
        return "[[task:\(task.id.uuidString)|\(displayTitle)]]"
    }

    nonisolated static func taskReferenceMarkdown(title: String) -> String {
        "[[task:\(title.trimmingCharacters(in: .whitespacesAndNewlines))]]"
    }

    static func noteReferenceMarkdown(for note: Note) -> String {
        "[[note:\(note.id.uuidString)|\(sanitizedReferenceTitle(note.displayTitle, fallback: "Untitled"))]]"
    }

    nonisolated static func noteReferenceMarkdown(title: String) -> String {
        "[[\(title.trimmingCharacters(in: .whitespacesAndNewlines))]]"
    }

    nonisolated private static func parseNoteReference(_ raw: String) -> NoteLinkReference {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload: String
        if trimmed.lowercased().hasPrefix("note:") {
            payload = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            return NoteLinkReference(rawValue: trimmed, noteID: UUID(uuidString: trimmed), title: trimmed)
        }

        let parts = payload.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        if parts.count == 2 {
            let idText = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            let title = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            return NoteLinkReference(rawValue: trimmed, noteID: UUID(uuidString: idText), title: title)
        }
        return NoteLinkReference(rawValue: trimmed, noteID: UUID(uuidString: payload), title: payload)
    }

    nonisolated private static func parseTaskReference(_ raw: String) -> NoteTaskReference {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        if parts.count == 2 {
            let idText = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            let title = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            return NoteTaskReference(rawValue: trimmed, taskID: UUID(uuidString: idText), title: title)
        }
        return NoteTaskReference(rawValue: trimmed, taskID: UUID(uuidString: trimmed), title: trimmed)
    }

    nonisolated private static func isTaskReferencePayload(_ payload: String) -> Bool {
        payload.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasPrefix("task:")
    }

    nonisolated private static func sanitizedReferenceTitle(_ title: String, fallback: String) -> String {
        let sanitized = title
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "|", with: "-")
            .replacingOccurrences(of: "[", with: "(")
            .replacingOccurrences(of: "]", with: ")")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? fallback : sanitized
    }

    nonisolated private static func matches(in content: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = content as NSString
        let range = NSRange(location: 0, length: ns.length)
        return regex.matches(in: content, range: range).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            return ns.substring(with: match.range(at: 1))
        }
    }
}

enum NoteReferenceResolver {
    static func linkedNotes(for note: Note, in notes: [Note]) -> [Note] {
        let references = NoteReferenceParser.noteReferences(in: note.content)
        return references.compactMap { reference in
            if let noteID = reference.noteID,
               noteID != note.id,
               let exact = notes.first(where: { $0.id == noteID }) {
                return exact
            }
            let title = reference.fallbackTitle
            return notes.first {
                $0.id != note.id && noteTitle($0).caseInsensitiveCompare(title) == .orderedSame
            }
        }
    }

    static func linkedTasks(for note: Note, in tasks: [AppTask]) -> [AppTask] {
        let references = NoteReferenceParser.taskReferences(in: note.content)
        return references.compactMap { reference in
            if let taskID = reference.taskID,
               let exact = tasks.first(where: { $0.id == taskID }) {
                return exact
            }
            let title = reference.fallbackTitle
            return tasks.first {
                $0.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare(title) == .orderedSame
            }
        }
    }

    static func backlinks(for note: Note, in notes: [Note]) -> [Note] {
        let currentTitle = noteTitle(note)
        return notes.filter { other in
            guard other.id != note.id else { return false }
            return NoteReferenceParser.noteReferences(in: other.content).contains { reference in
                if reference.noteID == note.id { return true }
                guard !currentTitle.isEmpty else { return false }
                return reference.fallbackTitle.caseInsensitiveCompare(currentTitle) == .orderedSame
            }
        }
    }

    private static func noteTitle(_ note: Note) -> String {
        note.title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
