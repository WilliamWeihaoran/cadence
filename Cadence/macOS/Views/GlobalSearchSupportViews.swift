#if os(macOS)
import SwiftUI

enum GlobalSearchCategory: String, CaseIterable {
    case commands = "Commands"
    case pages = "Pages"
    case areas = "Areas"
    case projects = "Projects"
    case tasks = "Tasks"
    case events = "Calendar Events"
    case meetingNotes = "Event Notes"
    case goals = "Goals"
    case habits = "Habits"
}

enum GlobalSearchDestination: Hashable {
    case command(GlobalSearchCommand)
    case sidebar(SidebarItem)
    case area(UUID)
    case project(UUID)
    case task(UUID)
    case event(String)
    case eventNote(UUID)
    case goals
    case habits
}

/// `CaseIterable` since T-1940, so "every command the palette declares has a row" is a claim a
/// test can make. A case here exists only because Cmd+K offers it; one missing from
/// `GlobalSearchCommandDefinition.all` is a command nothing can reach.
enum GlobalSearchCommand: String, CaseIterable, Hashable {
    case newTask
    case focus
    case today
    case allTasks
    case calendar
    case settings
}

extension GlobalSearchCommand {
    /// **The page this command opens**, or `nil` for the one command that opens no page (T-1940).
    ///
    /// This is the fact `tintSource` used to be the only reader of, promoted so the row's title,
    /// glyph and query words can be read off it too. Five of the six commands open a destination
    /// the sidebar already draws; `.newTask` opens the capture sheet, so it is the one row whose
    /// copy is genuinely its own.
    var destination: CadenceFeatureDestination? {
        switch self {
        case .newTask: return nil
        case .focus: return .focus
        case .today: return .today
        case .allTasks: return .allTasks
        case .calendar: return .calendar
        case .settings: return .settings
        }
    }

    /// The destination whose sidebar tint this command's row is drawn in.
    ///
    /// `.newTask` is the only one that is not itself a destination — it opens the capture sheet
    /// rather than a page — and it takes the Tasks tint because that is the family it belongs to,
    /// which is also the colour it has always been drawn in. That fallback is the *only* thing
    /// this adds to `destination`, and it stays a `CadenceSidebarTint` lookup at the call site
    /// (T-244), so a user's Settings → Sidebar override still reaches the palette.
    var tintSource: CadenceFeatureDestination { destination ?? .allTasks }
}

/// A row in Cmd+K's **Commands** section.
///
/// **It carries no colour of its own.** Every tint here used to be a hand-assigned `Theme` accent
/// (T-244), and three of them named a different hue than the sidebar draws the same destination
/// in: Focus was `Theme.red` against the sidebar's teal, Calendar was `Theme.purple` against the
/// sidebar's red — the sidebar's *Notes* colour, on the Calendar row — and Settings was
/// `Theme.dim` against the sidebar's blue. The ticket named the first two; the third was found
/// while fixing them. The sidebar is the
/// source of truth — it is where Settings → Sidebar lets the user *retint* a destination — so the
/// tint is resolved from `CadenceSidebarTint` at build time instead, which also makes an override
/// reach this palette. It never did before: nothing here read
/// `CadencePreferenceKeys.sidebarTabColors` at all.
///
/// **And it types no name or glyph of its own either** (T-1940). `title` and `icon` were stored
/// beside `command`, and for **five of the six** rows — Focus, Today, All Tasks, Calendar,
/// Settings — both were character-for-character what the destination already returns: `timer`,
/// `sun.max.fill`, `checklist`, `calendar`, `gearshape.fill`, under "Focus", "Today", "All Tasks",
/// "Calendar", "Settings". That is the state [[T-258]] found one struct down in the Pages catalog,
/// where eight of nine icons agreed and the ninth did not, so one destination wore two glyphs
/// depending on how you reached it.
///
/// **The fields are deleted rather than left stored-and-equal**, which is the whole enforcement:
/// a second copy that currently matches is exactly the state the Pages one was in the day before
/// somebody edited the sidebar's glyph, and a test comparing two stored lists is green the day
/// somebody edits both. There is nowhere left for a second opinion about a command's name to live.
///
/// **`subtitle` stays stored, and that is a decision rather than an omission.** "Open the Today
/// page" names what the *command* does; a Pages row's sentence names what is *in* the page
/// (`searchSummary`). A one-line command row has room for exactly one sentence and the action is
/// the right one, so this is a real second register — not a second answer to the same question.
/// It is the only string the catalog below types.
struct GlobalSearchCommandDefinition {
    let command: GlobalSearchCommand

