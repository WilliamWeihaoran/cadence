import Foundation
import SwiftData
import Testing
@testable import Cadence

private final class InMemorySecretStore: AISecretStore {
    var values: [String: String] = [:]

    func loadSecret(account: String) throws -> String? {
        values[account]
    }

    func saveSecret(_ secret: String, account: String) throws {
        values[account] = secret
    }

    func deleteSecret(account: String) throws {
        values.removeValue(forKey: account)
    }
}

@MainActor
struct AISettingsManagerTests {
    @Test func settingsManagerSavesModelInDefaultsAndKeyInSecretStore() throws {
        try withTemporaryDefaults("CadenceTests.ai") { defaults in
            let secretStore = InMemorySecretStore()
            let manager = AISettingsManager(secretStore: secretStore, defaults: defaults)

            #expect(manager.model == "gpt-5.4-mini")
            #expect(manager.hasAPIKey == false)

            manager.model = "gpt-test"
            try manager.saveAPIKey(" sk-test ")

            #expect(defaults.string(forKey: "ai.openai.model") == "gpt-test")
            #expect(try manager.loadAPIKey() == "sk-test")
            #expect(manager.hasAPIKey)

            try manager.removeAPIKey()

            #expect(try manager.loadAPIKey() == nil)
            #expect(manager.hasAPIKey == false)
        }
    }
}

struct OpenAIResponsesProviderTests {
    @Test func providerBuildsResponsesRequestWithAuthModelAndStructuredOutput() throws {
        let provider = OpenAIResponsesProvider(apiKey: "sk-test", model: "gpt-test")
        let body = OpenAIResponseRequest(
            model: "gpt-test",
            instructions: "Extract tasks",
            input: "Note",
            text: .init(format: .taskDraftsSchema),
            maxOutputTokens: 100
        )

        let request = try provider.makeURLRequest(for: body)
        let data = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let text = try #require(json["text"] as? [String: Any])
        let format = try #require(text["format"] as? [String: Any])

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(json["model"] as? String == "gpt-test")
        #expect(format["type"] as? String == "json_schema")
        #expect(format["name"] as? String == "cadence_task_drafts")
        #expect(format["strict"] as? Bool == true)
    }
}

/// No platform guard. `AIActionService` carried an incidental `#if os(macOS)` around its whole
/// body, so these three tests were fenced off with it; the service is cross-platform now and so are
/// they.
@MainActor
struct AIActionServiceTests {
    @Test func noteContextOnlyIncludesSelectedNoteAndContainerName() throws {
        let context = Context(name: "Work")
        let project = Project(name: "Launch", context: context)
        let note = Note(kind: .list, title: "Specs")
        note.content = "Ship the thing."

        let result = try AIActionService.noteContext(note: note, project: project)

        #expect(result.title == "Specs")
        #expect(result.content == "Ship the thing.")
        #expect(result.containerName == "Launch")
    }

    @Test func applyingSelectedTaskDraftsCreatesOnlySelectedTasks() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let context = Context(name: "Work")
        let project = Project(name: "Launch", context: context)
        project.sectionNames = [TaskSectionDefaults.defaultName, "Build"]
        modelContext.insert(context)
        modelContext.insert(project)
        try modelContext.save()

        let selectedDraft = AITaskDraft(
            title: "Build BYOK",
            notes: "From AI test",
            priority: "high",
            dueDate: "2026-05-01",
            scheduledDate: "2026-04-30",
            scheduledStartMin: 960,
            estimatedMinutes: 90,
            sectionName: "Build",
            subtaskTitles: ["Settings", "Review sheet"]
        )
        let ignoredDraft = AITaskDraft(title: "Do not create")

        let created = try AIActionService.applyTaskDrafts(
            [selectedDraft, ignoredDraft],
            selectedIDs: [selectedDraft.id],
            project: project,
            areas: [],
            projects: [project],
            modelContext: modelContext
        )

        #expect(created.count == 1)
        #expect(created.first?.title == "Build BYOK")
        #expect(created.first?.priority == .high)
        #expect(created.first?.dueDate == "2026-05-01")
        #expect(created.first?.scheduledDate == "2026-04-30")
        #expect(created.first?.scheduledStartMin == 960)
        #expect(created.first?.estimatedMinutes == 90)
        #expect(created.first?.sectionName == "Build")
        #expect(created.first?.project?.id == project.id)
        #expect(Set(created.first?.subtasks?.map(\.title) ?? []) == Set(["Settings", "Review sheet"]))
    }

    @Test func invalidDraftsDoNotPartiallyCreateTasks() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let invalid = AITaskDraft(title: "Bad draft", priority: "urgent")

        #expect(throws: AIActionError.self) {
            try AIActionService.applyTaskDrafts(
                [invalid],
                selectedIDs: [invalid.id],
                areas: [],
                projects: [],
                modelContext: modelContext
            )
        }

        let descriptor = FetchDescriptor<AppTask>()
        #expect(try modelContext.fetch(descriptor).isEmpty)
    }
}

