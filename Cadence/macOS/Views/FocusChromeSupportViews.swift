#if os(macOS)
import SwiftUI

private struct FocusSurfaceHeader<Metadata: View>: View {
    let eyebrow: String
    let title: String
    let onClose: () -> Void
    @ViewBuilder let metadata: () -> Metadata

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                SectionEyebrowLabel(text: eyebrow)

                Text(title)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                metadata()
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }

            Spacer(minLength: 16)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 30, height: 30)
                    .background(Theme.surfaceElevated)
                    .clipShape(Circle())
            }
            .buttonStyle(.cadencePlain)
            .help("Close focus session")
        }
        .padding(.leading, 24)
        .padding(.trailing, 18)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .background(Theme.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.borderSubtle)
                .frame(height: 1)
        }
    }
}

private struct FocusMetaSeparator: View {
    var body: some View {
        Text("/")
            .foregroundStyle(Theme.dim.opacity(0.42))
    }
}

struct FocusSessionHeader: View {
    let task: AppTask
    let estimateLabel: String?
    let onClose: () -> Void

    var body: some View {
        let hasContainer = !task.containerName.isEmpty
        let hasPriority = task.priority != .none
        let hasDueDate = !task.dueDate.isEmpty
        let hasEstimate = estimateLabel != nil

        FocusSurfaceHeader(
            eyebrow: "Focus Session",
            title: TaskTitleSupport.displayTitle(task.title),
            onClose: onClose
        ) {
            HStack(spacing: 7) {
                if hasContainer {
                    Label {
                        Text(task.containerName)
                    } icon: {
                        Circle()
                            .fill(Color(hex: task.containerColor))
                            .frame(width: 6, height: 6)
                    }
                    if hasPriority || hasDueDate || hasEstimate { FocusMetaSeparator() }
                }

                if hasPriority {
                    Label {
                        Text(task.priority.label)
                    } icon: {
                        Circle()
                            .fill(Theme.priorityColor(task.priority))
                            .frame(width: 6, height: 6)
                    }
                    if hasDueDate || hasEstimate { FocusMetaSeparator() }
                }

                if hasDueDate {
                    Text("Due \(DateFormatters.relativeDate(from: task.dueDate))")
                    if hasEstimate { FocusMetaSeparator() }
                }

                if let estimateLabel {
                    Text(estimateLabel)
                        .lineLimit(1)
                }
            }
        }
    }
}

struct FocusBundleHeader: View {
    let bundle: TaskBundle
    let selectedCount: Int
    let onClose: () -> Void

    var body: some View {
        FocusSurfaceHeader(
            eyebrow: "Bundle Focus",
            title: bundle.displayTitle,
            onClose: onClose
        ) {
            HStack(spacing: 7) {
                Label {
                    Text(TimeFormatters.timeRange(startMin: bundle.startMin, endMin: bundle.endMin))
                } icon: {
                    Image(systemName: "tray.full")
                        .font(.system(size: 10, weight: .semibold))
                }
                FocusMetaSeparator()
                Text("\(selectedCount) selected")
                FocusMetaSeparator()
                Text("\(bundle.sortedTasks.count) total")
                if bundle.totalEstimatedMinutes > 0 {
                    FocusMetaSeparator()
                    Text("\(bundle.totalEstimatedMinutes)m estimated")
                }
            }
        }
    }
}

struct FocusTimerPanel<Controls: View>: View {
    let clockDisplay: String
    let isRunning: Bool
    let accent: Color
    @ViewBuilder let controls: () -> Controls

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Label(isRunning ? "Running" : "Paused", systemImage: isRunning ? "timer" : "pause.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isRunning ? accent : Theme.dim)
                Spacer()
            }

            Spacer(minLength: 0)

            Text(clockDisplay)
                .font(.system(size: 78, weight: .ultraLight, design: .monospaced))
                .foregroundStyle(isRunning ? Theme.text : Theme.muted)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .contentTransition(.numericText())
                .shadow(color: accent.opacity(isRunning ? 0.34 : 0), radius: 24)

            controls()

            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(Theme.surface)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(accent.opacity(isRunning ? 0.72 : 0.24))
                .frame(height: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusPanel, style: .continuous))
        .shadow(color: Theme.cardElevationShadow, radius: 16, x: 0, y: 6)
    }
}

struct FocusIconButton: View {
    let systemName: String
    let foreground: Color
    let background: Color
    let size: CGFloat
    var shadowColor: Color = .clear
    var shadowRadius: CGFloat = 0
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size > 44 ? 18 : 14, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .background(background)
                .clipShape(Circle())
                .shadow(color: shadowColor, radius: shadowRadius)
        }
        .buttonStyle(.cadencePlain)
        .help(help)
    }
}

#endif
