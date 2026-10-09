import SwiftUI

/// The card an app gets in its chat when it signs people in to a service it isn't registered with yet
/// (`Connections.waiting`): the one thing whoever builds the app has to do themselves, on the service's site,
/// and a place to paste the id the service gives. The id is kept with the app, so anyone the app is shared
/// with only presses Connect. Built like the setup card (a tile, a headline and a line, then rows); what the
/// rows say comes from the service's entry, Lamp's or the one the agent declared, and their wording is Lamp's.
/// It is two steps, and as little to read as they allow: this is the one place a person leaves Lamp for
/// someone else's form, so the card says where to go, what to press there and what to bring back.
enum ConnectionCard {
    /// One card for each service in a chat, however many builds the app has.
    static func isNeeded(_ service: String, after lines: [LogLine]) -> Bool {
        !lines.contains { $0.kind == .connect && $0.text == service }
    }

    static func title(_ app: String, _ service: String) -> String { "Let \(app) connect to \(service)" }

    static func reason(_ app: String, _ service: String) -> String {
        "\(service) asks for this once for each app, and it takes about a minute. After that, anyone using \(app) only presses Connect to \(service)."
    }

    /// Where the button goes and what to do there, in one line: the site by its own name, so the person
    /// sees where an entry sends them, whoever wrote it, then the entry's own words.
    static func instructions(_ service: Connections.Service, app: String) -> String {
        let notes = notes(service, app: app)
        let site = page(service, app: app)?.host.map { "Opens \($0)." } ?? ""
        switch notes.count {
        case 0: return [site, "Fill in the form there and register the app."].filter { !$0.isEmpty }.joined(separator: " ")
        case 1: return [site, notes[0]].filter { !$0.isEmpty }.joined(separator: " ")
        // Several things to do read as a list under the step, not as a paragraph beside the button.
        default: return site
        }
    }

    /// What the entry says to do on the page, a line each.
    static func notes(_ service: Connections.Service, app: String) -> [String] {
        (service.register?.notes ?? []).map { filled($0, app: app) }
    }

    /// An id as it comes off the clipboard: its first line with anything on it, without the space around it.
    static func pasted(_ text: String?) -> String {
        (text ?? "").split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
    }

    static func done(_ app: String, _ service: String) -> String { "All set. \(app) now has its Connect to \(service) button." }

    static func idLabel(_ service: Connections.Service) -> String { service.register?.idLabel ?? "Client ID" }

    /// The entry's words with the app's name in.
    static func filled(_ text: String, app: String) -> String { text.replacingOccurrences(of: "{{NAME}}", with: app) }

    /// The page to open, with the app's name in it where the service takes one in the address.
    static func page(_ service: Connections.Service, app: String) -> URL? {
        guard let register = service.register else { return nil }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let name = app.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        guard Connections.page(register.url) != nil,
              let url = URL(string: register.url.replacingOccurrences(of: "{{NAME}}", with: name)), url.scheme == "https" else { return nil }
        return url
    }
}

struct ConnectionCardView: View {
    /// The service's id, as the chat's line keeps it.
    let service: String
    /// The folder of the app whose chat this is.
    let dir: URL
    @ObservedObject private var store = Store.shared
    @State private var id = ""
    @State private var checking = false
    @State private var problem: String?
    @State private var revision = 0
    /// Whether the service's page has been opened from here, which ticks the first step.
    @State private var opened = false
    @FocusState private var focused: Bool

    var body: some View {
        let _ = revision
        // A service the app no longer names has nothing to register, so its card says nothing.
        if let project = store.projects.first(where: { $0.dir == dir }),
           let entry = Connections.services(for: project).first(where: { $0.id == service }) {
            card(entry, for: project)
        }
    }

