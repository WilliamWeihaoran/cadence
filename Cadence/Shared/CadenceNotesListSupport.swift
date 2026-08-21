import SwiftUI

// The grouped note list — the column of month headings with dated rows under them — is one
// surface drawn on two platforms. It was macOS-only, in `macOS/Views/NotesListRows.swift` and
// `macOS/Views/NotesListVisibilitySupport.swift`, both wrapped in `#if os(macOS)`; iOS rendered
// flat lists, or in three of the four kinds no list at all. Everything those two files held has
// moved here whole — the grouping, the visibility rules, the row, the header and the column — and
// the two macOS files are gone.
//
// What is new is the fold, which neither platform had.
//
// Nothing in this file is behind a platform guard. That is deliberate twice over: it is what lets
// both surfaces call one implementation, and it is what lets the macOS-built `CadenceTests` target
// pin the figures and the fold arithmetic. `Cadence/iOS/` is entirely inside `#if os(iOS)` and is
// invisible to that target, so any value type an iOS view needs asserted has to live out here.

// MARK: - Layout

/// One column or two — which form the iOS Notes surface renders, and the only thing that separates
/// iPhone from iPad there.
///
/// **The size class is not enough to decide it.** A host can be horizontally regular and still be
/// narrower than a 280pt list column plus a readable editor: the iPad Today inspector is exactly
/// that, and it rendered a ~40pt editor for as long as this branched on the size class alone. See
/// `CadenceNotesListMetrics.twoColumnMinimumWidth`.
nonisolated enum CadenceNotesLayout: Equatable, Sendable {
    /// The list is the whole surface and the editor is presented over it. The phone's form, and the
    /// form any regular-width host too narrow to split falls back to — it is reused, not rebuilt.
    case oneColumn
    /// List beside editor.
    case twoColumn
}

// MARK: - Metrics

