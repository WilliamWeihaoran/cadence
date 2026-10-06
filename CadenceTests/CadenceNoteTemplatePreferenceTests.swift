import Foundation
import SwiftData
import Testing
@testable import Cadence

/// The synced note templates (T-1346): what travels between the owner's Mac, iPhone and iPad, what
/// happens to the templates a device already held, and what two devices do to each other.
///
/// The owner's sentence, and the rule this suite is written against: *"the note templates should
/// sync. all data should sync across devices."* R64 found this to be the one real gap against that
/// question — a template the user wrote is the same kind of thing as a note they wrote.
///
/// Everything here runs against `CadenceNoteTemplatePreferenceStore`'s pure half or against an
/// in-memory store with mirroring off. Nothing in this file touches the owner's container.
@MainActor
struct CadenceNoteTemplatePreferenceTests {

    private typealias Store = CadenceNoteTemplatePreferenceStore

    private func customised(_ id: String, title: String, body: String, in raw: String = "") -> String {
        NoteTemplateLibrary.setOverride(for: id, title: title, subtitle: "", body: body, in: raw)
    }

    // MARK: - The canonical spelling

    /// `""`, `"{}"` and two key orderings of the same map all mean one thing, and the sync compares
    /// canonical forms so that they cannot read as three different states ringing between the two
    /// layers forever.
    @Test func theSameMapHasExactlyOneCanonicalSpelling() {
        #expect(Store.canonicalRaw("") == nil, "the untouched default says nothing")
        #expect(Store.canonicalRaw("   ") == nil)
        #expect(Store.canonicalRaw("{}") == Store.emptyRaw)
        #expect(Store.emptyRaw == "{}")

        let a = ##"{"checklist":{"body":"# A","subtitle":"","title":"A"},"daily-plan":{"body":"# B","subtitle":"","title":"B"}}"##
        let b = ##"{"daily-plan":{"title":"B","subtitle":"","body":"# B"},"checklist":{"title":"A","subtitle":"","body":"# A"}}"##
        #expect(Store.canonicalRaw(a) != nil)
        #expect(Store.canonicalRaw(a) == Store.canonicalRaw(b), "key order read as a change")
    }

    /// **A string this build cannot parse must never be published as a reset.** `overrides(from:)`
    /// answers `[:]` for it, which is right for a template list that has to draw something; the
    /// sync asks `decodedOverrides` instead, and `nil` there means "say nothing".
    @Test func anUnreadableLocalStringSaysNothingRatherThanSayingEmpty() {
        #expect(Store.canonicalRaw("not json at all") == nil)
        #expect(Store.canonicalRaw(#"{"checklist":"a bare string"}"#) == nil)
        // The reader every template surface uses keeps its old, forgiving answer.
        #expect(NoteTemplateLibrary.overrides(from: "not json at all").isEmpty)
        #expect(NoteTemplateLibrary.decodedOverrides(from: "not json at all") == nil)
        // A parsed empty map is a *decision* — what Reset Template leaves — and is not `nil`.
        #expect(NoteTemplateLibrary.decodedOverrides(from: "{}") != nil)
    }

    /// A template id this build has no stencil for is a newer build's template. It survives the
    /// round trip rather than being dropped, unlike `SidebarLayoutPreference`'s unrecognised
    /// destination tokens — this map is keyed data, not a layout this build has to place.
    @Test func aTemplateIDThisBuildDoesNotKnowSurvivesTheRoundTrip() throws {
        let raw = ##"{"retrospective":{"body":"# Retro","subtitle":"","title":"Retro"}}"##
        let canonical = try #require(Store.canonicalRaw(raw))
        #expect(canonical.contains("retrospective"))
        #expect(NoteTemplateLibrary.overrides(from: canonical)["retrospective"]?.title == "Retro")

        // And an edit to a known template leaves it alone, which is the existing `setOverride`
        // behaviour this ticket relies on rather than re-implementing.
        let edited = customised("checklist", title: "Packing", body: "# Packing", in: canonical)
        #expect(NoteTemplateLibrary.overrides(from: edited)["retrospective"]?.title == "Retro")
    }

    // MARK: - Which record

