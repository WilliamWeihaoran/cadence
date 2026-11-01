import Foundation

/// **One stored Sort / Order / Group preference per surface, read by both platforms** ([[T-8731]],
/// owner decision 2026-10-31 under [[T-8201]]).
///
/// The Inbox and All Tasks used to keep two sets of preferences: macOS wrote `inboxSortField` /
/// `inboxSortDirection` / `inboxGroupingMode` (and the All Tasks trio), and iOS wrote one
/// `ios.inbox.sortMode` / `ios.allTasks.sortMode` holding a `CadenceTaskSortMode`. That is the
/// ticket's last visible consequence — "the two platforms keep separate preference keys, so the
/// choice cannot follow the owner between devices". Both platforms read the macOS trio now, and
/// this type is the one-way door the old iOS value walks through.
///
/// **Read-time, idempotent, and non-destructive.** The legacy key is read and never cleared, the
/// same policy `TasksPanel.legacySortFieldDefaultsKey` states for macOS Today's retired chips:
/// nothing is gained by destroying the only record of what the user chose, and a build rolled back
/// to the one-chip bar still finds its preference intact. The migration writes only when the new
/// key is **absent**, so a later choice on the new control is never overwritten by a stale legacy
/// value, and running it twice changes nothing.
enum CadenceTaskPresentationPreferences {

    /// One surface's three keys plus the legacy iOS key that seeds them.
    struct SurfaceKeys: Sendable {
        let sortField: String
        let sortDirection: String
        let legacyIOSSortMode: String
    }

    static let inbox = SurfaceKeys(
        sortField: CadencePreferenceKeys.inboxSortField,
        sortDirection: CadencePreferenceKeys.inboxSortDirection,
        legacyIOSSortMode: CadencePreferenceKeys.iosInboxSortMode
    )

    static let allTasks = SurfaceKeys(
        sortField: CadencePreferenceKeys.allTasksSortField,
        sortDirection: CadencePreferenceKeys.allTasksSortDirection,
        legacyIOSSortMode: CadencePreferenceKeys.iosAllTasksSortMode
    )

    static let surfaces: [SurfaceKeys] = [inbox, allTasks]

    /// Seeds the shared Sort and Order keys from a legacy iOS sort mode, for every surface that
    /// has one and has not been given a shared value yet. Returns the keys it wrote, so a test can
    /// assert the second run writes nothing.
    ///
    /// Grouping has no legacy iOS value to migrate — iOS has never had a grouping control — so a
    /// phone that has never been grouped simply takes each page's shipped default, which is the
    /// one the Mac has always had.
    @discardableResult
    static func migrateLegacyIOSSortModes(in defaults: UserDefaults = CadenceDefaults.store) -> [String] {
        var written: [String] = []
        for surface in surfaces {
            guard defaults.string(forKey: surface.sortField) == nil else { continue }
            guard let legacy = defaults.string(forKey: surface.legacyIOSSortMode),
                  let mode = CadenceTaskSortMode(rawValue: legacy) else { continue }
            let pair = mode.macOSSortPair
            defaults.set(pair.field.rawValue, forKey: surface.sortField)
            written.append(surface.sortField)
            // Only when the direction is also unset: a Mac that has already stored one owns it,
            // and `.custom` ignores direction entirely (`TaskSortField.honorsDirection`).
            if defaults.string(forKey: surface.sortDirection) == nil {
                defaults.set(pair.direction.rawValue, forKey: surface.sortDirection)
                written.append(surface.sortDirection)
            }
        }
        return written
    }
}
