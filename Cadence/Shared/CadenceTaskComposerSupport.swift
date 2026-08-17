import Foundation

/// What an entry point hands the task composer.
///
/// The iOS counterpart of macOS's `TaskCreationSeed`, field for field, so a capture bar, a list
/// screen, or the tab bar's `+` preseeds the same way on both platforms. It lives here rather than
/// beside the sheet because everything under `Cadence/iOS/` is inside `#if os(iOS)` and therefore
/// invisible to `CadenceTests`, which builds for macOS.
///
/// A seed is a **starting point, not a constraint**: every field it carries is also reachable from
/// a row on the sheet, so a list-scoped entry point can seed its list and still be overruled
/// without leaving the sheet. That is also why the seeded fields are *rows* and not chips — a
/// pre-filled row states its value in the page, where a strip of chips only implied one.
struct CadenceTaskComposerSeed: Equatable {
    var title: String = ""
    var notes: String = ""
    /// The do date, `""` for none.
    var doDateKey: String = ""
    /// The due date, `""` for none.
    var dueDateKey: String = ""
    var priority: TaskPriority = .none
    var container: TaskContainerSelection = .inbox
    var sectionName: String = TaskSectionDefaults.defaultName
    /// Timeline slot in minutes from midnight, `-1` for none.
    var scheduledStartMin: Int = -1
    var estimatedMinutes: Int = 30

    init(
        title: String = "",
        notes: String = "",
        doDateKey: String = "",
        dueDateKey: String = "",
        priority: TaskPriority = .none,
        container: TaskContainerSelection = .inbox,
        sectionName: String = TaskSectionDefaults.defaultName,
        scheduledStartMin: Int = -1,
        estimatedMinutes: Int = 30
    ) {
        self.title = title
        self.notes = notes
        self.doDateKey = doDateKey
        self.dueDateKey = dueDateKey
        self.priority = priority
        self.container = container
        self.sectionName = sectionName
        self.scheduledStartMin = scheduledStartMin
        self.estimatedMinutes = estimatedMinutes
    }
}

/// The composer's editable state, minus the title, notes and tags.
///
/// These five are exactly what the sheet's do-date buttons and value rows edit, which is why they
/// travel together: the rows bind to one of these rather than to five separate `@State` properties
/// that could be reordered or half-passed.
struct CadenceTaskComposerFields: Equatable {
    var container: TaskContainerSelection
    var sectionName: String
    /// The do date, `""` for none.
    var doDateKey: String
    /// The due date, `""` for none.
    var dueDateKey: String
    var priority: TaskPriority
}

/// The arithmetic behind the iOS create-task sheet: what a seed resolves to, which rows a draft
/// earns, what each row and do-date button says, and what the whole thing hands
/// `TaskCreationService`.
///
/// Nothing here draws anything, and nothing here builds an `AppTask` by hand — creation goes through
/// `TaskCreationService` exactly as macOS's `CreateTaskSheet` and `InlineTaskComposer` do.
enum CadenceTaskComposerSupport {
    /// Matches `TaskCreationSeed.estimatedMinutes` and `InlineTaskComposerSupport`, so a task
    /// captured on iPhone is the same length as one captured anywhere else.
    static let defaultEstimatedMinutes = 30

    // MARK: - Seed resolution

    static func initialFields(for seed: CadenceTaskComposerSeed) -> CadenceTaskComposerFields {
        let trimmedSection = seed.sectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        return CadenceTaskComposerFields(
            container: seed.container,
            sectionName: trimmedSection.isEmpty ? TaskSectionDefaults.defaultName : trimmedSection,
            doDateKey: seed.doDateKey,
            dueDateKey: seed.dueDateKey,
            priority: seed.priority
        )
    }

    // MARK: - Row visibility

