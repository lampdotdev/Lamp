import XCTest
@testable import Lamp

/// A wish can be more than one app (`Parts`): a TV app with an iPhone app that controls it.
final class WishPartsTests: XCTestCase {
    /// "A TV app that I can control with my phone" is a TV app and an iPhone app, made to work together; "both", to
    /// "TV, Mac or both?", is a TV app and a Mac app.
    func testATVAppControlledFromThePhoneIsATVAppWithAnIPhoneApp() throws {
        let remote = try XCTUnwrap(Parts.kinds(for: ["tv", "iphone"]))
        XCTAssertEqual(remote.main, .tv)
        XCTAssertEqual(remote.parts, [.iphone])
        let both = try XCTUnwrap(Parts.kinds(for: ["tv", "mac"]))
        XCTAssertEqual(both.main, .tv)
        XCTAssertEqual(both.parts, [.mac])
    }

    /// A part's folder is inside its wish's, which the agent may swap for a link: the part's own folder, which its build's
    /// sandbox opens, is still found by name under the wish's, never where that link leads.
    func testAPartsFolderIsNeverWhereALinkInPlaceOfItsWishLeads() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("wish-parts-\(UUID().uuidString)").resolvingSymlinksInPath()
        defer { try? fm.removeItem(at: root) }
        let apps = root.appendingPathComponent("Apps"), elsewhere = root.appendingPathComponent("elsewhere")
        try fm.createDirectory(at: apps, withIntermediateDirectories: true)
        try fm.createDirectory(at: elsewhere.appendingPathComponent("iPhone"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: apps.appendingPathComponent("remote"), withDestinationURL: elsewhere)
        let part = LampProject(id: "remote.iphone", name: "Remote", exe: "Remote", dir: apps.appendingPathComponent("remote/iPhone"),
                               platform: .iphone, partOf: "remote")
        XCTAssertEqual(part.realDir.path, apps.appendingPathComponent("remote/iPhone").path)
    }
}

