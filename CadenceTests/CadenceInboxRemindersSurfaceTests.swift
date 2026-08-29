import EventKit
import Foundation
import SwiftUI
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

    /// **T-253, the rule as a value.** Only a return to `.active` re-derives. The other two phases
    /// are the *leaving* halves of the same transition: re-reading EventKit on the way out costs a
    /// fetch and tells the user nothing, because the change they are about to make in System
    /// Settings has not happened yet.
    @Test func onlyAReturnToTheForegroundRederivesAuthorization() {
        #expect(RemindersAuthorizationLifecycle.shouldRefresh(onScenePhaseChangeTo: .active))
        #expect(!RemindersAuthorizationLifecycle.shouldRefresh(onScenePhaseChangeTo: .inactive))
        #expect(!RemindersAuthorizationLifecycle.shouldRefresh(onScenePhaseChangeTo: .background))
    }

    /// **T-253, the effect.** The hook's one side effect is a re-derive, and `reconcileLedger`
    /// counts those inside `refreshAuthorizationState()` itself — so this watches the read happen
    /// rather than reading the text of a view body, on a host with no Reminders grant. The
    /// `isEnabled: false` half is the iOS Tasks page on All Tasks, which has no reminders surface
    /// on it and must not touch EventKit at all.
    @MainActor
    @Test func theSharedHookReadsEventKitOnlyWhereItIsEnabled() {
        let manager = RemindersManager.shared

        let before = manager.reconcileLedger.authorizationRefreshes
        RemindersAuthorizationLifecycleModifier(manager: manager, isEnabled: false).refreshIfEnabled()
        #expect(
            manager.reconcileLedger.authorizationRefreshes == before,
            "a disabled reminders lifecycle hook read EventKit anyway"
        )

        RemindersAuthorizationLifecycleModifier(manager: manager, isEnabled: true).refreshIfEnabled()
        #expect(
            manager.reconcileLedger.authorizationRefreshes == before + 1,
            "an enabled reminders lifecycle hook did not re-derive authorization"
        )
    }

    /// **T-253, both halves of the hook**, scoped to the modifier's own `body` so a count cannot be
    /// satisfied by something elsewhere in the file. This is the shape the two Settings sections
    /// were missing: `.onAppear` fires once, when the surface is first shown, and revoking in
    /// System Settings does not terminate the app on macOS — so without the foreground half a user
    /// who follows Settings > Reminders' own **Open Reminders Settings** button, revokes, and comes
    /// back is looking at a view that never disappeared and still claims access.
    @Test func theSharedHookCarriesBothHalvesOfTheLifecycle() throws {
        let source = try strippingComments(sourceFile("Cadence/Shared/CadenceRemindersPresentationSupport.swift"))
        let body = try cadenceFunctionBody("func body(content: Content) -> some View", in: source)

        #expect(body.contains(".onAppear"), "the shared reminders hook stopped re-deriving on appear")
        #expect(body.contains(".onChange(of: scenePhase)"), "the shared reminders hook stopped re-deriving on foreground")
        #expect(
            body.contains("RemindersAuthorizationLifecycle.shouldRefresh(onScenePhaseChangeTo:"),
            "the shared reminders hook re-spells which scene phase counts"
        )
        #expect(
            body.components(separatedBy: "refreshIfEnabled()").count - 1 == 2,
            "the shared reminders hook no longer refreshes from exactly its two lifecycle events"
        )
    }

    /// **T-253, the call sites.** All four reminders surfaces apply the one hook, and none of them
    /// keeps a hand-written half beside it — which is how two of them came to have only the
    /// appearance half while both Inboxes had both, each surface's comment claiming it matched the
    /// others.
    @Test func allFourRemindersSurfacesRederiveThroughTheOneHook() throws {
        let surfaces = [
            "Cadence/macOS/Views/SettingsRemindersSection.swift",
            "Cadence/macOS/Views/TasksListView.swift",
            "Cadence/iOS/iOSRemindersSettingsSection.swift",
            "Cadence/iOS/iOSTaskCollectionPage.swift",
        ]

        try expectCallSites(
            of: ".remindersAuthorizationLifecycle",
            at: Dictionary(uniqueKeysWithValues: surfaces.map { ($0, 1) })
        )

        for path in surfaces {
            let source = try strippingComments(sourceFile(path))
            #expect(
                !source.contains("refreshAuthorizationState"),
                "\(path) re-derives reminders authorization outside the one shared hook again"
            )
        }
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
            macSource.range(
                of: "regularCount:\\s*state\\.isConnected\\s*\\?\\s*reminders\\.count\\s*:\\s*nil",
                options: .regularExpression
            ) != nil,
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

    /// **T-254: the fold happens once**, and this is scoped to the one function that performs it,
    /// so a second `resolve` somewhere else in the manager cannot satisfy it. `isRestricted` is the
    /// flag that keeps going missing — it is pure infrastructure until a resolver is handed it, and
    /// `.restricted`'s whole presentation is unreachable in the running app if one is not, no
    /// matter how well `RemindersConnectionStateTests` pins the type.
    @Test func theManagerFoldsAllThreeFlagsIntoTheOneConnectionState() throws {
        let source = try strippingComments(sourceFile("Cadence/Services/CadenceRemindersManager.swift"))
        let fold = try cadenceFunctionBody("var connectionState: RemindersConnectionState", in: source)

        #expect(fold.contains("RemindersConnectionState.resolve("), "the manager stopped asking the shared resolver")
        #expect(fold.contains("isAuthorized: isAuthorized"), "the fold stopped reading isAuthorized")
        #expect(fold.contains("isDenied: isDenied"), "the fold stopped reading isDenied")
        #expect(fold.contains("isRestricted: isRestricted"), "the fold stopped reading isRestricted")
    }

    /// **And it happens nowhere else.** Five surfaces used to resolve their own — macOS Settings'
    /// category badge, both Settings sections, the iOS Inbox — while the fifth, macOS's Inbox,
    /// resolved nothing at all and branched three raw booleans in the wrong order. Five call sites
    /// is five chances to get the ordering wrong, and one of them did.
    @Test func nothingButTheManagerResolvesAConnectionStateFromTheFlags() throws {
        let callers = try filesContaining("RemindersConnectionState.resolve(")
        #expect(
            callers == ["Cadence/Services/CadenceRemindersManager.swift"],
            "the flags are folded into a connection state in \(callers) rather than only in the manager"
        )
    }

    /// **Every reminders surface reads that one answer.** The counterpart to the test above: one
    /// producer is worth nothing if a surface stops consuming it.
    ///
    /// **`SettingsView.swift` is listed at zero, and that is the assertion, not an exemption
    /// (T-20).** It read the state for one thing — a pill in the category header saying
    /// `Connected` / `Not connected` — and that pill restated the first line of the Reminders card
    /// directly beneath it. iOS deleted the same header slot in `775833d`; T-20 deleted it here,
    /// along with `SettingsStatusBadge` and the nine-case `switch` that fed it. A surface that no
    /// longer *displays* reminders state must not *read* it: a live read with nothing drawn from it
    /// is how the badge would come back one render at a time. Zero keeps the file inside this
    /// test's reach rather than dropping it out of the dictionary, so re-growing the header pill
    /// fails here rather than passing unnoticed.
    ///
    /// The four surfaces that still show the state are still required to read it, so this test
    /// fails in both directions.
    @Test func everyRemindersSurfaceReadsTheOneConnectionState() throws {
        try expectOccurrences(
            of: "remindersManager.connectionState",
            at: [
                "Cadence/macOS/Views/SettingsRemindersSection.swift": 1,
                "Cadence/macOS/Views/SettingsView.swift": 0,
                "Cadence/macOS/Views/TasksListView.swift": 1,
                "Cadence/iOS/iOSRemindersSettingsSection.swift": 1,
                "Cadence/iOS/iOSInboxRemindersSection.swift": 1,
            ]
        )
    }

    /// **T-254's structural half.** macOS's Inbox strip took `isAuthorized` / `isDenied` /
    /// `isRestricted` as three separate booleans and branched them itself, `isAuthorized` first —
    /// the opposite order to the shared resolver, which puts a live denial ahead of a stale
    /// authorized snapshot on purpose. In that window the Inbox drew reminder rows with completion
    /// buttons that no longer write while Settings, one category away, said access was denied.
    /// There is nothing left to get wrong: the view has one input and it arrives resolved.
    @Test func theMacOSInboxStripTakesOneStateAndNoBooleansOfItsOwn() throws {
        let section = try strippingComments(sourceFile("Cadence/macOS/Views/InboxSupportViews.swift"))

        #expect(
            section.contains("let state: RemindersConnectionState"),
            "InboxAppleRemindersSectionView no longer takes a resolved connection state"
        )
        for flag in ["let isAuthorized: Bool", "let isDenied: Bool", "let isRestricted: Bool"] {
            #expect(
                !section.contains(flag),
                "InboxAppleRemindersSectionView takes `\(flag)` again and can branch it in its own order"
            )
        }

        let body = try cadenceFunctionBody("var body: some View", in: section)
        #expect(
            body.contains("if state.isConnected {"),
            "macOS's Inbox strip decides whether it is connected somewhere other than the shared state"
        )
    }

    /// **T-254's copy half.** Four surfaces read `accessTitle` / `accessMessage` / `accessAction`;
    /// this one hand-wrote three of its four sentences beside them, and only borrowed the shared
    /// strings for `.restricted`. Which button appears — and that `.restricted` gets none — is the
    /// shared value's `accessAction` now rather than a local `if`, so [[T-256]]'s dead-button rule
    /// is obeyed here by construction instead of by a second spelling of it.
    @Test func theMacOSInboxAccessRowSpeaksTheSharedVocabulary() throws {
        let section = try strippingComments(sourceFile("Cadence/macOS/Views/InboxSupportViews.swift"))

        for needle in ["state.accessTitle", "state.accessMessage", "state.accessAction"] {
            #expect(section.contains(needle), "macOS's Inbox access row stopped reading \(needle)")
        }
        for retired in [
            "Reminders access is off",
            "Show Apple Reminders in Inbox",
            "Cadence can display active reminders and mark them complete here.",
            "Allow Cadence in Privacy & Security to show your active reminders.",
        ] {
            #expect(
                !section.contains(retired),
                "macOS's Inbox hand-writes \"\(retired)\" again, beside four surfaces reading the shared copy"
            )
        }
    }

    // MARK: - T-265: a refusal that cannot prompt records itself

    /// **The plan, as a value.** `.notDetermined` is the only status a prompt can come from;
    /// everything else either already has access or cannot be asked.
    @Test func onlyNotDeterminedCanPromptAndEveryOtherRefusalSaysWhat() {
        #expect(RemindersAccessRequestPlan.forStatus(.fullAccess) == .alreadyAuthorized)
        #expect(RemindersAccessRequestPlan.forStatus(.notDetermined) == .prompt)
        #expect(RemindersAccessRequestPlan.forStatus(.denied) == .cannotAsk(recordsDenial: true))
        #expect(RemindersAccessRequestPlan.forStatus(.restricted) == .cannotAsk(recordsDenial: false))

        // Neither of the two non-refusals records anything.
        #expect(!RemindersAccessRequestPlan.alreadyAuthorized.recordsDenial)
        #expect(!RemindersAccessRequestPlan.prompt.recordsDenial)
    }

    /// **T-265's actual hazard, named.** `RemindersConnectionState.resolve(status:)` folds every
    /// status it does not recognise through `default` into `.notDetermined`, which offers an
    /// **Allow Access** button. `requestAccess()`'s pre-prompt exit is what such a tap reaches, and
    /// it used to return `false` with no bookkeeping at all — so the button stayed, and stayed
    /// dead, for the rest of the launch. `deniedInThisSession` is the only thing that can take it
    /// away before a relaunch, so every status that offers the button must either prompt or record.
    ///
    /// `.writeOnly` is the one such value today. EventKit does not return it for reminders, which
    /// is why this was filed as latent rather than live — and is exactly why a test states the rule
    /// over every status rather than over the one that happens to reach it.
    /// `@MainActor` because `RemindersConnectionState` and `RemindersAccessAction` carry the
    /// app's default main-actor isolation, and their synthesized `Equatable` conformances cannot be
    /// used from a nonisolated context. `RemindersConnectionStateTests` is annotated whole for the
    /// same reason; only the tests here that compare one need it.
    @MainActor
    @Test func noStatusOffersAnAllowButtonThatNeitherPromptsNorRecordsARefusal() {
        // The fold that creates the hazard, stated so this test cannot quietly stop covering it.
        #expect(RemindersConnectionState.resolve(status: .writeOnly) == .notDetermined)
        #expect(RemindersConnectionState.resolve(status: .writeOnly).accessAction == .requestAccess)
        #expect(
            RemindersAccessRequestPlan.forStatus(.writeOnly).recordsDenial,
            "a .writeOnly status offers Allow Access and takes an arm that records nothing: the button is dead for the launch"
        )

        var offered = 0
        for raw in 0...8 {
            guard let status = EKAuthorizationStatus(rawValue: raw) else { continue }
            let plan = RemindersAccessRequestPlan.forStatus(status)
            guard RemindersConnectionState.resolve(status: status).accessAction == .requestAccess else { continue }
            offered += 1
            #expect(
                plan == .prompt || plan.recordsDenial,
                "status \(raw) offers Allow Access, cannot prompt, and records no denial"
            )
        }
        #expect(offered >= 2, "the sweep found \(offered) statuses offering Allow Access and is not doing its job")
    }

    /// **And a restriction is still not a denial the user can undo.** [[T-256]] split the two, and
    /// recording a session denial here would put it back: `deniedInThisSession` is only ever
    /// cleared by a real grant, so a restriction lifted mid-session would read as a denial pointing
    /// the user at a System Settings switch they never touched.
    /// `@MainActor` because `RemindersConnectionState` and `RemindersAccessAction` carry the
    /// app's default main-actor isolation, and their synthesized `Equatable` conformances cannot be
    /// used from a nonisolated context. `RemindersConnectionStateTests` is annotated whole for the
    /// same reason; only the tests here that compare one need it.
    @MainActor
    @Test func aRestrictionIsNotARefusalThisLaunchRemembers() {
        #expect(RemindersAccessRequestPlan.forStatus(.restricted) == .cannotAsk(recordsDenial: false))
        #expect(
            !RemindersAccessRequestPlan.forStatus(.restricted).recordsDenial,
            "a device restriction was recorded as a denial this launch has to remember"
        )
        // It needs no record: restricted is read live and outranks the denial flag either way.
        #expect(RemindersConnectionState.resolve(isAuthorized: false, isDenied: true, isRestricted: true) == .restricted)
        #expect(RemindersConnectionState.resolve(status: .restricted).accessAction == nil)
    }

    /// **The wiring, scoped to the one method.** `requestAccess()` had two exits returning `false`
    /// and only the post-prompt one recorded the refusal; the count below is what stops a third
    /// appearing. There is no bare `return false` left in the method at all — the bookkeeping
    /// cannot be skipped by adding one.
    @Test func requestAccessAnswersFalseOnlyThroughItsOneRefusal() throws {
        let source = try strippingComments(sourceFile("Cadence/Services/CadenceRemindersManager.swift"))
        let body = try cadenceFunctionBody("func requestAccess() async -> Bool", in: source)

        #expect(
            body.contains("RemindersAccessRequestPlan.forStatus("),
            "requestAccess decides what a status means without the shared plan again"
        )
        #expect(
            !body.contains("status == .notDetermined"),
            "requestAccess re-spells its pre-prompt exit as a hand-written guard again"
        )
        #expect(
            body.components(separatedBy: "return false").count - 1 == 0,
            "requestAccess has a bare `return false` that skips the denial bookkeeping"
        )
        #expect(
            body.components(separatedBy: "refuse(recordingDenial:").count - 1 == 2,
            "requestAccess no longer answers false through exactly its two shared refusals"
        )

        let refusal = try cadenceFunctionBody(
            "private func refuse(recordingDenial recordsDenial: Bool) -> Bool",
            in: source
        )
        #expect(
            refusal.contains("if recordsDenial { deniedInThisSession = true }"),
            "the one refusal stopped recording the denial it was told to record"
        )
        #expect(
            refusal.contains("refreshAuthorizationState()"),
            "the one refusal stopped re-deriving after recording"
        )
        #expect(refusal.contains("return false"), "the one refusal stopped answering false")
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

    // MARK: - The row's state transition

    /// **T-268, and the primary guard for T-255's bug.** The row's reconcile is a value now, so
    /// this asserts a *state* rather than the presence of a call name.
    ///
    /// The mutation this replaces a scan with: both rows called
    /// `apply(AppleReminderCompletionResolution.resolve(onComplete(id)))`, and rewriting that to
    /// `_ = AppleReminderCompletionResolution.resolve(onComplete(id))` restored the shipped bug on
    /// both platforms with 116/116 still passing — because every string the old assertions looked
    /// for (`revertsTick`, `failureNotice = resolution.notice`, the call name itself) survived
    /// inside a function nothing called any more. A longer string would have killed that exact
    /// mutation and nothing weaker. This states the behaviour instead.
    @Test func aRefusedWriteTakesTheTickBackAndSaysWhy() {
        let ticked = AppleReminderRowState.attempting
        #expect(ticked.isCompleting, "the tapped row is not drawn ticked")
        #expect(ticked.failureNotice == nil, "a new attempt carries the previous attempt's sentence")

        for outcome: AppleReminderCompletionOutcome in [.reminderUnavailable, .listIsReadOnly, .saveFailed] {
            let next = ticked.applying(outcome)
            #expect(
                next.isCompleting == false,
                "\(outcome) left the row struck through over a reminder Apple Reminders still has open"
            )
            #expect(
                next.failureNotice == AppleReminderCompletionResolution.resolve(outcome).notice,
                "\(outcome) reverted the tick without the shared policy's sentence"
            )
            #expect(next.failureNotice?.isEmpty == false, "\(outcome) reverts with no explanation at all")
        }

        // The one refusal that reverts silently: the section around the row has already replaced
        // every row with its access card.
        let denied = ticked.applying(.notAuthorized)
        #expect(denied == AppleReminderRowState(isCompleting: false, failureNotice: nil))

        // The only outcome that may leave the tick standing.
        #expect(ticked.applying(.completed) == ticked, "a saved completion put its own tick back")
    }

    /// A row that failed once and is tapped again must not show the old sentence under a new
    /// attempt, and must not keep it after a second attempt succeeds.
    @Test func aStaleNoticeDoesNotOutliveTheAttemptItDescribes() {
        let failed = AppleReminderRowState.attempting.applying(.saveFailed)
        #expect(failed.failureNotice != nil)

        #expect(AppleReminderRowState.attempting.failureNotice == nil, "re-tapping kept the old sentence")
        #expect(AppleReminderRowState.idle == AppleReminderRowState(isCompleting: false, failureNotice: nil))

        // Two different refusals in a row replace the sentence rather than accumulating one.
        let thenUnavailable = AppleReminderRowState.attempting.applying(.reminderUnavailable)
        #expect(thenUnavailable.failureNotice != failed.failureNotice)
    }

    /// **The cheap backstop, not the guard.** The test above fails when the reducer's policy
    /// regresses; it can only fail when a *row* stops reconciling if the row's state genuinely
    /// flows through the reducer. This pins that it does — one assignment through
    /// `AppleReminderRowState` per row, and neither row reaching past it to the policy underneath.
    ///
    /// The assignment form is what is counted, deliberately. `_ = rowState.applying(outcome)` — the
    /// discarded-result shape of the original mutation — fails here, and there is no longer a
    /// private `apply` helper for a mutation to leave defined and unreachable.
    ///
    /// iOS has no other tool available (`Cadence/iOS/` is invisible to a macOS-built test target)
    /// and macOS's row is `private` inside a view file, so neither row is referenceable.
    @Test func bothReminderRowsRunTheirStateThroughTheSharedReducer() throws {
        let rowFiles = [
            "Cadence/macOS/Views/InboxSupportViews.swift",
            "Cadence/iOS/iOSInboxRemindersSection.swift",
        ]

        try expectOccurrences(
            of: "rowState = rowState.applying(",
            at: Dictionary(uniqueKeysWithValues: rowFiles.map { ($0, 1) })
        )

        for path in rowFiles {
            let source = try strippingComments(sourceFile(path))
            #expect(
                source.contains("let onComplete: (String) -> AppleReminderCompletionOutcome"),
                "\(path) takes a completion handler that cannot report a failure again"
            )
            #expect(
                source.contains("@State private var rowState = AppleReminderRowState.idle"),
                "\(path) stopped holding its tick and notice as the shared state value"
            )
            #expect(
                source.contains("rowState = .attempting"),
                "\(path) stopped entering the shared attempting state when the circle is tapped"
            )
            // The policy is reached through the reducer and nowhere else, so a row cannot grow a
            // second reading of it that the value test above would not cover.
            #expect(
                source.contains("AppleReminderCompletionResolution") == false,
                "\(path) reaches past AppleReminderRowState to the resolution policy itself"
            )
        }
    }

    // MARK: - The manager reconciles its own view

    /// Which reconcile each outcome asks for, stated as a value. Two of the five mean the row is
    /// looking at something that is no longer true.
    @Test func onlyALostGrantOrAStaleFetchAsksTheManagerToReconcile() {
        #expect(AppleReminderCompletionReconcile.forOutcome(.notAuthorized) == .refreshAuthorization)
        #expect(AppleReminderCompletionReconcile.forOutcome(.reminderUnavailable) == .reload)
        #expect(AppleReminderCompletionReconcile.forOutcome(.saveFailed) == .reload)
        #expect(AppleReminderCompletionReconcile.forOutcome(.listIsReadOnly) == .none)
        #expect(AppleReminderCompletionReconcile.forOutcome(.completed) == .none)
    }

    /// **T-268's third gap.** Deleting `refreshAuthorizationState()` from the `.notAuthorized`
    /// branch — or `reload()` from `.reminderUnavailable` — used to pass everything, because on a
    /// host with no Reminders grant a re-derive of `isAuthorized` from `false` to `false` changes
    /// nothing a test can see. `reconcileLedger` counts the two calls *inside the methods
    /// themselves*, so a dispatcher that chooses correctly and then does nothing fails here.
    ///
    /// Host-agnostic: `.refreshAuthorization` on an authorized host also reloads, so that arm
    /// asserts only its own counter.
    @MainActor
    @Test func theManagerPerformsTheReconcileEachOutcomeMapsTo() {
        let manager = RemindersManager.shared

        for outcome: AppleReminderCompletionOutcome in [.completed, .notAuthorized, .reminderUnavailable, .listIsReadOnly, .saveFailed] {
            let before = manager.reconcileLedger
            let performed = manager.reconcile(after: outcome)
            let after = manager.reconcileLedger

            #expect(performed == AppleReminderCompletionReconcile.forOutcome(outcome))

            switch performed {
            case .refreshAuthorization:
                #expect(
                    after.authorizationRefreshes == before.authorizationRefreshes + 1,
                    "\(outcome) reported a re-derive of authorization it never performed"
                )
            case .reload:
                #expect(
                    after.reloadRequests == before.reloadRequests + 1,
                    "\(outcome) reported a refetch it never performed"
                )
                #expect(
                    after.authorizationRefreshes == before.authorizationRefreshes,
                    "\(outcome) re-derived authorization as well as refetching"
                )
            case .none:
                #expect(after == before, "\(outcome) reconciled something it said it would not")
            }
        }
    }

    /// And the wiring: the real `completeReminder(id:)` on an identifier no store can hold has to
    /// run that reconcile, not merely return the outcome. Refused either way — `.notAuthorized`
    /// without a grant, `.reminderUnavailable` with one — so neither arm is `.none`.
    @MainActor
    @Test func aRefusedCompletionReconcilesBeforeItAnswers() {
        let manager = RemindersManager.shared
        let before = manager.reconcileLedger
        let outcome = manager.completeReminder(id: "cadence-t268-no-such-reminder")
        let after = manager.reconcileLedger

        #expect(outcome != .completed, "a reminder that does not exist reported a successful save")

        switch AppleReminderCompletionReconcile.forOutcome(outcome) {
        case .refreshAuthorization:
            #expect(
                after.authorizationRefreshes > before.authorizationRefreshes,
                "a completion refused for lost access left the manager showing rows it may not read"
            )
        case .reload:
            #expect(
                after.reloadRequests > before.reloadRequests,
                "a completion refused as unresolvable left the stale row on screen"
            )
        case .none:
            Issue.record("\(outcome) is not a refusal a missing identifier can produce")
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
    @Test func theSourceScanActuallyReachesBothPlatformsSourceInInboxRemindersSurface() throws {
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
/// Fails unless `text` occurs exactly `count` times as live code in each listed file. Unlike
/// `expectCallSites` this does not append `(`, so it can pin an assignment.
private func expectOccurrences(
    of text: String,
    at files: [String: Int],
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    for (path, expected) in files {
        let code = try strippingComments(sourceFile(path))
        let actual = code.components(separatedBy: text).count - 1
        #expect(
            actual == expected,
            "\(path) contains \(text) \(actual) times, expected \(expected)",
            sourceLocation: sourceLocation
        )
    }
}

/// Every file under `Cadence/` whose **live code** contains `text` literally, sorted. Unlike
/// `filesMentioning` this takes no word boundary, so it can pin a dotted call like
/// `RemindersConnectionState.resolve(` without `.` being read as a regex wildcard.
private func filesContaining(_ text: String) throws -> [String] {
    try swiftFiles(under: "Cadence")
        .filter { try strippingComments(sourceFile($0)).contains(text) }
        .sorted()
}

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
