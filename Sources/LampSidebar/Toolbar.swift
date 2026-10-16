import SwiftUI
import AppKit
import LampSidebarKit

/// What the chat sits on: the chat's paper before macOS 26, and nothing from then on, where the app lays the chat
/// on a pane of Liquid Glass (`LampSidebar` in LampSupport.swift) and the glass is what shows.
extension View {
    @ViewBuilder func chatGround() -> some View {
        if #available(macOS 26, *) { self } else { background(ChatLook.paper) }
    }
}

/// The buttons Lamp's window has in its toolbar, above the chat: what changes the wish (Undo, Share, Delete) on the
/// left, and what shows more of it (Agent Details, Versions, Wish Info) on the right, as the toolbar groups them.
/// Each does what its button in Lamp's window does: the sidebar only passes the click on.
struct ChatToolbar: View {
    @EnvironmentObject private var link: Link
    let state: SidebarState
    let toolbar: SidebarToolbar
    @State private var deleting = false
    /// The share button, where the share menu opens once Lamp has made the file.
    @State private var shareAnchor = Anchor()
    @State private var shared: UUID?

    var body: some View {
        HStack(spacing: 8) {
            ToolGroup {
                ToolButton("arrow.uturn.backward", "Undo Last Change") { link.send(.undo) }
                    .disabled(!toolbar.canUndo)
                    .help(toolbar.canUndo ? "Go back to the version before this one" : "Nothing to undo yet")
                Menu {
                    Button("Copy Wish File") { link.send(.copyWishFile) }
                    Button("Share…") { link.send(.share) }
                    Button("Export…") { link.send(.export) }
                } label: {
                    ToolSymbol("square.and.arrow.up", "Share Wish")
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .background(AnchorView(anchor: shareAnchor))
                .disabled(!toolbar.canShare)
                .help(toolbar.canShare ? "Send this wish to someone with Lamp" : "Nothing to share until it's made")
                ToolButton("trash", "Delete Wish") { deleting = true }
                    .help("Delete this wish")
            }
            Spacer(minLength: 0)
            ToolGroup {
                ToolButton("wrench.and.screwdriver", "Agent Details", on: toolbar.details) { link.send(.details(!toolbar.details)) }
                    .help("Agent details")
                ToolButton("clock.arrow.circlepath", "Versions", on: state.panel == .versions) {
                    link.send(.panel(state.panel == .versions ? nil : .versions))
                }
                .disabled(!toolbar.hasVersions)
                .help(toolbar.hasVersions ? "See earlier versions of this wish, name them, and go back to one"
                      : "No versions yet: each change Lamp makes is saved as one")
                ToolButton("info.circle", "Wish Info", on: state.panel == .info) {
                    link.send(.panel(state.panel == .info ? nil : .info))
                }
                .help(toolbar.usage.map { "Show usage, cost and models for this wish. \($0)" } ?? "Show usage, cost and models for this wish")
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .confirmationDialog("Delete “\(state.app)”?", isPresented: $deleting) {
            Button("Move to Trash", role: .destructive) { link.send(.delete) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The wish, its chat, its history and what it saved are moved to the Trash.")
        }
        .onAppear { shared = state.sharing?.id }
        .onChange(of: state.sharing?.id) { if let sharing = state.sharing { share(sharing) } }
    }

    /// The share menu, at the share button, for the file Lamp made (`SidebarState.sharing`). This process can't read
    /// Lamp's files, so the file comes whole and is kept here, where the service it's shared with reads it.
    private func share(_ sharing: SidebarSharing) {
        guard shared != sharing.id else { return }
        shared = sharing.id
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("share-\(sharing.id.uuidString)")
        let name = (sharing.file.name as NSString).lastPathComponent
        let url = folder.appendingPathComponent(name.isEmpty ? "Wish.lampapp" : name)
        guard (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil,
              (try? sharing.file.data.write(to: url)) != nil, let view = shareAnchor.view, view.window != nil else { return }
        NSSharingServicePicker(items: [url]).show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }
}

/// A group of the toolbar's buttons: on one capsule of glass from macOS 26, as the system's toolbars group theirs;
/// before it, round buttons side by side as the message box's row has them.
private struct ToolGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        if #available(macOS 26, *) {
            HStack(spacing: 0) { content }
                .padding(.horizontal, 4)
                .glassEffect(.regular.interactive(), in: Capsule())
        } else {
            HStack(spacing: 6) { content }
        }
    }
}

private struct ToolSymbol: View {
    let symbol: String
    let name: String
    var on = false
    @Environment(\.isEnabled) private var isEnabled

    init(_ symbol: String, _ name: String, on: Bool = false) {
        self.symbol = symbol
        self.name = name
        self.on = on
    }

    var body: some View {
        let side: CGFloat = 30
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(on ? AnyShapeStyle(Color.accentColor) : isEnabled ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
            .frame(width: side, height: side)
            .background {
                if #available(macOS 26, *) {
                    if on { Circle().fill(Color.accentColor.opacity(0.15)).padding(2) }
                } else {
                    Circle().fill(on ? AnyShapeStyle(Color.accentColor.opacity(0.15)) : AnyShapeStyle(Color(nsColor: .textBackgroundColor)))
                        .overlay(Circle().strokeBorder(Color(nsColor: .separatorColor)))
                }
            }
            .contentShape(Circle())
            .accessibilityLabel(name)
    }
}

private struct ToolButton: View {
    let symbol: String
    let name: String
    var on = false
    let action: () -> Void

    init(_ symbol: String, _ name: String, on: Bool = false, action: @escaping () -> Void) {
        self.symbol = symbol
        self.name = name
        self.on = on
        self.action = action
    }

    var body: some View {
        Button(action: action) { ToolSymbol(symbol, name, on: on) }
            .buttonStyle(.plain)
            .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// The view a menu or panel is shown from, found once it's on screen.
final class Anchor {
    weak var view: NSView?
}

private struct AnchorView: NSViewRepresentable {
    let anchor: Anchor

    final class Marker: NSView {
        // Behind its button, never in its way.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeNSView(context: Context) -> Marker {
        let view = Marker()
        anchor.view = view
        return view
    }

    func updateNSView(_ view: Marker, context: Context) { anchor.view = view }
}

/// The agent's steps with Agent Details on, as Lamp's window shows them: one step as it is, several summed up in a
/// line that opens to each of them.
struct ToolsLine: View {
    let line: SidebarLine
    @State private var expanded = false

    var body: some View {
        let calls = line.calls ?? []
        if calls.count == 1 {
            row(calls[0], running: line.running)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    withAnimation(.snappy(duration: 0.2)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Group {
                            if line.running { ProgressView().controlSize(.mini) } else { Image(systemName: line.symbol ?? "wrench.adjustable") }
                        }
                        .frame(width: 16)
                        Text(line.text)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if expanded {
                    ForEach(calls.indices, id: \.self) { index in
                        row(calls[index], running: line.running && index == calls.count - 1)
                    }
                    .padding(.leading, 10)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private func row(_ call: SidebarToolCall, running: Bool) -> some View {
        HStack(spacing: 6) {
            Group {
                if running { ProgressView().controlSize(.mini) } else { Image(systemName: call.symbol) }
            }
            .frame(width: 16)
            Text(call.verb)
            if !call.argument.isEmpty {
                Text(call.argument)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}

/// The Versions panel, in place of the chat: every saved version, newest first, with a picture of how the app
/// looked. Any of them can be named or gone back to, as in Lamp's window.
struct VersionsPanel: View {
    @EnvironmentObject private var link: Link
    let state: SidebarState
    @State private var selected: String?
    @State private var restoring: SidebarVersion?
    @State private var naming: SidebarVersion?
    @State private var name = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Versions").font(.headline)
                Spacer()
                Button("Name Current…") { if let current = state.versions?.first { startNaming(current) } }
                    .controlSize(.small)
                    .disabled(state.versions?.isEmpty ?? true)
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
            if let versions = state.versions, !versions.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(versions) { version in
                            row(version)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation(.snappy(duration: 0.2)) { selected = selected == version.id ? nil : version.id }
                                }
                        }
                    }
                    .padding(.horizontal, 12).padding(.bottom, 12)
                }
            } else {
                Spacer()
                if state.versions == nil {
                    ProgressView().controlSize(.small)
                } else {
                    Text("No versions yet").font(.headline)
                    Text("Lamp saves a version every time the app changes.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .confirmationDialog("Go back to “\(restoring?.label ?? "")”?", isPresented: Binding(
            get: { restoring != nil }, set: { if !$0 { restoring = nil } })) {
            Button("Go Back") { if let version = restoring { link.send(.goBackToVersion(version.id)) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The app is rebuilt as it was then. Later versions are kept, so you can undo this.")
        }
        .alert(naming?.named == true ? "Rename This Version" : "Name This Version", isPresented: Binding(
            get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField("Name", text: $name)
            Button("Save") { if let version = naming { link.send(.nameVersion(version.id, name)) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A name makes this version easy to find, and to go back to later.")
        }
    }

    private func startNaming(_ version: SidebarVersion) {
        name = version.named ? version.label : ""
        naming = version
    }

    private func row(_ version: SidebarVersion) -> some View {
        let expanded = selected == version.id
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                if !expanded { picture(version, width: 64, height: 42) }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        if version.named { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
                        Text(version.label)
                            .fontWeight(version.named ? .semibold : .regular)
                            .lineLimit(expanded ? nil : 2)
                    }
                    HStack(spacing: 4) {
                        if version.current { Text("Current").foregroundStyle(Color.accentColor) }
                        Text(version.date, format: .relative(presentation: .named))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            if expanded {
                picture(version, width: nil, height: nil)
                HStack {
                    Button(version.named ? "Rename…" : "Name…") { startNaming(version) }
                    Spacer()
                    if !version.current {
                        Button("Go Back to This Version") { restoring = version }
                            .buttonStyle(.borderedProminent)
                            .disabled(state.busy)
                    }
                }
                .controlSize(.small)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(expanded ? Color.accentColor.opacity(0.1) : .clear))
        .contextMenu {
            Button(version.named ? "Rename…" : "Name…") { startNaming(version) }
            if version.named { Button("Remove Name") { link.send(.nameVersion(version.id, "")) } }
            if !version.current {
                Divider()
                Button("Go Back to This Version") { restoring = version }.disabled(state.busy)
            }
        }
    }

    /// How the app looked, or a plain stand-in for versions from before pictures were kept.
    @ViewBuilder
    private func picture(_ version: SidebarVersion, width: CGFloat?, height: CGFloat?) -> some View {
        let shape = RoundedRectangle(cornerRadius: 5)
        if let data = version.picture, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: width == nil ? .fit : .fill)
                .frame(width: width, height: height)
                .clipShape(shape)
                .overlay(shape.strokeBorder(.separator))
        } else if width != nil {
            shape.fill(.quaternary)
                .frame(width: width, height: height)
                .overlay(Image(systemName: "macwindow").foregroundStyle(.tertiary))
        }
    }
}

/// The wish's info, in place of the chat: what it has cost, what answers its AI, how Lamp builds it and where it
/// lives, the same rows as Lamp's info panel. It chooses nothing: its buttons lead to where things are chosen.
struct InfoPanel: View {
    @EnvironmentObject private var link: Link
    let state: SidebarState

    var body: some View {
        Form {
            ForEach(state.info ?? []) { section in
                Section {
                    ForEach(section.rows, id: \.label) { row in
                        LabeledContent(row.label) {
                            if let value = row.value {
                                Text(value).textSelection(.enabled)
                            } else {
                                HStack(spacing: 4) { Image(systemName: "exclamationmark.circle.fill"); Text("Not Ready") }
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                } header: {
                    if let title = section.title { Text(title) }
                } footer: {
                    if !section.buttons.isEmpty {
                        // One under another: the panel is narrow.
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(section.buttons, id: \.action) { button in
                                Button(button.title) { link.send(.infoAction(button.action)) }
                            }
                        }
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .overlay {
            if state.info == nil { ProgressView().controlSize(.small) }
        }
    }
}
