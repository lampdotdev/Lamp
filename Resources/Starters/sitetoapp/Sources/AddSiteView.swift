import SwiftUI

/// Adding a site to the catalog, or changing one's name and address.
struct AddSiteView: View {
    let editing: Site?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = ""
    @State private var nameTouched = false

    private var url: URL? { Site.normalized(address) }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Address", text: $address, prompt: Text("meet.google.com"))
                        .onChange(of: address) { _, _ in
                            if !nameTouched { name = AddSiteView.suggestedName(for: url) }
                        }
                    TextField("Name", text: Binding(get: { name }, set: { name = $0; nameTouched = true }), prompt: Text("Google Meet"))
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(editing == nil ? "Add" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(url == nil || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 460)
        .onAppear {
            if let editing {
                name = editing.name
                address = editing.url
                nameTouched = true
            }
        }
    }

    private func save() {
        guard let url else { return }
        var site = editing ?? Site(name: "", url: "")
        let changedAddress = site.url != url.absoluteString
        site.name = name.trimmingCharacters(in: .whitespaces)
        site.url = url.absoluteString
        Library.shared.save(site)
        if changedAddress || site.iconFile == nil { Library.shared.fetchIcon(for: site) }
        dismiss()
    }

    /// "app.intercom.com" → "Intercom".
    static func suggestedName(for url: URL?) -> String {
        guard let host = url?.host() else { return "" }
        if let known = SiteSuggestion.all.first(where: { Site.normalized($0.url)?.host() == host }) { return known.name }
        let base = Site.baseDomain(host).split(separator: ".").first.map(String.init) ?? host
        return base.prefix(1).uppercased() + base.dropFirst()
    }
}