    /// Whether the section row is worth a line on the sheet.
    ///
    /// Inbox is the *absence* of a list, and a list is what owns sections, so there is nothing to
    /// choose between there. Beyond that the rule is the inspector breadcrumb's: a lone `Default`
    /// section is a control with one option, which is not a control. It matters more now than it
    /// did as a chip — every row costs 57pt of a sheet that has to stay readable with the keyboard
    /// up, so a row that can only say one thing does not get one.
    static func showsSectionRow(
        container: TaskContainerSelection,
        availableSections: [String]
    ) -> Bool {
        guard container != .inbox else { return false }
        return CadenceTaskInspectorSupport.showsSectionSegment(availableSections: availableSections)
    }

    static func canCreate(title: String) -> Bool {
        !TaskTitleSupport.isEmpty(title)
    }

    // MARK: - Draft

    /// The draft the sheet hands `TaskCreationService`.
    ///
    /// The **raw** title goes in, markers and all: `TaskCreationDraft` already strips a `!`/`!!`/
    /// `!!!` marker off the title and reads a priority out of it, and re-implementing that here is
    /// how the two would drift.
    static func draft(
        title: String,
        notes: String,
        fields: CadenceTaskComposerFields,
        tags: [Tag],
        scheduledStartMin: Int = -1,
        estimatedMinutes: Int = defaultEstimatedMinutes
    ) -> TaskCreationDraft {
        TaskCreationDraft(
            title: title,
            notes: notes,
            priority: fields.priority,
            container: fields.container,
            sectionName: fields.sectionName,
            dueDateKey: fields.dueDateKey,
            scheduledDateKey: fields.doDateKey,
            subtaskTitles: [],
            tags: tags,
            // A slot on no day is not a slot. The service enforces the same rule; agreeing with it
            // here keeps the draft readable on its own.
            scheduledStartMin: fields.doDateKey.isEmpty ? -1 : scheduledStartMin,
            estimatedMinutes: estimatedMinutes
        )
    }

    // MARK: - Inline title markers

    /// The priority the draft will actually be created with, given what the title says and what the
    /// chip was set to.
    ///
    /// Same precedence `TaskCreationDraft.resolvedPriority` applies at creation, surfaced early so
    /// the chip can show a `!!!` taking effect while it is still being typed instead of announcing
    /// it only after the sheet has closed.
    static func resolvedPriority(title: String, selected: TaskPriority) -> TaskPriority {
        TaskTitleSupport.priorityShortcut(in: title)?.priority ?? selected
    }

    /// The title with any `!`/`!!`/`!!!` marker taken out.
    ///
    /// Used when a priority is picked from the chip: without it a title still ending in `!!!` would
    /// silently overrule the choice the user just made, because the marker wins at creation.
    static func titleClearingPriorityMarker(_ title: String) -> String {
        TaskTitleSupport.priorityShortcut(in: title)?.title ?? TaskTitleSupport.normalized(title)
    }

    /// The title once a `~` or `#` suggestion has been accepted — everything before the marker.
    ///
    /// The marker and its query are consumed by the choice they produced; what the task is called
    /// should not carry the mechanics of how its list was picked.
    static func title(removingShortcut shortcut: TaskTitleInlineShortcut) -> String {
        shortcut.prefix.trimmingCharacters(in: .whitespaces)
    }

    /// Prefix match, case-insensitive, empty query matches everything.
    ///
    /// The rule macOS's container picker already searches by (`ContainerPickerFilterSupport.matches`
    /// forwards here), so `~des` finds "Design" on both platforms and neither loosens into a
    /// substring match that would rank "Wedding" under `~d`.
    static func matchesQuery(_ name: String, query: String) -> Bool {
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
        guard !trimmedQuery.isEmpty else { return true }
        return name.lowercased().hasPrefix(trimmedQuery.lowercased())
    }

    // MARK: - Do date buttons

    /// The two fixed days the do-date buttons offer. The third button is a picker, not a day.
    enum DoDateChoice: Hashable {
        case today
        case tomorrow

        var dayOffset: Int {
            switch self {
            case .today: return 0
            case .tomorrow: return 1
            }
        }

        var label: String {
            switch self {
            case .today: return "Today"
            case .tomorrow: return "Tomorrow"
            }
        }
    }