/// Every figure the grouped note list draws itself with, in one value, for one surface.
///
/// Split from the row and header views for the same reason `CadencePageHeaderMetrics` is: a
/// measurement stated inside a `#if os(iOS)` view cannot be tested, and two platforms drawing the
/// same control from two literal sets is how they drift.
///
/// **The tiers are not cosmetic.** `.desktop` is a third tier rather than an alias for `.regular`,
/// exactly as `CadencePageHeaderSurface` already establishes: a macOS row is a 24pt-tall index
/// entry driven by a pointer, and a touch row has a 44pt floor and sets its type three points
/// larger. "The exact same sidebar" means the same structure, vocabulary and behaviour — one day
/// number in a fixed leading slot, one title, one optional detail line, one fill at one radius,
/// month headings that fold — not the same point values. Every figure that could be shared is
/// shared; the ones that could not are called out at their declarations.
nonisolated struct CadenceNotesListMetrics: Equatable, Sendable {
    // MARK: Row

    /// Fixed leading slot for the day number so one- and two-digit days line up as a single column
    /// instead of ragging against the text beside them.
    let dayNumberWidth: CGFloat
    /// Gap between the day-number slot and the title. **Shared at 14 on every tier.** At the 9pt
    /// macOS started from, the number and the first word read as one run of text; 14 is a clear
    /// word-space gap at both 12pt and 15pt type, so there was no reason for the phone to differ.
    let dayNumberSpacing: CGFloat
    let rowHorizontalPadding: CGFloat
    let rowVerticalPadding: CGFloat
    /// **Not shared, and the clearest example of why.** 0 on `.desktop`, where the row is as tall
    /// as its text and a pointer can hit a 24pt target; 44 on both touch tiers, which is the floor
    /// every other tappable row in this app already sets.
    let rowMinHeight: CGFloat
    let dayNumberSize: CGFloat
    let titleSize: CGFloat
    let detailSize: CGFloat

    // MARK: Month header

    /// **Not shared.** macOS's month heading is 11pt bold against 12pt rows; the touch tiers set
    /// 12 against 15pt rows. Both are one point over the day number beside them, which is the
    /// relationship that actually carries — a heading that out-reads its own rows.
    let headerLabelSize: CGFloat
    /// **Not shared**, for the same reason as `rowMinHeight`: the heading is a fold control now, so
    /// on touch it takes the 44pt floor. macOS leaves it intrinsic.
    let headerMinHeight: CGFloat
    let headerChevronSize: CGFloat

    // MARK: Column

    let groupSpacing: CGFloat
    let rowSpacing: CGFloat
    let columnHorizontalPadding: CGFloat
    let columnVerticalPadding: CGFloat

    /// Matches `rowHorizontalPadding` so the heading's left edge and the day-number column's left
    /// edge sit on the same line.
    var headerHorizontalPadding: CGFloat { rowHorizontalPadding }

    /// The chevron's slot and the gap after it add up to `headerHorizontalPadding`, so the heading
    /// row can lead with the chevron at padding zero and still put the *title* exactly where it sat
    /// before there was a chevron. The reference screenshot the user gave is of the unfolded
    /// column; adding a control to it must not move the text.
    static let headerChevronSlot: CGFloat = 8
    static let headerChevronSpacing: CGFloat = 2

    var headerLeadingPadding: CGFloat {
        max(0, headerHorizontalPadding - Self.headerChevronSlot - Self.headerChevronSpacing)
    }

    // MARK: Column width
    //
    // `HSplitView` only honours `idealWidth` when the pane is also bounded: given `minWidth` and
    // `idealWidth` alone it treats the pane as infinitely growable and splits the window down the
    // middle, which is how a column of day numbers ended up ~800pt wide in a maximized window and
    // wider than the editor beside it. `maxWidth` is what actually pins it. The divider is still
    // draggable — between `columnMinWidth` and `columnMaxWidth`.
    //
    // At the 224pt ideal a row spends 20pt on the day-number slot, 14pt of spacing, 2×10pt of row
    // padding and 2×8pt of column padding — 70pt of chrome — leaving ~154pt for the preview. At
    // 12pt system that is roughly 25 characters: "Shipped the invoice rec…", which is the first
    // phrase of the first line and enough to tell two notes apart. The 300pt maximum still reaches
    // ~37 characters for anyone who drags the divider out; the 180pt minimum keeps ~18, which is
    // short but still more than the day number it sits beside.

    static let columnMinWidth: CGFloat = 180
    static let columnIdealWidth: CGFloat = 224
    static let columnMaxWidth: CGFloat = 300

    /// The iPad sidebar's width. **Not shared with macOS's ideal**, and not draggable: iPad has no
    /// `HSplitView`, the rows set 15pt type rather than 12, and this column sits *inside* the root
    /// sidebar's split rather than beside a window edge. 280 gives the same ~25-character preview
    /// at the larger type that 224 gives macOS at 12pt.
    static let regularColumnWidth: CGFloat = 280

    // MARK: Two columns or one
    //
    // The split branched on the horizontal size class **alone**, with no width input and no floor,
    // so every regular-width host got two columns however little room it had — and the list took
    // `regularColumnWidth` off the top of it as a fixed frame. Today's inspector is 320pt wide at
    // its own floor (`CadenceTodayLayoutSupport.inspectorPaneMinWidth`), which left the editor
    // **320 − 280 − 1 = 39pt**: a markdown body wrapping one character per line.
    //
    // **This is a registered home of that rule, and the tension the last pass flagged is settled.**
    // `CadenceRegularPaneLayout.swift` is the house file, and it holds three expressions of the same
    // arithmetic (`CadenceRegularSplitLayout`, `CadenceCalendarWeekGridLayout`,
    // `CadenceCalendarPaneLayout.showsInspector`) while `CadenceTodayLayoutSupport` and
    // `CadenceRootShellLayout` hold one each — six in four files, not the four T-182 counted. The
    // call was to leave them in their surfaces and put the *register* in the house file rather than
    // to move the sums, because a floor is only a sum of its parts while the parts are next to it:
    // this one is derived from `regularColumnWidth`, two declarations above, and hoisting the sum
    // without the column would split "raise the column" from "the floor follows it".
    //
    // So a new split surface still does not get to write a seventh copy. It joins one of those four
    // files and gets listed in the register, and
    // `CadenceTests/CadencePaneWidthRuleHomesTests.swift` fails until it is.

    /// The 1pt `Divider()` between the two columns. Counted, because a floor that forgets it is a
    /// floor that is one point wrong — the mistake `CadenceTodayLayoutSupport.taskPaneWidth`
    /// records at length.
    static let columnDividerWidth: CGFloat = 1

    /// The least the editor half may be handed before two columns is worse than one.
    ///
    /// **Not picked, and not local.** It is `CadenceTodayLayoutSupport.inspectorPaneMinWidth` — the
    /// figure that file already states as "the least the notes/timeline inspector will accept before
    /// its own content starts clipping". That sentence is about *this* content, and spending it on
    /// the editor half alone is deliberately the stronger requirement: the editor must clear on its
    /// own what the whole pane's stated floor is. Spelled as a reference rather than a literal so
    /// the two cannot drift.
    ///
    /// The corroborating anchor is the phone, and it is the reason this is not larger. The
    /// one-column fallback *is* the phone's form, so "at least as wide as the editor already runs at
    /// as a whole screen" is the other defensible reading — 375pt, the narrowest screen the app
    /// ships on (iPhone SE 3rd gen / 13 mini; a 26.2 deployment target drops everything narrower),
    /// which would put the floor at 656. That is 10pt over an 11" iPad's portrait Notes pane
    /// (834 − 188 = 646), where the editor would have had 365 — tight, not broken. A floor's job is
    /// to name the width below which two columns is *worse* than one, not the width above which it
    /// is ideal, so the lower anchor wins and the only hosts whose layout changes are the ones that
    /// were unreadable.
    static var minimumEditorWidth: CGFloat { CadenceTodayLayoutSupport.inspectorPaneMinWidth }

    /// 601pt of host. **A sum, not a constant** — raise `regularColumnWidth` and this moves with it,
    /// which is the entire reason it is spelled this way rather than typed. Same construction, and
    /// the same history, as `CadenceTodayLayoutSupport.twoPaneMinimumWidth`: two panes with no floor
    /// at all until one host proved they needed one.
    static var twoColumnMinimumWidth: CGFloat {
        regularColumnWidth + columnDividerWidth + minimumEditorWidth
    }

    static func supportsTwoColumns(hostWidth: CGFloat) -> Bool {
        hostWidth >= twoColumnMinimumWidth
    }

    /// The form the iOS Notes surface renders, given the width its host actually handed it.
    ///
    /// **`hostWidth <= 0` means "not measured yet" and answers with the size class alone.** The
    /// width arrives from `onGeometryChange`, which lands after the first layout pass, so a regular
    /// host reads 0 for one frame; resolving that to `.oneColumn` would flash the phone's form on
    /// every appearance of the iPad Notes tab. This is the opposite call from
    /// `CadenceCalendarPaneLayout`'s, and for the same reason it gives: there, the pane opening
    /// full-width and *gaining* an inspector reads as the inspector arriving. Here the two-column
    /// form is the one the host almost always resolves to, so assuming it is what avoids the flash.
    static func layout(isRegularWidth: Bool, hostWidth: CGFloat) -> CadenceNotesLayout {
        guard isRegularWidth else { return .oneColumn }
        guard hostWidth > 0 else { return .twoColumn }
        return supportsTwoColumns(hostWidth: hostWidth) ? .twoColumn : .oneColumn
    }

    static func metrics(for surface: CadencePageHeaderSurface) -> CadenceNotesListMetrics {
        switch surface {
        case .desktop:
            return CadenceNotesListMetrics(
                dayNumberWidth: 20,
                dayNumberSpacing: 14,
                rowHorizontalPadding: 10,
                rowVerticalPadding: 6,
                rowMinHeight: 0,
                dayNumberSize: 12,
                titleSize: 12,
                detailSize: 11,
                headerLabelSize: 11,
                headerMinHeight: 0,
                headerChevronSize: 8,
                groupSpacing: 10,
                rowSpacing: 3,
                columnHorizontalPadding: 8,
                columnVerticalPadding: 10
            )
        case .compact, .regular:
            // One set for both touch tiers, not two. iPhone and iPad differ in *layout* — the
            // column is the whole pane on the phone and one of two panes on iPad — and must not
            // differ in how a row looks. This is the same rule `CadencePageHeaderMetrics` breaks
            // only for title volume, and a list row has no equivalent of that.
            return CadenceNotesListMetrics(
                dayNumberWidth: 22,
                dayNumberSpacing: 14,
                rowHorizontalPadding: 10,
                rowVerticalPadding: 9,
                rowMinHeight: 44,
                dayNumberSize: 13,
                titleSize: 15,
                detailSize: 12,
                headerLabelSize: 12,
                headerMinHeight: 44,
                headerChevronSize: 9,
                groupSpacing: 8,
                rowSpacing: 2,
                columnHorizontalPadding: 10,
                columnVerticalPadding: 10
            )
        }
    }

    static let desktop = metrics(for: .desktop)

    /// iOS's spelling: the size class, as the boolean every iOS view already has to hand.
    static func metrics(isRegularWidth: Bool) -> CadenceNotesListMetrics {
        metrics(for: isRegularWidth ? .regular : .compact)
    }
}

