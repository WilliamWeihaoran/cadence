import Foundation
import SwiftData
import Testing
@testable import Cadence

/// The synced sidebar layout: how it is stored, which row wins when two devices wrote one, what a
/// destination the stored strings have never heard of does, and where the selection goes when the
/// row under it is hidden (T-1274).
///
/// The layout became a `@Model` rather than an `@AppStorage` string because the owner answered the
/// ticket's one open question with *across devices*. That makes every rule here an account-wide
/// rule rather than a per-Mac one, which is why the duplicate-record and unknown-token cases are
/// pinned rather than left to whichever device reads first.
@MainActor
struct CadenceSidebarLayoutPreferenceTests {

    // MARK: - Parsing

    @Test func theStoredStringIsAListOfDestinationsWithoutDuplicatesOrStrangers() {
        let parse = CadenceSidebarLayoutPreferenceStore.destinations(fromRaw:)

        #expect(parse("today,calendar,notes") == [.today, .calendar, .notes])
        // A repeat keeps its first position: an order is a sequence of slots, not a multiset.
        #expect(parse("notes,today,notes") == [.notes, .today])
        // Unrecognised tokens are dropped rather than carried: this build cannot place a row it has
        // no case for. The cost is stated in `SidebarLayoutPreference`'s own note.
        #expect(parse("today,somethingNewer,notes") == [.today, .notes])
        // `goals` and `habits` are that case for real since T-2076 — they were rows in every build
        // before it, so the strings naming them are already synced. See
        // `aSyncedLayoutNamingRemovedDestinationsSurvivesIntact` for what that costs.
        #expect(parse("today,goals,habits") == [.today])
        #expect(parse("") == [])
        #expect(parse(" today , notes ") == [.today, .notes])
    }

    @Test func theRawStringRoundTripsAnOrder() {
        let order: [CadenceFeatureDestination] = [.calendar, .today, .notes]
        let raw = CadenceSidebarLayoutPreferenceStore.raw(from: order)

        #expect(raw == "calendar,today,notes")
        #expect(CadenceSidebarLayoutPreferenceStore.destinations(fromRaw: raw) == order)
    }

    // MARK: - Which record wins

    /// Two devices can each create a row before either has seen the other's, and there is no unique
    /// constraint to lean on — CloudKit forbids them. The newest edit wins, because that is what a
    /// person means by changing a preference on the device in front of them.
    @Test func theMostRecentlyUpdatedRowIsTheOneEveryDeviceReads() {
        let old = SidebarLayoutPreference(orderRaw: "today", updatedAt: Date(timeIntervalSince1970: 100))
        let recent = SidebarLayoutPreference(orderRaw: "calendar", updatedAt: Date(timeIntervalSince1970: 900))

        #expect(CadenceSidebarLayoutPreferenceStore.current(from: [old, recent])?.orderRaw == "calendar")
        #expect(CadenceSidebarLayoutPreferenceStore.current(from: [recent, old])?.orderRaw == "calendar")
        #expect(CadenceSidebarLayoutPreferenceStore.current(from: []) == nil)
    }

    /// The tie-break is the point: two devices reading the same pair must pick the *same* row, or
    /// each writes over the other forever.
    @Test func anExactTieIsBrokenByIdSoBothDevicesPickTheSameRow() {
        let moment = Date(timeIntervalSince1970: 500)
        let first = SidebarLayoutPreference(orderRaw: "today", updatedAt: moment)
        let second = SidebarLayoutPreference(orderRaw: "notes", updatedAt: moment)
        let winner = max(first.id.uuidString, second.id.uuidString) == first.id.uuidString ? first : second

        #expect(CadenceSidebarLayoutPreferenceStore.current(from: [first, second])?.id == winner.id)
        #expect(CadenceSidebarLayoutPreferenceStore.current(from: [second, first])?.id == winner.id)
    }

    // MARK: - The device-local fallback

