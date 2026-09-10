import Foundation
import SwiftData

/// What a completed reset removed, and the sentence each platform shows afterwards.
///
/// A value type rather than a formatted string handed back from the view, because
/// `Cadence/iOS/` is inside `#if os(iOS)` and invisible to the macOS-built test target: the
/// wording is the part worth pinning, and this is where a test can reach it.
///
/// **Two sentences, one deletion (T-474).** There was one `statusMessage` and it said "Cadence
/// account and data were deleted." on both platforms. Sign in with Apple is macOS-only, so on
/// iPhone and iPad there is no account profile to clear — the iOS screen says so in its own
/// header text and its own button, and then printed a success notice claiming otherwise.
/// `docs/app-review-notes.md` already draws the line the UI was crossing.
///
/// The split is **presentational only**: `deleteCadenceDataAndLocalArtifacts` is still one
/// sequence called from both panes, which is what keeps "delete my data" from coming to mean two
/// different things. What differs is the sentence, and it differs because the platforms differ.
struct PrivacyDataResetOutcome: Equatable, Sendable {
    /// Local Cadence store backups deleted along with the store's contents.
    let removedBackupCount: Int

    /// Why the saved OpenAI key is **still in the Keychain**, or `nil` when it is not (T-1101).
    ///
    /// The store deletion has already committed by the time the credential is reached, so a
    /// refused key deletion cannot fail the whole reset — but it must not be *silent* either.
    /// This was `try? aiSettingsManager.removeAPIKey()`: `KeychainCredentialStore.deleteSecret`
    /// throws on any `OSStatus` other than success or not-found, `removeAPIKey` clears
    /// `hasAPIKey` only after that call returns, and the reset then handed back an outcome whose
    /// sentence said the data was deleted. `docs/privacy.html` and the Data Safety pane both
    /// promise the saved key is removed, so the one thing the sentence may not do is claim it.
    let retainedAPIKeyReason: String?

    init(removedBackupCount: Int, retainedAPIKeyReason: String? = nil) {
        self.removedBackupCount = removedBackupCount
        self.retainedAPIKeyReason = retainedAPIKeyReason
    }

    /// macOS, where the reset also clears the local Sign in with Apple profile.
    var accountAndDataStatusMessage: String {
        let deleted = removedBackupCount == 0
            ? "Cadence account and data were deleted."
            : "Cadence account, data, and \(backupPhrase) were deleted."
        return appendingRetainedKeySentence(to: deleted)
    }

    /// iOS and iPadOS, where there is no account profile to clear.
    ///
    /// It must not contain the word "account" in any casing — that is the whole ticket, and it is
    /// asserted rather than left to review.
    var dataOnlyStatusMessage: String {
        let deleted = removedBackupCount == 0
            ? "Cadence data was deleted."
            : "Cadence data and \(backupPhrase) were deleted."
        return appendingRetainedKeySentence(to: deleted)
    }

    private var backupPhrase: String {
        "\(removedBackupCount) backup\(removedBackupCount == 1 ? "" : "s")"
    }

    /// Named on the same line both platforms already draw, and phrased as what is still true
    /// rather than as an apology: the key is *there*, and the control that removes it is named so
    /// the user can finish the deletion they asked for.
    ///
    /// An error whose description is empty still retained the key, so the sentence is written from
    /// the *presence* of a reason rather than from its text: a blank one falls back to naming the
    /// Keychain, and never to the wording that says the key is gone.
    private func appendingRetainedKeySentence(to deleted: String) -> String {
        guard let retainedAPIKeyReason else { return deleted }

        let trimmed = retainedAPIKeyReason
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let cause = trimmed.isEmpty ? "the Keychain refused the deletion" : trimmed

        return deleted
            + " The saved OpenAI key was not removed and is still in the Keychain (\(cause))."
            + " Delete it in Settings → AI."
    }
}

