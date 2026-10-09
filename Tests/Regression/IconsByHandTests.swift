import XCTest
@testable import Lamp

/// Icon artwork can be the person's own to draw, in Image Playground: a choice beside the models in
/// Settings → Building. Chosen, Lamp draws no icon and asks for no key; it offers the drawing in the chat.
final class IconsByHandTests: XCTestCase {
    private let models = ["google/gemini-3.1-flash-image", "openai/gpt-image-2"]

    // MARK: The choice

    func testByHandNeedsBothTheChoiceAndImagePlayground() {
        XCTAssertTrue(Icons.drawnByHand(choice: Icons.byHand, available: true))
        // Apple Intelligence turned off: the choice is kept, and Lamp carries on as if it hadn't been made.
        XCTAssertFalse(Icons.drawnByHand(choice: Icons.byHand, available: false))
        XCTAssertFalse(Icons.drawnByHand(choice: models[0], available: true))
        XCTAssertFalse(Icons.drawnByHand(choice: nil, available: true))
    }

    func testWithByHandSavedTheModelThatWouldDrawIsTheAppsOne() {
        let defaults = UserDefaults.standard
        let before = defaults.string(forKey: "iconModel")
        defer { defaults.set(before, forKey: "iconModel") }
        Icons.iconChoice = Icons.byHand
        XCTAssertEqual(Icons.iconModel, Icons.artModel)
        Icons.iconChoice = nil
        XCTAssertNil(defaults.string(forKey: "iconModel"))
        XCTAssertEqual(Icons.iconModel, Icons.artModel)
    }

    // MARK: What Settings shows

    func testChosenAsTheOnlyThingItCanStillBeUndone() {
        XCTAssertEqual(setting(models: [], byHandAvailable: true, byHandChosen: true),
                       .menu(ids: [Icons.byHand, Icons.noChoice], selected: Icons.byHand))
    }

    func testByHandIsAnEntryBesideTheModels() {
        XCTAssertEqual(setting(models: models, selection: models[1], byHandAvailable: true, byHandChosen: false),
                       .menu(ids: models + [Icons.byHand], selected: models[1]))
        XCTAssertEqual(setting(models: models, selection: models[1], byHandAvailable: true, byHandChosen: true),
                       .menu(ids: models + [Icons.byHand], selected: Icons.byHand))
        // One model is a menu too once there's another thing to choose.
        XCTAssertEqual(setting(models: [models[0]], selection: models[0], byHandAvailable: true, byHandChosen: false),
                       .menu(ids: [models[0], Icons.byHand], selected: models[0]))
    }

    func testCodexDrawingWithItsOwnModelIsAnEntryToo() {
        XCTAssertEqual(setting(models: [], drawer: "ChatGPT Codex", byHandAvailable: true, byHandChosen: true),
                       .menu(ids: [Icons.noChoice, Icons.byHand], selected: Icons.byHand))
        XCTAssertEqual(setting(models: [], drawer: "ChatGPT Codex", byHandAvailable: true, byHandChosen: false),
                       .menu(ids: [Icons.noChoice, Icons.byHand], selected: Icons.noChoice))
    }

    func testWithoutImagePlaygroundTheRowIsAsItWas() {
        // Chosen, then gone from this Mac: never a choice on screen that can't be used.
        XCTAssertEqual(setting(models: models, selection: "gone", byHandAvailable: false, byHandChosen: true),
                       .menu(ids: models, selected: models[0]))
        XCTAssertEqual(setting(models: [models[0]], byHandAvailable: false, byHandChosen: false), .named(models[0]))
        XCTAssertEqual(setting(models: [], drawer: "ChatGPT Codex", byHandAvailable: false, byHandChosen: false),
                       .named(Icons.noChoice))
    }

