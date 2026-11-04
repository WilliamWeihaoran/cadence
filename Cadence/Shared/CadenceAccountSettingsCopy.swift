import Foundation

/// Every word the Settings → Account card draws, read by both platforms' sections ([[T-8736]]).
///
/// The card was the Mac's alone (`SettingsAccountSection`) until iOS got the same section
/// (`iOSAccountSettingsSection`). The two views differ in chrome — `SettingsCard` and
/// `CadenceActionButton` on the Mac, `iOSSettingsCard` and `iOSActionButton` on iPhone and iPad —
/// and in nothing they say, so the sentences live here where a macOS-built test can read them and
/// neither view can drift into describing the identity differently.
enum CadenceAccountSettingsCopy {
    /// The card's title while no one is signed in, the section label above it on iOS, and the name
    /// `AppleAccountProfile.displayName` falls back to when Apple returned no name or email.
    static let accountTitle = "Apple Account"

    /// Why signing in is optional. True on both platforms: neither the local store nor the private
    /// iCloud database is keyed to the Sign in with Apple identity.
    static let signedOutDetail = "Optional identity for Cadence. Local access and iCloud sync do not depend on signing in."

    static let signOutTitle = "Sign Out"

    /// Opens Settings → Data Safety, where the one shared reset runs and clears this profile with
    /// the data ([[T-8736]]); the button itself deletes nothing.
    static let deleteAccountTitle = "Delete Account…"

    static func signInTitle(isAuthorizing: Bool) -> String {
        isAuthorizing ? "Signing In…" : "Sign in with Apple"
    }

    static let credentialStatusTitle = "Credential Status"
    static let entitlementStatusTitle = "Apple Sign-In Entitlement"

    /// "Signed in Oct 20" this year, "Signed in Oct 20, 2025" from another ([[T-6433]]): the
    /// sign-in date persists indefinitely, so a bare month and day made a sign-in from last year
    /// read like last week. Same rule as `DateFormatters.absoluteDay` ([[T-6252]]).
    static func signedInLabel(_ signedInAt: Date, relativeTo referenceDate: Date = Date()) -> String {
        "Signed in \(DateFormatters.absoluteDay(signedInAt, relativeTo: referenceDate))"
    }
}
