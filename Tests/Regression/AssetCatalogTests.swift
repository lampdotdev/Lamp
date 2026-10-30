import XCTest
@testable import Lamp

/// Lamp's index of free assets offers only work anyone may use without asking, and what's fetched from it is credited
/// in the wish's credits.json, which every share, publish and repository carries.
final class AssetCatalogTests: XCTestCase {
    private let sha = String(repeating: "a", count: 64)

    private func index(_ assets: [[String: Any]], packLicense: String? = nil) -> Data {
        var pack: [String: Any] = ["id": "pack", "name": "Pack", "author": "Someone", "source": "https://example.com/pack", "kind": "prop",
                                   "style": "flat", "archive": ["url": "https://example.com/pack.zip", "sha256": sha, "bytes": 1], "assets": assets]
        if let packLicense { pack["license"] = packLicense }
        return try! JSONSerialization.data(withJSONObject: ["version": 1, "packs": [pack]])
    }

    private func model(_ id: String, license: String?, url: String = "https://example.com/m.glb", sha: String? = nil) -> [String: Any] {
        var asset: [String: Any] = ["id": "pack/\(id)", "name": id, "kind": "prop", "file": url, "sha256": sha ?? self.sha, "bytes": 1,
                                    "page": "https://example.com/\(id)"]
        if let license { asset["license"] = license }
        return asset
    }

    private func sheet(_ id: String, files: [String]) -> [String: Any] {
        ["id": "pack/\(id)", "name": id, "kind": "sprites", "files": files, "bytes": 1, "license": "CC0-1.0"]
    }