// MARK: - Month grouping

struct NoteMonthGroup: Identifiable {
    /// `yyyy-MM`
    let id: String
    let title: String
    let notes: [Note]
}

/// One month heading and whatever is under it *after* the fold is applied.
///
/// `notes` is empty when `isCollapsed`, and `noteCount` is what the group holds either way — so a
/// collapsed heading can say how much it is hiding without the column having to keep a second copy
/// of the grouping around to ask.
struct CadenceNotesListSection: Identifiable {
    /// `yyyy-MM`
    let id: String
    let title: String
    let noteCount: Int
    let isCollapsed: Bool
    let notes: [Note]
}

enum NotesListGrouping {
    /// Groups an already-sorted note list into consecutive month runs, preserving the incoming
    /// order both between and inside groups.
    ///
    /// `dateKey` returns the `yyyy-MM-dd` key the note should file under; notes whose key does not
    /// parse fall back to their `updatedAt` day so nothing silently disappears from the list.
    ///
    /// **`dateKey` stays `@MainActor`, and could not be `nonisolated`.** The closure reads stored
    /// properties of `Note`, which is a `@Model` compiled under the app target's
    /// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; a nonisolated closure could not touch them, so
    /// dropping the annotation would only move the isolation error to each of the five call sites.
    /// The annotation is not what would make this testable off the main actor either — the `[Note]`
    /// parameter already pins the whole function there. The genuinely nonisolated half of this file
    /// is `CadenceNotesListMetrics` and `CadenceNotesFoldState`, which is where the arithmetic worth
    /// testing without a `ModelContext` lives.
    static func monthGroups(for notes: [Note], dateKey: @MainActor (Note) -> String) -> [NoteMonthGroup] {
        var groups: [NoteMonthGroup] = []
        var currentID: String?
        var currentNotes: [Note] = []

        func flush() {
            guard let currentID, !currentNotes.isEmpty else { return }
            groups.append(NoteMonthGroup(id: currentID, title: monthTitle(forMonthKey: currentID), notes: currentNotes))
        }

        for note in notes {
            let key = resolvedKey(dateKey(note), fallback: note.updatedAt)
            let monthKey = String(key.prefix(7))
            if monthKey != currentID {
                flush()
                currentID = monthKey
                currentNotes = []
            }
            currentNotes.append(note)
        }
        flush()
        return groups
    }

    /// **The one entry point both platforms call.** Groups, then applies the fold.
    ///
    /// A month with nothing in it never becomes a section — `monthGroups` cannot emit an empty
    /// group, and this cannot invent one. That is the defect the calendar agenda shipped: a heading
    /// standing over nothing, which reads as a loading failure rather than as an empty month.
    /// A *collapsed* section is not that: it carries `noteCount > 0` and says so.
    static func sections(
        for notes: [Note],
        kind: NoteKind,
        foldState: CadenceNotesFoldState,
        dateKey: @MainActor (Note) -> String
    ) -> [CadenceNotesListSection] {
        monthGroups(for: notes, dateKey: dateKey).map { group in
            let collapsed = foldState.isCollapsed(month: group.id, kind: kind)
            return CadenceNotesListSection(
                id: group.id,
                title: group.title,
                noteCount: group.notes.count,
                isCollapsed: collapsed,
                notes: collapsed ? [] : group.notes
            )
        }
    }

    private static func resolvedKey(_ key: String, fallback: Date) -> String {
        DateFormatters.date(from: key) == nil ? DateFormatters.dateKey(from: fallback) : key
    }

