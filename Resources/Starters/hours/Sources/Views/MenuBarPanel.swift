import SwiftUI

/// The menu bar icon: an hourglass, or while a timer runs, the client's color and the time so far.
struct MenuBarLabel: View {
    @ObservedObject var model: HoursModel
    @ObservedObject var ticker: Ticker

    var body: some View {
        if let running = model.running, let client = model.client(running.clientID) {
            Image(nsImage: Self.dot(client.nsTint))
                .accessibilityLabel("Timer for \(client.name)")
            Text(Format.clock(running.duration(now: ticker.now)))
                .monospacedDigit()
        } else {
            Image(systemName: "hourglass").accessibilityLabel("Hours")
        }
    }

    /// The menu bar draws its images as one-color templates; a drawn image that isn't a template keeps its color.
    static func dot(_ color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}

/// The panel under the menu bar icon: the running timer with its note, and one click to start one for any
/// client (which stops whatever was running).
struct MenuBarPanel: View {
    @EnvironmentObject private var model: HoursModel
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            runningTimer
            Divider()
            if model.clients.isEmpty {
                Text("Add a client in the Hours window to start tracking.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text("Start a timer").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                VStack(spacing: 2) {
                    ForEach(model.clients) { client in
                        ClientStartButton(client: client, isRunning: model.running?.clientID == client.id) {
                            saveNote()
                            model.startTimer(for: client.id)
                        }
                    }
                }
            }
            Divider()
            HStack {
                Button("Open Hours") {
                    LampMenuBar.close()
                    LampWindows.show()
                }
                Spacer()
                Button { LampMenuBar.openSettings() } label: { Image(systemName: "gearshape") }
                    .help("Settings")
                    .accessibilityLabel("Settings")
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                    .help("Quit Hours")
                    .accessibilityLabel("Quit Hours")
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 290)
        .onAppear { note = model.running?.note ?? "" }
        .onChange(of: model.running?.id) { note = model.running?.note ?? "" }
    }

    @ViewBuilder private var runningTimer: some View {
        if let running = model.running, let client = model.client(running.clientID) {
            HStack(alignment: .firstTextBaseline) {
                Circle().fill(client.tint).frame(width: 10, height: 10)
                Text(client.name).font(.headline).lineLimit(1)
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Format.clock(running.duration(now: context.date), withSeconds: true))
                        .font(.title2.weight(.semibold)).monospacedDigit()
                }
            }
            HStack {
                TextField("What are you working on?", text: $note)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(saveNote)
                Button("Stop") {
                    saveNote()
                    model.stopTimer()
                }
                .keyboardShortcut(.defaultAction)
            }
        } else {
            Label("No timer running", systemImage: "hourglass")
                .foregroundStyle(.secondary)
        }
    }

    private func saveNote() {
        guard var running = model.running, running.note != note else { return }
        running.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        model.save(running)
    }
}

/// A client row in the panel: a click starts its timer.
private struct ClientStartButton: View {
    let client: Client
    let isRunning: Bool
    let start: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: start) {
            HStack {
                Circle().fill(client.tint).frame(width: 9, height: 9)
                Text(client.name).lineLimit(1)
                Spacer()
                Image(systemName: isRunning ? "timer" : "play.fill")
                    .foregroundStyle(isRunning ? client.tint : .secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(hovering ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .disabled(isRunning)
        .onHover { hovering = $0 }
        .accessibilityLabel(isRunning ? "\(client.name), running" : "Start timer for \(client.name)")
    }
}
