#if os(macOS)
import SwiftUI

/// The rows Settings → Sidebar offers a handle for: a visibility toggle, a place in the stored
/// order, and a colour override.
///
/// **`.inbox` is not one of them any more.** Inbox is a view inside the Tasks destination now
/// (`CadenceTasksPageScope`), not a row, and a case here whose row the sidebar does not render is a
/// toggle and a colour picker that silently change nothing — see
/// `everyRowSettingsLetsYouCustomiseIsActuallyRendered`. Stored `inbox` entries in
/// `sidebarHiddenTabs` / `sidebarTabOrder` / `sidebarTabColors` now fail to decode and are dropped,
/// which is the graceful outcome every reader here already handles with `compactMap`.
enum SidebarStaticDestination: String, CaseIterable, Identifiable {
    case today
    case allTasks
    case focus
    case calendar
    case goals
    case habits

    var id: String { rawValue }

    var item: SidebarItem {
        switch self {
        case .today: return .today
        case .allTasks: return .allTasks
        case .focus: return .focus
        case .calendar: return .calendar
        case .goals: return .goals
        case .habits: return .habits
        }
    }

    var feature: CadenceFeatureDestination {
        switch self {
        case .today: return .today
        case .allTasks: return .allTasks
        case .focus: return .focus
        case .calendar: return .calendar
        case .goals: return .goals
        case .habits: return .habits
        }
    }

    var icon: String {
        feature.systemImage
    }

    var label: String {
        feature.title
    }

    var color: Color {
        Color(hex: defaultColorHex)
    }

    var defaultColorHex: String {
        feature.defaultColorHex
    }
}

extension SidebarStaticDestination {
    static var defaultOrder: [SidebarStaticDestination] {
        CadenceFeatureDestination.desktopSidebarOrder.compactMap { SidebarStaticDestination(rawValue: $0.rawValue) }
    }

    static func orderedDestinations(from raw: String) -> [SidebarStaticDestination] {
        let stored = raw
            .split(separator: ",")
            .compactMap { SidebarStaticDestination(rawValue: String($0)) }
        let uniqueStored = stored.reduce(into: [SidebarStaticDestination]()) { partial, item in
            if !partial.contains(item) { partial.append(item) }
        }
        let missing = defaultOrder.filter { !uniqueStored.contains($0) }
        return uniqueStored + missing
    }

    static func rawOrderString(from destinations: [SidebarStaticDestination]) -> String {
        destinations.map(\.rawValue).joined(separator: ",")
    }

    /// Delegates to `CadenceSidebarTint`, which parses the same string keyed by
    /// `CadenceFeatureDestination` raw values. The two enums share raw values by construction, so
    /// this is the same map read through the enum this screen is written in — and the iPad column,
    /// which has no `SidebarStaticDestination`, reads the shared spelling directly.
    static func colorHexMap(from raw: String) -> [SidebarStaticDestination: String] {
        CadenceSidebarTint.overrides(from: raw).reduce(into: [:]) { partial, entry in
            guard let destination = SidebarStaticDestination(rawValue: entry.key.rawValue) else { return }
            partial[destination] = entry.value
        }
    }

    static func rawColorString(from colors: [SidebarStaticDestination: String]) -> String {
        defaultOrder.compactMap { destination in
            guard let hex = colors[destination] else { return nil }
            return "\(destination.rawValue):\(hex)"
        }
        .joined(separator: ",")
    }

    func resolvedColorHex(from raw: String) -> String {
        SidebarStaticDestination.colorHexMap(from: raw)[self] ?? defaultColorHex
    }
}

extension CadenceFeatureDestination {
    /// The `SidebarStaticDestination` carrying this destination's Settings → Sidebar
    /// customisation — its visibility toggle, its place in the stored order, and its colour
    /// override — or `nil` for the destinations Settings does not offer a handle for.
    ///
    /// The two enums share raw values by construction; `SidebarStaticDestinationTests` pins that,
    /// because a rename on one side would silently turn every customisation into a default here.
    var sidebarStaticDestination: SidebarStaticDestination? {
        SidebarStaticDestination(rawValue: rawValue)
    }