/// The typed phrase that arms the destructive button, on every platform.
///
/// **One gate, because one of them was weaker than the other in the wrong direction (T-575).**
/// This used to describe a deliberate split: macOS behind a window-modal `confirmationDialog`,
/// iOS behind a sheet with this phrase typed into it, "same bar, different mechanism". It was not
/// the same bar. The Mac's dialog put a live **Delete Account & Data** button one click from the
/// settings pane, and the Mac's reset is the *larger* one — Sign in with Apple is macOS-only, so
/// only there is there an account profile to sign out as well. The less guarded path deleted more.
///
/// Both surfaces now present a modal that enumerates what is about to be lost and keeps its
/// destructive control disabled until `authorizes(_:)` says otherwise:
/// `SettingsDataResetConfirmationSheet` and `iOSDataResetConfirmationSheet`.
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
    /// - Parameters:
    ///   - markDeleted: Marks every Cadence-created row deleted, committing nothing. A parameter
    ///     because the failure this function is *about* is a fetch that throws part-way through
    ///     the sweep, and an in-memory container cannot be made to refuse one. `@MainActor`
    ///     because the default argument is what calls the sweep, and a default argument is not
    ///     inside this function's isolation the way the `building:` closure below it is.
    ///   - commit: How to commit, defaulting to `ModelContext.save()`. See
    ///     `CadencePendingChangePersistence.commitInsert(of:in:commit:)`.
    @MainActor
    static func deleteCadenceData(
        in modelContext: ModelContext,
        canceller: CadenceNotificationCanceller? = nil,
        markDeleted: @MainActor (ModelContext) throws -> Void = { try markAllCadenceModelsDeleted(in: $0) },
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) async throws {
        // **Both halves are inside the boundary, not just the save (T-1102).** This was twenty-one
        // fetch-and-delete passes followed by a bare `try modelContext.save()`: a throw from pass
        // twelve — or from the save — propagated to Settings, which printed it, while the rows
        // from passes one through eleven stayed marked deleted in the app's single `ModelContext`.
        // Nothing undid them, so the next unrelated `save()` anywhere in the app would have
        // committed part of a reset the user was told had failed, and a `rollback()` anywhere
        // would have discarded it. A refused deletion has to leave the store where it found it.
        try CadencePendingChangePersistence.commitDelete(in: modelContext, commit: commit) {
            try markDeleted(modelContext)
        }

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
        //
        // Below the commit, deliberately: cancelling the reminders for data the store still holds
        // is the one step a refused deletion must not take.
        await (canceller ?? .default).run()
    }

    /// Marks every Cadence-created model deleted. **Pending only — this commits nothing.**
    ///
    /// Add a new `@Model` here whenever you add one to `CadenceSchema`;
    /// `CadencePrivacyDataResetSurfaceTests` drives its coverage check off the schema and fails if
    /// you do not.
    static func markAllCadenceModelsDeleted(in modelContext: ModelContext) throws {
        try deleteAll(FocusSessionLog.self, in: modelContext)
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
        // Reported, not swallowed, and the remaining artifacts are still cleaned up: the store is
        // already gone by the time the Keychain is reached, so a refused key deletion cannot fail
        // the reset — it can only fail to be *mentioned*, which is what it did (T-1101).
        let retainedAPIKeyReason = removeStoredAPIKey(using: aiSettingsManager)
        clearWidgetState()
        StoreBackupManager.clearPendingRestore()
        StoreBackupManager.clearFailedRestore()
        let removedBackupCount = try StoreBackupManager.deleteAllBackups()
        return PrivacyDataResetOutcome(
            removedBackupCount: removedBackupCount,
            retainedAPIKeyReason: retainedAPIKeyReason
        )
    }

    /// The credential half of the reset, as its own function for the reason `clearWidgetState` is
    /// one: `deleteCadenceDataAndLocalArtifacts` also deletes the real backups directory inside
    /// the app's container, so no test may call it, and a failure path no test can reach is a
    /// failure path no test can prove.
    ///
    /// - Returns: `nil` when the saved key was removed, or when there was none to remove —
    ///   `KeychainCredentialStore.deleteSecret` treats `errSecItemNotFound` as success. Otherwise
    ///   the sentence to show, and the key is still stored.
    ///
    /// It does **not** rethrow. `AISettingsManager.removeAPIKey` leaves `hasAPIKey` alone when the
    /// deletion is refused, so Settings → AI keeps reporting the key as present and its **Delete
    /// API Key** button remains the retry — which is the whole of the recovery, and is why the
    /// reset can honestly finish the artifacts below it.
    @MainActor
    static func removeStoredAPIKey(using aiSettingsManager: AISettingsManager) -> String? {
        do {
            try aiSettingsManager.removeAPIKey()
            return nil
        } catch {
            return AIErrorPresenter.message(for: error)
        }
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
