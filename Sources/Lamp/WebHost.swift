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

    private static var resources: URL? { Bundle.main.resourceURL?.appendingPathComponent("WebHost") }

    /// Whether a declared kind's apps run in this host. Lamp Dev can be sent back to the EdgeHTML host with
    /// `defaults write <bundle id> xboxWebHost edgehtml`, to compare the two on the same console.
    static func isUsed(by declared: Integration.AppKind.Declared) -> Bool {
        guard declared.host == "webview2" else { return false }
        return !(Edition.isDev && UserDefaults.standard.string(forKey: "xboxWebHost") == "edgehtml")
    }

    /// Where a game's phone page goes in the package, beside Web/, which the host serves to phones itself.
    static let phoneFolder = "Phone"

    /// The package's files: the host and WebView2's library at the top, the app's under Web/, and a game's phone page
    /// under Phone/.
    static func payload(_ files: [(path: String, data: Data)], phone: ControllerSnapshot? = nil) throws -> [(path: String, data: Data)] {
        guard let resources,
              let host = try? Data(contentsOf: resources.appendingPathComponent(program)),
              let core = try? Data(contentsOf: resources.appendingPathComponent(library)) else {
            throw MSIX.Failure(message: "Lamp's web host for the Xbox is missing from Lamp itself.")
        }
        return [(program, host), (library, core)] + files.map { (folder + "/" + $0.path, $0.data) }
            + (phone?.files ?? []).map { (phoneFolder + "/" + $0.path, $0.data) }
    }
}
