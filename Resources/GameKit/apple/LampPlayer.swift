// Lamp's player: the one Mac app around a page (a game drawn with three.js, a screen, a web app), compiled once when
// Lamp is built and copied for every game and screen made on this Mac, so none of them waits on a build or needs
// Apple's tools. Nothing of any one game is in it: each copy reads what it is from its own bundle, which Lamp writes
// as it makes the copy: its name and id, what kind of page it is and where that's served (LampPlayer in Info.plist),
// what it's told about itself and Lamp (LampInstall, read by LampSupport.swift), its permission reasons and icon, and
// the page itself in Resources/Web.
//
// The same Swift as an app Lamp compiles around a page (LampWebGame.swift, LampWebApp.swift, LampPage.swift and
// LampSupport.swift), with what those have filled in by Lamp read here instead.
import SwiftUI

enum LampPlayer {
    private static let info = Bundle.main.object(forInfoDictionaryKey: "LampPlayer") as? [String: Any] ?? [:]

    /// The game's or screen's name, as Lamp wrote it.
    static var name: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? ProcessInfo.processInfo.processName
    }

    /// A game's window, or any other page's. A copy that says neither was made wrong: it stops, saying so, rather than
    /// open as something it isn't.
    static let isGame: Bool = {
        switch info["kind"] as? String {
        case "game": return true
        case "page": return false
        default: fatalError("This app's Info.plist doesn't say what kind of page it is (LampPlayer.kind).")
        }
    }()

    /// Where a page is served, which is where what it saves is kept: its kind's own address, for good. A game's is its
    /// own (`LampGamePage`); any other page has to name one of the addresses Lamp gives.
    static let scheme: String = {
        guard let scheme = info["scheme"] as? String, ["lamp-screen", "lamp-web-app"].contains(scheme) else {
            fatalError("This app's Info.plist doesn't name the address its page is served at (LampPlayer.scheme).")
        }
        return scheme
    }()

    /// The size a page made at a fixed size is laid out at ("1920x1080"), or nil for the window's.
    static var canvas: CGSize? {
        let sides = (info["canvas"] as? String)?.split(separator: "x").compactMap { Double($0) } ?? []
        return sides.count == 2 ? CGSize(width: sides[0], height: sides[1]) : nil
    }
}

if LampPlayer.isGame { LampGameApp.main() } else { LampWebApp.main() }
