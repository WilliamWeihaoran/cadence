#if os(macOS)
import SwiftUI
import SwiftData

struct CreateContextSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Context.order) private var contexts: [Context]

    @State private var name = ""
    /// `Context.colorHex`'s model default, read from the palette rather than re-typed. The model
    /// itself has to spell the hex — `CadenceMCPServer` compiles `Models/` and not `Theme.swift` —
    /// so this seed is the copy that can drift, and the one that must read the token (T-262).
    @State private var selectedColor = Theme.blueHex
    @State private var selectedIcon = "square.stack.fill"

    var body: some View {
        ListEditorSheetShell(
            title: "New Context",
            confirmTitle: "Create",
            isConfirmDisabled: CadenceTitleNormalization.isBlank(name),
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
            name: CadenceTitleNormalization.normalized(name),
            colorHex: selectedColor,
            icon: selectedIcon
        )
        ctx.order = CadenceOrderAllocation.nextOrder(after: contexts, order: \.order)
        modelContext.insert(ctx)
        dismiss()
    }
}

// MARK: - Color Grid

struct ColorGrid: View {
    @Binding var selected: String
    /// Which swatch menu this grid draws. `colors` is the list/goal/habit palette every caller but
    /// one wants; Settings → Sidebar's per-tab editor passes `destinationTints`, because a
    /// destination's glyph tint is app chrome rather than user-owned data and its defaults are
    /// `Theme` accents. Parameterised rather than forked — the grid's own "no second blue, no
    /// second green" rule below is what a second copy of this view would drift away from, and
    /// pointing the sidebar editor at the list palette is what put a second *teal* on screen
    /// (T-245).
    var palette: [String] = CadenceColorPalette.colors
    var columns: Int = 8
    var swatchSize: CGFloat = 28
    var spacing: CGFloat = 8

    /// One lap of the hue wheel plus a single neutral. A list's colour only earns its place if you
    /// can tell it apart from its neighbours in the sidebar, so the palette holds no second blue,
    /// no second green, and no second grey — the old 23 offered three near-identical greys and two
    /// near-whites, which is five swatches for one decision.
    var body: some View {
        LazyVGrid(
            columns: Array(repeating: .init(.fixed(swatchSize + 4), spacing: spacing), count: columns),
            spacing: spacing
        ) {
            ForEach(CadenceColorPalette.offered(selected, from: palette), id: \.self) { hex in
                let isSelected = CadenceColorPalette.matches(hex, selected)
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


    var columns: Int = 8
    var cellSize: CGFloat = 36
    var spacing: CGFloat = 6

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(cellSize), spacing: spacing), count: columns),
            spacing: spacing
        ) {
            ForEach(CadenceIconPalette.offeredIcons(for: selected), id: \.self) { icon in
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