    /// The Mac that has been customised for months must not reset itself the day the layout became
    /// synced. With no row in the store the device-local preference is what is drawn; the first
    /// edit writes a row, and from then on the local values are not consulted.
    @Test func theDeviceLocalPreferenceIsReadOnlyUntilASyncedRowExists() {
        let fallback = CadenceSidebarLayoutPreferenceStore.layout(
            from: [],
            legacyOrderRaw: "calendar,today",
            legacyHiddenRaw: "allTasks"
        )
        #expect(fallback.order == [.calendar, .today])
        #expect(fallback.hidden == [.allTasks])

        let synced = SidebarLayoutPreference(orderRaw: "notes", hiddenRaw: "focus")
        let resolved = CadenceSidebarLayoutPreferenceStore.layout(
            from: [synced],
            legacyOrderRaw: "calendar,today",
            legacyHiddenRaw: "allTasks"
        )
        #expect(resolved.order == [.notes])
        #expect(resolved.hidden == [.focus], "the local values outranked the synced row")
    }

    // MARK: - Visibility

    /// **The floor: one visible nav row.** Every row hidden is a state a person can reach in six
    /// clicks and cannot read their way out of, so the last toggle is refused and the screen says
    /// so.
    @Test func theLastVisibleNavRowCannotBeHidden() {
        let store = CadenceSidebarLayoutPreferenceStore.self
        let allButToday = Set(CadenceSidebarLayout.primaryDestinations.filter { $0 != .today })
        let layout = CadenceSidebarLayoutPreferenceStore.Layout(order: [], hidden: allButToday)

        #expect(store.hidden(setting: .today, visible: false, in: layout) == nil)
        // Everything else still toggles: this is a floor, not a freeze.
        #expect(store.hidden(setting: .calendar, visible: true, in: layout)?.contains(.calendar) == false)
        #expect(!store.lastVisibleRowNotice.isEmpty)
    }

    @Test func hidingAndShowingARowIsOtherwiseJustASetEdit() {
        let store = CadenceSidebarLayoutPreferenceStore.self
        let layout = CadenceSidebarLayoutPreferenceStore.Layout()

        #expect(store.hidden(setting: .calendar, visible: false, in: layout) == [.calendar])
        // A no-op answers nil rather than writing the same set again.
        #expect(store.hidden(setting: .calendar, visible: true, in: layout) == nil)
        // Settings has no handle at all, in either direction.
        #expect(store.hidden(setting: .settings, visible: false, in: layout) == nil)
    }

    // MARK: - Order

