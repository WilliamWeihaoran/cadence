import Foundation

// MARK: - Drop key → seed

/// What a task group *is*, for the purpose of a dropped `+`.
///
/// The cases are the grouping modes the app actually offers, not a general taxonomy: iOS groups by
/// date (Today), by completion status (Inbox, All Tasks) and by kanban section (list detail);
/// macOS adds by list and by priority. Naming the grouping rather than passing a raw key is what
/// keeps the rule in one place — `CadenceTaskDropSupport.dropKey(forGroup:)` decides once, for
/// every surface, what a header of that kind can hand a new task, including that some kinds hand
/// over nothing and so are not drop targets at all.
///
/// This exists because `CadenceTaskDisplayGroup.dropKey` is **not** in fact populated by every
/// host: only `priorityDisplayGroups` fills it in, `sectionGroups` and `dateDisplayGroups` leave it
/// nil, and the iOS Today, Inbox and All Tasks surfaces do not use `CadenceTaskDisplayGroup` at
/// all. Reading the field would have lit headers up that then seeded nothing.
enum CadenceTaskGroupDropIdentity: Equatable {
    /// One of the Today screen's four date buckets.
    case todayDate(CadenceTodayTaskGroupKind)
    /// "Active" / "Completed" — a status group, which is not a placement.
    case completion
    /// A whole list. `key` is the `inbox` / `a_<uuid>` / `p_<uuid>` spelling `assignTask` parses.
    case list(key: String, name: String)
    /// A list group **on the Today screen**. The same list, plus the day the page is about — see
    /// `dropKey(forGroup:)` for why it is a case of its own rather than a `.list`.
    case todayList(key: String, name: String)
    /// A kanban section inside a list. Carries the list too: a section belongs to one.
    case section(listKey: String, listName: String, name: String)
    case priority(TaskPriority)
}

/// What "create a task with the destination's attributes" actually resolves to.
///
/// The vocabulary is the `dropKey` one `CadenceTaskDisplayGroup` already carries and
/// `TasksPanelSupport.assignTask` already reads — `list:`, `date:`, `priority:` — extended with
/// `section:` and `due:` and with several keys joinable by `|` so one destination can contribute
/// more than one attribute. Reusing it is the point: a group that can *move* a task into itself
/// can now *seed* a new one the same way, from the same string, with no second vocabulary to keep
/// in step.
///
/// **The two vocabularies do differ on one key, deliberately.** `assignTask` reads
/// `date:scheduled` as "push this to tomorrow", because it is moving a task out of a bucket it no
/// longer belongs in. Creating is not moving: "Scheduled" is *some* future day, not a day, so
/// seeding tomorrow would be inventing a date the destination never named. It contributes nothing
/// here. `date:unscheduled` likewise — no date is what an unseeded task already has.
enum CadenceTaskDropSupport {
    static let separator: Character = "|"

    // MARK: What a task row offers

    /// The destination key for a drop onto an existing task row.
    ///
    /// **A row is the drop target because a row is the only thing on an iOS task surface that
    /// reliably knows its group.** Grouping on iOS is by section, by date, or by list, and a row
    /// inside such a group carries that group's defining attribute by construction — so one rule
    /// covers every grouping without each screen having to declare which one it is using.
    ///
    /// What it contributes is **placement**: the list, the section, the do date and the due date —
    /// where this work lives and when it is due. Deliberately *not* the row's priority, tags,
    /// notes, estimate, goal or recurrence. Priority is the clearest of those: it is a judgement
    /// about one task's importance, which a brand-new empty task has not earned, and the composer
    /// has `!`/`!!`/`!!!` and a chip for saying otherwise in the same keystroke.
    ///
    /// A row with none of the four — an Inbox task with no dates — yields `list:inbox` alone, and
    /// the composer opens exactly as tapping the button opens it. That is the honest answer for a
    /// destination with nothing to inherit: degrade to the tap, do not invent.
    static func dropKey(for task: AppTask) -> String {
        var parts = [listKey(for: task)]
        // Inbox is the absence of a list, and a list is what owns sections, so there is nothing to
        // name there — the same rule `CadenceTaskComposerSupport.showsSectionChip` applies.
        if task.project != nil || task.area != nil {
            parts.append("section:\(task.resolvedSectionName)")
        }
        if !task.scheduledDate.isEmpty {
            parts.append("date:\(task.scheduledDate)")
        }
        if !task.dueDate.isEmpty {
            parts.append("due:\(task.dueDate)")
        }
        return parts.joined(separator: String(separator))
    }

