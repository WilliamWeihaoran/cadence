#if os(macOS)
import SwiftUI

struct DailyNoteListRow: View {
    let note: Note
    let isSelected: Bool

    private var formattedDate: String {
        guard let date = DateFormatters.date(from: note.dateKey) else { return note.dateKey }
        return DateFormatters.longDate.string(from: date)
    }

    private var preview: String {
        note.content.components(separatedBy: "\n")
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? "Empty note"
    }

    private var isToday: Bool { note.dateKey == DateFormatters.todayKey() }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(isToday ? "Today" : formattedDate)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isToday ? Theme.blue : Theme.muted)
            Text(preview)
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
            CompactTagStrip(tags: note.sortedTags, limit: 3)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Theme.blue.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
        .contentShape(Rectangle())
        .cadenceHoverHighlight(
            cornerRadius: Theme.radiusControl,
            fillColor: Theme.blue.opacity(isSelected ? 0.14 : 0.06),
            strokeColor: Theme.blue.opacity(isSelected ? 0.22 : 0.12)
        )
    }
}

struct WeeklyNoteListRow: View {
    let note: Note
    let isSelected: Bool

    private var isThisWeek: Bool { note.weekKey == DateFormatters.currentWeekKey() }
    private var label: String { isThisWeek ? "This Week" : DateFormatters.weekLabel(from: note.weekKey) }

    private var preview: String {
        note.content.components(separatedBy: "\n")
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? "Empty note"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isThisWeek ? Theme.blue : Theme.muted)
            Text(preview)
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
            CompactTagStrip(tags: note.sortedTags, limit: 3)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Theme.blue.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
        .contentShape(Rectangle())
        .cadenceHoverHighlight(
            cornerRadius: Theme.radiusControl,
            fillColor: Theme.blue.opacity(isSelected ? 0.14 : 0.06),
            strokeColor: Theme.blue.opacity(isSelected ? 0.22 : 0.12)
        )
    }
}

struct MeetingNoteListRow: View {
    let note: Note
    let isSelected: Bool
    var showsPreview: Bool = true

    private var preview: String {
        note.content.components(separatedBy: "\n")
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? "Empty note"
    }

    private var detail: String {
        if let date = DateFormatters.date(from: note.eventDateKey) {
            if note.eventStartMin >= 0, note.eventEndMin >= 0 {
                return "\(DateFormatters.shortDate.string(from: date)) • \(TimeFormatters.timeRange(startMin: note.eventStartMin, endMin: note.eventEndMin))"
            }
            return DateFormatters.shortDate.string(from: date)
        }
        return "Updated \(DateFormatters.shortDate.string(from: note.updatedAt))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.displayTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
            if showsPreview {
                Text(preview)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }
            CompactTagStrip(tags: note.sortedTags, limit: 3)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Theme.blue.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
        .contentShape(Rectangle())
        .cadenceHoverHighlight(
            cornerRadius: Theme.radiusControl,
            fillColor: Theme.blue.opacity(isSelected ? 0.14 : 0.06),
            strokeColor: Theme.blue.opacity(isSelected ? 0.22 : 0.12)
        )
    }
}
#endif
