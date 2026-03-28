#if os(macOS)
import SwiftUI
import SwiftData
import Combine

struct FocusView: View {
    @Environment(FocusManager.self) private var focusManager
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]

    @State private var noteContent = ""
    @State private var showTaskPicker = false
    @State private var elapsed = 0  // stopwatch only

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HSplitView {
            timerPanel
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)

            VStack(spacing: 0) {
                HStack {
                    Text("Session Notes")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Theme.surface)
                Divider().background(Theme.borderSubtle)
                MarkdownEditorView(text: $noteContent)
            }
            .frame(minWidth: 300)

            SchedulePanel()
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 320)
        }
        .background(Theme.bg)
        .onReceive(timer) { _ in
            guard focusManager.isRunning else { return }
            if focusManager.mode == .stopwatch {
                elapsed += 1
            } else if focusManager.timerSeconds > 0 {
                focusManager.timerSeconds -= 1
            } else {
                focusManager.isRunning = false
            }
        }
    }

    // MARK: - Timer Panel

    private var timerPanel: some View {
        VStack(spacing: 0) {
            // Mode selector
            VStack(spacing: 16) {
                HStack(spacing: 2) {
                    ForEach(FocusManager.TimerMode.allCases, id: \.self) { m in
                        Button(m.rawValue) {
                            focusManager.mode = m
                            elapsed = 0
                            focusManager.reset()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: focusManager.mode == m ? .semibold : .regular))
                        .foregroundStyle(focusManager.mode == m ? Theme.blue : Theme.dim)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(focusManager.mode == m ? Theme.blue.opacity(0.12) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }

                // Big timer
                Text(timerDisplay)
                    .font(.system(size: 68, weight: .thin, design: .monospaced))
                    .foregroundStyle(focusManager.isRunning ? Theme.text : Theme.muted)
                    .monospacedDigit()

                // Progress ring (non-stopwatch)
                if focusManager.mode != .stopwatch {
                    ZStack {
                        Circle()
                            .stroke(Theme.borderSubtle, lineWidth: 4)
                            .frame(width: 100, height: 100)
                        Circle()
                            .trim(from: 0, to: timerProgress)
                            .stroke(Theme.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .frame(width: 100, height: 100)
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 1), value: timerProgress)
                    }
                }
            }
            .padding(.top, 28)
            .padding(.bottom, 20)

            // Controls
            HStack(spacing: 16) {
                Button { elapsed = 0; focusManager.reset() } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 42, height: 42)
                        .background(Theme.surfaceElevated)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Button { focusManager.isRunning.toggle() } label: {
                    Image(systemName: focusManager.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .background(Theme.blue)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Button {
                    if focusManager.mode == .stopwatch {
                        elapsed += 300
                    } else {
                        focusManager.timerSeconds = max(0, focusManager.timerSeconds - 300)
                    }
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 42, height: 42)
                        .background(Theme.surfaceElevated)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 28)

            Divider().background(Theme.borderSubtle)

            // Active task
            VStack(alignment: .leading, spacing: 8) {
                Text("FOCUSING ON")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .kerning(0.8)

                if let task = focusManager.activeTask {
                    HStack(spacing: 8) {
                        Circle().fill(Theme.blue).frame(width: 6, height: 6)
                        Text(task.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.text)
                            .lineLimit(2)
                        Spacer()
                        Button { focusManager.activeTask = nil } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.dim)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Button { showTaskPicker = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle").font(.system(size: 12))
                            Text("Pick a task").font(.system(size: 12))
                        }
                        .foregroundStyle(Theme.dim)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(Theme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
        }
        .background(Theme.surface)
        .popover(isPresented: $showTaskPicker) {
            FocusTaskPicker(tasks: allTasks.filter { !$0.isDone && !$0.isCancelled }) { task in
                focusManager.activeTask = task
                showTaskPicker = false
            }
        }
    }

    // MARK: - Helpers

    private var timerDisplay: String {
        let secs = focusManager.mode == .stopwatch ? elapsed : focusManager.timerSeconds
        let h = secs / 3600
        let m = (secs % 3600) / 60
        let s = secs % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    private var timerProgress: Double {
        let total: Double
        switch focusManager.mode {
        case .pomodoro:   total = 25 * 60
        case .fiftyTwo:   total = 52 * 60
        case .custom:     total = Double(focusManager.customMinutes * 60)
        case .stopwatch:  return 0
        }
        guard total > 0 else { return 0 }
        return max(0, 1.0 - Double(focusManager.timerSeconds) / total)
    }
}

// MARK: - Task Picker Popover

private struct FocusTaskPicker: View {
    let tasks: [AppTask]
    let onSelect: (AppTask) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("Pick a Task")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
                .padding(12)
            Divider().background(Theme.borderSubtle)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(tasks) { task in
                        Button { onSelect(task) } label: {
                            Text(task.title)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Theme.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
            }
        }
        .frame(width: 260, height: 320)
        .background(Theme.surface)
    }
}
#endif
