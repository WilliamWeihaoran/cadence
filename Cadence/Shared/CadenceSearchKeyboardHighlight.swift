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

extension View {
    func cadenceSearchHighlightPlate(isHighlighted: Bool, tint: Color) -> some View {
        modifier(CadenceSearchHighlightPlate(isHighlighted: isHighlighted, tint: tint))
    }
}
