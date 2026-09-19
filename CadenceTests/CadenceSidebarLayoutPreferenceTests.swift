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

        #expect(parse("today,goals,habits") == [.today, .goals, .habits])
        // A repeat keeps its first position: an order is a sequence of slots, not a multiset.
        #expect(parse("goals,today,goals") == [.goals, .today])
        // Unrecognised tokens are dropped rather than carried: this build cannot place a row it has
        // no case for. The cost is stated in `SidebarLayoutPreference`'s own note.
        #expect(parse("today,somethingNewer,notes") == [.today, .notes])
        #expect(parse("") == [])
        #expect(parse(" today , notes ") == [.today, .notes])
    }

    @Test func theRawStringRoundTripsAnOrder() {
        let order: [CadenceFeatureDestination] = [.habits, .today, .notes]
        let raw = CadenceSidebarLayoutPreferenceStore.raw(from: order)

        #expect(raw == "habits,today,notes")
        #expect(CadenceSidebarLayoutPreferenceStore.destinations(fromRaw: raw) == order)
    }

    // MARK: - Which record wins

    /// Two devices can each create a row before either has seen the other's, and there is no unique
    /// constraint to lean on — CloudKit forbids them. The newest edit wins, because that is what a
    /// person means by changing a preference on the device in front of them.
    @Test func theMostRecentlyUpdatedRowIsTheOneEveryDeviceReads() {
        let old = SidebarLayoutPreference(orderRaw: "today", updatedAt: Date(timeIntervalSince1970: 100))
        let recent = SidebarLayoutPreference(orderRaw: "habits", updatedAt: Date(timeIntervalSince1970: 900))

        #expect(CadenceSidebarLayoutPreferenceStore.current(from: [old, recent])?.orderRaw == "habits")
        #expect(CadenceSidebarLayoutPreferenceStore.current(from: [recent, old])?.orderRaw == "habits")
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
            legacyOrderRaw: "habits,today",
            legacyHiddenRaw: "goals"
        )
        #expect(fallback.order == [.habits, .today])
        #expect(fallback.hidden == [.goals])

        let synced = SidebarLayoutPreference(orderRaw: "notes", hiddenRaw: "focus")
        let resolved = CadenceSidebarLayoutPreferenceStore.layout(
            from: [synced],
            legacyOrderRaw: "habits,today",
            legacyHiddenRaw: "goals"
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
        #expect(store.hidden(setting: .goals, visible: true, in: layout)?.contains(.goals) == false)
        #expect(!store.lastVisibleRowNotice.isEmpty)
    }

    @Test func hidingAndShowingARowIsOtherwiseJustASetEdit() {
        let store = CadenceSidebarLayoutPreferenceStore.self
        let layout = CadenceSidebarLayoutPreferenceStore.Layout()

        #expect(store.hidden(setting: .habits, visible: false, in: layout) == [.habits])
        // A no-op answers nil rather than writing the same set again.
        #expect(store.hidden(setting: .habits, visible: true, in: layout) == nil)
        // Settings has no handle at all, in either direction.
        #expect(store.hidden(setting: .settings, visible: false, in: layout) == nil)
    }

    // MARK: - Order

    @Test func aDragMovesOneRowAndLeavesTheRestInOrder() {
        let store = CadenceSidebarLayoutPreferenceStore.self
        let layout = CadenceSidebarLayoutPreferenceStore.Layout()
        let declared = store.orderedCustomisableDestinations(for: layout)

        #expect(declared == [.today, .allTasks, .calendar, .notes, .goals, .habits, .focus])
        // Upwards: insert before the target.
        #expect(
            store.order(in: layout, moving: .habits, before: .today)
                == [.habits, .today, .allTasks, .calendar, .notes, .goals, .focus]
        )
        // Downwards: the same primitive, one index lower, which is what
        // `CadenceOrderReassignment.moved` does for every other reorder in the app.
        #expect(
            store.order(in: layout, moving: .today, before: .goals)
                == [.allTasks, .calendar, .notes, .today, .goals, .habits, .focus]
        )
        #expect(store.order(in: layout, moving: .today, before: .today) == nil)
    }

    /// The written order is the **whole** customisable list, not just the row that moved: a stored
    /// order naming a subset only constrains that subset, so a one-name string would let the next
    /// row added above it jump the queue.
    @Test func aDragWritesEveryRowSoTheArrangementSurvives() throws {
        let layout = CadenceSidebarLayoutPreferenceStore.Layout()
        let moved = try #require(
            CadenceSidebarLayoutPreferenceStore.order(in: layout, moving: .goals, before: .allTasks)
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
            order: [.habits, .today],
            hidden: [.goals]
        )

        try CadenceSidebarLayoutPreferenceStore.write(layout, records: [], in: context)

        let rows = try context.fetch(FetchDescriptor<SidebarLayoutPreference>())
        #expect(rows.count == 1)
        #expect(rows.first?.orderRaw == "habits,today")
        #expect(rows.first?.hiddenRaw == "goals")
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
            .init(order: [.notes], hidden: [.habits]),
            records: first,
            in: context,
            now: Date(timeIntervalSince1970: 20)
        )

        let rows = try context.fetch(FetchDescriptor<SidebarLayoutPreference>())
        #expect(rows.count == 1, "a second row appeared instead of the first being edited")
        #expect(rows.first?.orderRaw == "notes")
        #expect(rows.first?.hiddenRaw == "habits")
        #expect(rows.first?.updatedAt == Date(timeIntervalSince1970: 20))
    }

    /// A refused commit puts the row back. The Settings screens name the failure on screen rather
    /// than leaving a row sitting where the store never took it — the `try? save()` rule's second
    /// half, since this path inserts.
    @Test func arefusedWriteLeavesTheStoredLayoutExactlyAsItWas() throws {
        let context = ModelContext(try CadenceTestStore.container())
        try CadenceSidebarLayoutPreferenceStore.write(
            .init(order: [.today], hidden: [.goals]),
            records: [],
            in: context,
            now: Date(timeIntervalSince1970: 10)
        )
        let rows = try context.fetch(FetchDescriptor<SidebarLayoutPreference>())

        #expect(throws: (any Error).self) {
            try CadenceSidebarLayoutPreferenceStore.write(
                .init(order: [.habits], hidden: []),
                records: rows,
                in: context,
                now: Date(timeIntervalSince1970: 20),
                commit: { _ in throw CocoaError(.fileWriteUnknown) }
            )
        }

        let after = CadenceSidebarLayoutPreferenceStore.layout(from: rows)
        #expect(after.order == [.today])
        #expect(after.hidden == [.goals])
        #expect(rows.first?.updatedAt == Date(timeIntervalSince1970: 10))
    }

    /// A refused *insert* leaves no row at all, rather than one the store never took.
    @Test func arefusedFirstEditLeavesNoRowBehind() throws {
        let context = ModelContext(try CadenceTestStore.container())

        #expect(throws: (any Error).self) {
            try CadenceSidebarLayoutPreferenceStore.write(
                .init(order: [.habits], hidden: []),
                records: [],
                in: context,
                commit: { _ in throw CocoaError(.fileWriteUnknown) }
            )
        }

        #expect(try context.fetch(FetchDescriptor<SidebarLayoutPreference>()).isEmpty)
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