    /// `2026-08` -> `AUGUST 2026`. The year is always shown: a note list scrolls back years, and a
    /// bare month name is only unambiguous for the twelve months you happen to be looking at.
    static func monthTitle(forMonthKey monthKey: String) -> String {
        guard let date = DateFormatters.date(from: "\(monthKey)-01") else { return monthKey.uppercased() }
        return DateFormatters.monthYear.string(from: date).uppercased()
    }

    /// `2026-W33` -> the `yyyy-MM-dd` key of that ISO week's Monday.
    ///
    /// Forwards to `DateFormatters.weekStartDate(forWeekKey:calendar:)`, which owns the ISO
    /// Monday-week construction this used to spell out for itself.
    static func weekStartDateKey(forWeekKey weekKey: String) -> String {
        guard let monday = DateFormatters.weekStartDate(forWeekKey: weekKey) else { return weekKey }
        return DateFormatters.dateKey(from: monday)
    }
}

// MARK: - Fold state

/// Which month headings are folded shut, per note kind.
///
/// **Per kind, and persisted.** Both halves are choices:
///
/// - *Per kind*, because the four tabs are not four views of one list. Daily is a row per day and
///   scrolls back years, so folding 2025 shut is how you get to the top of 2026; Notepad is
///   grouped by creation month only because a notepad note has no date of its own, and someone who
///   folds a Daily year has said nothing about what they want Notepad to look like. A global set of
///   collapsed month keys would also collide across kinds — `2026-08` means a different group in
///   each — so one user action would fold four lists.
/// - *Persisted*, because folding a decade of Daily notes shut is a filing decision, not a scroll
///   position, and re-doing it every launch is the whole cost of the feature. `selectedDayKey` on
///   the mobile Notes header is deliberately **not** persisted for the opposite reason: a stored
///   day reopens you on a week-old page and you write today's entry into it. A collapsed month
///   cannot mislead like that — the rows are one tap away and the chevron says which way it points.
///
/// Stored as one JSON blob under a single key, the way `NoteTemplateLibrary` stores template
/// overrides, so there is one `@AppStorage` on each surface rather than one per kind.
///
/// **On the write-only-key hazard.** `CadenceNotesEditorPreferences.purgeRetiredKeys()` is this
/// repo's handling for a `UserDefaults` key the app keeps writing after every reader is gone. That
/// is not this key's shape — both platforms read it on every Notes render, and the call-site tests
/// in `CadenceNotesListSupportTests` fail if either stops. What *could* rot is an entry for a note
/// kind that no longer exists, so `decoded(_:)` drops any key that is not a live `NoteKind` and the
/// next write persists the pruned form. Month keys are deliberately *not* pruned: a month with no
/// rows today can gain one tomorrow, and forgetting the fold when its last note is filtered out
/// would make the state flicker.
nonisolated struct CadenceNotesFoldState: Equatable, Sendable {
    /// `@AppStorage` key. One blob, both platforms, all four kinds.
    static let storageKey = "notes.collapsedMonths"

    /// `NoteKind.rawValue` -> the `yyyy-MM` keys folded shut in that kind's list.
    private var collapsed: [String: Set<String>]

    init() {
        collapsed = [:]
    }

    init(collapsed: [NoteKind: Set<String>]) {
        self.collapsed = collapsed.reduce(into: [:]) { result, entry in
            guard !entry.value.isEmpty else { return }
            result[entry.key.rawValue] = entry.value
        }
    }

    // MARK: Reading

    func isCollapsed(month monthID: String, kind: NoteKind) -> Bool {
        collapsed[kind.rawValue]?.contains(monthID) ?? false
    }

    func collapsedMonths(kind: NoteKind) -> Set<String> {
        collapsed[kind.rawValue] ?? []
    }

    /// True when every section on screen is folded shut — what the "expand all" affordance keys
    /// off. An empty list answers `false`: there is nothing folded, so there is nothing to unfold,
    /// and answering `true` would light up a control that does nothing.
    func isEverythingCollapsed(in sections: [CadenceNotesListSection]) -> Bool {
        !sections.isEmpty && sections.allSatisfy(\.isCollapsed)
    }

    // MARK: Writing

    mutating func setCollapsed(_ isCollapsed: Bool, month monthID: String, kind: NoteKind) {
        var months = collapsed[kind.rawValue] ?? []
        if isCollapsed {
            months.insert(monthID)
        } else {
            months.remove(monthID)
        }
        // An empty set is dropped rather than stored, so expanding everything leaves the same blob
        // a fresh install has instead of `{"daily":[]}` that reads as state.
        collapsed[kind.rawValue] = months.isEmpty ? nil : months
    }

    mutating func toggle(month monthID: String, kind: NoteKind) {
        setCollapsed(!isCollapsed(month: monthID, kind: kind), month: monthID, kind: kind)
    }

    /// Folds every section currently on screen. Takes the sections rather than "all months" because
    /// only what is listed can be folded — a month whose one note is filtered out has no heading to
    /// fold, and inventing an entry for it would be state about a group the user has never seen.
    mutating func collapseAll(_ sections: [CadenceNotesListSection], kind: NoteKind) {
        for section in sections {
            setCollapsed(true, month: section.id, kind: kind)
        }
    }

    /// Unfolds everything in one kind — including months no longer listed, which is the point: this
    /// is the escape hatch, so it must not leave a fold behind that nothing on screen can undo.
    mutating func expandAll(kind: NoteKind) {
        collapsed[kind.rawValue] = nil
    }

    // MARK: Storage

    /// Tolerant by construction: anything unreadable decodes to "nothing is folded", which is the
    /// state a fresh install is in and the only failure mode that cannot hide a note.
    static func decoded(_ raw: String) -> CadenceNotesFoldState {
        guard !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let stored = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            return CadenceNotesFoldState()
        }

        var state = CadenceNotesFoldState()
        for (kindRaw, months) in stored {
            // Drops entries for a kind that is no longer a `NoteKind` case, so retiring a tab
            // cannot leave an unreachable fold behind.
            guard NoteKind(rawValue: kindRaw) != nil, !months.isEmpty else { continue }
            state.collapsed[kindRaw] = Set(months)
        }
        return state
    }

    /// Sorted on the way out so the stored blob is stable: `Set` and `Dictionary` iteration order
    /// are not, and an unstable encoding rewrites `UserDefaults` — and on iOS, wakes every
    /// `@AppStorage` observer — on every render that touches this.
    func encoded() -> String {
        guard !collapsed.isEmpty else { return "" }
        let stored = collapsed.reduce(into: [String: [String]]()) { result, entry in
            result[entry.key] = entry.value.sorted()
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(stored), let raw = String(data: data, encoding: .utf8) else {
            return ""
        }
        return raw
    }
}

