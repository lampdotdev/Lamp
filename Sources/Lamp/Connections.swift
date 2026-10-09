import Foundation

/// The services an app made with Lamp can sign the person in to (`LampConnection` in LampSupport.swift).
/// The helper is the same for all of them: the connect button and screen, the sign-in on the service's own
/// site, the Keychain and the renewing. What differs is an entry, and an entry is data: where the sign-in
/// happens, the public id the app is registered under there, where the sign-in may be sent, and the words
/// and picture on the screen. What an app does with the account is code the agent writes.
///
/// Entries come from two places. Lamp has some (`known`), with everything but perhaps the id. An app has
/// its own in capabilities.json (`Declared`): an id for one of Lamp's, registered by whoever builds the app,
/// or a whole service Lamp has no entry for, which the agent describes. They travel with the app, shared
/// copies included, because nothing in them is a secret. An id is looked for in the app first, then in
/// Lamp's entry; a service that hands out ids to apps that ask would be a third place, tried between the
/// two, and none of Lamp's does. Until a service has an id for an app, the app's chat has a card with the
/// steps to register it (`ConnectionCard`), and the app says it isn't set up.
///
/// A sign-in that wants a client secret can't be an entry: everything here ships readable inside every app,
/// and there is deliberately nowhere to put a secret. Nor can one that only offers a redirect, for now.
enum Connections {
    struct Service: Equatable {
        /// The name the agent writes (`.github`), so a Swift identifier, and never changed once apps use it:
        /// it is also where the app's Keychain entry is filed.
        var id: String
        /// As the person knows it.
        var name: String
        /// The app's registration with the service. Public by design. Empty until there is one, and then
        /// the app shows that it isn't set up and its chat has the card.
        var clientID: String
        /// Where an app asks for a code to show (OAuth's device flow), and where it trades it for the sign-in.
        /// Empty for a service signed in to in the browser.
        var deviceURL: String
        var tokenURL: String
        /// The service's own sign-in page, for the other way in (the authorization code flow with PKCE).
        var authorizeURL = ""
        /// Where the service sends the person back from that page (`checkedRedirect`).
        var redirect = ""
        /// What else the sign-in page's address has to carry.
        var parameters: [String: String] = [:]
        /// The service's API: the only hosts an app's sign-in is sent to.
        var hosts: [String]
        /// Who signed in, for the button's "GitHub: octocat": an address answering JSON, and the field in it.
        var accountURL: String
        var accountField: String
        /// The scopes worth telling the agent about, each with what it means in the person's words: the
        /// connect screen shows the line for each one an app asks for.
        var scopes: [(name: String, says: String)]
        /// Said when an app asks for no scope.
        var basic: String
        /// The service's mark, a small PNG in base64 with only its shape (drawn in the text's color).
        var icon: String
        /// How whoever builds an app registers it with the service, for the card.
        var register: Register?

        static func == (a: Service, b: Service) -> Bool { a.id == b.id }
    }

    /// Registering an app with a service: the page to open, what to enter there, and what the id is called.
    /// `{{NAME}}` in any of it is the app's name, and `{{REDIRECT}}` the address the service is to send the
    /// person back to, for a service signed in to in the browser. The page's address may carry the form's values, for a
    /// service whose form takes them from there (a fill-in link): `…/apps/new?name={{NAME}}&url=…`. That is
    /// the same for every service, Lamp's or one an app declares, and so is what guards it: the address is
    /// https with nobody's name or password in it, the app's name is the only thing Lamp puts into it, and
    /// only after the `?`, so an app can't steer the host or the path with its name. The card says which
    /// site the button opens, and always lists the values too, for a form that opens empty.
    struct Register: Codable, Equatable {
        struct Value: Codable, Equatable {
            var label: String
            var value: String
        }
        var url: String
        /// What to type into the page's fields, by the page's own labels.
        var values: [Value]?
        /// Anything else to do there, a short line each ("Tick Enable Device Flow").
        var notes: [String]?
        /// What the page calls the id it gives ("Client ID").
        var idLabel: String?
    }

