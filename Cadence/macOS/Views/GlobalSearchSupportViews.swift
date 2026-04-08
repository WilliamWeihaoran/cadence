#if os(macOS)
import SwiftUI

enum GlobalSearchCategory: String, CaseIterable {
    case commands = "Commands"
    case pages = "Pages"
    case areas = "Areas"
    case projects = "Projects"
    case tasks = "Tasks"
    case events = "Calendar Events"
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
    case goals
    case habits
}

enum GlobalSearchCommand: String, Hashable {
    case newTask
    case focus
    case today
    case allTasks
    case calendar
    case settings
}

struct GlobalSearchCommandDefinition {
    let command: GlobalSearchCommand
    let title: String
    let subtitle: String
    let icon: String
    let tintHex: String
    let aliases: String
}

struct GlobalSearchPageDefinition {
    let label: String
    let item: SidebarItem
    let icon: String
    let tintHex: String
    let baseSubtitle: String
    let aliases: String
    let toggleable: SidebarStaticDestination?
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

struct GlobalSearchSection: Identifiable {
    let category: GlobalSearchCategory
    let results: [GlobalSearchResult]

    var id: String { category.rawValue }
}

enum GlobalSearchMatcher {
    nonisolated static func rankResults(_ results: [GlobalSearchResult], query: String) -> [GlobalSearchResult] {
        results.sorted { lhs, rhs in
            let leftScore = matchScore(query: query, lhs.title, lhs.subtitle) ?? Int.min
            let rightScore = matchScore(query: query, rhs.title, rhs.subtitle) ?? Int.min
            if leftScore != rightScore { return leftScore > rightScore }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    nonisolated static func matchScore(query: String, _ fields: String...) -> Int? {
        matchScore(query: query, fields: fields)
    }

    nonisolated static func matchScore(query: String, fields: [String]) -> Int? {
        if query.isEmpty { return 1 }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return 1 }

        let normalizedQuery = normalize(trimmedQuery)
        let queryTokens = normalizedQuery.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !queryTokens.isEmpty else { return 1 }

        let normalizedFields = fields
            .map(normalize)
            .filter { !$0.isEmpty }
        guard !normalizedFields.isEmpty else { return nil }

        let title = normalizedFields.first ?? ""
        let body = normalizedFields.joined(separator: " ")
        let titleWords = title.split(separator: " ").map(String.init)
        let allWords = body.split(separator: " ").map(String.init)

        var score = 0

        if title == normalizedQuery {
            score += 1_000
        } else if title.hasPrefix(normalizedQuery) {
            score += 800
        } else if body.contains(normalizedQuery) {
            score += 320
        }

        for token in queryTokens {
            if let index = titleWords.firstIndex(where: { $0.hasPrefix(token) }) {
                score += max(260 - (index * 14), 180)
                continue
            }
            if let index = allWords.firstIndex(where: { $0.hasPrefix(token) }) {
                score += max(170 - (index * 6), 90)
                continue
            }
            if title.contains(token) {
                score += 85
                continue
            }
            if body.contains(token) {
                score += 35
                continue
            }
            return nil
        }

        return score
    }

    nonisolated static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "[^A-Za-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

extension GlobalSearchCommandDefinition {
    static var all: [GlobalSearchCommandDefinition] {
        [
            .init(command: .newTask, title: "New Task", subtitle: "Create a task from anywhere in the app", icon: "plus.circle.fill", tintHex: Theme.blue.globalSearchHexString() ?? "#5AA2FF", aliases: "create task add"),
            .init(command: .focus, title: "Focus", subtitle: "Jump straight to the Focus page", icon: "timer", tintHex: Theme.red.globalSearchHexString() ?? "#FF6B6B", aliases: "pomodoro timer focus"),
            .init(command: .today, title: "Today", subtitle: "Open the Today page", icon: "sun.max.fill", tintHex: Theme.amber.globalSearchHexString() ?? "#FFB84D", aliases: "today dashboard daily"),
            .init(command: .allTasks, title: "All Tasks", subtitle: "Open the full task index", icon: "checklist", tintHex: Theme.blue.globalSearchHexString() ?? "#5AA2FF", aliases: "tasks all"),
            .init(command: .calendar, title: "Calendar", subtitle: "Open the calendar and timeline", icon: "calendar", tintHex: Theme.purple.globalSearchHexString() ?? "#9E8CFF", aliases: "calendar schedule events"),
            .init(command: .settings, title: "Settings", subtitle: "Open app settings", icon: "gearshape.fill", tintHex: Theme.dim.globalSearchHexString() ?? "#7B8492", aliases: "preferences settings")
        ]
    }
}

extension GlobalSearchPageDefinition {
    static var all: [GlobalSearchPageDefinition] {
        [
            .init(label: "Today", item: .today, icon: "sun.max.fill", tintHex: Theme.amber.globalSearchHexString() ?? "#FFB84D", baseSubtitle: "Daily dashboard and timeline", aliases: "today dashboard daily", toggleable: .today),
            .init(label: "All Tasks", item: .allTasks, icon: "checklist", tintHex: Theme.blue.globalSearchHexString() ?? "#5AA2FF", baseSubtitle: "Everything across your workspace", aliases: "tasks all", toggleable: .allTasks),
            .init(label: "Inbox", item: .inbox, icon: "tray.fill", tintHex: Theme.blue.globalSearchHexString() ?? "#5AA2FF", baseSubtitle: "Unsorted capture tasks", aliases: "inbox capture", toggleable: .inbox),
            .init(label: "Focus", item: .focus, icon: "timer", tintHex: Theme.red.globalSearchHexString() ?? "#FF6B6B", baseSubtitle: "Focus timer and active task", aliases: "focus timer pomodoro", toggleable: .focus),
            .init(label: "Calendar", item: .calendar, icon: "calendar", tintHex: Theme.purple.globalSearchHexString() ?? "#9E8CFF", baseSubtitle: "Full calendar and time blocks", aliases: "calendar schedule events", toggleable: .calendar),
            .init(label: "Goals", item: .goals, icon: "target", tintHex: Theme.green.globalSearchHexString() ?? "#4ECB71", baseSubtitle: "Goals and progress", aliases: "goals target", toggleable: .goals),
            .init(label: "Habits", item: .habits, icon: "flame.fill", tintHex: Theme.amber.globalSearchHexString() ?? "#FFB84D", baseSubtitle: "Habits and streaks", aliases: "habits streaks", toggleable: .habits),
            .init(label: "Notes", item: .notes, icon: "doc.text", tintHex: Theme.purple.globalSearchHexString() ?? "#9E8CFF", baseSubtitle: "Workspace notes", aliases: "notes docs", toggleable: nil),
            .init(label: "Settings", item: .settings, icon: "gearshape.fill", tintHex: Theme.dim.globalSearchHexString() ?? "#7B8492", baseSubtitle: "Appearance, calendar, and sidebar preferences", aliases: "settings preferences", toggleable: nil)
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

            if !draftQuery.isEmpty {
                Button(action: clear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.dim)
                }
                .buttonStyle(.cadencePlain)
            }
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

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10)
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

                    Text(result.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHighlighted ? result.tint.opacity(0.09) : Color.clear)
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isHighlighted ? result.tint.opacity(0.18) : Color.clear, lineWidth: 1)
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
