import SwiftUI

/// The sidebar: every recording, newest first, searchable by title and by what was said.
struct RecordingList: View {
    @ObservedObject private var library = Library.shared
    @State private var search = ""
    @State private var pendingDelete: Recording?

    private var shown: [Recording] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return library.recordings }
        return library.recordings.filter { recording in
            recording.title.localizedCaseInsensitiveContains(query)
                || recording.lines.contains { $0.text.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        List(selection: $library.selection) {
            ForEach(shown) { recording in
                RecordingRow(recording: recording)
                    .tag(recording.id)
                    .contextMenu {
                        Button("Delete…", role: .destructive) { pendingDelete = recording }
                    }
            }
        }
        .searchable(text: $search, placement: .sidebar, prompt: "Search transcripts")
        .overlay {
            if library.recordings.isEmpty {
                ContentUnavailableView("No Recordings", systemImage: "waveform",
                                       description: Text("Press Record to start one."))
            } else if shown.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if library.hasExamples {
                Button("Clear Examples") { library.clearExamples() }
                    .buttonStyle(.borderless)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
                    .help("Remove the two sample recordings")
            }
        }
        .onDeleteCommand { pendingDelete = library.selected }
        .confirmationDialog("Delete “\(pendingDelete?.title ?? "")”?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        ), presenting: pendingDelete) { recording in
            Button("Delete", role: .destructive) { library.delete(recording.id) }
        } message: { recording in
            Text(recording.canPlay ? "Its audio and transcript will be deleted." : "Its transcript will be deleted.")
        }
    }
}

private struct RecordingRow: View {
    let recording: Recording

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(recording.title)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(recording.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                Text("·")
                Text(recording.duration.spoken)
                if recording.isExample {
                    Text("·")
                    Text("Example")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