    /// Two devices can each mint a row before either sees the other's; CloudKit forbids the unique
    /// constraint that would stop it. Newest edit wins, `id` breaks a tie, and every device picks
    /// the same one — otherwise each picks its own and they overwrite each other forever.
    @Test func theNewestTemplateRowWinsAndTheIDBreaksATie() {
        let old = NoteTemplatePreference(overridesRaw: "{}", updatedAt: Date(timeIntervalSince1970: 100))
        let recent = NoteTemplatePreference(
            overridesRaw: customised("checklist", title: "Packing", body: "# Packing"),
            updatedAt: Date(timeIntervalSince1970: 900)
        )
        #expect(Store.current(from: [old, recent])?.id == recent.id)
        #expect(Store.current(from: [recent, old])?.id == recent.id)
        #expect(Store.current(from: []) == nil)

        let moment = Date(timeIntervalSince1970: 500)
        let first = NoteTemplatePreference(overridesRaw: "{}", updatedAt: moment)
        let second = NoteTemplatePreference(overridesRaw: "{}", updatedAt: moment)
        let winner = first.id.uuidString < second.id.uuidString ? second : first
        #expect(Store.current(from: [first, second])?.id == winner.id)
        #expect(Store.current(from: [second, first])?.id == winner.id)
    }

    /// **No row is the device-local answer, and it is deliberately silent.** That is the shape of
    /// "`CD_NoteTemplatePreference` is not deployed to Production yet" *and* of "nothing has
    /// downloaded yet", and nothing can tell them apart — so the local default stands and no notice
    /// is shown.
    @Test func withNoRowTheDeviceLocalOverridesStand() {
        let local = customised("checklist", title: "Packing", body: "# Packing")
        #expect(Store.overridesRaw(from: [], localRaw: local) == local)

        // With a row, the row — **including an empty one**, because `{}` is the exact state Reset
        // Template leaves and a reset has to travel.
        let reset = NoteTemplatePreference(overridesRaw: "{}", updatedAt: Date(timeIntervalSince1970: 1))
        #expect(Store.overridesRaw(from: [reset], localRaw: local) == "{}")
    }

    // MARK: - The first-run merge

    /// The one moment a union is sound: this device has never published, so a key the record does
    /// not hold cannot be one somebody reset — the record has never heard from this device at all.
    @Test func theFirstRunMergeUnionsRatherThanOverwriting() throws {
        let local = customised("checklist", title: "Packing", body: "# Packing")
        let remote = customised("daily-plan", title: "Morning", body: "# Morning")

        let merged = try #require(Store.firstRunMerge(localRaw: local, recordRaw: remote))
        #expect(merged["checklist"]?.title == "Packing")
        #expect(merged["daily-plan"]?.title == "Morning")
    }

    /// Remote wins a key both hold: the record is shared state two other devices may already be
    /// reading, and this device's copy of the same id is the older claim by construction. Since
    /// that leaves the record holding exactly what it held, **no write is proposed at all** — a
    /// seed that bumped `updatedAt` for an unchanged map would move this row to the front of the
    /// duplicate rule on three devices for nothing.
    @Test func theFirstRunMergeLetsTheRecordWinAKeyBothHold() throws {
        let local = customised("checklist", title: "Mine", body: "# Mine")
        let remote = customised("checklist", title: "Theirs", body: "# Theirs")

        #expect(Store.firstRunMerge(localRaw: local, recordRaw: remote) == nil)

        // And with a second local key the record has never seen, the merge is the union — the
        // remote spelling of the shared id, plus the one only this device holds.
        let localPlus = customised("daily-plan", title: "Morning", body: "# Morning", in: local)
        let merged = try #require(Store.firstRunMerge(localRaw: localPlus, recordRaw: remote))
        #expect(merged["checklist"]?.title == "Theirs", "the local copy of a shared id won")
        #expect(merged["daily-plan"]?.title == "Morning")
        #expect(merged.count == 2)
    }

