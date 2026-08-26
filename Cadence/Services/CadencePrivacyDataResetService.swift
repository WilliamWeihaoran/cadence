import Foundation
import SwiftData

/// What a completed reset removed, and the one sentence both platforms show afterwards.
///
/// A value type rather than a formatted string handed back from the view, because
/// `Cadence/iOS/` is inside `#if os(iOS)` and invisible to the macOS-built test target: the
/// wording is the part worth pinning, and this is where a test can reach it.
struct PrivacyDataResetOutcome: Equatable, Sendable {
    /// Local Cadence store backups deleted along with the store's contents.
    let removedBackupCount: Int

    var statusMessage: String {
        removedBackupCount == 0
            ? "Cadence account and data were deleted."
            : "Cadence account, data, and \(removedBackupCount) backup\(removedBackupCount == 1 ? "" : "s") were deleted."
    }
}

/// The typed phrase that arms the destructive button.
///
/// macOS gates the reset behind a window-modal `confirmationDialog`: the destructive control is
/// never on the settings pane, and reaching it costs a deliberate click on an alert that
/// enumerates everything about to be lost. The mobile translation of that dialog is a bottom
/// action sheet — one thumb-reachable tap — so iOS spends the seriousness somewhere a phone can
/// actually carry it: the destructive control lives in a modal sheet, and stays disabled until
/// this phrase has been typed. Same bar, different mechanism.
///
/// Deliberately outside any platform guard so the rule is testable; `authorizes(_:)` is the only
/// thing that decides, and no view may re-spell it.
enum PrivacyDataResetConfirmation {
    /// Shown to the user verbatim, so it has to read as something you would only type on purpose.
    static let requiredPhrase = "DELETE"

    /// Trimmed and case-insensitive: a phone keyboard's autocapitalisation is not a security
    /// boundary, and someone who typed `delete` into a field labelled with `DELETE` meant it.
    /// Whitespace alone never authorizes — an empty field must not read as a match.
    static func authorizes(_ typed: String) -> Bool {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.compare(requiredPhrase, options: .caseInsensitive) == .orderedSame
    }
}

/// Wipes every Cadence-created model, plus the local artifacts that outlive the store.
///
/// **This file has no `#if os(macOS)` and does not live under `macOS/Services/`.** It sat there
/// behind that guard while importing only Foundation and SwiftData and containing zero AppKit
/// references — the same shape `RemindersManager` had, and the same consequence: the shipped
/// privacy policy promised in-app deletion that iOS had no route to. The guard was an accident of
/// where the file was written. A 2-line tombstone under the old *unprefixed* name records the
/// move; the prefix on this file is what keeps the two from colliding on `.stringsdata`.
enum PrivacyDataResetService {
    @MainActor
    static func deleteCadenceData(
        in modelContext: ModelContext,
        canceller: CadenceNotificationCanceller? = nil
    ) async throws {
        try deleteAll(HabitCompletion.self, in: modelContext)
        try deleteAll(GoalListLink.self, in: modelContext)
        try deleteAll(Subtask.self, in: modelContext)
        try deleteAll(TaskBundle.self, in: modelContext)
        try deleteAll(AppTask.self, in: modelContext)
        try deleteAll(EventNote.self, in: modelContext)
        try deleteAll(DailyNote.self, in: modelContext)
        try deleteAll(WeeklyNote.self, in: modelContext)
        try deleteAll(PermNote.self, in: modelContext)
        try deleteAll(Note.self, in: modelContext)
        try deleteAll(Document.self, in: modelContext)
        try deleteAll(MarkdownImageAsset.self, in: modelContext)
        try deleteAll(SavedLink.self, in: modelContext)
        try deleteAll(Habit.self, in: modelContext)
        try deleteAll(Goal.self, in: modelContext)
        try deleteAll(Pursuit.self, in: modelContext)
        try deleteAll(Project.self, in: modelContext)
        try deleteAll(Area.self, in: modelContext)
        try deleteAll(Context.self, in: modelContext)
        try deleteAll(Tag.self, in: modelContext)
        try modelContext.save()

        // Pending OS notifications are not in the store, so wiping the store does not touch them.
        // That was nearly harmless while every reminder was a one-shot that fired once and
        // expired; now that habit reminders repeat on time-of-day, a reset would leave a banner
        // carrying a deleted habit's **title** firing every day until the next reconcile — and
        // reconcile only runs when the scene leaves `.active`. "Delete my data" has to mean the
        // notifications too.
        //
        // **Awaited, not spawned.** This was `Task { await … }` and a bare `return`, so the reset
        // reported success with the cancellation still in flight: quit promptly after confirming
        // and a deleted habit's daily reminder outlives the data it describes, surfacing later
        // from an app the user believes they emptied. `docs/privacy.html` and the App Review
        // notes both describe this reset, which is what makes the difference between "done" and
        // "started" a promise rather than a nicety. `docs/TODO.md` T-297.
        await (canceller ?? .default).run()
    }