    /// The macOS selection this destination navigates to, or `nil` for the ones the sidebar does
    /// not route to as a page (`.lists` is the scrolling region; `.search` is the header button).
    var macSidebarItem: SidebarItem? {
        switch self {
        case .today: return .today
        case .allTasks: return .allTasks
        case .focus: return .focus
        case .inbox: return .inbox
        case .calendar: return .calendar
        case .notes: return .notes
        case .goals: return .goals
        case .habits: return .habits
        case .settings: return .settings
        case .lists, .search: return nil
        }
    }

    /// The macOS selection a **deep link** resolving to this destination opens.
    ///
    /// **T-375(b): this used to walk `SidebarStaticDestination.allCases` and it silently narrowed
    /// the answer.** That table is the set of rows Settings → Sidebar offers a handle for — six
    /// cases — not the set of pages the app has. So `.notes`, `.inbox` and `.settings` found no
    /// match and fell through the `?? .today` to Today: not a crash, not a log line, just a link
    /// opening the wrong page. It was correct only because no resolver returned one of those three
    /// yet, which is a fact about today's `resolvedDestination` rather than about this mapping.
    ///
    /// `macSidebarItem` is the sidebar's real feature-to-page table and answers all nine. The
    /// fallback survives for the two destinations that genuinely are not pages — `.lists` is the
    /// scrolling region and `.search` is the header button — and `CadenceDeepLinkTests` pins each
    /// case by name, so widening the resolver can no longer route somewhere quiet by default.
    var deepLinkSidebarItem: SidebarItem {
        macSidebarItem ?? .today
    }
}

/// Fixed geometry for the single sidebar column: app header, nav rows, the scrolling
/// lists region, and the pinned bottom group all size off these values.
///
/// The sidebar used to be an icon rail plus a separate lists panel; it is now one
/// column, so this is the only place row height, glyph size, and inset are decided.
/// Nav glyphs deliberately inherit the old rail's sizing judgment — a large, legible
/// icon rather than the 12–13pt used by list rows — because nav is the primary
/// affordance in this column. `iconSize` and `iconSlotWidth` move together: growing the
/// glyph past the slot pushes labels out of alignment with each other.
enum SidebarMetrics {
    // MARK: Column

    static let horizontalInset: CGFloat = 10
    /// The column starts below this inset so its first row clears the window's traffic
    /// lights and the floating Cmd+O sidebar toggle, both drawn over the top-left corner
    /// of the content view (`.fullSizeContentView`).
    static let topInset: CGFloat = 46
    static let bottomInset: CGFloat = 10

    // MARK: App header

    static let appMarkSize: CGFloat = 24
    static let appMarkCornerRadius: CGFloat = 7
    static let appMarkFallbackIconSize: CGFloat = 13
    static let appTitleFontSize: CGFloat = 15
    /// Sized so `appMarkSize + headerSpacing == iconSlotWidth + iconLabelSpacing`: the
    /// wordmark then starts on exactly the same x as every nav row label below it.
    static let headerSpacing: CGFloat = 6
    static let headerBottomSpacing: CGFloat = 12
    static let searchButtonSize: CGFloat = 26
    static let searchIconSize: CGFloat = 13

    // MARK: Nav rows

    /// Every figure below is `CadenceSidebarMetrics`', not this file's. The two sidebar columns
    /// had drifted in glyph size, label size, icon-to-label spacing, colour-bar height and
    /// due-date caption size; the shared type is where those are decided now, and this enum is the
    /// macOS spelling of it. Only `rowHeight` differs by surface, and only because a finger needs
    /// 44pt where a pointer does not.
    private static let shared = CadenceSidebarMetrics.metrics(for: .desktop)

    static let rowHeight: CGFloat = shared.rowHeight
    static let rowCornerRadius: CGFloat = shared.cornerRadius
    static let rowSpacing: CGFloat = shared.rowSpacing
    static let rowHorizontalPadding: CGFloat = shared.horizontalPadding
    static let iconSlotWidth: CGFloat = shared.iconSlotWidth
    static let iconSize: CGFloat = shared.iconSize
    static let iconLabelSpacing: CGFloat = shared.iconLabelSpacing
    static let labelFontSize: CGFloat = shared.labelFontSize
    static let secondaryIconOpacity: Double = shared.secondaryIconOpacity

    // MARK: Lists section