    func testTheMenuEndsInTheWayToAddAKey() {
        // With Image Playground the only entry, the key and download offers under Not Ready are gone: the
        // menu's last entry leads to where they're added.
        XCTAssertEqual(Icons.menuPick(Icons.configureProviders, forIcons: true), .providers)
        XCTAssertEqual(Icons.menuPick(Icons.configureProviders, forIcons: false), .providers)
        XCTAssertEqual(Icons.menuPick(Icons.noChoice, forIcons: true), .clear)
        XCTAssertEqual(Icons.menuPick(Icons.byHand, forIcons: true), .choose(Icons.byHand))
        XCTAssertEqual(Icons.menuPick(models[0], forIcons: false), .choose(models[0]))
        // It's no model's id, nor any other entry's.
        XCTAssertFalse(Icons.artModels.map(\.id).contains(Icons.configureProviders))
        XCTAssertFalse([Icons.byHand, Icons.noChoice, Icons.localArt].contains(Icons.configureProviders))
    }

    func testALineSeparatesGroupsOfEntriesAndIsNeverOneOfThem() {
        // A line drawn with the Image Playground entry was what the closed menu showed once a key had put
        // models above it: a blank where the choice's name belongs.
        XCTAssertEqual(Icons.menuGroups(models + [Icons.byHand]), [models, [Icons.byHand]])
        XCTAssertEqual(Icons.menuGroups([Icons.byHand, Icons.noChoice]), [[Icons.byHand], [Icons.noChoice]])
        XCTAssertEqual(Icons.menuGroups([Icons.noChoice, Icons.byHand]), [[Icons.noChoice], [Icons.byHand]])
        XCTAssertEqual(Icons.menuGroups(models), [models])
    }

    private func setting(models: [String], selection: String = "", drawer: String? = nil, byHandAvailable: Bool,
                         byHandChosen: Bool) -> Icons.ArtMenu {
        Icons.artMenu(models: models, selection: selection, drawer: drawer, byHandAvailable: byHandAvailable,
                         byHandChosen: byHandChosen)
    }

    // MARK: What the resolver says

    @MainActor func testIconArtworkIsAnsweredByTheResolver() {
        let defaults = UserDefaults.standard
        let before = defaults.string(forKey: "iconModel")
        defer { defaults.set(before, forKey: "iconModel") }

        // Chosen: the person is what answers, key or no key, on a Mac that has Image Playground. Without
        // it the choice counts for nothing and icons are answered as pictures are.
        Icons.iconChoice = Icons.byHand
        let chosen = AppAI.resolve(.pictures, in: .icon)
        if Icons.playgroundAvailable {
            XCTAssertEqual(chosen.tier, .best)
            XCTAssertEqual(chosen.provider, Icons.byHand)
            XCTAssertEqual(chosen.upgrades, [])
            XCTAssertTrue(AppAI.iconsByHand)
        } else {
            XCTAssertEqual(chosen.tier, AppAI.resolve(.pictures).tier)
            XCTAssertFalse(AppAI.iconsByHand)
        }

        // Not chosen: answered as pictures are, and where nothing draws, drawing by hand is one more way.
        Icons.iconChoice = nil
        let pictures = AppAI.resolve(.pictures)
        let icon = AppAI.resolve(.pictures, in: .icon)
        XCTAssertFalse(AppAI.iconsByHand)
        XCTAssertEqual(icon.tier, pictures.tier)
        XCTAssertEqual(icon.answer, pictures.answer)
        XCTAssertEqual(icon.upgrades, pictures.tier == .none ? pictures.upgrades + [.drawIcons] : pictures.upgrades)
    }

    @MainActor func testDrawingByHandIsNeverOfferedForPicturesInsideApps() {
        let defaults = UserDefaults.standard
        let before = defaults.string(forKey: "iconModel")
        defer { defaults.set(before, forKey: "iconModel") }
        for choice in [nil, Icons.byHand] {
            Icons.iconChoice = choice
            // The choice is for icons: an app's pictures are answered, and offered, as if it weren't there.
            for context in [AIContext.mac, .phoneAway] {
                let resolution = AppAI.resolve(.pictures, in: context)
                XCTAssertFalse(resolution.upgrades.contains(.drawIcons))
                XCTAssertNotEqual(resolution.provider, Icons.byHand)
            }
        }
    }