/// What a wish of several apps keeps through what Lamp does to it, read off its folder as Lamp reads it.
final class WishPartsKeptTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("wish-parts-kept-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    /// A wish folder holding a TV app and, in iPhone/, an iPhone app, as `make_app_for` leaves it.
    private func remote(meta: String) throws -> URL {
        let wish = root.appendingPathComponent("remote")
        let phone = wish.appendingPathComponent("iPhone")
        try FileManager.default.createDirectory(at: wish.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: wish.appendingPathComponent("Web"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: phone.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
        try meta.write(to: wish.appendingPathComponent(".lamp/meta.json"), atomically: true, encoding: .utf8)
        try "".write(to: wish.appendingPathComponent("Web/lamp.js"), atomically: true, encoding: .utf8)
        try #"{"name":"Remote","exe":"Remote","platform":"iphone"}"#.write(to: phone.appendingPathComponent(".lamp/meta.json"), atomically: true, encoding: .utf8)
        try #"let package = Package(name: "Remote", platforms: [.iOS(.v17)])"#.write(to: phone.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        return wish
    }

    /// A rename writes the wish's meta.json again, and wrote it without the list of its parts: the iPhone app was still
    /// in its folder and gone from the wish. Its parts are found from its files, so whatever meta.json says, it has them.
    func testARenamedWishStillHasItsIPhoneApp() throws {
        let wish = try remote(meta: #"{"name":"Remote QA","exe":"Remote","platform":"tv"}"#)
        let read = try XCTUnwrap(Store.readWish(at: wish))
        XCTAssertEqual(read.partFolders, ["iPhone"])
        XCTAssertEqual(Parts.load(read).map(\.platform), [.iphone])
    }

    /// An Undo of the request that added the iPhone app takes its files away; Lamp's own files in its folder stay, and
    /// must not keep the part.
    func testAPartGoesWithItsFiles() throws {
        let wish = try remote(meta: #"{"name":"Remote","exe":"Remote","platform":"tv","parts":["iPhone"]}"#)
        try FileManager.default.removeItem(at: wish.appendingPathComponent("iPhone/Package.swift"))
        XCTAssertEqual(try XCTUnwrap(Store.readWish(at: wish)).partFolders, [])
    }

    /// "Make it work on my Mac too" changes the iPhone app in place into one for both, in the same folder: it's still
    /// the wish's, not gone because iPhone/ now holds an app for both.
    func testAnIPhoneAppMadeForTheMacTooStaysAPart() throws {
        let wish = try remote(meta: #"{"name":"Remote","exe":"Remote","platform":"tv"}"#)
        try #"let package = Package(name: "Remote", platforms: [.macOS(.v14), .iOS(.v17)])"#
            .write(to: wish.appendingPathComponent("iPhone/Package.swift"), atomically: true, encoding: .utf8)
        let read = try XCTUnwrap(Store.readWish(at: wish))
        XCTAssertEqual(read.partFolders, ["iPhone"])
        XCTAssertEqual(Parts.load(read).map(\.platform), [.universal])
    }

    /// Undo of "make the iPhone app work on the Mac too" puts iPhone/ back to an iPhone app in the same folder: the part
    /// Lamp has listed (an app for both) no longer matches its files, so a restore lists it again.
    func testARestoreThatChangesAPartsKindInPlaceIsSeen() throws {
        let wish = try remote(meta: #"{"name":"Remote","exe":"Remote","platform":"tv"}"#)
        let listed = LampProject(id: "remote.iphone", name: "Remote", exe: "Remote", dir: wish.appendingPathComponent("iPhone"),
                                 platform: .universal, partOf: "remote")
        XCTAssertFalse(Parts.match([listed], filesOf: wish))
        XCTAssertTrue(Parts.match(Parts.load(try XCTUnwrap(Store.readWish(at: wish))), filesOf: wish))
    }

    /// A new wish whose request could be for the TV or the Mac waits to be asked. It's named on its first request,
    /// and naming it wrote it again without that, so it was made a Mac app without asking.
    func testNamingAWishKeepsWhatItIsStillToBeToldAndItsParts() {
        let draft = LampProject(id: "untitled", name: "Untitled", exe: "Untitled", dir: root.appendingPathComponent("untitled"),
                                instance: "a", untitled: true, platform: .tv, partFolders: ["iPhone"], undecided: ["tv", "mac"])
        let named = draft.named("Family Slideshow", id: "familyslideshow", exe: "FamilySlideshow", dir: root.appendingPathComponent("familyslideshow"))
        XCTAssertEqual(named.undecided, ["tv", "mac"])
        XCTAssertEqual(named.partFolders, ["iPhone"])
        XCTAssertEqual(named.platform, .tv)
        XCTAssertEqual(named.instance, "a")
        XCTAssertFalse(named.untitled)
    }

    /// A wish's Mac app looked for its own files (its pictures, its runtime folder) at Lamp's apps folder and its id,
    /// "familyalbum.mac", where nothing is: it opened empty. It's told where its folder is.
    @MainActor func testAPartIsToldWhereItsFolderIs() {
        let wish = root.appendingPathComponent("familyalbum")
        let part = LampProject(id: "familyalbum.mac", name: "Family Album", exe: "FamilyAlbum", dir: wish.appendingPathComponent("Mac"),
                               platform: .mac, partOf: "familyalbum")
        XCTAssertEqual(Template.installValues(for: part)["folder"], "familyalbum/Mac")
        let plain = LampProject(id: "familyalbum", name: "Family Album", exe: "FamilyAlbum", dir: wish, platform: .tv)
        XCTAssertEqual(Template.installValues(for: plain)["folder"], "familyalbum")
    }

    /// Lamp's own request to carry on after a part's Reload started a turn of the part's own, with no prompt of its
    /// own and saving in a folder that isn't a repository ("couldn't save this change as a version"). It's the wish's.
    func testAPartsRequestGoesToItsWish() {
        let wish = LampProject(id: "familyalbum", name: "Family Album", exe: "FamilyAlbum", dir: root.appendingPathComponent("familyalbum"), platform: .tv)
        let part = LampProject(id: "familyalbum.mac", name: "Family Album", exe: "FamilyAlbum", dir: wish.dir.appendingPathComponent("Mac"),
                               platform: .mac, partOf: "familyalbum")
        XCTAssertEqual(Store.requestOwner(of: part, among: [wish, part]).id, "familyalbum")
        XCTAssertEqual(Store.requestOwner(of: wish, among: [wish, part]).id, "familyalbum")
    }

    /// A TV app whose phones are its wish's iPhone app takes them as players whatever the list of Lamp's apps holds at
    /// the moment: Lamp reading its apps again set the list without the parts first, which ended the game and left the
    /// phone waiting with the TV running.
    func testATVAppWithAnIPhoneAppTakesPlayersWhileLampReadsItsApps() throws {
        let wish = try XCTUnwrap(Store.readWish(at: try remote(meta: #"{"name":"Remote","exe":"Remote","platform":"tv"}"#)))
        XCTAssertTrue(Store.takesPlayers(wish))
    }

    /// "Make it work on my Mac too" changes a TV wish's iPhone app in place, so the app for both is still in iPhone/;
    /// the rules Lamp names for it said every path was in Apple/, where nothing is.
    func testTheRulesOfAnIPhoneAppMadeForTheMacTooAreForItsOwnFolder() throws {
        let wish = try remote(meta: #"{"name":"Remote","exe":"Remote","platform":"tv"}"#)
        try #"let package = Package(name: "Remote", platforms: [.macOS(.v14), .iOS(.v17)])"#
            .write(to: wish.appendingPathComponent("iPhone/Package.swift"), atomically: true, encoding: .utf8)
        let parts = Parts.load(try XCTUnwrap(Store.readWish(at: wish)))
        XCTAssertEqual(parts.map(\.platform), [.universal])
        let (status, answer) = Skills.read(["name": Parts.skill(for: .universal)], from: Skills.readable(parts: parts))
        XCTAssertEqual(status, 200)
        let rules = try XCTUnwrap(answer["text"] as? String)
        XCTAssertTrue(rules.contains("the part of the wish in iPhone/"), rules.prefix(400) + "…")
        XCTAssertFalse(rules.contains("Apple/"))
    }

    /// A TV wish's iPhone app is a part, not the app at its root: the agent asking to set up its AI away from home was
    /// told "`away` is only for iPhone apps".
    func testATVWishWithAnIPhoneAppCanBeOfferedSetupAwayFromHome() throws {
        let wish = try XCTUnwrap(Store.readWish(at: try remote(meta: #"{"name":"Remote","exe":"Remote","platform":"tv"}"#)))
        XCTAssertTrue(Store.hasPhoneApp(wish, parts: Parts.load(wish)))
        XCTAssertFalse(Store.hasPhoneApp(LampProject(id: "slides", name: "Slides", exe: "Slides", dir: root.appendingPathComponent("slides"), platform: .tv), parts: []))
    }
}