    /// Only CC0 and CC-BY are offered: non-commercial, own terms, no license, an address that isn't https, a file with no
    /// hash to check it by, or an archive path that leads out are all left out, and the shipped index holds none of them.
    func testOnlyWorkAnyoneMayUseIsOffered() throws {
        let items = AssetCatalog.items(from: index([
            model("free", license: "CC0-1.0"),
            model("credited", license: "CC-BY-3.0"),
            model("nc", license: "CC-BY-NC-4.0"),
            model("personal", license: "LicenseRef-personal-use"),
            model("share-alike", license: "CC-BY-SA-4.0"),
            model("none", license: nil),
            model("plain-http", license: "CC0-1.0", url: "http://example.com/m.glb"),
            model("unchecked", license: "CC0-1.0", sha: "nothex"),
            sheet("escape", files: ["../../.ssh/id.png"]),
            sheet("sheet", files: ["Sheets/a.png", "Sheets/a.xml"]),
        ]))
        XCTAssertEqual(items.map(\.name), ["free", "credited", "sheet"])
        XCTAssertTrue(items[0].creditAsPack, "CC0 work is credited as its pack")
        XCTAssertFalse(items[1].creditAsPack, "CC-BY work is credited as itself")
        XCTAssertTrue(AssetCatalog.items(from: index([model("inherits", license: nil)], packLicense: "CC-BY-NC-3.0")).isEmpty)

        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let shipped = try Data(contentsOf: root.appendingPathComponent("Resources/asset-catalog.json"))
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: shipped) as? [String: Any])
        let listed = (raw["packs"] as? [[String: Any]] ?? []).reduce(0) { $0 + (($1["assets"] as? [Any])?.count ?? 0) }
        XCTAssertGreaterThan(listed, 100)
        XCTAssertEqual(AssetCatalog.items(from: shipped).count, listed, "every asset in the shipped index may be offered")
    }

    private func clip(_ id: String, kind: String = "sound", files: [String]) -> [String: Any] {
        ["id": "pack/\(id)", "name": id, "kind": kind, "files": files, "bytes": 1, "license": "CC0-1.0"]
    }

    /// A sound or music is offered only as the sound files the runtimes decode, and pictures only as pictures: the kind
    /// and the file have to agree, and every other check holds for them as for a picture.
    func testSoundsAreOfferedOnlyAsSoundFiles() {
        var direct = model("loop", license: "CC0-1.0", url: "https://example.com/loop.ogg")
        direct["kind"] = "music"
        var directHTTP = model("plain", license: "CC0-1.0", url: "http://example.com/plain.ogg")
        directHTTP["kind"] = "music"
        var directMP3 = model("song", license: "CC0-1.0", url: "https://example.com/song.mp3")
        directMP3["kind"] = "music"
        var unchecked = model("unchecked", license: "CC0-1.0", url: "https://example.com/unchecked.wav", sha: "nothex")
        unchecked["kind"] = "sound"
        let items = AssetCatalog.items(from: index([
            direct, directHTTP, directMP3, unchecked,
            clip("coin", files: ["Sounds/coin.wav"]),
            clip("click", files: ["Audio/click.OGG"]),
            clip("escape", files: ["../../coin.wav"]),
            clip("program", files: ["Sounds/coin.command"]),
            clip("picture", files: ["Sounds/coin.png"]),
            clip("in-a-sheet", kind: "sprites", files: ["Sounds/coin.wav"]),
        ]))
        XCTAssertEqual(items.map(\.name), ["loop", "coin", "click"])
        XCTAssertTrue(items.allSatisfy(\.isAudio))
        XCTAssertNil(items[0].thumb, "a sound has no picture to fetch")
        XCTAssertEqual(AssetCatalog.search("", kind: "music", in: items).map(\.name), ["loop"])
        XCTAssertEqual(AssetCatalog.search("", kind: "model", in: items), [], "a sound is no 3D kind")
    }

    /// Files out of an archive land side by side in their pack's folder, so two from different folders with one name
    /// would have the second written over the first and both credited. The second is left out, however its name is
    /// cased, since a Mac's disk doesn't tell them apart. The same file listed twice is one file.
    func testTwoFilesLandingOnOneNameAreNotOffered() {
        let items = AssetCatalog.items(from: index([
            clip("first", files: ["A/coin.wav"]),
            clip("second", files: ["B/coin.wav"]),
            clip("cased", files: ["C/Coin.WAV"]),
            clip("same-file", files: ["A/coin.wav"]),
            clip("inside-one", files: ["D/jump.wav", "E/jump.wav"]),
            clip("other", files: ["B/jump.wav"]),
        ]))
        XCTAssertEqual(items.map(\.name), ["first", "same-file", "other"])
    }

    /// The shipped sounds are CC0, found by what a game asks for, in formats the catalog takes, with their length, and
    /// credited as their pack. A sound's line says how long it is and whether it loops.
    func testShippedSoundsAreFoundAndCredited() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let shipped = AssetCatalog.items(from: try Data(contentsOf: root.appendingPathComponent("Resources/asset-catalog.json")))
        let sounds = shipped.filter(\.isAudio)
        XCTAssertGreaterThan(sounds.count, 20)
        XCTAssertTrue(sounds.allSatisfy { $0.license == "CC0-1.0" }, "a CC-BY track needs credit the app shows, which these don't carry")
        XCTAssertTrue(sounds.allSatisfy { ($0.seconds ?? 0) > 0 })
        XCTAssertEqual(AssetCatalog.search("coin", kind: "sound", in: shipped).first?.id, "subspace-retro-sfx/coin")
        let menu = try XCTUnwrap(AssetCatalog.search("relaxed menu", kind: "music", in: shipped).first)
        XCTAssertEqual(menu.id, "subspace-music-loops/menu-relaxed")
        XCTAssertNotNil(menu.file, "one loop is fetched alone, not out of its pack's 33 MB archive")
        let line = AssetCatalog.line(menu, budget: nil)
        XCTAssertTrue(line.contains("55 s") && line.contains("loops"), line)

        let credits = AssetCatalog.credits(for: [(menu, ["Web/assets/subspace-music-loops/menu-relaxed.ogg"])])
        XCTAssertEqual(credits.upstream.map(\.name), ["12 Music Loops"])
        XCTAssertEqual(credits.upstream.first?.author, "Juhani Junkala (SubspaceAudio)")
        XCTAssertEqual(credits.upstream.first?.files, ["Web/assets/subspace-music-loops/menu-relaxed.ogg"])
    }

    /// What's fetched is credited with its files: a pack of CC0 work once, CC-BY work as itself, and a second fetch from
    /// the same pack adds its files to the same entry, which the About window shows with its license.
    func testFetchedAssetsAreCreditedWithTheirFiles() throws {
        let items = AssetCatalog.items(from: index([model("bench", license: "CC0-1.0"), model("lamp", license: "CC0-1.0"),
                                                      model("taxi", license: "CC-BY-3.0")]))
        let credits = AssetCatalog.credits(for: [(items[0], ["Web/assets/pack/bench.glb"]), (items[2], ["Web/assets/pack/taxi.glb"])])
        XCTAssertEqual(credits.upstream.map(\.name), ["Pack", "taxi"])
        XCTAssertEqual(credits.upstream[0].license, "CC0-1.0")
        XCTAssertEqual(credits.upstream[1].license, "CC-BY-3.0")
        XCTAssertEqual(credits.upstream[1].author, "Someone")
        XCTAssertEqual(credits.upstream.map(\.adapted), [false, false], "a game isn't based on the assets it uses")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-assets-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let project = LampProject(id: "town", name: "Town", exe: "Town", dir: root.appendingPathComponent("town"))
        try FileManager.default.createDirectory(at: project.dir.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
        try Credits.add(credits, to: project)
        try Credits.add(AssetCatalog.credits(for: [(items[1], ["Web/assets/pack/lamp.glb"])]), to: project)
        let kept = Credits.load(project)
        XCTAssertEqual(kept.upstream.count, 2)
        XCTAssertEqual(kept.upstream[0].files, ["Web/assets/pack/bench.glb", "Web/assets/pack/lamp.glb"])
        XCTAssertNil(kept.basis, "nothing fetched is what the wish is based on")
        XCTAssertTrue(try XCTUnwrap(kept.aboutPage).contains("<a href=\"https://example.com/taxi\">taxi</a> by Someone (CC-BY-3.0)"))
    }
}
