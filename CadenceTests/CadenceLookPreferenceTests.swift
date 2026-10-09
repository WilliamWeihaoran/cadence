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
            calendarPresentationRaw: "",
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
            calendarPresentationRaw: "",
            records: [],
            in: context,
            now: Date(timeIntervalSince1970: 10)
        )
        let first = try context.fetch(FetchDescriptor<LookPreference>())

        try Store.write(
            accentPaletteID: "glacier",
            sidebarTabColorsRaw: "",
            taskPresentationRaw: "today.mode=newest",
            calendarPresentationRaw: "",
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
                calendarPresentationRaw: "",
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
            calendarPresentationRaw: "",
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
                calendarPresentationRaw: "",
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
            calendarPresentationRaw: "",
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
            calendarPresentationRaw: "",
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
        #expect(Store.mirrorWrites(forCalendarPresentation: bare.calendarPresentationRaw).isEmpty)
    }

    // MARK: - T-1347: the work-hours window

    /// The owner's sentence was *"all settings should sync too."* The window is two integers and
    /// one vocabulary on all three devices, so it needs no codec and no platform switch — which is
    /// the measurement, not an assumption: `CalendarWorkHoursPreferences` keys them `calendar.*`
    /// rather than `macos.*` and both Settings sections write the same two keys.
    @Test func bothPlatformsOwnTheSameTwoWorkHoursKeys() {
        let mirrors = Store.calendarMirrors()
        #expect(mirrors.map(\.defaultsKey) == [
            CalendarWorkHoursPreferences.startMinuteKey,
            CalendarWorkHoursPreferences.endMinuteKey
        ])
        #expect(mirrors.allSatisfy { $0.kind == .int })
        // The two maps are disjoint, so a calendar pair cannot land in the task column or vice
        // versa. This is the assertion behind the separate field.
        let taskKeys = Set((Store.mirrors(on: .macOS) + Store.mirrors(on: .iOS)).map(\.recordKey))
        #expect(taskKeys.intersection(Set(mirrors.map(\.recordKey))).isEmpty)
    }

    /// **The window must arrive as real `Int` defaults.** `@AppStorage(...) var startMinute = 540`
    /// reads `integer(forKey:)`, and a string-shaped `"540"` reads back as unset — so a mirror that
    /// wrote the record value verbatim would sync the setting and draw nine o'clock anyway.
    @Test func adoptingTheWindowWritesIntegersTheTimelineCanRead() throws {
        try withTemporaryDefaults("work-hours-adopt") { defaults in
            try withTemporaryDefaults("work-hours-adopt-accent") { accents in
                let sync = CadenceLookPreferenceSync(defaults: defaults, accentDefaults: accents, platform: .macOS)
                let record = LookPreference(calendarPresentationRaw: "workHours.end=1230;workHours.start=450")

                let changed = sync.adopt(records: [record], applyAccent: false)
                #expect(changed.contains(CalendarWorkHoursPreferences.startMinuteKey))
                #expect(changed.contains(CalendarWorkHoursPreferences.endMinuteKey))
                #expect(defaults.integer(forKey: CalendarWorkHoursPreferences.startMinuteKey) == 450)
                #expect(defaults.integer(forKey: CalendarWorkHoursPreferences.endMinuteKey) == 1230)
                #expect(defaults.object(forKey: CalendarWorkHoursPreferences.startMinuteKey) is Int)

                // A second adopt moves nothing, which is what stops the pair looping.
                #expect(sync.adopt(records: [record], applyAccent: false).isEmpty)
            }
        }
    }

    /// A value this build cannot read as a minute is left alone rather than coerced to zero, which
    /// would move the band to midnight on every device that read it.
    @Test func anUnreadableMinuteLeavesTheWindowWhereItIs() throws {
        try withTemporaryDefaults("work-hours-garbage") { defaults in
            try withTemporaryDefaults("work-hours-garbage-accent") { accents in
                defaults.set(9 * 60, forKey: CalendarWorkHoursPreferences.startMinuteKey)
                let sync = CadenceLookPreferenceSync(defaults: defaults, accentDefaults: accents, platform: .iOS)

                let changed = sync.adopt(
                    records: [LookPreference(calendarPresentationRaw: "workHours.start=half past nine")],
                    applyAccent: false
                )
                #expect(!changed.contains(CalendarWorkHoursPreferences.startMinuteKey))
                #expect(defaults.integer(forKey: CalendarWorkHoursPreferences.startMinuteKey) == 9 * 60)
            }
        }
    }

    /// A device that has never opened the picker says nothing, so it cannot publish a compiled-in
    /// nine-to-five over a window the owner set on another device.
    @Test func aDeviceThatNeverChoseAWindowPublishesNothing() throws {
        try withTemporaryDefaults("work-hours-unset") { defaults in
            #expect(Store.currentCalendarMirrors(in: defaults).isEmpty)

            let record = LookPreference(calendarPresentationRaw: "workHours.end=1230;workHours.start=450")
            #expect(
                Store.pendingWrite(
                    accentPaletteID: "",
                    sidebarTabColorsRaw: "",
                    currentMirrors: [:],
                    currentCalendarMirrors: Store.currentCalendarMirrors(in: defaults),
                    record: record,
                    on: .macOS
                ) == nil,
                "an unset picker proposed a write"
            )
        }
    }

    /// The round trip: a window chosen here is what the record carries, and a pair this build has
    /// no mirror for rides through untouched — the same rule the task map already has.
    @Test func aWindowChosenOnOneDeviceIsWhatTheRecordCarries() throws {
        try withTemporaryDefaults("work-hours-publish") { defaults in
            defaults.set(7 * 60 + 30, forKey: CalendarWorkHoursPreferences.startMinuteKey)
            defaults.set(16 * 60, forKey: CalendarWorkHoursPreferences.endMinuteKey)

            let record = LookPreference(calendarPresentationRaw: "workHours.start=540;weekStartsOn=monday")
            let pending = try #require(
                Store.pendingWrite(
                    accentPaletteID: "",
                    sidebarTabColorsRaw: "",
                    currentMirrors: [:],
                    currentCalendarMirrors: Store.currentCalendarMirrors(in: defaults),
                    record: record,
                    on: .macOS
                )
            )
            let pairs = Store.pairs(fromRaw: pending.calendarPresentationRaw)
            #expect(pairs["workHours.start"] == "450")
            #expect(pairs["workHours.end"] == "960")
            #expect(pairs["weekStartsOn"] == "monday", "a pair this build has no mirror for was dropped")
            // And the task column is untouched by a calendar edit.
            #expect(pending.taskPresentationRaw == record.taskPresentationRaw)
        }
    }

    /// The whole window survives a store write and comes back out of the record on the other side.
    @Test func theWindowSurvivesTheStore() throws {
        let container = try CadenceTestStore.container()
        let context = ModelContext(container)

        try Store.write(
            accentPaletteID: "",
            sidebarTabColorsRaw: "",
            taskPresentationRaw: "",
            calendarPresentationRaw: "workHours.end=1110;workHours.start=480",
            records: [],
            in: context,
            now: Date(timeIntervalSince1970: 10)
        )
        let rows = try context.fetch(FetchDescriptor<LookPreference>())
        #expect(rows.count == 1)

        try withTemporaryDefaults("work-hours-store") { defaults in
            try withTemporaryDefaults("work-hours-store-accent") { accents in
                let other = CadenceLookPreferenceSync(defaults: defaults, accentDefaults: accents, platform: .iOS)
                other.adopt(records: rows, applyAccent: false)
                let range = CalendarWorkHoursPreferences.normalizedRange(
                    startMinute: defaults.integer(forKey: CalendarWorkHoursPreferences.startMinuteKey),
                    endMinute: defaults.integer(forKey: CalendarWorkHoursPreferences.endMinuteKey)
                )
                #expect(range == .init(startMinute: 480, endMinute: 1110))
            }
        }
    }

    // MARK: - T-1347: a look row this build does not fully understand

    /// **A row written before the calendar column existed must not move the window.**
    ///
    /// This is not the hypothetical shape: every `LookPreference` already on the owner's other
    /// devices is spelled this way, and `CD_LookPreference` reaching Production will hand each of
    /// them to a build that now has two more keys to look for. The [[T-2076]] lesson was that the
    /// fix which mattered was proving the *stale* record keeps the setting rather than resetting
    /// it, so this asserts both halves at once: the keys the old row does carry are adopted, and
    /// the two it does not carry leave the person's window exactly where they left it.
    @Test func aLookRowFromBeforeTheCalendarColumnLeavesTheWindowAlone() throws {
        try withTemporaryDefaults("work-hours-stale") { defaults in
            try withTemporaryDefaults("work-hours-stale-accent") { accents in
                defaults.set(7 * 60 + 30, forKey: CalendarWorkHoursPreferences.startMinuteKey)
                defaults.set(16 * 60, forKey: CalendarWorkHoursPreferences.endMinuteKey)
                let sync = CadenceLookPreferenceSync(defaults: defaults, accentDefaults: accents, platform: .iOS)

                // The whole row as an older build wrote it: a task map, and no calendar column.
                let stale = LookPreference(
                    taskPresentationRaw: "today.mode=priority",
                    calendarPresentationRaw: ""
                )
                let changed = sync.adopt(records: [stale], applyAccent: false)

                #expect(
                    changed.contains(CadencePreferenceKeys.iosTodaySortMode),
                    "the stale row stopped carrying what it did carry"
                )
                #expect(!changed.contains(CalendarWorkHoursPreferences.startMinuteKey))
                #expect(!changed.contains(CalendarWorkHoursPreferences.endMinuteKey))
                #expect(defaults.integer(forKey: CalendarWorkHoursPreferences.startMinuteKey) == 7 * 60 + 30)
                #expect(defaults.integer(forKey: CalendarWorkHoursPreferences.endMinuteKey) == 16 * 60)
            }
        }
    }

    /// **Half a window is half a window, not a reset.**
    ///
    /// A record can carry one of the two keys and not the other: a write that only half landed, a
    /// build that knew one spelling, a pair dropped on the way. The absent-key rule has to hold
    /// per key rather than per map — adopt the half that arrived, leave the half that did not —
    /// and the band the timeline then draws has to still be a band, which is
    /// `normalizedRange`'s job and is checked here rather than assumed.
    @Test func halfAWorkHoursRecordLeavesTheOtherHalfWhereItIs() throws {
        try withTemporaryDefaults("work-hours-half") { defaults in
            try withTemporaryDefaults("work-hours-half-accent") { accents in
                defaults.set(8 * 60, forKey: CalendarWorkHoursPreferences.startMinuteKey)
                defaults.set(17 * 60, forKey: CalendarWorkHoursPreferences.endMinuteKey)
                let sync = CadenceLookPreferenceSync(defaults: defaults, accentDefaults: accents, platform: .macOS)

                let changed = sync.adopt(
                    records: [LookPreference(calendarPresentationRaw: "workHours.start=450")],
                    applyAccent: false
                )
                #expect(changed == [CalendarWorkHoursPreferences.startMinuteKey])
                #expect(defaults.integer(forKey: CalendarWorkHoursPreferences.startMinuteKey) == 450)
                #expect(
                    defaults.integer(forKey: CalendarWorkHoursPreferences.endMinuteKey) == 17 * 60,
                    "the half the record never carried was reset"
                )

                let range = CalendarWorkHoursPreferences.normalizedRange(
                    startMinute: defaults.integer(forKey: CalendarWorkHoursPreferences.startMinuteKey),
                    endMinute: defaults.integer(forKey: CalendarWorkHoursPreferences.endMinuteKey)
                )
                #expect(range == .init(startMinute: 450, endMinute: 17 * 60))

                // And the half that did not arrive is still this device's to publish, so the two
                // devices converge on a whole window rather than on half of one.
                #expect(Store.currentCalendarMirrors(in: defaults).count == 2)
            }
        }
    }

    // MARK: - T-3040: publish never runs before this launch's first adopt

    /// **The race, end to end: a setting touched before the record has been read.**
    ///
    /// `UserDefaults.didChangeNotification` fires for every write in the process and the host is
    /// subscribed before `onAppear` runs, so a publish can reach the record while `records` is
    /// still empty — which is also what a device mid-import sees. Minting there produces a row
    /// stamped `now` that `current(from:)` prefers over the row that arrives a moment later
    /// carrying a month of the owner's choices, and nothing merges the loser back: `LookPreference`
    /// is outside `DataIntegrityRepairService`'s dedupe set on purpose, because that pass *deletes*
    /// what it collapses and this model's "Duplicates" note forbids exactly that.
    ///
    /// So the assertion is on the row **set** and on **which row wins**, not on a return value: a
    /// guard that refused the write and minted anyway would pass a weaker test.
    @Test func aPublishBeforeTheFirstAdoptMintsNoRowForTheImportToLoseTo() throws {
        try withTemporaryDefaults("look-race") { defaults in
            try withTemporaryDefaults("look-race-accent") { accents in
                // This device has touched exactly one chip, so `currentMirrors` has something to
                // say and the all-empty candidate that stops an untouched device does not apply.
                defaults.set("Priority", forKey: CadencePreferenceKeys.allTasksSortField)

                let container = try CadenceTestStore.container()
                let context = ModelContext(container)
                let sync = CadenceLookPreferenceSync(defaults: defaults, accentDefaults: accents, platform: .macOS)
                #expect(sync.hasAdopted == false)

                // The notification arrives first. `records` is empty because the import has not
                // landed, not because the account is.
                sync.publish(records: [], in: context, now: Date(timeIntervalSince1970: 10_000))

                // Now the import lands, carrying the look the owner set a month ago.
                let imported = LookPreference(
                    accentPaletteID: "ember",
                    sidebarTabColorsRaw: "inbox=#FF0000",
                    taskPresentationRaw: "allTasks.grouping=project;inbox.mode=priority",
                    updatedAt: Date(timeIntervalSince1970: 1_000)
                )
                context.insert(imported)
                try context.save()

                let rows = try ModelContext(container).fetch(FetchDescriptor<LookPreference>())
                #expect(rows.count == 1, "the early publish minted a row the import then lost to")
                let winner = try #require(Store.current(from: rows))
                #expect(winner.accentPaletteID == "ember", "a minted row outranked the imported one")
                #expect(winner.taskPresentationRaw == "allTasks.grouping=project;inbox.mode=priority")
                #expect(winner.updatedAt == Date(timeIntervalSince1970: 1_000))
            }
        }
    }

    /// The bound that must survive the guard: a device that has touched nothing publishes nothing,
    /// *after* it has adopted as well as before. `currentMirrors` omits an unset key, so the
    /// candidate is empty and `pendingWrite` mints no row — a guard that started minting rows of
    /// pure defaults on every untouched device would be the regression this one is meant to avoid.
    @Test func anUntouchedDeviceStillMintsNothingOnceItHasAdopted() throws {
        try withTemporaryDefaults("look-race-untouched") { defaults in
            try withTemporaryDefaults("look-race-untouched-accent") { accents in
                let container = try CadenceTestStore.container()
                let context = ModelContext(container)
                let sync = CadenceLookPreferenceSync(defaults: defaults, accentDefaults: accents, platform: .macOS)

                #expect(sync.adopt(records: [], applyAccent: false).isEmpty)
                #expect(sync.hasAdopted, "the gate stayed shut on an empty record set")
                #expect(Store.currentMirrors(in: defaults, on: .macOS).isEmpty)

                sync.publish(records: [], in: context, now: Date(timeIntervalSince1970: 10_000))

                let rows = try ModelContext(container).fetch(FetchDescriptor<LookPreference>())
                #expect(rows.isEmpty, "a device with nothing to say minted a row")
            }
        }
    }

    /// **The obvious wrong fix is one that blocks legitimate writes, so both legitimate shapes are
    /// pinned here.**
    ///
    /// A device whose account genuinely has no row still mints one once it has looked — otherwise
    /// a first-ever user's settings would never reach a second device, which is worse than the bug
    /// being closed. And a device that has adopted a real row still writes into it rather than
    /// minting a second.
    @Test func aPublishAfterTheFirstAdoptStillReachesTheRecord() throws {
        try withTemporaryDefaults("look-race-after") { defaults in
            try withTemporaryDefaults("look-race-after-accent") { accents in
                defaults.set("Priority", forKey: CadencePreferenceKeys.allTasksSortField)

                let container = try CadenceTestStore.container()
                let context = ModelContext(container)
                let sync = CadenceLookPreferenceSync(defaults: defaults, accentDefaults: accents, platform: .macOS)

                // An account with no row: adopt reads an empty set, and the mint still happens.
                sync.adopt(records: [], applyAccent: false)
                sync.publish(records: [], in: context, now: Date(timeIntervalSince1970: 2_000))

                // Read back through a second context, so what is asserted is the store's answer
                // rather than one object's memory.
                let landed = try ModelContext(container).fetch(FetchDescriptor<LookPreference>())
                #expect(landed.count == 1, "the gate blocked a first-ever device's only write")
                #expect(Store.current(from: landed)?.taskPresentationRaw == "allTasks.mode=priority")

                // And a later local change goes into that row rather than minting a second. The
                // records come from `context`, which is the host's shape — the one app-wide
                // context the `@Query` and the write both sit in; an object fetched from a second
                // context would be edited where this `save()` cannot see it. No second adopt here
                // on purpose: in the host the record has not moved, so the only thing that runs is
                // the notification's publish.
                let minted = try context.fetch(FetchDescriptor<LookPreference>())
                defaults.set("Custom", forKey: CadencePreferenceKeys.allTasksSortField)
                sync.publish(records: minted, in: context, now: Date(timeIntervalSince1970: 3_000))

                let after = try ModelContext(container).fetch(FetchDescriptor<LookPreference>())
                #expect(after.count == 1, "a normal publish minted a second row")
                #expect(Store.current(from: after)?.taskPresentationRaw == "allTasks.mode=listOrder")
                #expect(sync.lastFailureNotice == nil)
            }
        }
    }

    // MARK: - T-3040's residual: what a minted row costs once it has already won

    /// **The clause `hasAdopted` cannot shut, and this does not claim to shut it either.**
    ///
    /// Nothing in-process can tell *"no row has downloaded yet"* from *"no row has ever existed"*
    /// while a cold CloudKit import is in flight, so a device that touches a setting inside that
    /// window still mints a row stamped `now`, and the import still arrives stamped older and still
    /// loses `current(from:)`. That ordering is not fixed here and nothing below asserts that it is.
    /// What is asserted is the **cost**: the imported row is still in the store — the model's
    /// *Duplicates* note is why nothing deletes it — so the month of choices it carries is readable
    /// instead of outranked into silence.
    ///
    /// The fixture is the lost case exactly: the minted row is newer and says one thing, about the
    /// one chip this device touched; the import is older and carries the accent, the tints and two
    /// pairs this device has never had an opinion about.
    @Test func anImportThatLostToAMintedRowStillGivesBackEverythingTheMintedRowIsSilentAbout() throws {
        try withTemporaryDefaults("look-fold") { defaults in
            try withTemporaryDefaults("look-fold-accent") { accents in
                let minted = LookPreference(
                    taskPresentationRaw: "allTasks.mode=priority",
                    updatedAt: Date(timeIntervalSince1970: 10_000)
                )
                let imported = LookPreference(
                    accentPaletteID: "ember",
                    sidebarTabColorsRaw: "inbox=#FF0000",
                    taskPresentationRaw: "allTasks.mode=listOrder;allTasks.grouping=project;inbox.mode=priority",
                    calendarPresentationRaw: "workHours.start=480;workHours.end=1020",
                    updatedAt: Date(timeIntervalSince1970: 1_000)
                )

                let sync = CadenceLookPreferenceSync(defaults: defaults, accentDefaults: accents, platform: .macOS)
                let changed = sync.adopt(records: [minted, imported], applyAccent: false)

                // The winner still wins everything it names: this device moved the All Tasks chip
                // and is not second-guessed by a row a month older that happens to mention it.
                #expect(
                    defaults.string(forKey: CadencePreferenceKeys.allTasksSortField) == TaskSortField.priority.rawValue,
                    "a losing row overrode a key the winner names"
                )
                // And everything the winner is silent about comes back.
                #expect(defaults.string(forKey: CadencePreferenceKeys.allTasksGroupingMode) == "project")
                #expect(
                    defaults.string(forKey: CadencePreferenceKeys.inboxSortField) == TaskSortField.priority.rawValue
                )
                #expect(defaults.string(forKey: CadencePreferenceKeys.sidebarTabColors) == "inbox=#FF0000")
                #expect(defaults.integer(forKey: CalendarWorkHoursPreferences.startMinuteKey) == 480)
                #expect(defaults.integer(forKey: CalendarWorkHoursPreferences.endMinuteKey) == 1_020)
                #expect(
                    changed.contains(CadenceAccentPaletteStore.defaultsKey),
                    "the palette the owner picked a month ago stayed lost"
                )
                #expect(Store.resolved(from: [minted, imported])?.accentPaletteID == "ember")

                // Non-vacuity: a key NO row names is still left exactly where this device had it,
                // which is the absent-key rule the fold must not have widened into "take anything".
                #expect(defaults.object(forKey: CadencePreferenceKeys.todaySortMode) == nil)
            }
        }
    }

    /// The fold can only ADD, and both directions of that are pinned here rather than inferred:
    /// a key the winner names is the winner's however old the row that disagrees, and the newest
    /// loser wins among losers. Pure, so it says what the grammar does without a container.
    @Test func foldingPrefersTheWinnerThenTheNewestLoserAndNeverTheOtherWayRound() {
        let winner = LookPreference(
            taskPresentationRaw: "allTasks.grouping=none",
            updatedAt: Date(timeIntervalSince1970: 300)
        )
        let middle = LookPreference(
            accentPaletteID: "glacier",
            taskPresentationRaw: "allTasks.grouping=project;inbox.mode=priority",
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let oldest = LookPreference(
            accentPaletteID: "ember",
            taskPresentationRaw: "inbox.mode=listOrder;today.mode=doDate",
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        let folded = Store.resolved(from: [oldest, winner, middle])
        #expect(folded?.taskPresentationRaw == "allTasks.grouping=none;inbox.mode=priority;today.mode=doDate")
        #expect(folded?.accentPaletteID == "glacier", "an older row outranked a newer one")
        #expect(folded?.sidebarTabColorsRaw.isEmpty == true, "a field no row names was invented")
        #expect(Store.resolved(from: []) == nil)

        // One row folds to itself, which is the case every ordinary device is in.
        #expect(Store.resolved(from: [winner])?.taskPresentationRaw == "allTasks.grouping=none")
        // And the row a write goes into is still the head of the same order, spelled once.
        #expect(Store.current(from: [oldest, winner, middle])?.id == winner.id)
        #expect(Store.ordered(from: [oldest, winner, middle]).map(\.id) == [winner.id, middle.id, oldest.id])
    }

    /// **Reading is not writing.** The fold must not look like a change: if it did, every launch
    /// over a two-row store would bump `updatedAt` and ship a write to the other two devices for
    /// having read. And it must not mint a third row either, which is the bound
    /// `aLateDeployDeliveringTwoRowsCostsALookAndNeverTheStore` holds for the un-folded path.
    ///
    /// Then the second half, which is where the recovery becomes durable: the next change the
    /// owner actually makes carries the recovered pairs up into the winning row, because
    /// `pendingWrite` starts from the folded reading rather than from the winner alone.
    @Test func theFoldPublishesNothingByItselfAndRidesUpOnTheNextRealChange() throws {
        try withTemporaryDefaults("look-fold-publish") { defaults in
            try withTemporaryDefaults("look-fold-publish-accent") { accents in
                let container = try CadenceTestStore.container()
                let context = ModelContext(container)
                let minted = LookPreference(
                    taskPresentationRaw: "allTasks.mode=priority",
                    updatedAt: Date(timeIntervalSince1970: 10_000)
                )
                let imported = LookPreference(
                    accentPaletteID: "ember",
                    sidebarTabColorsRaw: "inbox=#FF0000",
                    taskPresentationRaw: "allTasks.grouping=project",
                    updatedAt: Date(timeIntervalSince1970: 1_000)
                )
                context.insert(minted)
                context.insert(imported)
                try context.save()

                let rows = try context.fetch(FetchDescriptor<LookPreference>())
                let sync = CadenceLookPreferenceSync(defaults: defaults, accentDefaults: accents, platform: .macOS)
                sync.adopt(records: rows, applyAccent: false)
                sync.publish(records: rows, in: context, now: Date(timeIntervalSince1970: 20_000))

                let afterReading = try ModelContext(container).fetch(FetchDescriptor<LookPreference>())
                #expect(afterReading.count == 2, "reading the losing row minted a third")
                #expect(
                    Store.current(from: afterReading)?.updatedAt == Date(timeIntervalSince1970: 10_000),
                    "the fold published itself as a change"
                )
                #expect(
                    Store.current(from: afterReading)?.taskPresentationRaw == "allTasks.mode=priority",
                    "the fold rewrote the winning row for nothing"
                )

                // Now a real local change, and the recovered pairs go up with it.
                defaults.set("Custom", forKey: CadencePreferenceKeys.allTasksSortField)
                sync.publish(records: rows, in: context, now: Date(timeIntervalSince1970: 30_000))

                let afterChange = try ModelContext(container).fetch(FetchDescriptor<LookPreference>())
                #expect(afterChange.count == 2, "the change minted a third row")
                let winner = try #require(Store.current(from: afterChange))
                #expect(winner.taskPresentationRaw == "allTasks.grouping=project;allTasks.mode=listOrder")
                #expect(winner.accentPaletteID == "ember", "the recovered palette was dropped on the next write")
                #expect(winner.sidebarTabColorsRaw == "inbox=#FF0000")
                #expect(afterChange.contains { $0.accentPaletteID == "ember" && $0.taskPresentationRaw == "allTasks.grouping=project" },
                        "the losing row was deleted")
            }
        }
    }
}
