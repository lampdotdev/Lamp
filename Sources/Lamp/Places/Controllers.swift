import Foundation

/// The controllers a game names buttons for, a layout each: how a page tells one from the name or USB vendor the
/// controller reports, what's printed on its buttons, and how its badges are drawn. This is the one list of them: a
/// device's row names its controller by a layout's `id` here (`Place.Input`), checked against it, and a game's page is
/// given it as `Web/lamp-controllers.js`, which lamp-game.js reads instead of keeping one of its own.
struct ControllerLayout: Equatable {
    let id: String
    /// How the game's log says the player took it up.
    let spoken: String
    /// What the name the Gamepad API gives it holds (its USB vendor is in Chrome's), as a case-insensitive pattern.
    let match: String
    /// USB vendors, for a host that reads the controller itself and sends its vendor (`lampNativePad`).
    let vendors: [Int]
    /// What's printed on each part of the pad, by `BUTTON`'s names (and LT, RT, STICK_L, STICK_R); a part left out is
    /// called what the base layout calls it.
    let names: [String: String]
    /// The colors of the face buttons' letters or shapes.
    var faces: [String: String] = [:]
    /// The glyphs drawn on Menu and View, where the buttons carry symbols rather than words.
    var menuGlyphs: [String: String] = [:]
    /// The face buttons' symbols' CSS font size, where they need one of their own (a PlayStation's shapes run large).
    var faceSize: String? = nil
    /// Models of the layout that mark a button differently, told apart by the name they report.
    var variants: [(match: String, names: [String: String])] = []

    static func == (a: ControllerLayout, b: ControllerLayout) -> Bool { a.id == b.id }
}

enum Controllers {
    /// The layout a part's name falls back to, and a controller is taken as when nothing says which it is: the
    /// Gamepad API's standard layout is an Xbox controller's.
    static let base = "xbox"

    /// In the order a controller's name is matched against them: an Xbox's pattern is the broadest, so it's last.
    static let all: [ControllerLayout] = [
        ControllerLayout(id: "playstation", spoken: "a PlayStation controller", match: "054c|playstation|dualshock|dualsense", vendors: [0x054c],
                         names: ["A": "✕", "B": "○", "X": "□", "Y": "△", "LB": "L1", "RB": "R1", "LT": "L2", "RT": "R2",
                                 "MENU": "Options", "VIEW": "Create", "LSTICK": "L3", "RSTICK": "R3"],
                         faces: ["A": "#9aaeff", "B": "#ff6b70", "X": "#f48fd6", "Y": "#3fd5b0"], faceSize: ".95em",
                         variants: [(match: "dualshock|05c4|09cc", names: ["VIEW": "Share"])]),
        // A Switch controller's letters are the other way round from an Xbox's, and BUTTON.A is a place (the bottom
        // face button), so on a Switch it's the button marked B: a prompt names the letter printed on the button to
        // press, never the one in the same place on an Xbox.
        ControllerLayout(id: "switch", spoken: "a Switch controller", match: "057e|nintendo|pro controller|joy-?con", vendors: [0x057e],
                         names: ["A": "B", "B": "A", "X": "Y", "Y": "X", "LB": "L", "RB": "R", "LT": "ZL", "RT": "ZR", "MENU": "+", "VIEW": "−"]),
        ControllerLayout(id: "xbox", spoken: "an Xbox controller", match: "045e|xbox|xinput|microsoft", vendors: [0x045e],
                         names: ["A": "A", "B": "B", "X": "X", "Y": "Y", "LB": "LB", "RB": "RB", "LT": "LT", "RT": "RT", "MENU": "Menu",
                                 "VIEW": "View", "LSTICK": "LS", "RSTICK": "RS", "UP": "D-pad up", "DOWN": "D-pad down",
                                 "LEFT": "D-pad left", "RIGHT": "D-pad right", "STICK_L": "Left stick", "STICK_R": "Right stick"],
                         faces: ["A": "#5dc21e", "B": "#f04e3e", "X": "#2f8ee8", "Y": "#f2b51d"], menuGlyphs: ["MENU": "≡", "VIEW": "⧉"]),
    ]

    static var ids: [String] { all.map(\.id) }

    /// Why an input names a layout there isn't, or nil.
    static func problem(in input: Place.Input) -> String? {
        let unknown = [input.controller, input.layout].compactMap { $0 }.filter { !ids.contains($0) }
        guard !unknown.isEmpty else { return nil }
        return "input names a controller Lamp has no layout for (\(unknown.joined(separator: ", "))): it's one of \(ids.map { "\"\($0)\"" }.joined(separator: ", "))."
    }

    /// `Web/lamp-controllers.js`: the list as the page reads it.
    static var pageJS: String {
        let layouts: [[String: Any]] = all.map { layout in
            var row: [String: Any] = ["id": layout.id, "spoken": layout.spoken, "match": layout.match, "vendors": layout.vendors,
                                      "names": layout.names, "faces": layout.faces, "menuGlyphs": layout.menuGlyphs,
                                      "variants": layout.variants.map { ["match": $0.match, "names": $0.names] }]
            if let size = layout.faceSize { row["faceSize"] = size }
            return row
        }
        return "// Written by Lamp before every build; don't edit. The controllers a game names buttons for (Controllers).\n"
            + "export default \(GamePage.json(["base": base, "unknown": "a controller", "layouts": layouts]));\n"
    }
}
