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

/// One of the reference links a Settings → About screen offers: the public privacy policy, and the
/// public support page.
///
/// A value type rather than two hand-written button call sites per platform. Both platforms render
/// the same pair, and everything about the pair except the button chrome is one decision — which
/// links exist, what each is called, which glyph it carries, and what to say when its URL is
/// missing. Adding a third link is one entry here rather than one entry per About screen, and the
/// titles exist in exactly one place, so the two screens cannot come to disagree about the wording
/// of a link that points at the same page.
///
/// Deliberately outside any `#if`: `Cadence/iOS/` is invisible to the macOS-built test target, so
/// the list itself has to live somewhere both the iOS view and `CadenceTests` can see.
struct CadenceAppReferenceLink: Identifiable, Equatable {
    let id: String
    let title: String
    let systemImage: String
    let url: URL?
    let missingMessage: String

    static let privacyPolicy = CadenceAppReferenceLink(
        id: "privacy-policy",
        title: "Privacy Policy",
        systemImage: "lock.shield.fill",
        url: AppStoreReviewReadiness.privacyPolicyURL,
        missingMessage: AppStoreReviewReadiness.privacyPolicyMissingMessage
    )

    static let support = CadenceAppReferenceLink(
        id: "support",
        title: "Support",
        systemImage: "questionmark.circle.fill",
        url: AppStoreReviewReadiness.supportURL,
        missingMessage: AppStoreReviewReadiness.supportURLMissingMessage
    )

    static let all: [CadenceAppReferenceLink] = [privacyPolicy, support]

    /// The section label above them, shared for the same reason the list is.
    ///
    /// It reads `Links` rather than iOS's old `Review Links`, over a card that no longer carries a
    /// glyph tile, a `Privacy and Support` heading, or the sentence `Use these during TestFlight
    /// and App Review checks.` — App Review vocabulary in a shipped build, and a heading that
    /// restated the two buttons underneath it, which is the page-header `subtitle` mistake one
    /// card down.
    static let sectionTitle = "Links"
}
