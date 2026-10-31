import Foundation

/// What the Calendar page says when it cannot read Apple Calendar ([[T-5954]]).
///
/// Every event read on the page — macOS's board, month and timeline, iOS's
/// `refreshVisibleEvents` — returns empty behind an authorization guard, and until this type the
/// page drew that emptiness as if it were the answer: no notice, and on the iPhone month agenda a
/// "Nothing this month" that stated the opposite of the truth. On macOS the only way to grant
/// access was Settings, which nothing on the page mentioned.
///
/// This is the whole decision, kept pure so it is testable without EventKit: the two managers'
/// `isAuthorized` / `isDenied` arrive as plain inputs, and no test here asks TCC anything.
///
/// **Placement is reversible and was chosen without the owner** (the ticket's one open choice):
/// one slim notice under the Calendar toolbar on both platforms, shaped like the Inbox's Reminders
/// strip on macOS and iOS Search's calendar-access card on iOS. Tasks still draw beneath it, so
/// the page stays usable. Moving it is a view change only; the gate below does not move with it.
nonisolated enum CadenceCalendarAccessNotice: Equatable {
    /// Nobody has been asked yet. An offer, not a fault — the neutral glyph, as Settings draws it.
    case connectOffer
    /// Refused (or restricted, which both managers' `isDenied` already fold in). Neither platform
    /// re-prompts, so the only action is the system Settings app.
    case denied

    enum Action: Equatable {
        case requestAccess
        case openSystemSettings
    }

    enum Platform: Equatable {
        case mac
        case mobile
    }

    /// `nil` means the page can read events (or is showing fixture events, which stand in for
    /// them) and draws no notice. Authorization is read first: the notice is about the events
    /// that are missing, so a page that has them says nothing.
    static func resolve(
        isAuthorized: Bool,
        isDenied: Bool,
        showsFixtureEvents: Bool = false
    ) -> CadenceCalendarAccessNotice? {
        if isAuthorized || showsFixtureEvents { return nil }
        return isDenied ? .denied : .connectOffer
    }

    /// The Settings card's titles, verbatim — one string per state on both platforms.
    var title: String {
        switch self {
        case .connectOffer: return CadenceCalendarSettingsCopy.connectOfferTitle
        case .denied: return CadenceCalendarSettingsCopy.accessDeniedTitle
        }
    }

    /// The denied sentence names where the reader has to go, which differs per platform — the
    /// same split each Settings card makes, in the same words.
    func detail(on platform: Platform) -> String {
        switch (self, platform) {
        case (.connectOffer, _):
            return CadenceCalendarSettingsCopy.accessRequiredDetail
        case (.denied, .mac):
            return "Allow Cadence from System Settings, Privacy & Security, Calendars."
        case (.denied, .mobile):
            return "Allow Cadence from the iOS Settings app to show Apple Calendar events."
        }
    }

    var action: Action {
        switch self {
        case .connectOffer: return .requestAccess
        case .denied: return .openSystemSettings
        }
    }

    /// The Settings cards' button titles on each platform.
    func actionTitle(on platform: Platform) -> String {
        switch (action, platform) {
        case (.requestAccess, _): return "Allow Access"
        case (.openSystemSettings, .mac): return "Open Calendar Settings"
        case (.openSystemSettings, .mobile): return "Open Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .connectOffer: return "calendar.badge.plus"
        case .denied: return "exclamationmark.triangle.fill"
        }
    }

    /// The month agenda's empty state. With a notice up, an empty month is only empty of what
    /// Cadence holds, so it may not say "Nothing this month".
    ///
    /// The subtitle names only what a month agenda can hold (T-9203). It said "events, blocks or
    /// tasks", the last owner-visible mention of a Block after [[T-3170]] removed every Block
    /// surface, promising a third kind of row that nothing draws any more.
    static func monthAgendaEmptyCopy(
        notice: CadenceCalendarAccessNotice?
    ) -> (message: String, subtitle: String) {
        guard notice != nil else {
            return ("Nothing this month", "Days with events or tasks show up here.")
        }
        return ("No tasks this month", notConnectedSentence)
    }

    /// A day's one-line empty state on the board column and the day inspector.
    static func dayEmptyText(notice: CadenceCalendarAccessNotice?) -> String {
        notice == nil ? CadenceEmptyStateCopy.nothingScheduledTitle : "No tasks scheduled"
    }

    static let notConnectedSentence = "Apple Calendar is not connected, so its events are not shown."
}