/// **T-574: pressing Save with the field empty must never delete the saved key.**
///
/// The AI settings card shows an *empty* `SecureField` whenever a key is stored — the placeholder
/// reads "Saved in Keychain", because the secret itself is never rendered back. So "empty draft" is
/// the resting state of the screen, not an unusual one, and routing it to `removeAPIKey()` made
/// **Save API Key** a one-click credential wipe on the pane's default state. macOS had no guard at
/// all; iOS disabled its Save button but leaned on the view for the whole of the protection.
///
/// Both halves are pinned here: the manager refuses an empty save whatever calls it, and each
/// platform's Save control is dead while the draft is blank so the refusal is not something the
/// user has to discover by triggering it.
@MainActor
struct AIAPIKeySaveGuardTests {

    /// The behaviour, on a real manager over a real (in-memory) secret store: a stored key
    /// survives a blank save, a whitespace-only save, and the error each one reports.
    @Test func anEmptyDraftCannotReachRemovalAndLeavesTheStoredKeyIntact() throws {
        try withTemporaryDefaults("CadenceTests.ai.emptySave") { defaults in
            let secretStore = InMemorySecretStore()
            let manager = AISettingsManager(secretStore: secretStore, defaults: defaults)

            try manager.saveAPIKey("sk-live")
            #expect(manager.hasAPIKey)

            for blank in ["", "   ", "\n\t "] {
                #expect(throws: AISettingsError.emptyAPIKey) {
                    try manager.saveAPIKey(blank)
                }
                #expect(
                    try manager.loadAPIKey() == "sk-live",
                    "saving \(blank.debugDescription) destroyed the stored API key"
                )
                #expect(manager.hasAPIKey, "saving \(blank.debugDescription) cleared the key status")
                #expect(
                    manager.statusMessage != "API key removed.",
                    "saving \(blank.debugDescription) reported a removal"
                )
            }

            // Removal is still reachable — deliberately, and only through its own function.
            try manager.removeAPIKey()
            #expect(try manager.loadAPIKey() == nil)
            #expect(manager.hasAPIKey == false)
        }
    }

    /// A save is not a delete. Scoped to `saveAPIKey`'s own body so the assertion cannot be
    /// satisfied by `removeAPIKey`'s declaration twelve lines below it.
    @Test func theSaveFunctionDoesNotReachTheRemovalPathAtAll() throws {
        let source = try aiKeyGuardStrippingComments(
            aiKeyGuardSourceFile("Cadence/Services/AI/AISettingsManager.swift")
        )
        let body = try cadenceFunctionBody("func saveAPIKey(_ key: String) throws", in: source)

        #expect(
            !body.contains("removeAPIKey"),
            "an empty draft routes back to key removal from inside saveAPIKey"
        )
        #expect(
            body.contains("AISettingsError.emptyAPIKey"),
            "saveAPIKey no longer refuses an empty draft"
        )
    }

    /// Both Save controls are dead while the draft is blank, and both decide it by trimming — a
    /// button that stays live on `"   "` and a guard that rejects it are two different answers to
    /// the same question.
    @Test func neitherPlatformOffersALiveSaveButtonOnABlankDraft() throws {
        let expectations = [
            "Cadence/macOS/Views/SettingsSectionViews.swift": [
                ".disabled(isAPIKeyDraftEmpty)",
                "aiAPIKeyDraft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty",
            ],
            "Cadence/iOS/iOSSettingsTemplateAndListSections.swift": [
                "isDisabled:aiAPIKeyDraft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty",
            ],
        ]

        for (path, needles) in expectations {
            let source = try aiKeyGuardStrippingComments(aiKeyGuardSourceFile(path))
            // Non-vacuity: this really is the AI settings card, read from disk, before any
            // absence or presence claim is made about it.
            #expect(source.contains("Save API Key") || source.contains("Save Key"), "\(path) is not the AI key card")
            let compact = source.filter { !$0.isWhitespace }
            for needle in needles {
                #expect(compact.contains(needle), "\(path) no longer guards Save with \(needle)")
            }
        }
    }
}

private func aiKeyGuardSourceFile(_ relativePath: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
}

private func aiKeyGuardStrippingComments(_ source: String) throws -> String {
    let withoutBlocks = try NSRegularExpression(pattern: "/\\*.*?\\*/", options: [.dotMatchesLineSeparators])
    let stripped = withoutBlocks.stringByReplacingMatches(
        in: source,
        range: NSRange(source.startIndex..<source.endIndex, in: source),
        withTemplate: ""
    )
    return stripped
        .components(separatedBy: .newlines)
        .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        .joined(separator: "\n")
}