    /// GitHub, through an OAuth App with its device flow on: no secret and no redirect, on Mac and iPhone.
    /// Such a sign-in doesn't run out, so GitHub never asks for the renewal the helper can do. Lamp has no
    /// registration of its own with GitHub yet, so the id is each app's.
    static let github = Service(
        id: "github",
        name: "GitHub",
        clientID: "",
        deviceURL: "https://github.com/login/device/code",
        tokenURL: "https://github.com/login/oauth/access_token",
        hosts: ["api.github.com"],
        accountURL: "https://api.github.com/user",
        accountField: "login",
        scopes: [
            ("repo", "See and change your repositories, private ones too"),
            ("public_repo", "See and change your public repositories"),
            ("read:user", "See your profile"),
            ("user:email", "See your email addresses"),
            ("notifications", "See your notifications and mark them read"),
            ("read:org", "See which organizations and teams you belong to"),
            ("gist", "See and write your gists"),
            ("workflow", "Change the workflows that run in your repositories"),
        ],
        basic: "See what's public on your profile",
        icon: "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",
        register: Register(
            // A fill-in link. GitHub's form takes its values from the address (seen working 2026-10-09),
            // though GitHub only documents that for GitHub Apps.
            url: "https://github.com/settings/applications/new?oauth_application%5Bname%5D={{NAME}}&oauth_application%5Burl%5D=https%3A%2F%2Flamp.dev&oauth_application%5Bcallback_url%5D=https%3A%2F%2Flamp.dev",
            values: [.init(label: "Application name", value: "{{NAME}}"),
                     .init(label: "Homepage URL", value: "https://lamp.dev"),
                     .init(label: "Authorization callback URL", value: "https://lamp.dev")],
            notes: ["Tick Enable Device Flow, then press Register application."],
            idLabel: "Client ID"))

    /// The services Lamp has an entry for.
    static let known = [github]

    // MARK: - What an app declares

    /// A service as an app declares it in capabilities.json (`connections`). For one of Lamp's, the id is
    /// all that's read. For any other, the agent gives the rest, and it is used only when all of it passes
    /// (`checked`), whoever wrote the file: the agent here, or the sender of a shared app.
    struct Declared: Codable, Equatable {
        var id: String
        var clientID: String?
        var name: String?
        var deviceURL: String?
        var tokenURL: String?
        var authorizeURL: String?
        var redirect: String?
        var parameters: [String: String]?
        var hosts: [String]?
        var accountURL: String?
        var accountField: String?
        /// The service's scopes the app uses, each with what it means in the person's words.
        var scopes: [String: String]?
        var register: Register?

        /// Read leniently: one field of the wrong kind is dropped, not the whole of capabilities.json.
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = (try? values.decode(String.self, forKey: .id)) ?? ""
            clientID = try? values.decode(String.self, forKey: .clientID)
            name = try? values.decode(String.self, forKey: .name)
            deviceURL = try? values.decode(String.self, forKey: .deviceURL)
            tokenURL = try? values.decode(String.self, forKey: .tokenURL)
            authorizeURL = try? values.decode(String.self, forKey: .authorizeURL)
            redirect = try? values.decode(String.self, forKey: .redirect)
            parameters = try? values.decode([String: String].self, forKey: .parameters)
            hosts = try? values.decode([String].self, forKey: .hosts)
            accountURL = try? values.decode(String.self, forKey: .accountURL)
            accountField = try? values.decode(String.self, forKey: .accountField)
            scopes = try? values.decode([String: String].self, forKey: .scopes)
            register = try? values.decode(Register.self, forKey: .register)
        }

