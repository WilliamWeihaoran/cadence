#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import Cadence

/// [[T-18162]]: `macOSRootView.refreshAppData()` re-identifies the whole main shell with
/// `.id(dataRefreshID)` on every out-of-process write, which reset every page's `@State` -- the
/// Notes tab and its open note, the Settings category, the Calendar month. Those values now live
/// in `macOSRootRetainedPageState`, above the `.id()`, read through `@RootRetained`.
///
/// The hosted tests stand up the same shape: a child under `.id(generation)`, re-identified by
/// swapping the host's root view, which is what bumping `dataRefreshID` does.
@MainActor
final class RetainedProbeRecorder {
    var appearances: [Int] = []
}

private struct RetainedProbeChild: View {
    let recorder: RetainedProbeRecorder
    @RootRetained("probe.value") private var value: Int = 0

    var body: some View {
        Text("probe")
            .onAppear {
                recorder.appearances.append(value)
                if value == 0 { value = 7 }
            }
    }
}

private struct RetainedProbeRoot: View {
    let generation: Int
    let scope: macOSRootRetainedPageScope?
    let recorder: RetainedProbeRecorder

    var body: some View {
        RetainedProbeChild(recorder: recorder)
            .id(generation)
            .environment(\.cadenceRootRetainedPageScope, scope)
    }
}

@MainActor
struct CadenceRootRetainedPageStateTests {
    private func settle<V: View>(_ host: NSHostingView<V>) async throws {
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        host.layoutSubtreeIfNeeded()
    }

    private func hosted<V: View>(_ view: V) -> (NSHostingView<V>, NSWindow) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 200, height: 60)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        return (host, window)
    }

    /// Mounts the probe, re-identifies it once, and answers what each appearance read.
    private func appearancesAcrossOneRebuild(scope: macOSRootRetainedPageScope?) async throws -> [Int] {
        let recorder = RetainedProbeRecorder()
        let (host, window) = hosted(RetainedProbeRoot(generation: 0, scope: scope, recorder: recorder))
        defer { window.contentView = nil; window.close() }
        try await settle(host)
        host.rootView = RetainedProbeRoot(generation: 1, scope: scope, recorder: recorder)
        try await settle(host)
        return recorder.appearances
    }

    /// The fix: a value written before the rebuild is what the rebuilt view reads.
    @Test func aRetainedValueSurvivesTheRootsIdentityRebuild() async throws {
        let store = macOSRootRetainedPageState()
        let scope = macOSRootRetainedPageScope(store: store, scope: macOSRootRetainedPageState.scope(for: .notes))
        let appearances = try await appearancesAcrossOneRebuild(scope: scope)
        #expect(appearances == [0, 7])
    }

    /// Non-vacuity, and the defect: with no root store the wrapper is plain `@State`, and the same
    /// rebuild hands the second appearance the default again -- the Notes-back-to-Today reset.
    @Test func withoutTheRootStoreTheRebuildResetsTheValueLikeState() async throws {
        let appearances = try await appearancesAcrossOneRebuild(scope: nil)
        #expect(appearances == [0, 0])
    }

    /// Leaving a page drops its values (the root does this on a selection change), so coming back
    /// opens it on its defaults as before; another page's values are untouched.
    @Test func removingAScopeDropsOnlyThatPagesValues() {
        let store = macOSRootRetainedPageState()
        let notes = macOSRootRetainedPageState.scope(for: .notes)
        let settings = macOSRootRetainedPageState.scope(for: .settings)
        store.box(for: "notes.page", in: notes).stored = .init(value: 3)
        store.box(for: "settings.category", in: settings).stored = .init(value: 5)
        #expect(store.storedKeyCount == 2)

        store.removeValues(in: notes)

        #expect(store.box(for: "notes.page", in: notes).stored == nil)
        #expect(store.box(for: "settings.category", in: settings).stored?.value as? Int == 5)
    }

    /// A Notes tab change drops the tabs' selections and keeps the tab itself.
    @Test func removingAKeyPrefixKeepsTheScopesOtherValues() {
        let store = macOSRootRetainedPageState()
        let notes = macOSRootRetainedPageState.scope(for: .notes)
        store.box(for: "notes.page", in: notes).stored = .init(value: 1)
        store.box(for: NotesView.retainedSelectionPrefix + "daily", in: notes).stored = .init(value: 2)
        store.box(for: NotesView.retainedSelectionPrefix + "weekly", in: notes).stored = .init(value: 3)

        store.removeValues(in: notes, keyPrefix: NotesView.retainedSelectionPrefix)

        #expect(store.box(for: "notes.page", in: notes).stored?.value as? Int == 1)
        #expect(store.box(for: NotesView.retainedSelectionPrefix + "daily", in: notes).stored == nil)
        #expect(store.box(for: NotesView.retainedSelectionPrefix + "weekly", in: notes).stored == nil)
    }

    /// Two lists are two root pages, so one list's open note never leaks into another's.
    @Test func distinctListsAreDistinctScopes() {
        let a = UUID(), b = UUID()
        #expect(macOSRootRetainedPageState.scope(for: .area(a)) != macOSRootRetainedPageState.scope(for: .area(b)))
        #expect(macOSRootRetainedPageState.scope(for: .area(a)) != macOSRootRetainedPageState.scope(for: .project(a)))
    }

    /// A refresh waits while any window has a sheet attached (the Edit List sheet, a dialog).
    @Test func aRefreshIsDeferredOnlyWhileASheetIsAttached() {
        let parent = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        sheet.isReleasedWhenClosed = false
        defer { parent.close(); sheet.close() }

        #expect(!macOSRootDataRefreshSupport.shouldDeferRefresh(windows: [parent]))
        parent.beginSheet(sheet, completionHandler: nil)
        #expect(parent.attachedSheet === sheet, "non-vacuity: the sheet must really be attached")
        #expect(macOSRootDataRefreshSupport.shouldDeferRefresh(windows: [parent]))
        parent.endSheet(sheet)
        #expect(!macOSRootDataRefreshSupport.shouldDeferRefresh(windows: [parent]))
    }
}
#endif
