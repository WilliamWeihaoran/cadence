import SwiftData
import SwiftUI

/// The bottom-of-list entry point; sections and Kanban columns use the same stored configs.
struct CadenceSectionCreationRow: View {
    var area: Area?
    var project: Project?

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
                        TextField("Section name", text: $name)
                            .textFieldStyle(.plain)
                            .focused($isNameFocused)
                            .onAppear { isNameFocused = true }
                            .onSubmit(addSection)
                            .onChange(of: name) { _, _ in failureNotice = nil }
                        Button(action: addSection) {
                            Image(systemName: "checkmark")
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .help("Add section")
                        .accessibilityLabel("Add section")
                        Button(action: cancel) {
                            Image(systemName: "xmark")
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .help("Cancel section")
                        .accessibilityLabel("Cancel section")
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
                        Label("Section", systemImage: "plus")
                            .foregroundStyle(Theme.dim)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Add section")
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