        init(id: String, clientID: String? = nil, name: String? = nil, deviceURL: String? = nil, tokenURL: String? = nil,
             authorizeURL: String? = nil, redirect: String? = nil, parameters: [String: String]? = nil,
             hosts: [String]? = nil, accountURL: String? = nil, accountField: String? = nil, scopes: [String: String]? = nil,
             register: Register? = nil) {
            self.id = id; self.clientID = clientID; self.name = name; self.deviceURL = deviceURL; self.tokenURL = tokenURL
            self.authorizeURL = authorizeURL; self.redirect = redirect; self.parameters = parameters
            self.hosts = hosts; self.accountURL = accountURL; self.accountField = accountField; self.scopes = scopes
            self.register = register
        }
    }

    /// Names a service can't have: Swift's own words, and what `LampService` already calls its parts.
    private static let taken: Set<String> = ["id", "name", "hosts", "icon", "wording", "lines", "self", "init", "default", "case", "class",
                                             "struct", "enum", "func", "let", "var", "static", "true", "false", "nil", "in", "is", "as",
                                             "if", "else", "for", "while", "do", "try", "throw", "return", "switch", "where", "import",
                                             "public", "private", "internal", "extension", "protocol", "super", "some", "any"]

    /// Only what passes, six services at most. One of Lamp's keeps its id and nothing else, so an app can't
    /// point GitHub's name at another address. Any other needs all of a sign-in: a name that isn't one of
    /// Lamp's, both addresses over https, and where its API is.
    static func checked(_ declared: [Declared]) -> [Declared] {
        var kept: [Declared] = []
        for entry in declared where kept.count < 6 && !kept.contains(where: { $0.id == entry.id }) {
            let clientID = entry.clientID.flatMap { matches($0, #"^[A-Za-z0-9._~-]{4,200}$"#) ? $0 : nil }
            if known.contains(where: { $0.id == entry.id }) {
                if let clientID { kept.append(Declared(id: entry.id, clientID: clientID)) }
                continue
            }
            guard matches(entry.id, #"^[a-z][A-Za-z0-9]{1,23}$"#), !taken.contains(entry.id),
                  let name = entry.name.flatMap({ line($0, limit: 30) }),
                  !known.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }),
                  let tokenURL = entry.tokenURL.flatMap(secure) else { continue }
            // One way in or the other: a code to enter (the device flow), or the service's page in the browser.
            let deviceURL = entry.deviceURL.flatMap(secure)
            let authorizeURL = deviceURL == nil ? entry.authorizeURL.flatMap(secure) : nil
            guard deviceURL != nil || authorizeURL != nil else { continue }
            let redirect = authorizeURL == nil ? nil : checkedRedirect(entry.redirect)
            // A redirect that doesn't pass leaves no way back from the browser, so the service isn't taken.
            if authorizeURL != nil, redirect == nil { continue }
            var parameters: [String: String] = [:]
            if authorizeURL != nil {
                for (name, value) in (entry.parameters ?? [:]).sorted(by: { $0.key < $1.key }) where parameters.count < 6 {
                    if matches(name, #"^[a-z][a-z0-9_]{0,39}$"#), !ownParameters.contains(name), matches(value, #"^[A-Za-z0-9._~-]{1,80}$"#) {
                        parameters[name] = value
                    }
                }
            }
            let hosts = (entry.hosts ?? []).map { $0.lowercased() }.filter { matches($0, #"^([a-z0-9-]{1,63}\.)+[a-z]{2,24}$"#) }.prefix(5)
            guard !hosts.isEmpty else { continue }
            // Who signed in is asked of the service's own API or not at all.
            let accountURL = entry.accountURL.flatMap(secure).flatMap { hosts.contains(URL(string: $0)?.host?.lowercased() ?? "") ? $0 : nil }
            let accountField = entry.accountField.flatMap { matches($0, #"^[A-Za-z0-9_]{1,40}$"#) ? $0 : nil }
            var scopes: [String: String] = [:]
            for (scope, says) in (entry.scopes ?? [:]).sorted(by: { $0.key < $1.key }) where scopes.count < 12 {
                if matches(scope, #"^[\x21-\x7E]{1,100}$"#), let says = line(says, limit: 80) { scopes[scope] = says }
            }
            var register: Register?
            if let asked = entry.register, let url = page(asked.url) {
                let values = (asked.values ?? []).prefix(8).compactMap { value -> Register.Value? in
                    guard let label = line(value.label, limit: 40), let text = line(value.value, limit: 200) else { return nil }
                    return Register.Value(label: label, value: text)
                }
                // Room for a real instruction: an agent's own run to about 150 characters, and a note that is cut
                // is a step the person never sees.
                let notes = (asked.notes ?? []).prefix(5).compactMap { line($0, limit: 240) }
                register = Register(url: url, values: values.isEmpty ? nil : Array(values), notes: notes.isEmpty ? nil : Array(notes),
                                    idLabel: asked.idLabel.flatMap { line($0, limit: 30) })
            }
            kept.append(Declared(id: entry.id, clientID: clientID, name: name, deviceURL: deviceURL, tokenURL: tokenURL,
                                 authorizeURL: authorizeURL, redirect: redirect, parameters: parameters.isEmpty ? nil : parameters, hosts: Array(hosts),
                                 accountURL: accountField == nil ? nil : accountURL, accountField: accountURL == nil ? nil : accountField,
                                 scopes: scopes.isEmpty ? nil : scopes, register: register))
        }
        return kept
    }

    /// What the sign-in page's address carries for every sign-in, which an entry can't set or replace, and
    /// the one thing it must never carry: there is no secret in an app.
    private static let ownParameters: Set<String> = ["response_type", "client_id", "redirect_uri", "scope", "state", "code_challenge",
                                                     "code_challenge_method", "client_secret", "code_verifier", "code"]

    /// Lamp's own private address for coming back from a service's page, in the form OAuth asks of native
    /// apps (RFC 8252): a scheme under a domain that is Lamp's. Only the system's sign-in window answers it.
    static let appRedirect = "dev.lamp.connect:/oauth"

    /// Where a service may send the person back, or nothing. "app" (the default) is Lamp's private address,
    /// which works on Mac and iPhone. "loopback" is this Mac's own address on any free port, for a service
    /// that only takes that; a Mac app listens there, and an iPhone app can't. A service that dictates the
    /// form gets it written out: `http://127.0.0.1` with the port it wants, or a private scheme with a dot in
    /// it (so never one the system or another kind of app owns), where `{{REVERSED_ID}}` is the app's id with
    /// its parts turned round, as Google asks. Never an address on the web: the answer would go to whoever
    /// runs that site.
    static func checkedRedirect(_ redirect: String?) -> String? {
        guard let redirect, !redirect.isEmpty, redirect != "app" else { return "app" }
        if redirect == "loopback" { return redirect }
        guard redirect.count <= 200 else { return nil }
        if matches(redirect, #"^http://127\.0\.0\.1(:[0-9]{4,5})?(/[A-Za-z0-9._~/-]{0,80})?$"#) {
            let port = URLComponents(string: redirect)?.port
            return port == nil || (1024...65535).contains(port!) ? redirect : nil
        }
        let plain = redirect.replacingOccurrences(of: "{{REVERSED_ID}}", with: "com.example.app")
        return matches(plain, #"^[a-z][a-z0-9+-]*(\.[a-z0-9+-]+)+:/{1,2}[A-Za-z0-9._~/-]{0,80}$"#) ? redirect : nil
    }

    /// The redirect as it's typed into the service's registration form, or nothing when it can't be known
    /// yet (it is made from the id the service hasn't given) or the service signs in with a code.
    static func redirectToRegister(_ service: Service) -> String? {
        guard service.deviceURL.isEmpty, !service.authorizeURL.isEmpty, !service.redirect.contains("{{REVERSED_ID}}") else { return nil }
        switch service.redirect {
        case "", "app": return appRedirect
        case "loopback": return "http://127.0.0.1/oauth"
        default: return service.redirect
        }
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    /// One line of ordinary text, or nothing: these words are shown to people, in the app and in Lamp.
    private static func line(_ text: String, limit: Int) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= limit,
              !trimmed.unicodeScalars.contains(where: { $0.properties.generalCategory == .control || $0.properties.generalCategory == .format
                                                           || $0.properties.generalCategory == .lineSeparator
                                                           || $0.properties.generalCategory == .paragraphSeparator }) else { return nil }
        return trimmed
    }

    /// A registration page's address, or nothing: an https address like any other here, where the app's name
    /// may be asked for (`{{NAME}}`) only among the values after the `?`.
    static func page(_ address: String) -> String? {
        let parts = address.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        guard !parts[0].contains("{"), !parts[0].contains("}"),
              secure(address.replacingOccurrences(of: "{{NAME}}", with: "name").replacingOccurrences(of: "{{REDIRECT}}", with: "redirect")) != nil
        else { return nil }
        return address
    }

    /// An https address with a host and nobody's name or password in it, or nothing.
    private static func secure(_ address: String) -> String? {
        guard address.count <= 600, let url = URL(string: address), url.scheme == "https", let host = url.host, host.contains("."),
              url.user == nil, url.password == nil else { return nil }
        return address
    }

    // MARK: - An app's services

    /// The services an app can name: Lamp's, each with the app's own id for it when it has one, then the
    /// ones the app declares itself.
    static func services(for project: LampProject) -> [Service] {
        services(declared: Template.Capabilities.load(project).connections ?? [])
    }

    static func services(declared: [Declared]) -> [Service] {
        let declared = checked(declared)
        var services = known.map { service -> Service in
            var service = service
            if let id = declared.first(where: { $0.id == service.id })?.clientID { service.clientID = id }
            return service
        }
        for entry in declared where !known.contains(where: { $0.id == entry.id }) {
            services.append(Service(id: entry.id, name: entry.name ?? "", clientID: entry.clientID ?? "", deviceURL: entry.deviceURL ?? "",
                                    tokenURL: entry.tokenURL ?? "", authorizeURL: entry.authorizeURL ?? "", redirect: entry.redirect ?? "",
                                    parameters: entry.parameters ?? [:], hosts: entry.hosts ?? [], accountURL: entry.accountURL ?? "",
                                    accountField: entry.accountField ?? "",
                                    scopes: (entry.scopes ?? [:]).sorted { $0.key < $1.key }.map { ($0.key, $0.value) },
                                    basic: "", icon: "", register: entry.register))
        }
        return services
    }

    /// The services an app uses that have no id yet: the ones it declares itself, and Lamp's when its code
    /// names them. Each gets a card in the app's chat.
    static func waiting(in project: LampProject) -> [Service] {
        let declared = checked(Template.Capabilities.load(project).connections ?? []).map(\.id)
        let code = usesConnections(project)
        return services(for: project).filter { service in
            service.clientID.isEmpty && (declared.contains(service.id) || code.contains { names(service.id, in: $0) })
        }
    }

    /// The app's own files that use the helper, as text.
    private static func usesConnections(_ project: LampProject) -> [String] {
        let sources = project.dir.appendingPathComponent("Sources")
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
        return files.filter { $0.pathExtension == "swift" && $0.lastPathComponent != "LampSupport.swift" }
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            .filter { $0.contains("LampConnect") || $0.contains("lampConnectionSheet") || $0.contains("LampService") }
    }

    static func names(_ id: String, in code: String) -> Bool {
        code.range(of: #"\.\#(id)\b"#, options: .regularExpression) != nil
    }

    /// Keeps the id whoever builds the app got from the service, in the app's capabilities.json, so it goes
    /// wherever the app goes.
    static func keep(_ clientID: String, for service: String, in project: LampProject) throws {
        var capabilities = Template.Capabilities.load(project)
        var declared = capabilities.connections ?? []
        if let index = declared.firstIndex(where: { $0.id == service }) {
            declared[index].clientID = clientID
        } else {
            declared.append(Declared(id: service, clientID: clientID))
        }
        capabilities.connections = declared
        try capabilities.save(for: project)
    }

    // MARK: - Checking an id

    enum Verdict: Equatable {
        case good
        /// The service answered, and this isn't an id it will sign people in with. The reason is for the person.
        case refused(String)
        case unreachable
    }

    /// Asks the service to start a sign-in with the id, which is all an app would do with it. Nothing comes
    /// of the code it hands back: nobody is shown it, so it runs out unused. Only an answer that is about
    /// the id refuses it (OAuth's words for an app it doesn't know or that may not sign in this way, and
    /// GitHub's own). Any other complaint, about scopes or the request, is no reason to turn the id away:
    /// services differ in what they want asked, and the app's connect screen says what the service says.
    static func verify(_ clientID: String, for service: Service, session: URLSession = URLSession(configuration: .ephemeral)) async -> Verdict {
        guard matches(clientID, #"^[A-Za-z0-9._~-]{4,200}$"#) else {
            return .refused("That doesn't look like an id from \(service.name). Copy it again from the page.")
        }
        // A service signed in to in the browser has nothing to ask without the person there: the id is kept
        // as it is, and the service's own page says so if it's wrong.
        guard !service.deviceURL.isEmpty else { return .good }
        guard let url = URL(string: service.deviceURL) else { return .unreachable }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        // With the scopes the entry names, since some services start no sign-in without any.
        let scope = service.scopes.map(\.name).joined(separator: " ").addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        request.httpBody = Data(("client_id=\(clientID)" + (scope.isEmpty ? "" : "&scope=\(scope)")).utf8)
        guard let (data, response) = try? await session.data(for: request), let status = (response as? HTTPURLResponse)?.statusCode else {
            return .unreachable
        }
        let reply = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if reply["device_code"] is String { return .good }
        guard status < 500, status != 429 else { return .unreachable }
        switch reply["error"] as? String ?? "" {
        case "device_flow_disabled", "unauthorized_client":
            return .refused("\(service.name) knows this app, but its device flow is off. Turn that on in the app's page there, then save again.")
        case "invalid_client", "Not Found":
            return .refused("\(service.name) doesn't know that id. Copy it again from the app's page there.")
        default:
            return status == 404 ? .refused("\(service.name) doesn't know that id. Copy it again from the app's page there.") : .good
        }
    }

    // MARK: - What apps and the agent are given

    /// The entries as LampSupport.swift carries them: one static member of `LampService` each.
    static func swift(for services: [Service]) -> String {
        services.map { service in
            let wording = service.scopes.map { "\(literal($0.name)): \(literal($0.says))" }.joined(separator: ", ")
            return """
                static let \(service.id) = LampService(
                    id: \(literal(service.id)), name: \(literal(service.name)), clientID: \(literal(service.clientID)),
                    deviceURL: \(literal(service.deviceURL)), tokenURL: \(literal(service.tokenURL)),
                    authorizeURL: \(literal(service.authorizeURL)), redirect: \(literal(service.redirect)),
                    parameters: [\(service.parameters.isEmpty ? ":" : service.parameters.sorted { $0.key < $1.key }.map { "\(literal($0.key)): \(literal($0.value))" }.joined(separator: ", "))],
                    hosts: [\(service.hosts.map(literal).joined(separator: ", "))],
                    accountURL: \(literal(service.accountURL)), accountField: \(literal(service.accountField)),
                    wording: [\(wording.isEmpty ? ":" : wording)], basicWording: \(literal(service.basic)),
                    icon: \(literal(service.icon)))
            """
        }.joined(separator: "\n")
    }

    /// A Swift string literal holding exactly this text.
    private static func literal(_ text: String) -> String {
        var escaped = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\\": escaped += "\\\\"
            case "\"": escaped += "\\\""
            case _ where scalar.value < 0x20 || scalar.value == 0x7F: escaped += "\\u{\(String(scalar.value, radix: 16))}"
            default: escaped.unicodeScalars.append(scalar)
            }
        }
        return "\"" + escaped + "\""
    }
}
