import SwiftData
import SwiftUI

/// What the add row calls the thing it makes ([[T-7085]]). A list's sections and its Kanban columns
/// are the same stored `TaskSectionConfig`, but the owner's call of 2026-11-03 is that a board says
/// "column" -- its header buttons, its editor and the Mac's add rail already did -- while the Tasks
/// tab keeps "section" for its grouping. One set of words for both platforms (T-8201).
nonisolated enum CadenceSectionCreationNoun: Equatable, Sendable {
    case section
    case column

    var buttonTitle: String {
        switch self {
        case .section: "Section"
        case .column: "Column"
        }
    }

    var namePlaceholder: String { "\(buttonTitle) name" }
    var addLabel: String { "Add \(buttonTitle.lowercased())" }
    var cancelLabel: String { "Cancel \(buttonTitle.lowercased())" }

    /// The name a board's add rail gives a NEW column; `KanbanBoardSupport.nextSectionName`
    /// numbers it past any column already holding it. Existing names are user data and never
    /// change -- a column the rail made as "New Section" keeps that name.
    static let newColumnBaseName = "New Column"
}

/// The bottom-of-list entry point; sections and Kanban columns use the same stored configs.
struct CadenceSectionCreationRow: View {
    var area: Area?
    var project: Project?
    /// `.column` on the iOS Kanban tab, `.section` (the default) on both Tasks tabs.
    var noun: CadenceSectionCreationNoun = .section

    @Environment(\.modelContext) private var modelContext
    @State private var isEditing = false
    @State private var name = ""
    @State private var failureNotice: String?
    @FocusState private var isNameFocused: Bool

    private var containerIdentity: UUID? { area?.id ?? project?.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if containerIdentity != nil {
                if isEditing {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .foregroundStyle(Theme.dim)
                            .accessibilityHidden(true)
                        TextField(noun.namePlaceholder, text: $name)
                            .textFieldStyle(.plain)
                            .focused($isNameFocused)
                            .onAppear { isNameFocused = true }
                            .onSubmit(addSection)
                            .onChange(of: name) { _, _ in failureNotice = nil }
                        Button(action: addSection) {
                            Image(systemName: "checkmark")
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .help(noun.addLabel)
                        .accessibilityLabel(noun.addLabel)
                        Button(action: cancel) {
                            Image(systemName: "xmark")
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .help(noun.cancelLabel)
                        .accessibilityLabel(noun.cancelLabel)
                    }
                    // [[T-10061]]: Escape cancels through the xmark's own `cancel`, focus-scoped, as
                    // it does in the Mac Links add form, the inline task composer and the Settings
                    // tag and context editors. `onExitCommand` is AppKit's route from the focused
                    // field; `onKeyPress` follows SwiftUI focus, and also reaches an iPad keyboard.
                    // `cancel()` is idempotent, so whichever fires second changes nothing.
                    #if os(macOS)
                    .onExitCommand(perform: cancel)
                    #endif
                    .onKeyPress(.escape) {
                        cancel()
                        return .handled
                    }
                } else {
                    Button {
                        isEditing = true
                    } label: {
                        Label(noun.buttonTitle, systemImage: "plus")
                            .foregroundStyle(Theme.dim)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(noun.addLabel)
                }
                if let failureNotice {
                    CadenceInlineNotice(text: failureNotice, tone: .failure)
                }
            }
        }
        .buttonStyle(.cadencePlain)
        .cadenceFont(.controlLabel)
        .foregroundStyle(Theme.text)
        .cadenceScaledTypography()
        .onChange(of: containerIdentity) { _, _ in cancel() }
    }

    private func addSection() {
        guard let container = CadenceSectionConfigMerge.container(area: area, project: project) else { return }
        failureNotice = CadenceSectionEditingSupport.createSection(
            named: name,
            colorHex: area?.colorHex ?? project?.colorHex ?? TaskSectionDefaults.defaultColorHex,
            in: container,
            modelContext: modelContext
        )
        guard failureNotice == nil else { return }
        cancel()
    }

    private func cancel() {
        isNameFocused = false
        isEditing = false
        name = ""
        failureNotice = nil
    }
}