    @Test func aDragMovesOneRowAndLeavesTheRestInOrder() {
        let store = CadenceSidebarLayoutPreferenceStore.self
        let layout = CadenceSidebarLayoutPreferenceStore.Layout()
        let declared = store.orderedCustomisableDestinations(for: layout)

        #expect(declared == [.today, .allTasks, .calendar, .notes, .focus])
        // Upwards: insert before the target.
        #expect(
            store.order(in: layout, moving: .notes, before: .today)
                == [.notes, .today, .allTasks, .calendar, .focus]
        )
        // Downwards: the same primitive, one index lower, which is what
        // `CadenceOrderReassignment.moved` does for every other reorder in the app.
        #expect(
            store.order(in: layout, moving: .today, before: .notes)
                == [.allTasks, .calendar, .today, .notes, .focus]
        )
        #expect(store.order(in: layout, moving: .today, before: .today) == nil)
    }

    /// The written order is the **whole** customisable list, not just the row that moved: a stored
    /// order naming a subset only constrains that subset, so a one-name string would let the next
    /// row added above it jump the queue.
    @Test func aDragWritesEveryRowSoTheArrangementSurvives() throws {
        let layout = CadenceSidebarLayoutPreferenceStore.Layout()
        let moved = try #require(
            CadenceSidebarLayoutPreferenceStore.order(in: layout, moving: .notes, before: .allTasks)
        )

        #expect(Set(moved) == CadenceSidebarLayout.customisableDestinations)
    }

    // MARK: - Where the selection goes

    /// Hiding the page you are on is the *likeliest* hide, because it is the one in front of you.
    @Test func aSelectionOnAHiddenRowMovesToTheFirstVisibleRow() {
        let visible: [CadenceFeatureDestination] = [.calendar, .notes, .settings]

        #expect(CadenceSidebarLayout.selectionFallback(for: .today, visibleRows: visible) == .calendar)
        // Inbox has no row of its own: it folds onto Tasks, which is hidden here too.
        #expect(CadenceSidebarLayout.selectionFallback(for: .inbox, visibleRows: visible) == .calendar)
    }

    /// `nil` means "leave the selection alone", and it is the common answer.
    @Test func aSelectionThatIsStillDrawnIsLeftAlone() {
        let visible: [CadenceFeatureDestination] = [.today, .allTasks, .calendar, .settings]

        #expect(CadenceSidebarLayout.selectionFallback(for: .today, visibleRows: visible) == nil)
        // Inbox has no row of its own, so what matters is the Tasks row it folds onto — drawn
        // here, where the test above hides it and gets a move instead.
        #expect(CadenceSidebarLayout.selectionFallback(for: .inbox, visibleRows: visible) == nil)
        // Lists is the scrolling region and Search is the header button: no hidden set can take
        // either away, so neither is ever moved off.
        #expect(CadenceSidebarLayout.selectionFallback(for: .lists, visibleRows: visible) == nil)
        #expect(CadenceSidebarLayout.selectionFallback(for: .search, visibleRows: []) == nil)
    }

    // MARK: - Writing

    @Test func theFirstEditCreatesOneRowCarryingTheWholeLayout() throws {
        let context = ModelContext(try CadenceTestStore.container())
        let layout = CadenceSidebarLayoutPreferenceStore.Layout(
            order: [.calendar, .today],
            hidden: [.allTasks]
        )

        try CadenceSidebarLayoutPreferenceStore.write(layout, records: [], in: context)

        let rows = try context.fetch(FetchDescriptor<SidebarLayoutPreference>())
        #expect(rows.count == 1)
        #expect(rows.first?.orderRaw == "calendar,today")
        #expect(rows.first?.hiddenRaw == "allTasks")
        #expect(CadenceSidebarLayoutPreferenceStore.layout(from: rows) == layout)
    }

    /// A second edit updates the row the readers picked and bumps `updatedAt`, so that row stays
    /// the winner rather than a second one appearing beside it.
    @Test func laterEditsUpdateTheChosenRowInPlace() throws {
        let context = ModelContext(try CadenceTestStore.container())
        try CadenceSidebarLayoutPreferenceStore.write(
            .init(order: [.today], hidden: []),
            records: [],
            in: context,
            now: Date(timeIntervalSince1970: 10)
        )
        let first = try context.fetch(FetchDescriptor<SidebarLayoutPreference>())

        try CadenceSidebarLayoutPreferenceStore.write(
            .init(order: [.notes], hidden: [.calendar]),
            records: first,
            in: context,
            now: Date(timeIntervalSince1970: 20)
        )

        let rows = try context.fetch(FetchDescriptor<SidebarLayoutPreference>())
        #expect(rows.count == 1, "a second row appeared instead of the first being edited")
        #expect(rows.first?.orderRaw == "notes")
        #expect(rows.first?.hiddenRaw == "calendar")
        #expect(rows.first?.updatedAt == Date(timeIntervalSince1970: 20))
    }

    /// A refused commit puts the row back. The Settings screens name the failure on screen rather
    /// than leaving a row sitting where the store never took it — the `try? save()` rule's second
    /// half, since this path inserts.
    @Test func arefusedWriteLeavesTheStoredLayoutExactlyAsItWas() throws {
        let context = ModelContext(try CadenceTestStore.container())
        try CadenceSidebarLayoutPreferenceStore.write(
            .init(order: [.today], hidden: [.allTasks]),
            records: [],
            in: context,
            now: Date(timeIntervalSince1970: 10)
        )
        let rows = try context.fetch(FetchDescriptor<SidebarLayoutPreference>())

        #expect(throws: (any Error).self) {
            try CadenceSidebarLayoutPreferenceStore.write(
                .init(order: [.calendar], hidden: []),
                records: rows,
                in: context,
                now: Date(timeIntervalSince1970: 20),
                commit: { _ in throw CocoaError(.fileWriteUnknown) }
            )
        }

        let after = CadenceSidebarLayoutPreferenceStore.layout(from: rows)
        #expect(after.order == [.today])
        #expect(after.hidden == [.allTasks])
        #expect(rows.first?.updatedAt == Date(timeIntervalSince1970: 10))
    }

    /// A refused *insert* leaves no row at all, rather than one the store never took.
    @Test func arefusedFirstEditLeavesNoRowBehind() throws {
        let context = ModelContext(try CadenceTestStore.container())

        #expect(throws: (any Error).self) {
            try CadenceSidebarLayoutPreferenceStore.write(
                .init(order: [.calendar], hidden: []),
                records: [],
                in: context,
                commit: { _ in throw CocoaError(.fileWriteUnknown) }
            )
        }

        #expect(try context.fetch(FetchDescriptor<SidebarLayoutPreference>()).isEmpty)
    }

    // MARK: - T-1290: the record type that Production does not have yet

    /// **What a device reads before anyone presses *Deploy Schema Changes*.**
    ///
    /// SwiftData creates a record type in the **Development** database as a debug build runs; the
    /// **Production** database gets it only when a human deploys the schema in the CloudKit
    /// Console. Until then a TestFlight or App Store build talks to a Production schema with no
    /// `CD_SidebarLayoutPreference`, and this row alone does not sync while every older type does.
    ///
    /// **The degradation is testable because the app never asks CloudKit anything here.** A
    /// `ModelContainer` builds its local store from `CadenceSchema.schema`, not from whatever the
    /// Production schema happens to hold, so the entity exists locally either way and every read
    /// on this path is a local fetch. That makes "the record type is not deployed" arrive at this
    /// store as *zero rows* — the same shape as "no device has written one yet" — which is exactly
    /// what this suite can construct. `CadenceTestStore.container()` is `cloudKitDatabase: .none`,
    /// a store with no mirroring at all, and the layout still survives a write and a re-read from
    /// a **second** `ModelContext`, so what is asserted below is the store's answer rather than
    /// one live object's memory of it.
    ///
    /// What this does **not** measure is the mirroring layer: whether a refused export of an
    /// unknown record type stays confined to this type. Nothing in a unit test can reach that.
    @Test func anUndeployedRecordTypeIsJustAnEmptyFetchAndTheLayoutSurvivesLocally() throws {
        // The read half: nothing arrived, nothing is device-local either, and the sidebar still
        // gets a complete drawable layout rather than an error or a blank one.
        let nothing = CadenceSidebarLayoutPreferenceStore.layout(from: [])
        #expect(nothing == .declared)
        #expect(
            Set(CadenceSidebarLayoutPreferenceStore.orderedCustomisableDestinations(for: nothing))
                == CadenceSidebarLayout.customisableDestinations,
            "a device with no synced row lost rows from its sidebar"
        )

        // The write half: the user's own drag lands and stays landed on this device.
        let container = try CadenceTestStore.container()
        try CadenceSidebarLayoutPreferenceStore.write(
            .init(order: [.calendar, .today], hidden: [.allTasks]),
            records: [],
            in: ModelContext(container),
            now: Date(timeIntervalSince1970: 10)
        )

        let stored = try ModelContext(container).fetch(FetchDescriptor<SidebarLayoutPreference>())
        #expect(stored.count == 1)
        let drawn = CadenceSidebarLayoutPreferenceStore.layout(
            from: stored,
            legacyOrderRaw: "calendar,notes",
            legacyHiddenRaw: "today"
        )
        #expect(drawn.order == [.calendar, .today])
        #expect(drawn.hidden == [.allTasks], "the device-local fallback outranked the row this device wrote")
    }

    /// **And what happens on the day the schema is finally deployed.**
    ///
    /// Each device wrote its own row while the type was invisible to the others, so the deploy
    /// delivers two rows at once. That is the duplicate case the reader was built for and not a new
    /// one: newest `updatedAt` wins, every device picks the same row, and the loser is **left
    /// alone** rather than deleted — deleting a row another device is mid-sync with is how a
    /// preference becomes a data-loss bug, and it is why a late deploy costs a layout at most and
    /// never a store.
    @Test func theDeployArrivingLateReconcilesBothDevicesRowsWithoutDeletingEither() throws {
        let container = try CadenceTestStore.container()
        let context = ModelContext(container)
        let fromTheMac = SidebarLayoutPreference(
            orderRaw: "calendar,today",
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let fromTheiPhone = SidebarLayoutPreference(
            orderRaw: "notes,today",
            hiddenRaw: "allTasks",
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        context.insert(fromTheMac)
        context.insert(fromTheiPhone)
        try context.save()

        let arrived = try context.fetch(FetchDescriptor<SidebarLayoutPreference>())
        #expect(arrived.count == 2)
        let resolved = CadenceSidebarLayoutPreferenceStore.layout(
            from: arrived,
            legacyOrderRaw: "calendar",
            legacyHiddenRaw: "focus"
        )
        #expect(resolved.order == [.notes, .today], "the older row won")
        #expect(resolved.hidden == [.allTasks])

        // The next edit goes to the row every device already agreed on, so no third row appears.
        try CadenceSidebarLayoutPreferenceStore.write(
            .init(order: [.today, .notes], hidden: []),
            records: arrived,
            in: context,
            now: Date(timeIntervalSince1970: 300)
        )

        let after = try ModelContext(container).fetch(FetchDescriptor<SidebarLayoutPreference>())
        #expect(after.count == 2, "the reconciliation minted or removed a row")
        #expect(
            after.contains { $0.orderRaw == "calendar,today" },
            "the losing row was deleted instead of being left alone"
        )
        #expect(CadenceSidebarLayoutPreferenceStore.layout(from: after).order == [.today, .notes])
    }

    // MARK: - T-2076: a synced row naming a destination this build removed

    /// **The hazard T-2076 had to clear.** The sidebar layout is CloudKit-synced and keyed against
    /// `CadenceFeatureDestination` raw values, so the owner's iPhone and iPad already hold a record
    /// whose `orderRaw` and `hiddenRaw` name `goals` and `habits` — rows every build before this one
    /// drew. This build has no case for either.
    ///
    /// The requirement is not that the strings keep working; it is that a stale record must not
    /// **corrupt or silently reset** a layout. So what is asserted here is survival of everything
    /// around the removed tokens: the surviving rows keep their stored *sequence*, a hidden set
    /// that named a removed row resolves to a smaller set rather than to "nothing is customised",
    /// and the sidebar still resolves to a full column of drawable rows.
    ///
    /// The hidden half is where a reset would have shown: `hidden` is a `Set`, and a decoder that
    /// threw or bailed on the first unknown token would have returned `Layout.declared` — a layout
    /// with *nothing* hidden, which looks like the preference was wiped and would then be written
    /// back as one on the user's next drag. `compactMap` drops the strangers and keeps the rest,
    /// which is why the Calendar row below is still hidden.
    @Test func aSyncedLayoutNamingRemovedDestinationsSurvivesIntact() {
        // Exactly what T-1274 would have written on a device the owner had dragged Notes to the
        // top of and hidden Calendar on, with Goals and Habits still in the column.
        let fromAnOlderBuild = SidebarLayoutPreference(
            orderRaw: "notes,goals,today,habits,allTasks,calendar",
            hiddenRaw: "calendar,habits",
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )

        let layout = CadenceSidebarLayoutPreferenceStore.layout(from: [fromAnOlderBuild])

        // The order survives as a *subsequence* — Notes is still above Today, Today above Tasks —
        // rather than collapsing to the declared order or to nothing.
        #expect(layout.order == [.notes, .today, .allTasks, .calendar])
        // And not as a reset: `.declared` is the empty layout, and reading this record as that is
        // the failure this test exists for.
        #expect(layout != .declared)
        // Calendar is still hidden. `habits` was dropped, not treated as a parse failure that
        // discards the rest of the set.
        #expect(layout.hidden == [.calendar])

        // The column the sidebar actually draws from it: Notes first because the user dragged it
        // there, Calendar absent because the user hid it, and nothing missing or duplicated.
        let drawn = CadenceSidebarLayout.resolvedDestinations(
            in: .primary,
            customisable: CadenceSidebarLayout.customisableDestinations,
            storedOrder: layout.order,
            hidden: layout.hidden
        )
        #expect(drawn == [.notes, .today, .allTasks])

        // The Settings list the owner would see: every customisable row, none of them a stranger,
        // and the dragged ones still in the order they were dragged into.
        let settingsRows = CadenceSidebarLayoutPreferenceStore.orderedCustomisableDestinations(for: layout)
        #expect(Set(settingsRows) == CadenceSidebarLayout.customisableDestinations)
        #expect(settingsRows == [.notes, .today, .allTasks, .calendar, .focus])
    }

    /// **The record is not rewritten until the owner edits the layout themselves**, and when it is,
    /// the removed tokens are simply absent rather than preserved.
    ///
    /// This is the deliberate cost named on `destinations(fromRaw:)`: a device still on the older
    /// build keeps drawing Goals and Habits from this same row until it updates, because nothing
    /// here deletes the row, and it loses their stored *slots* (not their visibility) the moment a
    /// newer device writes. Visibility is opt-out, so an absent destination is a shown one — which
    /// is why the older device re-shows them rather than losing them.
    @Test func aLaterEditRewritesTheRowWithoutTheRemovedTokensAndWithoutDeletingIt() throws {
        let context = ModelContext(try CadenceTestStore.container())
        let fromAnOlderBuild = SidebarLayoutPreference(
            orderRaw: "notes,goals,today,habits",
            hiddenRaw: "calendar,goals",
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        context.insert(fromAnOlderBuild)
        try context.save()
        let records = try context.fetch(FetchDescriptor<SidebarLayoutPreference>())

        var layout = CadenceSidebarLayoutPreferenceStore.layout(from: records)
        layout.order = try #require(
            CadenceSidebarLayoutPreferenceStore.order(in: layout, moving: .today, before: .notes)
        )
        try CadenceSidebarLayoutPreferenceStore.write(
            layout,
            records: records,
            in: context,
            now: Date(timeIntervalSince1970: 2_000)
        )

        let rewritten = try context.fetch(FetchDescriptor<SidebarLayoutPreference>())
        #expect(rewritten.count == 1, "the stale row was replaced instead of being edited")
        // The whole customisable list, in the sidebar's own walk, with `goals` and `habits`
        // simply absent — not preserved, and not standing in the way of the rows that remain.
        #expect(rewritten.first?.orderRaw == "today,notes,allTasks,calendar,focus")
        #expect(rewritten.first?.hiddenRaw == "calendar")
        #expect(rewritten.first?.id == fromAnOlderBuild.id)
        #expect(rewritten.first?.updatedAt == Date(timeIntervalSince1970: 2_000))
    }

    // MARK: - The model is additive

    /// CloudKit has been in Production since 2026-09-05 with no `SchemaMigrationPlan`, so the
    /// layout had to arrive as a **new** record type: every property here has a default, nothing
    /// is required, and no existing model gained or lost a column.
    @Test func theModelIsOptionalEverywhereAndInTheSchema() {
        let bare = SidebarLayoutPreference()

        #expect(bare.orderRaw.isEmpty)
        #expect(bare.hiddenRaw.isEmpty)
        #expect(CadenceSchema.schema.entities.map(\.name).contains("SidebarLayoutPreference"))
        // A bare row reads as "nothing customised", which is the declared layout.
        #expect(CadenceSidebarLayoutPreferenceStore.layout(from: [bare]) == .declared)
    }
}

