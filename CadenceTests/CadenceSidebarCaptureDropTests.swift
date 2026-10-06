import Foundation
import Testing
@testable import Cadence

/// Drag-to-create, third half: what the **iPad sidebar** offers a dropped `+` (T-2054).
///
/// The owner: *"when i drag the blue + button onto the side bar lists, it should create a list
/// there… the blue add button on ios and ipados should create things with inherited context when
/// dragged into some region"*. Every other destination in the app implies a *task*; a context group
/// in the sidebar is the one region that implies a *list*, so "what is being created" became a
/// second answer a drop has to carry.
///
/// Two things are worth pinning and they are the two this suite is split into: that the key and the
/// creation it resolves to are inverses, and that only a **drop** can reach the list arm — a tap or
/// a palette segment consulting the drop key is exactly the page-seeding T-337 removed, and it
/// would compile and look reasonable.
///
/// The view layer under `Cadence/iOS/` is invisible to this target. What that layer does with these
/// values is pinned by a source scan at the bottom, which is how every other drop target in this
/// repo is held to the vocabulary it claims to speak.
@MainActor
struct CadenceSidebarCaptureDropTests {

    private let todayKey = "2026-10-04"

    // MARK: - The key and the creation are inverses

    /// The round trip, with **two rows**: a named group and the context-less one. One row alone
    /// would stay green with the `nil` arm deleted, because `UUID(uuidString:)` would simply fail
    /// and the function would answer `nil` either way — the one-candidate trap.
    @Test func aContextGroupsKeyRoundTripsBackToTheGroupItNames() {
        let work = UUID()

        let named = CadenceTaskDropSupport.newListDropKey(contextID: work)
        #expect(named == "newlist:\(work.uuidString)")
        #expect(CadenceTaskDropSupport.newListDrop(forDropKey: named)?.contextID == work)

        let ungrouped = CadenceTaskDropSupport.newListDropKey(contextID: nil)
        #expect(ungrouped == "newlist:none")
        let parsed = CadenceTaskDropSupport.newListDrop(forDropKey: ungrouped)
        #expect(parsed == CadenceTaskDropSupport.NewListDrop(contextID: nil))
    }

    /// **"No group" and "a group I cannot read" are different answers.** `newlist:none` is the
    /// catch-all region, which is a real destination; a `newlist:` naming something that is not a
    /// UUID is a key no call site produces, and resolving it to "no group" would quietly make a
    /// list in the wrong place rather than making none.
    @Test func anUnreadableContextGroupIsNotAListDropAtAll() {
        #expect(CadenceTaskDropSupport.newListDrop(forDropKey: "newlist:not-a-uuid") == nil)
        #expect(CadenceTaskDropSupport.newListDrop(forDropKey: "newlist:") == nil)
    }

    /// Every key the rest of the app already speaks still means a task. The `list:` row here is the
    /// control the empty-denominator trap needs: without it, a `newListDrop` that answered `nil` to
    /// *everything* would pass this suite's first half too.
    @Test func everyOrdinaryDropKeyStillMeansATask() {
        for key in ["list:inbox", "date:today", "list:a_\(UUID().uuidString)|section:Doing", ""] {
            #expect(CadenceTaskDropSupport.newListDrop(forDropKey: key) == nil, "\(key) read as a list drop")
        }
    }

    // MARK: - What a released press commits to

    /// A sidebar list **row** and a sidebar context **group** are two different commitments, and
    /// this asserts both from one release so neither can be read as the other.
    @Test func aGroupMakesAListWhileAListRowMakesATaskInIt() {
        let home = UUID()
        let area = UUID()

        let onGroup = CadenceCaptureSeedResolver.creation(
            for: .drop,
            dropKey: CadenceTaskDropSupport.newListDropKey(contextID: home),
            todayKey: todayKey
        )
        #expect(onGroup == .list(contextID: home))

        let onRow = CadenceCaptureSeedResolver.creation(
            for: .drop,
            dropKey: "list:\(CadenceTaskDropSupport.containerKey(for: .area(area)))",
            todayKey: todayKey
        )
        guard case .task(let seed) = onRow else {
            Issue.record("a list row stopped making a task")
            return
        }
        #expect(seed.container == .area(area))
    }

    /// **The T-337 reversal, as a value.** A `.tap` is a task wherever the finger was, and so is a
    /// palette segment: the button contributes nothing and only a *target* contributes anything.
    /// An arm here that consulted the key for a tap would compile and would look reasonable, which
    /// is the whole reason the outcome is an input rather than something the call site knows.
    @Test func onlyADroppedPressCanAskTheSidebarForAList() {
        let key = CadenceTaskDropSupport.newListDropKey(contextID: UUID())

        for outcome in [CadenceCapturePressOutcome.tap, .action(.task), .dismissed, .none] {
            let creation = CadenceCaptureSeedResolver.creation(for: outcome, dropKey: key, todayKey: todayKey)
            #expect(creation == .task(CadenceTaskComposerSeed()), "\(outcome) inherited a drop target")
        }

        // Non-vacuity: the same key *does* reach the list arm when the press was a drop.
        #expect(CadenceCaptureSeedResolver.creation(for: .drop, dropKey: key, todayKey: todayKey) != .task(CadenceTaskComposerSeed()))
    }

