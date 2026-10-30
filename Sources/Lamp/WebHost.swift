import Foundation
import LampRelayKit

/// Lamp's web host for the Xbox: one prebuilt program (`Resources/WebHost`, built from `lamp_web_host.cpp` by
/// `scripts/build-web-host.sh`) that shows a web app's pages full screen in WebView2, the console's Chromium, in place
/// of the EdgeHTML host Windows gives a package that names a start page. It never changes between apps, so it's put
/// beside each app's files in its package as it is: a web app needs no toolchain on the person's Mac. The app's files go
/// in its Web folder, served to the page at https://lamp.example/.
enum WebHost {
    static let program = "App.exe"
    /// WebView2's WinRT layer, Microsoft's redistributable from its WebView2 SDK, which the package registers.
    static let library = "Microsoft.Web.WebView2.Core.dll"
    /// Where the app's own files go in the package.
    static let folder = "Web"
    /// The classes of `library` the host (or WebView2 itself) activates by name.
    static let activatableClasses = [
        "Microsoft.Web.WebView2.Core.CoreWebView2Environment",
        "Microsoft.Web.WebView2.Core.CoreWebView2EnvironmentOptions",
        "Microsoft.Web.WebView2.Core.CoreWebView2ControllerWindowReference",
        "Microsoft.Web.WebView2.Core.CoreWebView2CustomSchemeRegistration",
    ]

    static var resources: URL? { Bundle.main.resourceURL?.appendingPathComponent("WebHost") }

    /// Whether a declared kind's apps run in this host. Lamp Dev can be sent back to the EdgeHTML host with
    /// `defaults write <bundle id> xboxWebHost edgehtml`, to compare the two on the same console; a shared app never is,
    /// since only this host keeps it to its sites (`policy`).
    static func isUsed(by declared: Integration.AppKind.Declared, guarded: Bool = false) -> Bool {
        guard declared.host == "webview2" else { return false }
        return guarded || !(Edition.isDev && UserDefaults.standard.string(forKey: "xboxWebHost") == "edgehtml")
    }

    /// What a shared app's page may reach on the console, which the host keeps to with or without Lamp
    /// (`lamp_web_guard.h`): the sites it was shared with (`NetworkPolicy.origins`), and Lamp's own addresses for the
    /// page's calls to Lamp.
    /// Written beside the host as `policyFile`, outside Web/, where nothing of the app's own can reach it.
    struct Policy: Codable, Equatable {
        /// The host's `lampg::policy_format`: a host that doesn't know it guards the app with nothing listed.
        var format = 1
        var origins: [String]
        var lamp: [String]
    }
    static let policyFile = "network-policy.json"

    /// Whether a built host keeps to `policyFile`: one that does names it (`lampg::policy_file`, a plain string in the
    /// program), one built before the guard doesn't.
    static func readsPolicy(_ host: Data) -> Bool { host.range(of: Data(policyFile.utf8)) != nil }

    /// The policy for an app shared with the person, from what Lamp keeps for it (`SharedNetwork`); nil for one of their
    /// own, or one they let reach every site, which the host leaves as it is.
    static func policy(for project: LampProject) -> Policy? {
        policy(from: SharedNetwork.policy(for: project), lamp: DeviceSupport.installValues(for: project)["routes"] as? [String] ?? [])
    }

    /// The host has no bar to ask the person about a site Lamp couldn't name (`mayConnect`), and runs no Swift of the
    /// app's own (`ownSwift`): on the console a shared page reaches its listed sites and nothing else.
    static func policy(from shared: NetworkPolicy?, lamp routes: [String]) -> Policy? {
        guard let shared, shared.restricts else { return nil }
        return Policy(origins: shared.origins, lamp: Array(Set(routes.compactMap(NetworkPolicy.origin))).sorted())
    }

    /// Where a game's phone page goes in the package, beside Web/, which the host serves to phones itself.
    static let phoneFolder = "Phone"

    /// The package's files: the host and WebView2's library at the top, a shared app's policy beside them, the app's
    /// under Web/, and a game's phone page under Phone/.
    static func payload(_ files: [(path: String, data: Data)], phone: ControllerSnapshot? = nil, policy: Policy? = nil,
                        from resources: URL? = resources) throws -> [(path: String, data: Data)] {
        guard let resources,
              let host = try? Data(contentsOf: resources.appendingPathComponent(program)),
              let core = try? Data(contentsOf: resources.appendingPathComponent(library)) else {
            throw MSIX.Failure(message: "Lamp's web host for the Xbox is missing from Lamp itself.")
        }
        // A host built before the guard runs a shared page unheld, its policy file unread: a shared app never goes out
        // with one.
        if policy != nil, !readsPolicy(host) {
            throw MSIX.Failure(message: "This app was shared with you, and this copy of Lamp can't keep it to the sites it was shared with on an Xbox yet, so it isn't put there.")
        }
        let rule = try policy.map { [(policyFile, try JSONEncoder().encode($0))] } ?? []
        return [(program, host), (library, core)] + rule + files.map { (folder + "/" + $0.path, $0.data) }
            + (phone?.files ?? []).map { (phoneFolder + "/" + $0.path, $0.data) }
    }
}
