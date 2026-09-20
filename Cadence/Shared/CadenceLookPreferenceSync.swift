import Combine
import Foundation
import SwiftData
import SwiftUI

/// The one thing that carries values between the synced `LookPreference` record and the
/// device-local defaults every surface already reads (T-1307).
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
        guard let record = CadenceLookPreferenceStore.current(from: records) else { return [] }
        var changed: Set<String> = []

        for (key, value) in CadenceLookPreferenceStore.mirrorWrites(
            forTaskPresentation: record.taskPresentationRaw,
            on: platform
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
        if let mirror = CadenceLookPreferenceStore.mirrors(on: platform).first(where: { $0.defaultsKey == key }),
           mirror.kind == .bool {
            let wanted = value == "true"
            guard defaults.object(forKey: key) == nil || defaults.bool(forKey: key) != wanted else { return false }
            defaults.set(wanted, forKey: key)
            return true
        }
        guard defaults.string(forKey: key) != value else { return false }
        defaults.set(value, forKey: key)
        return true
    }

    // MARK: - Publish

    /// Reads this device's mirrors up into the record, committing only when something differs.
    ///
    /// Not `try?`: this inserts on the first write, and a swallowed insert is a pending change for
    /// the next unrelated `save()` to take. The failure is kept in `lastFailureNotice` and the next
    /// local change tries again.
    func publish(records: [LookPreference], in modelContext: ModelContext, now: Date = Date()) {
        let record = CadenceLookPreferenceStore.current(from: records)
        guard let pending = CadenceLookPreferenceStore.pendingWrite(
            accentPaletteID: accentDefaults.string(forKey: CadenceAccentPaletteStore.defaultsKey) ?? "",
            sidebarTabColorsRaw: defaults.string(forKey: CadencePreferenceKeys.sidebarTabColors) ?? "",
            currentMirrors: CadenceLookPreferenceStore.currentMirrors(in: defaults, on: platform),
            record: record,
            on: platform
        ) else { return }

        do {
            try CadenceLookPreferenceStore.write(
                accentPaletteID: pending.accentPaletteID,
                sidebarTabColorsRaw: pending.sidebarTabColorsRaw,
                taskPresentationRaw: pending.taskPresentationRaw,
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