    // MARK: What a group header offers

    /// The destination key for a drop onto a group *header*.
    ///
    /// **A header's key is what every row under it shares** — the row rule lifted one level. A row
    /// is the drop target because it carries its group's defining attribute by construction; a
    /// header carries that same attribute directly, and only that. So a header never contributes
    /// more than the group named, and it reaches the one place a row cannot: a group with no rows,
    /// which is exactly where seeding a new task from the group is most useful.
    ///
    /// **`nil` means the header is not a drop target at all**, and that is the deliberate departure
    /// from the row rule. A row with nothing to give still degrades to what a tap does, because a
    /// row is an object: the drag is pointing at something real either way, and refusing some rows
    /// and not others would be invisible to the eye. A header is a *label*. There is nothing under
    /// the pointer but words, so a header that lights up and then hands over nothing is pure noise
    /// — and headers are told apart by their titles, so "Due Today accepts, Overdue does not" is
    /// legible in a way "this row accepts, that one does not" would never be.
    ///
    /// Three families resolve to nothing, for two different reasons:
    /// - **Overdue** and **Past Do** share a date that has already gone by. `dateValue` would drop
    ///   it, so the header would accept and seed nothing.
    /// - **Active** / **Completed** are completion status, not placement. Every new task is active,
    ///   and none is created done — there is nothing here a composer could start from.
    static func dropKey(forGroup identity: CadenceTaskGroupDropIdentity) -> String? {
        switch identity {
        case .todayDate(let kind):
            switch kind {
            // Both of these are defined by a day in the past. See `dateValue`.
            case .overdue, .pastDo: return nil
            // On the Today screen these two buckets are exact: `todayGroups` hands `dueToday`
            // every task whose `dueDate` is today, and — because the overdue and due-today buckets
            // have already claimed everything holding a due date — `plannedToday` only ever holds
            // tasks whose `scheduledDate` is today.
            case .dueToday: return "due:today"
            case .plannedToday: return "date:today"
            }
        case .completion:
            return nil
        case .list(let key, _):
            return "list:\(key)"
        case .todayList(let key, _):
            // **A group seeds everything that defines membership in it, not just the narrowest
            // thing.** A row is under this header because it is in that list *and* because it is
            // on Today; a key naming only the list would file the new task correctly and then let
            // it vanish from the page it was dropped on, which is the one outcome a drop target
            // must not produce. Same rule as `.section`, which carries its list for the same
            // reason: a section belongs to a list, and a Today list group belongs to today.
            //
            // A plain `.list` — a list detail's empty state, the Inbox panel — must *not* pick a
            // date up here. There the day is not part of what the group is, and seeding one would
            // be inventing a date the destination never named.
            return "list:\(key)\(separator)date:today"
        case .section(let listKey, _, let name):
            return "list:\(listKey)\(separator)section:\(name)"
        case .priority(let priority):
            // The one identity the model already spells this way: `priorityDisplayGroups` populates
            // `CadenceTaskDisplayGroup.dropKey` with exactly this string. Priority is withheld from
            // a *row's* key because it is a judgement about that one task; a priority group header
            // is the field itself, and dropping on it is asking for it by name.
            return "priority:\(priority.rawValue)"
        }
    }

    /// The display name a group's caption needs and its key cannot carry. See `placementCaption`.
    static func listName(forGroup identity: CadenceTaskGroupDropIdentity) -> String {
        switch identity {
        case .list(_, let name), .todayList(_, let name): return name
        case .section(_, let listName, _): return listName
        case .todayDate, .completion, .priority: return ""
        }
    }

