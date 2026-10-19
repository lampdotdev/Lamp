import SwiftUI
import UniformTypeIdentifiers

enum AddBottle {
    /// Photos dropped on the shelf, picked up when the sheet opens.
    static var dropped: [URL] = []
}

/// Snap, drop or scan a bottle; the AI reads it and fills in its tag.
struct AddBottleView: View {
    @EnvironmentObject var shelf: Shelf
    @Environment(\.dismiss) private var dismiss

    @State private var draft = Bottle(name: "", tag: "")
    @State private var cutout: NSImage?
    @State private var hasPhoto = false
    @State private var working: String?
    @State private var problem: String?
    @State private var productImage: URL?
    @State private var showCamera = false
    @State private var showImporter = false
    @State private var peppers = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 22) {
                preview
                form
            }
            .padding(22)
            Divider()
            HStack {
                if let problem { Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).lineLimit(2) }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Put It on the Shelf") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty || working != nil)
            }
            .padding(16)
        }
        .frame(width: 680)
        .sheet(isPresented: $showCamera) { CameraSheet { process($0) } }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result { load(url) }
        }
        .onAppear {
            // A fresh tag every time: the sheet can keep what it held last time.
            draft = Bottle(name: "", tag: "")
            cutout = nil; hasPhoto = false; working = nil; problem = nil; productImage = nil; peppers = ""
            if let url = AddBottle.dropped.first { load(url) }
            AddBottle.dropped = []
        }
    }

    // MARK: Picture side

    private var preview: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.12, green: 0.08, blue: 0.05))
                if let cutout {
                    Image(nsImage: cutout).resizable().aspectRatio(contentMode: .fit).padding(18)
                } else if hasPhoto {
                    Image(nsImage: BottleImages.generic).resizable().aspectRatio(contentMode: .fit).padding(30).opacity(0.5)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "camera.viewfinder").font(.system(size: 38)).foregroundStyle(.secondary)
                        Text("Drop a photo of the bottle\nor its barcode").multilineTextAlignment(.center).foregroundStyle(.secondary)
                    }
                }
                if let working {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text(working).font(.callout)
                    }
                    .padding(14)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .frame(width: 220, height: 300)
            .lampDropFiles { urls in if let url = urls.first { load(url) } }

            HStack(spacing: 8) {
                Button { showCamera = true } label: { Label("Snap", systemImage: "camera") }
                Button { showImporter = true } label: { Label("Choose…", systemImage: "photo") }
                Button { paste() } label: { Label("Paste", systemImage: "doc.on.clipboard") }
            }
            .controlSize(.small)
            .disabled(working != nil)
            if let productImage, cutout == nil || hasPhoto {
                Button("Use the maker's photo") { useProductPhoto(productImage) }
                    .controlSize(.small)
                    .disabled(working != nil)
            }
        }
    }

    // MARK: Tag side

    private var form: some View {
        Form {
            Section {
                HStack {
                    TextField("Name", text: $draft.name, prompt: Text("What's it called?"))
                    if !hasPhoto {
                        Button("Look It Up") { lookUpByName() }
                            .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty || working != nil)
                            .help("Let AI fill in the rest from the name")
                    }
                }
                TextField("Maker", text: $draft.maker)
                TextField("Peppers", text: $peppers, prompt: Text("habanero, scotch bonnet…"))
                Picker("Shelf", selection: $draft.family) {
                    ForEach(FlavorFamily.allCases) { Text($0.title.capitalized).tag($0.rawValue) }
                }
            }
            Section {
                LabeledContent("Heat") {
                    PepperRow(value: draft.intensity) { draft.heat = Double($0) }
                }
                LabeledContent("Your stars") {
                    StarRow(value: draft.stars) { draft.stars = $0 }
                }
            }
            Section {
                TextField("Tastes", text: $draft.tastes, axis: .vertical).lineLimit(1...2)
                TextField("Ingredients", text: $draft.ingredients, axis: .vertical).lineLimit(1...3)
                TextField("Tag", text: $draft.tag, prompt: Text("A note for the shelf"))
            }
        }
        .formStyle(.grouped)
        .frame(height: 430)
    }

    // MARK: Work

    private func load(_ url: URL) {
        guard let image = NSImage(contentsOf: url) else { problem = "That isn't a photo I can read."; return }
        process(image)
    }

    private func paste() {
        if let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self])?.first as? NSImage {
            process(image)
        } else if let url = NSPasteboard.general.readObjects(forClasses: [NSURL.self])?.first as? URL, url.isFileURL {
            load(url)
        } else {
            problem = "There's no photo on the clipboard."
        }
    }

    private func process(_ image: NSImage) {
        problem = nil
        hasPhoto = true
        cutout = nil
        productImage = nil
        working = "Cutting it out…"
        Task {
            async let cut = Cutout.make(image)
            var product: BottleReader.Product?
            if let code = await Cutout.barcode(in: image) {
                draft.barcode = code
                working = "Found a barcode…"
                product = await BottleReader.lookUp(code)
                productImage = product?.imageURL
            }
            cutout = await cut
            if cutout == nil { problem = "Couldn't cut the bottle out, so it'll get a plain bottle." }
            working = "Reading the label…"
            await read { try await BottleReader.read(photo: image, product: product?.text) }
            working = nil
        }
    }

    private func lookUpByName() {
        problem = nil
        working = "Looking it up…"
        let name = draft.name
        Task {
            await read { try await BottleReader.read(photo: nil, name: name) }
            working = nil
        }
    }

    private func useProductPhoto(_ url: URL) {
        working = "Fetching the photo…"
        Task {
            defer { working = nil }
            guard let (data, _) = try? await URLSession.shared.data(from: url), let image = NSImage(data: data) else {
                problem = "Couldn't fetch the maker's photo."
                return
            }
            working = "Cutting it out…"
            if let cut = await Cutout.make(image) { cutout = cut } else { problem = "Couldn't cut that one out either." }
        }
    }

    private func read(_ reading: () async throws -> Reading) async {
        do {
            let r = try await reading()
            if let v = r.name, !v.isEmpty { draft.name = v }
            if let v = r.maker, !v.isEmpty { draft.maker = v }
            if let v = r.peppers, !v.isEmpty { peppers = v.joined(separator: ", ") }
            if let v = r.ingredients { draft.ingredients = v }
            if let v = r.tastes { draft.tastes = v }
            if let v = r.heat { draft.heat = min(10, max(1, v.rounded())) }
            if let v = r.tag, !v.isEmpty { draft.tag = v }
            if let v = r.family { draft.family = FlavorFamily.from(v).rawValue }
            working = "Finding it a spot…"
            if let family = await BottleReader.family(for: r) { draft.family = family.rawValue }
        } catch {
            problem = "Couldn't read it: \(error.localizedDescription) Fill it in yourself."
        }
    }

    private func save() {
        var bottle = draft
        bottle.id = UUID().uuidString
        bottle.name = bottle.name.trimmingCharacters(in: .whitespaces)
        bottle.peppers = peppers.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if let cutout { bottle.imageName = BottleImages.save(cutout) }
        else if bottle.flavor == .crunchy { bottle.imageName = "style:jar" }
        bottle.addedAt = Date()
        withAnimation(.spring(duration: 0.6)) { shelf.add(bottle) }
        dismiss()
    }
}
