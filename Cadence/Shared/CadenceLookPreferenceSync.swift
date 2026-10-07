import Combine
import Foundation
import SwiftData
import SwiftUI

/// The one thing that carries values between the synced `LookPreference` record and the
/// device-local defaults every surface already reads (T-1307, and the work-hours window since
/// T-1347).
///
/// Two directions, and they are deliberately triggered by different things:
///
/// - **Adopt** runs whenever the record changes — a remote row arriving, or this device's own
///   write landing. It reads the record *down* into the mirrors. The record is the source of
///   truth, so this direction never asks whether the local value was "newer"; there is no such
///   thing across three devices without a clock nobody can trust.
/// - **Publish** runs on `UserDefaults.didChangeNotification`, which fires only because something
///   was actually written. It reads the mirrors *up* into the record.
///
/// The pair cannot loop. Adopt writes a mirror only when the value differs, so an adopt that
/// changes nothing posts no notification; a publish whose diff is empty returns `nil` from
/// `pendingWrite` and commits nothing. A real local edit runs publish once, which bumps the record,
/// which runs adopt once, which finds every mirror already correct and stops.
///
/// **And they are ordered: adopt first, publish never before it** (T-3040). `publish` is driven by
/// `UserDefaults.didChangeNotification`, which fires for *every* write in the process — dozens of
/// them during startup — and the host subscribes to it while its body is first evaluated, which is
/// before `onAppear` has run the launch's first adopt. A publish that reaches the record first sees
/// `records` as empty and **mints a row stamped `now`**, which `CadenceLookPreferenceStore.current`
/// then prefers over every row this device has not read yet. Nothing merges the loser back:
/// `LookPreference` is deliberately outside `DataIntegrityRepairService`'s dedupe set, which
/// *deletes* the rows it collapses and is the one thing this model's own "Duplicates" note forbids.
/// So the ordering is the guard, and `hasAdopted` below is the whole of it.
///
/// **No write site changed.** That is the point of the shape: the sort chips, the tint picker and
/// the palette picker keep writing the same local defaults they always wrote, `CadenceWidgets`
/// keeps reading the app-group key with no SwiftData anywhere near it, and the thirty-odd readers
/// keep reading. Threading a `@Query` and a failure banner through fourteen write sites would have
/// been a bigger change with more ways to be wrong.
@MainActor
@Observable
final class CadenceLookPreferenceSync {
    /// Why the last commit was refused, kept rather than shown.
    ///
    /// A refused commit here costs nothing the user can see: the mirror was written first, so this
    /// device already looks the way they asked, and only the trip to the other two is deferred to
    /// the next change or the next launch. Surfacing a banner for that would be telling someone
    /// about a failure with no action attached to it.
    private(set) var lastFailureNotice: String?

    /// `true` once this launch's first `adopt` has read the record set, whether or not it found a
    /// row in it. The gate `publish` gets to run behind (T-3040).
    ///
    /// **Launch-scoped rather than persisted, and set by the read rather than by the find.** Those
    /// are two separate judgements and both are load-bearing:
    ///
    /// - *Launch-scoped*, because the hazard is a launch-ordering one. `CadenceNoteTemplatePreferenceSync`
    ///   persists its equivalent flag because what it gates is a once-per-device migration; there is
    ///   no migration here, and a persisted flag would leave this gate permanently open from the
    ///   second launch onwards — which is exactly the launch where a startup write can still beat
    ///   the first adopt.
    /// - *Set by the read*, because "a record was found" is not available to a device whose account
    ///   has never had one. Gating on that would mean a first-ever user's device never mints the
    ///   shared row at all and nothing they set ever reached a second device — a worse bug than the
    ///   one this closes. `adopt` is called from `onAppear` and from every `onChange`, so the flag
    ///   says what it needs to say: this device has looked.
    ///
    /// **What this does not close, stated rather than implied.** A cold CloudKit import can still
    /// be in flight long after `onAppear`, and nothing in-process can tell "no row has downloaded
    /// yet" from "no row has ever existed" — `CadenceSyncActivityLog`'s events are launch-scoped
    /// and, per [[T-2010]], not provably delivered at all. A device that touches a setting during
    /// that window can still mint. The mitigation is the one already in
    /// `CadenceLookPreferenceStore.pendingWrite`: a minted row carries only the pairs this device
    /// actually set, `adopt` writes only the keys a record names, and neither accent nor tint can
    /// be minted empty over a value this device has not seen.
    @ObservationIgnored private(set) var hasAdopted = false

