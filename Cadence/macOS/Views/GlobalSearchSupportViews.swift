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

enum GlobalSearchCommand: String, Hashable {
    case newTask
    case focus
    case today
    case allTasks
    case calendar
    case settings
}

extension GlobalSearchCommand {
    /// The destination whose sidebar tint this command's row is drawn in.
    ///
    /// `.newTask` is the only one that is not itself a destination — it opens the capture sheet
    /// rather than a page — and it takes the Tasks tint because that is the family it belongs to,
    /// which is also the colour it has always been drawn in.
    var tintSource: CadenceFeatureDestination {
        switch self {
        case .newTask: return .allTasks
        case .focus: return .focus
        case .today: return .today
        case .allTasks: return .allTasks
        case .calendar: return .calendar
        case .settings: return .settings
        }
    }
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
struct GlobalSearchCommandDefinition {
    let command: GlobalSearchCommand
    let title: String
    let subtitle: String
    let icon: String
    let aliases: String

    func tintHex(sidebarTabColorsRaw: String) -> String {
        CadenceSidebarTint.hex(for: command.tintSource, overridesRaw: sidebarTabColorsRaw)
    }
}

/// A row in Cmd+K's **Pages** section.
///
/// The destination is the one stored fact, and the three things that used to be typed beside it
/// all follow from it: the selection the row opens (`item`), the tint it is drawn in, and the
/// sidebar toggle its subtitle reports on (`toggleable`). See `GlobalSearchCommandDefinition` for
/// why the tint is not spelled here.
struct GlobalSearchPageDefinition {
    let label: String
    let feature: CadenceFeatureDestination
    let icon: String
    let baseSubtitle: String
    let aliases: String

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
    static var all: [GlobalSearchCommandDefinition] {
        [
            .init(command: .newTask, title: "New Task", subtitle: "Create a task from anywhere in the app", icon: "plus.circle.fill", aliases: "create task add"),
            .init(command: .focus, title: "Focus", subtitle: "Jump straight to the Focus page", icon: "timer", aliases: "pomodoro timer focus"),
            .init(command: .today, title: "Today", subtitle: "Open the Today page", icon: "sun.max.fill", aliases: "today dashboard daily"),
            .init(command: .allTasks, title: "All Tasks", subtitle: "Open the full task index", icon: "checklist", aliases: "tasks all"),
            .init(command: .calendar, title: "Calendar", subtitle: "Open the calendar and timeline", icon: "calendar", aliases: "calendar schedule events"),
            .init(command: .settings, title: "Settings", subtitle: "Open app settings", icon: "gearshape.fill", aliases: "preferences settings")
        ]
    }
}

extension GlobalSearchPageDefinition {
    static var all: [GlobalSearchPageDefinition] {
        [
            .init(label: "Today", feature: .today, icon: "sun.max.fill", baseSubtitle: "Daily dashboard and timeline", aliases: "today dashboard daily"),
            .init(label: "All Tasks", feature: .allTasks, icon: "checklist", baseSubtitle: "Everything across your workspace", aliases: "tasks all"),
            .init(label: "Inbox", feature: .inbox, icon: "tray.fill", baseSubtitle: "Unsorted capture tasks", aliases: "inbox capture"),
            .init(label: "Focus", feature: .focus, icon: "timer", baseSubtitle: "Focus timer and active task", aliases: "focus timer pomodoro"),
            .init(label: "Calendar", feature: .calendar, icon: "calendar", baseSubtitle: "Full calendar and time blocks", aliases: "calendar schedule events"),
            .init(label: "Goals", feature: .goals, icon: "flag.fill", baseSubtitle: "Directions, milestones, and progress", aliases: "goals milestones targets stages directions"),
            .init(label: "Habits", feature: .habits, icon: "flame.fill", baseSubtitle: "Habits and streaks", aliases: "habits streaks"),
            .init(label: "Notes", feature: .notes, icon: "doc.text", baseSubtitle: "Workspace notes", aliases: "notes docs"),
            .init(label: "Settings", feature: .settings, icon: "gearshape.fill", baseSubtitle: "Appearance, calendar, and sidebar preferences", aliases: "settings preferences")
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

    private var subtitleParts: GlobalSearchSubtitleParts {
        GlobalSearchSubtitleParts(subtitle: result.subtitle, category: result.category)
    }

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