    /// A drag that came down on nothing is a tap that travelled — unchanged by any of this.
    @Test func aDropOnNothingStillMakesAnUnseededTask() {
        #expect(
            CadenceCaptureSeedResolver.creation(for: .drop, dropKey: nil, todayKey: todayKey)
                == .task(CadenceTaskComposerSeed())
        )
    }

    // MARK: - What the ghost says

    /// The ghost names what is about to exist, and it names the **group** rather than a task field.
    ///
    /// Running a `newlist:` key through `seed(forDropKey:)` resolves to a default
    /// `CadenceTaskComposerSeed`, whose container is `.inbox` — so without the branch the ghost
    /// would read "New list · Inbox", a task's field printed on a thing that is not a task. That is
    /// the mutation this asserts against.
    @Test func theSidebarGhostNamesTheGroupAndNotAnInbox() {
        let key = CadenceTaskDropSupport.newListDropKey(contextID: UUID())

        #expect(CadenceTaskDropSupport.ghostTitle(forDropKey: key) == "New list")
        #expect(CadenceTaskDropSupport.ghostTitle(forDropKey: "list:inbox") == "New task")

        let caption = CadenceTaskDropSupport.placementCaption(
            forDropKey: key,
            todayKey: todayKey,
            listName: "Work"
        )
        #expect(caption == "in Work")
        #expect(caption.contains("Inbox") == false)
    }

    /// The catch-all region promises nothing in words, because it has nothing to promise: a list in
    /// no group is what "Other" collects, and naming it would be inventing a group.
    @Test func theUngroupedSidebarRegionPromisesNoGroupInWords() {
        let caption = CadenceTaskDropSupport.placementCaption(
            forDropKey: CadenceTaskDropSupport.newListDropKey(contextID: nil),
            todayKey: todayKey,
            listName: ""
        )
        #expect(caption.isEmpty)
    }

    // MARK: - The three layers the sidebar actually registers

    /// **The sidebar is the ninth participant in the drop registry, and these are its three
    /// layers.** `CadenceCaptureDropHitTest` takes the smallest containing frame, so a row beats
    /// its section and a section beats the region without any registration order being arranged —
    /// which means the only thing a source scan has to hold is that all three are *declared*, and
    /// that each declares the key its level is entitled to.
    @Test func theSidebarRegistersARowASectionAndARegionTarget() throws {
        let code = CadenceSourceScan.codeOnly(try cadenceTestSource("Cadence/iOS/iOSRootSidebar.swift"))
        let region = try cadenceFunctionBody("struct iOSSidebarListsRegion: View", in: code)

        #expect(region.contains("iOSNewTaskDropTarget("), "non-vacuity: the region registers no drop target at all")
        // A row offers a task in its list, through the identity every other list row in the app uses.
        #expect(region.contains("group: .list(key: Self.dropListKey(for: item), name: item.name)"),
                "a sidebar list row stopped offering a task in its own list")
        // A context section offers a list in itself; the catch-all offers nothing.
        #expect(region.contains("CadenceTaskDropSupport.newListDropKey(contextID: contextID)"),
                "a context group stopped offering a new list in itself")
        // Spelled without the empty string the guard returns: `codeOnly` blanks literal contents,
        // so a needle that leaned on one would be asserting against the masker rather than the code.
        #expect(region.contains("guard let contextID = section.contextID else { return"),
                "the catch-all Other section now registers a target it cannot honour")
        // And the always-present outermost layer, which is what a fresh install has instead of sections.
        #expect(region.contains("CadenceTaskDropSupport.newListDropKey(contextID: nil)"),
                "the lists region stopped accepting a drop when it holds no sections — T-1113's shape")
    }

    /// **The other end of "inherited", and nothing held it.** Everything above pins the key and
    /// the `CadenceCaptureCreation` it resolves to; the sheet that key opens is where the group
    /// actually becomes a stored relationship, and a break at either of this test's two points
    /// looks *correct on screen* — which is the failure mode T-2054 was filed against.
    ///
    /// Two links, and each one alone is the whole feature:
    ///
    /// 1. `load()` has to copy `seededContext` into `selectedContextID`, or the editor opens on
    ///    "No context" and the group the finger came down on is simply discarded. The sheet still
    ///    appears, the list is still created, and it lands in no group.
    /// 2. `save()`'s `.newArea` arm has to construct the `Area` **with** `selectedContext`, or the
    ///    picker is decoration: it would state the dropped group, the user would see it stated,
    ///    and the row would appear under "Other".
    ///
    /// Both arms of `load()` are asserted rather than `.newArea` alone, because the remedy this
    /// ticket leaves open — one new-list mode with an Area/Project toggle — merges them, and a
    /// test that only knew about `.newArea` would go quiet over the half that moved.
    ///
    /// Scoped to the two declarations rather than counted over the file: a `selectedContext` that
    /// migrated from `save()` into some helper would keep a whole-file count green.
    @Test func theDroppedGroupReachesTheEditorAndThenTheStoredList() throws {
        let code = CadenceSourceScan.codeOnly(try cadenceTestSource("Cadence/iOS/iOSListEditorViews.swift"))

        let load = try cadenceFunctionBody("private func load()", in: code)
        #expect(load.contains("selectedContextID = seededContextValue"),
                "a dropped context group no longer reaches the list editor's own context control")
        // Non-vacuity, and the merge guard: today there are two new-list arms and both seed.
        #expect(load.components(separatedBy: "selectedContextID = seededContextValue").count - 1 == 2,
                "a new-list arm of the editor stopped seeding the dropped group")

        let save = try cadenceFunctionBody("private func save()", in: code)
        #expect(save.contains("Area(name: trimmedName, context: selectedContext"),
                "a list created from a sidebar drop no longer joins the group it was dropped on")

        // The seed is a starting point, not a constraint: the picker must still be able to
        // overrule it, which is what makes `selectedContextID` — rather than `seededContext` —
        // the value `save()` reads. A `save()` that read the seed directly would pass the line
        // above if it were spelled with `seededContext`, so the relationship is asserted here.
        #expect(!save.contains("seededContext"),
                "the editor's save path reads the drop's seed instead of the control the user can change")
    }
}