    /// Whether a group with no rows still earns its header.
    ///
    /// **A group you can still add to does not vanish; a group you cannot does.** An empty kanban
    /// column is the case this rule exists for — it is a column you made and have not filled, and
    /// hiding it is what put the only useful drop target out of reach. An empty "Completed" is a
    /// heading over nothing with nothing to do about it.
    ///
    /// It is the same predicate as `dropKey(forGroup:) != nil` on purpose: "visible when empty" and
    /// "accepts a dropped `+`" are one property, so a header can never be shown as an empty
    /// invitation it would then refuse.
    static func showsWhenEmpty(_ identity: CadenceTaskGroupDropIdentity?) -> Bool {
        guard let identity else { return false }
        return dropKey(forGroup: identity) != nil
    }

    private static func listKey(for task: AppTask) -> String {
        // Project before area: a project task's `area` is left nil by `TaskCreationService`, but
        // reading the more specific one first means a row repaired into holding both still lands
        // where the UI shows it.
        if let project = task.project { return "list:\(containerKey(for: .project(project.id)))" }
        if let area = task.area { return "list:\(containerKey(for: .area(area.id)))" }
        return "list:\(containerKey(for: .inbox))"
    }

    // MARK: What a surface knows about itself

    /// The `list:` value for a container a *page* is scoped to, in the `inbox` / `a_<uuid>` /
    /// `p_<uuid>` spelling `container(fromListKey:)` reads back and `assignTask` already parses.
    ///
    /// `dropKey(for:)` reads a row's list off the row. A group *header* has no row to read — a
    /// list-detail section header knows which list it is in only because the page does — so the
    /// page hands its own container in. One spelling of that string, produced and consumed in the
    /// same file, is what stops a surface inventing a fourth encoding of "which list".
    static func containerKey(for container: TaskContainerSelection) -> String {
        switch container {
        case .inbox: return "inbox"
        case .area(let id): return "a_\(id.uuidString)"
        case .project(let id): return "p_\(id.uuidString)"
        }
    }

    /// What a **section** header inside a list is, for a dropped `+`.
    ///
    /// The Inbox answer is not a special case bolted on: a section belongs to a list, and the Inbox
    /// is the *absence* of one, so there is no column there to name. It is the same rule
    /// `dropKey(for:)` applies when it withholds `section:` from an unfiled row, and the same one
    /// `seed(forDropKey:)` enforces when it collapses a key naming both — stated here so a caller
    /// cannot mint a `.section` identity the resolver would then contradict.
    static func groupIdentity(
        container: TaskContainerSelection,
        listName: String,
        sectionName: String
    ) -> CadenceTaskGroupDropIdentity {
        guard container != .inbox else { return groupIdentity(container: container, listName: listName) }
        return .section(
            listKey: containerKey(for: container),
            listName: listName,
            name: sectionName
        )
    }

    /// What a **whole list** is, for a dropped `+`: the identity a page scoped to one list hands
    /// its empty state, which is the one destination left when there are no rows and no columns
    /// drawn to point at. Inbox's own empty panel already uses it; a list detail's is the same
    /// case with a real list behind it.
    static func groupIdentity(
        container: TaskContainerSelection,
        listName: String
    ) -> CadenceTaskGroupDropIdentity {
        .list(key: containerKey(for: container), name: listName)
    }

    // MARK: Resolution

    /// The composer seed a drop key produces.
    ///
    /// A seed, as everywhere else in this app, is a **starting point and not a constraint**: every
    /// field here is also a chip in the composer's strip, so the destination's assumption is shown
    /// before the task exists and can be overruled without leaving the sheet.
    static func seed(forDropKey key: String, todayKey: String) -> CadenceTaskComposerSeed {
        var seed = CadenceTaskComposerSeed()
        for part in key.split(separator: separator).map(String.init) {
            apply(part, to: &seed, todayKey: todayKey)
        }
        // A section belongs to a list. A key that names both Inbox and a section is contradicting
        // itself; the list wins, because that is the field the section is a subdivision of.
        if seed.container == .inbox {
            seed.sectionName = TaskSectionDefaults.defaultName
        }
        return seed
    }

