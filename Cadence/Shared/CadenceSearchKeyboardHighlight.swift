import SwiftUI

/// **The one arrow-key walk over a search result list** ([[T-11196]] (2)), shared by Cmd+K on the
/// Mac (`GlobalSearchOverlayStateSupport`) and iOS Search on an iPad with a hardware keyboard
/// (`iOSSearchView`).
///
/// Both lists are walked as an ordered list of string ids -- results, plus a capped section's
/// "N more results" row where it is drawn ([[T-4320]]) -- so the rule is stated once over ids and
/// each platform maps its own row type onto them. The Mac's copy of this walk lived on
/// `GlobalSearchOverlayStateSupport` behind `#if os(macOS)` and took AppKit's
/// `MoveCommandDirection`, which iOS does not have; it forwards here now.
nonisolated enum CadenceSearchKeyboardHighlight {
    enum Step: Equatable {
        case up
        case down
    }

    /// A continuation row's highlight id: `continuation-<section id>`, a prefix no
    /// `CadenceSearchIdentity` kind uses, so it cannot collide with a result's.
    static func continuationID(forSection sectionID: String) -> String {
        "continuation-\(sectionID)"
    }

    /// One step from `currentID`, clamped at both ends. An id that is not in the list walks from
    /// the top, which is the Mac palette's long-standing answer.
    static func moved(_ step: Step, currentID: String?, ids: [String]) -> String? {
        guard !ids.isEmpty else { return nil }
        let currentIndex = ids.firstIndex(where: { $0 == currentID }) ?? 0
        switch step {
        case .down:
            return ids[min(currentIndex + 1, ids.count - 1)]
        case .up:
            return ids[max(currentIndex - 1, 0)]
        }
    }

    /// Keeps the highlight on a row that still exists, else the first row.
    static func synced(current: String?, ids: [String]) -> String? {
        guard !ids.isEmpty else { return nil }
        if let current, ids.contains(current) {
            return current
        }
        return ids.first
    }

    /// **iOS's walk: no highlight until the keyboard asks for one.** A touch screen has no
    /// highlight to show, so iOS Search starts with none; the first arrow press lands on the first
    /// row rather than stepping past it, and after that it is `moved(_:currentID:ids:)` exactly.
    /// A highlight whose row has gone is re-synced; an absent one stays absent.
    static func engagedMove(_ step: Step, currentID: String?, ids: [String]) -> String? {
        guard let currentID, ids.contains(currentID) else { return ids.first }
        return moved(step, currentID: currentID, ids: ids)
    }

    /// What Return acts on when no row is highlighted yet: the first, as Cmd+K's always-synced
    /// highlight would have been.
    static func submitTarget(highlightedID: String?, ids: [String]) -> String? {
        synced(current: highlightedID, ids: ids)
    }
}

/// **The one highlight plate a search row draws** -- the row's own tint at 0.09 under a 0.18
/// hairline, at radius 12 -- shared by Cmd+K's rows and iOS Search's rows ([[T-11196]] (2)), so
/// the keyboard highlight reads the same on both platforms.
struct CadenceSearchHighlightPlate: ViewModifier {
    static let cornerRadius: CGFloat = 12

    let isHighlighted: Bool
    let tint: Color

    func body(content: Content) -> some View {
        content
            .background(isHighlighted ? tint.opacity(0.09) : Color.clear)
            .overlay {
                RoundedRectangle(cornerRadius: Self.cornerRadius)
                    .strokeBorder(isHighlighted ? tint.opacity(0.18) : Color.clear, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
    }
}

extension CadenceSearchResultCap {
    /// **The "N more results" row's tint, read by both search surfaces** ([[T-12601]], under
    /// [[T-8201]]): its chevron, its label and its keyboard highlight plate. Neutral, because the
    /// row is not a result and must not read as one ([[T-4320]], the Mac's argued reading). iOS
    /// drew it in `Theme.blue` with no reason given; an iPad's hardware-keyboard highlight is the
    /// exact case the neutral plate was argued for, and touch changes how the row is reached, not
    /// what it is.
    static let continuationTint: Color = Theme.dim
}

extension View {
    func cadenceSearchHighlightPlate(isHighlighted: Bool, tint: Color) -> some View {
        modifier(CadenceSearchHighlightPlate(isHighlighted: isHighlighted, tint: tint))
    }
}

/// **How iOS Search brings the keyboard highlight's ROW into view, not just its section**
/// ([[T-18659]]).
///
/// Each section is one `List` row (`iOSSearchResultGroup` draws its rows in one card), and a
/// `List`'s `scrollTo` reaches rows, not views inside one, so the only scroll target is the whole
/// group. A minimal-distance scroll to a group taller than the viewport does nothing once part of
/// it is on screen, and Down walked the highlight off the bottom of a 24-row Tasks card.
///
/// The group is still the target; what changes is the **anchor**. `scrollTo(id, anchor: f)`
/// lines the group's point at fraction `f` of its height up with the viewport's point at fraction
/// `f`, which puts the group's top at `-f * (groupHeight - viewportHeight)`. Solving that for the
/// row's top (scrolled up to) or bottom (scrolled down to) gives the minimal scroll that shows it.
nonisolated enum CadenceSearchRowScroll {
    enum Plan: Equatable {
        /// The row is already fully on screen: leave the list where it is.
        case none
        /// Scroll to the row's group with this anchor; `nil` is the minimal-distance scroll, which
        /// shows a group that fits the viewport whole.
        case group(anchor: UnitPoint?)
    }

    /// Breathing room kept between the row and the viewport's edge, which also absorbs the list
    /// row's own insets around the group.
    static let margin: CGFloat = 12

    /// - Parameters:
    ///   - rowTop/rowBottom: the row's edges in its group's own coordinates.
    ///   - groupTop: the group's top in viewport coordinates (0 is the viewport's top edge).
    static func plan(
        rowTop: CGFloat,
        rowBottom: CGFloat,
        groupTop: CGFloat,
        groupHeight: CGFloat,
        viewportHeight: CGFloat
    ) -> Plan {
        let topOnScreen = groupTop + rowTop
        let bottomOnScreen = groupTop + rowBottom
        if topOnScreen >= 0, bottomOnScreen <= viewportHeight { return .none }
        let overflow = groupHeight - viewportHeight
        guard overflow > 0 else { return .group(anchor: nil) }
        let fraction = bottomOnScreen > viewportHeight
            ? (rowBottom + margin - viewportHeight) / overflow
            : (rowTop - margin) / overflow
        return .group(anchor: UnitPoint(x: 0.5, y: min(max(fraction, 0), 1)))
    }
}
