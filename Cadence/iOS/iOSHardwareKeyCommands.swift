#if os(iOS)
import SwiftUI

/// **[[T-17173]] — the Mac's Cmd-keys on an iPad hardware keyboard, beyond Cmd+K and Cmd+N.**
///
/// A hardware keyboard is the same input on both platforms, so under [[T-8201]] a Mac key with an
/// iPad equivalent is bound here too. Each key is bound by the surface that owns the state it
/// changes, the way Cmd+K and Cmd+N are bound by `iOSRootView` ([[T-8766]], [[T-13281]]):
///
/// - Cmd+, (the Mac's Cadence > Settings…) by `iOSRootView`, which owns both shells' navigation.
/// - Cmd+O (View > Toggle Sidebar) by `iPadMacStyleRootShell`, which owns the fold and the drawer.
///   The compact shell has no sidebar to fold -- a tab bar on a narrow width -- so the key is bound
///   only where a sidebar is drawn.
/// - Cmd+\ (View > Toggle Timeline) by `iOSTodayView`'s two-pane layout, the one iPad surface that
///   shows a timeline beside a page: it flips that inspector pane between Notes and Timeline. The
///   iPad has no timeline overlay over other pages, so the key is bound nowhere else. The iPadOS
///   menu bar does not list these keys -- no `Commands` value is attached to the iPad scene
///   ([[T-18278]]).
///
/// The titles are the Mac items' own, so the Cmd-hold overlay lists what the Mac's menu does.
/// Each key rides on the same zero-size, transparent button Cmd+K and Cmd+N use rather than
/// `.hidden()`, which can drop a button's shortcut. None of them is Return or Escape, so none
/// competes with a composer's own Cmd+Return / Escape layer ([[T-18083]]); and like Cmd+K and
/// Cmd+N they are reached through the responder chain, so a key typed in a text field that does
/// not bind it still arrives. The note editor's key table binds none of the three.
enum iOSHardwareKeyCommand {
    static let settingsTitle = "Settings"
    static let settingsKey: Character = ","
    static let toggleSidebarTitle = "Toggle Sidebar"
    static let toggleSidebarKey: Character = "o"
    static let toggleTimelineTitle = "Toggle Timeline"
    static let toggleTimelineKey: Character = "\\"
}

extension View {
    /// Binds Cmd+`key` to `action` through a zero-size, transparent button titled `title`.
    func iOSCommandKey(_ title: String, key: Character, action: @escaping () -> Void) -> some View {
        background {
            Button(title, action: action)
                .keyboardShortcut(KeyEquivalent(key), modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }
}

extension iOSTodaySidePanel {
    /// Cmd+\ on the two-pane Today ([[T-17173]]): Timeline when Notes is up, Notes when Timeline is.
    var togglingTimeline: iOSTodaySidePanel {
        self == .timeline ? .notes : .timeline
    }
}
#endif
