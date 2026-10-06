import SwiftUI

/// The Versions panel: every saved version of an app, newest first, with a picture of how it looked.
/// Any of them can be named or brought back.
struct VersionsView: View {
    @EnvironmentObject private var store: Store
    let project: LampProject
    @State private var versions: [AppVersion] = []
    @State private var loaded = false
    @State private var selected: String?
    @State private var restoring: AppVersion?

    private var busy: Bool { store.busy.contains(project.id) }

    var body: some View {
        VStack(spacing: 0) {
            if versions.isEmpty {
                ContentUnavailableView(loaded ? "No versions yet" : "Loading…", systemImage: "clock.arrow.circlepath",
                                       description: Text(loaded ? "Lamp saves a version every time the app changes." : ""))
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(versions) { version in
                            VersionRow(project: project, version: version, current: version.id == versions.first?.id,
                                       expanded: selected == version.id, busy: busy,
                                       restore: { restoring = version })
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation(.snappy(duration: 0.2)) { selected = selected == version.id ? nil : version.id }
                                }
                        }
                    }
                    .padding(8)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    Text("Versions").font(.headline)
                    Spacer()
                    Button("Name Current…") {
                        if let current = versions.first { store.naming = VersionNaming(project: project, version: current) }
                    }
                    .controlSize(.small)
                    .disabled(versions.isEmpty)
                    .help("Give the version the app is at now a name (⌘S)")
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                Divider()
            }
            .background(.bar)
        }
        .task(id: "\(busy)-\(store.versionsRevision)") {
            versions = await Versions.list(project)
            loaded = true
            if let current = versions.first { await store.fillCurrentPicture(project, current: current) }
            store.titleVersions(project)
        }
        .confirmationDialog("Go back to “\(restoring?.label ?? "")”?", isPresented: Binding(
            get: { restoring != nil }, set: { if !$0 { restoring = nil } })) {
            Button("Go Back") {
                if let version = restoring { Task { await store.restore(project, to: version) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The app is rebuilt as it was then. Later versions are kept, so you can undo this.")
        }
    }
}

private struct VersionRow: View {
    @EnvironmentObject private var store: Store
    let project: LampProject
    let version: AppVersion
    let current: Bool
    let expanded: Bool
    let busy: Bool
    let restore: () -> Void
    @State private var picture: NSImage?
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                if !expanded { thumbnail(width: 64, height: 42) }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        if version.name != nil {
                            Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
                        }
                        Text(version.label)
                            .fontWeight(version.name == nil ? .regular : .semibold)
                            .lineLimit(expanded ? nil : 2)
                    }
                    HStack(spacing: 4) {
                        if current { Text("Current").foregroundStyle(Color.accentColor) }
                        Text(version.date, format: .relative(presentation: .named))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            if expanded {
                thumbnail(width: nil, height: nil)
                HStack {
                    Button(version.name == nil ? "Name…" : "Rename…") {
                        store.naming = VersionNaming(project: project, version: version)
                    }
                    Spacer()
                    if !current {
                        Button("Go Back to This Version", action: restore)
                            .buttonStyle(.borderedProminent)
                            .disabled(busy)
                    }
                }
                .controlSize(.small)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(
            expanded ? Color.accentColor.opacity(0.1) : hovered ? Color.primary.opacity(0.05) : .clear))
        .onHover { hovered = $0 }
        .contextMenu {
            Button(version.name == nil ? "Name…" : "Rename…") {
                store.naming = VersionNaming(project: project, version: version)
            }
            if version.name != nil {
                Button("Remove Name") { Task { await store.name(version, of: project, as: "") } }
            }
            if !current {
                Divider()
                Button("Go Back to This Version", action: restore).disabled(busy)
            }
        }
        .task(id: store.versionsRevision) {
            let url = Versions.pictureURL(in: project, for: version.id)
            picture = await Task.detached { NSImage(contentsOf: url) }.value
        }
    }

    /// The app's window as it looked, or a plain placeholder for versions from before pictures were kept.
    @ViewBuilder
    private func thumbnail(width: CGFloat?, height: CGFloat?) -> some View {
        let shape = RoundedRectangle(cornerRadius: 5)
        if let picture {
            Image(nsImage: picture)
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
