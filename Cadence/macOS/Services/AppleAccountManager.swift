#if os(macOS)
import AppKit
import AuthenticationServices
import Foundation
import Observation
import Security

struct AppleAccountProfile: Equatable {
    var userIdentifier: String
    var email: String
    var givenName: String
    var familyName: String
    var signedInAt: Date

    var displayName: String {
        let fullName = [givenName, familyName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !fullName.isEmpty { return fullName }
        if !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return email }
        return "Apple Account"
    }
}

protocol AppleAccountStorage {
    func loadProfile() -> AppleAccountProfile?
    func saveProfile(_ profile: AppleAccountProfile)
    func clearProfile()
}

struct AppleAccountDefaultsStorage: AppleAccountStorage {
    private enum Key {
        static let userIdentifier = "appleAccount.userIdentifier"
        static let email = "appleAccount.email"
        static let givenName = "appleAccount.givenName"
        static let familyName = "appleAccount.familyName"
        static let signedInAt = "appleAccount.signedInAt"
    }

    var defaults: UserDefaults = .standard

    func loadProfile() -> AppleAccountProfile? {
        guard let userIdentifier = defaults.string(forKey: Key.userIdentifier),
              !userIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return AppleAccountProfile(
            userIdentifier: userIdentifier,
            email: defaults.string(forKey: Key.email) ?? "",
            givenName: defaults.string(forKey: Key.givenName) ?? "",
            familyName: defaults.string(forKey: Key.familyName) ?? "",
            signedInAt: defaults.object(forKey: Key.signedInAt) as? Date ?? Date()
        )
    }

    func saveProfile(_ profile: AppleAccountProfile) {
        defaults.set(profile.userIdentifier, forKey: Key.userIdentifier)
        defaults.set(profile.email, forKey: Key.email)
        defaults.set(profile.givenName, forKey: Key.givenName)
        defaults.set(profile.familyName, forKey: Key.familyName)
        defaults.set(profile.signedInAt, forKey: Key.signedInAt)
    }

    func clearProfile() {
        defaults.removeObject(forKey: Key.userIdentifier)
        defaults.removeObject(forKey: Key.email)
        defaults.removeObject(forKey: Key.givenName)
        defaults.removeObject(forKey: Key.familyName)
        defaults.removeObject(forKey: Key.signedInAt)
    }
}

enum AppleAccountProfileMerge {
    static func merged(
        existing: AppleAccountProfile?,
        userIdentifier: String,
        email: String?,
        givenName: String?,
        familyName: String?,
        signedInAt: Date
    ) -> AppleAccountProfile {
        AppleAccountProfile(
            userIdentifier: userIdentifier,
            email: firstNonEmpty(email, existing?.email),
            givenName: firstNonEmpty(givenName, existing?.givenName),
            familyName: firstNonEmpty(familyName, existing?.familyName),
            signedInAt: signedInAt
        )
    }

    private static func firstNonEmpty(_ primary: String?, _ fallback: String?) -> String {
        let primaryTrimmed = primary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !primaryTrimmed.isEmpty { return primaryTrimmed }
        return fallback?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

enum AppleAccountCredentialStatus: Equatable {
    case unchecked
    case authorized
    case revoked
    case notFound
    case transferred
    case unavailable

    var title: String {
        switch self {
        case .unchecked: return "Not checked"
        case .authorized: return "Authorized"
        case .revoked: return "Revoked"
        case .notFound: return "Not found"
        case .transferred: return "Transferred"
        case .unavailable: return "Signed out"
        }
    }
}

struct AppleSignInEntitlementStatus: Equatable {
    var values: [String]

    var isConfigured: Bool {
        values.contains("Default")
    }

    var title: String {
        isConfigured ? "Available" : "Missing"
    }

    var detail: String {
        values.isEmpty ? "No Sign in with Apple entitlement found." : values.joined(separator: ", ")
    }

    static func current() -> AppleSignInEntitlementStatus {
        guard let task = SecTaskCreateFromSelf(kCFAllocatorDefault),
              let value = SecTaskCopyValueForEntitlement(
                task,
                "com.apple.developer.applesignin" as CFString,
                nil
              ) else {
            return AppleSignInEntitlementStatus(values: [])
        }
        return parsed(from: value)
    }

    static func parsed(from value: Any?) -> AppleSignInEntitlementStatus {
        if let values = value as? [String] {
            return AppleSignInEntitlementStatus(values: values)
        }
        if let value = value as? String {
            return AppleSignInEntitlementStatus(values: [value])
        }
        return AppleSignInEntitlementStatus(values: [])
    }
}

@Observable
final class AppleAccountManager: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    static let shared = AppleAccountManager()

    private let storage: AppleAccountStorage

    var profile: AppleAccountProfile?
    var statusMessage: String?
    var isAuthorizing = false
    var credentialStatus: AppleAccountCredentialStatus
    var entitlementStatus: AppleSignInEntitlementStatus

    var isSignedIn: Bool { profile != nil }

    init(storage: AppleAccountStorage = AppleAccountDefaultsStorage()) {
        let loadedProfile = storage.loadProfile()
        self.storage = storage
        self.profile = loadedProfile
        self.credentialStatus = loadedProfile == nil ? .unavailable : .unchecked
        self.entitlementStatus = AppleSignInEntitlementStatus.current()
        super.init()
    }

    func signIn() {
        statusMessage = nil
        isAuthorizing = true

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    func signOut() {
        storage.clearProfile()
        profile = nil
        credentialStatus = .unavailable
        statusMessage = "Signed out."
    }

    func refreshCredentialState() {
        entitlementStatus = AppleSignInEntitlementStatus.current()
        guard let userIdentifier = profile?.userIdentifier else {
            credentialStatus = .unavailable
            return
        }
        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userIdentifier) { [weak self] state, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                switch state {
                case .authorized:
                    self.credentialStatus = .authorized
                case .revoked:
                    self.credentialStatus = .revoked
                    self.storage.clearProfile()
                    self.profile = nil
                    self.statusMessage = "Apple account access is no longer active."
                case .notFound:
                    self.credentialStatus = .notFound
                    self.storage.clearProfile()
                    self.profile = nil
                    self.statusMessage = "Apple account access is no longer active."
                case .transferred:
                    self.credentialStatus = .transferred
                    self.statusMessage = "Apple account transfer is in progress."
                @unknown default:
                    break
                }
            }
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        isAuthorizing = false
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            statusMessage = "Apple sign-in did not return an Apple ID credential."
            return
        }

        let merged = AppleAccountProfileMerge.merged(
            existing: profile,
            userIdentifier: credential.user,
            email: credential.email,
            givenName: credential.fullName?.givenName,
            familyName: credential.fullName?.familyName,
            signedInAt: Date()
        )
        storage.saveProfile(merged)
        profile = merged
        credentialStatus = .authorized
        statusMessage = "Signed in with Apple."
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        isAuthorizing = false
        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
            statusMessage = "Sign in was canceled."
        } else {
            statusMessage = "Could not sign in with Apple."
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first ?? NSWindow()
    }
}
#endif
