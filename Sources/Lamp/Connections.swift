import Foundation

/// The services an app made with Lamp can sign the person in to (`LampConnection` in LampSupport.swift).
/// The helper is the same for all of them: the connect button and screen, the sign-in on the service's own
/// site, the Keychain and the renewing. What differs is an entry here, and an entry is data: where the
/// sign-in happens, the public name Lamp is registered under there, where the sign-in may be sent, and the
/// words and picture on the screen. What an app does with the account is code the agent writes.
///
/// A service belongs here when a sign-in needs nothing secret from the app, since everything in an entry
/// ships readable inside every app: GitHub's device flow is that. A service that wants a client secret
/// can't be an entry as they are now.
enum Connections {
    struct Service: Equatable {
        /// The name the agent writes (`.github`), so a Swift identifier, and never changed once apps use it:
        /// it is also where the app's Keychain entry is filed.
        var id: String
        /// As the person knows it.
        var name: String
        /// Lamp's registration with the service. Public by design; empty until there is one, and then the
        /// service isn't offered to apps or named to the agent.
        var clientID: String
        /// Where an app asks for a code to show (OAuth's device flow), and where it trades it for the sign-in.
        var deviceURL: String
        var tokenURL: String
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

        static func == (a: Service, b: Service) -> Bool { a.id == b.id }
    }

    /// GitHub, through an OAuth App with its device flow on: no secret and no redirect, on Mac and iPhone.
    /// Such a sign-in doesn't run out, so GitHub never asks for the renewal the helper can do.
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
        icon: "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")

    static let all = [github]

    /// The ones apps can use now: Lamp is registered with them.
    static var offered: [Service] { all.filter { !$0.clientID.isEmpty } }

    /// The entries as LampSupport.swift carries them: one static member of `LampService` each.
    static func swift(for services: [Service]) -> String {
        services.map { service in
            let wording = service.scopes.map { "\(literal($0.name)): \(literal($0.says))" }.joined(separator: ", ")
            return """
                static let \(service.id) = LampService(
                    id: \(literal(service.id)), name: \(literal(service.name)), clientID: \(literal(service.clientID)),
                    deviceURL: \(literal(service.deviceURL)), tokenURL: \(literal(service.tokenURL)),
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
