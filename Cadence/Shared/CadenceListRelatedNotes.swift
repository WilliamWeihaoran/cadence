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

    /// An undated note is never past. A dated one is past once the day its event ends is behind
    /// today, or on that day once its end (its start, when it has no end) is behind `nowMinutes`.
    ///
    /// **[[T-19035]] -- an end that wraps ends on the next day.** The note stores its start's day
    /// and two wall-clock minutes, the end's read on whatever day the end falls
    /// (`CadenceEventNoteSupport.eventDateMetadata`). An end before the start (11 PM -> 1 AM), or
    /// an end at minute 0 (10 PM -> 12 AM, and the next-midnight reading of an all-day day that
    /// [[T-16880]] also takes) is on the day after the start, so the note stays upcoming for the
    /// whole start day and until that minute of the next. Comparing it against the start day
    /// dropped a 10 PM -> 12 AM note at 00:01 of its own day.
    ///
    /// Not covered: an event whose end is two or more days later -- a Mon-Wed all-day offsite, or a
    /// timed event across several midnights -- stores an end minute that does not wrap or wraps
    /// once, and nothing else on the note records the end's day. It still drops out at the end of
    /// its start day (or the day after). Fixing that needs a synced end-day field, a schema
    /// change ([[T-19039]]).
    static func isPast(_ note: Note, todayKey: String, nowMinutes: Int) -> Bool {
        guard !note.eventDateKey.isEmpty else { return false }
        let endDayKey = endsOnNextDay(startMin: note.eventStartMin, endMin: note.eventEndMin)
            ? (dayKey(after: note.eventDateKey) ?? note.eventDateKey)
            : note.eventDateKey
        if endDayKey < todayKey { return true }
        guard endDayKey == todayKey else { return false }
        let comparisonMinutes = note.eventEndMin >= 0 ? note.eventEndMin : note.eventStartMin
        return comparisonMinutes >= 0 && comparisonMinutes < nowMinutes
    }

    /// Whether a stored span's end minute is on the day after its start: an end before the start,
    /// or an end at midnight. A zero-length timed event (10:00 -> 10:00) is the same day.
    static func endsOnNextDay(startMin: Int, endMin: Int) -> Bool {
        guard startMin >= 0, endMin >= 0 else { return false }
        return endMin < startMin || endMin == 0
    }

    /// The `yyyy-MM-dd` key one calendar day after `key`. Pure day arithmetic, so it is done in
    /// a fixed zone: a key names a day, not an instant.
    private static func dayKey(after key: String) -> String? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
        guard let day = DateFormatters.date(from: key, in: calendar),
              let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
        return DateFormatters.dateKey(from: next, calendar: calendar)
    }

    // MARK: - Search and tag filter

    /// The tags the filter bar offers: the active tags on any note or task note this tab lists,
    /// one per slug, in the catalogue's order -- all of them, uncapped.
    ///
    /// **[[T-14451]].** This is the whole decision, for both platforms. The Mac's `TagFilterBar`
    /// used to drop archived tags, collapse duplicate slugs and cap the strip at eight on its own,
    /// while the iPad tab filtered archived in its own wrapper and kept duplicates, so a ninth tag could
    /// be filtered by on one platform and not the other, and the Mac search field tightened its
    /// padding for a bar that then drew nothing. Both bars now draw exactly this list, and
    /// `hasTagFilters` reads the same list the bar draws.
    static func filterableTags(notes: [Note], taskNotes: [AppTask], in allTags: [Tag]) -> [Tag] {
        let noteSlugs = notes.flatMap { ($0.tags ?? []).map(\.slug) }
        let taskSlugs = taskNotes.flatMap { ($0.tags ?? []).map(\.slug) }
        let slugs = Set(noteSlugs + taskSlugs)
        return TagSupport.uniqueBySlug(allTags.filter { !$0.isArchived && slugs.contains($0.slug) })
    }

    /// The slugs `filter` requires for a chip selection held as tag **ids**: the live slug of each
    /// selected tag the bar still offers.
    ///
    /// **[[T-17014]].** Both tabs held the selection as slugs and intersected it with the bar's
    /// slugs whenever they changed. `TagSupport.rename` rewrites a tag's slug, so renaming `work`
    /// to `Job` while its chip was on silently dropped the filter -- every note reappeared and the
    /// `Job` chip drew off. An id survives a rename; the slug is read here, at filter time.
    static func requiredTagSlugs(selectedTagIDs: Set<UUID>, filterableTags: [Tag]) -> Set<String> {
        Set(filterableTags.filter { selectedTagIDs.contains($0.id) }.map(\.slug))
    }

    /// The selection pruned to the tags the bar still offers: a tag archived, or no longer on
    /// anything listed, cannot stay a hidden requirement. A renamed tag keeps its id and so stays.
    static func prunedTagSelection(_ selectedTagIDs: Set<UUID>, filterableTags: [Tag]) -> Set<UUID> {
        selectedTagIDs.intersection(filterableTags.map(\.id))
    }

    /// [[T-18760]]: a list Notes tab draws its search field and tag chips only once the list has a
    /// note -- a field over an empty list narrows nothing. A list whose notes the query hides
    /// still shows the row, so the query can be cleared. The iPad tab's [[T-7031]] rule, which
    /// the Mac tab now reads too.
    static func showsFilterRow(hasAnyNotes: Bool) -> Bool {
        hasAnyNotes
    }

    /// The search text and chip selection a Notes tab holds -- the two controls `filter` reads.
    struct FilterControls: Equatable {
        var query: String
        var selectedTagIDs: Set<UUID>

        static let cleared = FilterControls(query: "", selectedTagIDs: [])
    }

    /// The controls to hold once the list's note count changes: unchanged while it has a note,
    /// cleared once its last note goes.
    ///
    /// **[[T-18770]].** [[T-18760]]'s `showsFilterRow` hides the field over an empty list but
    /// left its query in place, unseen, so the next note to arrive without `addNote` -- an event
    /// note from the linked calendar, a note filed in from elsewhere, a sync -- came back behind
    /// a pre-filled query the user typed before the list emptied, and could land as "No matches".
    /// The chips were already pruned with `filterableTags`; the query was not.
    static func controls(_ current: FilterControls, hasAnyNotes: Bool) -> FilterControls {
        hasAnyNotes ? current : .cleared
    }

    /// The controls to hold once `created` -- a note the tab just made and selected -- is on screen:
    /// unchanged when the note already passes `filter`, otherwise cleared, query and chips both.
    ///
    /// **[[T-18596]].** Both tabs selected a new note with the filter left on, and a new note is
    /// blank and untagged, so any query it does not match or any chip hid it: the editor wrote a
    /// note the column beside it did not list, or listed "No matches" beside. The filter is a view,
    /// not an assignment, so the note is never tagged from the chips -- the filter gives way.
    static func controls(
        revealing created: Note,
        from current: FilterControls,
        requiredTagSlugs: Set<String>,
        tasks: [AppTask]
    ) -> FilterControls {
        let passes = !filter([created], query: current.query, requiredTagSlugs: requiredTagSlugs, tasks: tasks).isEmpty
        return passes ? current : .cleared
    }

    /// A note survives when it carries **every** required tag and, given a query, the query is in
    /// its title, its body (task embeds read under the task's live title — see
    /// `MarkdownTaskEmbedTitleCache`), or one of its tags' names or slugs.
    ///
    /// **[[T-18412]]: "is in" means what Cmd+K and iOS Search mean.** Both legs asked
    /// `localizedCaseInsensitiveContains` of the whole trimmed query, which folds case but not
    /// diacritics and needs the words in the typed order, so `cafe` hid "Café menu" and
    /// `report draft` hid "Draft report" -- notes the other two search surfaces find from the same
    /// words. The match now goes through `CadenceSearchMatcher.matchScore`, the one scorer, as the
    /// Focus picker's did in [[T-13871]]. This is a filter, not a ranking: the rows keep the order
    /// they came in, and the required-tag gate is unchanged.
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
        let prepared = CadenceSearchMatcher.PreparedQuery(query)
        return notes.filter { note in
            let noteTagSlugs = Set((note.tags ?? []).map(\.slug))
            guard requiredTagSlugs.isSubset(of: noteTagSlugs) else { return false }
            guard !query.isEmpty else { return true }
            return matches(prepared, fields: [
                note.displayTitle,
                CadenceSearchNoteText.body(of: note, taskTitles: taskTitles),
                CadenceSearchTagSupport.text(for: note.sortedTags),
            ])
        }
    }

    /// A task note survives when it carries every required tag and, given a query, the query is in
    /// its title, its notes, or one of its tags' names or slugs.
    ///
    /// **[[T-13761]]: the tag leg is the notes' own.** This predicate stopped at title and notes, so
    /// in one search field typing `urgent` kept every note tagged Urgent and dropped every task note
    /// tagged Urgent -- although the filter bar above offers that tag *because* a task note carries
    /// it, and Cmd+K / iOS Search find the same task by the same tag name.
    static func filter(
        taskNotes: [AppTask],
        query rawQuery: String,
        requiredTagSlugs: Set<String>
    ) -> [AppTask] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let prepared = CadenceSearchMatcher.PreparedQuery(query)
        return taskNotes.filter {
            let taskTagSlugs = Set(($0.tags ?? []).map(\.slug))
            guard requiredTagSlugs.isSubset(of: taskTagSlugs) else { return false }
            guard !query.isEmpty else { return true }
            return matches(prepared, fields: [
                $0.title,
                $0.notes,
                CadenceSearchTagSupport.text(for: $0.sortedTags),
            ])
        }
    }

    /// The match both predicates share ([[T-18412]]): the shared scorer over title, body and the
    /// tags' names and slugs (`CadenceSearchTagSupport.text`, as Cmd+K and iOS Search read them).
    /// A non-blank query with nothing searchable in it -- `"`, `---` -- matches nothing (T-3099).
    private static func matches(_ query: CadenceSearchMatcher.PreparedQuery, fields: [String]) -> Bool {
        CadenceSearchMatcher.matchScore(query: query, fields: fields) != nil
    }
}
