import Foundation
import Testing
@testable import Cadence

/// [[T-18157]] and [[T-18158]]: what an iPad size-class swap may no longer throw away.
///
/// `iOSRootView` builds one of two whole shells from `horizontalSizeClass`, so a Split View or Stage
/// Manager resize across the compact/regular boundary destroys every view inside the shell. Two
/// things were lost with it: a half-typed composer presented by a host inside the shell
/// ([[T-18157]]), and the place inside Notes and Lists ([[T-18158]]). [[T-334]] / [[T-335]] are the
/// precedent: the state goes ABOVE the switch.
///
/// The carry is pinned behaviourally because it lives in `Shared/`. The wiring cannot be:
/// `Cadence/iOS/` is entirely inside `#if os(iOS)` and this target builds for macOS, so the second
/// suite reads source text and says so.
@MainActor
struct CadenceShellPlaceCarryTests {
    private let noteA = UUID()
    private let noteB = UUID()

    private func place(_ note: UUID?, tab: CadenceNotesTabVocabulary = .notepad, open: Bool = true) -> CadenceNotesShellPlace {
        CadenceNotesShellPlace(tab: tab, dayKey: "2026-11-10", noteID: note, isOpen: open)
    }

    /// The ticket's case: an older Notepad note open in the iPad pane, narrowed into compact and
    /// widened back. Each shell's page restores the other's place and re-records it at its own
    /// width, so the round trip hands back the note both ways.
    @Test func aNotesPlaceSurvivesARegularCompactRegularRoundTrip() throws {
        let carry = CadenceShellPlaceCarry()
        carry.recordNotes(place(noteA), isRegularWidth: true)

        let narrowed = carry.notesPlaceToRestore(isRegularWidth: false)
        #expect(narrowed == place(noteA), "narrowing lost the open note")
        // The compact page records where it now is -- the restored place.
        carry.recordNotes(try #require(narrowed), isRegularWidth: false)

        #expect(carry.notesPlaceToRestore(isRegularWidth: true) == place(noteA), "widening back lost the open note")
    }

    /// The other half of the rule: a page rebuilt at the SAME width (Notes, then Today, then Notes in
    /// one shell) restores nothing, so the header's documented per-visit Daily reset is untouched.
    @Test func aPageRebuiltAtTheSameWidthRestoresNothing() {
        let carry = CadenceShellPlaceCarry()
        carry.recordNotes(place(noteA), isRegularWidth: true)
        #expect(carry.notesPlaceToRestore(isRegularWidth: true) == nil)

        carry.recordNotes(place(noteB), isRegularWidth: false)
        #expect(carry.notesPlaceToRestore(isRegularWidth: false) == nil)
        #expect(carry.notesPlaceToRestore(isRegularWidth: true) == place(noteB), "the latest record must answer")
    }

    /// A fresh carry -- a launch -- restores nothing on either width.
    @Test func aFreshCarryRestoresNothing() {
        let carry = CadenceShellPlaceCarry()
        #expect(carry.notesPlaceToRestore(isRegularWidth: true) == nil)
        #expect(carry.notesPlaceToRestore(isRegularWidth: false) == nil)
        #expect(carry.listToRestore(isRegularWidth: true) == nil)
        #expect(carry.listToRestore(isRegularWidth: false) == nil)
    }

    /// Lists: the third list picked in the regular pane, narrowed (the compact form has no standing
    /// selection and passes it on) and widened back.
    @Test func aSelectedListSurvivesARegularCompactRegularRoundTrip() throws {
        let carry = CadenceShellPlaceCarry()
        let third = CadenceCarriedListRoute.project(UUID())
        carry.recordList(third, isRegularWidth: true)

        let narrowed = carry.listToRestore(isRegularWidth: false)
        #expect(narrowed == third)
        carry.recordList(try #require(narrowed), isRegularWidth: false)

        #expect(carry.listToRestore(isRegularWidth: true) == third, "widening back picked another list")
        #expect(carry.listToRestore(isRegularWidth: false) == nil)
    }

    /// The restored note is the carried one only while its tab still holds it; a note deleted in
    /// between leaves the page to its default rather than selecting a dangling id.
    @Test func aCarriedNoteIsSelectedOnlyWhileItsTabStillHoldsIt() {
        #expect(place(noteA).noteToSelect(amongTabNoteIDs: [noteB, noteA]) == noteA)
        #expect(place(noteA).noteToSelect(amongTabNoteIDs: [noteB]) == nil)
        #expect(place(nil).noteToSelect(amongTabNoteIDs: [noteB]) == nil)
    }

    /// "Open" in each of the three forms a Notes page takes. The two-column pane always stands a
    /// note beside the list, so there only a CHOSEN note counts -- otherwise every narrowing out of
    /// the default Daily note would throw a cover over the compact index.
    @Test func openMeansTheEditorTheFormActuallyShows() {
        // Compact: the cover or the event-note sheet, nothing else.
        #expect(CadenceNotesShellPlace.isOpen(isRegularWidth: false, layout: .oneColumn, compactEditorIsUp: true, inlineEditorIsShown: false, noteWasChosen: false))
        #expect(!CadenceNotesShellPlace.isOpen(isRegularWidth: false, layout: .oneColumn, compactEditorIsUp: false, inlineEditorIsShown: true, noteWasChosen: true))
        // Regular one-column: the inline editor.
        #expect(CadenceNotesShellPlace.isOpen(isRegularWidth: true, layout: .oneColumn, compactEditorIsUp: false, inlineEditorIsShown: true, noteWasChosen: false))
        #expect(!CadenceNotesShellPlace.isOpen(isRegularWidth: true, layout: .oneColumn, compactEditorIsUp: true, inlineEditorIsShown: false, noteWasChosen: true))
        // Regular two-column: a chosen note, not the default one.
        #expect(CadenceNotesShellPlace.isOpen(isRegularWidth: true, layout: .twoColumn, compactEditorIsUp: false, inlineEditorIsShown: false, noteWasChosen: true))
        #expect(!CadenceNotesShellPlace.isOpen(isRegularWidth: true, layout: .twoColumn, compactEditorIsUp: true, inlineEditorIsShown: true, noteWasChosen: false))
    }
}

/// The wiring half, read from source because `Cadence/iOS/` does not compile into this target.
@Suite
struct CadenceShellSwapWiringTests {
    private static func code(_ path: String) throws -> String {
        CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
    }

    /// The root's body and the `Group` that holds the two shells, so "above the switch" is a
    /// placement claim rather than a count.
    private static func rootBodyAndShells() throws -> (body: String, shells: String) {
        let root = try code("Cadence/iOS/iOSRootView.swift")
        let body = try cadenceFunctionBody("var body: some View", in: root)
        let shells = try cadenceFunctionBody("Group", in: body)
        #expect(shells.contains("iPadMacStyleRootShell(") && shells.contains("iOSCompactRootShell("),
                "the scan no longer reaches the two shells")
        return (body, shells)
    }

    /// [[T-18157]]: a placement's host presents nothing. Any `.sheet` or `.fullScreenCover` here is
    /// a composer whose lifetime is a shell's.
    @Test func aPlacementsCaptureHostForwardsAndPresentsNothing() throws {
        let source = try Self.code("Cadence/iOS/iOSCaptureRadialMenu.swift")
        let placement = try cadenceFunctionBody("private struct iOSCaptureHostModifier: ViewModifier", in: source)
        #expect(placement.contains("presenter.forward(request, onCreated: onCreated)"))
        for presentation in [".sheet(", ".fullScreenCover(", ".popover("] {
            #expect(!placement.contains(presentation), "the placement host presents \(presentation) again")
        }

        let host = try cadenceFunctionBody("private struct iOSCapturePresentationHostModifier: ViewModifier", in: source)
        #expect(host.contains(".sheet(item: $composer)"))
        #expect(host.contains(".fullScreenCover(item: $noteBeingCaptured)"))
        #expect(host.contains(".environment(presenter)"))
        // One host, one composer at a time: a second request must not swap the draft out.
        #expect(host.contains("guard composer == nil, noteBeingCaptured == nil else { return }"))
    }

    /// [[T-18157]]: the presenting host is mounted once in the iOS tree, on the root, above the
    /// size-class switch -- not inside either shell branch.
    @Test func theCapturePresentationHostIsMountedOnceAboveBothShells() throws {
        var perFile: [String: Int] = [:]
        for path in try CadenceSourceScan.swiftFiles(under: "Cadence/iOS") {
            let count = try Self.code(path).components(separatedBy: ".iOSCapturePresentationHost(").count - 1
            if count > 0 { perFile[(path as NSString).lastPathComponent] = count }
        }
        #expect(perFile == ["iOSRootView.swift": 1])

        let (body, shells) = try Self.rootBodyAndShells()
        for modifier in [
            ".iOSCapturePresentationHost(capturePresenter)",
            ".sheet(item: $sidebarListEditorRequest)",
            ".environment(placeCarry)"
        ] {
            #expect(body.contains(modifier), "iOSRootView's body no longer applies \(modifier)")
            #expect(!shells.contains(modifier), "\(modifier) is inside a shell branch, so a resize destroys it")
        }
        // The Cmd+N host forwards too, so it must sit inside the presenter's environment.
        let keyboard = try #require(body.range(of: ".iOSCaptureHost(keyboardCapture)"))
        let presentation = try #require(body.range(of: ".iOSCapturePresentationHost(capturePresenter)"))
        #expect(keyboard.upperBound <= presentation.lowerBound)
    }

    /// [[T-18157]]: the iPad sidebar's own list editor is presented by the root, not the shell.
    @Test func theSidebarShellPresentsNoListEditorOfItsOwn() throws {
        let shell = try Self.code("Cadence/iOS/iOSRootSidebar.swift")
        let body = try cadenceFunctionBody("struct iPadMacStyleRootShell<Content: View>: View", in: shell)
        #expect(body.contains("@Binding var listEditorRequest: iOSSidebarListEditorRequest?"))
        #expect(!body.contains(".sheet("), "the iPad shell presents a sheet a resize would dismiss")
    }

    /// [[T-18158]]: the two shells' Notes destinations opt in; Today's inspector does not.
    @Test func onlyTheShellsNotesPagesCarryTheirPlace() throws {
        let flag = "carriesPlaceAcrossShells: true"
        #expect(try Self.code("Cadence/iOS/iOSRootView.swift").components(separatedBy: flag).count - 1 == 1)
        #expect(try Self.code("Cadence/iOS/iOSCompactTabShell.swift").components(separatedBy: flag).count - 1 == 2)
        #expect(!(try Self.code("Cadence/iOS/iOSTodayView.swift").contains("carriesPlaceAcrossShells")))
    }

    /// [[T-18158]]: a rebuilt Notes page asks for the carried place BEFORE seeding its default, and
    /// both reseeding handlers yield to a pending restore.
    @Test func theNotesPageRestoresTheCarriedPlaceBeforeSeedingADefault() throws {
        let notes = try Self.code("Cadence/iOS/iOSNotesView.swift")
        let appear = try #require(notes.range(of: ".onAppear {").map { String(notes[$0.upperBound...].prefix(400)) })
        let restore = try #require(appear.range(of: "if let place = carriedPlaceToRestore() {"))
        let seed = try #require(appear.range(of: "selectDefaultNote()"))
        #expect(restore.upperBound <= seed.lowerBound)
        #expect(appear.contains("restore(place)"))

        let tabChange = try #require(notes.range(of: ".onChange(of: activeTab) { _, _ in").map { String(notes[$0.upperBound...].prefix(200)) })
        #expect(tabChange.contains("if let place = pendingCarriedPlace, place.tab == activeTab {"))
        let dayChange = try #require(notes.range(of: ".onChange(of: selectedDayKey) { _, _ in").map { String(notes[$0.upperBound...].prefix(200)) })
        #expect(dayChange.contains("if let place = pendingCarriedPlace, place.tab == activeTab, place.dayKey == selectedDayKey {"))
        #expect(notes.contains("placeCarry.recordNotes(shellPlace, isRegularWidth: shellIsRegular)"))
    }

    /// [[T-18158]]: Lists adopts the carried list on appear and records both forms' selections.
    @Test func theListsPageAdoptsAndRecordsTheCarriedList() throws {
        let lists = try Self.code("Cadence/iOS/iOSListViews.swift")
        let appear = try #require(lists.range(of: ".onAppear {").map { String(lists[$0.upperBound...].prefix(120)) })
        let adopt = try #require(appear.range(of: "adoptCarriedList()"))
        let seed = try #require(appear.range(of: "selectDefaultListIfNeeded()"))
        #expect(adopt.upperBound <= seed.lowerBound, "the default list is seeded before the carried one is adopted")
        #expect(lists.contains(".onAppear { recordList(route) }"))
        #expect(lists.contains("placeCarry?.recordList(route.carried, isRegularWidth: !isCompact)"))
    }
}
