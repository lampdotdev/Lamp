import Foundation

extension Platform {
    /// A web app for Samsung and LG TVs (`TVTemplate`), tried in a preview on this Mac and put on the person's TV.
    static let tv = Platform(kind: "tv")
}

extension Target {
    static let tv = Target(
        platform: .tv, places: [.tv],
        identity: Identity(name: "the TV app", phrase: "a TV app for Samsung and LG TVs", analytics: "tv", made: { _, _ in "Samsung and LG TVs" },
                           devices: Words(words: [("tv", "\"tv\" for Samsung and LG TVs",
                                                     "\"tv\" (alone) for a Samsung or LG TV, [\"tv\"] when they mention their TV, a Frame TV, the living room screen or watching from the sofa")],
                                            hint: nil, claims: { $0 == ["tv"] }, alone: false,
                                            // What's on the TV is what a wish with a TV app is about; the rest reach it.
                                            leads: true, asked: ("tv", "for the TV", "for Samsung and LG TVs")),
                           tryOnHelp: { _ in "Where it opens: the TV preview on this Mac, or one of your TVs" },
                           place: { _ in .elsewhere("TV", symbol: "tv") }),
        guidance: Guidance(prompt: { _ in Agent.tvPrompt() },
                           changeRules: { _ in Agent.Rules.tvEdit + Agent.Rules.tvFrameworks + Agent.Rules.tvDesign + Agent.Rules.tvKeys + Agent.Rules.tvData + Agent.Rules.tvTry },
                           skills: { ["phone-controllers"] },
                           // It reaches AI only through this Mac, over the same Wi‑Fi; the preview is on the Mac.
                           elsewhere: { _ in "- On the person's TV: the same, while it's on this Mac's Wi‑Fi with Lamp open; away from it, or with Lamp closed, no AI" }),
        // Its own files are its web code; Lamp's is its script, which marks the folder as a TV app.
        recipe: Recipe(language: .web, fill: TVTemplate.fill, ownedFiles: TVTemplate.writeOwnedFiles, support: TVTemplate.writeOwnedFiles,
                       isMade: TVTemplate.isTV, scaffolded: { dir, _ in TVTemplate.isTV(dir) },
                       sources: { _ in [TVTemplate.webFolder, TVTemplate.phoneFolder, "icon.json"] },
                       builtURL: { TVs.stagingFolder(for: $0).appendingPathComponent("web/index.html") }, marker: TVTemplate.supportFile,
                       shareRefusal: "Lamp doesn't share TV apps yet."),
        part: Part(folder: "TV", family: "tv", word: "tv", menu: ("TV App", "tv"), rules: { Agent.tvPrompt(part: $0) },
                   // How the wish's other apps reach the TV app.
                   wishRule: Agent.Rules.tvParts) { dir, wish in
            AppFile.read(dir.appendingPathComponent(TVTemplate.supportFile), inFolder: wish, last: 1) != nil
        },
        setup: .none)
}

extension Language {
    static let web = Language(name: "web", code: "the web code in Web/", leftover: "the rest of Web/") {
        "Write the app again as a TV app in Web/ (the scaffold is there), reading \($0) for what it does, then delete \($1) with delete_file. "
    }
}
