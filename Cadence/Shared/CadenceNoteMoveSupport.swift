import Foundation
import SwiftData

/// Filing a list note under another area or project, for both platforms.
///
/// **[[T-8762]]: this was macOS-only.** The two `move` helpers lived in
/// `Cadence/macOS/Views/AIActionsSupportViews.swift`, behind `#if os(macOS)`, so nothing under
/// `Cadence/iOS` could reach them, and a list note filed under the wrong list on the phone stayed
/// there until a Mac moved it. Nothing about re-filing a note is pointer- or keyboard-shaped
/// ([[T-8201]]), so the mutation moved here verbatim and each platform supplies only its chrome:
/// the Mac's Actions popover page, iOS's `iOSNoteManageMenu`. The Mac file keeps the rest of
/// `NoteActionSupport` as an extension, so its call sites read exactly as they did.
enum NoteActionSupport {
    /// Files a note under an area, or under nothing.
    ///
    /// **Throwing, and taking a non-optional context (T-630).** This used to repoint the note and
    /// run `try? modelContext?.save()`, and the row that called it had already closed the picker —
    /// so the popover shutting was the user's only success signal and it shut either way. A
    /// refused commit left the note repointed in the app's single `ModelContext`, waiting for the
    /// next unrelated `save()` to finish it or the next `rollback()` to throw it away, with nothing
    /// left on screen to disagree.
    ///
    /// The undo is a field snapshot rather than `modelContext.rollback()`, for the reason
    /// `CadencePendingChangePersistence.commitEdit` documents: one context app-wide, so a refused
    /// move must not take the note somebody is editing behind the popover with it.
    static func move(
        _ note: Note,
        toArea area: Area?,
        modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        let previousArea = note.area
        let previousProject = note.project
        let previousUpdatedAt = note.updatedAt
        let previousOrder = note.order
        note.order = arrivalOrder(for: note, area: area, project: nil)
        note.area = area
        note.project = nil
        note.updatedAt = Date()
        try CadencePendingChangePersistence.commitEdit(in: modelContext, commit: commit) {
            note.area = previousArea
            note.project = previousProject
            note.updatedAt = previousUpdatedAt
            note.order = previousOrder
        }
    }

    /// The project half of `move(_:toArea:modelContext:commit:)`, undoing the same four fields.
    ///
    /// Written out rather than routed through a shared private helper: a third declaration named
    /// `move` in this file would make every `declarationBody(named: "move")` reader ambiguous, and
    /// the saving is four lines.
    static func move(
        _ note: Note,
        toProject project: Project?,
        modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        let previousArea = note.area
        let previousProject = note.project
        let previousUpdatedAt = note.updatedAt
        let previousOrder = note.order
        note.order = arrivalOrder(for: note, area: nil, project: project)
        note.area = nil
        note.project = project
        note.updatedAt = Date()
        try CadencePendingChangePersistence.commitEdit(in: modelContext, commit: commit) {
            note.area = previousArea
            note.project = previousProject
            note.updatedAt = previousUpdatedAt
            note.order = previousOrder
        }
    }

    /// The `order` a note takes on arriving in a list: last among that list's notes, as a new
    /// note lands ([[T-13973]]).
    ///
    /// Both moves used to carry the note's old `order` across, which in the destination is a
    /// number from another list's sequence -- above every note there if the source list was
    /// young, below if old. `CadenceListNoteFiling.nextOrder(in:)` is the one allocation the `+`
    /// buttons read ([[T-13971]]). Read **before** the note is repointed, so the destination's
    /// inverse does not yet hold it.
    ///
    /// Two cases keep the order the note has: re-choosing the list it is already in (the checked
    /// row) is not an arrival, and "No List" has no list sequence to join -- unfiled list notes
    /// are not drawn in an `order`-sorted column.
    static func arrivalOrder(for note: Note, area: Area?, project: Project?) -> Int {
        let alreadyThere = (area != nil && note.area?.id == area?.id)
            || (project != nil && note.project?.id == project?.id)
        guard !alreadyThere, area != nil || project != nil else { return note.order }
        let residents = (area?.notes ?? project?.notes ?? [])
            .filter { $0.kind == .list && $0.id != note.id }
        return CadenceListNoteFiling.nextOrder(in: residents)
    }
}

/// The rules both platforms' Move Note chrome reads, so the two cannot come to disagree about
/// which notes can be moved or what a destination is called ([[T-8762]]).
enum CadenceNoteMoveDestinations {
    /// Move Note is offered for a list note, and only when there is a list to move it to.
    ///
    /// Dated, notepad and event notes are filed by their date, by nothing, or by their calendar
    /// event — a list is not theirs to change, which is why the Mac popover never offered it.
    static func offersMove(kind: NoteKind, hasAreas: Bool, hasProjects: Bool) -> Bool {
        kind == .list && (hasAreas || hasProjects)
    }

    /// The lists a note's Move Note page offers ([[T-9062]]).
    ///
    /// Both menus used to iterate the unfiltered `@Query`, so archived, done, paused and cancelled
    /// lists sat among the live ones and a note could be filed into a list the sidebar no longer
    /// shows. This is the rule every task list picker already reads
    /// (`CadenceTaskComposerSupport.pickableAreas` / `pickableProjects`): active lists, sorted,
    /// plus the note's **current** list even when it is inactive, so its checked row still reads.
    struct Destinations {
        let areas: [Area]
        let projects: [Project]
    }

    static func destinations(for note: Note, areas: [Area], projects: [Project]) -> Destinations {
        Destinations(
            areas: CadenceTaskComposerSupport.pickableAreas(areas, selectedID: note.area?.id),
            projects: CadenceTaskComposerSupport.pickableProjects(projects, selectedID: note.project?.id)
        )
    }

    /// `offersMove(kind:hasAreas:hasProjects:)` over the **filtered** lists, so a store whose only
    /// lists are archived does not offer a Move page with nowhere on it to go.
    static func offersMove(kind: NoteKind, destinations: Destinations) -> Bool {
        offersMove(kind: kind, hasAreas: !destinations.areas.isEmpty, hasProjects: !destinations.projects.isEmpty)
    }

    static let noListTitle = "No List"
    static let noListSubtitle = "Keep it loose in notes"

    /// Blank names read "Untitled Area", as the sidebar and Cmd+K read them (T-7288).
    static func title(for area: Area) -> String {
        CadenceTitleNormalization.display(area.name, fallback: CadenceTitleNormalization.defaultAreaName)
    }

    static func title(for project: Project) -> String {
        CadenceTitleNormalization.display(project.name, fallback: CadenceTitleNormalization.defaultProjectName)
    }

    static func isUnfiled(_ note: Note) -> Bool {
        note.area == nil && note.project == nil
    }
}
