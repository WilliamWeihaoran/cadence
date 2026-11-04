import AuthenticationServices
import Foundation
import Observation
import Security
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// One manager for both platforms ([[T-8736]]). It sat under `Cadence/macOS/Services/` inside
// `#if os(macOS)` while the iOS target already declared `com.apple.developer.applesignin` in
// `Cadence-iOS.entitlements`, so the "macOS-only" account surface was a file location, not a
// platform constraint ([[T-8201]]). Two members still differ, and each names the constraint that
// forces it beside it: the presentation anchor (an `NSWindow` on the Mac, a `UIWindow` on iPhone
// and iPad, because `ASPresentationAnchor` is that platform's window type) and the entitlement
// read (the iOS SDK ships no `SecTask`, so a process there cannot read its own entitlements).

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
        return CadenceAccountSettingsCopy.accountTitle
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

    var defaults: UserDefaults = CadenceDefaults.store

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

    /// macOS only, because the read is `SecTaskCopyValueForEntitlement` and the iOS and iPadOS
    /// SDKs do not ship `SecTask.h` at all: a process there has no public API for reading its own
    /// entitlements, so iOS draws no entitlement row rather than one that could only guess.
    #if os(macOS)
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
    #endif

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
    #if os(macOS)
    /// macOS only: see `AppleSignInEntitlementStatus.current()` for why iOS cannot read it.
    var entitlementStatus: AppleSignInEntitlementStatus
    #endif

    var isSignedIn: Bool { profile != nil }

    init(storage: AppleAccountStorage = AppleAccountDefaultsStorage()) {
        let loadedProfile = storage.loadProfile()
        self.storage = storage
        self.profile = loadedProfile
        self.credentialStatus = loadedProfile == nil ? .unavailable : .unchecked
        #if os(macOS)
        self.entitlementStatus = AppleSignInEntitlementStatus.current()
        #endif
        super.init()
    }

    func signIn() {
        statusMessage = nil
        #if os(iOS)
        // The anchor below is a window on a connected scene, and iOS has no window without one.
        // A tap reaches here only from a drawn button, so this refusal is a guard, not a path.
        guard !Self.windowScenes.isEmpty else {
            statusMessage = "Could not sign in with Apple."
            return
        }
        #endif
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
        #if os(macOS)
        entitlementStatus = AppleSignInEntitlementStatus.current()
        #endif
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

    /// The one presentation difference, and it is the platform's window type rather than a
    /// choice: `ASPresentationAnchor` is `NSWindow` on macOS and `UIWindow` on iOS and iPadOS, and
    /// the system sheet attaches to whichever window is key on that platform.
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        #if os(macOS)
        NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first ?? NSWindow()
        #else
        let scenes = Self.windowScenes
        let windows = scenes.flatMap(\.windows)
        if let window = windows.first(where: \.isKeyWindow) ?? windows.first {
            return window
        }
        // A scene with no window yet still takes one; `signIn()` refuses to start a request
        // while no scene is connected, so the last line is unreachable.
        guard let scene = scenes.first else {
            preconditionFailure("signIn() starts a request only while a window scene is connected")
        }
        return UIWindow(windowScene: scene)
        #endif
    }

    #if os(iOS)
    private static var windowScenes: [UIWindowScene] {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    }
    #endif
}
