import Foundation

/// What a list's **Notes** tab lists besides the list's own notes, and how its search field and tag
/// filter narrow all three sections. Both platforms.
///
/// **[[T-7031]].** macOS's `ListNotesView` derived the "Task Notes" section (open tasks in the list
/// that carry notes), the linked calendar's upcoming event notes, and the search-and-tag predicate
/// inline, as private members of the view. The iPad tab (`iOSListNotesView`) had none of the four,
/// so a list whose notes live on its tasks drew "no notes" on iPad while the Mac listed them. The
/// derivation moved here verbatim so the two tabs cannot list different things for the same list;
/// only the containers (a collapsible sidebar section on macOS, a heading in the scrolling column on
/// iOS) differ.
enum CadenceListRelatedNotes {

    // MARK: - Sources

    /// The calendar whose event notes this list shows. An area's link wins and is not merged with a
    /// project's: a list is one or the other, and the Mac has always read it in this order.
    static func linkedCalendarID(area: Area?, project: Project?) -> String {
        area?.linkedCalendarID ?? project?.linkedCalendarID ?? ""
    }

    /// The list's open tasks — neither done nor cancelled — whose notes hold more than whitespace.
    /// Scoped to the list on purpose: the *editor* is handed every task, so a task embedded from
    /// another list still renders (see `ListNotesView.taskNotes`).
    static func taskNotes(for area: Area?, project: Project?, in tasks: [AppTask]) -> [AppTask] {
        CadenceTaskQuerySupport.tasks(for: area, project: project, in: tasks).filter {
            !$0.isDone &&
                !$0.isCancelled &&
                !$0.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// The linked calendar's meeting notes that have not yet ended, newest event first.
    ///
    /// - Parameters:
    ///   - todayKey: the host's observed day, not a clock read in a body ([[T-5012]]).
    ///   - nowMinutes: minutes past midnight now; an event today that has ended drops out.
    static func upcomingEventNotes(
        linkedCalendarID: String,
        in notes: [Note],
        todayKey: String,
        nowMinutes: Int
    ) -> [Note] {
        CadenceEventNoteSupport.meetingNotes(forLinkedCalendarID: linkedCalendarID, in: notes)
            .filter { !isPast($0, todayKey: todayKey, nowMinutes: nowMinutes) }
    }

    /// An undated note is never past. A dated one is past before today, or today once its end (its
    /// start, when it has no end) is behind `nowMinutes`.
    static func isPast(_ note: Note, todayKey: String, nowMinutes: Int) -> Bool {
        guard !note.eventDateKey.isEmpty else { return false }
        if note.eventDateKey < todayKey { return true }
        guard note.eventDateKey == todayKey else { return false }
        let comparisonMinutes = note.eventEndMin >= 0 ? note.eventEndMin : note.eventStartMin
        return comparisonMinutes >= 0 && comparisonMinutes < nowMinutes
    }

    // MARK: - Search and tag filter

    /// The tags the filter bar offers: those on any note or task note this tab lists, in the
    /// catalogue's order.
    static func filterableTags(notes: [Note], taskNotes: [AppTask], in allTags: [Tag]) -> [Tag] {
        let noteSlugs = notes.flatMap { ($0.tags ?? []).map(\.slug) }
        let taskSlugs = taskNotes.flatMap { ($0.tags ?? []).map(\.slug) }
        let slugs = Set(noteSlugs + taskSlugs)
        return allTags.filter { slugs.contains($0.slug) }
    }

    /// A note survives when it carries **every** required tag and, given a query, the query is in
    /// its title, its body (task embeds read under the task's live title — see
    /// `MarkdownTaskEmbedTitleCache`), or one of its tags' names or slugs.
    static func filter(
        _ notes: [Note],
        query rawQuery: String,
        requiredTagSlugs: Set<String>,
        tasks: [AppTask]
    ) -> [Note] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty || !requiredTagSlugs.isEmpty else { return notes }
        // Built once here, not once per note.
        let taskTitles = MarkdownTaskEmbedTitleCache.titles(for: tasks)
        return notes.filter { note in
            let noteTagSlugs = Set((note.tags ?? []).map(\.slug))
            guard requiredTagSlugs.isSubset(of: noteTagSlugs) else { return false }
            guard !query.isEmpty else { return true }
            return note.displayTitle.localizedCaseInsensitiveContains(query) ||
                MarkdownTaskEmbedTitleCache.resolving(note.content, titles: taskTitles)
                    .localizedCaseInsensitiveContains(query) ||
                note.sortedTags.contains { tag in
                    tag.name.localizedCaseInsensitiveContains(query) ||
                        tag.slug.localizedCaseInsensitiveContains(TagSupport.slug(for: query))
                }
        }
    }

    /// A task note survives when it carries every required tag and, given a query, the query is in
    /// its title or its notes.
    static func filter(
        taskNotes: [AppTask],
        query rawQuery: String,
        requiredTagSlugs: Set<String>
    ) -> [AppTask] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return taskNotes.filter {
            let taskTagSlugs = Set(($0.tags ?? []).map(\.slug))
            guard requiredTagSlugs.isSubset(of: taskTagSlugs) else { return false }
            guard !query.isEmpty else { return true }
            return $0.title.localizedCaseInsensitiveContains(query) ||
                $0.notes.localizedCaseInsensitiveContains(query)
        }
    }
}