    /// What this **command** does, in the imperative. See the note above for why it is the one
    /// stored string.
    let subtitle: String

    /// The row's title: the destination's own name, or the capture sheet's for the one command
    /// that opens no page (T-1940).
    var title: String { command.destination?.title ?? "New Task" }

    /// The glyph the sidebar draws this command's destination with (T-1940), or `.newTask`'s own.
    ///
    /// `plus.circle.fill` is not the Tasks glyph and must not be: the row adds a task rather than
    /// going to the task index, and it is the one row here whose tint is a borrow
    /// (`tintSource` falls back to `.allTasks`) while its glyph is not.
    var icon: String { command.destination?.systemImage ?? "plus.circle.fill" }

    /// The extra words that reach this row (T-1940).
    ///
    /// Stored per row until now, and every word each of the five destination-backed rows carried
    /// was already in `searchAliases` — "pomodoro", "dashboard", "daily", "events" and the rest —
    /// so deriving them adds words and drops none. It also ends the asymmetry the Pages side left
    /// behind: after T-1782 a word could reach the Calendar *page* and not the Calendar *command*
    /// in the same palette.
    var aliases: String { command.destination?.searchAliases ?? "create task add" }

    func tintHex(sidebarTabColorsRaw: String) -> String {
        CadenceSidebarTint.hex(for: command.tintSource, overridesRaw: sidebarTabColorsRaw)
    }
}

/// A row in Cmd+K's **Pages** section.
///
/// The destination is the one stored fact, and **everything else follows from it**: the selection
/// the row opens (`item`), the tint it is drawn in, the sidebar toggle its subtitle reports on
/// (`toggleable`), the glyph (`icon`, T-258) and — since T-1782 — the row's own title, its
/// subtitle and the extra words that reach it. See `GlobalSearchCommandDefinition` for why the
/// tint is not spelled here. The Commands catalog beside it was the last list in this file typing
/// its own copy of a destination's name and glyph; T-1940 deleted those fields too, so neither
/// section of the palette holds a second opinion about a page any more.
struct GlobalSearchPageDefinition {
    let feature: CadenceFeatureDestination

    /// The row's title, which is the destination's own (T-1782).
    ///
    /// It was a stored `let label: String` and all nine entries typed the string `title` already
    /// returns. `compactTitle` is deliberately *not* what this reads: the palette row says
    /// "All Tasks", where a sidebar row says "Tasks".
    var label: String { feature.title }

    /// The glyph the sidebar draws this destination with (T-258).
    ///
    /// It was a stored `let icon: String` typed beside each entry, and eight of the nine happened
    /// to equal `systemImage` while the ninth did not: the palette said `doc.text` for Notes and
    /// the sidebar said `note.text`, so one destination wore two glyphs depending on how you
    /// reached it. Same defect class as the tint one line down — two lists answering one question
    /// about a destination, agreeing until one of them moved. The field is **deleted** rather than
    /// left stored-and-equal, because a second copy that currently matches is exactly the state
    /// this one was in before somebody changed the sidebar's glyph.
    ///
    /// The `doc.text` on `GlobalSearchIndexSupport`'s event-note rows is unrelated and stays:
    /// those rows are notes, not the Notes destination.
    var icon: String { feature.systemImage }

    /// **What is in this page — the destination's own sentence, not a second one** (T-1782).
    ///
    /// This was a stored `baseSubtitle`, and it was a *contents* line for all nine entries, which
    /// is what `CadenceFeatureDestination.searchSummary` is. The two lists disagreed about seven of
    /// the nine: Today read "Daily dashboard and timeline" here and "Tasks, notes, and schedule"
    /// on iOS, Notes "Workspace notes" against "Daily, weekly, and permanent notes", and so on.
    /// T-1701 had already taken two of them — Inbox's and Goals' — *from* this list into the
    /// destination precisely so it would not invent an eleventh phrasing; this is the rest of that
    /// move, in the same direction.
    ///
    /// **Deleted rather than left stored-and-equal**, which is the rule `icon` below was already
    /// fixed by: a second copy that currently matches is the exact state this one was in before
    /// somebody changed the other list. The standing "page headers do not describe the page you are
    /// on" rule does not bear on it either way — both surfaces are search *rows*, which the rule
    /// explicitly allows a subtitle, so it permits two registers without requiring them.
    var baseSubtitle: String { feature.searchSummary }

