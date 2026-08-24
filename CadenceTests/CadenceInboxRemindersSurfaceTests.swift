import Foundation
import Testing
@testable import Cadence

/// T-163 / T-167: Apple Reminders in the Inbox, on **both** platforms, and the shipped permission
/// string that promises it.
///
/// **Why this file exists rather than one more assertion on the helper.**
/// `CadenceTasksPageScope.showsRemindersStrip` was already pinned by `CadenceCompactTabTests`
/// before any of this was built, and it stayed green through the entire period in which iOS had no
/// reminders surface at all: a pure function is true about nobody in particular. That is T-161
/// exactly — a committed fix was revertible with the whole suite green because the tests pinned a
/// helper while nothing observed the call site. So the assertions below read the real source files,
/// with exact per-file counts, in the style of `CadenceSharedBoardChromeTests`, and the last test
/// in the file is the one that stops the scan going vacuous.
///
/// Source-text assertions are the only tool available for the iOS half: `Cadence/iOS/` is inside
/// `#if os(iOS)` and this target builds for macOS, so there is no iOS symbol to reference.
struct CadenceInboxRemindersSurfaceTests {

    // MARK: - The surface exists on both platforms

    /// **The T-161 test for T-163.** Delete either call site and this fails. Nothing else in the
    /// suite would: the gate below is a pure function, the manager is a singleton with no view
    /// attached, and iOS's section is invisible to a macOS-built test target.
    @Test func bothPlatformsDrawAnAppleRemindersSectionInTheInbox() throws {
        try expectCallSites(
            of: "InboxAppleRemindersSectionView",
            at: ["Cadence/macOS/Views/TasksListView.swift": 1]
        )
        try expectCallSites(
            of: "iOSInboxRemindersSection",
            at: ["Cadence/iOS/iOSTaskCollectionPage.swift": 1]
        )
    }

    /// One gate, asked once per platform. A `collection == .inbox` or a `scope == .inbox` written
    /// out beside the call site instead would be a second, untested spelling of the rule — and it
    /// is the rule, not the drawing, that decides whether the Inbox keeps being an inbox.
    @Test func bothPlatformsGateTheSectionOnTheOneTestedFunction() throws {
        try expectCallSites(
            of: "CadenceTasksPageScope.showsRemindersStrip",
            at: [
                "Cadence/macOS/Views/TasksListView.swift": 1,
                "Cadence/iOS/iOSTaskCollectionPage.swift": 1,
            ]
        )
    }

