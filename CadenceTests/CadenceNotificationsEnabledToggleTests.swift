import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **T-361: turning "Enable reminders" off cancelled nothing until a scene-phase sweep.**
///
/// `NotificationManager.reconcile` has always done the right thing *when it runs* — it reads
/// `notificationsEnabled` and calls `cancelAll()` when the setting is off. What did not exist was
/// anything observing the setting **change**. There were zero `onChange(of: notificationsEnabled)`
/// handlers on either platform, so Settings wrote `UserDefaults` and stopped: pending OS
/// notifications survived until the app next backgrounded, and a reminder could fire moments after
/// the user switched reminders off.
///
/// The symmetric half is the same bug wearing the opposite sign, and a fix that only cancels
/// leaves it behind: switching reminders back **on** scheduled nothing until a lifecycle
/// checkpoint, so the setting read as doing nothing at all. Both directions are pinned separately
/// below, because a reaction with two branches that are each other's inverse is exactly the shape
/// where a swapped pair stays green forever.
///
/// The reaction lives in one shared place —
/// `HabitNotificationReconcileSupport.applyNotificationsEnabledChange` — rather than as a
/// per-platform `onChange` body, which is the near-copy shape several audits have already flagged
/// (T-374). Both effects are injectable for the reason `CadenceNotificationCanceller` is: they
/// bottom out in `NotificationManager`, which early-returns inside a test host, so from the
/// outside a branch that ran and a branch that did not look identical.
@MainActor
struct CadenceNotificationsEnabledToggleTests {

    // MARK: - The two directions

