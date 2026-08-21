import Foundation

enum AppStoreReviewReadiness {
    static let privacyPolicyURL = URL(string: "https://williamweihaoran.github.io/cadence/privacy.html")
    static let supportURL = URL(string: "https://williamweihaoran.github.io/cadence/support.html")

    static let privacyPolicyMissingMessage = "Add a public privacy policy URL before submitting to App Review."
    static let supportURLMissingMessage = "Add a public support URL before submitting to App Review."
}

/// The three strings a Settings → About screen reports about the running build.
///
/// Shared because both platforms' About screens answer the same question, and the answer is a
/// bundle lookup rather than a design decision. It was three computed properties on
/// `iOSSettingsView` while macOS had no About screen at all; a second hand-written copy on the
/// desktop is how the two would come to disagree about which key holds the build number.
enum CadenceAppBuildIdentity {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    static var bundleID: String {
        Bundle.main.bundleIdentifier ?? "Unknown"
    }
}
