import SwiftUI

/// One-line task detail, shared by the focus rows, the bundle picker, and the **bundle member
/// rows on both platforms**. Renders as a single `Text` so it still collapses under
/// `lineLimit(1)`, while tinting only the due segment — an overdue task should read red on the
/// deadline, not on the scheduling note next to it.
///
/// This was `TaskDetailLineLabel` inside `#if os(macOS)`, which is the only reason iOS's bundle
/// member row wrote its own secondary line — and that copy showed priority and an estimate and
/// **no due date at all**, so a task inside a calendar block could be a week late and say nothing
/// about it. Nothing in here is AppKit; the guard was where the file happened to sit.
struct CadenceTaskDetailLineLabel: View {
    let parts: CadenceTaskDetailLine
    var fontSize: CGFloat = 10

    init(parts: CadenceTaskDetailLine, fontSize: CGFloat = 10) {
        self.parts = parts
        self.fontSize = fontSize
    }

    init(task: AppTask, fallback: String, fontSize: CGFloat = 10) {
        self.init(
            parts: CadenceFocusSupport.sidebarDetailParts(
                for: task,
                todayKey: DateFormatters.todayKey(),
                fallback: fallback
            ),
            fontSize: fontSize
        )
    }

    var body: some View {
        composed
            .font(.system(size: fontSize))
            .lineLimit(1)
    }

    /// One `Text`, not concatenated ones: `lineLimit(1)` has to collapse the whole line, and only
    /// the due segment is tinted so an overdue task cannot make its scheduling half look urgent too.
    private var composed: Text {
        var line = AttributedString()

        if let lead = parts.lead {
            var segment = AttributedString(lead)
            segment.foregroundColor = Theme.dim
            line += segment
        }

        if let due = parts.due {
            if !line.characters.isEmpty {
                var separator = AttributedString(" / ")
                separator.foregroundColor = Theme.dim
                line += separator
            }
            var segment = AttributedString(due)
            segment.foregroundColor = parts.isOverdue ? Theme.red : Theme.dim
            line += segment
        }

        return Text(line)
    }
}