    @Test func turningRemindersOffCancelsPendingNotificationsImmediately() async throws {
        let recorder = ToggleEffectRecorder()
        let context = try makeContext()

        await HabitNotificationReconcileSupport.applyNotificationsEnabledChange(
            false,
            in: context,
            effects: recorder.effects
        )

        #expect(
            recorder.cancels == 1,
            "turning reminders off no longer cancels pending notifications (T-361)"
        )
        #expect(recorder.reconciles == 0, "turning reminders off ran the enable branch")
        // The call is awaited, not spawned: the recorder suspends before it records, so a
        // fire-and-forget spelling cannot have set this by the time the call returns.
        #expect(recorder.didFinishCancelling)
    }

    /// Not the same assertion twice. `scheduleReconcile` is what plans a scheduled task's start
    /// and due reminders and a habit's daily reminder; without this arm the toggle appears dead
    /// until the app backgrounds.
    @Test func turningRemindersOnReconcilesImmediately() async throws {
        let recorder = ToggleEffectRecorder()
        let context = try makeContext()

        await HabitNotificationReconcileSupport.applyNotificationsEnabledChange(
            true,
            in: context,
            effects: recorder.effects
        )

        #expect(
            recorder.reconciles == 1,
            "turning reminders back on no longer schedules anything until a lifecycle checkpoint (T-361)"
        )
        #expect(recorder.cancels == 0, "turning reminders on cancelled instead of scheduling")
    }

    /// Off does not route through `scheduleReconcile`, and that is deliberate: that path fetches
    /// tasks and habits first and skips the whole pass when either fetch fails, which would make
    /// "the reminders you just switched off go away" conditional on a store read succeeding.
    @Test func theOffBranchCancelsWithoutConsultingTheStore() async throws {
        let recorder = ToggleEffectRecorder()

        await HabitNotificationReconcileSupport.applyNotificationsEnabledChange(
            false,
            in: try makeContext(),
            effects: recorder.effects
        )

        #expect(recorder.cancels == 1)
        #expect(recorder.contextsSeenByReconcile == 0)
    }

    /// The live effects are what ship. `.live` cancelling through `CadenceNotificationCanceller`
    /// rather than restating `NotificationManager.shared.cancelAll()` keeps one owner for "how the
    /// app cancels pending notifications".
    @Test func theLiveEffectsDelegateToTheExistingCanceller() throws {
        let source = strippingComments(try sourceFile(Self.sharedOwner))
        let live = try cadenceFunctionBody("static var live: Self", in: source)

        #expect(live.contains("CadenceNotificationCanceller.live"))
        #expect(live.contains("HabitNotificationReconcileSupport.scheduleReconcile"))
        #expect(!live.contains("NotificationManager.shared.cancelAll"))
    }

    // MARK: - Both platforms react, and neither keeps its own copy

    /// `Cadence/iOS/` is inside `#if os(iOS)` and invisible to this macOS-built target, and both
    /// handlers are modifiers on a SwiftUI view with no symbol a test can call — which leaves a
    /// source scan as the only tool. It is scoped to the `onChange` body so it cannot pass on an
    /// unrelated line elsewhere in a 300-line settings view.
    @Test func bothPlatformsReactToTheToggleThroughTheSharedEntryPoint() throws {
        for path in Self.settingsOwners {
            let raw = try sourceFile(path)
            let source = strippingComments(raw)
            #expect(source != raw, "\(path): the comment stripper did nothing")
            #expect(source.count == raw.count, "\(path): the stripper changed the string's length")

            let body = try cadenceFunctionBody(".onChange(of: notificationsEnabled)", in: source)
            #expect(
                body.contains("HabitNotificationReconcileSupport.notificationsEnabledDidChange"),
                "\(path) does not react to the reminders toggle through the shared entry point (T-361)"
            )
            #expect(
                body.contains("modelContext"),
                "\(path) reacts without handing the shared entry point a store to reconcile against"
            )
        }
    }

    /// The repo rule is one shared component over near-copies, and the toggle's reaction is two
    /// branches that only stay each other's inverse while there is one of them. A platform that
    /// grew its own `cancelAll`/`reconcile` pair inside an `onChange` is the drift this forbids.
    @Test func neitherPlatformDeclaresItsOwnCopyOfTheToggleReaction() throws {
        var scanned = 0
        var reactingFiles: [String] = []

        for path in try swiftFiles(under: "Cadence") {
            let source = strippingComments(try sourceFile(path))
            scanned += 1

            if path != Self.sharedOwner {
                #expect(
                    !source.contains("func applyNotificationsEnabledChange"),
                    "\(path) declares a second copy of the toggle reaction"
                )
            }

            guard source.contains("onChange(of: notificationsEnabled)") else { continue }
            reactingFiles.append(path)
            #expect(
                !source.contains("cancelAll"),
                "\(path) cancels inline instead of through the shared entry point"
            )
            #expect(
                !source.contains("NotificationManager.shared.reconcile"),
                "\(path) reconciles inline instead of through the shared entry point"
            )
            #expect(
                !source.contains("scheduleReconcile"),
                "\(path) reconciles inline instead of through the shared entry point"
            )
        }

        #expect(scanned > 300, "only \(scanned) files scanned — the enumerator read nothing")
        #expect(
            reactingFiles.sorted() == Self.settingsOwners.sorted(),
            "the toggle is observed by \(reactingFiles.sorted()), not by both settings owners"
        )

        let owner = strippingComments(try sourceFile(Self.sharedOwner))
        #expect(owner.contains("func applyNotificationsEnabledChange"))
        #expect(owner.contains("func notificationsEnabledDidChange"))
    }

    /// The absence assertions above are worth nothing if the reads are failing: a scan that reads
    /// no files passes every one of them.
    @Test func theToggleSourceScanReachesTheFilesItClaimsTo() throws {
        for path in Self.settingsOwners + [Self.sharedOwner] {
            let characters = try sourceFile(path).count
            #expect(characters > 500, "\(path) read as \(characters) characters")
        }

        #expect(throws: SourceBodyScanError.self) {
            try cadenceFunctionBody(
                ".onChange(of: aSettingThatDoesNotExist)",
                in: try sourceFile(Self.sharedOwner)
            )
        }
    }

    // MARK: - Fixtures

    private static let sharedOwner = "Cadence/Shared/HabitNotificationReconcileSupport.swift"

    private static let settingsOwners = [
        "Cadence/macOS/Views/SettingsView.swift",
        "Cadence/iOS/iOSSettingsView.swift",
    ]

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
    }

    private func sourceFile(_ relativePath: String) throws -> String {
        try CadenceSourceScan.sourceFile(relativePath)
    }

    private func strippingComments(_ source: String) -> String {
        CadenceSourceScan.strippingComments(source)
    }

    private func swiftFiles(under relativeDirectory: String) throws -> [String] {
        let directory = CadenceSourceScan.repositoryRoot().appendingPathComponent(relativeDirectory)
        guard let enumerator = FileManager.default.enumerator(atPath: directory.path) else {
            return []
        }
        return enumerator.compactMap { element in
            guard let relativePath = element as? String, relativePath.hasSuffix(".swift") else {
                return nil
            }
            return "\(relativeDirectory)/\(relativePath)"
        }
    }
}

// MARK: - The effect recorder

/// Stands in for the two live effects, which both early-return inside a test host and so cannot
/// tell a branch that ran from one that did not on their own.
///
/// The cancel half suspends before it records, deliberately: a recorder that set its flag
/// synchronously would be satisfied by a spawned-and-forgotten `Task` whenever the scheduler
/// happened to run the child first. Same reasoning as `CadencePrivacyDataResetSurfaceTests`.
@MainActor
private final class ToggleEffectRecorder {
    private(set) var cancels = 0
    private(set) var didFinishCancelling = false
    private(set) var reconciles = 0
    private(set) var contextsSeenByReconcile = 0

    var effects: CadenceNotificationsEnabledEffects {
        CadenceNotificationsEnabledEffects(
            cancel: {
                self.cancels += 1
                try? await Task.sleep(for: .milliseconds(20))
                self.didFinishCancelling = true
            },
            reconcile: { _ in
                self.reconciles += 1
                self.contextsSeenByReconcile += 1
            }
        )
    }
}

