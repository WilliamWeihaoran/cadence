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

    /// The page a list opens on: its own remembered tab when it has one, the user's global
    /// default when it does not.
    ///
    /// **The stale case belongs to the list, not to the default.** macOS's restore used to read
    /// the per-list value through the failable `init(rawValue:)` and, when that returned `nil`,
    /// throw the value away and fall back to `resolved(defaultPageRawValue)`. So a list still
    /// holding `Planning` — the value `ListDetailPageTests` documents as live on disk — opened on
    /// **Links** if that was the global default, rather than on Tasks. A stale remembered tab is
    /// an unrecognised page name, which is exactly what `resolved(_:)` exists to map to Tasks;
    /// it is not evidence that the user wanted their global default for this list. T-351.
    static func rememberedPage(storedRawValue: String?, defaultPageRawValue: String) -> ListDetailPage {
        guard let storedRawValue, !storedRawValue.isEmpty else {
            return resolved(defaultPageRawValue)
        }
        return resolved(storedRawValue)
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

/// The geometry of the iOS list-detail tab strip (`Tasks / Kanban / Notes / Links / Completed`).
///
/// **T-6985: the strip overran an iPhone once its counts showed.** At 12 pt of padding either side
/// of every tab the five labels need ~356 pt bare and ~419 pt with two-digit counts beside Tasks,
/// Kanban and Completed (SF 13 pt, measured), against 369 pt on a 393 pt iPhone after the host's
/// 12 pt gutters. It sat in a horizontal scroll view with its indicator hidden, so "Completed" was
/// cut off at the right edge with nothing saying the row moved.
///
/// So the strip now tries these paddings in order and takes the first at which every tab fits
/// (`ViewThatFits`); only past the tightest does it scroll, and then it says so with an edge fade
/// and keeps the selected tab in view. Here, in `Shared/`, rather than in the iOS view, because
/// `Cadence/iOS/` is invisible to the macOS-hosted test target and the tiers are the decision —
/// `CadenceListDetailTabStripFitTests` prices them against measured label widths.
enum ListDetailTabStripMetrics {
    /// Horizontal padding either side of each tab's label, loosest first.
    static let horizontalPaddingTiers: [CGFloat] = [12, 8, 6]
    /// Between adjacent tabs.
    static let tabSpacing: CGFloat = 2
    /// Between a tab's label and its count.
    static let labelCountSpacing: CGFloat = 6
    /// The strip's own inset either side, inside the scroll content.
    static let stripInset: CGFloat = 1
    /// No tab narrower than a touch target, whatever the tier. "Links" sits right at it at 6 pt.
    static let minimumTabWidth: CGFloat = 44

    /// The width the strip needs, given each tab's content width (label, plus spacing and count
    /// where one shows) and a padding tier. The same sum `ViewThatFits` makes of the real views.
    static func stripWidth(contentWidths: [CGFloat], horizontalPadding: CGFloat) -> CGFloat {
        let tabs = contentWidths.map { max($0 + horizontalPadding * 2, minimumTabWidth) }
        return tabs.reduce(0, +)
            + tabSpacing * CGFloat(max(contentWidths.count - 1, 0))
            + stripInset * 2
    }
}