    private func card(_ entry: Connections.Service, for project: LampProject) -> some View {
        let done = !entry.clientID.isEmpty
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: CardColumn.gap) {
                badge(done: done)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ConnectionCard.title(project.name, entry.name)).font(.headline)
                    Group {
                        if done {
                            Label {
                                Text(ConnectionCard.done(project.name, entry.name))
                            } icon: {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                        } else {
                            Text(ConnectionCard.reason(project.name, entry.name))
                        }
                    }
                    .font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
            }
            .padding(14)
            if !done {
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    steps(entry, for: project)
                }
                .padding(14)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
        .animation(.easeInOut(duration: 0.35), value: done)
    }

    /// Two steps: register the app on the service's page, then bring back the id it gives. What goes in the
    /// page's form is listed small under the first, for when the page doesn't open with it filled in: some
    /// services take a form's values from the address and some don't, and the card can't see which happened.
    /// So it is the same card for every service, with a fill-in link or without.
    @ViewBuilder
    private func steps(_ entry: Connections.Service, for project: LampProject) -> some View {
        let label = ConnectionCard.idLabel(entry)
        let values = entry.register?.values ?? []
        if let page = ConnectionCard.page(entry, app: project.name) {
            OptionRow(symbol: opened ? "checkmark.circle" : "1.circle", title: "Register \(project.name) on \(entry.name)",
                      detail: ConnectionCard.instructions(entry, app: project.name)) {
                Button("Open \(entry.name)…") {
                    NSWorkspace.shared.open(page)
                    opened = true
                    focused = true
                }
            }
        }
        let notes = ConnectionCard.notes(entry, app: project.name)
        if notes.count > 1 {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•")
                        Text(note).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.leading, CardColumn.indent(compact: false))
        }
        if !values.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("If the form there is empty, these go in it:").foregroundStyle(.secondary)
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
                    ForEach(values, id: \.label) { value in
                        let text = ConnectionCard.filled(value.value, app: project.name)
                        GridRow {
                            Text(value.label).foregroundStyle(.secondary)
                            Text(text).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(text, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                            .help("Copy")
                            .accessibilityLabel("Copy \(value.label)")
                        }
                    }
                }
            }
            .font(.caption)
            .padding(.leading, CardColumn.indent(compact: false))
        }
        OptionRow(symbol: "2.circle", title: "Paste the \(label) \(entry.name) shows next",
                  detail: "It isn't a password. It only tells \(entry.name) which app is asking.") {
            HStack(spacing: 6) {
                TextField(label, text: $id)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 190)
                    .focused($focused)
                    .onSubmit { save(entry, for: project) }
                    .disabled(checking)
                if checking {
                    ProgressView().controlSize(.small)
                } else {
                    // With nothing typed, one press takes the id from the clipboard and saves it.
                    Button(id.trimmed.isEmpty ? "Paste" : "Save") {
                        if id.trimmed.isEmpty { id = ConnectionCard.pasted(NSPasteboard.general.string(forType: .string)) }
                        if id.trimmed.isEmpty { focused = true } else { save(entry, for: project) }
                    }
                }
            }
        }
        if let problem {
            Text(problem).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                .padding(.leading, CardColumn.indent(compact: false))
        }
    }

    /// The service's own mark isn't Lamp's to put on a tile, so the tile says what the card is for.
    private func badge(done: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return Image(systemName: done ? "checkmark" : "person.crop.circle.badge.plus")
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(shape.fill(LinearGradient(colors: done ? [Color.green.opacity(0.85), Color.green]
                                                  : [Color.accentColor.opacity(0.85), Color.accentColor],
                                                  startPoint: .top, endPoint: .bottom)))
            .overlay(shape.strokeBorder(.black.opacity(0.08)))
            .frame(width: CardColumn.icon, height: CardColumn.icon)
    }

    /// Asks the service about the id before keeping it: one that's mistyped, or whose app has the device
    /// sign-in off, is said here, where it can be put right, and not later in the app.
    private func save(_ entry: Connections.Service, for project: LampProject) {
        let pasted = id.trimmed
        guard !pasted.isEmpty, !checking else { return }
        checking = true
        problem = nil
        Task {
            let verdict = await Connections.verify(pasted, for: entry)
            checking = false
            switch verdict {
            case .good:
                do {
                    try Connections.keep(pasted, for: entry.id, in: project)
                    revision += 1
                    // The app is built again so it has the id: now, or once whatever has the app is done.
                    await store.rebuild(project)
                } catch {
                    problem = "Lamp couldn't keep the id with the app: \(error.localizedDescription)"
                }
            case .refused(let why): problem = why
            case .unreachable: problem = "Lamp couldn't reach \(entry.name) to check the id. Try again in a moment."
            }
        }
    }
}