/// **T-576: the notification permission card has to re-read the permission the user just granted.**
///
/// The flow that broke it is the card's own: the permission is denied, so the pane offers **Enable
/// Notifications**; the system will not prompt a second time, so the button falls through to System
/// Settings; the user grants there and comes back. On macOS nothing terminated the app and nothing
/// re-derived — the pane had no refresh hook of any kind — so it went on reading "Notification
/// access required" until the next relaunch. iOS had `.onAppear`, which is the half that does *not*
/// fire on a return from the Settings app.
///
/// The correct pattern already existed one permission over: T-253's reminders hook, which carries
/// `.onAppear` **and** `.onChange(of: scenePhase)`. It is generalised rather than copied
/// (`CadenceAuthorizationLifecycle`), because a second hand-written pair of lifecycle events is the
/// exact shape the first one was created to stop.
@MainActor
struct CadenceNotificationsAuthorizationLifecycleTests {

    /// Both surfaces apply the one hook, exactly once, and neither keeps a hand-written half
    /// beside it — which is how the reminders panes came to carry only the appearance half while
    /// both Inboxes had both.
    @Test func bothNotificationsSurfacesRederiveThroughTheOneHook() throws {
        let surfaces = [
            "Cadence/macOS/Views/SettingsNotificationsSection.swift",
            "Cadence/iOS/iOSNotificationsSettingsSection.swift",
        ]

        for path in surfaces {
            let code = try t576StrippingComments(t576SourceFile(path))
            #expect(
                code.contains("CadenceNotificationSettingsCopy.accessRequiredTitle"),
                "non-vacuity: \(path) is not the notification permission card"
            )

            let applications = code.components(separatedBy: ".notificationsAuthorizationLifecycle(").count - 1
            #expect(applications == 1, "\(path) applies the lifecycle hook \(applications) times, expected 1")

            #expect(
                !code.contains("refreshAuthorizationState"),
                "\(path) re-derives notification authorization outside the one shared hook again"
            )
            #expect(
                !code.contains("scenePhase"),
                "\(path) hand-writes its own half of the lifecycle beside the hook"
            )
        }
    }

    /// One modifier for both permissions, in one file. Two `ViewModifier`s each spelling
    /// `.onAppear` plus `.onChange(of: scenePhase)` is two places for the pair to come apart, which
    /// is the whole history of this hook.
    @Test func theLifecycleHookIsOneTypeRatherThanOnePerPermission() throws {
        let files = try t576SwiftFiles(under: "Cadence")
        #expect(files.count > 300, "the source scan found \(files.count) files and cannot be doing its job")

        let declarers = try files.filter {
            try t576StrippingComments(t576SourceFile($0)).contains("ViewModifier")
                && t576StrippingComments(t576SourceFile($0)).contains(".onChange(of: scenePhase)")
        }
        #expect(
            declarers == ["Cadence/Shared/CadenceAuthorizationLifecycle.swift"],
            "authorization lifecycle modifiers are declared in \(declarers.sorted())"
        )

        // The reminders file's copy is retired, not merely unread: the extension that used to live
        // there is what the four reminders surfaces still call, and it has to resolve to the shared
        // modifier rather than to a survivor beside it.
        let reminders = try t576StrippingComments(
            t576SourceFile("Cadence/Shared/CadenceRemindersPresentationSupport.swift")
        )
        #expect(reminders.contains("enum RemindersAccessRequestPlan"), "non-vacuity: wrong reminders file")
        #expect(
            !reminders.contains("ViewModifier"),
            "the reminders file declares its own lifecycle modifier again"
        )

        let shared = try t576StrippingComments(t576SourceFile("Cadence/Shared/CadenceAuthorizationLifecycle.swift"))
        #expect(shared.contains("func remindersAuthorizationLifecycle"), "the reminders entry point moved again")
        #expect(shared.contains("func notificationsAuthorizationLifecycle"), "the notifications entry point is gone")
    }
}

private func t576SourceFile(_ relativePath: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
}

private func t576SwiftFiles(under relativeDirectory: String) throws -> [String] {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let directory = root.appendingPathComponent(relativeDirectory)
    guard let enumerator = FileManager.default.enumerator(atPath: directory.path) else { return [] }
    return enumerator.compactMap { element in
        guard let relativePath = element as? String, relativePath.hasSuffix(".swift") else { return nil }
        return "\(relativeDirectory)/\(relativePath)"
    }
}

/// Blanks `//` and `/* */` so the assertions read code rather than the design notes this repo
/// keeps. Crude on purpose: a `//` inside a string literal is blanked too, which can only make
/// these checks stricter about what counts as a comment.
private func t576StrippingComments(_ source: String) throws -> String {
    var result = source
    for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            result.replaceSubrange(
                range,
                with: String(repeating: " ", count: result.distance(from: range.lowerBound, to: range.upperBound))
            )
        }
    }
    return result
}
