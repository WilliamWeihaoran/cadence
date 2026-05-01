#if os(macOS)
import SwiftUI
import AppKit
import EventKit

struct SettingsAppearanceSection: View {
    let selectedTheme: ThemeOption
    let onSelectTheme: (ThemeOption) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 220), spacing: 16, alignment: .top)
                ],
                spacing: 16
            ) {
                ForEach(ThemeOption.allCases) { option in
                    themeOptionCard(option)
                }
            }
        }
    }

    private func themeOptionCard(_ option: ThemeOption) -> some View {
        let isSelected = selectedTheme == option

        return Button {
            onSelectTheme(option)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ForEach(Array(option.previewColors.enumerated()), id: \.offset) { _, color in
                        RoundedRectangle(cornerRadius: 6)
                            .fill(color)
                            .frame(height: 34)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(option.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        if isSelected {
                            Text("Active")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Theme.blue)
                                .clipShape(Capsule())
                        }
                    }

                    Text(option.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Theme.blue.opacity(0.7) : Theme.borderSubtle, lineWidth: isSelected ? 1.4 : 1)
            }
        }
        .buttonStyle(.cadencePlain)
    }
}

struct SettingsAccountSection: View {
    let appleAccountManager: AppleAccountManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 14) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill((appleAccountManager.isSignedIn ? Theme.green : Theme.dim).opacity(0.16))
                            .frame(width: 42, height: 42)
                            .overlay {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(appleAccountManager.isSignedIn ? Theme.green : Theme.dim)
                            }

                        VStack(alignment: .leading, spacing: 7) {
                            if let profile = appleAccountManager.profile {
                                Text(profile.displayName)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Theme.text)
                                if !profile.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text(profile.email)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.dim)
                                }
                                Text("Signed in \(DateFormatters.shortDate.string(from: profile.signedInAt))")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.muted)
                            } else {
                                Text("Sign in with Apple")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Theme.text)
                                Text("Use your Apple account as your Cadence identity. This does not lock the app or change iCloud sync.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.dim)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            if let statusMessage = appleAccountManager.statusMessage {
                                Text(statusMessage)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.muted)
                                    .padding(.top, 2)
                            }
                        }

                        Spacer()

                        if appleAccountManager.isSignedIn {
                            Button("Sign Out") {
                                appleAccountManager.signOut()
                            }
                            .buttonStyle(.cadencePlain)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.red)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Theme.red.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            Button {
                                appleAccountManager.signIn()
                            } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: "apple.logo")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text(appleAccountManager.isAuthorizing ? "Signing In..." : "Sign in with Apple")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 8)
                                .background(appleAccountManager.isAuthorizing ? Theme.dim : Color.black)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.cadencePlain)
                            .disabled(appleAccountManager.isAuthorizing)
                        }
                    }

                    Divider()
                        .background(Theme.borderSubtle)

                    VStack(spacing: 8) {
                        accountDiagnosticRow(
                            title: "Credential",
                            value: appleAccountManager.credentialStatus.title,
                            color: appleAccountManager.credentialStatus == .authorized ? Theme.green : Theme.dim
                        )
                        accountDiagnosticRow(
                            title: "Apple Sign-In Entitlement",
                            value: appleAccountManager.entitlementStatus.title,
                            color: appleAccountManager.entitlementStatus.isConfigured ? Theme.green : Theme.amber,
                            detail: appleAccountManager.entitlementStatus.detail
                        )
                    }
                }
            }
        }
        .onAppear {
            appleAccountManager.refreshCredentialState()
        }
    }

    private func accountDiagnosticRow(
        title: String,
        value: String,
        color: Color,
        detail: String? = nil
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.muted)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                if let detail {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.muted)
                }
            }
        }
    }
}

