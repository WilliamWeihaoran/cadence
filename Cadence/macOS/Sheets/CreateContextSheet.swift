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
        ListEditorSheetShell(
            title: "New Context",
            confirmTitle: "Create",
            isConfirmDisabled: name.trimmingCharacters(in: .whitespaces).isEmpty,
            onConfirm: create
        ) {
            ListEditorIdentityHeader(
                name: $name,
                colorHex: $selectedColor,
                icon: $selectedIcon,
                placeholder: "e.g. Work, School, Personal"
            )
        }
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
    var columns: Int = 8
    var swatchSize: CGFloat = 28
    var spacing: CGFloat = 8

    /// One lap of the hue wheel plus a single neutral. A list's colour only earns its place if you
    /// can tell it apart from its neighbours in the sidebar, so the palette holds no second blue,
    /// no second green, and no second grey — the old 23 offered three near-identical greys and two
    /// near-whites, which is five swatches for one decision.
    static let colors = [
        "#4a9eff", "#6366f1", "#a78bfa", "#e879f9", "#f472b6", "#ff6b6b",
        "#ffa94d", "#fbbf24", "#4ecb71", "#14b8a6", "#06b6d4", "#6b7a99",
    ]

    /// Trimming the palette must not silently re-colour anything already saved: a stored hex that
    /// is no longer offered is appended so its owner still shows a selected swatch. It disappears
    /// from the grid as soon as the user picks something else.
    ///
    /// Static so the sheets' one-line colour strip obeys the same rule from the same source.
    static func offeredColors(for selected: String) -> [String] {
        let stored = selected.trimmingCharacters(in: .whitespaces)
        guard !stored.isEmpty, !colors.contains(where: { matches($0, stored) }) else {
            return colors
        }
        return colors + [stored]
    }

    static func matches(_ lhs: String, _ rhs: String) -> Bool {
        lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: .init(.fixed(swatchSize + 4), spacing: spacing), count: columns),
            spacing: spacing
        ) {
            ForEach(Self.offeredColors(for: selected), id: \.self) { hex in
                let isSelected = Self.matches(hex, selected)
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: swatchSize, height: swatchSize)
                    .overlay(
                        Circle()
                            .strokeBorder(Theme.onColor.opacity(isSelected ? 1 : 0), lineWidth: 2)
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(Color(hex: hex).opacity(0.4), lineWidth: 3)
                            .scaleEffect(isSelected ? 1.3 : 1)
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

    var columns: Int = 8
    var cellSize: CGFloat = 36
    var spacing: CGFloat = 6

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(cellSize), spacing: spacing), count: columns),
            spacing: spacing
        ) {
            ForEach(Self.icons, id: \.self) { icon in
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selected == icon ? Theme.blue.opacity(0.2) : Theme.surfaceElevated)
                    Image(systemName: icon)
                        .font(.system(size: cellSize * 0.44))
                        .foregroundStyle(selected == icon ? Theme.blue : Theme.dim)
                }
                .frame(width: cellSize, height: cellSize)
                .onTapGesture { selected = icon }
            }
        }
    }
}
#endif
