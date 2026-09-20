import Foundation
import SwiftData
import Testing
@testable import Cadence

/// The synced look (T-1307, folding in T-1288): what travels between the owner's Mac, iPhone and
/// iPad, how the two platforms' different sort vocabularies meet, and — the half this ticket was
/// specifically warned about — what a device does with a value it has no control for.
///
/// Everything here runs against `CadenceLookPreferenceStore`'s pure half or against an in-memory
/// store, and the iOS table is exercised **on the Mac** by naming the platform, because the
/// interesting cases are exactly the ones where one platform holds a setting the other cannot
/// express.
@MainActor
struct CadenceLookPreferenceTests {

    private typealias Store = CadenceLookPreferenceStore

    // MARK: - The pair grammar

    @Test func theStoredStringIsAKeyValueMapWithSortedKeys() {
        let pairs = Store.pairs(fromRaw: "allTasks.mode=dueDate;today.mode=doDate;inbox.direction=Descending")
        #expect(pairs["allTasks.mode"] == "dueDate")
        #expect(pairs["today.mode"] == "doDate")
        #expect(pairs["inbox.direction"] == "Descending")
        #expect(pairs.count == 3)

        // Sorted on the way out, so the same map is always the same string and a write that
        // changed nothing cannot read as a change on the other two devices.
        #expect(Store.raw(from: pairs) == "allTasks.mode=dueDate;inbox.direction=Descending;today.mode=doDate")
    }

    @Test func malformedSegmentsAreSkippedRatherThanCrashingOrPoisoningTheMap() {
        let pairs = Store.pairs(fromRaw: ";;no-equals-sign;=novalue;today.mode=;today.mode=doDate; inbox.mode = listOrder ")
        #expect(pairs == ["today.mode": "doDate", "inbox.mode": "listOrder"])
    }

    @Test func aRoundTripThroughTheGrammarIsIdentity() {
        let raw = "allTasks.direction=Descending;allTasks.mode=priority;today.showCompleted=true"
        #expect(Store.raw(from: Store.pairs(fromRaw: raw)) == raw)
    }

    // MARK: - Which record

    /// Two devices can each mint a row before either sees the other's; CloudKit forbids the unique
    /// constraint that would stop it. Newest edit wins, `id` breaks a tie, and every device picks
    /// the same one — otherwise each picks its own and they overwrite each other forever.
    @Test func theNewestRowWinsAndTheIDBreaksATie() {
        let old = LookPreference(accentPaletteID: "cadence", updatedAt: Date(timeIntervalSince1970: 100))
        let recent = LookPreference(accentPaletteID: "ember", updatedAt: Date(timeIntervalSince1970: 900))
        #expect(Store.current(from: [old, recent])?.accentPaletteID == "ember")
        #expect(Store.current(from: [recent, old])?.accentPaletteID == "ember")
        #expect(Store.current(from: []) == nil)

        let moment = Date(timeIntervalSince1970: 500)
        let first = LookPreference(accentPaletteID: "cadence", updatedAt: moment)
        let second = LookPreference(accentPaletteID: "glacier", updatedAt: moment)
        let winner = [first, second].min { $0.id.uuidString < $1.id.uuidString } == first ? second : first
        #expect(Store.current(from: [first, second])?.id == winner.id)
        #expect(Store.current(from: [second, first])?.id == winner.id)
    }

    // MARK: - The two sort vocabularies

