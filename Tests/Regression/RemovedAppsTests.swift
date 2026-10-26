import XCTest
@testable import Lamp

/// Deleting a wish disposes of the apps it took away as well as the ones it has: each identity an app left as is kept,
/// so its copies on devices, build and signing folders and sign-ins are found by the same id, instance and integration,
/// whether or not an app of its folder is there now.
final class RemovedAppsTests: XCTestCase {
    private var wish: LampProject!

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-removed-apps-\(UUID().uuidString)/Party")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
        wish = LampProject(id: "party", name: "Party", exe: "Party", dir: dir, instance: "party-1")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: wish.dir.deletingLastPathComponent())
    }

    /// A part of the wish, its scaffold written unless it's one taken away.
    private func part(_ kind: Platform, in folder: String, integration: String? = nil, places: [Destination]? = nil,
                      made: Bool = true) throws -> LampProject {
        try FileManager.default.createDirectory(at: wish.dir.appendingPathComponent(folder), withIntermediateDirectories: true)
        let part = LampProject(id: Parts.id(wish: wish.id, folder: folder), name: wish.name, exe: wish.exe,
                           dir: wish.dir.appendingPathComponent(folder), instance: Parts.instance(wish: wish, folder: folder),
                           platform: kind, integration: integration, places: places, partOf: wish.id)
        if made { try kind.target.recipe.fill(part) }
        return part
    }

    /// A game installed on an Xbox, then taken away, then its wish deleted: it's disposed of as the app it was.
    func testAnAppTakenAwayIsDisposedOfWithItsWish() throws {
        let game = try part(.game, in: "Game", integration: "xbox-one:game", places: [.mac, .device], made: false)
        let phone = try part(.iphone, in: "iPhone")
        RemovedApp.record(game, in: wish.dir)
        let disposed = RemovedApp.disposals(of: wish, parts: [phone])
        XCTAssertEqual(disposed.map(\.id), [phone.id, game.id])
        let again = try XCTUnwrap(disposed.last)
        XCTAssertEqual(again.instance, game.instance)
        XCTAssertEqual(again.deviceIntegration, "xbox-one")
        XCTAssertEqual(again.places, game.places)
        XCTAssertEqual(again.dir, game.dir)
        XCTAssertEqual(DeviceApps.buildFolder(for: again), DeviceApps.buildFolder(for: game))
        XCTAssertEqual(Devices.signingFolder(for: again), Devices.signingFolder(for: game))
        // Made again as it was, it's disposed of once, as the present app.
        XCTAssertEqual(RemovedApp.disposals(of: wish, parts: [phone, game]).map(\.id), [phone.id, game.id])
    }

    /// The Xbox game taken away and Game/ made again for the Mac alone: deleting the wish still takes the Xbox copy off,
    /// and a second removal keeps the first one's record beside its own.
    func testAnAppMadeAgainInTheSameFolderLeavesTheOneBeforeToDispose() throws {
        let xbox = try part(.game, in: "Game", integration: "xbox-one:game", places: [.mac, .device], made: false)
        RemovedApp.record(xbox, in: wish.dir)
        let mac = try part(.game, in: "Game", places: [.mac], made: false)
        let disposed = RemovedApp.disposals(of: wish, parts: [mac])
        XCTAssertEqual(disposed.map(\.deviceIntegration), [nil, "xbox-one"])
        RemovedApp.record(mac, in: wish.dir)
        RemovedApp.record(mac, in: wish.dir)
        XCTAssertEqual(RemovedApp.list(in: wish.dir).map(\.integration), ["xbox-one:game", nil], "one record per identity, none dropped")
        XCTAssertEqual(RemovedApp.disposals(of: wish, parts: []).map(\.deviceIntegration), ["xbox-one", nil])
    }

    /// The app in the wish's own folder, taken away, is disposed of too, unless a version brought it back as it was.
    func testTheFirstAppTakenAwayIsDisposedOfUnlessItCameBack() throws {
        let phone = try part(.iphone, in: "iPhone")
        RemovedApp.record(wish, in: wish.dir)
        RemovedApp.record(wish, in: wish.dir)
        XCTAssertFalse(wish.holdsApp)
        let disposed = RemovedApp.disposals(of: wish, parts: [phone])
        XCTAssertEqual(disposed.map(\.id), [phone.id, wish.id], "recorded once")
        XCTAssertFalse(try XCTUnwrap(disposed.last).isPart)
        XCTAssertEqual(disposed.last?.instance, wish.instance)
        // Its files back, as a version brings them: the scaffold, and the package Lamp writes before each build. The
        // wish's own app goes with the wish itself.
        try wish.platform.target.recipe.fill(wish)
        try "".write(to: wish.dir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        XCTAssertTrue(wish.holdsApp)
        XCTAssertEqual(RemovedApp.disposals(of: wish, parts: [phone]).map(\.id), [phone.id])
    }
}
