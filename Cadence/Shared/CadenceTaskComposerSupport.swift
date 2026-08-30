import CoreGraphics
import Foundation

/// What an entry point hands the task composer.
///
/// The iOS counterpart of macOS's `TaskCreationSeed`, field for field, so a capture bar, a list
/// screen, or the tab bar's `+` preseeds the same way on both platforms. It lives here rather than
/// beside the sheet because everything under `Cadence/iOS/` is inside `#if os(iOS)` and therefore
/// invisible to `CadenceTests`, which builds for macOS.
///
/// A seed is a **starting point, not a constraint**: every field it carries is also reachable from
/// a tile on the sheet, so a list-scoped entry point can seed its list and still be overruled
/// without leaving the sheet. That is also why the seeded fields are *tiles* and not chips — a
/// pre-filled tile states its value under the field's own name, where a strip of chips only implied
/// one, and unlike a row it does so without spending a whole line per field.
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
/// These five are exactly what the sheet's value tiles edit, which is why they travel together: the
/// tiles bind to one of these rather than to five separate `@State` properties that could be
/// reordered or half-passed.
struct CadenceTaskComposerFields: Equatable {
    var container: TaskContainerSelection
    var sectionName: String
    /// The do date, `""` for none.
    var doDateKey: String
    /// The due date, `""` for none.
    var dueDateKey: String
    var priority: TaskPriority
}

