#if os(macOS)
import SwiftUI

// The note list is a column of dates, so it is laid out as one: a month header, then rows that
// carry only the day number and whatever the note actually says. The previous two-line rows
// repeated the full date ("Saturday, August 9") on every row, which meant the word "August"
// ran down the column twelve times and roughly a dozen notes filled the whole screen.

enum NotesListMetrics {
    /// Fixed leading slot for the day number so one- and two-digit days line up as a single
    /// column instead of ragging against the preview text.
    static let dayNumberWidth: CGFloat = 20
    /// Gap between the day-number slot and the title. Wider than the 9pt it started at: at 9pt the
    /// number and the first word of the preview read as one run of text, so a column of rows read
    /// as mush rather than as a number column with titles beside it. 14pt is a clear word-space
    /// gap at 12pt type without turning the slot into a second column of whitespace.
    static let dayNumberSpacing: CGFloat = 14
    static let rowHorizontalPadding: CGFloat = 10
    static let rowVerticalPadding: CGFloat = 6
    /// Matches `rowHorizontalPadding` so the header's left edge and the day-number column's left
    /// edge sit on the same line.
    static let headerHorizontalPadding: CGFloat = rowHorizontalPadding

    // MARK: - Column width
    //
    // `HSplitView` only honours `idealWidth` when the pane is also bounded: given `minWidth` and
    // `idealWidth` alone it treats the pane as infinitely growable and splits the window down the
    // middle, which is how a column of day numbers ended up ~800pt wide in a maximized window and
    // wider than the editor beside it. `maxWidth` is what actually pins it. The divider is still
    // draggable — between `columnMinWidth` and `columnMaxWidth`.
    //
    // These are the previous 220/280/380 scaled to 80%, rounded to whole 10s: the column was sized
    // for a preview long enough to read as a sentence, and it does not need to be — the row is an
    // index entry, not the note.
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
}

// MARK: - Month grouping

struct NoteMonthGroup: Identifiable {
    /// `yyyy-MM`
    let id: String
    let title: String
    let notes: [Note]
}

enum NotesListGrouping {
    /// Groups an already-sorted note list into consecutive month runs, preserving the incoming
    /// order both between and inside groups.
    ///
    /// `dateKey` returns the `yyyy-MM-dd` key the note should file under; notes whose key does not
    /// parse fall back to their `updatedAt` day so nothing silently disappears from the list.
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

    private static func resolvedKey(_ key: String, fallback: Date) -> String {
        DateFormatters.date(from: key) == nil ? DateFormatters.dateKey(from: fallback) : key
    }

    /// `2026-08` -> `AUGUST 2026`. The year is always shown: a note list scrolls back years, and a
    /// bare month name is only unambiguous for the twelve months you happen to be looking at.
    private static func monthTitle(forMonthKey monthKey: String) -> String {
        guard let date = DateFormatters.date(from: "\(monthKey)-01") else { return monthKey.uppercased() }
        return DateFormatters.monthYear.string(from: date).uppercased()
    }
}

/// Month header for a grouped note list. Uppercase and kerned, like the sidebar's context headers.
///
/// It has climbed twice. `Theme.dim` at 10pt lands 3.84:1 on `Theme.surface` — below the 4.5:1
/// floor for small text, and *dimmer* than the rows it heads, so the header was the quietest thing
/// in its own group. `Theme.muted` at 11pt bold reached 7.24:1, but the rows beside it are also
/// `Theme.muted`: identical colour, so the header out-read a row by weight alone and still lost.
/// `Theme.text` is 15.86:1 on `Theme.surface` and 2.19:1 against the `Theme.muted` day numbers and
/// titles beside it — a header that plainly out-reads its own rows, which is the whole job. It is
/// the same stop the app uses for primary content everywhere else, and uppercase + kerning keep it
/// legible as chrome rather than mistakable for a note title.
struct NotesMonthHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Theme.text)
            .kerning(0.8)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, NotesListMetrics.headerHorizontalPadding)
    }
}

/// The scrolling left-hand column of a Notes tab: month headers with their rows underneath.
struct NotesGroupedListColumn<Row: View>: View {
    let groups: [NoteMonthGroup]
    @ViewBuilder let row: (Note) -> Row

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 3) {
                        NotesMonthHeader(title: group.title)
                        ForEach(group.notes) { note in
                            row(note)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
        }
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
        HStack(alignment: .firstTextBaseline, spacing: NotesListMetrics.dayNumberSpacing) {
            Text(dayLabel)
                .font(.system(size: 12, weight: isEmphasized ? .bold : .medium).monospacedDigit())
                .foregroundStyle(foreground)
                .frame(width: NotesListMetrics.dayNumberWidth, alignment: .trailing)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: titleWeight))
                    .foregroundStyle(foreground)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                CompactTagStrip(tags: tags, limit: 3)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, NotesListMetrics.rowHorizontalPadding)
        .padding(.vertical, NotesListMetrics.rowVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                .fill(fill)
        )
        .contentShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

// MARK: - Shared note text

private enum NoteRowText {
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
            tags: note.sortedTags
        )
    }
}

// MARK: - Weekly

struct WeeklyNoteListRow: View {
    let note: Note
    let isSelected: Bool

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
            tags: note.sortedTags
        )
    }
}

extension NotesListGrouping {
    /// `2026-W33` -> the `yyyy-MM-dd` key of that ISO week's Monday.
    static func weekStartDateKey(forWeekKey weekKey: String) -> String {
        let parts = weekKey.components(separatedBy: "-W")
        guard parts.count == 2, let year = Int(parts[0]), let week = Int(parts[1]) else { return weekKey }
        var calendar = Calendar(identifier: .iso8601)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        var components = DateComponents()
        components.yearForWeekOfYear = year
        components.weekOfYear = week
        components.weekday = 2 // Monday
        guard let monday = calendar.date(from: components) else { return weekKey }
        return DateFormatters.dateKey(from: monday)
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

    private var eventDayKey: String {
        note.eventDateKey.isEmpty ? DateFormatters.dateKey(from: note.updatedAt) : note.eventDateKey
    }

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
            dayLabel: NoteRowText.dayLabel(forDateKey: eventDayKey, fallback: note.updatedAt),
            title: note.displayTitle,
            detail: detail,
            isEmphasized: false,
            isEmptyNote: NoteRowText.isEmpty(note),
            isSelected: isSelected,
            tags: note.sortedTags
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
            tags: note.sortedTags
        )
    }
}
#endif
