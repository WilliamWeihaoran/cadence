import Foundation
import Observation
import Security

protocol AISecretStore {
    func loadSecret(account: String) throws -> String?
    func saveSecret(_ secret: String, account: String) throws
    func deleteSecret(account: String) throws
}

enum AIKeychainError: LocalizedError, Equatable {
    case unexpectedStatus(OSStatus)
    case invalidSecretData

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return "Keychain returned status \(status)."
        case .invalidSecretData:
            return "The stored API key could not be read."
        }
    }
}

struct KeychainCredentialStore: AISecretStore {
    var service = "com.haoranwei.Cadence.ai"

    func loadSecret(account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw AIKeychainError.unexpectedStatus(status) }
        guard let data = result as? Data, let secret = String(data: data, encoding: .utf8) else {
            throw AIKeychainError.invalidSecretData
        }
        return secret
    }

    func saveSecret(_ secret: String, account: String) throws {
        let data = Data(secret.utf8)
        var query = baseQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw AIKeychainError.unexpectedStatus(updateStatus)
        }

        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw AIKeychainError.unexpectedStatus(addStatus) }
    }

    func deleteSecret(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AIKeychainError.unexpectedStatus(status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

@Observable
final class AISettingsManager {
    static let shared = AISettingsManager()

    private enum Key {
        static let model = "ai.openai.model"
        static let apiKeyAccount = "openai.apiKey"
    }

    private let secretStore: AISecretStore
    private let defaults: UserDefaults

    var model: String {
        didSet {
            defaults.set(model.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.model)
        }
    }
    var hasAPIKey = false
    var statusMessage: String?
    var isTestingConnection = false

    init(secretStore: AISecretStore = KeychainCredentialStore(), defaults: UserDefaults = .standard) {
        self.secretStore = secretStore
        self.defaults = defaults
        let storedModel = defaults.string(forKey: Key.model)?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = storedModel?.isEmpty == false ? storedModel! : "gpt-5.4-mini"
        refreshKeyStatus()
    }

    func refreshKeyStatus() {
        do {
            hasAPIKey = try loadAPIKey() != nil
        } catch {
            hasAPIKey = false
            statusMessage = AIErrorPresenter.message(for: error)
        }
    }

    func loadAPIKey() throws -> String? {
        let secret = try secretStore.loadSecret(account: Key.apiKeyAccount)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return secret?.isEmpty == false ? secret : nil
    }

    func saveAPIKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try removeAPIKey()
            return
        }
        try secretStore.saveSecret(trimmed, account: Key.apiKeyAccount)
        hasAPIKey = true
        statusMessage = "API key saved."
    }

    func removeAPIKey() throws {
        try secretStore.deleteSecret(account: Key.apiKeyAccount)
        hasAPIKey = false
        statusMessage = "API key removed."
    }

    func provider(session: URLSession = .shared) throws -> AIProvider {
        guard let apiKey = try loadAPIKey() else { throw AIProviderError.missingAPIKey }
        let selectedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return OpenAIResponsesProvider(
            apiKey: apiKey,
            model: selectedModel.isEmpty ? "gpt-5.4-mini" : selectedModel,
            session: session
        )
    }

    @MainActor
    func testConnection() async {
        isTestingConnection = true
        defer { isTestingConnection = false }
        do {
            let provider = try provider()
            _ = try await provider.summarizeNote(
                AITextNoteContext(title: "Connection Test", content: "Reply with a short confirmation.")
            )
            statusMessage = "Connection works."
        } catch {
            statusMessage = AIErrorPresenter.message(for: error)
        }
    }
}

enum AIErrorPresenter {
    static func message(for error: Error) -> String {
        if let localized = error as? LocalizedError, let message = localized.errorDescription {
            return message
        }
        return error.localizedDescription
    }
}