    /// macOS stores a `TaskSortField`; iOS stores a `CadenceTaskSortMode`. They are the same
    /// setting, and the mapping is not a new judgement — T-606 read it off the two comparators and
    /// `TaskOrderingTests` pins it. This asserts the store reuses that mapping rather than writing
    /// a second one that could drift from it.
    @Test func macOSSortFieldsMapOntoTheSharedVocabularyTheWayTaskOrderingAlreadySaid() {
        for field in TaskSortField.allCases {
            #expect(
                Store.recordValue(fromMirror: field.rawValue, codec: .macOSSortField)
                    == CadenceTaskSortMode.migratedFromMacOSTodaySortField(field.rawValue).rawValue
            )
        }
    }

    /// `.dueDate` and `.newest` have no `TaskSortField` at all. They project onto `Date`, the
    /// nearest of the Mac's three, rather than answering `nil`: a Mac drawing the nearest thing
    /// very nearly agrees with the phone, where a Mac refusing the value would show an unrelated
    /// order with nothing on screen saying why. The projection is only safe because a projected
    /// value is never published back — the next test.
    @Test func aModeTheMacCannotNameProjectsOntoItsNearestField() {
        #expect(Store.mirrorValue(fromRecord: "listOrder", codec: .macOSSortField) == TaskSortField.custom.rawValue)
        #expect(Store.mirrorValue(fromRecord: "priority", codec: .macOSSortField) == TaskSortField.priority.rawValue)
        #expect(Store.mirrorValue(fromRecord: "doDate", codec: .macOSSortField) == TaskSortField.date.rawValue)
        #expect(Store.mirrorValue(fromRecord: "dueDate", codec: .macOSSortField) == TaskSortField.date.rawValue)
        #expect(Store.mirrorValue(fromRecord: "newest", codec: .macOSSortField) == TaskSortField.date.rawValue)
        // A mode neither vocabulary knows is refused rather than guessed at, so the mirror keeps
        // whatever the person set on this device.
        #expect(Store.mirrorValue(fromRecord: "quarterlyReview", codec: .macOSSortField) == nil)
    }

    // MARK: - The failure this ticket was warned about

    /// **A Mac drawing a projection does not write the projection back.**
    ///
    /// The phone chose Due Date. The Mac has no such field, so it draws `Date`. If publishing then
    /// treated `Date` as a change it would store `doDate` and silently destroy a setting the Mac
    /// never had a control for — one platform overwriting a setting the other cannot express,
    /// which is the whole hazard. A mirror already holding the projection of what is stored counts
    /// as unchanged.
    @Test func aMacRedrawingAModeItCannotExpressLeavesTheStoredModeAlone() {
        let stored = ["allTasks.mode": "dueDate"]
        let asDrawn = ["allTasksSortField": TaskSortField.date.rawValue]

        let published = Store.publishedPairs(currentMirrors: asDrawn, stored: stored, on: .macOS)
        #expect(published["allTasks.mode"] == "dueDate", "the Mac overwrote a mode it cannot name")

        // And the moment the person actually moves the chip somewhere else, it *is* a change.
        let moved = ["allTasksSortField": TaskSortField.priority.rawValue]
        #expect(Store.publishedPairs(currentMirrors: moved, stored: stored, on: .macOS)["allTasks.mode"] == "priority")
    }

    /// A pair this platform has no mirror for rides through its write untouched — an iOS
    /// `showCompleted` on a Mac, a macOS `grouping` on a phone, or a key some future build adds.
    /// This is the one place this design improves on `SidebarLayoutPreference`, which drops a
    /// token it cannot read.
    @Test func aPairThisPlatformHasNoControlForSurvivesItsWrite() {
        let stored = [
            "allTasks.showCompleted": "true",   // iOS only
            "allTasks.grouping": "By List",     // macOS only
            "quarterly.review": "whatever",     // no build has ever had a control for this
        ]

        let fromTheMac = Store.publishedPairs(
            currentMirrors: ["allTasksSortField": TaskSortField.priority.rawValue],
            stored: stored,
            on: .macOS
        )
        #expect(fromTheMac["allTasks.showCompleted"] == "true")
        #expect(fromTheMac["quarterly.review"] == "whatever")
        #expect(fromTheMac["allTasks.mode"] == "priority")

        let fromThePhone = Store.publishedPairs(
            currentMirrors: ["ios.allTasks.showCompleted": "false"],
            stored: stored,
            on: .iOS
        )
        #expect(fromThePhone["allTasks.grouping"] == "By List", "the phone erased a macOS-only setting")
        #expect(fromThePhone["quarterly.review"] == "whatever")
        #expect(fromThePhone["allTasks.showCompleted"] == "false")
    }

    /// The direction half of the same rule, stated as the owner would ask it: what does a phone do
    /// with a direction it has no control for? **Nothing.** It is not in the phone's mirror table,
    /// so the phone never reads it and never writes it, and a Mac that chose low-priority-first
    /// still has it after the phone re-sorts All Tasks.
    @Test func aPhoneNeverTouchesTheDirectionItHasNoControlFor() {
        #expect(Store.mirrors(on: .iOS).contains { $0.recordKey.hasSuffix(".direction") } == false)
        #expect(Store.mirrors(on: .macOS).contains { $0.recordKey == "allTasks.direction" })

        let stored = ["allTasks.mode": "priority", "allTasks.direction": "Ascending"]
        let afterThePhoneResorted = Store.publishedPairs(
            currentMirrors: ["ios.allTasks.sortMode": "dueDate"],
            stored: stored,
            on: .iOS
        )
        #expect(afterThePhoneResorted["allTasks.direction"] == "Ascending")
        #expect(afterThePhoneResorted["allTasks.mode"] == "dueDate")

        // And the Mac, redrawing that, shows Date — its nearest field — still Ascending.
        let mirrors = Store.mirrorWrites(forTaskPresentation: Store.raw(from: afterThePhoneResorted), on: .macOS)
        #expect(mirrors["allTasksSortField"] == TaskSortField.date.rawValue)
        #expect(mirrors["allTasksSortDirection"] == "Ascending")
    }

    // MARK: - Adopting

    /// A key the record has never carried leaves this device's default exactly as the person left
    /// it. The alternative — filling every absent key with a default — would reset a preference
    /// nobody touched the first time any device wrote any other one.
    @Test func anAbsentPairChangesNothingOnThisDevice() {
        let writes = Store.mirrorWrites(forTaskPresentation: "today.mode=priority", on: .macOS)
        #expect(writes == ["todaySortMode": "priority"])
        #expect(Store.mirrorWrites(forTaskPresentation: "", on: .macOS).isEmpty)
        #expect(Store.mirrorWrites(forTaskPresentation: "", on: .iOS).isEmpty)
    }

    @Test func everyMirrorKeyIsSpelledOncePerPlatform() {
        for platform in Store.Platform.allCases {
            let mirrors = Store.mirrors(on: platform)
            #expect(Set(mirrors.map(\.defaultsKey)).count == mirrors.count)
            #expect(Set(mirrors.map(\.recordKey)).count == mirrors.count)
        }
    }

    // MARK: - Writing

    @Test func theFirstWriteCreatesOneRowCarryingTheWholeLook() throws {
        let context = ModelContext(try CadenceTestStore.container())

        try Store.write(
            accentPaletteID: "ember",
            sidebarTabColorsRaw: "today:#ff0000",
            taskPresentationRaw: "today.mode=doDate",
            records: [],
            in: context,
            now: Date(timeIntervalSince1970: 10)
        )

        let rows = try context.fetch(FetchDescriptor<LookPreference>())
        #expect(rows.count == 1)
        #expect(rows.first?.accentPaletteID == "ember")
        #expect(rows.first?.sidebarTabColorsRaw == "today:#ff0000")
        #expect(rows.first?.taskPresentationRaw == "today.mode=doDate")
    }

    /// A second write updates the row the readers picked rather than minting a second one beside
    /// it, and bumps `updatedAt` so that row stays the winner.
    @Test func laterWritesUpdateTheChosenRowInPlace() throws {
        let context = ModelContext(try CadenceTestStore.container())
        try Store.write(
            accentPaletteID: "ember",
            sidebarTabColorsRaw: "",
            taskPresentationRaw: "",
            records: [],
            in: context,
            now: Date(timeIntervalSince1970: 10)
        )
        let first = try context.fetch(FetchDescriptor<LookPreference>())

        try Store.write(
            accentPaletteID: "glacier",
            sidebarTabColorsRaw: "",
            taskPresentationRaw: "today.mode=newest",
            records: first,
            in: context,
            now: Date(timeIntervalSince1970: 20)
        )

        let rows = try context.fetch(FetchDescriptor<LookPreference>())
        #expect(rows.count == 1)
        #expect(rows.first?.accentPaletteID == "glacier")
        #expect(rows.first?.updatedAt == Date(timeIntervalSince1970: 20))
        #expect(rows.first?.createdAt == Date(timeIntervalSince1970: 10))
    }

    /// A refused commit puts every field back and mints nothing, so a failed sync leaves no half
    /// row behind for the next device to adopt.
    @Test func aRefusedWriteLeavesNoRowAndNoHalfEdit() throws {
        let context = ModelContext(try CadenceTestStore.container())
        struct Refused: Error {}

        #expect(throws: Refused.self) {
            try Store.write(
                accentPaletteID: "ember",
                sidebarTabColorsRaw: "",
                taskPresentationRaw: "",
                records: [],
                in: context,
                commit: { _ in throw Refused() }
            )
        }
        #expect(try context.fetch(FetchDescriptor<LookPreference>()).isEmpty)

        try Store.write(
            accentPaletteID: "ember",
            sidebarTabColorsRaw: "",
            taskPresentationRaw: "",
            records: [],
            in: context,
            now: Date(timeIntervalSince1970: 10)
        )
        let rows = try context.fetch(FetchDescriptor<LookPreference>())
        #expect(throws: Refused.self) {
            try Store.write(
                accentPaletteID: "glacier",
                sidebarTabColorsRaw: "changed",
                taskPresentationRaw: "today.mode=newest",
                records: rows,
                in: context,
                now: Date(timeIntervalSince1970: 20),
                commit: { _ in throw Refused() }
            )
        }
        let after = Store.current(from: try context.fetch(FetchDescriptor<LookPreference>()))
        #expect(after?.accentPaletteID == "ember")
        #expect(after?.sidebarTabColorsRaw == "")
        #expect(after?.taskPresentationRaw == "")
        #expect(after?.updatedAt == Date(timeIntervalSince1970: 10))
    }

    // MARK: - Not writing

    /// A publish runs on every `UserDefaults` change in the app and almost none of them touch one
    /// of these keys. `pendingWrite` answering `nil` is what stops a remembered scroll position
    /// from bumping `updatedAt` on three devices.
    @Test func nothingIsWrittenWhenTheRecordAlreadySaysExactlyThis() {
        let record = LookPreference(
            accentPaletteID: "ember",
            sidebarTabColorsRaw: "today:#ff0000",
            taskPresentationRaw: "today.mode=doDate"
        )
        #expect(
            Store.pendingWrite(
                accentPaletteID: "ember",
                sidebarTabColorsRaw: "today:#ff0000",
                currentMirrors: ["todaySortMode": "doDate"],
                record: record,
                on: .macOS
            ) == nil
        )
        #expect(
            Store.pendingWrite(
                accentPaletteID: "glacier",
                sidebarTabColorsRaw: "today:#ff0000",
                currentMirrors: ["todaySortMode": "doDate"],
                record: record,
                on: .macOS
            )?.accentPaletteID == "glacier"
        )
    }

    /// A device that has chosen nothing mints no row. Three devices each seeding a row of pure
    /// defaults is three rows to reconcile and nothing said.
    @Test func aDeviceWithNothingToSayMintsNoRow() {
        #expect(
            Store.pendingWrite(
                accentPaletteID: "",
                sidebarTabColorsRaw: "",
                currentMirrors: [:],
                record: nil,
                on: .macOS
            ) == nil
        )
        #expect(
            Store.pendingWrite(
                accentPaletteID: "",
                sidebarTabColorsRaw: "",
                currentMirrors: ["todaySortMode": "priority"],
                record: nil,
                on: .macOS
            )?.taskPresentationRaw == "today.mode=priority"
        )
    }

    /// **A device that has chosen no accent does not erase the one the owner chose elsewhere.**
    ///
    /// A publish runs on any `UserDefaults` change, including ones during startup before the first
    /// adopt, and at that moment this device's app-group key is empty while the record holds a
    /// palette. Reading that emptiness as a choice would blank the accent on all three devices.
    @Test func anUnsetLocalValueNeverOverwritesAStoredOne() {
        let record = LookPreference(accentPaletteID: "ember", sidebarTabColorsRaw: "today:#ff0000")

        #expect(
            Store.pendingWrite(
                accentPaletteID: "",
                sidebarTabColorsRaw: "",
                currentMirrors: [:],
                record: record,
                on: .macOS
            ) == nil,
            "a device that had chosen nothing wrote its emptiness over the record"
        )

        // A device that *has* chosen still wins, which is the other half.
        #expect(
            Store.pendingWrite(
                accentPaletteID: "glacier",
                sidebarTabColorsRaw: "",
                currentMirrors: [:],
                record: record,
                on: .macOS
            )?.sidebarTabColorsRaw == "today:#ff0000"
        )
    }

    // MARK: - The accent, and the widget that must keep reading it

    /// The record is the source of truth across devices; the **app-group default stays** as this
    /// device's mirror, because `CadenceWidgets` is a separate process that reads the palette on
    /// its next timeline reload with no SwiftData anywhere near it. Adopting a palette from the
    /// record must therefore leave that key holding the new id.
    @Test func adoptingAPaletteWritesTheAppGroupKeyTheWidgetReads() throws {
        try withTemporaryDefaults("look-accent") { suite in
            try withTemporaryDefaults("look-local") { local in
                let sync = CadenceLookPreferenceSync(defaults: local, accentDefaults: suite, platform: .macOS)

                // `applyAccent: false` keeps the process-wide `CadenceAccentPaletteSelection`
                // singleton out of it — a test must not repaint the app it is running inside.
                let changed = sync.adopt(records: [LookPreference(accentPaletteID: "ember")], applyAccent: false)
                #expect(changed.contains(CadenceAccentPaletteStore.defaultsKey))

                suite.set("ember", forKey: CadenceAccentPaletteStore.defaultsKey)
                #expect(CadenceAccentPaletteStore.loadSelected(userDefaults: suite).id == "ember")

                // An id this build has no palette for resolves to the standard set rather than
                // leaving the app with no accents — a newer device cannot blank an older one.
                suite.set("aurora", forKey: CadenceAccentPaletteStore.defaultsKey)
                #expect(CadenceAccentPaletteStore.loadSelected(userDefaults: suite) == CadenceAccentPalette.standard)
            }
        }
    }

    // MARK: - Adopt and publish cannot loop

    /// Adopt writes a mirror only when it differs, and publish commits only when `pendingWrite`
    /// answers non-`nil`. So a record read down leaves nothing for the publish it might trigger,
    /// which is what keeps the pair from ringing between the two layers forever.
    @Test func adoptingLeavesNothingToPublish() throws {
        try withTemporaryDefaults("look-loop") { defaults in
            try withTemporaryDefaults("look-loop-accent") { accents in
                let sync = CadenceLookPreferenceSync(defaults: defaults, accentDefaults: accents, platform: .iOS)
                let record = LookPreference(
                    accentPaletteID: "",
                    sidebarTabColorsRaw: "",
                    taskPresentationRaw: "today.mode=priority;today.showCompleted=true"
                )

                #expect(sync.adopt(records: [record], applyAccent: false).isEmpty == false)
                #expect(defaults.string(forKey: "ios.today.sortMode") == "priority")
                #expect(defaults.bool(forKey: "ios.today.showCompleted"))
                // The bool half matters: `UserDefaults.string(forKey:)` answers `nil` for a `Bool`,
                // so a mirror that wrote `"true"` as a string would read as unset on every launch.

                #expect(sync.adopt(records: [record], applyAccent: false).isEmpty, "a second adopt moved something")
                #expect(
                    Store.pendingWrite(
                        accentPaletteID: "",
                        sidebarTabColorsRaw: "",
                        currentMirrors: Store.currentMirrors(in: defaults, on: .iOS),
                        record: record,
                        on: .iOS
                    ) == nil,
                    "an adopt left something for publish to write back"
                )
            }
        }
    }

    // MARK: - T-1290: the record type Production does not have yet

    /// **What a device reads before anyone presses *Deploy Schema Changes*.**
    ///
    /// Same shape as `CadenceSidebarLayoutPreferenceTests`' equivalent, and for the same reason: a
    /// `ModelContainer` builds its local store from `CadenceSchema.schema` rather than from
    /// whatever Production holds, so an undeployed record type arrives here as *zero rows* — the
    /// same shape as "no device has written one yet". Every reader on this path is total, so the
    /// device simply keeps its own look.
    ///
    /// **This is the local half only, and the other half is worse than the ticket assumed.** Codex
    /// R49 (2026-09-20) reads TN3164 as documenting that a missing Production schema can abort
    /// exports for the **whole store**, not just the missing type — so this test says the app keeps
    /// working on the device, and says nothing at all about whether anything syncs. Nothing a unit
    /// test can construct reaches the mirroring layer. `CD_LookPreference` is owed a deploy beside
    /// `CD_SidebarLayoutPreference`; `docs/apple-release-readiness.md` carries the rule, which is
    /// that the press comes before the build goes out.
    @Test func anUndeployedRecordTypeIsJustAnEmptyFetchAndThisDeviceKeepsItsOwnLook() throws {
        try withTemporaryDefaults("look-dark") { defaults in
            try withTemporaryDefaults("look-dark-accent") { accents in
                defaults.set("Priority", forKey: "allTasksSortField")
                let sync = CadenceLookPreferenceSync(defaults: defaults, accentDefaults: accents, platform: .macOS)
                #expect(sync.adopt(records: [], applyAccent: false).isEmpty)
                #expect(
                    defaults.string(forKey: "allTasksSortField") == "Priority",
                    "an empty fetch reset a local setting"
                )
            }
        }

        #expect(CadenceSchema.schema.entities.map(\.name).contains("LookPreference"))

        // And the write half lands and stays landed on this device, read back through a *second*
        // context so what is asserted is the store's answer rather than one object's memory.
        let container = try CadenceTestStore.container()
        try Store.write(
            accentPaletteID: "ember",
            sidebarTabColorsRaw: "",
            taskPresentationRaw: "allTasks.mode=priority",
            records: [],
            in: ModelContext(container),
            now: Date(timeIntervalSince1970: 10)
        )
        let stored = try ModelContext(container).fetch(FetchDescriptor<LookPreference>())
        #expect(stored.count == 1)
        #expect(Store.current(from: stored)?.accentPaletteID == "ember")
    }

    /// A deploy arriving **late** delivers both devices' rows at once. That is the duplicate case:
    /// the newest wins, the loser is left alone rather than deleted, and the next write goes to the
    /// winner and mints no third row.
    @Test func aLateDeployDeliveringTwoRowsCostsALookAndNeverTheStore() throws {
        let container = try CadenceTestStore.container()
        let context = ModelContext(container)
        let fromTheMac = LookPreference(accentPaletteID: "ember", updatedAt: Date(timeIntervalSince1970: 100))
        let fromThePhone = LookPreference(accentPaletteID: "glacier", updatedAt: Date(timeIntervalSince1970: 200))
        context.insert(fromTheMac)
        context.insert(fromThePhone)
        try context.save()

        let arrived = try context.fetch(FetchDescriptor<LookPreference>())
        #expect(arrived.count == 2)
        #expect(Store.current(from: arrived)?.accentPaletteID == "glacier")

        try Store.write(
            accentPaletteID: "cadence",
            sidebarTabColorsRaw: "",
            taskPresentationRaw: "",
            records: arrived,
            in: context,
            now: Date(timeIntervalSince1970: 300)
        )

        let after = try ModelContext(container).fetch(FetchDescriptor<LookPreference>())
        #expect(after.count == 2, "the write minted a third row")
        #expect(Store.current(from: after)?.accentPaletteID == "cadence")
        #expect(after.contains { $0.accentPaletteID == "ember" }, "the losing row was deleted")
    }

    /// A row that has never been written reads as "this device decides", not as a look of empty
    /// strings imposed on everything.
    @Test func aBareRecordChangesNothing() {
        let bare = LookPreference()
        #expect(bare.accentPaletteID.isEmpty)
        #expect(Store.mirrorWrites(forTaskPresentation: bare.taskPresentationRaw, on: .macOS).isEmpty)
        #expect(Store.mirrorWrites(forTaskPresentation: bare.taskPresentationRaw, on: .iOS).isEmpty)
    }
}