// MARK: - Which notes earn a row

/// Which notes earn a row in a Notes list column.
///
/// Daily and weekly notes are created for you — opening the tab on a day you never wrote on still
/// makes a row — so an unfiltered column is mostly a list of days that say nothing, and the handful
/// you actually wrote on are buried in it. The list is an index of days *with content*; the current
/// day/week is pinned so there is always a way in to writing today.
///
/// Everything here is a pure function of a note's stored text. Nothing is cached: the column is
/// recomputed from the live `@Query`, so a note appears the moment it gains a character and drops
/// out the moment the last one is deleted.
enum NotesListVisibility {
    /// Does this note hold anything the user put there?
    ///
    /// Measured the same way `NoteEditorPane.isNoteBlank` gates its template chips — against the
    /// **body**, after `MarkdownMetadataParser.splitFrontmatter` — because a plain
    /// `content.isEmpty` test misses the auto-seeded `# Title` body and calls a note that says
    /// nothing "written".
    ///
    /// The one place this parts company with the template-chip rule: a **frontmatter block counts
    /// as content**. Frontmatter is rendered at zero height, so a note that has only been *tagged*
    /// looks blank in the editor but carries `---\ntags: [...]\n---`. Blank-bodied is exactly the
    /// state the template chips exist for, so the editor is right to offer them; the list is not,
    /// because dropping the row is the only handle on those tags and would strand them.
    static func hasContent(_ note: Note) -> Bool {
        hasContent(rawContent: note.content, displayTitle: note.displayTitle)
    }

    static func hasContent(rawContent: String, displayTitle: String) -> Bool {
        let split = MarkdownMetadataParser.splitFrontmatter(in: rawContent)
        if !split.frontmatter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return !isBlankBody(split.body, displayTitle: displayTitle)
    }

    /// A body with nothing in it but whitespace, or nothing but the heading the note was seeded
    /// with. Shared with the "looks empty" row styling so the list cannot dim a row it also lists
    /// as written.
    static func isBlankBody(_ body: String, displayTitle: String) -> Bool {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "# \(displayTitle)"
    }

    /// The body a row should preview: frontmatter stripped, so a tagged-but-unwritten note reads as
    /// empty rather than previewing its own `---` fence.
    static func previewBody(_ note: Note) -> String {
        MarkdownMetadataParser.splitFrontmatter(in: note.content).body
    }

    /// Filters an already-sorted list, keeping anything `isPinned` claims regardless of content.
    static func listed(_ notes: [Note], pinning isPinned: (Note) -> Bool) -> [Note] {
        notes.filter { isPinned($0) || hasContent($0) }
    }

    /// Daily tab: today is always listed, even blank — it is the way in to writing today's note.
    static func dailyNotes(_ notes: [Note], todayKey: String) -> [Note] {
        listed(notes) { $0.dateKey == todayKey }
    }

    /// Weekly tab: same rule one period up, pinning the current week.
    static func weeklyNotes(_ notes: [Note], currentWeekKey: String) -> [Note] {
        listed(notes) { $0.weekKey == currentWeekKey }
    }

    /// Notepad tab: **everything**, blank or not.
    ///
    /// The hide-empty rule exists because daily and weekly notes are created *for* you — opening
    /// the tab on a day you never wrote on makes a row — so an unfiltered column is mostly days
    /// that say nothing. A notepad note is the opposite: it only exists because you pressed "New
    /// Note", there is no period that manufactures one, and there is no "today" to pin. Filtering
    /// blanks here would make a note vanish the instant you created it, before you could type in
    /// it, and would leave no row to select or delete it from.
    ///
    /// Sorted newest-created first. `updatedAt` was the obvious alternative and is wrong: the
    /// editor commits content about a second after you stop typing, so an edit-ordered column
    /// would yank the row you are writing in to the top — across a month header — mid-sentence.
    /// `createdAt` never changes, so the column holds still, and it is the only date a note with
    /// no subject date actually has. `order` exists but nothing sets it for this kind and there is
    /// no drag-to-reorder here, so it would only ever be creation order spelled less honestly.
    static func notepadNotes(_ notes: [Note]) -> [Note] {
        notes
            .filter { $0.kind == .permanent }
            .sorted {
                $0.createdAt == $1.createdAt
                    ? $0.id.uuidString > $1.id.uuidString
                    : $0.createdAt > $1.createdAt
            }
    }

