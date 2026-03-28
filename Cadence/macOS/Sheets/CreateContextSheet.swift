#if os(macOS)
import SwiftUI
import SwiftData

struct CreateContextSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Context.order) private var contexts: [Context]

    @State private var name = ""
    @State private var selectedColor = "#4a9eff"
    @State private var selectedIcon = "square.stack.fill"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("New Context")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)

            Divider().background(Theme.borderSubtle)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    fieldLabel("Name")
                    TextField("e.g. Work, School, Personal", text: $name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.text)
                        .padding(10)
                        .background(Theme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderSubtle))

                    fieldLabel("Color")
                    ColorGrid(selected: $selectedColor)

                    fieldLabel("Icon")
                    IconGrid(selected: $selectedIcon)
                }
                .padding(24)
            }

            Divider().background(Theme.borderSubtle)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                Button("Create") { create() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Theme.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
            }
            .padding(16)
        }
        .frame(width: 420, height: 620)
        .background(Theme.surface)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.dim)
            .kerning(0.8)
    }

    private func create() {
        let ctx = Context(
            name: name.trimmingCharacters(in: .whitespaces),
            colorHex: selectedColor,
            icon: selectedIcon
        )
        ctx.order = contexts.count
        modelContext.insert(ctx)
        dismiss()
    }
}

// MARK: - Color Grid

struct ColorGrid: View {
    @Binding var selected: String

    static let colors = [
        // Blues & purples
        "#4a9eff", "#2563eb", "#6366f1", "#a78bfa", "#c084fc",
        // Greens
        "#4ecb71", "#22c55e", "#34d399", "#14b8a6",
        // Reds & pinks
        "#ff6b6b", "#ef4444", "#f472b6", "#e879f9",
        // Ambers & oranges
        "#ffa94d", "#fb923c", "#f59e0b", "#fbbf24",
        // Cyans & teals
        "#38bdf8", "#06b6d4",
        // Neutrals
        "#94a3b8", "#6b7a99", "#e2e8f0", "#ffffff",
    ]

    var body: some View {
        LazyVGrid(columns: Array(repeating: .init(.fixed(32)), count: 8), spacing: 8) {
            ForEach(Self.colors, id: \.self) { hex in
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Circle()
                            .strokeBorder(.white.opacity(selected == hex ? 1 : 0), lineWidth: 2)
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(Color(hex: hex).opacity(0.4), lineWidth: 3)
                            .scaleEffect(selected == hex ? 1.3 : 1)
                    )
                    .onTapGesture { selected = hex }
            }
        }
    }
}

// MARK: - Icon Grid

struct IconGrid: View {
    @Binding var selected: String

    static let icons = [
        // Organization
        "square.stack.fill", "folder.fill", "tray.fill", "archivebox.fill",
        "doc.fill", "doc.text.fill", "checklist", "list.bullet.clipboard",
        // Work & study
        "briefcase.fill", "graduationcap.fill", "book.fill", "pencil",
        "chart.bar.fill", "chart.line.uptrend.xyaxis", "lightbulb.fill", "brain",
        // Home & life
        "house.fill", "heart.fill", "person.fill", "person.2.fill",
        "star.fill", "bookmark.fill", "flag.fill", "tag.fill",
        // Activities
        "dumbbell.fill", "flame.fill", "leaf.fill", "drop.fill",
        "music.note", "headphones", "gamecontroller.fill", "paintbrush.fill",
        // Travel & places
        "airplane", "car.fill", "map.fill", "globe",
        // Other
        "bolt.fill", "camera.fill", "cart.fill", "stethoscope",
        "trophy.fill", "medal.fill", "crown.fill", "building.2.fill",
    ]

    let columns = Array(repeating: GridItem(.fixed(40)), count: 8)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Self.icons, id: \.self) { icon in
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selected == icon ? Theme.blue.opacity(0.2) : Theme.surfaceElevated)
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundStyle(selected == icon ? Theme.blue : Theme.dim)
                }
                .frame(width: 36, height: 36)
                .onTapGesture { selected = icon }
            }
        }
    }
}
#endif
