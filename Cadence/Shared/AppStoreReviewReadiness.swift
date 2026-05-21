import Foundation

enum AppStoreReviewReadiness {
    static let privacyPolicyURL = URL(string: "https://williamweihaoran.github.io/cadence/privacy.html")
    static let supportURL = URL(string: "https://williamweihaoran.github.io/cadence/support.html")

    static let privacyPolicyMissingMessage = "Add a public privacy policy URL before submitting to App Review."
    static let supportURLMissingMessage = "Add a public support URL before submitting to App Review."
}