    /// Event Notes tab: **everything**, in event-day order.
    ///
    /// Deliberately unfiltered. The hide-empty rule exists because daily/weekly notes are created
    /// *for* you, one per period, so most rows say nothing. An event note only exists because you
    /// made one from a calendar event, there is one per event rather than one per day, and its row
    /// carries the event's own title — so it never renders as "Empty" and filtering would only hide
    /// notes you deliberately created.
    ///
    /// Sorted by the meeting's own day, not by last edit: the list is grouped under month headings,
    /// and an edit-ordered list would jump between months row to row.
    static func meetingNotes(_ notes: [Note]) -> [Note] {
        notes
            .filter { $0.kind == .meeting }
            .sorted {
                let left = meetingDayKey(for: $0)
                let right = meetingDayKey(for: $1)
                return left == right ? $0.updatedAt > $1.updatedAt : left > right
            }
    }

    /// The day an event note files under: the event's own, falling back to the last edit so a note
    /// with no metadata still lands in a month rather than dropping out of the column.
    static func meetingDayKey(for note: Note) -> String {
        note.eventDateKey.isEmpty ? DateFormatters.dateKey(from: note.updatedAt) : note.eventDateKey
    }
}

// MARK: - Month header

/// One month heading in a grouped note list, and the control that folds it.
///
/// Uppercase and kerned, like the sidebar's context headings. It has climbed twice. `Theme.dim` at
/// 10pt lands 3.84:1 on `Theme.surface` — below the 4.5:1 floor for small text, and *dimmer* than
/// the rows it heads, so the heading was the quietest thing in its own group. `Theme.muted` at 11pt
/// bold reached 7.24:1, but the rows beside it are also `Theme.muted`: identical colour, so the
/// heading out-read a row by weight alone and still lost. `Theme.text` is 15.86:1 on
/// `Theme.surface` and 2.19:1 against the `Theme.muted` day numbers and titles beside it — a
/// heading that plainly out-reads its own rows, which is the whole job.
///
/// **One fill at one radius.** The heading had no background at all before it became a button; it
/// has exactly one now, at `Theme.radiusControl` — the same radius the rows under it use, so a
/// hovered heading and a hovered row are the same shape. Do not add a second `.background()` or a
/// `cadenceHoverHighlight` on top of it.
struct NotesMonthHeader: View {
    let title: String
    /// How many rows the group holds. Shown **only when the group is folded**, because that is the
    /// only state where the column cannot answer it by looking. The unfolded heading is exactly the
    /// text it has always been.
    let noteCount: Int
    let isCollapsed: Bool
    var metrics: CadenceNotesListMetrics = .desktop
    let toggle: () -> Void

    @State private var isHovered = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
    }

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: CadenceNotesListMetrics.headerChevronSpacing) {
                Image(systemName: "chevron.down")
                    .font(.system(size: metrics.headerChevronSize, weight: .bold))
                    .foregroundStyle(Theme.dim)
                    .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                    .frame(width: CadenceNotesListMetrics.headerChevronSlot)

                Text(title)
                    .font(.system(size: metrics.headerLabelSize, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .kerning(0.8)
                    .lineLimit(1)

                if isCollapsed {
                    Text("\(noteCount)")
                        .font(.system(size: metrics.headerLabelSize - 1, weight: .medium).monospacedDigit())
                        .foregroundStyle(Theme.dim)
                }

                Spacer(minLength: 0)
            }
            .padding(.leading, metrics.headerLeadingPadding)
            .padding(.trailing, metrics.headerHorizontalPadding)
            .frame(maxWidth: .infinity, minHeight: metrics.headerMinHeight, alignment: .leading)
            .background(shape.fill(isHovered ? Theme.surfaceHover : Color.clear))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.16), value: isCollapsed)
        .accessibilityLabel(title)
        .accessibilityValue(isCollapsed ? "Collapsed, \(noteCount) notes" : "Expanded")
        .accessibilityHint(isCollapsed ? "Double tap to expand" : "Double tap to collapse")
    }
}

// MARK: - Column

/// The scrolling note-list column of a Notes tab: month headings with their rows underneath.
///
/// **The one column view, both platforms.** macOS puts it in an `HSplitView` beside the editor;
/// iOS puts it in a pane on iPad and fills the screen with it on iPhone. That is a difference in
/// what the column is placed *in*, which is the only axis iPhone, iPad and macOS are allowed to
/// differ on here.
struct NotesGroupedListColumn<Row: View>: View {
    let sections: [CadenceNotesListSection]
    var metrics: CadenceNotesListMetrics = .desktop
    let toggle: (String) -> Void
    @ViewBuilder let row: (Note) -> Row

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: metrics.groupSpacing) {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: metrics.rowSpacing) {
                        NotesMonthHeader(
                            title: section.title,
                            noteCount: section.noteCount,
                            isCollapsed: section.isCollapsed,
                            metrics: metrics,
                            toggle: { toggle(section.id) }
                        )
                        ForEach(section.notes) { note in
                            row(note)
                        }
                    }
                }
            }
            .padding(.horizontal, metrics.columnHorizontalPadding)
            .padding(.vertical, metrics.columnVerticalPadding)
        }
    }
}

/// The grouped note column **plus** the persisted fold state that drives it.
///
/// This is what every Notes surface on both platforms actually places: four macOS pages and the one
/// iOS list. Keeping the `@AppStorage` here rather than at each call site is the difference between
/// one place that knows how the fold is stored and five — and it means `NotesListGrouping.sections`
/// has exactly one caller in the app, so the grouping cannot be half-adopted.
///
/// `kind` is both what the rows are and what the fold is filed under, so the two can never
/// disagree about which list a collapsed month belongs to.
struct NotesFoldableListColumn<Row: View>: View {
    let notes: [Note]
    let kind: NoteKind
    var metrics: CadenceNotesListMetrics = .desktop
    /// The `yyyy-MM-dd` key each note files under. See `NotesListGrouping.monthGroups`.
    let dateKey: @MainActor (Note) -> String
    @ViewBuilder let row: (Note) -> Row

