#if os(macOS)
import SwiftUI
import SwiftData

struct CreateGoalSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Goal.order) private var allGoals: [Goal]
    @Query(sort: \Context.order) private var allContexts: [Context]

    @State private var title = ""
    @State private var desc = ""
    @State private var selectedContextID: UUID? = nil
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
    @State private var progressType: GoalProgressType = .subtasks
    @State private var targetHours: Double = 10
    @State private var selectedColor = "#4a9eff"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("New Goal")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)

            Divider().background(Theme.borderSubtle)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Title
                    fieldLabel("Title")
                    TextField("e.g. Run a 5K, Ship v1.0", text: $title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.text)
                        .padding(10)
                        .background(Theme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderSubtle))

                    // Outcome / desc
                    fieldLabel("Outcome")
                    TextField("Definitive outcome — what does done look like?", text: $desc)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.text)
                        .padding(10)
                        .background(Theme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderSubtle))

                    // Context
                    fieldLabel("Context")
                    Picker("", selection: $selectedContextID) {
                        Text("None").tag(Optional<UUID>.none)
                        ForEach(allContexts) { ctx in
                            Label(ctx.name, systemImage: ctx.icon).tag(Optional(ctx.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .foregroundStyle(Theme.text)
                    .padding(8)
                    .background(Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderSubtle))

                    // Dates
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            fieldLabel("Start Date")
                            DatePicker("", selection: $startDate, displayedComponents: .date)
                                .labelsHidden()
                                .datePickerStyle(.compact)
                                .foregroundStyle(Theme.text)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            fieldLabel("End Date")
                            DatePicker("", selection: $endDate, in: startDate..., displayedComponents: .date)
                                .labelsHidden()
                                .datePickerStyle(.compact)
                                .foregroundStyle(Theme.text)
                        }
                    }

                    // Progress type
                    fieldLabel("Track Progress By")
                    Picker("", selection: $progressType) {
                        Text("Subtasks").tag(GoalProgressType.subtasks)
                        Text("Hours").tag(GoalProgressType.hours)
                    }
                    .pickerStyle(.segmented)

                    // Target hours (only when "hours")
                    if progressType == .hours {
                        HStack(spacing: 12) {
                            fieldLabel("Target Hours")
                            Spacer()
                            Stepper(
                                value: $targetHours,
                                in: 1...1000,
                                step: 5
                            ) {
                                Text("\(Int(targetHours)) hrs")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.text)
                            }
                        }
                    }

                    // Color
                    fieldLabel("Color")
                    ColorGrid(selected: $selectedColor)
                }
                .padding(24)
            }

            Divider().background(Theme.borderSubtle)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.cadencePlain)
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                Button("Create") { create() }
                    .buttonStyle(.cadencePlain)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Theme.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(title.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
            }
            .padding(16)
        }
        .frame(width: 420, height: 620)
        .background(Theme.surface)
    }

    @ViewBuilder
    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.dim)
            .kerning(0.8)
    }

    private func create() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let goal = Goal(title: trimmed)
        goal.desc = desc.trimmingCharacters(in: .whitespaces)
        goal.startDate = DateFormatters.dateKey(from: startDate)
        goal.endDate = DateFormatters.dateKey(from: endDate)
        goal.progressType = progressType
        goal.targetHours = progressType == .hours ? targetHours : 0
        goal.colorHex = selectedColor
        goal.order = allGoals.count

        if let ctxID = selectedContextID,
           let ctx = (try? modelContext.fetch(FetchDescriptor<Context>()))?.first(where: { $0.id == ctxID }) {
            goal.context = ctx
        }

        modelContext.insert(goal)
        dismiss()
    }
}
#endif
