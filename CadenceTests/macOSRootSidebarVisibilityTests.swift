#if os(macOS)
import SwiftUI
import Testing
@testable import Cadence

/// **[[T-14432]]: a sidebar the user hid stays hidden across page changes; only Focus's own
/// auto-hide is undone on the way out of Focus.**
///
/// `handleSelectionChange` used to set `.all` for any page but Focus, so Cmd+O's hide came back on
/// Cmd+, or a Cmd+K jump. These drive the same static entry points `macOSRootView` calls, with the
/// same two `@State` values threaded through.
@MainActor
struct macOSRootSidebarVisibilityTests {
    @Test func aSidebarTheUserHidStaysHiddenOnAPageChange() {
        var visibility: NavigationSplitViewVisibility = .all
        var focusHid = false
        macOSRootLifecycleSupport.toggleSidebar(columnVisibility: &visibility, focusHidSidebar: &focusHid)
        #expect(visibility == .detailOnly, "non-vacuity: the toggle did not hide the sidebar")

        for page: SidebarItem? in [.settings, .today, .notes, nil] {
            macOSRootLifecycleSupport.handleSelectionChange(
                newValue: page,
                columnVisibility: &visibility,
                focusHidSidebar: &focusHid
            )
            #expect(visibility == .detailOnly, "a page change to \(String(describing: page)) undid the user's hide")
        }
    }

    @Test func leavingFocusUndoesFocussOwnHideOnce() {
        var visibility: NavigationSplitViewVisibility = .all
        var focusHid = false
        macOSRootLifecycleSupport.handleFocusRunningChange(
            isRunning: true,
            selection: .focus,
            columnVisibility: &visibility,
            focusHidSidebar: &focusHid
        )
        #expect(visibility == .detailOnly)
        #expect(focusHid)

        // Staying on Focus keeps it hidden; leaving brings it back.
        macOSRootLifecycleSupport.handleSelectionChange(newValue: .focus, columnVisibility: &visibility, focusHidSidebar: &focusHid)
        #expect(visibility == .detailOnly)
        macOSRootLifecycleSupport.handleSelectionChange(newValue: .today, columnVisibility: &visibility, focusHidSidebar: &focusHid)
        #expect(visibility == .all)
        #expect(!focusHid, "the restore did not spend the flag")

        // Spent: a later user hide is the user's.
        macOSRootLifecycleSupport.toggleSidebar(columnVisibility: &visibility, focusHidSidebar: &focusHid)
        macOSRootLifecycleSupport.handleSelectionChange(newValue: .settings, columnVisibility: &visibility, focusHidSidebar: &focusHid)
        #expect(visibility == .detailOnly)
    }

    @Test func aUserToggleInsideFocusTakesTheSidebarBack() {
        var visibility: NavigationSplitViewVisibility = .all
        var focusHid = false
        macOSRootLifecycleSupport.handleFocusRunningChange(
            isRunning: true,
            selection: .focus,
            columnVisibility: &visibility,
            focusHidSidebar: &focusHid
        )
        // Show, then hide again by hand: the standing hide is now the user's.
        macOSRootLifecycleSupport.toggleSidebar(columnVisibility: &visibility, focusHidSidebar: &focusHid)
        macOSRootLifecycleSupport.toggleSidebar(columnVisibility: &visibility, focusHidSidebar: &focusHid)
        #expect(visibility == .detailOnly)
        macOSRootLifecycleSupport.handleSelectionChange(newValue: .today, columnVisibility: &visibility, focusHidSidebar: &focusHid)
        #expect(visibility == .detailOnly)
    }

    @Test func focusHidingAnAlreadyHiddenSidebarDoesNotClaimIt() {
        var visibility: NavigationSplitViewVisibility = .detailOnly
        var focusHid = false
        macOSRootLifecycleSupport.handleFocusRunningChange(
            isRunning: true,
            selection: .focus,
            columnVisibility: &visibility,
            focusHidSidebar: &focusHid
        )
        #expect(!focusHid, "Focus claimed a hide the user had already made")
        macOSRootLifecycleSupport.handleSelectionChange(newValue: .today, columnVisibility: &visibility, focusHidSidebar: &focusHid)
        #expect(visibility == .detailOnly)
    }

    @Test func aFocusSessionOffTheFocusPageHidesNothing() {
        var visibility: NavigationSplitViewVisibility = .all
        var focusHid = false
        macOSRootLifecycleSupport.handleFocusRunningChange(
            isRunning: true,
            selection: .today,
            columnVisibility: &visibility,
            focusHidSidebar: &focusHid
        )
        #expect(visibility == .all)
        #expect(!focusHid)
    }
}
#endif
