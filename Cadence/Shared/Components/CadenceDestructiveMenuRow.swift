import SwiftUI

/// **[[T-11752]] — a destructive menu row agrees with itself.**
///
/// A `Button(role: .destructive)` inside a `.contextMenu` has its TITLE tinted red by the role, but
/// its glyph is drawn in the inherited tint, and the iOS root installs `.tint(Theme.blue)`. So a
/// saved link's long-press menu drew a blue `trash` beside a red "Delete": one row disagreeing
/// with itself about what it is. The Edit Project / Edit Area sheets already draw their delete
/// row's glyph in the label's red; this is the menu spelling of that one decision, so no call site
/// names the colour itself.
///
/// Applied to the destructive row of every row menu on both platforms (T-8201: one app). Where a
/// platform's menu already draws the glyph in the title's colour, the tint changes nothing.
private struct CadenceDestructiveMenuRow: ViewModifier {
    func body(content: Content) -> some View {
        content.tint(Theme.red)
    }
}

extension View {
    /// Tints a destructive menu row's glyph with its title. Apply to the `Button(role: .destructive)`.
    func cadenceDestructiveMenuRow() -> some View {
        modifier(CadenceDestructiveMenuRow())
    }
}
