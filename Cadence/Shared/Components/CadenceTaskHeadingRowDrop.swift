import SwiftUI

/// **A task row dragged over a group heading, and the line that says "here" ([[T-18062]]).**
///
/// Four headings take a dropped row: the Mac's All Tasks / Inbox groups (`TasksListSectionView`),
/// Today's list groups (`TasksPanelIntentSectionView`), a list's Tasks tab
/// (`ListTasksGroupSectionView`, [[T-5840]]), and iOS's grouped headings (`iOSTaskGroupHeader`,
/// [[T-16654]] / [[T-16682]]). Each was a bare `.dropDestination` with no `isTargeted:`, so the blue
/// insertion line followed a dragged row down the list and vanished at the one target that moves a
/// task's list, date or priority. They all come through here now, so the four cannot drift apart.
///
/// **The treatment: a 2pt line in the group's own tint along the foot of the heading,** where the
/// group's first row begins. Chosen over a heading-wide wash for three reasons: it is the row
/// insertion line's own vocabulary (2pt, the same 0.15s fade), so a drag reads as one continuous
/// gesture from row to heading; the Mac's heading regions carry their 16-20pt top gap inside the
/// drop region, which a wash would paint as a slab of empty colour; and a line at the group's top
/// is literally where a list Tasks tab heading files the row. The tint rather than the row line's
/// blue, because what a heading drop changes is *which group* the task is in, and the tint is how
/// the heading already names its group -- the row line's blue stays the colour of "reorder here".
///
/// **Registered only when there is a handler** -- a heading that refuses a row (Overdue, Leftover,
/// Due Today, the ungrouped "Tasks") registers no destination and draws nothing, rather than
/// lighting up and then refusing (T-591's silent accept, in reverse).
struct CadenceTaskHeadingRowDrop: ViewModifier {
    let tint: Color
    /// The heading's own horizontal inset, so the line spans the heading and not the padding the
    /// host wrapped it in.
    let horizontalInset: CGFloat
    /// Answers whether the dropped row was filed. `nil` registers nothing.
    let onDrop: ((String) -> Bool)?

    @State private var isTargeted = false

    static let lineHeight: CGFloat = 2

    @ViewBuilder
    func body(content: Content) -> some View {
        if let onDrop {
            content
                .overlay(alignment: .bottom) {
                    if isTargeted {
                        Rectangle()
                            .fill(tint)
                            .frame(height: Self.lineHeight)
                            .padding(.horizontal, horizontalInset)
                            .transition(.opacity)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: isTargeted)
                .dropDestination(for: String.self) { items, _ in
                    guard let payload = items.first else { return false }
                    return onDrop(payload)
                } isTargeted: { isTargeted = $0 }
        } else {
            content
        }
    }
}

extension View {
    /// See `CadenceTaskHeadingRowDrop`.
    func cadenceTaskHeadingRowDrop(
        tint: Color,
        horizontalInset: CGFloat = 0,
        onDrop: ((String) -> Bool)?
    ) -> some View {
        modifier(CadenceTaskHeadingRowDrop(tint: tint, horizontalInset: horizontalInset, onDrop: onDrop))
    }
}
