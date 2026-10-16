import SwiftUI

/// Past tidies of a folder, newest first, each opening to the files it moved.
struct ActivityList: View {
    @EnvironmentObject private var model: TidyModel
    let folder: WatchedFolder

    var body: some View {
        let records = model.records(for: folder)
        if records.isEmpty {
            ContentUnavailableView("No Tidies Yet", systemImage: "clock",
                                   description: Text("What Tidy Now moves shows up here, and can be put back."))
        } else {
            List {
                if records.contains(where: \.isExample) {
                    HStack {
                        Text("The tidy marked Example shows what the log looks like; no files were moved.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Clear Examples") { model.clearExamples() }
                    }
                    .font(.callout)
                }
                ForEach(records) { record in
                    RecordRow(record: record, folderPath: folder.path)
                }
            }
        }
    }
}

struct RecordRow: View {
    let record: TidyRecord
    let folderPath: String

    var body: some View {
        DisclosureGroup {
            ForEach(record.moves, id: \.self) { move in
                HStack(spacing: 6) {
                    Text(name(move.from))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("moved to")
                    if move.trashed {
                        Label("Trash", systemImage: "trash")
                    } else {
                        Text(relative(move.to))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .font(.callout)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: record.automatic ? "bolt" : "sparkles")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(record.date.formatted(.relative(presentation: .named)).capitalizedFirst
                     + " · " + record.date.formatted(date: .omitted, time: .shortened))
                Text(record.moves.count == 1 ? "1 file" : "\(record.moves.count) files")
                    .foregroundStyle(.secondary)
                if record.automatic { Tag("Automatic") }
                if record.undone { Tag("Undone") }
                if record.isExample { Tag("Example") }
            }
        }
    }

    private func name(_ path: String) -> String { URL(fileURLWithPath: path).lastPathComponent }

    private func relative(_ path: String) -> String {
        path.hasPrefix(folderPath + "/") ? String(path.dropFirst(folderPath.count + 1)) : path
    }
}

/// A small label beside a tidy: Automatic, Undone, Example.
struct Tag: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