    private let defaults: UserDefaults
    private let accentDefaults: UserDefaults
    private let platform: CadenceLookPreferenceStore.Platform

    init(
        defaults: UserDefaults = CadenceDefaults.store,
        accentDefaults: UserDefaults = CadenceAccentPaletteStore.sharedDefaults(),
        platform: CadenceLookPreferenceStore.Platform = .current
    ) {
        self.defaults = defaults
        self.accentDefaults = accentDefaults
        self.platform = platform
    }

    // MARK: - Adopt

    /// Reads the record down into this device's mirrors. Returns the keys it actually changed, so
    /// a test can tell an adopt that did something from one that found everything already right.
    @discardableResult
    func adopt(records: [LookPreference], applyAccent: Bool = true) -> Set<String> {
        // Before the early return, not after it: the flag means "this device has read the record
        // set", and an empty set is a reading. See `hasAdopted`.
        hasAdopted = true
        guard let record = CadenceLookPreferenceStore.current(from: records) else { return [] }
        var changed: Set<String> = []

        for (key, value) in CadenceLookPreferenceStore.mirrorWrites(
            forTaskPresentation: record.taskPresentationRaw,
            on: platform
        ) {
            if write(value, forKey: key) { changed.insert(key) }
        }

        // T-1347 — the work-hours window, which is the same two keys on all three devices.
        for (key, value) in CadenceLookPreferenceStore.mirrorWrites(
            forCalendarPresentation: record.calendarPresentationRaw
        ) {
            if write(value, forKey: key) { changed.insert(key) }
        }

        // Only a record that actually names a tint set overwrites this device's. An empty string
        // is "never chosen", not "chosen to be empty" — the same reading `mirrorWrites` gives an
        // absent pair.
        if !record.sidebarTabColorsRaw.isEmpty,
           write(record.sidebarTabColorsRaw, forKey: CadencePreferenceKeys.sidebarTabColors) {
            changed.insert(CadencePreferenceKeys.sidebarTabColors)
        }

        if !record.accentPaletteID.isEmpty,
           record.accentPaletteID != accentDefaults.string(forKey: CadenceAccentPaletteStore.defaultsKey) {
            changed.insert(CadenceAccentPaletteStore.defaultsKey)
            guard applyAccent else { return changed }
            // Through the shared selection rather than the defaults key directly: `select` writes
            // the app-group mirror the widget reads, pushes a timeline reload, and repaints every
            // view that touched `Theme` in its body. Writing the key alone would sync the palette
            // and leave this device drawing the old one until relaunch.
            CadenceAccentPaletteSelection.shared.select(
                CadenceAccentPalette.palette(id: record.accentPaletteID),
                userDefaults: accentDefaults
            )
        }

        return changed
    }