#if os(macOS)

/// The two enums that describe the same set of customisable rows, pinned against each other.
@MainActor
struct SidebarLayoutCustomisableParityTests {
    /// macOS's Settings screen is written in `SidebarStaticDestination`; iOS has no such type and
    /// reads `CadenceSidebarLayout.customisableDestinations`. One of them being wider than the
    /// other is a control that changes nothing on one platform, or a row one platform cannot edit.
    @Test func bothPlatformsOfferAHandleForTheSameRows() {
        #expect(
            Set(SidebarStaticDestination.allCases.map(\.feature))
                == CadenceSidebarLayout.customisableDestinations
        )
        // Notes is the row T-1274 added a handle for, and Settings is the one that must never get
        // one.
        #expect(CadenceSidebarLayout.customisableDestinations.contains(.notes))
        #expect(!CadenceSidebarLayout.customisableDestinations.contains(.settings))
    }

    /// The declared order Settings lists rows in is the sidebar's own, group by group.
    @Test func theDefaultOrderIsTheSidebarsDeclaredOrder() {
        #expect(
            CadenceFeatureDestination.desktopSidebarOrder
                == CadenceSidebarLayout.primaryDestinations + [.focus]
        )
        #expect(
            Set(SidebarStaticDestination.defaultOrder.map(\.feature))
                == CadenceSidebarLayout.customisableDestinations
        )
    }
}

#endif
