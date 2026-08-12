import SwiftUI

/// The one goal-progress bar. Lived inside `macOS/Views/GoalsSupportViews.swift`, so iOS fell back
/// to a bare `ProgressView(value:)` — a stock control with a stock tint track that read as a
/// different app to the macOS bar sitting on the same data.
struct GoalProgressBar: View {
    let progress: Double
    let color: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.borderSubtle.opacity(0.75))
                if progress > 0 {
                    Capsule()
                        .fill(color)
                        .frame(width: max(height, geo.size.width * progress))
                }
            }
        }
        .frame(height: height)
    }
}
