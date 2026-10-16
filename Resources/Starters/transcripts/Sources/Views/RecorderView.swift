import SwiftUI

/// The recorder: a big Record button, the level and running time while recording, and the transcript
/// appearing as it's heard.
struct RecorderView: View {
    @ObservedObject private var library = Library.shared
    @ObservedObject private var session = Library.shared.session

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 18) {
                RecordButton(phase: session.phase) { library.toggleRecording() }
                LevelMeter(levels: session.levels, isActive: session.isRecording)
                    .frame(maxWidth: 320)
                status
                    .frame(minHeight: 44, alignment: .top)
            }
            .padding(.top, 36)
            .padding(.horizontal, 24)

            if session.phase != .idle {
                Divider()
                LiveTranscript(lines: session.lines, volatile: session.volatileText, note: session.transcriptNote)
            } else {
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .navigationTitle("New Recording")
    }

    @ViewBuilder private var status: some View {
        switch session.phase {
        case .recording:
            if let startedAt = session.startedAt {
                TimelineView(.periodic(from: startedAt, by: 0.5)) { context in
                    Text(context.date.timeIntervalSince(startedAt).clock)
                        .font(.system(.title, design: .rounded).weight(.medium))
                        .monospacedDigit()
                }
                .accessibilityLabel("Recording time")
            }
        case .starting:
            Text(session.preparing ?? "Starting…").foregroundStyle(.secondary)
        case .finishing:
            Text("Finishing the transcript…").foregroundStyle(.secondary)
        case .idle:
            if let problem = session.problem {
                ProblemView(problem: problem)
            } else {
                Text("Record a meeting, a lecture or a voice memo.\nIt's transcribed on this Mac as you go.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct RecordButton: View {
    let phase: RecordingSession.Phase
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.red.gradient)
                    .frame(width: 84, height: 84)
                    .shadow(color: .red.opacity(0.35), radius: phase == .recording ? 14 : 6)
                if phase == .starting || phase == .finishing {
                    ProgressView().controlSize(.regular).tint(.white)
                } else {
                    // A square to stop, a dot to record, as on every recorder.
                    RoundedRectangle(cornerRadius: phase == .recording ? 6 : 15)
                        .fill(.white)
                        .frame(width: phase == .recording ? 28 : 30, height: phase == .recording ? 28 : 30)
                }
            }
            .animation(.spring(duration: 0.3), value: phase)
        }
        .buttonStyle(.plain)
        .disabled(phase == .starting || phase == .finishing)
        .accessibilityLabel(phase == .recording ? "Stop Recording" : "Start Recording")
        .help(phase == .recording ? "Stop recording (⌘R)" : "Start recording (⌘R)")
    }
}

/// Why a recording couldn't start, and the one thing that fixes it.
private struct ProblemView: View {
    let problem: RecordingSession.Problem

    var body: some View {
        VStack(spacing: 8) {
            switch problem {
            case .permission(let kind):
                Text("Transcripts needs \(kind.name) access, which is off in System Settings.")
                    .foregroundStyle(.secondary)
                Button("Open System Settings") { Permissions.openSettings(for: kind) }
            case .noMicrophone:
                Text("No microphone was found. Connect one, then press Record.")
                    .foregroundStyle(.secondary)
            case .failed(let message):
                Text(message).foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
    }
}

/// What's been heard so far, following the newest words.
private struct LiveTranscript: View {
    let lines: [TranscriptLine]
    let volatile: String
    let note: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let note {
                        Label(note, systemImage: "exclamationmark.bubble")
                            .foregroundStyle(.secondary)
                    } else if lines.isEmpty && volatile.isEmpty {
                        Text("Listening…").foregroundStyle(.tertiary)
                    }
                    ForEach(lines) { line in
                        TranscriptRow(line: line, isCurrent: false, canPlay: false) {}
                    }
                    if !volatile.isEmpty {
                        Text(volatile)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 58)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .onChange(of: lines.count) { proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: volatile) { proxy.scrollTo("end", anchor: .bottom) }
        }
    }
}
