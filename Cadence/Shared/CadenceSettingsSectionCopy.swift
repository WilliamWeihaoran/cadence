import Foundation

/// Settings copy that the Mac pane and the phone section both show.
///
/// **T-524.** Settings is the one screen the app draws twice from scratch: `Cadence/macOS/Views/`
/// holds one pane per category and `Cadence/iOS/` holds a section per category, and the two were
/// written from the same words rather than from the same string. That is the shape
/// `CadenceEmptyStateCopy` was created for one screen over, and the same drift followed it here —
/// the calendar access card already differs by a whole sentence between the two surfaces, which is
/// recorded on `calendarAccess…Title` below rather than papered over.
///
/// Only wording **both** surfaces show is here. Copy that is true on one platform and false on the
/// other — "Allow Cadence from the iOS Settings app…" against "…from System Settings, Privacy &
/// Security, Calendars." — stays at its own call site, because a constant would invite exactly the
/// substitution that makes it wrong.
///
/// `nonisolated` for the reason `CadenceEmptyStateCopy` carries the same keyword: the project sets
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so a bare enum here is main-actor isolated and
/// reading it from a `nonisolated` context warns today and is an error under Swift 6. Constants
/// have no state to protect.
nonisolated enum CadenceCalendarSettingsCopy {

    /// Settings → Calendar, with EventKit access refused. The **title** is one string across both
    /// surfaces; the sentence under it deliberately is not, because it names where the reader has
    /// to go and that is a different place on each platform.
    static let accessDeniedTitle = "Calendar access denied"

    /// Settings → Calendar, before anyone has been asked.
    ///
    /// **The two surfaces disagree under this title and the disagreement is not resolved here**
    /// (see T-543): macOS says "Allow Cadence to create and sync calendar events." while iOS says
    /// "Allow Cadence to show events and connect Apple calendars to areas or projects." Both are
    /// true of both platforms, so one of them is the right sentence for both — but picking it is a
    /// copy decision, not a de-duplication, and converging the two subtitles by fiat would hide the
    /// choice inside a refactor.
    static let accessRequiredTitle = "Calendar access required"

    /// The connect menu on a calendar row with no active area or project to offer.
    static let noConnectableListsLabel = "No active areas or projects"

    /// A calendar row that no list mirrors. The row prints the connected list names when there are
    /// any, so this is the whole line rather than a prefix.
    static let unconnectedSummary = "Not connected to any area or project"

    /// The work-hours row's title, on Settings > Calendar at both widths.
    ///
    /// **Only the title is shared.** The sentence under it differs on purpose-or-by-accident and
    /// this refactor does not decide which (T-544): macOS says "Weekly calendar views gently
    /// highlight …" and iOS says "Calendar day columns gently highlight …". Both surfaces read the
    /// same `CalendarWorkHoursPreferences.highlightFrame`, so at most one of those sentences
    /// describes where the band is actually drawn — that is a copy decision with a behavioural
    /// question under it, not a de-duplication, and converging it here would bury the choice.
    static let workdayBoundaryTitle = "Workday boundary"

    /// The accessible name of the calendar row's link menu — an icon-only control on both
    /// surfaces, so nothing else on the row says what it does.
    ///
    /// macOS reaches it through `cadenceControlLabel(_:)`, which sets the name *and* the tooltip;
    /// it used to set `.help` alone, which is the T-472 defect (a pointer gets a sentence and
    /// assistive technology gets the SF Symbol name) two screens away from where T-472 fixed it.
    static let connectMenuLabel = "Connect to areas and projects"
}

/// Settings → Notifications, which is one row in two states on both surfaces.
///
/// Every string here was spelled twice — the Mac's `SettingsNotificationsSection` and the phone's
/// `iOSNotificationsSettingsSection` are the same four sentences in two card vocabularies. Nothing
/// about the *words* differs by platform: both surfaces schedule the same local notifications
/// through the same `NotificationManager`, and only the route into system settings differs, which
/// is code rather than copy.
nonisolated enum CadenceNotificationSettingsCopy {

    /// The row title **and** the switch's accessible name, which is why it is one constant rather
    /// than two: T-484 named the toggle after its own row precisely so the two could not drift, and
    /// spelling them separately is how that drift starts. Pinned by
    /// `ControlAccessibilityLabelTests.theFiveNamedTogglesTakeTheirNameFromTheirOwnRow`.
    static let remindersToggleTitle = "Enable reminders"

    /// Says what is scheduled and that it stays on the device. "Locally" is load-bearing: nothing
    /// here goes through a push server, and the reader has just been asked for a system permission.
    static let remindersToggleDetail = "A task's scheduled start and due date, and a habit's reminder time, notify you locally."

    static let accessRequiredTitle = "Notification access required"
    static let accessRequiredDetail = "Allow Cadence to notify you about scheduled tasks, due dates, and habit reminders."

    /// The button under `accessRequiredDetail`. Names the thing it turns on rather than the
    /// permission dialog it opens, so it still reads correctly on the second press, when the
    /// system will not prompt again and both surfaces fall through to system settings.
    static let enableNotificationsAction = "Enable Notifications"
}