    /// `true` when the default actually moved. An equal write is skipped so adopt cannot post a
    /// change notification that would send publish round again.
    private func write(_ value: String, forKey key: String) -> Bool {
        // Both tables, because a `.bool` or an `.int` written as a string reads back as unset and
        // the surface silently falls to its compiled-in default. Searching only the task mirrors is
        // how the work-hours window would have arrived as `"540"` and drawn nine o'clock.
        let mirror = (CadenceLookPreferenceStore.mirrors(on: platform)
            + CadenceLookPreferenceStore.calendarMirrors())
            .first { $0.defaultsKey == key }

        switch mirror?.kind {
        case .bool:
            let wanted = value == "true"
            guard defaults.object(forKey: key) == nil || defaults.bool(forKey: key) != wanted else { return false }
            defaults.set(wanted, forKey: key)
            return true
        case .int:
            // A record value that is not an integer is left alone rather than coerced to zero,
            // which would move the band to midnight on every device that read it.
            guard let wanted = Int(value) else { return false }
            guard defaults.object(forKey: key) == nil || defaults.integer(forKey: key) != wanted else { return false }
            defaults.set(wanted, forKey: key)
            return true
        case .string, .none:
            guard defaults.string(forKey: key) != value else { return false }
            defaults.set(value, forKey: key)
            return true
        }
    }

    // MARK: - Publish

    /// Reads this device's mirrors up into the record, committing only when something differs.
    ///
    /// **Refused before this launch's first adopt** (T-3040). `UserDefaults.didChangeNotification`
    /// fires for every write in the process and the host is subscribed to it before `onAppear`
    /// runs, so without this the first startup write that touches any default at all would reach
    /// the record ahead of the only direction that reads it — and, finding nothing there, mint a
    /// row stamped `now` that outranks whatever this device has not read yet. The mirror is written
    /// first either way, so nothing the user can see is deferred by the refusal: `onAppear`'s adopt
    /// opens the gate a frame later and the next change publishes normally. `hasAdopted` carries
    /// the rest of the argument, including what it does *not* close.
    ///
    /// Not `try?`: this inserts on the first write, and a swallowed insert is a pending change for
    /// the next unrelated `save()` to take. The failure is kept in `lastFailureNotice` and the next
    /// local change tries again.
    func publish(records: [LookPreference], in modelContext: ModelContext, now: Date = Date()) {
        guard hasAdopted else { return }
        let record = CadenceLookPreferenceStore.current(from: records)
        guard let pending = CadenceLookPreferenceStore.pendingWrite(
            accentPaletteID: accentDefaults.string(forKey: CadenceAccentPaletteStore.defaultsKey) ?? "",
            sidebarTabColorsRaw: defaults.string(forKey: CadencePreferenceKeys.sidebarTabColors) ?? "",
            currentMirrors: CadenceLookPreferenceStore.currentMirrors(in: defaults, on: platform),
            currentCalendarMirrors: CadenceLookPreferenceStore.currentCalendarMirrors(in: defaults),
            record: record,
            on: platform
        ) else { return }

        do {
            try CadenceLookPreferenceStore.write(
                accentPaletteID: pending.accentPaletteID,
                sidebarTabColorsRaw: pending.sidebarTabColorsRaw,
                taskPresentationRaw: pending.taskPresentationRaw,
                calendarPresentationRaw: pending.calendarPresentationRaw,
                records: records,
                in: modelContext,
                now: now
            )
            lastFailureNotice = nil
        } catch {
            lastFailureNotice = CadencePendingChangePersistence.editFailureNotice
        }
    }
}

// MARK: - The host

/// The invisible view both roots attach, and the only place `CadenceLookPreferenceSync` is driven.
///
/// A `@Query` rather than a fetch, so a row arriving from another device re-runs `adopt` without
/// anything having to poll. It draws nothing: the settings it carries are drawn by the surfaces
/// that already read the local defaults.
struct CadenceLookPreferenceSyncHost: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var lookPreferences: [LookPreference]
    @State private var sync = CadenceLookPreferenceSync()

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear { sync.adopt(records: lookPreferences) }
            .onChange(of: lookPreferences.map(\.updatedAt)) { _, _ in
                sync.adopt(records: lookPreferences)
            }
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                sync.publish(records: lookPreferences, in: modelContext)
            }
    }
}

extension View {
    /// Attaches the synced look to a root view. Idempotent and cheap: one hidden overlay holding
    /// one `@Query`.
    func cadenceSyncedLook() -> some View {
        overlay(alignment: .topLeading) { CadenceLookPreferenceSyncHost() }
    }
}