    @AppStorage(CadenceNotesFoldState.storageKey) private var foldStateRaw = ""

    private var foldState: CadenceNotesFoldState {
        CadenceNotesFoldState.decoded(foldStateRaw)
    }

    var body: some View {
        NotesGroupedListColumn(
            sections: NotesListGrouping.sections(
                for: notes,
                kind: kind,
                foldState: foldState,
                dateKey: dateKey
            ),
            metrics: metrics,
            toggle: toggle,
            row: row
        )
    }

    private func toggle(_ monthID: String) {
        var state = foldState
        state.toggle(month: monthID, kind: kind)
        let encoded = state.encoded()
        // Only write when it actually changed. `@AppStorage` republishes on every assignment, and
        // this view is rebuilt by the same `@Query` that feeds it.
        guard encoded != foldStateRaw else { return }
        foldStateRaw = encoded
    }
}

// MARK: - Row

/// One row in a grouped note list.
///
/// Selection and hover are a single fill at a single radius. Do not add a second `.background`
/// or a `cadenceHoverHighlight` on top of this — that stacked-highlight-at-mismatched-radii bug
/// is exactly what this row was rewritten to remove.
struct NoteListDayRow: View {
    let dayLabel: String
    let title: String
    var detail: String?
    var isEmphasized: Bool = false
    var isEmptyNote: Bool = false
    let isSelected: Bool
    var tags: [Tag] = []
    var metrics: CadenceNotesListMetrics = .desktop

    @State private var isHovered = false

    /// One fill, one radius, three states.
    ///
    /// Selection used to be `Theme.surfaceElevated`, which is 1.07:1 against the `Theme.surface`
    /// the column is drawn on — a 4-value step you cannot see without a colour picker, and only
    /// 1.03:1 away from the hover fill, so the open note was indistinguishable from whatever the
    /// pointer happened to be over. `Theme.blue.opacity(0.16)` composites to 1.26:1 on
    /// `Theme.surface`: still quiet, but *hued*, so it separates from every grey in the column at a
    /// glance rather than by brightness. It is the same fill the markdown slash-command and
    /// reference pickers already use for their highlighted row, so selection reads the same way
    /// everywhere. Blue is spent here because a selected row is exactly what blue is reserved for.
    private var fill: Color {
        if isSelected { return Theme.blue.opacity(0.16) }
        return isHovered ? Theme.surfaceHover : .clear
    }

    /// Empty notes recede — number and label both — so the rows that actually say something are
    /// what the eye lands on. The selected row climbs to `Theme.text` for the same reason the fill
    /// changed: the fill alone is a hint, and the title going from 7.24:1 to 12.56:1 on the tinted
    /// plate is what actually reads as "this is the one that is open".
    private var foreground: Color {
        if isSelected || isEmphasized { return Theme.text }
        return isEmptyNote ? Theme.dim : Theme.muted
    }

    private var titleWeight: Font.Weight {
        if isSelected { return .semibold }
        return isEmphasized ? .semibold : .regular
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: metrics.dayNumberSpacing) {
            Text(dayLabel)
                .font(.system(size: metrics.dayNumberSize, weight: isEmphasized ? .bold : .medium).monospacedDigit())
                .foregroundStyle(foreground)
                .frame(width: metrics.dayNumberWidth, alignment: .trailing)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: metrics.titleSize, weight: titleWeight))
                    .foregroundStyle(foreground)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: metrics.detailSize))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                // `limit: 3`, which is what `NoteRowTagStrip` defaulted to; `CompactTagStrip`
                // defaults to 2 for the macOS rows that were its only callers.
                CompactTagStrip(tags: tags, limit: 3)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, metrics.rowHorizontalPadding)
        .padding(.vertical, metrics.rowVerticalPadding)
        .frame(maxWidth: .infinity, minHeight: metrics.rowMinHeight, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                .fill(fill)
        )
        .contentShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

// The note row's tag strip was `NoteRowTagStrip`, declared here as an acknowledged line-for-line
// copy of `CompactTagStrip` — with a comment asking for exactly the move T-173 made, since that
// type was inside `#if os(macOS)` and this file is shared. It is gone; the row calls
// `CompactTagStrip` in `Shared/Components/CadenceTagChip.swift`. The behaviour that copy
// deliberately dropped, the overflow badge's removal popover, is the behaviour the shared strip
// does not have either.

// MARK: - Shared note text

/// Internal rather than private: `NoteFolderListRow`'s callers on both platforms need the same
/// preview line, and a second copy of "first line that is not the title heading" is how two rows in
/// the same column start disagreeing about what a note says.
enum NoteRowText {
    /// "Looks empty" for row styling — the same body-measured rule the list filter uses, so a row
    /// can never be listed as written and dimmed as blank at the same time. A tagged-but-unwritten
    /// note is listed (its tags live there) and still reads as empty, which is what it looks like.
    static func isEmpty(_ note: Note) -> Bool {
        NotesListVisibility.isBlankBody(
            NotesListVisibility.previewBody(note),
            displayTitle: note.displayTitle
        )
    }

