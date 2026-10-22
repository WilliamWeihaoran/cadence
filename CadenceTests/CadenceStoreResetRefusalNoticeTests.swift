import Foundation
import Testing
@testable import Cadence

/// **[[T-3021]]: a refused `CADENCE_RESET_STORE` now says so on screen, not only in a log.**
///
/// [[T-3014]] made the launch reset refuse itself when the launch is not redirected to a throwaway
/// store directory, because the directory it would remove is the signed-in person's own store, its
/// Recovery store and every local backup. The refusal was recorded as one `Logger.error` and
/// nothing else — and nobody reads that log in the Xcode-debug-scheme case the guard was written
/// for, so the person who ticked the variable expecting a clean slate saw a full store with no
/// explanation, unable to tell a refusal from a reset that silently did nothing.
///
/// The owner's answer (2026-10-22) was to raise a non-blocking `startupIssue`, accepting the stated
/// cost: a user-visible surface on a developer-only variable.
///
/// **What is actually worth pinning here is the precedence, not the string.** There is one banner
/// and one Settings sync card, both fed from `PersistenceController.startupIssue`, and the refusal
/// arrives *first* — `resetStoreDirectoryIfRequested()` runs before any container is opened, and
/// every later writer of the slot overwrites it unconditionally. An unredirected launch that sets
/// the variable is, in practice, Xcode's Run button, and a development-signed debug build records
/// `.developmentBuild` from `makeContainer()` a few statements later. A single slot therefore hides
/// the refusal in the one case that motivated showing it, and promoting the refusal over that kind
/// would make `disablesCloudSync` false on a launch where sync really is off. Carrying both — the
/// claimant's `kind`, the refusal's sentence — is the only arrangement that loses neither.
@MainActor
struct CadenceStoreResetRefusalNoticeTests {

    private static let refusal = "CADENCE_RESET_STORE was set, and Cadence refused to act on it."

    private static let developmentBuild = CadenceStartupIssue(
        kind: .developmentBuild,
        message: "Cadence opened your store with iCloud sync off."
    )

    // MARK: - The one slot, filled from two halves

    /// Nothing else failed, so the refusal is the whole notice and gets to name its own kind.
    @Test func aRefusedResetIsTheWholeNoticeWhenNothingElseFailed() throws {
        let issue = try #require(
            PersistenceController.resolvedStartupIssue(recorded: nil, refusedStoreReset: Self.refusal)
        )

        #expect(issue.kind == .storeResetRefused)
        #expect(issue.message == Self.refusal)
    }

    /// The claimant keeps its `kind` and the refusal still reaches the reader.
    ///
    /// `.developmentBuild` is the specific co-occurrence this ticket turns on, and the `kind`
    /// assertion is the load-bearing one: `CadenceSyncHealth.resolve` renders a sync card only for
    /// a kind whose `disablesCloudSync` is true, so a refusal that *replaced* this one would take
    /// the "this device is not syncing" news off both surfaces on a launch where it is true.
    @Test func aRefusedResetRidesAlongsideTheIssueThatClaimedTheSlot() throws {
        let issue = try #require(
            PersistenceController.resolvedStartupIssue(
                recorded: Self.developmentBuild,
                refusedStoreReset: Self.refusal
            )
        )

        #expect(issue.kind == .developmentBuild, "the refusal demoted a store-level kind")
        #expect(issue.message.contains(Self.developmentBuild.message), "the claimant's own message was dropped")
        #expect(issue.message.contains(Self.refusal), "the refusal is invisible behind the kind that claimed the slot")
        #expect(issue.kind.disablesCloudSync, "a launch with sync off stopped saying so")

        let health = CadenceSyncHealth.resolve(
            startupIssue: issue,
            account: .available,
            pushRegistration: .registered
        )
        #expect(health.level == .notSyncing)
    }

    /// A launch that asked for nothing is left exactly as it was — including the empty case, which
    /// is every ordinary launch of this app.
    @Test func nothingIsAddedWhenTheResetWasNotRefused() {
        #expect(PersistenceController.resolvedStartupIssue(recorded: nil, refusedStoreReset: nil) == nil)
        #expect(
            PersistenceController.resolvedStartupIssue(
                recorded: Self.developmentBuild,
                refusedStoreReset: nil
            ) == Self.developmentBuild
        )
    }

    // MARK: - What the new kind promises

    /// Non-blocking, and not a store-level issue: nothing failed, nothing was deleted, and the
    /// store on screen is the person's own in its usual place. Each of the three properties is a
    /// different reader — the sync card, the quit warning, and Settings → Export.
    @Test func theRefusalIsAdvisoryAndLeavesEveryStoreLevelPropertyAlone() {
        #expect(CadenceStartupIssueKind.storeResetRefused.disablesCloudSync == false)
        #expect(CadenceStartupIssueKind.storeResetRefused.losesDataOnQuit == false)
        #expect(CadenceStartupIssueKind.storeResetRefused.theOpenStoreIsNotTheUsersData == false)

        let issue = CadenceStartupIssue(kind: .storeResetRefused, message: Self.refusal)
        #expect(issue.bannerTone == .caution)

        // The sync card must not react to it at all: the store it sits over is still mirroring.
        let health = CadenceSyncHealth.resolve(
            startupIssue: issue,
            account: .available,
            pushRegistration: .registered
        )
        #expect(health.level == .syncing)
    }

    /// The copy has one job beyond naming the refusal: say what *would* have worked. A banner that
    /// reports a refusal and stops leaves the reader as stuck as the silence did.
    @Test func theCopyNamesTheVariableAndThePreconditionItMissed() {
        let issue = CadenceStartupIssue(kind: .storeResetRefused, message: Self.refusal)

        #expect(issue.bannerTitle == "Store Was Not Reset")
        #expect(issue.bannerDetail.contains(Self.refusal), "the recorded message is not in the detail")
        #expect(
            issue.bannerDetail.contains("CADENCE_UI_TEST_STORE_ID"),
            "the detail does not say what would have made the reset run"
        )
        #expect(
            issue.bannerDetail.contains("Nothing was deleted"),
            "the detail does not say the store is untouched, which is the first thing a reader asks"
        )

        let collapsed = CadenceStartupIssueBannerModel(issue: issue, isCollapsed: true)
        #expect(collapsed.collapsedTitle == "Store Not Reset")
        #expect(collapsed.detail == nil)
    }

    // MARK: - The wiring, which no unit test can reach through `init()`

    /// `resetStoreDirectoryIfRequested()` is `private` and decides off a process-wide environment
    /// variable, so the on-screen half is pinned in source the same way
    /// `CadenceUITestStoreDirectoryTests` pins the refusal itself.
    @Test func theLaunchRefusalIsRaisedOnScreenAndNotOnlyLogged() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Services/PersistenceController.swift")
        )
        let body = try #require(
            CadenceSourceScan.declarationBody("func resetStoreDirectoryIfRequested()", in: source),
            "PersistenceController's launch reset was renamed"
        )

        #expect(body.contains("resetLogger.error("), "the log went away with the banner (T-3014)")
        #expect(
            body.contains("refusedStoreResetMessage ="),
            "the refusal is logged and nothing else again, which is the whole of T-3021"
        )

        // And the slot is read through the resolver, not around it: a view reading the stored half
        // directly would see the refusal only when nothing else claimed the slot.
        let resolved = try #require(
            CadenceSourceScan.declarationBody("static var startupIssue: CadenceStartupIssue?", in: source),
            "the startupIssue slot stopped being computed"
        )
        #expect(resolved.contains("resolvedStartupIssue(recorded:"))
    }
}