/// The arithmetic behind the iOS create-task sheet: what a seed resolves to, which tiles a draft
/// earns, what each tile says, and what the whole thing hands `TaskCreationService`.
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

    // MARK: - Tile visibility

    /// Whether the section tile is worth drawing.
    ///
    /// Inbox is the *absence* of a list, and a list is what owns sections, so there is nothing to
    /// choose between there. Beyond that the rule is the inspector breadcrumb's: a lone `Default`
    /// section is a control with one option, which is not a control.
    ///
    /// The name still says `Row` because the sheet's other callers and its tests do; what it gates
    /// is now a tile in the last row's spare half. See
    /// `CadenceTaskComposerLayout.tileCount(showsSectionTile:)` for why that is where a field that
    /// comes and goes belongs.
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

    // MARK: - Named days

    /// The two days a date field is most often set to, and which a tile can therefore name instead
    /// of dating.
    ///
    /// These were the two fixed buttons of the do-date's old three-button block. That block is gone
    /// — the do date is a tile like every other field now, and Today / Tomorrow are the first two
    /// pills inside the picker it opens (`CadenceQuickDatePopover`) — but the *naming* is what
    /// `dateValueLabel` still needs: a tile reading `Today` says more than one reading `Aug 17`.
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

    // MARK: - Tile values

    /// What a Do or Due tile says.
    ///
    /// `None` when unset — a value, not a prompt, because the caption above it already asks the
    /// question. Today and tomorrow are **named** rather than dated: those two are most of the do
    /// dates anyone sets, and `Today` is read without arithmetic where `Aug 17` is not. Anything
    /// else is the date itself, so a seeded "next Thursday" is legible without opening the picker.
    static func dateValueLabel(_ dateKey: String) -> String {
        guard !dateKey.isEmpty else { return "None" }
        if isSelected(.today, doDateKey: dateKey) { return "Today" }
        if isSelected(.tomorrow, doDateKey: dateKey) { return "Tomorrow" }
        return DateFormatters.shortDateString(from: dateKey)
    }

    /// What the priority tile says. `None` is a value here, not a prompt: the tile is already
    /// captioned "Priority", so the line under it answers — the same wording the task inspector's
    /// priority row uses, rather than the `!!` mark the chip used to show.
    static func priorityValueLabel(_ priority: TaskPriority) -> String {
        priority.label
    }

    /// What the tags tile says: the names while they fit, the count once they do not.
    ///
    /// `limit` is how many names the tile has room to spell before counting is the more useful
    /// answer. It defaults to 1 — one line on a half-width tile — and the sheet's tags tile, which
    /// runs the full width, passes 2. Listing every name is what the chips inside the picker are
    /// for.
    static func tagsValueLabel(names: [String], limit: Int = 1) -> String {
        let usable = names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if usable.isEmpty { return "None" }
        if usable.count <= max(1, limit) { return usable.joined(separator: ", ") }
        return "\(usable.count) tags"
    }

    // MARK: - Container resolution

    /// The lists a container picker may **offer**.
    ///
    /// Both pickers already filter this way — macOS's `ContainerPickerFilterSupport.groups` and
    /// iOS's `iOSContainerChoicePopover` — so the rule is written once here and derived at the
    /// controls rather than handed to them. That matters because "which lists may be offered" and
    /// "which list does this selection name" are different questions, and a composer that takes
    /// two arrays for the first and two more for the second is a composer whose label and whose
    /// save can disagree. See `resolvedContainer(for:areas:projects:)`.
    /// **T-514 added the `selectedID:` half**, and it is the one that matters for a picker rather
    /// than a suggestion strip. "Which lists may be offered" is a rule about *fresh* choices; the
    /// list a task is already in is not a fresh choice, and dropping it is how the container picker
    /// came to be unable to move a task out of an archived list. That is `CadencePickerSupport`'s
    /// `selectable(_:selectedID:)`, written once for `Context` (T-446), `Area` (T-488) and now
    /// `Project` — the grouped three-way control needs it applied to **both** its arrays.
    ///
    /// The no-argument spelling below is the same rule with nothing assigned, kept because a
    /// suggestion strip really is offering fresh choices only.
    static func pickableAreas(_ areas: [Area], selectedID: UUID?) -> [Area] {
        CadenceAreaPickerSupport.sorted(
            CadenceAreaPickerSupport.selectable(areas, selectedID: selectedID)
        )
    }

    static func pickableProjects(_ projects: [Project], selectedID: UUID?) -> [Project] {
        CadenceProjectPickerSupport.sorted(
            CadenceProjectPickerSupport.selectable(projects, selectedID: selectedID)
        )
    }

    /// It forwards rather than restating the rule: written out separately it silently dropped the
    /// sort, so the two overloads of one name returned the same elements in different orders.
    static func pickableAreas(_ areas: [Area]) -> [Area] {
        pickableAreas(areas, selectedID: nil)
    }

    static func pickableProjects(_ projects: [Project]) -> [Project] {
        pickableProjects(projects, selectedID: nil)
    }

    /// The area or project id a selection names, or `nil` for Inbox. What the two `pickable*`
    /// overloads above are handed, so that a control holding one selection does not have to spell
    /// the unwrapping twice.
    static func selectedAreaID(_ selection: TaskContainerSelection) -> UUID? {
        if case .area(let id) = selection { return id }
        return nil
    }

    static func selectedProjectID(_ selection: TaskContainerSelection) -> UUID? {
        if case .project(let id) = selection { return id }
        return nil
    }

    /// The list a selection names, or `nil` when it names none — either because it is Inbox, or
    /// because the list it named is no longer in the store.
    ///
    /// **This is the composer's one source.** The tile that says which list the task is going to,
    /// the sections that tile's neighbour offers, and the `TaskCreationService` the Add button
    /// builds all read the same two arrays through here, so there is no arrangement in which the
    /// sheet can show one destination and save into another (T-318).
    ///
    /// Membership is existence, not activity, which is the rule the app's other write surface
    /// already applies: `CadenceWriteService.resolveContainer` accepts any container it can find
    /// and throws `containerNotFound` only when there is none. A list that has been archived or
    /// completed since the sheet opened is still a real place a seeded task can go; a list that
    /// has been deleted is not.
    static func resolvedContainer(
        for selection: TaskContainerSelection,
        areas: [Area],
        projects: [Project]
    ) -> GoalLinkTarget? {
        switch selection {
        case .inbox:
            return nil
        case .area(let id):
            return areas.first(where: { $0.id == id }).map { GoalLinkTarget.area($0) }
        case .project(let id):
            return projects.first(where: { $0.id == id }).map { GoalLinkTarget.project($0) }
        }
    }

    /// Whether the selection names a list that is not there any more.
    ///
    /// Inbox is never missing: it is the *absence* of a list, so there is nothing to lose.
    static func namesMissingContainer(
        _ selection: TaskContainerSelection,
        areas: [Area],
        projects: [Project]
    ) -> Bool {
        guard selection != .inbox else { return false }
        return resolvedContainer(for: selection, areas: areas, projects: projects) == nil
    }

    /// The selection a composer should be holding, given the lists that exist right now.
    ///
    /// **T-317.** A create sheet keeps its selection in `@State` and re-normalized only when the
    /// *selection* changed, never when the available lists did, so an id for a list deleted in
    /// another window or removed by sync stayed reachable — and `TaskContainerResolver`
    /// `applyContainer` attaches nothing for an id it cannot find while the insert goes ahead
    /// anyway. The task then landed in the Inbox while the sheet still named a list.
    static func normalizedContainer(
        _ selection: TaskContainerSelection,
        areas: [Area],
        projects: [Project]
    ) -> TaskContainerSelection {
        namesMissingContainer(selection, areas: areas, projects: projects) ? .inbox : selection
    }

    /// What the composer's List control says.
    ///
    /// `Inbox` covers both "no list chosen" and "the chosen list is gone", because those are the
    /// same destination — the second only after `normalizedContainer` has made it so. Dimmer
    /// styling is what conveys unset, exactly as the task inspector's breadcrumb does it.
    static func containerName(
        for selection: TaskContainerSelection,
        areas: [Area],
        projects: [Project]
    ) -> String {
        resolvedContainer(for: selection, areas: areas, projects: projects)?.displayName
            ?? CadenceTaskInspectorSupport.inboxSegmentTitle
    }

    /// Said in the composer when the list it was holding has gone.
    ///
    /// The creation is refused rather than quietly downgraded: an Inbox task the user did not ask
    /// for is indistinguishable from one they did, and the sheet still holds everything they typed,
    /// so saying so and letting them press Add again costs one tap and no work.
    static let missingContainerNotice =
        "That list is no longer available. Add again to create this task in the Inbox."

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

