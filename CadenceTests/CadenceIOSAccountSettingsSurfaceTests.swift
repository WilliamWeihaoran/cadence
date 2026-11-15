import Foundation
import Testing
@testable import Cadence

/// **[[T-8736]]: Settings → Account on iPhone and iPad — sign in, sign out, delete.**
///
/// Owner decision 2026-10-31, option (a): the full Account surface comes to iOS, partly because
/// App Store rule 5.1.1(v) wants in-app deletion wherever an account can be created. The Mac's
/// card was the only one because `AppleAccountManager` sat in `Cadence/macOS/Services/` inside
/// `#if os(macOS)`; the iOS entitlement was already declared.
///
/// Read as source for the reason `CadencePrivacyDataResetSurfaceTests` gives: `Cadence/iOS/` is
/// inside `#if os(iOS)`, and this target builds for macOS, so the iOS half has no symbol to call.
/// The shared halves — the manager, the copy, the layout — are referenced directly.
@MainActor
struct CadenceIOSAccountSettingsSurfaceTests {

    private func code(_ path: String) throws -> String {
        CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
    }

    /// The manager is shared code now, and only its two hardware-bound members branch.
    @Test func theAppleAccountManagerIsSharedAndBranchesOnlyWhereThePlatformForcesIt() throws {
        let manager = try code("Cadence/Services/AppleAccountManager.swift")
        #expect(manager.contains("final class AppleAccountManager"), "non-vacuity: the manager moved or was renamed")
        #expect(
            !manager.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#if os(macOS)"),
            "the manager is a macOS-only file again"
        )
        // Imports (1), the entitlement read (2: `current()` and the stored property, with its init
        // and refresh assignments), and the presentation anchor (1). A new branch has to name the
        // constraint that forces it before this count moves.
        #expect(
            manager.components(separatedBy: "#if os(macOS)").count - 1 == 6,
            "AppleAccountManager grew or lost a platform branch"
        )
        #expect(manager.contains("UIWindow(windowScene:"), "the iOS presentation anchor is gone")
        #expect(manager.contains("NSApp.keyWindow"), "the macOS presentation anchor is gone")
        #expect(
            !FileManager.default.fileExists(atPath: CadenceSourceScan.repositoryRoot()
                .appendingPathComponent("Cadence/macOS/Services/AppleAccountManager.swift").path),
            "a second, macOS-only copy of the manager is back"
        )
    }

    /// Mobile offers the Account category, and the iOS shell draws a screen for it.
    @Test func iOSSettingsDrawsTheAccountSection() throws {
        #expect(CadenceMobileSettingsLayout.categories.contains(.account))
        #expect(!CadenceMobileSettingsLayout.desktopOnly.contains(.account))

        let components = try code("Cadence/iOS/iOSSettingsComponents.swift")
        #expect(components.contains("case .account: self = .account"), "iOSSettingsCategory refuses .account again")
        #expect(components.contains("case .account: return .account"))

        let settings = try code("Cadence/iOS/iOSSettingsView.swift")
        let route = try #require(settings.range(of: "case .account:"), "iOS Settings has no Account route")
        let tail = settings[route.upperBound...]
        let next = tail.range(of: "\n        case ")?.lowerBound ?? tail.endIndex
        let branch = tail[..<next]
        #expect(branch.contains("iOSAccountSettingsSection("), "the Account route draws some other screen")
        // Delete Account deletes nothing on its own: it opens Data Safety, where the shared reset
        // runs behind the typed phrase — the Mac's `onDeleteAccount` does the same.
        #expect(branch.contains("onDeleteAccount: { select(.data) }"), "Delete Account… no longer opens Data Safety")
    }

    /// The section does what the Mac card does, through the same manager and the same words.
    @Test func theIOSAccountSectionSignsInSignsOutAndRoutesToDeletion() throws {
        let section = try code("Cadence/iOS/iOSAccountSettingsSection.swift")
        let body = try #require(
            CadenceSourceScan.declarationBody("struct iOSAccountSettingsSection: View", in: section),
            "the iOS Account section is gone"
        )
        for call in ["appleAccountManager.signIn()", "appleAccountManager.signOut()", "action: onDeleteAccount", "appleAccountManager.refreshCredentialState()"] {
            #expect(body.components(separatedBy: call).count - 1 == 1, "the iOS Account section calls \(call) other than once")
        }
        for copy in ["accountTitle", "signedOutDetail", "signOutTitle", "deleteAccountTitle", "signInTitle(", "signedInLabel(", "credentialStatusTitle"] {
            #expect(body.contains("CadenceAccountSettingsCopy.\(copy)"), "the iOS Account section types its own \(copy)")
        }
        // The Mac card reads the same copy, so the two cannot describe the identity differently.
        let mac = try code("Cadence/macOS/Views/SettingsSectionViews.swift")
        let macBody = try #require(CadenceSourceScan.declarationBody("struct SettingsAccountSection: View", in: mac))
        for copy in ["accountTitle", "signedOutDetail", "signOutTitle", "deleteAccountTitle", "signInTitle(", "credentialStatusTitle", "entitlementStatusTitle"] {
            #expect(macBody.contains("CadenceAccountSettingsCopy.\(copy)"), "the Mac Account card types its own \(copy)")
        }
        #expect(!macBody.contains("Optional identity for Cadence"), "the Mac card types the shared sentence beside the constant")
    }

    /// The manager reaches the iOS environment, or the section and the reset trap at runtime.
    @Test func theIOSRootEnvironmentCarriesTheAppleAccountManager() throws {
        let app = try code("Cadence/CadenceApp.swift")
        let iosBranch = try #require(
            app.range(of: "iOSRootView()").map { start in
                let rest = app[start.upperBound...]
                return String(rest[..<(rest.range(of: "#endif")?.lowerBound ?? rest.endIndex)])
            },
            "non-vacuity: the iOS root branch was not found"
        )
        #expect(iosBranch.contains(".environment(AppleAccountManager.shared)"), "iOS never injects the Apple account manager")
    }

    /// **[[T-17818]].** The entitlement row explains exactly one state — a build without the Sign
    /// in with Apple entitlement — so a configured build draws none, and the raw "Default" value
    /// never reaches a user who can sign in.
    @Test func theEntitlementRowDrawsOnlyForABuildThatLacksTheEntitlement() {
        #expect(AppleSignInEntitlementStatus.parsed(from: ["Default"]).drawsStatusRow == false)
        #expect(AppleSignInEntitlementStatus.parsed(from: "Default").drawsStatusRow == false)
        #expect(AppleSignInEntitlementStatus.parsed(from: nil).drawsStatusRow)
        #expect(AppleSignInEntitlementStatus.parsed(from: ["Other"]).drawsStatusRow)
    }

    /// **[[T-17818]].** Credential Status draws only where the card cannot say it: Revoked and Not
    /// found clear the profile, so the card reads signed-out; Transferred keeps it signed in. The
    /// other three restated the card (or are the instant before the check answers).
    @Test func theCredentialStatusRowDrawsOnlyWhereTheCardCannotSayIt() {
        let drawn: [AppleAccountCredentialStatus] = [.revoked, .notFound, .transferred]
        let hidden: [AppleAccountCredentialStatus] = [.unchecked, .authorized, .unavailable]
        for status in drawn {
            #expect(status.drawsStatusRow, "\(status.title) restates nothing, but no longer draws")
        }
        for status in hidden {
            #expect(status.drawsStatusRow == false, "\(status.title) restates the card above it")
        }
    }

    /// **[[T-17818]].** Both cards read the predicates rather than drawing each row unconditionally,
    /// and each draws its divider only over a row — so a healthy, signed-in-or-out account card is
    /// the identity and its actions alone, on both platforms.
    @Test func bothAccountCardsGateTheirStatusRowsOnThePredicates() throws {
        let mac = try code("Cadence/macOS/Views/SettingsSectionViews.swift")
        let macBody = try #require(CadenceSourceScan.declarationBody("struct SettingsAccountSection: View", in: mac))
        #expect(macBody.contains("let drawsCredentialRow = appleAccountManager.credentialStatus.drawsStatusRow"))
        #expect(macBody.contains("let drawsEntitlementRow = appleAccountManager.entitlementStatus.drawsStatusRow"))
        let macRows = try #require(
            CadenceSourceScan.declarationBody("if drawsCredentialRow || drawsEntitlementRow", in: macBody),
            "the Mac card draws its status block unconditionally again"
        )
        #expect(macRows.contains("CadenceRowDivider()"), "the Mac card's divider left the gated block")
        let outsideRows = macBody.replacingOccurrences(of: macRows, with: "")
        #expect(!outsideRows.contains("CadenceRowDivider()"), "the Mac card draws a divider over no row")
        // Outside the gated block only the helper's own declaration may name it.
        #expect(outsideRows.contains("private func accountDiagnosticRow("), "non-vacuity: the row helper moved")
        #expect(outsideRows.components(separatedBy: "accountDiagnosticRow(").count - 1 == 1, "the Mac card draws a status row outside the gate")
        let credential = try #require(CadenceSourceScan.declarationBody("if drawsCredentialRow", in: macRows))
        let entitlement = try #require(CadenceSourceScan.declarationBody("if drawsEntitlementRow", in: macRows))
        #expect(credential.contains("CadenceAccountSettingsCopy.credentialStatusTitle"), "the Mac Credential Status row is not behind its predicate")
        #expect(entitlement.contains("CadenceAccountSettingsCopy.entitlementStatusTitle"), "the Mac entitlement row is not behind its predicate")

        let ios = try code("Cadence/iOS/iOSAccountSettingsSection.swift")
        let iosBody = try #require(CadenceSourceScan.declarationBody("struct iOSAccountSettingsSection: View", in: ios))
        let iosRow = try #require(
            CadenceSourceScan.declarationBody("if appleAccountManager.credentialStatus.drawsStatusRow", in: iosBody),
            "the iOS Credential Status row draws unconditionally again"
        )
        #expect(iosRow.contains("iOSRowDivider()"), "the iOS divider left the gated block")
        #expect(iosRow.contains("CadenceAccountSettingsCopy.credentialStatusTitle"))
        #expect(iosBody.components(separatedBy: "iOSRowDivider()").count - 1 == 1, "the iOS card draws a divider over no row")
        #expect(iosBody.components(separatedBy: "credentialStatusTitle").count - 1 == 1)
    }

    /// The copy itself, pinned where both platforms read it.
    @Test func theAccountCopyIsTheMacCardsWords() {
        #expect(CadenceAccountSettingsCopy.accountTitle == "Apple Account")
        #expect(CadenceAccountSettingsCopy.signedOutDetail == "Optional identity for Cadence. Local access and iCloud sync do not depend on signing in.")
        #expect(CadenceAccountSettingsCopy.signOutTitle == "Sign Out")
        #expect(CadenceAccountSettingsCopy.deleteAccountTitle == "Delete Account…")
        #expect(CadenceAccountSettingsCopy.signInTitle(isAuthorizing: false) == "Sign in with Apple")
        #expect(CadenceAccountSettingsCopy.signInTitle(isAuthorizing: true) == "Signing In…")
    }
}