    /// The extra words that reach this row, which are the destination's (T-1782).
    ///
    /// Also stored, also a second answer to a question the destination answers: the palette matched
    /// against `aliases` while iOS matched against `searchAliases`, so "dashboard" found Today on a
    /// Mac and nothing on a phone, and "notepad" the reverse. The five words this list had that
    /// `searchKeywords` did not — dashboard, daily, targets, stages, docs — moved into
    /// `searchKeywords`, so nothing stopped being findable here and everything became findable on
    /// both.
    var aliases: String { feature.searchAliases }

    /// `nil` for a destination the sidebar does not route to as a page — `.lists` is the
    /// scrolling region and `.search` is the header button, so neither can be a palette row.
    var item: SidebarItem? { feature.macSidebarItem }

    /// The Settings → Sidebar handle this row reports "Hidden from sidebar" against, or `nil` for
    /// a destination Settings offers no handle for. Inbox is the interesting one: it is a *view*
    /// inside the Tasks destination rather than a sidebar row, so there is no visibility toggle
    /// for this entry to report on — and it stays its own palette row anyway, because it is still
    /// its own view.
    var toggleable: SidebarStaticDestination? { feature.sidebarStaticDestination }

    func tintHex(sidebarTabColorsRaw: String) -> String {
        CadenceSidebarTint.hex(for: feature, overridesRaw: sidebarTabColorsRaw)
    }
}

struct GlobalSearchResult: Identifiable, Hashable {
    let id: String
    let category: GlobalSearchCategory
    let title: String
    let subtitle: String
    let icon: String
    let tintHex: String
    let destination: GlobalSearchDestination

    var tint: Color { Color(hex: tintHex) }
}

/// Task subtitles are a bullet-joined metadata string where the due date lands near the end,
/// so a long list name plus tags used to truncate it away entirely. Splitting the due segment
/// out lets the row lay it out with priority instead of letting it fall off the tail.
struct GlobalSearchSubtitleParts {
    let leading: String
    let due: String?

    init(subtitle: String, category: GlobalSearchCategory) {
        let segments = subtitle.components(separatedBy: " • ")
        // Only tasks carry a due segment, and the container name always leads — so a list
        // literally named "Due Diligence" is never mistaken for one. Scanning from the back
        // also prefers the real due segment over an earlier tag that happens to start with it.
        let dueIndex: Int? = category == .tasks
            ? segments.indices.dropFirst().last(where: { segments[$0].hasPrefix("Due ") })
            : nil

        guard let dueIndex else {
            self.leading = subtitle
            self.due = nil
            return
        }
        self.leading = segments.enumerated()
            .filter { $0.offset != dueIndex }
            .map(\.element)
            .joined(separator: " • ")
        self.due = segments[dueIndex]
    }
}

struct GlobalSearchSection: Identifiable {
    let category: GlobalSearchCategory
    let results: [GlobalSearchResult]

    var id: String { category.rawValue }
}

extension GlobalSearchCommandDefinition {
    /// **The command and the sentence about the command, and nothing else** (T-1940). Every row
    /// here used to type a title, a glyph and an alias string too; five of the six typed the
    /// destination's own.
    ///
    /// **This list is the whole of `GlobalSearchCommand`, and that is a different fact from the
    /// Pages catalog's.** `GlobalSearchPageDefinition.all` is deliberately shorter than
    /// `CadenceFeatureDestination.allCases` — `.lists` is the sidebar's scrolling region and
    /// `.search` is the palette itself, so neither can be a row. Nothing of that kind applies
    /// here: a `GlobalSearchCommand` case exists only because the palette offers it, so a case
    /// missing from this list is a command the user cannot reach, not a routing fact.
    ///
    /// **Five of these open the same page a Pages row opens, and that stays** — Cmd+K lists Today,
    /// All Tasks, Calendar, Focus and Settings twice, once per section. Nothing in the repository
    /// said whether that was intentional; it is, and this is where that is now written down. The
    /// two sections answer different questions — a *verb* ("Open the Today page", ranked first)
    /// against a *place* ("Tasks, notes, and schedule") — they route differently
    /// (`.command` against `.sidebar`), and removing the five would leave a Commands section
    /// holding one row, which is deleting the section rather than de-duplicating it.
    static var all: [GlobalSearchCommandDefinition] {
        [
            .init(command: .newTask, subtitle: "Create a task from anywhere in the app"),
            .init(command: .focus, subtitle: "Jump straight to the Focus page"),
            .init(command: .today, subtitle: "Open the Today page"),
            .init(command: .allTasks, subtitle: "Open the full task index"),
            .init(command: .calendar, subtitle: "Open the calendar and timeline"),
            .init(command: .settings, subtitle: "Open app settings")
        ]
    }
}

