#if os(iOS)
import SwiftData
import SwiftUI
import UIKit

/// **[[T-18882]] — the long-press menu over a task card embedded in a note.**
///
/// The card is drawn by the note's `UITextView`, so a SwiftUI `.contextMenu` cannot be put on it;
/// the editor's `UIContextMenuInteraction` answers a press on the card with this `UIMenu` instead
/// of letting it fall to the text view's selection callout. It is `iOSTaskRowContextMenu` spelled
/// in UIKit: the same items, words, glyphs and order, and every write through the same static the
/// row's menu calls (`iOSTaskRowContextMenu.duplicate`, `.moveSection`, `.moveToList`,
/// `.selectRecurrenceRule`) or the same shared helper. `iOSTaskEmbedContextMenuParityTests` holds
/// the literal set equal to the row menu's, so an item added to one and not the other goes red.
///
/// Two items take the card's own path rather than the row's, as the Mac's card menu does: **Edit**
/// is what a tap on the card does (the inline task panel, else the task sheet), and every refusal,
/// the repeat-scope question and **Delete Task**'s confirmation are answered by
/// `iOSTaskEmbedMenuOutcomeModifier` on the note -- the row's modifiers, in the row's roles -- since
/// the menu is gone by the time any of them shows.
@MainActor
enum iOSTaskEmbedContextMenu {
    static func menu(
        for task: AppTask,
        modelContext: ModelContext,
        outcome: iOSTaskEmbedMenuOutcome,
        openDetail: @escaping () -> Void
    ) -> UIMenu {
        outcome.task = task
        let allTasks = (try? modelContext.fetch(FetchDescriptor<AppTask>(sortBy: [SortDescriptor(\.order)]))) ?? []
        let areas = (try? modelContext.fetch(FetchDescriptor<Area>(sortBy: [SortDescriptor(\.order)]))) ?? []
        let projects = (try? modelContext.fetch(FetchDescriptor<Project>(sortBy: [SortDescriptor(\.order)]))) ?? []
        let offerableAreas = CadenceTaskComposerSupport.pickableAreas(areas, selectedID: task.area?.id)
        let offerableProjects = CadenceTaskComposerSupport.pickableProjects(projects, selectedID: task.project?.id)

        func action(_ title: String, _ image: String, attributes: UIMenuElement.Attributes = [], _ handler: @escaping () -> Void) -> UIAction {
            UIAction(title: title, image: UIImage(systemName: image), attributes: attributes) { _ in handler() }
        }

        func submenu(_ title: String, _ image: String, _ children: [UIMenuElement]) -> UIMenu {
            UIMenu(title: title, image: UIImage(systemName: image), children: children)
        }

        func moveToContainer(area: Area?, project: Project?) {
            outcome.moveFailed = !iOSTaskRowContextMenu.moveToList(
                task,
                area: area,
                project: project,
                allTasks: allTasks,
                modelContext: modelContext
            )
        }

        var items: [UIMenuElement] = [action("Edit", "square.and.pencil", openDetail)]

        // Absent on a settled task, not disabled -- the row's T-276 rule.
        if CadenceFocusSupport.canFocus(task) {
            items.append(action("Focus", CadenceFeatureDestination.focus.systemImage) {
                CadenceFocusHandoffCenter.shared.request(.task(task.id))
            })
        }

        items.append(submenu("Priority: \(task.priority.label)", "flag.fill", TaskPriority.allCases.map { priority in
            action(priority.label, priority == task.priority ? "checkmark.circle.fill" : "circle") {
                outcome.priorityFailed = !CadenceTaskMutationSupport.setPriority(priority, for: task, modelContext: modelContext)
            }
        }))

        items.append(submenu(
            task.recurrenceRule == .none ? "Repeat" : "Repeat: \(task.recurrenceRule.label)",
            "repeat",
            TaskRecurrenceRule.allCases.map { recurrence in
                action(recurrence.label, recurrence == task.recurrenceRule ? "checkmark.circle.fill" : recurrence.systemImage) {
                    outcome.recurrenceFailed = !iOSTaskRowContextMenu.selectRecurrenceRule(
                        recurrence,
                        for: task,
                        allTasks: allTasks,
                        modelContext: modelContext,
                        pendingRecurrenceRule: Binding(
                            get: { outcome.pendingRecurrenceRule },
                            set: { outcome.pendingRecurrenceRule = $0 }
                        )
                    )
                }
            }
        ))

        var doDate: [UIMenuElement] = [
            action("Today", CadenceTaskDateMenuLabel.glyph(.today, dateKey: task.scheduledDate, otherwise: "sun.max.fill")) {
                outcome.dateFailed = !CadenceTaskDateEditing.scheduleToday(task, in: modelContext)
            },
            action("Tomorrow", CadenceTaskDateMenuLabel.glyph(.tomorrow, dateKey: task.scheduledDate, otherwise: "calendar")) {
                outcome.dateFailed = !CadenceTaskDateEditing.scheduleTomorrow(task, in: modelContext)
            },
            action("Next Week", CadenceTaskDateMenuLabel.glyph(.nextWeek, dateKey: task.scheduledDate, otherwise: "calendar.badge.clock")) {
                outcome.dateFailed = !CadenceTaskDateEditing.scheduleNextWeek(task, in: modelContext)
            },
        ]
        if !task.scheduledDate.isEmpty {
            doDate.append(action("Clear Do Date", "xmark.circle") {
                outcome.dateFailed = !CadenceTaskDateEditing.clearScheduledDate(task, in: modelContext)
            })
        }
        items.append(submenu(CadenceTaskDateMenuLabel.title("Do Date", dateKey: task.scheduledDate), "sun.max.fill", doDate))

        var dueDate: [UIMenuElement] = [
            action("Today", CadenceTaskDateMenuLabel.glyph(.today, dateKey: task.dueDate, otherwise: "flag.fill")) {
                outcome.dateFailed = !CadenceTaskDateEditing.dueToday(task, in: modelContext)
            },
            action("Tomorrow", CadenceTaskDateMenuLabel.glyph(.tomorrow, dateKey: task.dueDate, otherwise: "calendar")) {
                outcome.dateFailed = !CadenceTaskDateEditing.dueTomorrow(task, in: modelContext)
            },
            action("Next Week", CadenceTaskDateMenuLabel.glyph(.nextWeek, dateKey: task.dueDate, otherwise: "calendar.badge.clock")) {
                outcome.dateFailed = !CadenceTaskDateEditing.dueNextWeek(task, in: modelContext)
            },
        ]
        if !task.dueDate.isEmpty {
            dueDate.append(action("Clear Due Date", "xmark.circle") {
                outcome.dateFailed = !CadenceTaskDateEditing.clearDueDate(task, in: modelContext)
            })
        }
        items.append(submenu(CadenceTaskDateMenuLabel.title("Due Date", dateKey: task.dueDate), "flag.fill", dueDate))

        let names = task.moveSectionChoices
        if names.count > 1 {
            items.append(submenu("Move Section", "rectangle.split.3x1.fill", names.map { section in
                action(section, section.caseInsensitiveCompare(task.resolvedSectionName) == .orderedSame ? "checkmark.circle.fill" : "rectangle.split.3x1") {
                    outcome.moveFailed = !iOSTaskRowContextMenu.moveSection(section, task: task, modelContext: modelContext)
                }
            }))
        }

        // The row's `Divider()`s are inline groups here: UIKit draws the separator between them.
        var lists: [UIMenuElement] = [
            action("Inbox", task.area == nil && task.project == nil ? "checkmark.circle.fill" : CadenceListKindIcon.inbox) {
                moveToContainer(area: nil, project: nil)
            },
        ]
        if !offerableAreas.isEmpty {
            lists.append(UIMenu(options: .displayInline, children: offerableAreas.map { area in
                action(CadenceAreaPickerSupport.title(for: area), task.area?.id == area.id && task.project == nil ? "checkmark.circle.fill" : CadenceListKindIcon.area) {
                    moveToContainer(area: area, project: nil)
                }
            }))
        }
        if !offerableProjects.isEmpty {
            lists.append(UIMenu(options: .displayInline, children: offerableProjects.map { project in
                action(CadenceProjectPickerSupport.title(for: project), task.project?.id == project.id ? "checkmark.circle.fill" : CadenceListKindIcon.project) {
                    moveToContainer(area: nil, project: project)
                }
            }))
        }
        items.append(submenu("Move to List", "folder.fill", lists))

        items.append(action("Duplicate", "plus.square.on.square") {
            outcome.duplicateFailed = !iOSTaskRowContextMenu.duplicate(task, allTasks: allTasks, modelContext: modelContext)
        })

        items.append(action("Delete Task", "trash", attributes: .destructive) {
            outcome.showDeleteConfirmation = true
        })

        return UIMenu(children: items)
    }
}