/// The create-task sheet's vertical layout, as numbers rather than as literals scattered through the
/// view.
///
/// **This exists because height is the thing that went wrong.** The sheet's previous shape — a
/// do-date button block over five 57pt value rows — needed about 462pt of content against the
/// ~390pt a 390×844pt phone leaves once a software keyboard is up. The Tags row therefore sat below
/// the fold, which is exactly the failure rows had been chosen to prevent: a seeded value you cannot
/// see is no better stated than a seeded chip you cannot tell apart.
///
/// The tile grid is the answer. Six fields that cost six lines as rows cost three as 2-up tiles, and
/// `contentHeight(showsSectionTile:)` is what says so — composed from the same constants the sheet
/// lays itself out with and from `CadenceValueTileMetrics`, so it cannot quietly disagree with what
/// is drawn. `CadenceTaskComposerLayoutTests` holds it against the fold.
///
/// **The two device figures are measured on iPhone 17e, not assumed**, and they correct the estimate
/// this redesign was specified against. That estimate put the usable area at 452pt by taking 508pt
/// of screen above the keyboard and subtracting a navigation bar; it left out the ~50pt a sheet is
/// inset from the top of the screen, and undercounted the bar. The real scroll viewport starts about
/// 118pt down. The 508pt figure itself holds: the keyboard's top edge is there, and the previous
/// shape's Tags row landing ~70pt below it is what an actual keyboard-up screenshot showed.
nonisolated enum CadenceTaskComposerLayout {
    // MARK: - What the sheet draws

    /// `titleField`'s `minHeight`.
    static let titleHeight: CGFloat = 52
    /// `notesField` at rest: one 18pt line inside 14pt of padding. It grows on focus and opens
    /// grown when the seed carried notes, but the resting height is what has to clear the keyboard.
    static let notesRestingHeight: CGFloat = 46
    /// Gap between the sheet's stacked blocks — title, notes, grid.
    static let fieldSpacing: CGFloat = 12
    /// Gap between two tiles, in both axes.
    static let tileSpacing: CGFloat = 10
    static let tileHeight: CGFloat = CadenceValueTileMetrics.minHeight
    static let contentTopPadding: CGFloat = 12
    static let contentBottomPadding: CGFloat = 20

    /// **Do · Due**, then **List · Priority**, then **Section · Tags** — or Tags alone across the
    /// last row when the picked list has no sections to choose between.
    static let gridRowCount = 3

    /// Where the conditional field goes, and why it is the *last* row that flexes.
    ///
    /// The section tile is the one field that comes and goes, so the arrangement is chosen so that
    /// its arrival disturbs as little as possible and — crucially — **costs no height at all**. It
    /// takes the empty half of the last row, which Tags would otherwise have spread across. The two
    /// fixed rows above never move, the sheet is the same height either way, and the fold has one
    /// number to clear rather than two.
    ///
    /// It also lands directly *under* List, in the same column, which is the adjacency that matters:
    /// a section is a property of the list, and a section without its list means nothing.
    static func tileCount(showsSectionTile: Bool) -> Int {
        // Do, Due, List, Priority, Tags — plus Section when the picked list has any.
        showsSectionTile ? 6 : 5
    }

    /// The content height of the sheet's scroll view at rest: title, notes and the three tile rows,
    /// with their spacing and the scroll view's padding.
    ///
    /// "At rest" is the case that matters — the keyboard is up because the title field has focus, so
    /// notes is collapsed and the `~`/`#` suggestion strip is not showing.
    ///
    /// The parameter is deliberately ignored. It is kept because callers and tests want to *ask* the
    /// question, and the answer being "it makes no difference" is the property worth pinning rather
    /// than hiding behind a signature that could not express it.
    static func contentHeight(showsSectionTile: Bool = false) -> CGFloat {
        _ = showsSectionTile
        let grid = CGFloat(gridRowCount) * tileHeight + CGFloat(gridRowCount - 1) * tileSpacing

        return contentTopPadding
            + titleHeight
            + fieldSpacing
            + notesRestingHeight
            + fieldSpacing
            + grid
            + contentBottomPadding
    }

    // MARK: - What the device leaves

    /// Where the software keyboard's top edge sits on a 390×844pt phone: 844 less a ~336pt
    /// keyboard. **Measured** — an iPhone 17e screenshot with the keyboard raised puts it here, and
    /// puts the previous shape's Tags row about 70pt below it, which is what that shape was reported
    /// to do.
    static let keyboardTopFromScreenTop: CGFloat = 508

    /// Where the sheet's scroll viewport starts: the sheet is inset roughly 50pt from the top of the
    /// screen and its inline navigation bar takes another ~68. This is the term the original 452pt
    /// estimate left out.
    static let scrollViewportTop: CGFloat = 118

    /// The space the scroll view actually gets with the keyboard up.
    static let keyboardVisibleContentHeight: CGFloat = keyboardTopFromScreenTop - scrollViewportTop

    /// The previous shape's content height, measured off the same screenshot: a do-date button block
    /// over five value rows. Kept as a number rather than a memory so the improvement stays checkable.
    static let supersededRowLayoutHeight: CGFloat = 462

    /// How much of the visible area is still empty below the last tile. Negative means a field is
    /// under the fold, which is the condition this whole shape exists to avoid.
    static func slackBelowFold(showsSectionTile: Bool = false) -> CGFloat {
        keyboardVisibleContentHeight - contentHeight(showsSectionTile: showsSectionTile)
    }
}
