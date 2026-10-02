import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var store: Store
    @State private var showingNew = false

    var body: some View {
        if store.setup.checked && !store.setup.ready {
            SetupView()
        } else {
            main
        }
    }

    private var main: some View {
        NavigationSplitView {
            List(store.projects, selection: $store.selection) { project in
                HStack {
                    Label {
                        Text(project.name)
                    } icon: {
                        if let icon = store.icons[project.id] {
                            Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                        } else {
                            Image(systemName: "app.dashed")
                        }
                    }
                    Spacer()
                    if store.busy.contains(project.id) { ProgressView().controlSize(.mini) }
                }
                .tag(project.id)
                .contextMenu {
                    Button("New Icon") { Task { await store.newIcon(project) } }
                        .disabled(store.busy.contains(project.id))
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([project.installedURL])
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .overlay {
                if store.projects.isEmpty {
                    ContentUnavailableView("No apps yet", systemImage: "hammer",
                                           description: Text("Click + to forge one."))
                }
            }
            .toolbar {
                Button { showingNew = true } label: { Label("New App", systemImage: "plus") }
            }
        } detail: {
            if let project = store.selected {
                ProjectView(project: project).id(project.id)
            } else {
                ContentUnavailableView("Select an app", systemImage: "sidebar.left")
            }
        }
        .sheet(isPresented: $showingNew) { NewAppSheet() }
    }
}

struct ProjectView: View {
    @EnvironmentObject private var store: Store
    let project: ForgeProject
    @State private var draft = ""
    @FocusState private var focused: Bool
    @AppStorage("showDetails") private var showDetails = false

    private var lines: [LogLine] {
        (store.logs[project.id] ?? []).filter { showDetails || $0.kind != .detail }
    }
    private var busy: Bool { store.busy.contains(project.id) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if lines.isEmpty {
                            Text("Describe what \(project.name) should do, or what to change. Forge builds it and opens it for you. While using the app, press ⇧⌘E to come back here and ask for changes.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(lines) { LogRow(line: $0) }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding()
                }
                .onChange(of: lines.count) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            Divider()
            HStack(alignment: .bottom, spacing: 8) {
                TextField(busy ? "Working…" : "Describe a change…", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .focused($focused)
                    .onSubmit(send)
                if busy {
                    ProgressView().controlSize(.small)
                    Text("Working…").foregroundStyle(.secondary)
                } else {
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                    .buttonStyle(.plain)
                    .disabled(draft.trimmed.isEmpty)
                }
            }
            .padding(12)
        }
        .navigationTitle(project.name)
        .navigationSubtitle(usageSummary)
        .toolbar {
            Button { Task { await store.run(project) } } label: {
                Label("Open App", systemImage: "play.fill")
            }
            .disabled(busy)
            Button { Task { await store.undo(project) } } label: {
                Label("Undo Last Change", systemImage: "arrow.uturn.backward")
            }
            .disabled(busy)
            Toggle(isOn: $showDetails) {
                Label("Show Details", systemImage: "terminal")
            }
            .help("Show what the agent is doing under the hood")
        }
        .onAppear { focused = true }
        .onChange(of: store.chatFocusRequest) { focused = true }
    }

    private var usageSummary: String {
        guard let usage = store.usage[project.id], usage.calls > 0 else { return "" }
        return String(format: "AI: %d call%@ · $%.2f", usage.calls, usage.calls == 1 ? "" : "s", usage.cost)
    }

    private func send() {
        let text = draft.trimmed
        guard !text.isEmpty, !busy else { return }
        draft = ""
        Task { await store.send(text, to: project) }
    }
}

struct LogRow: View {
    let line: LogLine

    var body: some View {
        switch line.kind {
        case .user:
            Text(line.text)
                .textSelection(.enabled)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: .infinity, alignment: .trailing)
        case .agent:
            Text((try? AttributedString(markdown: line.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                 ?? AttributedString(line.text))
                .textSelection(.enabled)
        case .status:
            Label(line.text, systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .error:
            Label(line.text, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        case .detail:
            Text(line.text)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(12)
        }
    }
}

struct NewAppSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var brief = ""

    var body: some View {
        Form {
            TextField("Name", text: $name, prompt: Text("Standup Notes"))
            TextField("What should it do?", text: $brief,
                      prompt: Text("Optional: a menu of today's meetings with a notes field for each"),
                      axis: .vertical)
                .lineLimit(3...8)
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") {
                    store.create(name: name, brief: brief)
                    dismiss()
                }
                .disabled(name.trimmed.isEmpty)
            }
        }
    }
}