    func testTheIconsCardAsksAboutIconArtwork() {
        XCTAssertEqual(SetupOffer(capability: .pictures, icon: true).context, .icon)
        XCTAssertEqual(SetupOffer(capability: .pictures).context, .mac)
        XCTAssertEqual(SetupOffer(capability: .pictures, away: true).context, .phoneAway)
    }

    // MARK: The card and the line in the chat

    func testAnIconCardIsTheSameOfferAsAPictureCard() throws {
        // One card per capability per app: an app with the icon's card isn't given another for its pictures.
        let icon = SetupOffer(capability: .pictures, icon: true)
        XCTAssertEqual(icon, SetupOffer(capability: .pictures))
        XCTAssertTrue(Set([icon]).contains(SetupOffer(capability: .pictures)))
        XCTAssertNotEqual(icon, SetupOffer(capability: .pictures, away: true))
        XCTAssertNotEqual(icon, SetupOffer(capability: .text))
        // It still knows it's about the icon after a trip through the chat's file.
        let line = LogLine(kind: .offer, text: "Nothing on this Mac can draw pictures yet.", offer: icon)
        let read = try JSONDecoder().decode(LogLine.self, from: JSONEncoder().encode(line))
        XCTAssertEqual(read.setupOffer?.icon, true)
    }

    func testACardFromBeforeIsNotAboutTheIcon() throws {
        let saved = #"{"id":"6F1C8E2A-3B9D-4C1E-9A7F-2D5B8E0C4A12","kind":"offer","text":"Recipe Box just tried to make a picture.","offer":{"capability":"pictures"}}"#
        let line = try JSONDecoder().decode(LogLine.self, from: Data(saved.utf8))
        XCTAssertNil(line.setupOffer?.icon)
    }

    func testTheOfferToDrawLastsOnlyWhileThereIsSomethingToDraw() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("IconsByHandTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let project = LampProject(id: "tide-times", name: "Tide Times", exe: "TideTimes", dir: dir)
        // No design yet: nothing to draw for.
        XCTAssertFalse(Icons.awaitsDrawing("anything", in: project, byHand: true))

        let spec = IconSpec(subject: "a blue wave over a sandy beach", symbol: "water.waves", background: "sky", tint: "#2f7fd6")
        Icons.save(spec, for: project)
        let key = Icons.artKey(project, spec: spec)
        XCTAssertTrue(Icons.awaitsDrawing(key, in: project, byHand: true))
        // Icons are no longer drawn by hand (the choice changed, or Image Playground went).
        XCTAssertFalse(Icons.awaitsDrawing(key, in: project, byHand: false))

        // The icon was designed again: the line for the old design has nothing to offer.
        var redesigned = spec
        redesigned.subject = "a red lighthouse"
        Icons.save(redesigned, for: project)
        XCTAssertFalse(Icons.awaitsDrawing(key, in: project, byHand: true))
        let newKey = Icons.artKey(project, spec: redesigned)
        XCTAssertTrue(Icons.awaitsDrawing(newKey, in: project, byHand: true))

        // Drawn: the artwork is there.
        let art = Icons.artURL(project, spec: redesigned)
        try FileManager.default.createDirectory(at: art.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
                                                    samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: art)
        XCTAssertFalse(Icons.awaitsDrawing(newKey, in: project, byHand: true))
    }

