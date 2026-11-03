import Foundation

/// **The Calendar page's view, style and timeline density: one stored preference each, read by
/// both platforms** ([[T-8737]], owner decision 2026-10-31).
///
/// The phone remembered all three under `ios.calendar.viewMode`, `ios.calendar.presentation` and
/// `ios.calendar.zoomLevel` (a `Double` multiplier), and Settings → Navigation → Defaults set
/// them. The Mac held its view and style in `@State`, so its Calendar opened on Week / Timeline at
/// every launch, and kept its zoom under `calendarZoomLevel` as an `Int` 1…3. The owner's call is
/// that these are app-wide defaults, so both platforms now read the three keys below and both
/// Settings panes write them.
///
/// **One key is not one value across devices.** A Mac and an iPhone keep their own defaults
/// domains; what one spelling buys is that the two surfaces cannot drift onto different keys and
/// types again (the same argument `CadencePreferenceKeys.searchIncludesCompletedTasks` makes).
///
/// **Read-time, idempotent and non-destructive**, the policy `CadenceTaskPresentationPreferences`
/// set for [[T-8731]]: a legacy value seeds a shared key only while that key is **absent**, so a
/// choice made on the new key is never overwritten and a second run writes nothing; and the legacy
/// value is left on disk, so a build rolled back to the old keys still finds the user's choice.
enum CadenceCalendarPreferences {
    /// A `CadenceCalendarViewMode` raw value.
    static let viewModeKey = "calendarViewMode"
    /// A `CadenceCalendarPresentation` raw value.
    static let presentationKey = "calendarPresentation"
    /// The zoom key is `CadenceCalendarZoom.storageKey`, declared beside the zoom it holds.
    static var zoomKey: String { CadenceCalendarZoom.storageKey }

    /// The retired iOS keys. Read here and nowhere else.
    static let legacyIOSViewModeKey = "ios.calendar.viewMode"
    static let legacyIOSPresentationKey = "ios.calendar.presentation"

    /// The zoom's two legacy sources, in the order they are tried. Both are legal multipliers of
    /// the shared `Double`: iOS's already was one, and the Mac's `Int` 1/2/3 is the same Compact /
    /// Comfort / Spacious ordering (`CadenceCalendarZoom.timelineLevel(for:)`). Only one of them
    /// exists on any real device; the order matters only to a domain holding both, where the
    /// continuous value is the more precise record of the choice. Neither is cleared.
    static let legacyZoomKeys = [
        CadenceCalendarZoom.legacyIOSStorageKey,
        CadenceCalendarZoom.legacyMacStorageKey
    ]

    /// Seeds each shared key that is still absent from its legacy source. Returns the keys it
    /// wrote, so a test can assert that a second run writes nothing.
    ///
    /// A legacy value that does not parse — an unknown raw string, a non-number, a non-finite
    /// number — seeds nothing, so the page falls back to its shipped default exactly as it would
    /// have read that garbage before. The zoom is copied as stored, not clamped: every reader
    /// clamps (`CadenceCalendarZoom.clamp`), and copying is what "never drop a stored value" means.
    @discardableResult
    static func migrateLegacyKeys(in defaults: UserDefaults = CadenceDefaults.store) -> [String] {
        var written: [String] = []

        if defaults.object(forKey: viewModeKey) == nil,
           let legacy = defaults.string(forKey: legacyIOSViewModeKey),
           CadenceCalendarViewMode(rawValue: legacy) != nil {
            defaults.set(legacy, forKey: viewModeKey)
            written.append(viewModeKey)
        }

        if defaults.object(forKey: presentationKey) == nil,
           let legacy = defaults.string(forKey: legacyIOSPresentationKey),
           CadenceCalendarPresentation(rawValue: legacy) != nil {
            defaults.set(legacy, forKey: presentationKey)
            written.append(presentationKey)
        }

        if defaults.object(forKey: zoomKey) == nil {
            for key in legacyZoomKeys {
                guard let number = defaults.object(forKey: key) as? NSNumber else { continue }
                let zoom = number.doubleValue
                guard zoom.isFinite else { continue }
                defaults.set(zoom, forKey: zoomKey)
                written.append(zoomKey)
                break
            }
        }

        return written
    }
}
