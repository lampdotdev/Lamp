import AVFoundation
import SwiftUI

/// Adds items three ways: holding the barcode up to the camera, typing the number on it, or searching by
/// title. Several can be added before closing, so a pile can be scanned in one go.
struct AddItemSheet: View {
    enum Way: String, CaseIterable, Identifiable {
        case scan = "Scan Barcode", code, search = "Search"
        var id: String { rawValue }
        var label: String { self == .code ? ItemKind.code : rawValue }
    }

    @EnvironmentObject private var library: Library
    @Environment(\.dismiss) private var dismiss
    @State var shelfID: Shelf.ID
    @AppStorage("addWay") private var way = Way.scan
    @StateObject private var scanner = BarcodeScanner()
    @State private var text = ""
    @State private var results: [ItemDetails] = []
    @State private var added: Set<ItemDetails.ID> = []
    @State private var looking = false
    @State private var message: String?

    var body: some View {
        VStack(spacing: 14) {
            Picker("Add by", selection: $way) {
                ForEach(Way.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch way {
            case .scan: camera
            case .code: field("Type the \(ItemKind.code) from the back", button: "Look Up")
            case .search: field("Title or \(ItemKind.creator.lowercased())", button: "Search")
            }

            found
                .frame(maxHeight: .infinity)

            HStack {
                Picker("Add to", selection: $shelfID) {
                    ForEach(library.shelves) { Text($0.name).tag($0.id) }
                }
                .fixedSize()
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 520, height: way == .scan ? 600 : 460)
        .onAppear { if way == .scan { startCamera() } }
        .onChange(of: way) {
            results = []
            message = nil
            if way == .scan { startCamera() } else { scanner.stop() }
        }
        .onDisappear { scanner.stop() }
    }

    // MARK: Ways in

    @ViewBuilder
    private var camera: some View {
        switch scanner.access {
        case .denied, .restricted:
            ContentUnavailableView {
                Label("Camera Not Allowed", systemImage: "video.slash")
            } description: {
                Text("Turn on the camera for Shelves in System Settings, or type the number instead.")
            } actions: {
                Button("Open System Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
                }
            }
            .frame(height: 260)
        default:
            VStack(spacing: 8) {
                CameraPreview(session: scanner.session, connected: scanner.connected)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(.white.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                            .frame(width: 220, height: 110)
                    }
                    .accessibilityLabel("Camera")
                HStack {
                    Text("Hold the barcode on the back up to the camera.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if scanner.cameras.count > 1 {
                        Picker("Camera", selection: Binding(get: { scanner.cameraID }, set: { scanner.use($0) })) {
                            ForEach(scanner.cameras, id: \.uniqueID) { Text($0.localizedName).tag(Optional($0.uniqueID)) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .help("An iPhone near your Mac can be its camera")
                    }
                }
            }
        }
    }

    private func field(_ prompt: String, button: String) -> some View {
        HStack {
            TextField(prompt, text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit(lookUp)
            Button(button, action: lookUp)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || looking)
        }
    }

    // MARK: What was found

    @ViewBuilder
    private var found: some View {
        if looking {
            ProgressView().controlSize(.small)
        } else if !results.isEmpty {
            List(results) { details in
                FoundRow(details: details, added: added.contains(details.id)) {
                    library.add(details, to: shelfID)
                    added.insert(details.id)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        } else if let message {
            VStack(spacing: 10) {
                Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if way == .search, !text.isEmpty {
                    Button("Add “\(text)” by Hand") {
                        library.add(ItemDetails(title: text, creator: ""), to: shelfID)
                        self.message = "Added. Click it on the shelf to fill in the rest."
                    }
                }
            }
        } else {
            Spacer()
        }
    }

    private func startCamera() {
        scanner.onCode = { code in
            guard let isbn = BookLookup.normalize(code) else {
                message = "That barcode isn't a \(ItemKind.singular.lowercased())'s. Look for the one with the \(ItemKind.code)."
                return
            }
            find(isbn: isbn)
        }
        scanner.start()
    }

    private func lookUp() {
        let typed = text.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return }
        if way == .code {
            guard let isbn = BookLookup.normalize(typed) else {
                message = "That doesn't look like an \(ItemKind.code). It's the 10 or 13 digits by the barcode."
                results = []
                return
            }
            find(isbn: isbn)
        } else {
            search(typed)
        }
    }

    private func find(isbn: String) {
        run(nothing: "Nothing found for \(isbn). Try searching by title.") {
            try await BookLookup.find(isbn: isbn).map { [$0] } ?? []
        }
    }

    private func search(_ query: String) {
        run(nothing: "Nothing found for “\(query)”.") { try await BookLookup.search(query) }
    }

    private func run(nothing: String, _ lookup: @escaping () async throws -> [ItemDetails]) {
        looking = true
        message = nil
        Task {
            do {
                results = try await lookup()
                if results.isEmpty { message = nothing }
            } catch {
                results = []
                message = "Couldn't reach Open Library. Check the connection and try again."
            }
            looking = false
        }
    }
}

private struct FoundRow: View {
    let details: ItemDetails
    let added: Bool
    let add: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: details.coverURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle().fill(.quaternary).overlay(Image(systemName: ItemKind.symbol).foregroundStyle(.secondary))
            }
            .frame(width: 36, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            VStack(alignment: .leading, spacing: 2) {
                Text(details.title).font(.headline).lineLimit(2)
                Text([details.creator, details.year.map(String.init)].compactMap { $0 }.filter { !$0.isEmpty }
                    .joined(separator: " · "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if added {
                Label("Added", systemImage: "checkmark").foregroundStyle(.secondary)
            } else {
                Button("Add", action: add)
            }
        }
        .padding(.vertical, 2)
    }
}
