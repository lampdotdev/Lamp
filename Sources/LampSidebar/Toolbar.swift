import SwiftUI
import AppKit
import LampSidebarKit

/// What the chat sits on: the chat's paper, opaque, as the app's card under it is (`LampSidebar.Paper` in
/// LampSupport.swift).
extension View {
    func chatGround() -> some View { background(ChatLook.paper) }
}

/// The bar at the top of the chat, one row: the red button that closes the chat, what the chat is for, and its
/// buttons. Where the title and every button fit, they're all there; where they don't, Undo stays and a button for the
/// rest takes their place, which pressed stays lit and puts them in the title's place: Wish Info, Share, Agent Details,
/// Delete and Versions. Each does what its button in Lamp's window does: the sidebar only passes the click on. Closing
/// and the room between the buttons, which moves the chat, are the app's to do (`Host`): the panel is its window.
struct ChatBar: View {
    @EnvironmentObject private var link: Link
    /// Nil until Lamp is there: the bar still closes and moves the chat.
    let state: SidebarState?
    @State private var more = false
    @State private var deleting = false
    @State private var moving = false
    /// The share button, where the share menu opens once Lamp has made the file.
    @State private var shareAnchor = Anchor()

    var body: some View {
        Group {
            if let state, let toolbar = state.toolbar {
                ViewThatFits(in: .horizontal) {
                    // Wide enough for the whole title and every button.
                    HStack(spacing: 8) {
                        CloseLight { Host.closeChat() }
                        title(state).fixedSize()
                        Spacer(minLength: 0)
                        ToolGroup { rest(state, toolbar) }
                        ToolGroup { undo(toolbar); versions(state, toolbar) }
                    }
                    HStack(spacing: 8) {
                        CloseLight { Host.closeChat() }
                        if more {
                            Spacer(minLength: 0)
                            ToolGroup { rest(state, toolbar) }
                                .transition(.opacity.combined(with: .move(edge: .trailing)))
                        } else {
                            title(state).frame(maxWidth: .infinity)
                        }
                        ToolGroup {
                            undo(toolbar)
                            if more { versions(state, toolbar) }
                            // Its own symbol says it's on (filled), so it has no lit circle behind it.
                            ToolButton(more ? "ellipsis.rectangle.fill" : "ellipsis.rectangle", more ? "Fewer Buttons" : "More Buttons",
                                       on: more, plain: true) {
                                withAnimation(.snappy(duration: 0.2)) { more.toggle() }
                            }
                            .help(more ? "Show the title again" : "Wish info, sharing, agent details, delete and versions")
                            // Changed where it stands, the symbol simply filled: not faded or slid in as a new button.
                            .transaction { $0.animation = nil }
                        }
                    }
                }
            } else {
                HStack(spacing: 8) {
                    CloseLight { Host.closeChat() }
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(height: 36)
        .padding(.horizontal, 12)
        .padding(.top, 8).padding(.bottom, 6)
        // Pressing anywhere on the bar but a button and dragging moves the chat, as a title bar moves its window. The
        // app moves it from here on, following the pointer until the button is let go.
        .background {
            Color.clear.contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .onChanged { _ in
                        if !moving { moving = true; Host.startMove() }
                    }
                    .onEnded { _ in moving = false })
        }
        .confirmationDialog("Delete “\(state?.app ?? "")”?", isPresented: $deleting) {
            Button("Move to Trash", role: .destructive) { link.send(.delete) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The wish, its chat, its history and what it saved are moved to the Trash.")
        }
        .onChange(of: link.sharing?.id) {
            if let sharing = link.sharing { share(sharing) }
            link.sharing = nil
        }
    }

    /// Lamp's icon and name before the app's: the chat sits beside someone else's window, so it says whose it is.
    private func title(_ state: SidebarState) -> some View {
        HStack(spacing: 6) {
            Button { link.send(.showLamp) } label: { ChatLook.LampMark(side: 18) }
                .buttonStyle(.plain)
                .help("Open Lamp")
                .accessibilityLabel("Open Lamp")
            Text("Lamp: \(state.app)")
                .font(.system(size: NSFont.systemFontSize, weight: .semibold))
                .lineLimit(1).truncationMode(.tail)
                // The title is part of the room to drag the chat by.
                .allowsHitTesting(false)
        }
    }

    private func undo(_ toolbar: SidebarToolbar) -> some View {
        ToolButton("arrow.uturn.backward", "Undo Last Change") { link.send(.undo) }
            .disabled(!toolbar.canUndo)
            .help(toolbar.canUndo ? "Go back to the version before this one" : "Nothing to undo yet")
    }

    private func versions(_ state: SidebarState, _ toolbar: SidebarToolbar) -> some View {
        ToolButton("clock.arrow.circlepath", "Versions", on: state.panel == .versions) {
            link.send(.panel(state.panel == .versions ? nil : .versions))
        }
        .disabled(!toolbar.hasVersions)
        .help(toolbar.hasVersions ? "See earlier versions of this wish, name them, and go back to one"
              : "No versions yet: each change Lamp makes is saved as one")
    }

    /// What the button for the rest shows (Versions goes beside Undo, the two being about the same thing).
    @ViewBuilder private func rest(_ state: SidebarState, _ toolbar: SidebarToolbar) -> some View {
        ToolButton("info.circle", "Wish Info", on: state.panel == .info) {
            link.send(.panel(state.panel == .info ? nil : .info))
        }
        .help(toolbar.usage.map { "Usage, cost and models. \($0)" } ?? "Usage, cost and models")
        Menu {
            Button("Copy Wish File") { link.send(.copyWishFile) }
            Button("Share…") { link.send(.share) }
            Button("Export…") { link.send(.export) }
        } label: {
            ToolSymbol("square.and.arrow.up", "Share")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .background(AnchorView(anchor: shareAnchor))
        .disabled(!toolbar.canShare)
        .help("Share this wish")
        ToolButton("chevron.left.forwardslash.chevron.right", "Agent Details", on: toolbar.details) { link.send(.details(!toolbar.details)) }
            .help("Agent details")
        ToolButton("trash", "Delete Wish") { deleting = true }
            .help("Delete this wish")
    }

    /// The share menu, at the share button, for the file Lamp made (`SidebarState.sharing`). This process can't read
    /// Lamp's files, so the file comes whole and is kept here, where the service it's shared with reads it.
    private func share(_ sharing: SidebarSharing) {
        // Only the latest file is kept: the one shared before has been handed to its service by now.
        let temporary = FileManager.default.temporaryDirectory
        for old in (try? FileManager.default.contentsOfDirectory(atPath: temporary.path)) ?? [] where old.hasPrefix("share-") {
            try? FileManager.default.removeItem(at: temporary.appendingPathComponent(old))
        }
        let folder = temporary.appendingPathComponent("share-\(sharing.id.uuidString)")
        let name = (sharing.file.name as NSString).lastPathComponent
        let url = folder.appendingPathComponent(name.isEmpty ? "Wish.lampapp" : name)
        guard (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil,
              (try? sharing.file.data.write(to: url)) != nil, let view = shareAnchor.view, view.window != nil else { return }
        NSSharingServicePicker(items: [url]).show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }
}

/// The chat's close button, drawn as a window's red one, since it closes the chat as that closes a window: a red dot
/// that shows its mark when pointed at.
private struct CloseLight: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(nsColor: .systemRed))
                .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
                .overlay {
                    Image(systemName: "xmark")
                        .font(.system(size: 6.5, weight: .heavy))
                        .foregroundStyle(.black.opacity(0.55))
                        .opacity(hovered ? 1 : 0)
                }
                .frame(width: 12, height: 12)
                .padding(6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help("Close the chat")
        .accessibilityLabel("Close Chat")
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
    /// Nothing behind the symbol when it's on: the symbol shows it.
    var plain = false
    @Environment(\.isEnabled) private var isEnabled

    init(_ symbol: String, _ name: String, on: Bool = false, plain: Bool = false) {
        self.symbol = symbol
        self.name = name
        self.on = on
        self.plain = plain
    }

    var body: some View {
        let side: CGFloat = 30
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(on ? AnyShapeStyle(Color.accentColor) : isEnabled ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
            .frame(width: side, height: side)
            .background {
                if #available(macOS 26, *) {
                    if on && !plain { Circle().fill(Color.accentColor.opacity(0.15)).padding(2) }
                } else {
                    Circle().fill(on && !plain ? AnyShapeStyle(Color.accentColor.opacity(0.15)) : AnyShapeStyle(Color(nsColor: .textBackgroundColor)))
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
    var plain = false
    let action: () -> Void

    init(_ symbol: String, _ name: String, on: Bool = false, plain: Bool = false, action: @escaping () -> Void) {
        self.symbol = symbol
        self.name = name
        self.on = on
        self.plain = plain
        self.action = action
    }

    var body: some View {
        Button(action: action) { ToolSymbol(symbol, name, on: on, plain: plain) }
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
            row(calls[0], running: line.running).padding(.leading, ChatLook.stepIndent)
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
                .pointingHand()
                if expanded {
                    ForEach(calls.indices, id: \.self) { index in
                        row(calls[index], running: line.running && index == calls.count - 1)
                    }
                    .padding(.leading, 10)
                }
            }
            .font(ChatLook.stepFont)
            .foregroundStyle(.secondary)
            .padding(.leading, ChatLook.stepIndent)
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
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
        }
        .font(ChatLook.stepFont)
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
                    .padding(.horizontal, 12)
                    if state.hasEarlierVersions == true {
                        Button("Show Earlier Versions") { link.send(.earlierVersions) }
                            .controlSize(.small)
                            .padding(.top, 4)
                    }
                    Color.clear.frame(height: 12)
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
