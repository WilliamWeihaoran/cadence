import Testing

@testable import Cadence

struct NoteTemplateLibraryTests {
    @Test func overridesReplaceTemplateFieldsForMatchingNoteKinds() {
        let raw = NoteTemplateLibrary.setOverride(
            for: "project-brief",
            title: "Custom Brief",
            subtitle: "Custom scope",
            body: "# Custom",
            in: ""
        )

        let template = NoteTemplateLibrary.templates(for: .list, overridesRaw: raw)
            .first { $0.id == "project-brief" }

        #expect(template?.title == "Custom Brief")
        #expect(template?.subtitle == "Custom scope")
        #expect(template?.body == "# Custom")
    }

    @Test func resetOverrideRestoresDefaultTemplate() throws {
        let customizedRaw = NoteTemplateLibrary.setOverride(
            for: "research-note",
            title: "Custom Research",
            subtitle: "Changed",
            body: "# Changed",
            in: ""
        )
        let resetRaw = NoteTemplateLibrary.resetOverride(for: "research-note", in: customizedRaw)

        let defaultTemplate = try #require(NoteTemplateLibrary.defaultTemplate(id: "research-note"))
        let template = try #require(NoteTemplateLibrary.templates(for: .list, overridesRaw: resetRaw).first { $0.id == "research-note" })

        #expect(template == defaultTemplate)
        #expect(NoteTemplateLibrary.overrides(from: resetRaw).isEmpty)
    }

    @Test func matchingDefaultValuesDoNotPersistAnOverride() {
        let defaultTemplate = NoteTemplateLibrary.defaultTemplate(id: "checklist")!
        let raw = NoteTemplateLibrary.setOverride(
            for: defaultTemplate.id,
            title: defaultTemplate.title,
            subtitle: defaultTemplate.subtitle,
            body: defaultTemplate.body,
            in: ""
        )

        #expect(NoteTemplateLibrary.overrides(from: raw).isEmpty)
    }
}