    /// The widget half of the reset, as its own function so a test can drive it without the parts
    /// that touch the real keychain and the real backups directory.
    ///
    /// **Clearing the stored state is not a reload.** `clearStoredState` drops the optimistic
    /// completion overrides and the reload throttle out of the app group; it does not ask WidgetKit
    /// for anything, so the last rendered timeline entry — deleted task and habit titles included —
    /// stays on the home screen until the system next decides to refresh, which can be a long time.
    /// `force` because the reset must not be swallowed by the reload throttle it just cleared the
    /// other side of. `docs/TODO.md` T-310.
    @MainActor
    static func clearWidgetState(userDefaults: UserDefaults? = nil) {
        CadenceWidgetRefreshCenter.clearStoredState(userDefaults: userDefaults)
        CadenceWidgetRefreshCenter.reloadAllWidgets(force: true, userDefaults: userDefaults)
    }

    /// The whole reset both platforms perform, minus the one piece that is genuinely macOS-only.
    ///
    /// macOS's Data Safety pane assembled this inline; iOS needed the same sequence, and a second
    /// hand-written copy of it is exactly how "delete my data" ends up meaning two different
    /// things on two platforms. Sign in with Apple is entitlement-gated and macOS-only
    /// (`AppleAccountManager` is inside `#if os(macOS)`), so signing that profile out stays at the
    /// macOS call site rather than becoming an optional parameter nobody on iOS can pass.
    @MainActor
    static func deleteCadenceDataAndLocalArtifacts(
        in modelContext: ModelContext,
        aiSettingsManager: AISettingsManager
    ) async throws -> PrivacyDataResetOutcome {
        try await deleteCadenceData(in: modelContext)
        try? aiSettingsManager.removeAPIKey()
        clearWidgetState()
        StoreBackupManager.clearPendingRestore()
        StoreBackupManager.clearFailedRestore()
        let removedBackupCount = try StoreBackupManager.deleteAllBackups()
        return PrivacyDataResetOutcome(removedBackupCount: removedBackupCount)
    }

    private static func deleteAll<T: PersistentModel>(_ type: T.Type, in modelContext: ModelContext) throws {
        let models = try modelContext.fetch(FetchDescriptor<T>())
        for model in models {
            modelContext.delete(model)
        }
    }
}

/// The pending-notification cancellation the reset performs, as an injectable value.
///
/// It has to be injectable to be *provable*. `NotificationManager.cancelAll()` early-returns
/// inside a test host, so from the outside a spawned-and-forgotten `Task` and an awaited call
/// look identical — which is exactly how T-297 survived: the call was there, and the promise it
/// was supposed to keep was not. A test hands in a canceller that suspends and records, and then
/// the difference between "the reset waited" and "the reset started something" is a value.
///
/// Same shape and same reasons as `CadenceWindDownReconciler`: `default` is inert inside a test
/// host, so the eighteen suites that drive the reset over an in-memory store do not reach
/// `UNUserNotificationCenter`.
@MainActor
struct CadenceNotificationCanceller {
    /// `false` for a canceller that deliberately does nothing. Exposed so `default` can be pinned.
    let isLive: Bool

    private let body: () async -> Void

    init(isLive: Bool = true, _ body: @escaping () async -> Void) {
        self.isLive = isLive
        self.body = body
    }

    func run() async {
        await body()
    }

    static let live = Self { await NotificationManager.shared.cancelAll() }

    static let inert = Self(isLive: false) {}

    static var `default`: Self {
        NotificationManager.isTestEnvironment ? .inert : .live
    }
}
