import SwiftUI

extension WebModel {
    /// When the window comes forward with one of the site's links on the clipboard (a Meet link someone sent), it's
    /// offered at the top, once.
    func checkClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              text != lastOffered, !text.contains(" "), text.count < 2000,
              let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), isOwn(url),
              url.absoluteString != webView.url?.absoluteString else { return }
        lastOffered = text
        withAnimation(.spring(duration: 0.3)) { offeredLink = url }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            self?.dismissOffer(url)
        }
    }

    func dismissOffer(_ url: URL? = nil) {
        guard url == nil || offeredLink == url else { return }
        withAnimation(.easeOut(duration: 0.2)) { offeredLink = nil }
    }

    /// What was typed into Open Link: an address, or just a path or code on this site ("abc-defg-hij" in Meet).
    func link(from text: String) -> URL? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.contains("."), let url = Site.normalized(text) { return url }
        guard let home = site.address, let origin = URL(string: "/", relativeTo: home)?.absoluteURL else { return nil }
        let path = text.hasPrefix("/") ? String(text.dropFirst()) : text
        return URL(string: path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path, relativeTo: origin)?.absoluteURL
    }
}

/// "Open copied link" at the top of the page.
struct LinkPill: View {
    @ObservedObject var web: WebModel
    let url: URL

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "link")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Open copied link?")
                    .font(.callout.weight(.semibold))
                Text((url.host() ?? "") + url.path())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: 280, alignment: .leading)
            Button("Open") { web.open(url) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Button { web.dismissOffer() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Not now")
            .accessibilityLabel("Not now")
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .padding(.top, 14)
    }
}

/// File ▸ Open Link…: paste a link (or a Meet code) and it opens right here.
struct OpenLinkSheet: View {
    @ObservedObject var web: WebModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Open Link in \(web.site.name)")
                .font(.headline)
            TextField("Link", text: $text, prompt: Text(web.site.host + "/…"))
                .textFieldStyle(.roundedBorder)
                .onSubmit(open)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Open", action: open)
                    .keyboardShortcut(.defaultAction)
                    .disabled(web.link(from: text) == nil)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            if let copied = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
               let url = URL(string: copied), url.scheme?.hasPrefix("http") == true {
                text = copied
            }
        }
    }

    private func open() {
        guard let url = web.link(from: text) else { return }
        web.open(url)
        dismiss()
    }
}