/// The menu's after-the-tap state, held by the note for the embed whose menu opened last: the
/// flags the row keeps in `@State`, here because the menu is built outside any view.
@MainActor
@Observable
final class iOSTaskEmbedMenuOutcome {
    var task: AppTask?
    var showDeleteConfirmation = false
    var deleteFailed = false
    var moveFailed = false
    var recurrenceFailed = false
    var dateFailed = false
    var priorityFailed = false
    var duplicateFailed = false
    var pendingRecurrenceRule: TaskRecurrenceRule?
}

/// The other halves of the embed menu -- the repeat-scope question, the delete confirmation and its
/// failure, and the five refusals -- the same modifiers in the same roles `iOSBoardTaskCard` applies
/// them. On a background so the editor's identity never depends on whether a menu has opened.
struct iOSTaskEmbedMenuOutcomeModifier: ViewModifier {
    @Bindable var outcome: iOSTaskEmbedMenuOutcome
    @Environment(\.modelContext) private var modelContext

    func body(content: Content) -> some View {
        content.background {
            if let task = outcome.task {
                Color.clear
                    .iOSTaskRowRecurrenceScopeDialog(
                        task: task,
                        pendingRecurrenceRule: $outcome.pendingRecurrenceRule
                    )
                    .iOSTaskDeleteConfirmation(task: task, isPresented: $outcome.showDeleteConfirmation) { scope in
                        outcome.deleteFailed = !CadenceTaskMutationSupport.delete(
                            task,
                            modelContext: modelContext,
                            recurrenceScope: scope
                        )
                    }
                    .iOSTaskDeleteFailureAlert(isPresented: $outcome.deleteFailed)
                    .iOSTaskMoveFailureAlert(isPresented: $outcome.moveFailed)
                    .iOSTaskRowRecurrenceFailureAlert(isPresented: $outcome.recurrenceFailed)
                    .iOSTaskRowDateFailureAlert(isPresented: $outcome.dateFailed)
                    .iOSTaskRowPriorityFailureAlert(isPresented: $outcome.priorityFailed)
                    .iOSTaskRowDuplicateFailureAlert(isPresented: $outcome.duplicateFailed)
            }
        }
    }
}
#endif