extension GlobalSearchPageDefinition {
    /// **The destination is the whole entry** (T-1782). Every word a Pages row draws or is matched
    /// against now comes from `CadenceFeatureDestination`, so the palette has nowhere to keep a
    /// second opinion about a page — which is the enforcement, the stored field being gone rather
    /// than a test comparing two lists that are free to drift between runs of it.
    ///
    /// This list is still shorter than `CadenceFeatureDestination.allCases`, and deliberately:
    /// `.lists` is the sidebar's scrolling region and `.search` is the palette itself, so neither
    /// is a row the palette can open. That is a routing fact, not a copy one.
    static var all: [GlobalSearchPageDefinition] {
        [
            .init(feature: .today),
            .init(feature: .allTasks),
            .init(feature: .inbox),
            .init(feature: .focus),
            .init(feature: .calendar),
            .init(feature: .goals),
            .init(feature: .habits),
            .init(feature: .notes),
            .init(feature: .settings)
        ]
    }
}

struct GlobalSearchHeader: View {
    @Binding var draftQuery: String
    let clear: () -> Void
    let submit: () -> Void
    @FocusState.Binding var isSearchFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "command")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.dim)

            TextField("Jump anywhere or run a command…", text: $draftQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.text)
                .focused($isSearchFocused)
                .onSubmit(submit)

            CadenceSearchFieldClearButton(
                text: $draftQuery,
                glyphSize: 16,
                focus: $isSearchFocused,
                onClear: clear
            )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Theme.surface.opacity(0.48))
    }
}

struct GlobalSearchEmptyState: View {
    let query: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "command")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Theme.dim.opacity(0.8))
            Text(query.isEmpty ? "Start typing to search or run a command" : "No matches found")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text(query.isEmpty ? "Pages, lists, tasks, events, goals, habits, and quick commands all show up here." : "Try a cleaner title, list name, or command like new task.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct GlobalSearchResultRow: View {
    let result: GlobalSearchResult
    let isHighlighted: Bool
    let onSelect: () -> Void
    let onHover: () -> Void

    private var subtitleParts: GlobalSearchSubtitleParts {
        GlobalSearchSubtitleParts(subtitle: result.subtitle, category: result.category)
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: Theme.radiusControl)
                    .fill(result.tint.opacity(0.18))
                    .frame(width: 34, height: 34)
                    .overlay {
                        Image(systemName: result.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(result.tint)
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text(result.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if !subtitleParts.leading.isEmpty {
                            Text(subtitleParts.leading)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.dim)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }

                        if let due = subtitleParts.due {
                            // Laid out ahead of the rest of the metadata so the due date is never
                            // the part that gets truncated away.
                            Text(due)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.amber)
                                .lineLimit(1)
                                .fixedSize()
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Theme.amber.opacity(0.14))
                                .clipShape(Capsule())
                                .layoutPriority(1)
                        }
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHighlighted ? result.tint.opacity(0.09) : Color.clear)
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isHighlighted ? result.tint.opacity(0.18) : Color.clear, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.cadencePlain)
        .padding(.horizontal, 6)
        .onHover { hovering in
            if hovering { onHover() }
        }
    }
}

extension Color {
    func globalSearchHexString() -> String? {
        let platformColor = NSColor(self).usingColorSpace(.deviceRGB)
        guard let platformColor else { return nil }
        let r = Int(round(platformColor.redComponent * 255))
        let g = Int(round(platformColor.greenComponent * 255))
        let b = Int(round(platformColor.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
#endif
