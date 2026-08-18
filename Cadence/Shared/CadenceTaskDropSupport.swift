import Foundation
import Observation
import UniformTypeIdentifiers

// MARK: - The drag's own type

extension UTType {
    /// The create-task drag's payload type.
    ///
    /// Every drag context in this app carries a unique payload prefix so a drop target cannot be
    /// handed a payload from an unrelated one — `area:`, `project:`, `listTask:`, `taskBundle:`,
    /// `allDayEvent:`, and a bare task UUID are the ones already in use. This drag adds
    /// `newTask:` (below), but it also registers under a **content type** of its own rather than
    /// plain text, and that is what makes the rule structural rather than advisory:
    /// `onDrop(of:)` filters on content type *synchronously*, so a task row refuses a
    /// task-reorder drag before it ever lights up as a target. Registering as `public.text` and
    /// checking the prefix after an asynchronous load would mean the row highlights, accepts, and
    /// then does nothing — the failure mode this codebase keeps shipping.
    ///
    /// The prefix is still checked on the way out. The type keeps *other people's* drags away; the
    /// prefix keeps a malformed one of our own from being read as a source identifier.
    static let cadenceNewTaskDrag = UTType(exportedAs: "com.haoranwei.Cadence.new-task-drag")
}

/// The string a create-task drag carries: `newTask:<source UUID>`.
///
/// The identifier is the *button* the drag started from, not the task being created — no task
/// exists yet. It is what lets the drop find its way back to the control the finger lifted from,
/// which matters on iPad where several pages (and so several floating buttons) can be alive at
/// once and only one of them should open a composer.
enum CadenceTaskDropPayload {
    static let prefix = "newTask:"

    static func string(for sourceID: UUID) -> String {
        "\(prefix)\(sourceID.uuidString)"
    }

    static func sourceID(from payload: String) -> UUID? {
        guard payload.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(payload.dropFirst(prefix.count)))
    }

    static func itemProvider(sourceID: UUID) -> NSItemProvider {
        let provider = NSItemProvider()
        let data = Data(string(for: sourceID).utf8)
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.cadenceNewTaskDrag.identifier,
            visibility: .ownProcess
        ) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }
}

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
        case .list(_, let name): return name
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
    private static func dateValue(_ value: String, todayKey: String) -> String? {
        if value == "today" { return todayKey }
        // "Scheduled" and "Unscheduled" name a bucket, not a day. See the type comment.
        guard value != "scheduled", value != "unscheduled" else { return nil }
        guard DateFormatters.date(from: value) != nil, value >= todayKey else { return nil }
        return value
    }
}

// MARK: - Routing the drop back to the button

/// Carries a resolved drop from wherever it landed back to the create-task button it was dragged
/// from, which is the control that owns the composer sheet.
///
/// A shared object rather than a preference or an environment value for the reason
/// `SidebarDragContext` documents: a drag source and its drop target are arbitrarily far apart in
/// the view tree and cannot pass anything up or down between `onDrag` and `performDrop`. Unlike
/// `SidebarDragContext` this one is `@Observable`, because the button has to *react* to a drop
/// rather than merely read state during one.
@Observable
final class CadenceTaskDropCoordinator {
    struct Request: Identifiable, Equatable {
        let id = UUID()
        /// The button the drag started from. Only that button presents.
        let sourceID: UUID
        let seed: CadenceTaskComposerSeed
    }

    static let shared = CadenceTaskDropCoordinator()

    private(set) var pending: Request?

    /// Returns false — and changes nothing — for a payload this context did not write.
    @discardableResult
    func deliver(payload: String, dropKey: String, todayKey: String) -> Bool {
        guard let sourceID = CadenceTaskDropPayload.sourceID(from: payload) else { return false }
        pending = Request(
            sourceID: sourceID,
            seed: CadenceTaskDropSupport.seed(forDropKey: dropKey, todayKey: todayKey)
        )
        return true
    }

    /// Hands the request to its own source exactly once. Every other live button asks and gets
    /// nothing, which is what stops a drop opening four composers on an iPad.
    func consume(for sourceID: UUID) -> Request? {
        guard let request = pending, request.sourceID == sourceID else { return nil }
        pending = nil
        return request
    }
}