    /// The lists region shares the nav rows' left edge rather than indenting under its
    /// own heading. A list row carries **no glyph**: the list's colour is a 2pt bar drawn
    /// inside the row's own leading padding, so the name starts at
    /// `horizontalInset + listRowHorizontalPadding` — the same x as the context eyebrow
    /// above it, and the same x for every list whether or not it has a colour worth
    /// noticing. A dot would have had to sit *in* the text column and push the names off
    /// that line. These are derived from the nav values instead of restated so the two
    /// halves of the column can't drift apart again.
    static let listRowHorizontalPadding: CGFloat = SidebarMetrics.rowHorizontalPadding
    static let listIconLabelSpacing: CGFloat = SidebarMetrics.iconLabelSpacing
    static let listRowCornerRadius: CGFloat = SidebarMetrics.rowCornerRadius
    static let listRowSpacing: CGFloat = SidebarMetrics.rowSpacing
    /// Only the empty-state "Add first list" button still draws a glyph in this region.
    static let listIconSize: CGFloat = 12
    static let listLabelFontSize: CGFloat = shared.listLabelFontSize
    static let listRowVerticalPadding: CGFloat = 7
    /// Minimum gap between a truncating list name and its trailing metadata.
    static let listTrailingGap: CGFloat = 8
    /// Gap between the trailing due-date flag and the trailing count.
    static let listTrailingItemSpacing: CGFloat = shared.listTrailingItemSpacing

    // MARK: List colour bar

    /// Narrow enough to read as an edge marker rather than a swatch. Sits in the row's
    /// leading padding, clear of both the rounded corners and the first letter of the name.
    static let listColorBarWidth: CGFloat = shared.listColorBarWidth
    static let listColorBarHeight: CGFloat = shared.listColorBarHeight
    static let listColorBarLeadingInset: CGFloat = shared.listColorBarLeadingInset

    // MARK: Context headers

    /// The sidebar's context header *is* the app's eyebrow, so it reads the eyebrow rather than
    /// re-typing it. These were a literal `10` and `0.8` (T-284) — the same two numbers
    /// `SectionEyebrowLabel` has published all along, and `SettingsViewSupport`'s group header
    /// already chains off this pair.
    static let contextHeaderFontSize: CGFloat = SectionEyebrowLabel.Size.standard.fontSize
    static let contextHeaderKerning: CGFloat = SectionEyebrowLabel.Size.standard.kerning
    static let contextHeaderTopPadding: CGFloat = 3
    static let contextHeaderBottomSpacing: CGFloat = 6
    static let contextSectionBottomSpacing: CGFloat = 8
    static let contextAddButtonSize: CGFloat = 16
    static let contextAddIconSize: CGFloat = 9

    // MARK: List due-date flag

    static let listDueDateIconSize: CGFloat = shared.listDueDateIconSize
    static let listDueDateFontSize: CGFloat = shared.listDueDateFontSize
    static let listDueDateSpacing: CGFloat = shared.listDueDateSpacing

    // MARK: Counts

    /// Counts are bare digits, not filled capsules, and both platforms draw them with the same
    /// `CadenceSidebarCountLabel` — the size lives in `CadenceSidebarCountMetrics`, not here,
    /// because a per-platform sidebar metrics enum is exactly where the 11-against-12 fork was.
    ///
    /// Minimum gap held between a row's truncating label and its count. The count is
    /// fixed-size and wins layout priority, so this is the point at which the *label*
    /// starts truncating — a three-digit count never overlaps it.
    static let badgeLeadingGap: CGFloat = shared.badgeLeadingGap

    // MARK: Group separation

    static let groupSpacing: CGFloat = shared.groupSpacing
    /// The footer row's two glyph plates. Square, and smaller than a full nav row: these are the
    /// column's two quietest destinations and the row exists to spend less height on them.
    static let footerGlyphSize: CGFloat = 28
    static let contextSectionSpacing: CGFloat = shared.sectionSpacing
    static let dividerInset: CGFloat = 2
}

/// One navigation row. Modelled as a value type rather than a
/// `SidebarStaticDestination` so Notes and Settings — which have no static-destination
/// case, and therefore no hide toggle or color override in Settings — can sit in the nav
/// groups alongside the destinations that do.
struct SidebarNavItem: Identifiable {
    let id: String
    let item: SidebarItem
    let icon: String
    let label: String
    let tint: Color
    let count: CadenceSidebarCount?
    let accessibilityID: String
}
#endif