    static func dateKey(for choice: DoDateChoice, from reference: Date = Date()) -> String {
        let day = Calendar.current.date(byAdding: .day, value: choice.dayOffset, to: reference) ?? reference
        return DateFormatters.dateKey(from: day)
    }

    static func isSelected(_ choice: DoDateChoice, doDateKey: String) -> Bool {
        guard !doDateKey.isEmpty else { return false }
        return DateFormatters.dayOffset(from: doDateKey) == choice.dayOffset
    }

    /// What tapping Today or Tomorrow leaves the do date as.
    ///
    /// **Tapping the day the task already has clears it.** These three buttons are the whole
    /// do-date control now — there is no row beside them holding a Clear — so if the only way to
    /// undo a mis-tapped "Today" were to open the picker, one tap could not be taken back by one
    /// tap. It is also the behaviour `Cmd+T` has had on macOS since long before this sheet.
    static func toggledDoDateKey(
        current: String,
        tapping choice: DoDateChoice,
        from reference: Date = Date()
    ) -> String {
        isSelected(choice, doDateKey: current) ? "" : dateKey(for: choice, from: reference)
    }

    /// Whether the do date is a day the two fixed buttons cannot say, and so is being carried by
    /// the picker button itself.
    static func isCustomDoDate(_ doDateKey: String) -> Bool {
        guard !doDateKey.isEmpty else { return false }
        return !isSelected(.today, doDateKey: doDateKey) && !isSelected(.tomorrow, doDateKey: doDateKey)
    }

    /// What the third button says: its own name while the date is unset or is one of the other two
    /// buttons' days, and the day itself once it is holding one — so a seeded "next Thursday" is
    /// legible without opening anything.
    static func doDatePickLabel(_ doDateKey: String) -> String {
        isCustomDoDate(doDateKey) ? DateFormatters.shortDateString(from: doDateKey) : "Pick…"
    }

    // MARK: - Row values

    /// What the priority row says. `None` is a value here, not a prompt: the row is already
    /// labelled "Priority", so the trailing control's job is to answer it — the same wording the
    /// task inspector's priority row uses, rather than the `!!` mark the chip used to show.
    static func priorityValueLabel(_ priority: TaskPriority) -> String {
        priority.label
    }

    /// What the tags row says: the tag while there is one, the count once there are several.
    ///
    /// Listing every name is what the chips inside the picker are for; this one has to fit on the
    /// trailing edge of a 44pt row beside its label.
    static func tagsValueLabel(names: [String]) -> String {
        let usable = names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        switch usable.count {
        case 0: return "None"
        case 1: return usable[0]
        default: return "\(usable.count) tags"
        }
    }

    // MARK: - Container tokens

    /// `TaskContainerSelection` as the `"inbox"` / `"area:UUID"` / `"project:UUID"` string the iOS
    /// container picker is written against.
    ///
    /// That encoding was hand-spelled in four iOS files, each re-deriving `dropFirst(5)` and
    /// `dropFirst(8)` from the prefix length. It is one mapping, so it is written once here and
    /// covered by tests; the new sheet is the only caller so far, and the others can adopt it
    /// without any change in behaviour.
    static func token(for selection: TaskContainerSelection) -> String {
        switch selection {
        case .inbox: return "inbox"
        case .area(let id): return "area:\(id.uuidString)"
        case .project(let id): return "project:\(id.uuidString)"
        }
    }

    /// The inverse of `token(for:)`. Anything unrecognised — including a stale identifier for a
    /// list that has since been deleted — reads as Inbox, which is where a task with no list lives.
    static func selection(fromToken token: String) -> TaskContainerSelection {
        if token.hasPrefix("area:"), let id = UUID(uuidString: String(token.dropFirst(5))) {
            return .area(id)
        }
        if token.hasPrefix("project:"), let id = UUID(uuidString: String(token.dropFirst(8))) {
            return .project(id)
        }
        return .inbox
    }
}
