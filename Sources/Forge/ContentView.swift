import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var store: Store
    @State private var showingNew = false

    var body: some View {
        Group {
            if store.setup.checked && !store.setup.ready {
                SetupView()
            } else {
                main
            }
        }
        .sheet(item: $store.pendingImport) { pending in
            ImportReviewView(pending: pending)
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
                    Divider()
                    Button("Copy App File") { store.copyAppFile(project) }
                    ShareLink("Share…", item: SharedApp(project: project),
                              preview: SharePreview(project.name, image: Image(systemName: "app.gift")))
                    Button("Export…") { store.chooseExport(project) }
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
            .safeAreaInset(edge: .bottom) {
                HStack {
                    SettingsLink { Label("Settings", systemImage: "gearshape") }
                        .buttonStyle(.borderless)
                        .help("Settings (⌘,)")
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
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
    @State private var attachments: [URL] = []
    @State private var composerHeight: CGFloat = 24
    @State private var focusRequest = 0
    @State private var dropTargeted = false
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
                        ForEach(lines) { LogRow(line: $0, dir: project.dir) }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding()
                }
                .onChange(of: lines.count) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            Divider()
            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(attachments, id: \.self) { url in
                            AttachmentChip(url: url) { attachments.removeAll { $0 == url } }
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.top, 8)
            }
            HStack(alignment: .bottom, spacing: 8) {
                Button(action: chooseFiles) { Image(systemName: "paperclip").font(.title3) }
                    .buttonStyle(.borderless)
                    .help("Attach files. You can also paste or drop images and files here.")
                    .padding(.bottom, 2)
                Composer(text: $draft, height: $composerHeight,
                         placeholder: busy ? "Working…" : "Describe a change…  (Shift-Return for a new line)",
                         isEnabled: true, focusRequest: focusRequest,
                         onSubmit: send, onFiles: { attachments.append(contentsOf: $0) })
                    .frame(height: composerHeight)
                if busy {
                    ProgressView().controlSize(.small)
                    Text("Working…").foregroundStyle(.secondary)
                } else {
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                    .buttonStyle(.plain)
                    .disabled(draft.trimmed.isEmpty && attachments.isEmpty)
                }
            }
            .padding(12)
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor, lineWidth: 3).padding(4)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url { DispatchQueue.main.async { attachments.append(url) } }
                }
            }
            return true
        }
        .navigationTitle(project.name)
        .navigationSubtitle(usageSummary)
        .toolbar {
            Button { Task { await store.run(project) } } label: {
                Label("Open App", systemImage: "play.fill")
            }
            .disabled(busy)
            Menu {
                Button("Copy App File") { store.copyAppFile(project) }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                ShareLink("Share…", item: SharedApp(project: project),
                          preview: SharePreview(project.name, image: Image(systemName: "app.gift")))
                Button("Export…") { store.chooseExport(project) }
            } label: {
                Label("Share App", systemImage: "square.and.arrow.up")
            }
            .help("Send this app to someone with Forge")
            Button { Task { await store.undo(project) } } label: {
                Label("Undo Last Change", systemImage: "arrow.uturn.backward")
            }
            .disabled(busy)
            Toggle(isOn: $showDetails) {
                Label("Show Details", systemImage: "terminal")
            }
            .help("Show what the agent is doing under the hood")
        }
        .onAppear { focusRequest += 1 }
        .onChange(of: store.chatFocusRequest) { focusRequest += 1 }
    }

    private var usageSummary: String {
        guard let usage = store.usage[project.id], usage.calls > 0 else { return "" }
        return String(format: "AI: %d call%@ · $%.2f", usage.calls, usage.calls == 1 ? "" : "s", usage.cost)
    }

    private func send() {
        let text = draft.trimmed
        guard !text.isEmpty || !attachments.isEmpty, !busy else { return }
        let files = attachments
        draft = ""
        attachments = []
        Task { await store.send(text.isEmpty ? "Use the attached files." : text, attachments: files, to: project) }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Attach screenshots, mockups, images, data or documents"
        if panel.runModal() == .OK { attachments.append(contentsOf: panel.urls) }
    }
}

struct LogRow: View {
    let line: LogLine
    let dir: URL

    var body: some View {
        switch line.kind {
        case .user:
            VStack(alignment: .trailing, spacing: 6) {
                if let names = line.attachments, !names.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(names, id: \.self) { name in
                            let url = dir.appendingPathComponent(Attachments.folder).appendingPathComponent(name)
                            Button { NSWorkspace.shared.open(url) } label: {
                                if Attachments.isImage(url) {
                                    AttachmentThumbnail(url: url, size: 72)
                                } else {
                                    AttachmentChip(url: url)
                                }
                            }
                            .buttonStyle(.plain)
                            .help(name)
                        }
                    }
                }
                Text(line.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            }
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

/// Shown before building an app someone else shared: what it does, what it can access, and any red flags.
struct ImportReviewView: View {
    @EnvironmentObject private var store: Store
    let pending: Store.PendingImport

    private var review: ImportReview? { pending.review }
    private var highRisk: Bool { review?.risk == "high" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Open “\(pending.package.name)”?").font(.title2.bold())
            Text("Someone shared this app with you. Forge will build it and open it on your Mac, where it can do anything an app you run can do.")
                .foregroundStyle(.secondary)

            if let review {
                if !review.summary.isEmpty {
                    section("What it does") { Text(review.summary) }
                }
                if !review.detected.isEmpty || !review.capabilities.isEmpty {
                    section("What it can access") {
                        ForEach(review.detected + review.capabilities.filter { !review.detected.contains($0) }, id: \.self) {
                            Label($0, systemImage: "checkmark.shield").labelStyle(.titleAndIcon)
                        }
                    }
                }
                if !pending.package.attachments.isEmpty {
                    section("Included files") {
                        Text(pending.package.attachments.map(\.lastPathComponent).joined(separator: ", "))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                if !review.concerns.isEmpty {
                    section("Concerns") {
                        ForEach(review.concerns, id: \.self) {
                            Label($0, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        }
                    }
                }
                riskBadge(review.risk)
                if let note = review.note {
                    Text(note).font(.callout).foregroundStyle(.secondary)
                }
                Text("Forge's check is a guide, not a guarantee. Only open apps from people you trust.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Checking what this app does…").foregroundStyle(.secondary)
                }
                .padding(.vertical, 20)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { store.cancelImport() }
                    .keyboardShortcut(highRisk || review == nil ? .defaultAction : .cancelAction)
                Button(highRisk ? "Open Anyway" : "Build & Open", role: highRisk ? .destructive : nil) {
                    store.confirmImport()
                }
                .disabled(review == nil)
                .keyboardShortcut(highRisk || review == nil ? .cancelAction : .defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
        }
    }

    private func riskBadge(_ risk: String) -> some View {
        let (text, color, icon): (String, Color, String) = switch risk {
        case "low": ("Looks safe", .green, "checkmark.seal.fill")
        case "medium": ("Powerful, check it's what you expect", .yellow, "exclamationmark.circle.fill")
        case "high": ("Looks risky. Don't open unless you trust the sender", .red, "xmark.octagon.fill")
        default: ("Not checked by AI", .secondary, "questionmark.circle")
        }
        return Label(text, systemImage: icon)
            .font(.callout.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}
