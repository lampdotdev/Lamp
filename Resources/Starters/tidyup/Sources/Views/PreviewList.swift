import SwiftUI

/// What Tidy Now would do, file by file: where each goes and why. Nothing has moved yet.
struct PreviewList: View {
    @EnvironmentObject private var model: TidyModel
    let folder: WatchedFolder

    var body: some View {
        let plan = model.plans[folder.id] ?? Planner.Plan()
        if plan.unreadable {
            ContentUnavailableView {
                Label("Can't Open \(folder.name)", systemImage: "lock")
            } description: {
                Text("Tidy Up needs your permission to look in this folder.")
            } actions: {
                Button("Open Privacy Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!)
                }
                Button("Try Again") { model.refresh(folder.id) }
            }
        } else if plan.changes.isEmpty {
            ContentUnavailableView("Already Tidy", systemImage: "sparkles",
                                   description: Text("Nothing in \(folder.name) needs moving with these rules."))
        } else {
            VStack(spacing: 0) {
                if model.namingUnavailable {
                    namingNote
                }
                Table(plan.changes) {
                    TableColumn("File") { change in
                        HStack(spacing: 6) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: change.source.path))
                                .resizable()
                                .frame(width: 18, height: 18)
                                .accessibilityHidden(true)
                            Text(relative(change.source.path))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    TableColumn("Goes To") { change in
                        destination(change)
                    }
                    TableColumn("Why") { change in
                        Text(change.reason)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .width(min: 120, ideal: 180)
                }
                .contextMenu(forSelectionType: PlannedChange.ID.self) { ids in
                    if let change = plan.changes.first(where: { ids.contains($0.id) }) {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([change.source]) }
                        Button("Leave This File Alone") { model.skip(change, in: folder.id) }
                    }
                }
            }
        }
    }

    @ViewBuilder private func destination(_ change: PlannedChange) -> some View {
        if change.waitingForName {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Reading…").foregroundStyle(.secondary)
            }
        } else if let target = change.destination {
            Label(relative(target.path), systemImage: "arrow.right")
                .lineLimit(1)
                .truncationMode(.middle)
        } else {
            Label("Trash", systemImage: "trash")
        }
    }

    /// A path inside the folder, as the person thinks of it ("Images/photo.jpg").
    private func relative(_ path: String) -> String {
        path.hasPrefix(folder.path + "/") ? String(path.dropFirst(folder.path.count + 1)) : path
    }

    private var namingNote: some View {
        HStack {
            Image(systemName: "info.circle").foregroundStyle(.secondary)
            Text("Files can't be named by what's in them right now, so they keep their names.")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Try Again") { model.retryNaming() }
                .controlSize(.small)
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}
