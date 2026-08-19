#if os(macOS)
import SwiftUI

let todayPanelHeaderHeight: CGFloat = 100

/// Name only. See `DesktopPageHeader`, which this is the `.pane`-role spelling of.
///
/// The name survives because "panel header" is what the header of one of Today's three columns is,
/// and because its callers — the notepad, the task column and the schedule — are exactly that.
/// It set its title at the full page size, so Today drew three column headings at the volume the
/// Inbox uses for the whole screen, on the one page that has no page title above them at all.
/// iPad Today's task column had the same bug and is already `.pane`; this is the same fix.
///
/// `background: nil` because the hosts paint their own plate behind the header band.
struct PanelHeader: View {
    let eyebrow: String
    let title: String

    var body: some View {
        DesktopPageHeader(
            role: .pane,
            eyebrow: eyebrow,
            title: title,
            background: nil,
            spreads: false
        )
    }
}
#endif
