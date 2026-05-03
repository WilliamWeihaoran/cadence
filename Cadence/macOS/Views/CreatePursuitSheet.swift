#if os(macOS)
import SwiftData
import SwiftUI

struct CreatePursuitSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Pursuit.order) private var allPursuits: [Pursuit]
    @Query(sort: \Context.order) private var allContexts: [Context]

    private let editingPursuit: Pursuit?
    private let onSave: ((Pursuit) -> Void)?

    @State private var title = ""
    @State private var desc = ""
    @State private var selectedIcon = "sparkles"
    @State private var selectedColor = "#a78bfa"
    @State private var selectedContextID: UUID?
    @State private var selectedStatus: PursuitStatus = .active
    @Environment(\.modelContext) private var modelContext

    init(pursuit: Pursuit? = nil, context: Context? = nil, onSave: ((Pursuit) -> Void)? = nil) {
        editingPursuit = pursuit
        self.onSave = onSave
        _title = State(initialValue: pursuit?.title ?? "")
        _desc = State(initialValue: pursuit?.desc ?? "")
        _selectedIcon = State(initialValue: pursuit?.icon ?? "sparkles")
        _selectedColor = State(initialValue: pursuit?.colorHex ?? "#a78bfa")
        _selectedContextID = State(initialValue: pursuit?.context?.id ?? context?.id)
        _selectedStatus = State(initialValue: pursuit?.status ?? .active)
    }

    private var isEditing: Bool {
        editingPursuit != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isEditing ? "Edit Pursuit" : "New Pursuit")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)

            Divider().background(Theme.borderSubtle)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    fieldLabel("Title")
                    TextField("e.g. Become more knowledgeable", text: $title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.text)
                        .padding(10)
                        .background(Theme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderSubtle))

                    fieldLabel("Direction")
                    TextField("What are you trying to cultivate?", text: $desc)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.text)
                        .padding(10)
                        .background(Theme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderSubtle))

                    fieldLabel("Context")
                    CadenceContextPickerButton(
                        contexts: allContexts,
                        selectedID: $selectedContextID
                    )

                    if isEditing {
                        fieldLabel("Status")
                        PursuitStatusSection(selection: $selectedStatus)
                    }

                    fieldLabel("Icon")
                    IconGrid(selected: $selectedIcon)

                    fieldLabel("Color")
                    ColorGrid(selected: $selectedColor)
                }
                .padding(24)
            }

            Divider().background(Theme.borderSubtle)

            HStack {
                Spacer()
                CadenceActionButton(title: "Cancel", role: .ghost, size: .compact) {
                    dismiss()
                }
                CadenceActionButton(
                    title: isEditing ? "Save" : "Create",
                    role: .primary,
                    size: .compact,
                    tint: Color(hex: selectedColor),
                    isDisabled: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    save()
                }
            }
            .padding(16)
        }
        .frame(width: 460, height: 640)
        .background(Theme.surface)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.dim)
            .kerning(0.8)
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let pursuit = editingPursuit ?? Pursuit(title: trimmed)
        pursuit.title = trimmed
        pursuit.desc = desc.trimmingCharacters(in: .whitespacesAndNewlines)
        pursuit.icon = selectedIcon
        pursuit.colorHex = selectedColor
        pursuit.status = selectedStatus
        pursuit.context = selectedContextID.flatMap { id in allContexts.first { $0.id == id } }

        if editingPursuit == nil {
            pursuit.order = allPursuits.count
            modelContext.insert(pursuit)
        }

        onSave?(pursuit)
        dismiss()
    }
}

private struct PursuitStatusSection: View {
    @Binding var selection: PursuitStatus

    var body: some View {
        HStack(spacing: 8) {
            ForEach(PursuitStatus.allCases, id: \.self) { status in
                CadencePillButton(
                    title: status.label,
                    isSelected: selection == status,
                    minWidth: 70,
                    tint: tint(for: status)
                ) {
                    selection = status
                }
            }
        }
        .padding(4)
        .background(Theme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.borderSubtle, lineWidth: 1))
    }

    private func tint(for status: PursuitStatus) -> Color {
        switch status {
        case .active: return Theme.green
        case .paused: return Theme.amber
        case .done: return Theme.blue
        }
    }
}
#endif