    /// **The half of the permission string that had no code behind it at all.**
    /// `RemindersManager.completeReminder(id:)` shipped with exactly one caller — macOS's Inbox row
    /// — while the string promised "mark them complete when you check them off" on both platforms.
    /// These three files are the declaration and its two callers; drop the iOS one and this fails.
    @Test func markingAReminderCompleteIsReachableFromBothPlatforms() throws {
        let mentions = try filesMentioning("completeReminder")

        #expect(
            mentions == [
                "Cadence/Services/CadenceRemindersManager.swift",
                "Cadence/iOS/iOSInboxRemindersSection.swift",
                "Cadence/macOS/Views/TasksListView.swift",
            ],
            "completeReminder(id:) is reached from \(mentions.sorted())"
        )
    }

    // MARK: - The shipped permission string

    /// T-167. The string is in `project.pbxproj` rather than an `Info.plist`, which is why nothing
    /// was checking it. It claims two things — reminders shown *in Inbox*, and completion — and
    /// both are shipped to iOS as well as macOS, so this asserts the claim and the two tests above
    /// assert the code behind it. Reword the string and this fails; that is the point, because a
    /// reword is the other way this ticket could have been closed and it should be a deliberate
    /// edit rather than a silent drift away from what the app does.
    @Test func theShippedRemindersPermissionStringDescribesWhatBothPlatformsDo() throws {
        let project = try String(
            contentsOf: repositoryRoot().appendingPathComponent("Cadence.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )

        let declarations = project
            .components(separatedBy: "\n")
            .filter { $0.contains("INFOPLIST_KEY_NSRemindersFullAccessUsageDescription") }

        #expect(!declarations.isEmpty, "the reminders usage description is no longer declared")

        for declaration in declarations {
            #expect(declaration.contains("Inbox"), "the usage description stopped naming the Inbox")
            #expect(declaration.contains("complete"), "the usage description stopped promising completion")
        }
    }

    // MARK: - Access revoked while the page is open

    /// macOS re-derives on `onAppear` and that is enough there. It is not enough on iOS: Reminders
    /// access is revoked in the **Settings app**, so returning to a page that never disappeared is
    /// a foreground transition. Both paths have to be on the page.
    @Test func theIOSInboxRederivesAccessOnAppearAndOnForeground() throws {
        let source = try strippingComments(sourceFile("Cadence/iOS/iOSTaskCollectionPage.swift"))

        #expect(source.contains("refreshAuthorizationState"), "the iOS Inbox stopped re-deriving reminders access")
        #expect(source.contains("scenePhase"), "the iOS Inbox stopped re-deriving access on foreground")
        #expect(source.contains(".onAppear"), "the iOS Inbox stopped re-deriving access on appear")
    }

    /// **The bug that was already found and fixed once here, guarded so it cannot come back.**
    /// `EKEventStore.authorizationStatus` is cached per process on iOS and keeps reporting
    /// `.notDetermined` for the rest of the launch after the user taps Allow, so
    /// `requestAccess()` trusts EventKit's own `granted` answer and calls `store.reset()`. Anything
    /// that "confirms" a fresh grant by re-reading the cached status puts the Connect button back
    /// on screen until the app is relaunched — which is what the connect flow did before. The
    /// section asks for access and nothing else.
    @Test func theIOSSectionNeverConfirmsAFreshGrantAgainstTheCachedStatus() throws {
        let source = try strippingComments(sourceFile("Cadence/iOS/iOSInboxRemindersSection.swift"))

        #expect(source.contains("requestAccess()"), "the iOS Inbox lost its request-access path")
        #expect(
            !source.contains("refreshAuthorizationState"),
            "the iOS reminders section re-reads the per-process-cached authorization status again"
        )
        #expect(
            !source.contains("EKEventStore"),
            "the iOS reminders section reads EventKit directly instead of RemindersManager"
        )
    }

    // MARK: - The gate itself, at the iOS spelling

    /// The mapping the iOS call site goes through. Two enums for the same two-case choice, so the
    /// one that decides is asked and the other is translated.
    @Test func everyTaskCollectionMapsOntoItsScope() {
        #expect(CadenceTasksPageScope(collection: .inbox) == .inbox)
        #expect(CadenceTasksPageScope(collection: .allTasks) == .all)

        // Total, and stated as such: a third collection must not silently land on a scope.
        for collection in CadenceTaskCollection.allCases {
            let scope = CadenceTasksPageScope(collection: collection)
            #expect(scope.section.title == collection.title || scope == .all)
        }
    }

    /// The gate read through the iOS spelling, which is the combination the page actually asks.
    /// All Tasks answers `false` in every state, including the ones that are `true` for Inbox.
    @Test func onlyTheInboxCollectionShowsTheSection() {
        for isAuthorized in [true, false] {
            for isLoading in [true, false] {
                for hasReminders in [true, false] {
                    #expect(
                        !CadenceTasksPageScope.showsRemindersStrip(
                            scope: CadenceTasksPageScope(collection: .allTasks),
                            isAuthorized: isAuthorized,
                            isLoading: isLoading,
                            hasReminders: hasReminders
                        )
                    )
                }
            }
        }

        let inbox = CadenceTasksPageScope(collection: .inbox)
        // Not connected: the section is the Connect button, so it shows with nothing to list.
        #expect(CadenceTasksPageScope.showsRemindersStrip(scope: inbox, isAuthorized: false, isLoading: false, hasReminders: false))
        // Connected and quiet with nothing open: nothing to say, so the Inbox keeps its own empty state.
        #expect(!CadenceTasksPageScope.showsRemindersStrip(scope: inbox, isAuthorized: true, isLoading: false, hasReminders: false))
    }

    /// The empty state and the section are alternatives. macOS spells that as an extra clause on
    /// `TasksListView.isEmpty`; iOS passes `hidesEmptyState:` into its sections view. Same
    /// statement, so the two must stay each other's negation — which is what this pins on the one
    /// case that used to get it wrong: a cleared Inbox with open reminders under it.
    @Test func aClearedInboxWithOpenRemindersDoesNotAlsoAnnounceThatItIsClear() throws {
        let inbox = CadenceTasksPageScope(collection: .inbox)
        #expect(CadenceTasksPageScope.showsRemindersStrip(scope: inbox, isAuthorized: true, isLoading: false, hasReminders: true))

        let page = try strippingComments(sourceFile("Cadence/iOS/iOSTaskCollectionPage.swift"))
        #expect(
            page.contains("hidesEmptyState: showsRemindersSection"),
            "the iOS Inbox can show \"Inbox is clear\" above a list of open reminders again"
        )
    }

    // MARK: - T-264: the count capsule is not a lie above the access card

    /// **T-264.** Both Inbox headers used to pass `reminders.count` unconditionally, so
    /// not-determined, denied and restricted all rendered "APPLE REMINDERS 0" directly above a
    /// card admitting Cadence cannot see the reminders at all — a count of zero states a fact the
    /// app does not have. The fix is the count becoming `nil` (not `0`) whenever the section is not
    /// connected, and `CadenceTaskGroupHeading` / `TaskListGroupHeader` suppress the capsule for a
    /// `nil` count rather than drawing it.
    @Test func neitherInboxHeaderPassesTheRawReminderCountUnconditionally() throws {
        let macSource = try strippingComments(sourceFile("Cadence/macOS/Views/InboxSupportViews.swift"))
        #expect(
            macSource.range(of: "regularCount:\\s*reminders\\.count\\s*,", options: .regularExpression) == nil,
            "macOS's Inbox header passes the raw reminder count again, with no gate on authorization"
        )
        #expect(
            macSource.range(of: "regularCount:\\s*isAuthorized\\s*\\?\\s*reminders\\.count\\s*:\\s*nil", options: .regularExpression) != nil,
            "macOS's Inbox header stopped hiding the count while unauthorized"
        )

        let iosSource = try strippingComments(sourceFile("Cadence/iOS/iOSInboxRemindersSection.swift"))
        #expect(
            iosSource.range(of: "count:\\s*remindersManager\\.reminders\\.count\\s*\\n", options: .regularExpression) == nil,
            "iOS's Inbox header passes the raw reminder count again, with no gate on authorization"
        )
        #expect(
            iosSource.range(
                of: "count:\\s*state\\.isConnected\\s*\\?\\s*remindersManager\\.reminders\\.count\\s*:\\s*nil",
                options: .regularExpression
            ) != nil,
            "iOS's Inbox header stopped hiding the count while unauthorized"
        )
    }

    /// The heading component itself must be able to suppress the capsule, or the two call-site
    /// fixes above have nowhere to route a `nil` to. Pins the declaration rather than the call
    /// sites, so a future revert of either component (not just the two headers) is caught here.
    ///
    /// **This test pins the *type*, not the decision, and that is not enough on its own.** A
    /// verifier rewrote `CadenceTaskGroupHeading.body` from `if let count` to
    /// `countBadge(count ?? 0)` — restoring "APPLE REMINDERS 0" over the access card — and the
    /// whole suite stayed green, because `let count: Int?` still read exactly as before. The two
    /// tests below are what close that: `onlyAnUnknownCountSuppressesTheCapsule` states the rule
    /// on a value, and `bothGroupHeadersReadTheOneCapsuleRule` says both bodies ask for it.
    @Test func theSharedHeadingComponentsAcceptAnOptionalCount() throws {
        let heading = try strippingComments(sourceFile("Cadence/Shared/Components/CadenceTaskGroupHeading.swift"))
        #expect(heading.contains("let count: Int?"), "CadenceTaskGroupHeading.count is no longer optional")

        let iosHeader = try strippingComments(sourceFile("Cadence/iOS/iOSTaskGroupSection.swift"))
        #expect(iosHeader.contains("let count: Int?"), "iOSTaskGroupHeader.count is no longer optional")

        let macHeader = try strippingComments(sourceFile("Cadence/macOS/Views/ListDetailSupportViews.swift"))
        #expect(macHeader.contains("let regularCount: Int?"), "TaskListGroupHeader.regularCount is no longer optional")
    }

    /// The rule itself, exercised directly. `nil` is "cannot say" and draws nothing; every real
    /// count — **including zero**, which is a real answer — keeps its capsule.
    @Test func onlyAnUnknownCountSuppressesTheCapsule() {
        #expect(!CadenceTaskGroupHeadingMetrics.showsCapsule(for: nil))
        #expect(CadenceTaskGroupHeadingMetrics.showsCapsule(for: 0))
        for count in [1, 2, 7, 99, Int.max] {
            #expect(CadenceTaskGroupHeadingMetrics.showsCapsule(for: count))
        }
    }

    /// **The half that catches a rewritten view body.** `onlyAnUnknownCountSuppressesTheCapsule`
    /// above says what the rule is; nothing in a macOS-built test target can watch a SwiftUI
    /// `body` decide to obey it, so this asserts that both bodies *ask*. That makes it a source
    /// scan — the thing that failed here before — but a **positive** one, which is the polarity
    /// `Cadence/Shared/AGENTS.md` recommends: the `?? 0` rewrite that survived the old assertion
    /// deletes the call and fails this, and a header that keeps the behaviour with its own private
    /// copy of the rule fails it too. Both mutations were run and both fail here.
    @Test func bothGroupHeadersReadTheOneCapsuleRule() throws {
        try expectCallSites(
            of: "CadenceTaskGroupHeadingMetrics.showsCapsule",
            at: [
                "Cadence/Shared/Components/CadenceTaskGroupHeading.swift": 1,
                "Cadence/macOS/Views/ListDetailSupportViews.swift": 1,
            ]
        )
    }

    // MARK: - T-256: isRestricted reaches every live consumer

    /// The manager exposes the live status directly, with no session fold — a restriction is a
    /// device policy, not something the in-app prompt can produce or reverse, so there is nothing
    /// here for `deniedInThisSession` to have an opinion about (contrast `isDenied`, which does
    /// fold a session record in, per its own doc comment).
    @Test func theManagerReadsRestrictedLiveWithNoSessionFold() throws {
        let source = try strippingComments(sourceFile("Cadence/Services/CadenceRemindersManager.swift"))
        #expect(source.contains("var isRestricted: Bool"), "RemindersManager stopped exposing isRestricted")
        #expect(
            source.range(
                of: "isRestricted:\\s*Bool\\s*\\{\\s*EKEventStore\\.authorizationStatus\\(for:\\s*\\.reminder\\)\\s*==\\s*\\.restricted",
                options: .regularExpression
            ) != nil,
            "RemindersManager.isRestricted no longer reads the live EventKit status directly"
        )
    }

    /// **The call-site pin.** `isRestricted` is pure infrastructure until something reads it —
    /// exactly the "cannot fail at all" shape this file's own header warns about for
    /// `showsRemindersStrip`. Every surface that resolves a `RemindersConnectionState` from the
    /// manager's flags must pass this one too, or `.restricted`'s presentation is unreachable in
    /// the running app no matter how well the pure type is tested in `RemindersConnectionStateTests`.
    @Test func everyLiveResolverIsHandedIsRestricted() throws {
        for path in [
            "Cadence/macOS/Views/SettingsRemindersSection.swift",
            "Cadence/macOS/Views/SettingsView.swift",
            "Cadence/iOS/iOSRemindersSettingsSection.swift",
            "Cadence/iOS/iOSInboxRemindersSection.swift",
        ] {
            let source = try strippingComments(sourceFile(path))
            #expect(
                source.contains("isRestricted: remindersManager.isRestricted"),
                "\(path) stopped resolving RemindersConnectionState with isRestricted"
            )
        }
    }

    /// macOS's Inbox strip does not build a `RemindersConnectionState` at all — it takes
    /// `isAuthorized` / `isDenied` / `isRestricted` as three separate booleans instead — so it is
    /// pinned on its own rather than folded into the loop above.
    @Test func macOSInboxPassesIsRestrictedThroughToItsAccessRow() throws {
        let callSite = try strippingComments(sourceFile("Cadence/macOS/Views/TasksListView.swift"))
        #expect(
            callSite.contains("isRestricted: remindersManager.isRestricted"),
            "TasksListView stopped handing the Inbox reminders section a live isRestricted"
        )

        let section = try strippingComments(sourceFile("Cadence/macOS/Views/InboxSupportViews.swift"))
        #expect(section.contains("let isRestricted: Bool"), "InboxAppleRemindersSectionView dropped its isRestricted parameter")
        #expect(
            section.contains("isRestricted: isRestricted"),
            "InboxAppleRemindersSectionView stopped forwarding isRestricted to AppleRemindersAccessRow"
        )
        // No button at all when restricted — the dead-`.denied`-button bug closed a second time.
        #expect(
            section.contains("if !isRestricted {"),
            "AppleRemindersAccessRow no longer withholds its button when restricted"
        )
    }

    // MARK: - T-255: a completion that fails does not stay ticked

    /// **The refusal ordering, as a value.** It used to be a `guard` chain inside a method
    /// returning `Void`, which is why four separate failures were indistinguishable from success.
    /// Authorization is asked first because an unauthorized store cannot be trusted to resolve an
    /// identifier at all; "gone" beats "read-only" for the same reason — there is no list to ask
    /// about a reminder that is not there.
    @Test func theCompletionRefusalsAreOrderedFromTheOutsideIn() {
        #expect(
            AppleReminderCompletionOutcome.refusal(
                isAuthorized: false,
                reminderResolves: false,
                allowsContentModifications: false
            ) == .notAuthorized
        )
        // Authorization wins even when the two inner answers are fine.
        #expect(
            AppleReminderCompletionOutcome.refusal(
                isAuthorized: false,
                reminderResolves: true,
                allowsContentModifications: true
            ) == .notAuthorized
        )
        #expect(
            AppleReminderCompletionOutcome.refusal(
                isAuthorized: true,
                reminderResolves: false,
                allowsContentModifications: true
            ) == .reminderUnavailable
        )
        #expect(
            AppleReminderCompletionOutcome.refusal(
                isAuthorized: true,
                reminderResolves: true,
                allowsContentModifications: false
            ) == .listIsReadOnly
        )
        // The one combination that lets the write through.
        #expect(
            AppleReminderCompletionOutcome.refusal(
                isAuthorized: true,
                reminderResolves: true,
                allowsContentModifications: true
            ) == nil
        )
    }

    /// **The bug, stated on a value.** The tick asserts "Apple Reminders has this completed", so
    /// only the outcome that confirms a save may leave it standing. Every other outcome — the
    /// three refusals and the `save` throw — has to put the row back, or the user is looking at a
    /// completed reminder that Apple Reminders still has open until the next relaunch un-ticks it.
    @Test func onlyAConfirmedSaveLeavesTheRowTicked() {
        #expect(AppleReminderCompletionResolution.resolve(.completed) == .keepCompleted)
        #expect(!AppleReminderCompletionResolution.resolve(.completed).revertsTick)

        for outcome: AppleReminderCompletionOutcome in [
            .notAuthorized, .reminderUnavailable, .listIsReadOnly, .saveFailed
        ] {
            #expect(
                AppleReminderCompletionResolution.resolve(outcome).revertsTick,
                "\(outcome) leaves the row ticked over a reminder Apple Reminders still has open"
            )
        }
    }

    /// **Revert *and* say why — but only where nothing else will.** A tick that quietly undoes
    /// itself reads as a misclick, so silence is not the whole answer; an alert on every transient
    /// EventKit refusal is noise, and arrives per row when a sync conflict or a revoked grant hits
    /// a whole list at once. `.notAuthorized` is the one case that stays silent, because the
    /// section replaces every row with its access card and says far more than a line under one row
    /// could.
    @Test func onlyTheOutcomeTheSurfaceAlreadyExplainsRevertsSilently() {
        #expect(AppleReminderCompletionResolution.resolve(.notAuthorized) == .revertSilently)
        #expect(AppleReminderCompletionResolution.resolve(.notAuthorized).notice == nil)
        #expect(AppleReminderCompletionResolution.resolve(.completed).notice == nil)

        for outcome: AppleReminderCompletionOutcome in [.reminderUnavailable, .listIsReadOnly, .saveFailed] {
            let notice = AppleReminderCompletionResolution.resolve(outcome).notice
            #expect(notice != nil, "\(outcome) reverts the tick with no explanation at all")
            #expect(notice?.isEmpty == false)
        }

        // Three distinct sentences: a reminder that is gone, a list that will not take writes and
        // a save that threw are three different things to do about it.
        let notices = [
            AppleReminderCompletionOutcome.reminderUnavailable,
            .listIsReadOnly,
            .saveFailed
        ].compactMap { AppleReminderCompletionResolution.resolve($0).notice }
        #expect(Set(notices).count == 3, "two failures share one sentence")
    }

    /// **The production method, exercised.** Everything above is pure; this is the real
    /// `RemindersManager` answering a completion that cannot possibly succeed — no grant needed,
    /// and true whether or not this host happens to have one, because no store contains this
    /// identifier. Under the old signature there was nothing to return and nothing to assert.
    @MainActor
    @Test func theManagerReportsACompletionItCouldNotPerform() {
        let outcome = RemindersManager.shared.completeReminder(id: "cadence-t255-no-such-reminder")

        #expect(outcome != .completed, "a reminder that does not exist reported a successful save")
        #expect(
            AppleReminderCompletionResolution.resolve(outcome).revertsTick,
            "the row would keep its tick after a completion that never happened"
        )
    }

    /// **The call-site pin.** The policy above is infrastructure until both rows apply it —
    /// exactly the "cannot fail at all" shape this file's own header warns about. A positive scan,
    /// which is the polarity `Cadence/Shared/AGENTS.md` recommends: a row that goes back to
    /// discarding the outcome, or grows its own second policy, fails here. iOS has no other tool
    /// available — `Cadence/iOS/` is invisible to a macOS-built test target — and macOS's row is
    /// `private` inside a view file, so neither is referenceable.
    @Test func bothReminderRowsApplyTheOneCompletionPolicy() throws {
        try expectCallSites(
            of: "AppleReminderCompletionResolution.resolve",
            at: [
                "Cadence/macOS/Views/InboxSupportViews.swift": 1,
                "Cadence/iOS/iOSInboxRemindersSection.swift": 1,
            ]
        )

        for path in [
            "Cadence/macOS/Views/InboxSupportViews.swift",
            "Cadence/iOS/iOSInboxRemindersSection.swift",
        ] {
            let source = try strippingComments(sourceFile(path))
            #expect(
                source.contains("let onComplete: (String) -> AppleReminderCompletionOutcome"),
                "\(path) takes a completion handler that cannot report a failure again"
            )
            #expect(
                source.contains("resolution.revertsTick"),
                "\(path) stopped asking the shared policy whether to put the tick back"
            )
            #expect(
                source.contains("failureNotice = resolution.notice"),
                "\(path) stopped showing the shared policy's sentence"
            )
        }
    }

    /// The manager has to hand the answer back at all. Pinned on the declaration rather than on
    /// its callers, so a revert to `-> Void` fails here even if a caller is deleted at the same
    /// time — and the refusal ordering has to stay the shared one rather than becoming a second
    /// `guard` chain that no test can reach.
    @Test func theManagerReturnsTheWritesAnswerAndDoesNotRespellTheRefusals() throws {
        let source = try strippingComments(sourceFile("Cadence/Services/CadenceRemindersManager.swift"))

        #expect(
            source.contains("func completeReminder(id: String) -> AppleReminderCompletionOutcome"),
            "RemindersManager.completeReminder discards the write's answer again"
        )
        #expect(
            source.contains("AppleReminderCompletionOutcome.refusal("),
            "RemindersManager stopped reading the shared refusal ordering"
        )
        #expect(source.contains("return .completed"), "the success path stopped reporting success")
        #expect(source.contains("return .saveFailed"), "a save throw stopped reporting a failure")
    }

    // MARK: - The row's two tints

    /// EventKit's priority is inverted — **1 is the most urgent, 9 the least** — and 0 means unset.
    /// Both rows read the same mapping, and it resolves to `Theme.priorityColor`, so an Apple
    /// Reminder marked high looks exactly as high as a Cadence task marked high in the same card.
    @Test func reminderPriorityMapsOntoTheAppsOwnPriorityRamp() {
        #expect(AppleReminderRowPresentation.priorityTint(1) == Theme.priorityColor(.high))
        #expect(AppleReminderRowPresentation.priorityTint(4) == Theme.priorityColor(.high))
        #expect(AppleReminderRowPresentation.priorityTint(5) == Theme.priorityColor(.medium))
        #expect(AppleReminderRowPresentation.priorityTint(6) == Theme.priorityColor(.low))
        #expect(AppleReminderRowPresentation.priorityTint(9) == Theme.priorityColor(.low))
        #expect(AppleReminderRowPresentation.priorityTint(0) == Theme.priorityColor(.none))
        // Out of range rather than crashing or reading as urgent.
        #expect(AppleReminderRowPresentation.priorityTint(42) == Theme.priorityColor(.none))
    }

    /// Colour is reserved for the exceptional: late is red, today is amber, and everything still
    /// ahead — or unparseable — is chrome.
    @Test func onlyALateOrTodayDueDateEarnsAColour() {
        #expect(AppleReminderRowPresentation.dueTint(dayOffset: -1) == Theme.red)
        #expect(AppleReminderRowPresentation.dueTint(dayOffset: 0) == Theme.amber)
        #expect(AppleReminderRowPresentation.dueTint(dayOffset: 1) == Theme.dim)
        #expect(AppleReminderRowPresentation.dueTint(dayOffset: nil) == Theme.dim)
    }

    /// Neither row may re-spell the tints it was just handed. macOS's had them inline; the whole
    /// value of moving them is that the second platform could not write a third ramp.
    @Test func neitherReminderRowKeepsItsOwnColourRamp() throws {
        for path in [
            "Cadence/macOS/Views/InboxSupportViews.swift",
            "Cadence/iOS/iOSInboxRemindersSection.swift",
        ] {
            let source = try strippingComments(sourceFile(path))
            #expect(
                source.contains("AppleReminderRowPresentation"),
                "\(path) stopped reading the shared reminder tints"
            )
            #expect(
                source.range(of: "case 1\\s*\\.\\.\\.\\s*4", options: .regularExpression) == nil,
                "\(path) has its own reminder priority ramp again"
            )
        }
    }

    // MARK: - The scan itself

    /// The absence assertions above are worth nothing if the scan reads no files, and a scan that
    /// silently returns nothing passes every one of them. This is the test that stops them going
    /// vacuous — the same guard `CadenceSharedBoardChromeTests` carries, and for the same reason: a
    /// `/tmp` against `/private/tmp` path mismatch once made a scan that read nothing at all look
    /// like four clean results.
    @Test func theSourceScanActuallyReachesBothPlatformsSource() throws {
        let files = try swiftFiles(under: "Cadence")

        #expect(files.count > 300, "the source scan found \(files.count) files and cannot be doing its job")
        #expect(files.contains("Cadence/iOS/iOSInboxRemindersSection.swift"))
        #expect(files.contains("Cadence/iOS/iOSTaskCollectionPage.swift"))
        #expect(files.contains("Cadence/macOS/Views/TasksListView.swift"))
        #expect(files.contains("Cadence/macOS/Views/InboxSupportViews.swift"))
        #expect(files.contains("Cadence/Services/CadenceRemindersManager.swift"))

        // And the scan has to be reading *content*, not just listing names: a positive control on
        // a string that is unmistakably in one of the files above.
        #expect(try strippingComments(sourceFile("Cadence/Services/CadenceRemindersManager.swift"))
            .contains("func completeReminder"))
        #expect(try !filesMentioning("completeReminder").isEmpty)
    }
}

