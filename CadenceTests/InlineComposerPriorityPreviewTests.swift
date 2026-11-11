#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// **T-8106.** `TaskTitleEntryField` drew its `!`/`!!`/`!!!` marker only for a host that passed a
/// `priority` binding, so a board column's inline composer showed the raw `!!` where the New Task
/// sheet showed the coloured marker. The composer keeps the marks in the title (it has no chip to
/// show a stripped priority) and asks for the preview explicitly.
@MainActor
struct InlineComposerPriorityPreviewTests {

    @Test func thePreviewIsOnForABindingOrAnExplicitRequestAndOffOtherwise() {
        #expect(TaskTitleEntryField.previewsPriorityShortcut(hasPriorityBinding: true, requested: false))
        #expect(TaskTitleEntryField.previewsPriorityShortcut(hasPriorityBinding: false, requested: true))
        #expect(!TaskTitleEntryField.previewsPriorityShortcut(hasPriorityBinding: false, requested: false))
    }

    @Test func theInlineComposerAsksForTheMarkerPreview() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/InlineTaskComposerView.swift")
        )
        let call = try #require(source.range(of: "TaskTitleEntryField("))
        let arguments = source[call.upperBound...].prefix(400)
        #expect(arguments.contains("previewsPriorityShortcut: true"))
        // Still no binding: with one, blurring strips the marks into a priority this row cannot show.
        #expect(!arguments.contains("priority: $"))
    }

    /// The field reaches the rule above from its init and gates the marker on it, rather than on
    /// the binding the composer does not pass.
    @Test func theTitleFieldGatesItsMarkerOnTheRequestedPreview() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TaskTitleEntryField.swift")
        )
        #expect(source.contains("requested: previewsPriorityShortcut"))
        #expect(source.contains("guard previewsPriorityShortcut else { return nil }"))
    }

    /// The marks the preview draws are the ones the saved card takes.
    @Test func theCardTakesThePriorityThePreviewDraws() throws {
        let segments = try #require(TaskTitleSupport.priorityShortcutSegments(in: "Call bank !!"))
        let draft = InlineTaskComposerSupport.draft(
            title: "Call bank !!",
            fields: InlineTaskComposerSupport.initialFields(for: .column(container: .inbox, sectionName: "")),
            tags: []
        )
        #expect(segments.title == "Call bank")
        #expect(draft.resolvedPriority == segments.priority)
        #expect(draft.resolvedPriority != .none)
    }

    /// **T-16586.** A title marked at both ends previews both marks as marks and the title between
    /// as plain text — the title and priority the card is actually created with. The segments used
    /// to carry the leading mark only, so `!! ship it !!!` drew a coloured `!!` and `ship it !!!`.
    @Test func aTitleMarkedAtBothEndsPreviewsBothMarksAndTheCreatedTitle() throws {
        let typed = "!! ship it !!!"
        let segments = try #require(TaskTitleSupport.priorityShortcutSegments(in: typed))
        let created = try #require(TaskTitleSupport.priorityShortcut(in: typed))
        let draft = InlineTaskComposerSupport.draft(
            title: typed,
            fields: InlineTaskComposerSupport.initialFields(for: .column(container: .inbox, sectionName: "")),
            tags: []
        )
        #expect(segments.leadingMarker == "!!")
        #expect(segments.trailingMarker == "!!!")
        #expect(segments.title == "ship it")
        #expect(segments.title == created.title)
        #expect(segments.priority == .high)
        #expect(draft.resolvedPriority == segments.priority)
    }

    /// One-ended marks keep the other end empty, so the preview draws a single marker.
    @Test func aTitleMarkedAtOneEndLeavesTheOtherMarkEmpty() throws {
        let leading = try #require(TaskTitleSupport.priorityShortcutSegments(in: "! call mom"))
        #expect(leading.leadingMarker == "!")
        #expect(leading.trailingMarker.isEmpty)
        #expect(leading.title == "call mom")

        let trailing = try #require(TaskTitleSupport.priorityShortcutSegments(in: "call mom !!"))
        #expect(trailing.leadingMarker.isEmpty)
        #expect(trailing.trailingMarker == "!!")
        #expect(trailing.title == "call mom")

        #expect(TaskTitleSupport.priorityShortcutSegments(in: "email! alice") == nil)
    }

    /// **T-16586.** The field draws both ends' marks, not one chosen by placement.
    @Test func theTitleFieldDrawsTheMarkAtEachEnd() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TaskTitleEntryField.swift")
        )
        #expect(source.contains("priorityShortcutMarker(segments.leadingMarker, priority: segments.priority)"))
        #expect(source.contains("priorityShortcutMarker(segments.trailingMarker, priority: segments.priority)"))
    }
}
#endif