    func testTheDrawingIsOfferedOncePerDesignAndNotBesideTheIconsCard() {
        let reply = LogLine(kind: .agent, text: "Tide Times is ready.")
        XCTAssertTrue(LogLine.offersDrawing("a.png", after: [reply]))
        XCTAssertFalse(LogLine.offersDrawing("a.png", after: [reply, LogLine(kind: .drawIcon, text: "a.png")]))
        // A new design gets its own line.
        XCTAssertTrue(LogLine.offersDrawing("b.png", after: [reply, LogLine(kind: .drawIcon, text: "a.png")]))
        // The card about the icon has the button, whatever the design.
        let card = LogLine(kind: .offer, text: "Nothing on this Mac can draw pictures yet.", offer: SetupOffer(capability: .pictures, icon: true))
        XCTAssertFalse(LogLine.offersDrawing("a.png", after: [reply, card]))
        // A card about pictures inside the app says nothing about its icon.
        let pictures = LogLine(kind: .offer, text: "Tide Times just tried to make a picture.", offer: SetupOffer(capability: .pictures))
        XCTAssertTrue(LogLine.offersDrawing("a.png", after: [reply, pictures]))
    }

    func testTheDrawingIsOfferedWhenTheTurnFinishesNotDuringIt() {
        let lines = [LogLine(kind: .user, text: "A tip calculator"), LogLine(kind: .status, text: "Building…")]
        // The agent builds and opens the app to look at it mid-turn: the offer waits for the turn's end.
        XCTAssertEqual(LogLine.drawingOffer("a.png", after: lines, built: true, inTurn: true), .held)
        XCTAssertEqual(LogLine.drawingOffer("a.png", after: lines, built: true, inTurn: false), .now)
        // Before there's an app there's nothing to hold: the install that makes one asks again.
        XCTAssertEqual(LogLine.drawingOffer("a.png", after: lines, built: false, inTurn: true), .none)
        XCTAssertEqual(LogLine.drawingOffer("a.png", after: lines, built: false, inTurn: false), .none)
        // Offered already for this design: not held for a second line either.
        let offered = lines + [LogLine(kind: .drawIcon, text: "a.png")]
        XCTAssertEqual(LogLine.drawingOffer("a.png", after: offered, built: true, inTurn: true), .none)
        XCTAssertEqual(LogLine.drawingOffer("b.png", after: offered, built: true, inTurn: true), .held)
    }

    func testAPictureOfferTakesThePlaceOfAnAnsweredIconCard() {
        let reply = LogLine(kind: .agent, text: "Tide Times is ready.")
        let iconCard = LogLine(kind: .offer, text: "Nothing on this Mac can draw pictures yet.", offer: SetupOffer(capability: .pictures, icon: true))
        let pictures = SetupOffer(capability: .pictures)
        XCTAssertEqual(LogLine.standing(of: pictures, in: [reply], iconAnswered: true), .new)
        // Folded to All set (the person draws icons, or Settings' model does while the app's own choice
        // can't), the icon's card would leave the app's pictures with no way to be set up: the app's own
        // request replaces it.
        XCTAssertEqual(LogLine.standing(of: pictures, in: [reply, iconCard], iconAnswered: true), .replaces(1))
        // Still open (nothing answers the icon), it offers the same ways: one card is enough.
        XCTAssertEqual(LogLine.standing(of: pictures, in: [reply, iconCard], iconAnswered: false), .offered)
        // The icon's card isn't raised again over itself, nor over a card about the app's pictures.
        XCTAssertEqual(LogLine.standing(of: SetupOffer(capability: .pictures, icon: true), in: [reply, iconCard], iconAnswered: true), .offered)
        let picturesCard = LogLine(kind: .offer, text: "Tide Times just tried to make a picture.", offer: pictures)
        XCTAssertEqual(LogLine.standing(of: pictures, in: [reply, picturesCard], iconAnswered: true), .offered)
        XCTAssertEqual(LogLine.standing(of: SetupOffer(capability: .text), in: [reply, iconCard], iconAnswered: true), .new)
    }

    func testTheLineInTheChatSurvivesItsFile() throws {
        let line = LogLine(kind: .drawIcon, text: "0123456789abcdef.png")
        let read = try JSONDecoder().decode(LogLine.self, from: JSONEncoder().encode(line))
        XCTAssertEqual(read.kind, .drawIcon)
        XCTAssertEqual(read.text, "0123456789abcdef.png")
        XCTAssertNil(read.setupOffer)
    }
}