    /// First line with anything on it, or `nil` for a note that is still blank. Measured against
    /// the body: previewing the raw content would show `---` for every tagged note.
    static func preview(_ note: Note) -> String? {
        NotesListVisibility.previewBody(note)
            .components(separatedBy: "\n")
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty })
    }

    /// Preview for a note whose title is carried by a `# Heading` at the top of its own body.
    /// `preview` would return that heading, so the row would print the same string twice — once as
    /// its title and once as its detail.
    static func previewBelowTitleHeading(_ note: Note) -> String? {
        NotesListVisibility.previewBody(note)
            .components(separatedBy: "\n")
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && $0 != "# \(note.displayTitle)" }
    }

    static func dayLabel(forDateKey key: String, fallback: Date) -> String {
        let date = DateFormatters.date(from: key) ?? fallback
        return DateFormatters.dayNumber.string(from: date)
    }
}

// MARK: - Daily

struct DailyNoteListRow: View {
    let note: Note
    let isSelected: Bool
    var metrics: CadenceNotesListMetrics = .desktop

    private var isToday: Bool { note.dateKey == DateFormatters.todayKey() }

    var body: some View {
        NoteListDayRow(
            dayLabel: NoteRowText.dayLabel(forDateKey: note.dateKey, fallback: note.updatedAt),
            // Today keeps its own treatment at the top of its group: it says so, in full weight,
            // and demotes its preview to the second line.
            title: isToday ? "Today" : (NoteRowText.preview(note) ?? "Empty"),
            detail: isToday ? NoteRowText.preview(note) : nil,
            isEmphasized: isToday,
            isEmptyNote: NoteRowText.isEmpty(note),
            isSelected: isSelected,
            tags: note.sortedTags,
            metrics: metrics
        )
    }
}

// MARK: - Weekly

struct WeeklyNoteListRow: View {
    let note: Note
    let isSelected: Bool
    var metrics: CadenceNotesListMetrics = .desktop

    private var isThisWeek: Bool { note.weekKey == DateFormatters.currentWeekKey() }

    /// Weekly notes file under the month of the week they start in, so the leading slot carries
    /// that week's first day and the numbers still form a column.
    private var mondayKey: String { NotesListGrouping.weekStartDateKey(forWeekKey: note.weekKey) }

    var body: some View {
        NoteListDayRow(
            dayLabel: NoteRowText.dayLabel(forDateKey: mondayKey, fallback: note.updatedAt),
            title: isThisWeek ? "This Week" : (NoteRowText.preview(note) ?? "Empty"),
            detail: isThisWeek ? NoteRowText.preview(note) : nil,
            isEmphasized: isThisWeek,
            isEmptyNote: NoteRowText.isEmpty(note),
            isSelected: isSelected,
            tags: note.sortedTags,
            metrics: metrics
        )
    }
}

// MARK: - Meeting

struct MeetingNoteListRow: View {
    let note: Note
    let isSelected: Bool
    /// `true` where the row stands on its own (the list-detail Notes tab, which has no month
    /// header above it) and so has to spell the date out; `false` in the grouped Notes list,
    /// where the header and the day slot already say it.
    var showsDate: Bool = true
    var metrics: CadenceNotesListMetrics = .desktop

    private var detail: String {
        let timeLabel = note.eventStartMin >= 0 && note.eventEndMin >= 0
            ? TimeFormatters.timeRange(startMin: note.eventStartMin, endMin: note.eventEndMin)
            : ""
        guard showsDate else { return timeLabel }
        guard let date = DateFormatters.date(from: note.eventDateKey) else {
            return "Updated \(DateFormatters.shortDate.string(from: note.updatedAt))"
        }
        let dateLabel = DateFormatters.shortDate.string(from: date)
        return timeLabel.isEmpty ? dateLabel : "\(dateLabel) • \(timeLabel)"
    }

    var body: some View {
        NoteListDayRow(
            dayLabel: NoteRowText.dayLabel(
                forDateKey: NotesListVisibility.meetingDayKey(for: note),
                fallback: note.updatedAt
            ),
            title: note.displayTitle,
            detail: detail,
            isEmphasized: false,
            isEmptyNote: NoteRowText.isEmpty(note),
            isSelected: isSelected,
            tags: note.sortedTags,
            metrics: metrics
        )
    }
}

// MARK: - Notepad

/// One notepad note.
///
/// A notepad note has no date of its own, so the leading slot carries the day it was created —
/// which is also what the column is grouped and sorted by, so the numbers still descend inside a
/// month header exactly like the dated tabs. The title is the note's own title, kept in step with
/// the `# Heading` at the top of the body; the second line previews the body under it.
struct NotepadNoteListRow: View {
    let note: Note
    let isSelected: Bool
    var metrics: CadenceNotesListMetrics = .desktop

    var body: some View {
        NoteListDayRow(
            dayLabel: NoteRowText.dayLabel(
                forDateKey: DateFormatters.dateKey(from: note.createdAt),
                fallback: note.createdAt
            ),
            title: note.displayTitle,
            detail: NoteRowText.previewBelowTitleHeading(note),
            isEmphasized: false,
            isEmptyNote: NoteRowText.isEmpty(note),
            isSelected: isSelected,
            tags: note.sortedTags,
            metrics: metrics
        )
    }
}

// MARK: - Tab → kind

extension CadenceMobileNotesTab {
    /// The `NoteKind` this tab lists.
    ///
    /// Declared here rather than on the enum because the fold state is keyed by `NoteKind` and this
    /// is the file that needs the mapping. **`.events` maps to `NoteKind.meeting`** — the raw value
    /// `"meeting"` is persisted in `Note.kindRaw`, so only the *label* reads "Event Notes"; the case
    /// must not be renamed.
    var noteKind: NoteKind {
        switch self {
        case .today: return .daily
        case .week: return .weekly
        case .notepad: return .permanent
        case .events: return .meeting
        }
    }
}
