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
        let defaultsName = "CadenceTests.ai.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
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
