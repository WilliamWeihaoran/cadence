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
        var persisted = false
        macOSRootLifecycleSupport.toggleSidebar(columnVisibility: &visibility, focusHidSidebar: &focusHid, persistedSidebarHidden: &persisted)
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
        var persisted = false
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
        macOSRootLifecycleSupport.toggleSidebar(columnVisibility: &visibility, focusHidSidebar: &focusHid, persistedSidebarHidden: &persisted)
        macOSRootLifecycleSupport.handleSelectionChange(newValue: .settings, columnVisibility: &visibility, focusHidSidebar: &focusHid)
        #expect(visibility == .detailOnly)
    }

    @Test func aUserToggleInsideFocusTakesTheSidebarBack() {
        var visibility: NavigationSplitViewVisibility = .all
        var focusHid = false
        var persisted = false
        macOSRootLifecycleSupport.handleFocusRunningChange(
            isRunning: true,
            selection: .focus,
            columnVisibility: &visibility,
            focusHidSidebar: &focusHid
        )
        // Show, then hide again by hand: the standing hide is now the user's.
        macOSRootLifecycleSupport.toggleSidebar(columnVisibility: &visibility, focusHidSidebar: &focusHid, persistedSidebarHidden: &persisted)
        macOSRootLifecycleSupport.toggleSidebar(columnVisibility: &visibility, focusHidSidebar: &focusHid, persistedSidebarHidden: &persisted)
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
    // MARK: - [[T-18163]]: the user's fold survives a relaunch; Focus's does not

    @Test func theUsersToggleIsWhatPersists() {
        var visibility: NavigationSplitViewVisibility = .all
        var focusHid = false
        var persisted = false
        macOSRootLifecycleSupport.toggleSidebar(columnVisibility: &visibility, focusHidSidebar: &focusHid, persistedSidebarHidden: &persisted)
        #expect(visibility == .detailOnly)
        #expect(persisted, "hiding the sidebar by hand was not stored for the next launch")
        macOSRootLifecycleSupport.toggleSidebar(columnVisibility: &visibility, focusHidSidebar: &focusHid, persistedSidebarHidden: &persisted)
        #expect(visibility == .all)
        #expect(!persisted, "showing the sidebar by hand left the stored hide standing")
    }

    @Test func focussOwnHideIsNeverStored() throws {
        var visibility: NavigationSplitViewVisibility = .all
        var focusHid = false
        var persisted = false
        macOSRootLifecycleSupport.handleFocusRunningChange(
            isRunning: true,
            selection: .focus,
            columnVisibility: &visibility,
            focusHidSidebar: &focusHid
        )
        #expect(visibility == .detailOnly, "non-vacuity: Focus did not hide the sidebar")
        // A relaunch now must come back with the sidebar the user left: shown.
        try withTemporaryDefaults("cadence.tests.mac-sidebar-fold") { defaults in
            defaults.set(persisted, forKey: CadencePreferenceKeys.macSidebarHidden)
            #expect(macOSRootLifecycleSupport.launchColumnVisibility(store: defaults) == .all)
        }

        // A user toggle inside Focus shows it, and THAT is stored.
        macOSRootLifecycleSupport.toggleSidebar(columnVisibility: &visibility, focusHidSidebar: &focusHid, persistedSidebarHidden: &persisted)
        #expect(visibility == .all)
        #expect(!persisted)
    }

    @Test func aNewWindowOpensWithTheStoredFold() throws {
        try withTemporaryDefaults("cadence.tests.mac-sidebar-fold") { defaults in
            #expect(macOSRootLifecycleSupport.launchColumnVisibility(store: defaults) == .all, "an unset key must open the sidebar")
            defaults.set(true, forKey: CadencePreferenceKeys.macSidebarHidden)
            #expect(macOSRootLifecycleSupport.launchColumnVisibility(store: defaults) == .detailOnly)
            defaults.set(false, forKey: CadencePreferenceKeys.macSidebarHidden)
            #expect(macOSRootLifecycleSupport.launchColumnVisibility(store: defaults) == .all)
        }
    }

    /// The root view is what binds both values to storage, and a view cannot be driven headless, so
    /// this reads it: the toggle must be handed the stored bool, the column state must be seeded
    /// from it, and the timeline panel must be the `@AppStorage` value itself.
    @Test func theRootViewBindsBothChoicesToStorage() throws {
        let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile("Cadence/macOS/macOSRootView.swift"))
        #expect(source.contains("@AppStorage(CadencePreferenceKeys.macSidebarHidden) private var persistedSidebarHidden"))
        #expect(source.contains("persistedSidebarHidden: &persistedSidebarHidden"))
        #expect(source.contains("columnVisibility: NavigationSplitViewVisibility = macOSRootLifecycleSupport.launchColumnVisibility()"))
        #expect(source.contains("@AppStorage(CadencePreferenceKeys.macTimelinePanelShown) private var showTimelineSidebar"))
        #expect(!source.contains("@State private var showTimelineSidebar"))
    }
}
#endif
