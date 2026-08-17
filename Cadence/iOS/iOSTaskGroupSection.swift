#if os(iOS)
import SwiftUI

/// A task group's header: the section eyebrow and how many rows are under it.
///
/// There were three private near-copies of this — one each in the compact Today, Inbox and All
/// Tasks views, at spacings 9/7, 9/7 and 10/8 — and the iPad versions of the same three screens
/// drew the eyebrow with no count at all. So "Active" told you how many on the phone and not on
/// the tablet, and the two phone screens that agreed only agreed by coincidence.
///
/// Usable as a `List` section header as well as inside a `VStack`, which is what lets the
/// `List`-hosted iPad panels and the `ScrollView`-hosted compact ones share it.
struct iOSTaskGroupHeader: View {
    let title: String
    let color: Color
    let count: Int

    var body: some View {
        HStack {
            iOSTaskSectionHeader(title: title, color: color)
            Spacer()
            Text("\(count)")
                .font(.system(size: 11, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(color.opacity(0.11))
                .clipShape(Capsule())
        }
    }
}

/// One counted group of task rows: `iOSTaskGroupHeader` over the rows it counts.
///
/// The spacings are the majority spelling of the three components this replaced (9 between the
/// header and the rows, 7 between rows); All Tasks' 10/8 was the odd one out.
struct iOSTaskGroupSection: View {
    let title: String
    let color: Color
    let tasks: [AppTask]
    /// The row density the hosting surface uses — Today's compact column packs its rows tighter
    /// than the full-page lists do.
    var density: iOSTaskRowDensity = .regular
    /// Completed groups are dimmed as a whole rather than row by row.
    var opacity: Double = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            iOSTaskGroupHeader(title: title, color: color, count: tasks.count)

            VStack(spacing: 7) {
                ForEach(tasks) { task in
                    iOSTaskRow(task: task, density: density)
                        .opacity(opacity)
                }
            }
        }
    }
}
#endif