    /// The seed a released **capture drag** commits to: the placement it landed on, or — when it
    /// landed on nothing at all — whatever the button itself already knew.
    ///
    /// The base is not always empty, which is the whole reason this overload exists. The tab bar's
    /// `+` is deliberately unscoped, so its base *is* an empty seed; a page's corner `+` is already
    /// standing on a list, or on today, and a drag that fizzles over blank space should not throw
    /// that away and hand back a bare Inbox composer.
    static func seed(
        forDropKey key: String?,
        todayKey: String,
        base: CadenceTaskComposerSeed
    ) -> CadenceTaskComposerSeed {
        guard let key, !key.isEmpty else { return base }
        return seed(forDropKey: key, todayKey: todayKey)
    }

    private static func apply(
        _ part: String,
        to seed: inout CadenceTaskComposerSeed,
        todayKey: String
    ) {
        if part.hasPrefix("list:") {
            seed.container = container(fromListKey: String(part.dropFirst(5)))
        } else if part.hasPrefix("section:") {
            let name = String(part.dropFirst(8)).trimmingCharacters(in: .whitespacesAndNewlines)
            seed.sectionName = name.isEmpty ? TaskSectionDefaults.defaultName : name
        } else if part.hasPrefix("date:") {
            if let dateKey = dateValue(String(part.dropFirst(5)), todayKey: todayKey) {
                seed.doDateKey = dateKey
            }
        } else if part.hasPrefix("due:") {
            if let dateKey = dateValue(String(part.dropFirst(4)), todayKey: todayKey) {
                seed.dueDateKey = dateKey
            }
        } else if part.hasPrefix("priority:") {
            // No row emits this — `dropKey(for:)` deliberately withholds priority. It is read
            // because `CadenceTaskQuerySupport.priorityDisplayGroups` already *produces* it, so a
            // priority-grouped surface adopting this drag gets the right seed for free rather than
            // needing the resolver changed underneath it.
            if let priority = TaskPriority(rawValue: String(part.dropFirst(9))) {
                seed.priority = priority
            }
        }
    }

    /// `list:` values use the `inbox` / `a_<uuid>` / `p_<uuid>` spelling `assignTask` already
    /// parses, not the `inbox` / `area:<uuid>` / `project:<uuid>` spelling of
    /// `CadenceTaskComposerSupport.token(for:)`. Two encodings for one idea is a wart, but the
    /// drop-key one is the wire format of a table this feature is joining, and quietly changing it
    /// would break the surfaces already speaking it.
    private static func container(fromListKey value: String) -> TaskContainerSelection {
        if value.hasPrefix("a_"), let id = UUID(uuidString: String(value.dropFirst(2))) {
            return .area(id)
        }
        if value.hasPrefix("p_"), let id = UUID(uuidString: String(value.dropFirst(2))) {
            return .project(id)
        }
        return .inbox
    }

    // MARK: What the ghost says

