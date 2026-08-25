#if os(macOS)
import SwiftUI
import AppKit
import EventKit

struct SettingsAccountSection: View {
    let appleAccountManager: AppleAccountManager
    let onDeleteAccount: () -> Void

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
                                Text("Apple Account")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Theme.text)
                                Text("Optional identity for Cadence. Local access and iCloud sync do not depend on signing in.")
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
                            HStack(spacing: 10) {
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

                                Button("Delete Account...") {
                                    onDeleteAccount()
                                }
                                .buttonStyle(.cadencePlain)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.onColor)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Theme.red)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
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
                                .foregroundStyle(Theme.onColor)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 8)
                                .background(appleAccountManager.isAuthorizing ? Theme.dim : Theme.appleSignInFill)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.cadencePlain)
                            .disabled(appleAccountManager.isAuthorizing)
                        }
                    }

                    CadenceRowDivider()

                    VStack(spacing: 8) {
                        accountDiagnosticRow(
                            title: "Credential Status",
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
                            Text("OpenAI API Key")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.text)
                            Text("Stored in Keychain. Cadence sends selected note content to OpenAI only when you run an AI action, such as summarizing a note or extracting task drafts.")
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

                    CadenceRowDivider()

                    VStack(alignment: .leading, spacing: 8) {
                        aiDisclosureRow(
                            icon: "checkmark.shield.fill",
                            title: "User initiated",
                            detail: "AI requests run only after you choose an AI command."
                        )
                        aiDisclosureRow(
                            icon: "doc.text.magnifyingglass",
                            title: "Selected note content",
                            detail: "The note title, note text, and related list names may be sent for the requested action."
                        )
                        aiDisclosureRow(
                            icon: "key.fill",
                            title: "Your API key",
                            detail: "The key is stored in Keychain and can be removed here at any time."
                        )
                    }

                    CadenceRowDivider()

                    CadenceSettingsField(title: "API Key") {
                        SecureField(aiSettingsManager.hasAPIKey ? "Saved in Keychain" : "sk-...", text: $aiAPIKeyDraft)
                    }

                    CadenceSettingsField(title: "Model ID") {
                        TextField("gpt-5.4-mini", text: Binding(
                            get: { aiSettingsManager.model },
                            set: { aiSettingsManager.model = $0 }
                        ))
                    }

                    HStack(spacing: 10) {
                        Button("Save API Key") {
                            do {
                                try aiSettingsManager.saveAPIKey(aiAPIKeyDraft)
                                aiAPIKeyDraft = ""
                            } catch {
                                aiSettingsManager.statusMessage = AIErrorPresenter.message(for: error)
                            }
                        }
                        .buttonStyle(.cadencePlain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.onColor)
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
                            Button("Delete Key") {
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

    private func aiDisclosureRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.blue)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // `settingsField` used to sit here: an eyebrow over an inset well, at radius 9, with a
    // `.stroke` (which straddles the edge) rather than a `.strokeBorder`. It was one of three
    // spellings of the same well on this platform — `SettingsTagsSection` has the other two — and
    // iOS had already collapsed its own three into `iOSSettingsField`. That type is the shared
    // `CadenceSettingsField` now, on the radius scale, and this section reads it (T-20).
}

/// Settings → Navigation: the one app default the desktop has, as a value row.
///
/// **This is `iOSNavigationSettingsSection`'s shape, adopted rather than approximated (T-20).** It
/// was a bold `Default Page` title over a grey explanatory line over a row of `ListDetailPage`
/// pills, the selected one filled saturated `Theme.blue` — five different weights of emphasis for
/// one setting, and a control that exists nowhere else in the app. iOS rebuilt the same screen in
/// `775833d` on `iOSEditorFieldRow` + `iOSChoiceValueButton` + `iOSChoicePopoverList`, which are
/// now the shared `CadenceFieldRow` / `CadenceChoiceValueButton` / `CadenceChoicePopoverList`, so
/// the two platforms present one control.
///
/// The explanatory line stayed, unlike the three iOS dropped. Those said nothing their label did
/// not ("Choose the first calendar range shown on mobile", under a row reading *Calendar view*);
/// this one says something no label can — that a list normally remembers its own page, and this is
/// only the fallback. It sits under the row it belongs to rather than above it, indented to the
/// label column, at the same 11pt `Theme.dim` a choice row's subtitle uses.
struct SettingsNavigationSection: View {
    @Binding var listDetailDefaultPage: String
    @State private var showPagePicker = false

    /// Never trust the raw persisted string: it can still hold a page this build removed
    /// (e.g. "Planning"), which would leave the value reading as something unselectable.
    private var selectedPage: ListDetailPage {
        ListDetailPage.resolved(listDetailDefaultPage)
    }

    private var pageSelection: Binding<ListDetailPage> {
        Binding(
            get: { selectedPage },
            set: { listDetailDefaultPage = $0.rawValue }
        )
    }

    var body: some View {
        CadenceFieldSection(title: "List Opening") {
            CadenceFieldRow(label: "Default page", systemImage: "rectangle.stack") {
                CadenceChoiceValueButton(
                    title: selectedPage.rawValue,
                    minHeight: CadenceSettingsRowMetrics.rowHeight
                ) {
                    showPagePicker = true
                }
                .popover(isPresented: $showPagePicker) {
                    CadenceChoicePopoverList(
                        rows: ListDetailPage.allCases.map { page in
                            CadenceChoiceRow(
                                value: page,
                                title: page.rawValue,
                                systemImage: page.icon,
                                color: Theme.blue
                            )
                        },
                        selection: pageSelection,
                        isPresented: $showPagePicker
                    )
                }
            }

            Text("Used when a list does not have a saved page.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
                .padding(.leading, CadenceSettingsRowMetrics.glyphSlot + CadenceSettingsRowMetrics.glyphLabelSpacing)
        }
        .onAppear {
            // One-time normalization: rewrite a stale/unrecognized persisted value so the
            // rest of the app reads a page that actually exists.
            if listDetailDefaultPage != selectedPage.rawValue {
                listDetailDefaultPage = selectedPage.rawValue
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
            SettingsSectionLabel(text: "Main Sidebar Tabs")
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
                            CadenceRowDivider(leadingInset: 42)
                        }
                    }
                }
            }
        }
    }
}

#endif
