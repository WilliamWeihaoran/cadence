#if os(macOS)
import SwiftUI

/// **[[T-18634]] — which edge of a Settings row a drag lands against.**
///
/// The Contexts and Sidebar panes drop the dragged row INTO the slot of the row dropped on
/// ([[T-18630]]: `CadenceOrderReassignment.moved(_:_:onto:)`, `order(in:moving:onto:)`), so a
/// downward drag lands after the target and an upward one before it. Both rows used to wash the
/// whole target blue, which says nothing about that. They now draw the sidebar's 2pt insertion
/// line on the edge the dragged row will sit against.
///
/// The edge is read off the order the pane will DRAW once the drop is written, computed by the
/// same call the drop writes through -- so the line cannot promise a place the drop does not put
/// the row. That matters for Focus: it takes a drop but sorts last as a footer glyph, so a nav row
/// dropped on it is drawn directly ABOVE it, not below as the plain index rule would say.
enum SettingsRowDropIndicator {
    /// The edge of `target` the dragged row sits against in `afterDrop`, or `nil` when the drop
    /// draws nothing new: no drag in flight, a payload the pane does not draw (a stale or foreign
    /// drag), the row onto itself, or a drop that leaves the drawn order as it is.
    static func edge<ID: Equatable>(
        dragged: ID?,
        target: ID,
        drawn: [ID],
        afterDrop: [ID]?
    ) -> SidebarListDropPlacement.Edge? {
        guard let dragged, dragged != target,
              let afterDrop, afterDrop != drawn,
              let index = afterDrop.firstIndex(of: dragged) else { return nil }
        if afterDrop.indices.contains(index + 1), afterDrop[index + 1] == target { return .top }
        if afterDrop.indices.contains(index - 1), afterDrop[index - 1] == target { return .bottom }
        return nil
    }

    /// The Sidebar pane's rows as Settings will draw them after `dragged` is dropped on `target`:
    /// `order(in:moving:onto:)`, the order `SettingsView.moveSidebarTab` writes, read back through
    /// `orderedCustomisableDestinations`, the order the pane draws.
    static func sidebarTabs(
        afterDropping dragged: SidebarStaticDestination,
        onto target: SidebarStaticDestination,
        in layout: CadenceSidebarLayoutPreferenceStore.Layout
    ) -> [SidebarStaticDestination]? {
        guard let order = CadenceSidebarLayoutPreferenceStore.order(
            in: layout,
            moving: dragged.feature,
            onto: target.feature
        ) else { return nil }
        return CadenceSidebarLayoutPreferenceStore
            .orderedCustomisableDestinations(for: .init(order: order, hidden: layout.hidden))
            .compactMap(\.sidebarStaticDestination)
    }
}

/// The payload of the Settings row drag in flight. `.dropDestination(isTargeted:)` does not say
/// what is being dragged, so the source records it as the drag starts -- `.draggable`'s payload is
/// an autoclosure SwiftUI evaluates when the drag begins -- the way `SidebarDragContext` does for
/// the sidebar.
///
/// SwiftUI never says when a drag ends without a drop ([[T-7701]]), so this is a hint for the
/// line only: every drop on a row clears it, the next drag replaces it, and the drop itself reads
/// the payload it was handed, never this.
final class SettingsRowDragContext {
    static let shared = SettingsRowDragContext()
    private(set) var draggedPayload: String?

    /// Records `payload` as the drag in flight and hands it back as the drag's payload.
    func begin(_ payload: String) -> String {
        draggedPayload = payload
        return payload
    }

    func end() {
        draggedPayload = nil
    }
}

/// The sidebar's 2pt insertion line on one edge of a row, or nothing.
struct SettingsRowDropLine: View {
    let edge: SidebarListDropPlacement.Edge?

    var body: some View {
        if let edge {
            VStack(spacing: 0) {
                if edge == .bottom { Spacer(minLength: 0) }
                Rectangle().fill(Theme.blue).frame(height: 2)
                if edge == .top { Spacer(minLength: 0) }
            }
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }
}
#endif
