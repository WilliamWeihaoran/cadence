import Foundation

nonisolated struct NoteLinkReference: Hashable {
    let rawValue: String
    let noteID: UUID?
    let title: String

    nonisolated var fallbackTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

nonisolated struct NoteTaskReference: Hashable {
    let rawValue: String
    let taskID: UUID?
    let title: String

    nonisolated var fallbackTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

nonisolated enum NoteReferenceParser {
    // There is no `noteLinks(in:)`. It was `noteReferences(...).map(\.fallbackTitle)` with no
    // production caller: linked notes and backlinks need the parsed `NoteLinkReference` — the
    // stable `noteID` above all — not a bare title, which is what made the title-only form the
    // wrong thing to hand anyone in the first place.

    nonisolated static func noteReferences(in content: String) -> [NoteLinkReference] {
        matches(in: content, pattern: #"\[\[([^\[\]]+?)\]\]"#)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !isTaskReferencePayload($0) }
            .map(parseNoteReference)
            .filter { !$0.fallbackTitle.isEmpty }
    }

    nonisolated static func taskReferences(in content: String) -> [NoteTaskReference] {
        // Case-insensitive to match the renderer and the link target, both of which lowercase the
        // prefix — otherwise "[[Task:…]]" draws and navigates as a task but never reaches linked
        // tasks or backlinks.
        matches(in: content, pattern: #"(?i)\[\[task:(.+?)\]\]"#)
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

nonisolated enum NoteReferenceResolver {
    static func linkedNotes(for note: Note, in notes: [Note]) -> [Note] {
        linkedNotes(noteID: note.id, content: note.content, in: notes)
    }

    static func linkedNotes(noteID currentNoteID: UUID, content: String, in notes: [Note]) -> [Note] {
        let references = NoteReferenceParser.noteReferences(in: content)
        return references.compactMap { reference in
            if let noteID = reference.noteID,
               noteID != currentNoteID,
               let exact = notes.first(where: { $0.id == noteID }) {
                return exact
            }
            let title = reference.fallbackTitle
            return notes.first {
                $0.id != currentNoteID && noteTitle($0).caseInsensitiveCompare(title) == .orderedSame
            }
        }
    }

    static func linkedTasks(for note: Note, in tasks: [AppTask]) -> [AppTask] {
        linkedTasks(in: note.content, tasks: tasks)
    }

    static func linkedTasks(in content: String, tasks: [AppTask]) -> [AppTask] {
        let references = NoteReferenceParser.taskReferences(in: content)
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
        backlinks(noteID: note.id, title: noteTitle(note), in: notes)
    }

    static func backlinks(noteID: UUID, title: String, in notes: [Note]) -> [Note] {
        let currentTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return notes.filter { other in
            guard other.id != noteID else { return false }
            return NoteReferenceParser.noteReferences(in: other.content).contains { reference in
                if reference.noteID == noteID { return true }
                guard !currentTitle.isEmpty else { return false }
                return reference.fallbackTitle.caseInsensitiveCompare(currentTitle) == .orderedSame
            }
        }
    }

    private static func noteTitle(_ note: Note) -> String {
        note.title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The sections a note's reference panel offers, in the order both platforms draw them.
///
/// The labels and glyphs live here rather than in either view because there are two panels now —
/// macOS's `NoteReferenceStrip` and iOS's `iOSNoteReferencePanel` — and a section that reads
/// "Backlinks" on one and "Linked From" on the other is one note answering one question two ways.
nonisolated enum NoteReferencePanelSection: String, Hashable, CaseIterable, Identifiable {
    /// What this note points at.
    case linkedNotes
    /// The tasks it points at, `[[task:…]]`.
    case taskReferences
    /// What points at this note — the half iOS had no way to see.
    case backlinks

    var id: String { rawValue }

    var label: String {
        switch self {
        case .linkedNotes: return "Linked Notes"
        case .taskReferences: return "Task References"
        case .backlinks: return "Backlinks"
        }
    }

    var systemImage: String {
        switch self {
        case .linkedNotes: return "doc.text"
        case .taskReferences: return "checkmark.circle"
        case .backlinks: return "arrow.uturn.backward.circle"
        }
    }
}

/// What one note points at, and what points back at it.
///
/// Deliberately three arrays of models rather than anything pre-formatted: the panel draws a live
/// task's title and completion state, and a resolved reference that has since been renamed must read
/// as the thing it points at rather than as the text in the markdown.
nonisolated struct NoteReferencePanelContents {
    let linkedNotes: [Note]
    let linkedTasks: [AppTask]
    let backlinks: [Note]

    /// No `static let empty`: `[Note]` is not `Sendable`, so a stored static would not compile in
    /// the MCP server target's Swift 6 mode. Defaulted arguments cost nothing and cannot rot.
    init(linkedNotes: [Note] = [], linkedTasks: [AppTask] = [], backlinks: [Note] = []) {
        self.linkedNotes = linkedNotes
        self.linkedTasks = linkedTasks
        self.backlinks = backlinks
    }

    var isEmpty: Bool {
        linkedNotes.isEmpty && linkedTasks.isEmpty && backlinks.isEmpty
    }

    /// Only the sections with something in them, in the canonical order. An empty section is not
    /// drawn as an empty section — a note with no backlinks says nothing about backlinks.
    var sections: [NoteReferencePanelSection] {
        var result: [NoteReferencePanelSection] = []
        if !linkedNotes.isEmpty { result.append(.linkedNotes) }
        if !linkedTasks.isEmpty { result.append(.taskReferences) }
        if !backlinks.isEmpty { result.append(.backlinks) }
        return result
    }
}

/// The one entry point a reference panel resolves through.
///
/// It is a wrapper over `NoteReferenceResolver` and nothing more, on purpose: the resolution rules —
/// stable id first, case-insensitive title fallback, first match wins, an unresolvable reference
/// simply absent — are already written down and already tested there, and a second surface that
/// re-derived them would be free to disagree. So the panel gets a shape to draw and no decisions of
/// its own.
nonisolated enum NoteReferencePanelSupport {
    static func contents(
        noteID: UUID,
        title: String,
        content: String,
        notes: [Note],
        tasks: [AppTask]
    ) -> NoteReferencePanelContents {
        NoteReferencePanelContents(
            linkedNotes: NoteReferenceResolver.linkedNotes(noteID: noteID, content: content, in: notes),
            linkedTasks: NoteReferenceResolver.linkedTasks(in: content, tasks: tasks),
            backlinks: NoteReferenceResolver.backlinks(noteID: noteID, title: title, in: notes)
        )
    }

    /// `content` is passed separately because an editor's buffer is ahead of `note.content` between
    /// commits, and the panel should describe the text on screen.
    ///
    /// `displayTitle` rather than `title`, matching macOS's call site: a daily note's title is its
    /// date key, and `[[2026-08-21]]` is a link a user can reasonably write.
    static func contents(
        for note: Note,
        content: String,
        notes: [Note],
        tasks: [AppTask]
    ) -> NoteReferencePanelContents {
        contents(
            noteID: note.id,
            title: note.displayTitle,
            content: content,
            notes: notes,
            tasks: tasks
        )
    }

    /// The note kind in the app's current vocabulary, for the one line under a chip's title.
    ///
    /// `.meeting` reads "Event note" because that case's raw value is persisted and only its label
    /// was renamed — `note.kind.rawValue.capitalized` still says "Meeting", which is the retired
    /// name of the tab it lives in.
    static func noteKindLabel(_ kind: NoteKind) -> String {
        switch kind {
        case .daily: return "Daily note"
        case .weekly: return "Weekly note"
        case .permanent: return "Notepad"
        case .list: return "List note"
        case .meeting: return "Event note"
        }
    }

    /// The kind label **plus whatever distinguishes this note from the others of its kind** — the
    /// day, the week, the event's date, or the list it is filed under. For a full-width row that
    /// has room to say it. `noteKindLabel` above is what a compact pill takes.
    ///
    /// **T-239: this switch was spelled three times and the three disagreed.** What each said:
    /// - `noteKindLabel` (here): "Daily note" / "Weekly note" / "Notepad" / "List note" /
    ///   "Event note". Correct vocabulary, no room for the detail.
    /// - `iOSSearchView.noteSubtitle`: the detail form, but `.permanent` read **"Permanent note"**
    ///   where the app's own tab, `Note.displayTitle` and this file all say "Notepad" — and that
    ///   string is one of the fields `CadenceSearchMatcher` scores, so the notepad was not findable
    ///   under the word the app uses for it.
    /// - `iOSMarkdownNoteReferenceRow.subtitle`: `.list` read **"Linked note"**, which names the
    ///   reference panel's *Linked Notes* section rather than the note and drops the container the
    ///   search spelling shows; and `.daily` / `.weekly` returned a **bare** `dateKey` / `weekKey`.
    ///   That is exactly what `Note.displayTitle` returns for those kinds, because
    ///   `NoteMigrationService.dailyNote` creates every one with `title: dateKey` — so every daily
    ///   and weekly row in that picker printed the same string twice, one line under the other.
    ///   That is the live bug of the three.
    ///
    /// One separator for all three dated kinds. The row spelled the event's `·` and the search's
    /// `/`; two separators inside one list of results is a difference that means nothing.
    static func noteKindDetail(_ note: Note) -> String {
        switch note.kind {
        case .daily:
            return datedDetail("Daily", key: note.dateKey, kind: .daily)
        case .weekly:
            return datedDetail("Weekly", key: note.weekKey, kind: .weekly)
        case .permanent:
            return noteKindLabel(.permanent)
        case .list:
            return listContainerName(note) ?? noteKindLabel(.list)
        case .meeting:
            return datedDetail("Event", key: note.eventDateKey, kind: .meeting)
        }
    }

    /// Falls back to the bare label rather than to an empty string, so a dated kind with no date
    /// still says which kind it is.
    private static func datedDetail(_ prefix: String, key: String, kind: NoteKind) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? noteKindLabel(kind) : "\(prefix) / \(trimmed)"
    }

    /// The list a `.list` note is filed under, trimmed and non-empty. `iOSSearchView` spelled this
    /// `compactMap { $0 }.first`, which accepts a whitespace-only list name and renders as a blank
    /// subtitle instead of falling through to "List note".
    private static func listContainerName(_ note: Note) -> String? {
        [note.area?.name, note.project?.name]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    /// What a referenced task's chip says when it has no due date to show. The container it lives in
    /// if it has one, and otherwise where it actually is.
    static func taskFallbackSubtitle(_ task: AppTask) -> String {
        let container = task.containerName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !container.isEmpty { return container }
        return task.isDone ? "Completed" : "Inbox"
    }
}
