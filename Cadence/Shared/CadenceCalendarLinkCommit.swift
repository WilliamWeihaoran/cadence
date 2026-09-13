import Foundation
import SwiftData

/// **T-1132.** Writing one list's `linkedCalendarID`, and putting it back when the store refuses.
///
/// Both calendar settings surfaces — macOS's `SettingsCalendarSection` and iOS's
/// `iOSCalendarSettingsSection` — connect, disconnect and re-pick a calendar link from four
/// controls each, and every one of those writes used to reach the store through a swallowed save:
/// `try? modelContext.save()` on iOS, `do { … } catch { print(…) }` on macOS. The `print` was the
/// worse of the two, because it is not a report to the user *and* it is invisible to every half of
/// the save-commit rule: `swallowedSave` keys on `try?` over a commit surface, and a caught-and-
/// printed error is neither.
///
/// **What a refused save cost, and why it was not merely a lost edit.** The refresh that runs after
/// the write computes the device-local observation record from
/// `CadenceCalendarLinkObservations.linkedCalendarIDs(areas:projects:)` — read off the **model
/// objects**, which hold the new identifier whether or not the store took it — and writes it to
/// `UserDefaults`. A defaults write outlives the pending change, so the link was discarded and the
/// record saying *"this device is observing calendar X"* was not, for T-624's evidence gate to read
/// afterwards as fact. It cut both ways, because `observing(...)` ends in `∩ linked`: a refused
/// **link** manufactured evidence this device did not have, and a refused **unlink** erased
/// evidence it did, silencing a genuinely broken link the gate should still be reporting.
///
/// So the undo here is not decoration. Restoring the field before the caller is told is what makes
/// the surface's refusal notice ("Nothing was changed") true, and what leaves
/// `linkedCalendarIDs(areas:projects:)` answering the same set the store holds — which is the
/// premise the other two refresh call sites, `.onAppear` and the store-version change, quietly
/// depend on. Neither of those reads a pending write *because nothing leaves one pending any more*;
/// before this, a refused save left the edit on the model for the next appearance to publish.
///
/// The undo is a field snapshot rather than `modelContext.rollback()`, for the reason
/// `CadencePendingChangePersistence.commitEdit` documents: this app has one `ModelContext`, and a
/// refused calendar link must not take the note someone is typing behind the settings window.
enum CadenceCalendarLinkCommit {

    /// Links `area` to `calendarID` — or to nothing, for `""` — and commits it.
    ///
    /// - Parameter commit: How to commit. Defaulted for the same reason
    ///   `CadencePendingChangePersistence.commitInsert(of:in:commit:)` defaults it: a `save()` that
    ///   throws cannot be provoked out of an in-memory container, and an undo path no test can
    ///   reach is an undo path no test can prove.
    static func write(
        _ calendarID: String,
        to area: Area,
        in modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        let previous = area.linkedCalendarID
        area.linkedCalendarID = calendarID
        try CadencePendingChangePersistence.commitEdit(in: modelContext, commit: commit) {
            area.linkedCalendarID = previous
        }
    }

    /// `write(_:to:in:commit:)` for a project. The same sentence about a different model, which is
    /// the only difference between the two: `Area` and `Project` share no protocol here, and
    /// inventing one for a single `String` property would be a larger change than the second
    /// overload.
    static func write(
        _ calendarID: String,
        to project: Project,
        in modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        let previous = project.linkedCalendarID
        project.linkedCalendarID = calendarID
        try CadencePendingChangePersistence.commitEdit(in: modelContext, commit: commit) {
            project.linkedCalendarID = previous
        }
    }
}
