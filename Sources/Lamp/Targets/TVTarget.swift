import Foundation

extension Platform {
    /// A page shown full screen and glanced at from across a room (`TVTemplate`, `ScreenKit`): a TV app for Samsung and
    /// LG TVs, tried in a preview on this Mac and put on the person's TV, and, given those places too, a screen shown
    /// on this Mac, an iPhone or iPad and the Xbox (`LampProject.places`), the same page everywhere. An app from before
    /// screens has the TV as its one place.
    static let tv = Platform(kind: "tv")
}

extension Target {
    static let tv = Target(
        platform: .tv, places: [.mac, .ios, .tv, .device],
        identity: Identity(name: "the TV app", phrase: "a screen: a page shown full screen on a TV, this Mac, an iPad or an Xbox", analytics: "tv",
                           made: { _, _ in "Samsung and LG TVs" },
                           devices: Words(words: [("tv", "\"tv\" for Samsung and LG TVs",
                                                     "\"tv\" (alone) for a Samsung or LG TV, [\"tv\"] when they mention their TV, a Frame TV, the living room screen or watching from the sofa"),
                                                    ("screen", "\"screen\" for a screen shown elsewhere too (with \"mac\", \"ipad\", \"tv\" and \"xbox-one\" for where it's shown)",
                                                     "\"screen\" for something shown full screen and glanced at")],
                                            hint: "[\"screen\"] for something shown full screen and glanced at from across a room rather than used up close: "
                                                + "a family calendar or chore board, a photo frame or album slideshow, a dashboard, a scoreboard, a clock, "
                                                + "the day's weather; with \"tv\" when it's for their TV too, \"ipad\" on an iPad on a stand, \"xbox-one\" on "
                                                + "their Xbox. One that's only for their TV is [\"tv\"]. An app the person works in or plays is no screen",
                                            claims: { $0 == ["tv"] || ($0.contains("screen") && $0.allSatisfy { GameKit.placeWords.keys.contains($0) } && !$0.contains("game")) },
                                            alone: false,
                                            asked: ("tv", "for the TV", "for Samsung and LG TVs")),
                           tryOnHelp: { $0.openPlaces == [.tv] ? "Where it opens: the TV preview on this Mac, or one of your TVs"
                               : "Where it's shown: this Mac, an iPhone or iPad, one of your TVs, or your Xbox" },
                           place: { ScreenKit.hostsOnApple($0) ? .window : .elsewhere("TV", symbol: "tv") }),
        guidance: Guidance(prompt: { ScreenKit.hostsOnApple($0) || $0.openPlaces.contains(.device) ? Agent.screenPrompt(for: $0) : Agent.tvPrompt() },
                           changeRules: { ScreenKit.hostsOnApple($0) ? Agent.Rules.screenEdit + Agent.Rules.tvFrameworks + Agent.Rules.tvDesign + Agent.Rules.tvKeys
                                              + Agent.Rules.tvData + Agent.Rules.pageNative + Agent.Rules.tvTry
                                          : Agent.Rules.tvEdit + Agent.Rules.tvFrameworks + Agent.Rules.tvDesign + Agent.Rules.tvKeys + Agent.Rules.tvData + Agent.Rules.tvTry },
                           skills: { ["phone-controllers"] },
                           // It reaches AI only through this Mac, over the same Wi‑Fi; the preview is on the Mac.
                           elsewhere: { _ in "- On the person's TV, iPad or Xbox: the same, while it's on this Mac's Wi‑Fi with Lamp open; away from it, or with Lamp closed, no AI and no Lamp.wish link to the wish's other apps" }),
        // Its own files are its web code (and the Swift that answers its page's calls of the device, where it's shown on
        // Apple's devices); Lamp's is its script, which marks the folder as a TV app, and the app around the page.
        recipe: Recipe(language: .web, fill: ScreenKit.fill, ownedFiles: ScreenKit.write(for:), support: ScreenKit.write(for:),
                       isMade: TVTemplate.isTV, scaffolded: { dir, _ in TVTemplate.isTV(dir) },
                       sources: { [TVTemplate.webFolder, TVTemplate.phoneFolder, "icon.json"] + (ScreenKit.hostsOnApple($0) ? ["Sources"] : []) },
                       inputs: { ScreenKit.hostsOnApple($0) ? ScreenKit.stamp : nil },
                       builtURL: { project in
                           project.onTV ? TVs.stagingFolder(for: project).appendingPathComponent("web/index.html")
                               : project.onDevice ? DeviceApps.packageURL(for: project)
                               : project.dir.appendingPathComponent(project.onIOS ? "build/iOS/\(project.exe).app" : "build/\(project.exe).app")
                       },
                       marker: TVTemplate.supportFile,
                       // Its web files travel in a shared file (`TVFiles`), as a Swift app's sources do.
                       shareRefusal: nil),
        part: Part(folder: "TV", family: "tv", word: "tv", menu: ("TV App", "tv"), rules: { Agent.tvPrompt(part: $0) },
                   // How the wish's other apps reach the TV app.
                   wishRule: Agent.Rules.tvParts) { dir, wish in
            AppFile.read(dir.appendingPathComponent(TVTemplate.supportFile), inFolder: wish, last: 1) != nil
        },
        setup: .none,
        startsAt: [.tv])
}

extension Language {
    static let web = Language(name: "web", code: "the web code in Web/", leftover: "the rest of Web/") {
        "Write the app again as a TV app in Web/ (the scaffold is there), reading \($0) for what it does, then delete \($1) with delete_file. "
    }
}
