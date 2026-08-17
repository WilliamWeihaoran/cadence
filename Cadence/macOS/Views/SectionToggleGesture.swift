#if os(macOS)
import SwiftUI

/// The double-click half of a collapse/expand header, shared by the three headers that have it:
/// `CollapsibleTaskGroupHeader` (TasksPanelSupportViews), `TasksPanelGroupHeader`
/// (TasksPanelSectionViews) and `TaskListGroupHeader` (ListDetailSupportViews). All three are a
/// `Button` whose action is the toggle *plus* a two-count tap gesture running the same toggle,
/// which reads like a duplicate until you measure it.
///
/// Measured with an in-process SwiftUI harness (synthetic `NSEvent`s through `NSApp.sendEvent`, so
/// real gesture arbitration runs), on both `.buttonStyle(.plain)` and a custom `ButtonStyle`:
///
/// | gesture      | Button alone      | Button + this modifier            |
/// |--------------|-------------------|-----------------------------------|
/// | single click | 1 toggle, instant | 1 toggle, ~1 double-click interval late |
/// | double click | **2 toggles**     | 1 toggle (the Button's action does not fire at all) |
///
/// So it is neither dead code nor a double-toggle bug: it is what stops a double-click from
/// collapsing a section and immediately re-expanding it — which looks like the click did nothing.
/// The price is that every *single* click waits out the system double-click interval before the
/// section moves. Keep the pair together; deleting the gesture restores the two-toggle flicker.
private struct SectionToggleDoubleClick: ViewModifier {
    let isEnabled: Bool
    let perform: () -> Void

    func body(content: Content) -> some View {
        content.onTapGesture(count: 2) {
            guard isEnabled else { return }
            perform()
        }
    }
}

extension View {
    /// Attach to a collapse/expand header `Button` whose own action is the same toggle.
    /// See `SectionToggleDoubleClick` for why both are needed.
    func sectionToggleDoubleClick(
        isEnabled: Bool = true,
        perform: @escaping () -> Void
    ) -> some View {
        modifier(SectionToggleDoubleClick(isEnabled: isEnabled, perform: perform))
    }
}
#endif
