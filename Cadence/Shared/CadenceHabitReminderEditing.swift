import Foundation

/// What a habit editor opens with, given whatever `Habit.reminderMinuteOfDay` happens to hold.
///
/// **T-410.** The model stores this as a bare `Int?` and validates nothing — it says so in its own
/// doc — so each editor had to decide for itself what an out-of-range value looks like, and the
/// two decided differently. macOS handed it to `Calendar.date(bySettingHour:minute:second:of:)`,
/// which returns `nil` for hour 24, and its `?? Date()` fallback rendered the reminder as **the
/// current time**. iOS handed the same value to `TimeFormatters.timeString(from:)`, which reduces
/// it modulo a day, so 1440 read as **12 AM**. Neither was wrong about data nobody had checked;
/// both invented a time, and a picker opened on an invented time saves it straight back as if the
/// user had chosen it.
///
/// The agreed answer is that an editor never names a time it cannot justify: a stored minute
/// outside `HabitNotificationPlanner.reminderMinuteRange` opens **unset**, exactly as `nil` does,
/// and the user's next save clears it. That range is read rather than respelled — T-363 made it
/// the app's only check on this field, and a second copy of `0...1439` is how the two editors
/// diverged in the first place.
///
/// `nonisolated` for the reason `NonisolatedValueTypeTests` records: under
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` a bare value type is main-actor isolated, and this
/// is read from a `View.init`, which is not.
nonisolated enum CadenceHabitReminderEditing {
    /// Where both editors' pickers start when there is no reminder to load: 9:00 AM.
    static let defaultMinuteOfDay = 9 * 60

    /// Whether the toggle is on, and the minute the picker should show.
    ///
    /// The two are returned together because they are one decision. Reading `!= nil` for the
    /// toggle and `?? default` for the minute — which is what both editors did — lets them
    /// disagree: the toggle says "there is a reminder" while the picker shows a fabricated time.
    static func editorState(for storedMinuteOfDay: Int?) -> (isOn: Bool, minuteOfDay: Int) {
        guard let stored = storedMinuteOfDay,
              HabitNotificationPlanner.reminderMinuteRange.contains(stored)
        else { return (false, defaultMinuteOfDay) }
        return (true, stored)
    }

    /// A minute a picker can render, for the surfaces that hold one as a plain `Int`.
    ///
    /// `editorState(for:)` already keeps the desktop sheet's binding in range, so this is the
    /// second line of defence rather than the first — but it is the line that matters, because
    /// the thing it replaces was a `?? Date()` that turned any unrenderable minute into now.
    static func editorMinuteOfDay(_ minuteOfDay: Int) -> Int {
        HabitNotificationPlanner.reminderMinuteRange.contains(minuteOfDay) ? minuteOfDay : defaultMinuteOfDay
    }
}
