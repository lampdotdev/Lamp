import XCTest
@testable import Lamp

/// A device picked under Try On is chosen only once its check answers; a choice made meanwhile, the one already saved
/// included, is the one that stands.
@MainActor
final class AndroidDeviceChoiceTests: XCTestCase {
    private var root: URL!

    override func tearDown() {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    /// A store with one Android TV app, opening in the TV emulator, whose device checks wait until the test answers them.
    private func store() throws -> (Store, LampProject, () -> [() -> Void]) {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-android-choice-\(UUID().uuidString)")
        let dir = root.appendingPathComponent("living-room")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
        try #"{"name":"Living Room","exe":"LivingRoom","platform":"android-tv"}"#
            .write(to: dir.appendingPathComponent(".lamp/meta.json"), atomically: true, encoding: .utf8)
        try "rootProject.name = \"LivingRoom\"\n".write(to: dir.appendingPathComponent(Template.androidSettingsFile), atomically: true, encoding: .utf8)
        try "\n".write(to: dir.appendingPathComponent(Template.androidTVMarker), atomically: true, encoding: .utf8)
        let store = Store(testingAt: root)
        var answers: [() -> Void] = []
        store.checkAndroidDevice = { _, then in answers.append(then) }
        let app = try XCTUnwrap(store.projects.first { $0.id == "living-room" })
        XCTAssertNil(app.device)
        XCTAssertEqual(app.destination, .androidTV)
        return (store, app, { answers })
    }

    func testTheEmulatorChosenAgainDuringTheCheckStays() throws {
        let (store, app, answers) = try store()
        store.tryOn(app, "androidtv:192.168.1.30:5555")
        store.tryOn(app, "emulator:tv")
        XCTAssertEqual(answers().count, 1)
        answers()[0]()
        XCTAssertNil(store.current(app)?.device, "the device's check answered after the emulator was chosen again")
    }

    func testOnlyTheLastOfTwoDevicesIsChosen() throws {
        let (store, app, answers) = try store()
        store.tryOn(app, "androidtv:192.168.1.30:5555")
        store.tryOn(app, "androidtv:192.168.1.31:5555")
        XCTAssertEqual(answers().count, 2)
        answers()[1]()
        XCTAssertEqual(store.current(app)?.device, "192.168.1.31:5555")
        // The change to the second is done (its turn over) before the first's check answers.
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        answers()[0]()
        XCTAssertEqual(store.current(app)?.device, "192.168.1.31:5555")
    }
}
