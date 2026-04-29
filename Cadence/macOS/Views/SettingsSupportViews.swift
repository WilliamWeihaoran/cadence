#if os(macOS)
import SwiftUI
import SwiftData
import EventKit
import AuthenticationServices
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

struct CalendarLinkRow: View {
    let icon: String
    let name: String
    let color: Color
    @Binding var linkedCalendarID: String
    let calendars: [EKCalendar]

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(color.opacity(0.18))
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(color)
                }

            Text(name)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)

            Spacer()

            CadenceCalendarPickerButton(
                calendars: calendars,
                selectedID: $linkedCalendarID,
                style: .compact
            )
            .fixedSize()
        }
        .padding(.vertical, 10)
    }
}

struct ContextSettingsRow: View {
    @Bindable var context: Context
    let onDropBefore: (UUID) -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var isDropTarget = false
    @State private var isEditing = false
    @State private var editName = ""
    @State private var editColor = ""
    @State private var editIcon = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(hex: isEditing ? editColor : context.colorHex).opacity(0.18))
                    .frame(width: 28, height: 28)
                    .overlay {
                        Image(systemName: isEditing ? editIcon : context.icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: isEditing ? editColor : context.colorHex))
                    }

                Text(isEditing ? (editName.isEmpty ? context.name : editName) : context.name)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)

                Spacer()

                if isHovered && !isEditing {
                    HStack(spacing: 4) {
                        actionButton(icon: "pencil") { startEditing() }
                        actionButton(icon: "archivebox", color: Theme.amber) { onArchive() }
                        actionButton(icon: "trash", color: Theme.red) { onDelete() }
                    }
                    .transition(.opacity)
                }

                if !isEditing {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isDropTarget ? Theme.blue.opacity(0.10) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isDropTarget ? Theme.blue.opacity(0.45) : Color.clear, lineWidth: 1)
            )

            if isEditing {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Context name", text: $editName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text)
                        .padding(8)
                        .background(Theme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.borderSubtle))

                    Text("COLOR")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                        .kerning(0.8)
                    ColorGrid(selected: $editColor)

                    Text("ICON")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                        .kerning(0.8)
                    IconGrid(selected: $editIcon)

                    HStack {
                        Spacer()
                        CadenceActionButton(
                            title: "Cancel",
                            role: .ghost,
                            size: .compact
                        ) {
                            withAnimation(.easeInOut(duration: 0.15)) { isEditing = false }
                        }

                        CadenceActionButton(
                            title: "Save",
                            role: .primary,
                            size: .compact,
                            isDisabled: editName.trimmingCharacters(in: .whitespaces).isEmpty
                        ) {
                            saveEdit()
                        }
                    }
                    .padding(.bottom, 4)
                }
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isEditing)
        .onHover { isHovered = $0 }
        .draggable(context.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard let draggedID = items.compactMap(UUID.init(uuidString:)).first else { return false }
            onDropBefore(draggedID)
            isDropTarget = false
            return true
        } isTargeted: { targeted in
            isDropTarget = targeted
        }
    }

    @ViewBuilder
    private func actionButton(icon: String, color: Color = Theme.dim, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(color)
                .frame(width: 26, height: 26)
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.cadencePlain)
    }

    private func startEditing() {
        editName = context.name
        editColor = context.colorHex
        editIcon = context.icon
        withAnimation(.easeInOut(duration: 0.15)) { isEditing = true }
    }

    private func saveEdit() {
        let trimmed = editName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        context.name = trimmed
        context.colorHex = editColor
        context.icon = editIcon
        withAnimation(.easeInOut(duration: 0.15)) { isEditing = false }
    }
}

struct ArchivedContextRow: View {
    let context: Context
    let onRestore: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(hex: context.colorHex).opacity(0.12))
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: context.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: context.colorHex).opacity(0.5))
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(context.name)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                Text("Archived")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.amber)
            }

            Spacer()

            Button("Restore", action: onRestore)
                .buttonStyle(.cadencePlain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Button("Delete", action: onDelete)
                .buttonStyle(.cadencePlain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Theme.red)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(.vertical, 10)
    }
}

struct SidebarTabSettingsRow: View {
    let destination: SidebarStaticDestination
    let tintHex: String
    let isVisible: Bool
    let onEdit: () -> Void
    let onDropBefore: (SidebarStaticDestination) -> Void

    @State private var isDropTarget = false

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(hex: tintHex).opacity(0.15))
                .frame(width: 30, height: 30)
                .overlay {
                    Image(systemName: destination.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: tintHex))
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(destination.label)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                Text(isVisible ? "Visible in sidebar" : "Hidden from sidebar")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.dim)
            }

            Spacer()

            Button("Edit", action: onEdit)
                .buttonStyle(.cadencePlain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.dim)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 2)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isDropTarget ? Theme.blue.opacity(0.10) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isDropTarget ? Theme.blue.opacity(0.45) : Color.clear, lineWidth: 1)
        )
        .draggable(destination.rawValue)
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, let dragged = SidebarStaticDestination(rawValue: raw) else { return false }
            onDropBefore(dragged)
            isDropTarget = false
            return true
        } isTargeted: { targeted in
            isDropTarget = targeted
        }
    }
}

struct SidebarTabEditorSheet: View {
    let destination: SidebarStaticDestination
    @Binding var tintHex: String
    @Binding var isVisible: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(hex: tintHex).opacity(0.16))
                    .frame(width: 42, height: 42)
                    .overlay {
                        Image(systemName: destination.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color(hex: tintHex))
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text(destination.label)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("Customize how this tab appears in the sidebar.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Color")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.dim)

                ColorGrid(selected: $tintHex)
            }

            settingsPanelRow(
                title: "Show in Sidebar",
                subtitle: "Hidden tabs can still be restored later from Settings."
            ) {
                Toggle("", isOn: $isVisible)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(Theme.blue)
            }

            HStack {
                Spacer()
                CadenceActionButton(
                    title: "Done",
                    role: .primary,
                    size: .compact
                ) {
                    dismiss()
                }
            }
        }
        .padding(22)
        .frame(width: 420)
        .background(Theme.bg)
    }

    @ViewBuilder
    private func settingsPanelRow<Accessory: View>(
        title: String,
        subtitle: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            accessory()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.borderSubtle, lineWidth: 1)
        }
    }
}

struct ListLifecycleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let statusLabel: String
    let primaryLabel: String
    let onPrimary: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(color.opacity(0.18))
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(color)
                }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(statusLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(statusLabel == "Completed" ? Theme.green : Theme.amber)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background((statusLabel == "Completed" ? Theme.green : Theme.amber).opacity(0.14))
                        .clipShape(Capsule())
                }
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                }
            }

            Spacer()

            Button(primaryLabel, action: onPrimary)
                .buttonStyle(.cadencePlain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Button("Delete", action: onDelete)
                .buttonStyle(.cadencePlain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Theme.red)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(.vertical, 10)
    }
}
#endif