    /// The one line the insertion ghost prints under "New task": the placement the drop will
    /// actually seed, spelled the way the composer's chips will spell it.
    ///
    /// **This exists because the ghost's *position* promises nothing.** A drop seeds placement —
    /// list, section, do date, due date — and never `order`; `TaskCreationService` appends, and the
    /// surface's own sort decides where the row finally sits. So the gap that opens is only "a new
    /// task joins here", and the part that *is* kept has to be said in words rather than implied
    /// by a position. Deriving it from the same `seed(forDropKey:)` the drop will use is what stops
    /// the caption and the composer disagreeing: the past-date guard, the Inbox/section
    /// contradiction rule and the `scheduled`/`unscheduled` exclusions are applied once, here and
    /// there both.
    ///
    /// `listName` is supplied by the caller because a `list:` key carries a UUID, not a name, and
    /// resolving one needs a `ModelContext` this layer deliberately does not have. An empty name —
    /// a list row whose list has no name — drops the segment rather than inventing one.
    static func placementCaption(
        forDropKey key: String,
        todayKey: String,
        listName: String
    ) -> String {
        let seed = seed(forDropKey: key, todayKey: todayKey)
        var placement: [String] = []

        // **Only a key that names a list may print one.** `CadenceTaskComposerSeed.container`
        // defaults to `.inbox`, so reading the resolved seed alone made every key without a
        // `list:` part claim "Inbox" — which no task row could ever produce (a row always emits
        // one) but a group header can: "Due Today" names a date and nothing else. The caption is
        // what the drop *inherits*; the composer's own chip is where the default belongs.
        let namesList = key
            .split(separator: separator)
            .contains { $0.hasPrefix("list:") }

        if !namesList {
            if seed.sectionName != TaskSectionDefaults.defaultName {
                placement.append(seed.sectionName)
            }
        } else if seed.container == .inbox {
            placement.append("Inbox")
        } else {
            let trimmed = listName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { placement.append(trimmed) }
            // The default section is what a task in that list gets anyway, so naming it says
            // nothing the list has not already said — the rule `showsSectionChip` applies.
            if seed.sectionName != TaskSectionDefaults.defaultName {
                placement.append(seed.sectionName)
            }
        }

        var parts: [String] = []
        if !placement.isEmpty { parts.append(placement.joined(separator: " › ")) }
        if !seed.doDateKey.isEmpty { parts.append("Do \(dayLabel(seed.doDateKey, todayKey: todayKey))") }
        if !seed.dueDateKey.isEmpty { parts.append("Due \(dayLabel(seed.dueDateKey, todayKey: todayKey))") }
        // Only a priority *group* header emits `priority:` — no row does, deliberately. Spelled
        // "High priority" rather than bare "High" because it sits in a list beside "Inbox" and
        // "Do Today", where a lone adjective would not say which field it is setting. Without this
        // the one seed a priority header contributes would be the one thing the ghost did not
        // mention, which is the disagreement this caption exists to prevent.
        if seed.priority != .none { parts.append("\(seed.priority.label) priority") }
        return parts.joined(separator: " · ")
    }

    /// The same caption for a group header, or `nil` when the header is not a drop target.
    ///
    /// Deliberately the *same* function the row ghost calls, reached through the same
    /// `dropKey`→`seed` path. A header and a row that promise different things for the same
    /// placement would be the defect worth avoiding here, and the only way to be sure they cannot
    /// is for there to be one sentence-builder and one set of rules behind it.
    static func placementCaption(
        forGroup identity: CadenceTaskGroupDropIdentity,
        todayKey: String
    ) -> String? {
        guard let key = dropKey(forGroup: identity) else { return nil }
        return placementCaption(
            forDropKey: key,
            todayKey: todayKey,
            listName: listName(forGroup: identity)
        )
    }

    private static func dayLabel(_ key: String, todayKey: String) -> String {
        key == todayKey ? "Today" : DateFormatters.shortDateString(from: key)
    }

    /// `today`, or a `yyyy-MM-dd` day that has not already gone by.
    ///
    /// **A date in the past is dropped, not seeded.** Overdue and Past Do are real groups on the
    /// Today screen, and a row in one of them carries a day that has already been and gone — a new
    /// task cannot be done yesterday, and starting it life late is worse than starting it undated.
    /// Keys are `yyyy-MM-dd`, so the string comparison *is* the date comparison.
    ///
    /// **The comparison is only a date comparison once the key is fixed-width**, which is why the
    /// canonical spelling is taken from `normalizedDateKey` rather than the caller's text being
    /// kept after a parse: `"2026-8-20"` parses happily and then sorts *after* `"2026-08-25"`, so
    /// validating by parsing and returning the raw string would seed a composer with a key that
    /// loses every later comparison — the past check on this very line included.
    private static func dateValue(_ value: String, todayKey: String) -> String? {
        if value == "today" { return todayKey }
        // "Scheduled" and "Unscheduled" name a bucket, not a day. See the type comment.
        guard value != "scheduled", value != "unscheduled" else { return nil }
        guard let key = DateFormatters.normalizedDateKey(value), key >= todayKey else { return nil }
        return key
    }
}