// MARK: - Source-reading helpers

/// Fails unless `name` is called exactly `count` times in each listed file.
///
/// Exact counts rather than "contains", for the reason `CadenceSharedBoardChromeTests` records: a
/// mutation that reverted *one* of several call sites left a "contains" assertion green.
private func expectCallSites(
    of name: String,
    at callSites: [String: Int],
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    for (path, expected) in callSites {
        let code = try strippingComments(sourceFile(path))
        let actual = code.components(separatedBy: "\(name)(").count - 1
        #expect(
            actual == expected,
            "\(path) calls \(name) \(actual) times, expected \(expected)",
            sourceLocation: sourceLocation
        )
    }
}

/// Every file under `Cadence/` whose **live code** mentions `name`, sorted. Comments are stripped
/// so the tombstones and design notes this repo keeps do not count as callers.
private func filesMentioning(_ name: String) throws -> [String] {
    let pattern = "(?<![A-Za-z0-9_])\(name)(?![A-Za-z0-9_])"
    return try swiftFiles(under: "Cadence")
        .filter { try strippingComments(sourceFile($0)).range(of: pattern, options: .regularExpression) != nil }
        .sorted()
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

/// `enumerator(atPath:)` rather than `enumerator(at:)`: the URL variant yields absolute paths, and
/// `#filePath` can name the repo through a symlinked prefix (`/tmp` against `/private/tmp` on an
/// isolated build tree) that `FileManager` resolves and the literal does not.
private func swiftFiles(under relativeDirectory: String) throws -> [String] {
    let directory = repositoryRoot().appendingPathComponent(relativeDirectory)
    guard let enumerator = FileManager.default.enumerator(atPath: directory.path) else {
        return []
    }
    return enumerator.compactMap { element in
        guard let relativePath = element as? String, relativePath.hasSuffix(".swift") else { return nil }
        return "\(relativeDirectory)/\(relativePath)"
    }
}

private func sourceFile(_ relativePath: String) throws -> String {
    try String(contentsOf: repositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
}

/// Blanks out `//` line comments and `/* */` block comments so the assertions read code rather than
/// prose. Crude on purpose: a `//` inside a string literal is blanked too, which can only make
/// these checks stricter about what counts as a comment, never looser about live code.
private func strippingComments(_ source: String) throws -> String {
    var result = source
    for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            result.replaceSubrange(range, with: String(repeating: " ", count: result.distance(from: range.lowerBound, to: range.upperBound)))
        }
    }
    return result
}
