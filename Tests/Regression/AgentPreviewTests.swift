import XCTest
@testable import Lamp

/// The agent looks at and uses an app only in a preview on this Mac (`AgentPreview`), whatever Try On points at: the
/// person's own phone, Android device or TV is theirs, and stays what their Play and Reload deliver to.
final class AgentPreviewTests: XCTestCase {
    private func app(_ platform: Platform, at place: Destination, device: String?) -> LampProject {
        var project = LampProject(id: "pocket", name: "Pocket", exe: "Pocket", dir: URL(fileURLWithPath: "/tmp/pocket"), platform: platform)
        project.chosen = place
        project.device = device
        return project
    }

    /// Try On points at a device record of the person's: the agent's look and use go to that place's preview on this Mac,
    /// with the simulator chosen under Try On kept, while the app as it's kept, which Play and Reload install from, still
    /// names the device.
    func testTryOnAtTheirOwnDeviceIsLookedAtAndUsedInItsPreview() {
        var phone = app(.iphone, at: .ios, device: "00008110-001A2B3C4D5E801E")
        phone.simulator = "6B1F2C3D-4E5F-4A6B-8C7D-9E0F1A2B3C4D"
        let simulator = AgentPreview.app(for: phone)
        XCTAssertEqual(simulator?.id, phone.id)
        XCTAssertEqual(simulator?.destination, .ios)
        XCTAssertNil(simulator?.device, "looked at in the simulator, not on their phone")
        XCTAssertEqual(simulator?.simulator, phone.simulator)
        XCTAssertEqual(phone.device, "00008110-001A2B3C4D5E801E", "Play and Reload still put it on their phone")

        let android = app(.android, at: .android, device: "R58M42ABCDE")
        XCTAssertEqual(AgentPreview.app(for: android)?.destination, .android)
        XCTAssertNil(AgentPreview.app(for: android)?.device, "Lamp's emulator, not their phone")
        XCTAssertEqual(android.device, "R58M42ABCDE")
        let networked = app(.android, at: .android, device: "192.168.1.40:5555")
        XCTAssertNil(AgentPreview.app(for: networked)?.device)
        // One of Lamp's own emulators picked under Try On is a preview, by the serial adb gives it.
        let emulator = Emulator.Kind.phone.serial
        XCTAssertEqual(AgentPreview.app(for: app(.android, at: .android, device: emulator))?.device, emulator)

        let tv = app(.tv, at: .tv, device: "samsung:living-room")
        XCTAssertEqual(AgentPreview.app(for: tv)?.destination, .tv)
        XCTAssertNil(AgentPreview.app(for: tv)?.device, "the TV preview, not their TV")

        let both = app(.universal, at: .ios, device: "00008110-001A2B3C4D5E801E")
        XCTAssertEqual(AgentPreview.app(for: both)?.destination, .ios)
        XCTAssertNil(AgentPreview.app(for: both)?.device)

        let mac = app(.mac, at: .mac, device: nil)
        XCTAssertEqual(AgentPreview.app(for: mac), mac)
    }

    /// A device app whose integration has no preview (a Roku's) has nothing Lamp can open on this Mac: it's only built.
    func testADeviceAppWithNoPreviewIsOnlyBuilt() {
        var roku = app(.device, at: .device, device: "roku:X01")
        roku.integration = "roku"
        XCTAssertNil(AgentPreview.app(for: roku))
        XCTAssertTrue(AgentPreview.none(roku).contains("has no preview Lamp can open"))
    }

    /// Try On names the person's own Android phone, and their Play last opened the app there: the agent's look and use
    /// go to Lamp's emulator, and neither asks that phone anything (its process, its selector) on the way, while what
    /// Try On names and the run Play recorded stay as they were. The same look with the app open in the emulator does
    /// ask the emulator, so the check below sees a device being asked when one is.
    @MainActor
    func testALookOrUseNeverAsksThePersonsDevicePlayOpened() async {
        let store = Store.shared
        let phone = app(.android, at: .android, device: "R58M42ABCDE")
        let saved = Store.androidPID
        var asked: [String] = []
        Store.androidPID = { _, serial in asked.append(serial); return 4242 }
        defer {
            Store.androidPID = saved
            store.androidApps[phone.id] = nil
            store.androidLeases["R58M42ABCDE"] = nil
            store.androidLeases[Emulator.Kind.phone.serial] = nil
        }
        let played = Store.AndroidRun(device: "R58M42ABCDE", serial: "R58M42ABCDE", pid: 4242, log: nil)
        store.androidApps[phone.id] = played
        store.androidLeases["R58M42ABCDE"] = phone.id

        guard let preview = AgentPreview.app(for: phone) else { return XCTFail("an Android app has the emulator") }
        XCTAssertNil(preview.device, "the look and use go to Lamp's emulator")
        XCTAssertNil(store.previewAndroidRun(of: preview))
        let open = await store.androidPreviewOpen(preview)
        XCTAssertFalse(open, "not open where the agent looks, so the look opens it in the emulator")
        let used = await store.androidUseTarget(preview)
        XCTAssertNil(used, "nothing for use_app to press on their phone")
        XCTAssertEqual(asked, [], "their phone was asked nothing")
        XCTAssertEqual(phone.device, "R58M42ABCDE", "Try On still names their phone")
        XCTAssertTrue(store.androidApps[phone.id] === played, "Play's run is left as it was")
        XCTAssertTrue(played.alive)

        let emulator = Store.AndroidRun(device: Emulator.Kind.phone.serial, serial: Emulator.Kind.phone.serial, pid: 4242, log: nil)
        store.androidApps[phone.id] = emulator
        store.androidLeases[Emulator.Kind.phone.serial] = phone.id
        let inEmulator = await store.androidPreviewOpen(preview)
        XCTAssertTrue(inEmulator)
        XCTAssertEqual(asked, [Emulator.Kind.phone.serial], "only the emulator is asked")
    }

    /// A look at a Roku app only builds it, and the turn's end then sees nothing changed since that build. The look
    /// leaves the turn's end something to deliver, so the change still goes onto the person's Roku there, as on any
    /// look (`settle`).
    @MainActor
    func testABuildOnlyLookLeavesTheTurnsEndToPutItOnTheDevice() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("agent-preview-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var roku = LampProject(id: "pocket-roku", name: "Pocket", exe: "Pocket", dir: dir, platform: .device)
        roku.chosen = .device
        roku.device = "roku:X01"
        roku.integration = "roku"
        XCTAssertNil(AgentPreview.app(for: roku))
        // Lamp's own files in place, and the sources built as they are: nothing is left for the look to build.
        try Template.writeSupport(for: roku)
        try FileManager.default.createDirectory(at: roku.builtURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("package".utf8).write(to: roku.builtURL)
        Runtime.markBuilt(roku, from: Runtime.fingerprint(roku))
        XCTAssertFalse(Runtime.sourcesChanged(roku))

        let turn = Store.Turn()
        turn.agent = Process()
        let (status, answer) = await Store.shared.buildWithoutPreview(roku, in: turn)
        XCTAssertEqual(status, 200)
        XCTAssertTrue((answer["text"] as? String)?.contains("has no preview Lamp can open") == true)
        XCTAssertEqual(turn.look.installed[roku.id], true, "the turn's end puts it on the Roku")
        XCTAssertNil(turn.look.crashes[roku.id])
        XCTAssertFalse(turn.look.inProgress)
    }
}

