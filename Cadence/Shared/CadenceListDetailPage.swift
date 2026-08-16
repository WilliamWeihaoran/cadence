import Foundation

/// The tabs a list (area or project) detail page is made of, on both platforms.
///
/// There used to be two of these: this one under `macOS/Views/ListDetailView.swift` and an
/// `iOSListDetailPage` under `iOS/`, identical apart from the spelling of the Notes case — and they
/// had already drifted. macOS deleted its Planning tab when the Calendar Board absorbed the
/// Planning page's bucketing, drag-to-reschedule and "N unscheduled · N overdue" summary; iOS kept
/// showing a Planning tab long after. One enum is what stops that happening again.
///
/// It lives in `Shared/` for a second reason as well: `Cadence/iOS/` is entirely inside
/// `#if os(iOS)` and therefore invisible to `CadenceTests`, which builds for macOS, so a resolution
/// rule declared there could not be pinned by a test.
enum ListDetailPage: String, CaseIterable, Identifiable, Hashable {
    case tasks     = "Tasks"
    case kanban    = "Kanban"
    case documents = "Notes"
    case links     = "Links"
    case completed = "Completed"

    var id: String { rawValue }

    static let defaultPage: ListDetailPage = .tasks

    /// Persisted raw values outlive the tabs they name, and "Planning" is the live example: it is a
    /// stored value on disk (and in the Settings default-page preference) naming a page that exists
    /// on neither platform any more. Resolve anything unrecognised to Tasks, so a stale preference
    /// lands on a real page instead of leaving the detail pane blank and every pill unhighlighted.
    ///
    /// Read every persisted page value through here — `init(rawValue:)` returns `nil` for exactly
    /// the cases this exists to handle.
    static func resolved(_ rawValue: String) -> ListDetailPage {
        ListDetailPage(rawValue: rawValue) ?? defaultPage
    }

    /// The tab bars themselves are text-only; this is used by the Settings "default list page"
    /// picker.
    var icon: String {
        switch self {
        case .tasks:     return "checkmark.square"
        case .kanban:    return "square.grid.3x2"
        case .documents: return "doc.text"
        case .links:     return "link"
        case .completed: return "list.bullet.clipboard"
        }
    }
}