struct SettingsAISection: View {
    let aiSettingsManager: AISettingsManager
    @Binding var aiAPIKeyDraft: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 14) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill((aiSettingsManager.hasAPIKey ? Theme.green : Theme.dim).opacity(0.16))
                            .frame(width: 42, height: 42)
                            .overlay {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(aiSettingsManager.hasAPIKey ? Theme.green : Theme.dim)
                            }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("OpenAI BYOK")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.text)
                            Text("Cadence stores your API key in Keychain and sends only the note you choose to summarize or extract tasks from.")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.dim)
                                .fixedSize(horizontal: false, vertical: true)
                            if let statusMessage = aiSettingsManager.statusMessage {
                                Text(statusMessage)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.muted)
                            }
                        }

                        Spacer()
                    }

                    Divider().background(Theme.borderSubtle)

                    settingsField(title: "API Key") {
                        SecureField(aiSettingsManager.hasAPIKey ? "Saved in Keychain" : "sk-...", text: $aiAPIKeyDraft)
                    }

                    settingsField(title: "Model") {
                        TextField("gpt-5.4-mini", text: Binding(
                            get: { aiSettingsManager.model },
                            set: { aiSettingsManager.model = $0 }
                        ))
                    }

                    HStack(spacing: 10) {
                        Button("Save Key") {
                            do {
                                try aiSettingsManager.saveAPIKey(aiAPIKeyDraft)
                                aiAPIKeyDraft = ""
                            } catch {
                                aiSettingsManager.statusMessage = AIErrorPresenter.message(for: error)
                            }
                        }
                        .buttonStyle(.cadencePlain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Theme.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        Button(aiSettingsManager.isTestingConnection ? "Testing..." : "Test Connection") {
                            Task { await aiSettingsManager.testConnection() }
                        }
                        .buttonStyle(.cadencePlain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(aiSettingsManager.hasAPIKey ? Theme.blue : Theme.dim)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background((aiSettingsManager.hasAPIKey ? Theme.blue : Theme.dim).opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .disabled(!aiSettingsManager.hasAPIKey || aiSettingsManager.isTestingConnection)

                        if aiSettingsManager.hasAPIKey {
                            Button("Remove Key") {
                                do {
                                    try aiSettingsManager.removeAPIKey()
                                } catch {
                                    aiSettingsManager.statusMessage = AIErrorPresenter.message(for: error)
                                }
                            }
                            .buttonStyle(.cadencePlain)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.red)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Theme.red.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
        }
        .onAppear {
            aiSettingsManager.refreshKeyStatus()
        }
    }

    private func settingsField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.muted)
            content()
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(Theme.borderSubtle, lineWidth: 1)
                }
        }
    }
}

struct SettingsNavigationSection: View {
    @Binding var listDetailDefaultPage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Default List Page")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.dim)

                    HStack(spacing: 10) {
                        ForEach(ListDetailPage.allCases) { page in
                            Button {
                                listDetailDefaultPage = page.rawValue
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: page.icon)
                                        .font(.system(size: 11, weight: .semibold))
                                    Text(page.rawValue)
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundStyle(listDetailDefaultPage == page.rawValue ? .white : Theme.dim)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(minHeight: 34)
                                .contentShape(Rectangle())
                                .background(listDetailDefaultPage == page.rawValue ? Theme.blue : Theme.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 9))
                            }
                            .buttonStyle(.cadencePlain)
                        }
                    }
                }
            }
        }
    }
}

struct SettingsSidebarSection: View {
    let orderedSidebarTabs: [SidebarStaticDestination]
    let hiddenTabs: Set<SidebarStaticDestination>
    let sidebarTabColorsRaw: String
    let onEdit: (SidebarStaticDestination) -> Void
    let onDropBefore: (SidebarStaticDestination, SidebarStaticDestination) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard {
                VStack(spacing: 0) {
                    ForEach(Array(orderedSidebarTabs.enumerated()), id: \.element.id) { index, destination in
                        SidebarTabSettingsRow(
                            destination: destination,
                            tintHex: destination.resolvedColorHex(from: sidebarTabColorsRaw),
                            isVisible: !hiddenTabs.contains(destination),
                            onEdit: { onEdit(destination) },
                            onDropBefore: { onDropBefore($0, destination) }
                        )
                        if index < orderedSidebarTabs.count - 1 {
                            Divider().background(Theme.borderSubtle).padding(.leading, 42)
                        }
                    }
                }
            }
        }
    }
}

#endif