    /// Nothing to contribute, nothing written. A device with no local customisation must not mint a
    /// row — three fresh devices seeding `{}` at each other is the failure R64 warned about by
    /// name.
    @Test func aDeviceWithNothingToContributeSeedsNothing() {
        #expect(Store.firstRunMerge(localRaw: "", recordRaw: nil) == nil)
        #expect(Store.firstRunMerge(localRaw: "{}", recordRaw: nil) == nil)
        #expect(Store.firstRunMerge(localRaw: "corrupt", recordRaw: nil) == nil)

        // And a local map the record already holds in full is not a write either.
        let both = customised("checklist", title: "Packing", body: "# Packing")
        #expect(Store.firstRunMerge(localRaw: both, recordRaw: both) == nil)
    }

    // MARK: - Round trip through a real store

    /// The behavioural half: a customisation written on one device is what the other device reads,
    /// multiline markdown body and all.
    @Test func anEditOnOneDeviceIsWhatTheOtherDeviceReads() throws {
        let container = try CadenceTestStore.container()
        let context = ModelContext(container)
        let body = """
        ---
        tags: [packing]
        ---

        # Packing

        ○ Passport
        ○ Charger

        """
        let raw = customised("checklist", title: "Packing", body: body)

        try Store.write(raw, records: [], in: context, now: Date(timeIntervalSince1970: 10))
        let records = try context.fetch(FetchDescriptor<NoteTemplatePreference>())
        #expect(records.count == 1)

        try withTemporaryDefaults("template-adopt") { defaults in
            let other = CadenceNoteTemplatePreferenceSync(defaults: defaults)
            #expect(other.reconcile(records: records, in: context))

            let adopted = defaults.string(forKey: NoteTemplateLibrary.storageKey) ?? ""
            let template = try #require(
                NoteTemplateLibrary.templates(for: .list, overridesRaw: adopted).first { $0.id == "checklist" }
            )
            #expect(template.title == "Packing")
            #expect(template.body == body, "the markdown body did not survive the trip")
            #expect(NoteTemplateLibrary.isCustomized(template, overridesRaw: adopted))
        }
    }

    /// **An empty body is a real edit** and `resolved(_:with:)` has no fallback for it — the rule
    /// `setOverride` already carried. Syncing must not quietly restore the default body.
    @Test func anEmptyBodySurvivesTheTripAsAnEmptyBody() throws {
        let raw = customised("checklist", title: "Blank", body: "")
        let container = try CadenceTestStore.container()
        let context = ModelContext(container)
        try Store.write(raw, records: [], in: context, now: Date(timeIntervalSince1970: 10))
        let records = try context.fetch(FetchDescriptor<NoteTemplatePreference>())

        try withTemporaryDefaults("template-empty-body") { defaults in
            let sync = CadenceNoteTemplatePreferenceSync(defaults: defaults)
            sync.reconcile(records: records, in: context)
            let adopted = defaults.string(forKey: NoteTemplateLibrary.storageKey) ?? ""
            let template = try #require(
                NoteTemplateLibrary.templates(for: .list, overridesRaw: adopted).first { $0.id == "checklist" }
            )
            #expect(template.body.isEmpty)
            // And the empty *title* still falls back, which is the other half of the same rule.
            #expect(template.title == "Blank")
        }
    }

    /// A reset on one device is a reset on the other. `{}` in the record is a value, not an
    /// absence, which is the one place this bridge deliberately differs from
    /// `CadenceLookPreferenceSync`'s "empty means never chosen".
    @Test func aResetOnOneDeviceTravelsAsAReset() throws {
        let container = try CadenceTestStore.container()
        let context = ModelContext(container)
        let customisedRaw = customised("checklist", title: "Packing", body: "# Packing")

        try withTemporaryDefaults("template-reset") { defaults in
            defaults.set(customisedRaw, forKey: NoteTemplateLibrary.storageKey)
            let sync = CadenceNoteTemplatePreferenceSync(defaults: defaults)

            // This device seeds its customisation, then the other device resets it.
            sync.reconcile(records: [], in: context)
            var records = try context.fetch(FetchDescriptor<NoteTemplatePreference>())
            #expect(records.count == 1)

            let remoteReset = NoteTemplateLibrary.resetOverride(for: "checklist", in: customisedRaw)
            try Store.write(remoteReset, records: records, in: context, now: Date(timeIntervalSince1970: 9_000))
            records = try context.fetch(FetchDescriptor<NoteTemplatePreference>())

            #expect(sync.adopt(records: records), "the reset did not reach the local default")
            let adopted = defaults.string(forKey: NoteTemplateLibrary.storageKey) ?? ""
            let template = try #require(
                NoteTemplateLibrary.templates(for: .list, overridesRaw: adopted).first { $0.id == "checklist" }
            )
            let stock = try #require(NoteTemplateLibrary.defaultTemplate(id: "checklist"))
            #expect(template == stock, "Reset Template stopped meaning reset")
            #expect(!NoteTemplateLibrary.isCustomized(stock, overridesRaw: adopted))
        }
    }

    // MARK: - Seeding is once, and it does not double-apply

    /// The migration the ticket turns on: somebody already has customised templates in local
    /// defaults, and they must arrive in the shared row without being applied twice.
    @Test func anExistingLocalCustomisationSeedsTheRowExactlyOnce() throws {
        let container = try CadenceTestStore.container()
        let context = ModelContext(container)
        let local = customised("checklist", title: "Packing", body: "# Packing")

        try withTemporaryDefaults("template-seed-once") { defaults in
            defaults.set(local, forKey: NoteTemplateLibrary.storageKey)
            let sync = CadenceNoteTemplatePreferenceSync(defaults: defaults)
            #expect(!sync.hasSeeded)

            sync.reconcile(records: [], in: context)
            var records = try context.fetch(FetchDescriptor<NoteTemplatePreference>())
            #expect(records.count == 1)
            #expect(sync.hasSeeded)
            #expect(NoteTemplateLibrary.overrides(from: records[0].overridesRaw)["checklist"]?.title == "Packing")

            // Running it again — a relaunch, a remote row arriving — mints nothing further.
            sync.reconcile(records: records, in: context)
            sync.reconcile(records: records, in: context)
            records = try context.fetch(FetchDescriptor<NoteTemplatePreference>())
            #expect(records.count == 1, "the seed ran twice")
        }
    }

    /// The second device to migrate **merges into the existing row rather than minting a second
    /// one**, which is the "must not double-apply if two devices both migrate" half.
    @Test func aSecondDeviceMigratingMergesIntoTheRowRatherThanMintingAnother() throws {
        let container = try CadenceTestStore.container()
        let context = ModelContext(container)

        // Device one's row, already in the store.
        try Store.write(
            customised("daily-plan", title: "Morning", body: "# Morning"),
            records: [], in: context, now: Date(timeIntervalSince1970: 10)
        )
        var records = try context.fetch(FetchDescriptor<NoteTemplatePreference>())

        try withTemporaryDefaults("template-seed-second") { defaults in
            defaults.set(customised("checklist", title: "Packing", body: "# Packing"),
                         forKey: NoteTemplateLibrary.storageKey)
            let second = CadenceNoteTemplatePreferenceSync(defaults: defaults)
            second.reconcile(records: records, in: context, now: Date(timeIntervalSince1970: 20))

            records = try context.fetch(FetchDescriptor<NoteTemplatePreference>())
            #expect(records.count == 1, "the second device minted a duplicate row")
            let merged = NoteTemplateLibrary.overrides(from: records[0].overridesRaw)
            #expect(merged["daily-plan"]?.title == "Morning", "device one's template was overwritten")
            #expect(merged["checklist"]?.title == "Packing", "device two's template was dropped")

            // And the local default now holds the merged map, not the pre-merge record.
            let adopted = defaults.string(forKey: NoteTemplateLibrary.storageKey) ?? ""
            #expect(NoteTemplateLibrary.overrides(from: adopted).count == 2)
        }
    }

    /// A device with nothing of its own adopts and mints nothing.
    @Test func aFreshDeviceAdoptsWithoutSeeding() throws {
        let container = try CadenceTestStore.container()
        let context = ModelContext(container)
        try Store.write(
            customised("checklist", title: "Packing", body: "# Packing"),
            records: [], in: context, now: Date(timeIntervalSince1970: 10)
        )
        let records = try context.fetch(FetchDescriptor<NoteTemplatePreference>())

        try withTemporaryDefaults("template-fresh") { defaults in
            let sync = CadenceNoteTemplatePreferenceSync(defaults: defaults)
            #expect(sync.reconcile(records: records, in: context))
            let freshRows = try context.fetch(FetchDescriptor<NoteTemplatePreference>())
            #expect(freshRows.count == 1)
            #expect(sync.hasSeeded)
            let adopted = defaults.string(forKey: NoteTemplateLibrary.storageKey) ?? ""
            #expect(NoteTemplateLibrary.overrides(from: adopted)["checklist"]?.title == "Packing")
        }
    }

    // MARK: - Adopt and publish cannot loop

    /// Adopt writes the local default only when the canonical forms differ, and publish commits
    /// only on a real diff. So a record read down leaves nothing for the publish it might trigger,
    /// which is what keeps the pair from ringing between the two layers forever.
    @Test func adoptingATemplateRowLeavesNothingToPublish() throws {
        let container = try CadenceTestStore.container()
        let context = ModelContext(container)
        try Store.write(
            customised("checklist", title: "Packing", body: "# Packing"),
            records: [], in: context, now: Date(timeIntervalSince1970: 10)
        )
        let records = try context.fetch(FetchDescriptor<NoteTemplatePreference>())
        let before = records[0].updatedAt

        try withTemporaryDefaults("template-loop") { defaults in
            let sync = CadenceNoteTemplatePreferenceSync(defaults: defaults)
            #expect(sync.reconcile(records: records, in: context))
            #expect(!sync.adopt(records: records), "a second adopt moved something")

            sync.publish(records: records, in: context, now: Date(timeIntervalSince1970: 9_000))
            #expect(records[0].updatedAt == before, "publish bumped a record it had nothing to say about")
            let loopRows = try context.fetch(FetchDescriptor<NoteTemplatePreference>())
            #expect(loopRows.count == 1)
        }
    }

    /// A real local edit does reach the record, and it is the whole map that travels.
    @Test func aLocalEditPublishesTheWholeMap() throws {
        let container = try CadenceTestStore.container()
        let context = ModelContext(container)

        try withTemporaryDefaults("template-publish") { defaults in
            let sync = CadenceNoteTemplatePreferenceSync(defaults: defaults)
            sync.reconcile(records: [], in: context)
            #expect(sync.hasSeeded)
            let beforeEdit = try context.fetch(FetchDescriptor<NoteTemplatePreference>())
            #expect(beforeEdit.isEmpty)

            // The Settings surface writes the same `@AppStorage` key it always wrote.
            defaults.set(customised("checklist", title: "Packing", body: "# Packing"),
                         forKey: NoteTemplateLibrary.storageKey)
            sync.publish(records: [], in: context, now: Date(timeIntervalSince1970: 10))

            let records = try context.fetch(FetchDescriptor<NoteTemplatePreference>())
            #expect(records.count == 1)
            #expect(NoteTemplateLibrary.overrides(from: records[0].overridesRaw)["checklist"]?.title == "Packing")
        }
    }

    /// **Publish is refused before the seed decision has been made.** Dozens of unrelated
    /// `@AppStorage` writes fire `UserDefaults.didChangeNotification` at launch, and one of them
    /// arriving first must not push this device's map up as a plain overwrite and pre-empt the
    /// merge — that is the one place another device's customisations could be lost without anybody
    /// editing a template.
    @Test func publishIsRefusedUntilTheSeedDecisionHasBeenMade() throws {
        let container = try CadenceTestStore.container()
        let context = ModelContext(container)
        try Store.write(
            customised("daily-plan", title: "Morning", body: "# Morning"),
            records: [], in: context, now: Date(timeIntervalSince1970: 10)
        )
        let records = try context.fetch(FetchDescriptor<NoteTemplatePreference>())

        try withTemporaryDefaults("template-publish-gate") { defaults in
            defaults.set(customised("checklist", title: "Packing", body: "# Packing"),
                         forKey: NoteTemplateLibrary.storageKey)
            let sync = CadenceNoteTemplatePreferenceSync(defaults: defaults)

            sync.publish(records: records, in: context, now: Date(timeIntervalSince1970: 20))
            #expect(
                NoteTemplateLibrary.overrides(from: records[0].overridesRaw)["daily-plan"] != nil,
                "an early publish overwrote the shared row before the merge could run"
            )

            // After the seed, the same map is merged rather than substituted.
            sync.reconcile(records: records, in: context, now: Date(timeIntervalSince1970: 30))
            let merged = NoteTemplateLibrary.overrides(from: records[0].overridesRaw)
            #expect(merged.count == 2)
        }
    }

    /// An unreadable local default is repaired by the record rather than published over it.
    @Test func anUnreadableLocalDefaultIsRepairedNotPropagated() throws {
        let container = try CadenceTestStore.container()
        let context = ModelContext(container)
        let good = customised("checklist", title: "Packing", body: "# Packing")
        try Store.write(good, records: [], in: context, now: Date(timeIntervalSince1970: 10))
        let records = try context.fetch(FetchDescriptor<NoteTemplatePreference>())

        try withTemporaryDefaults("template-corrupt") { defaults in
            defaults.set("}{ not json", forKey: NoteTemplateLibrary.storageKey)
            let sync = CadenceNoteTemplatePreferenceSync(defaults: defaults)

            sync.reconcile(records: records, in: context)
            #expect(NoteTemplateLibrary.overrides(from: records[0].overridesRaw)["checklist"]?.title == "Packing")
            let adopted = defaults.string(forKey: NoteTemplateLibrary.storageKey) ?? ""
            #expect(NoteTemplateLibrary.overrides(from: adopted)["checklist"]?.title == "Packing")

            defaults.set("}{ not json", forKey: NoteTemplateLibrary.storageKey)
            sync.publish(records: records, in: context, now: Date(timeIntervalSince1970: 9_000))
            #expect(
                NoteTemplateLibrary.overrides(from: records[0].overridesRaw)["checklist"]?.title == "Packing",
                "a corrupt local string became every device's reset"
            )
        }
    }

    // MARK: - A refused commit

    /// The write commits through `CadencePendingChangePersistence`, so a refusal puts the record
    /// back where it was and leaves nothing pending in the app's single `ModelContext`.
    @Test func aRefusedEditLeavesTheRecordWhereItWas() throws {
        struct Refusal: Error {}
        let container = try CadenceTestStore.container()
        let context = ModelContext(container)
        let original = customised("checklist", title: "Packing", body: "# Packing")
        try Store.write(original, records: [], in: context, now: Date(timeIntervalSince1970: 10))
        let records = try context.fetch(FetchDescriptor<NoteTemplatePreference>())
        let before = records[0].overridesRaw
        let beforeUpdatedAt = records[0].updatedAt

        #expect(throws: Refusal.self) {
            try Store.write(
                customised("daily-plan", title: "Morning", body: "# Morning"),
                records: records, in: context,
                now: Date(timeIntervalSince1970: 9_000),
                commit: { _ in throw Refusal() }
            )
        }
        #expect(records[0].overridesRaw == before)
        #expect(records[0].updatedAt == beforeUpdatedAt)
    }

    /// A refused *seed* leaves the flag clear, so the next launch tries again rather than silently
    /// abandoning this device's templates.
    @Test func aRefusedSeedIsRetriedOnTheNextLaunch() throws {
        struct Refusal: Error {}
        let container = try CadenceTestStore.container()
        let context = ModelContext(container)

        try withTemporaryDefaults("template-seed-refused") { defaults in
            defaults.set(customised("checklist", title: "Packing", body: "# Packing"),
                         forKey: NoteTemplateLibrary.storageKey)
            let sync = CadenceNoteTemplatePreferenceSync(defaults: defaults)

            #expect(sync.seedIfNeeded(records: [], in: context, commit: { _ in throw Refusal() }) == nil)
            #expect(!sync.hasSeeded, "a refused seed marked itself done")
            #expect(sync.lastFailureNotice == CadencePendingChangePersistence.editFailureNotice)
            let afterRefusal = try context.fetch(FetchDescriptor<NoteTemplatePreference>())
            #expect(afterRefusal.isEmpty)

            #expect(sync.seedIfNeeded(records: [], in: context, now: Date(timeIntervalSince1970: 10)) != nil)
            #expect(sync.hasSeeded)
            #expect(sync.lastFailureNotice == nil)
            let afterRetry = try context.fetch(FetchDescriptor<NoteTemplatePreference>())
            #expect(afterRetry.count == 1)
        }
    }

    // MARK: - The template feature is unchanged

    /// **Do not silently change what a template IS.** The three behaviours the Settings surfaces
    /// depend on are decided by `NoteTemplateLibrary` and this ticket did not touch them: an empty
    /// title or subtitle falls back to the default, an edit equal to the default stores no
    /// override, and the seeded body still opens with its `# Title`.
    @Test func theTemplateRulesAreStillNoteTemplateLibrarys() throws {
        let stock = try #require(NoteTemplateLibrary.defaultTemplate(id: "checklist"))
        #expect(stock.body.hasPrefix("# Checklist"))

        // An edit back to the default is not an override.
        let restored = NoteTemplateLibrary.setOverride(
            for: stock.id, title: stock.title, subtitle: stock.subtitle, body: stock.body, in: ""
        )
        #expect(NoteTemplateLibrary.overrides(from: restored).isEmpty)
        #expect(Store.canonicalRaw(restored) == Store.emptyRaw)

        // A cleared title asks for the default back rather than recording an empty one.
        let clearedTitle = NoteTemplateLibrary.setOverride(
            for: stock.id, title: "", subtitle: stock.subtitle, body: "# Mine", in: ""
        )
        let resolved = try #require(
            NoteTemplateLibrary.templates(for: .list, overridesRaw: clearedTitle).first { $0.id == stock.id }
        )
        #expect(resolved.title == stock.title)
        #expect(resolved.body == "# Mine")
    }

    /// Non-vacuity for the suite's premise: the model really is in the schema, and really is the
    /// additive shape a deployed CloudKit store demands.
    @Test func theRecordIsRegisteredAndAdditive() throws {
        let entity = try #require(CadenceSchema.schema.entities.first { $0.name == "NoteTemplatePreference" })
        #expect(entity.relationships.isEmpty, "a relationship here would need an inverse and a delete rule")
        #expect(entity.uniquenessConstraints.isEmpty, "CloudKit forbids a unique constraint")
        #expect(entity.properties.count >= 4)

        // Every property defaults, which is what makes the type readable by a store that has never
        // seen it. A fresh instance is the proof the initialiser needs no argument.
        let fresh = NoteTemplatePreference()
        #expect(fresh.overridesRaw.isEmpty)
        #expect(fresh.createdAt == fresh.updatedAt)
    }

    // MARK: - A record this build does not fully understand (T-1346)

    /// **The guard `publish` already has, read the other way round.**
    ///
    /// `publish` refuses to turn a local string it cannot parse into a reset inside the record, so
    /// one device's corruption cannot become every device's — `anUnreadableLocalDefaultIsRepaired`
    /// `NotPropagated` pins that. The record→device direction had no matching rule: `adopt` passed
    /// `overridesRaw` straight into `writeLocal`, which canonicalises a string it cannot read to
    /// `{}`. So a row this build could not read **erased the templates on every device that
    /// received it** — the [[T-2076]] shape (a record naming things this build has no reading for)
    /// with the worse outcome, because a reset is a setting the user chose, gone.
    ///
    /// Two shapes arrive that way and neither is hypothetical. `""` is what SwiftData hands back
    /// for a field a CloudKit record did not carry — a partially written record, or a row from a
    /// build that does not write this column — and `theRecordIsRegisteredAndAdditive` pins that a
    /// fresh row really is spelled exactly that way. A map in an encoding this build cannot decode
    /// is what a *newer* build's row looks like from here.
    ///
    /// The rule is the publish side's, stated once more for the read: **a string that says nothing
    /// is not a reset.** `{}` still is one, which is the line this guard must not cross.
    @Test func aRecordThisBuildCannotReadLeavesTheTemplatesAlone() {
        let local = customised("checklist", title: "Packing", body: "# Packing")
        let newest = Date(timeIntervalSince1970: 50)

        // The field never arrived.
        #expect(
            Store.overridesRaw(from: [NoteTemplatePreference(overridesRaw: "", updatedAt: newest)], localRaw: local)
                == local,
            "a row carrying no map erased this device's templates"
        )

        // The map is in a shape this build cannot decode.
        let foreignRaw = ##"{"checklist":{"v":2,"body":"# Packing"}}"##
        #expect(Store.canonicalRaw(foreignRaw) == nil, "the fixture decodes here, so it proves nothing")
        #expect(
            Store.overridesRaw(from: [NoteTemplatePreference(overridesRaw: foreignRaw, updatedAt: newest)], localRaw: local)
                == local,
            "a newer build's encoding erased this device's templates"
        )

        // A deliberate reset is a value and still travels. This is the distinction the guard rests
        // on, and it holds only because `write` canonicalises: the reset this app stores is `{}`,
        // never `""`.
        #expect(
            Store.overridesRaw(from: [NoteTemplatePreference(overridesRaw: "{}", updatedAt: newest)], localRaw: local)
                == "{}"
        )
        #expect(Store.emptyRaw == "{}")
    }

    /// When one row is unreadable and an older one is not, the **older readable row** is what the
    /// device shows.
    ///
    /// `current(from:)` is unchanged and still answers the newest row: it is the row every device
    /// writes to, and moving the write target would stop the three devices converging on one row.
    /// What changes is the read — an unreadable winner means "this row tells me nothing", and the
    /// next thing a device can honestly show is the newest row that does tell it something. The
    /// unreadable row is left inert rather than deleted, as every loser here is, and the next local
    /// edit publishes over it and repairs it.
    @Test func anOlderReadableRowIsPreferredToANewerUnreadableOne() {
        let readable = NoteTemplatePreference(
            overridesRaw: customised("checklist", title: "Packing", body: "# Packing"),
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        let unreadable = NoteTemplatePreference(
            overridesRaw: "}{ not json",
            updatedAt: Date(timeIntervalSince1970: 99)
        )
        let rows = [readable, unreadable]

        #expect(Store.current(from: rows)?.id == unreadable.id, "the write target moved")
        #expect(Store.currentReadable(from: rows)?.id == readable.id)
        let shown = Store.overridesRaw(from: rows, localRaw: "")
        #expect(NoteTemplateLibrary.overrides(from: shown)["checklist"]?.title == "Packing")
    }

    /// And the same thing end to end, through the bridge the app actually runs: a foreign row
    /// arriving must not move `noteTemplateOverrides`, and the next local edit must repair it.
    @Test func aForeignRowArrivingDoesNotTouchTheLocalDefault() throws {
        let container = try CadenceTestStore.container()
        let context = ModelContext(container)
        let mine = customised("checklist", title: "Packing", body: "# Packing")

        try withTemporaryDefaults("template-foreign") { defaults in
            defaults.set(mine, forKey: NoteTemplateLibrary.storageKey)
            let sync = CadenceNoteTemplatePreferenceSync(defaults: defaults)

            // This device has already contributed; the steady state, not the first run.
            sync.reconcile(records: [], in: context, now: Date(timeIntervalSince1970: 10))
            #expect(sync.hasSeeded)

            let foreign = NoteTemplatePreference(
                overridesRaw: ##"{"checklist":{"v":2,"body":"# Packing"}}"##,
                updatedAt: Date(timeIntervalSince1970: 9_000)
            )
            context.insert(foreign)

            #expect(!sync.adopt(records: [foreign]), "an unreadable row moved the local default")
            let after = defaults.string(forKey: NoteTemplateLibrary.storageKey) ?? ""
            #expect(
                NoteTemplateLibrary.overrides(from: after)["checklist"]?.title == "Packing",
                "a row this build cannot read reset the owner's templates"
            )

            // The repair: this device's next publish overwrites the unintelligible row rather than
            // leaving the three devices stuck on something none of them can read.
            sync.publish(records: [foreign], in: context, now: Date(timeIntervalSince1970: 9_100))
            #expect(NoteTemplateLibrary.overrides(from: foreign.overridesRaw)["checklist"]?.title == "Packing")
        }
    }
}
