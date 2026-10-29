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
