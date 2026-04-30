import Foundation

struct NoteTaskReference: Hashable {
    let rawValue: String
    let taskID: UUID?
    let title: String

    var fallbackTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum NoteReferenceParser {
    static func noteLinks(in content: String) -> [String] {
        matches(in: content, pattern: #"\[\[([^\[\]]+?)\]\]"#)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !isTaskReferencePayload($0) }
    }

    static func taskReferences(in content: String) -> [NoteTaskReference] {
        matches(in: content, pattern: #"\[\[task:(.+?)\]\]"#)
            .map(parseTaskReference)
            .filter { !$0.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    static func taskReferenceMarkdown(for task: AppTask) -> String {
        let title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = title.isEmpty ? "Untitled Task" : title
        return "[[task:\(task.id.uuidString)|\(displayTitle)]]"
    }

    static func taskReferenceMarkdown(title: String) -> String {
        "[[task:\(title.trimmingCharacters(in: .whitespacesAndNewlines))]]"
    }

    private static func parseTaskReference(_ raw: String) -> NoteTaskReference {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        if parts.count == 2 {
            let idText = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            let title = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            return NoteTaskReference(rawValue: trimmed, taskID: UUID(uuidString: idText), title: title)
        }
        return NoteTaskReference(rawValue: trimmed, taskID: UUID(uuidString: trimmed), title: trimmed)
    }

    private static func isTaskReferencePayload(_ payload: String) -> Bool {
        payload.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasPrefix("task:")
    }

    private static func matches(in content: String, pattern: String) -> [String] {
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
        let titles = NoteReferenceParser.noteLinks(in: note.content)
        return titles.compactMap { title in
            notes.first {
                $0.id != note.id &&
                    $0.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        .caseInsensitiveCompare(title) == .orderedSame
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
        let currentTitle = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentTitle.isEmpty else { return [] }
        return notes.filter { other in
            other.id != note.id &&
                NoteReferenceParser.noteLinks(in: other.content).contains {
                    $0.caseInsensitiveCompare(currentTitle) == .orderedSame
                }
        }
    }
}
