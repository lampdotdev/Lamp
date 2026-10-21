import XCTest
@testable import Lamp

/// What an Android app is identified and read by: its package name from the app's folder name, a device's record
/// from adb, and the screen as text from the system's own dump of it.
final class AndroidKitTests: XCTestCase {
    func testPackageNameIsSafeForJava() {
        let project = LampProject(id: "coin-flip-2", name: "Coin Flip", exe: "CoinFlip", dir: URL(fileURLWithPath: "/tmp/coin-flip-2"))
        let package = Template.androidPackage(for: project)
        XCTAssertTrue(package.hasSuffix(".coin_flip_2"), package)
        XCTAssertFalse(package.contains("-"))
        XCTAssertTrue(package.split(separator: ".").allSatisfy { $0.first?.isNumber == false })
    }

    func testADeviceIsReadFromAdb() {
        let phone = Device.from(adb: "R5CT1234", state: "unauthorized", properties: [:])
        XCTAssertEqual(phone.kind, .android)
        XCTAssertEqual(phone.setup(), .needs("Allow USB debugging on it"))
        XCTAssertEqual(phone.reach, .cable)
        let ready = Device.from(adb: "192.168.1.20:5555", state: "device",
                                properties: ["ro.product.manufacturer": "Google", "ro.product.model": "Pixel 9", "ro.product.device": "tokay",
                                             "ro.build.version.release": "16", "size": "1080x2424", "density": "420"])
        XCTAssertEqual(ready.name, "Google Pixel 9")
        XCTAssertEqual(ready.forAgent, "Pixel 9, Android 16, screen 360×808 points at 3x")
        XCTAssertEqual(ready.reach, .network)
        XCTAssertEqual(ready.setup(), .ready)
        XCTAssertEqual(ready.density, 420)
        let emulator = Device.from(adb: "emulator-5554", state: "device", properties: ["ro.product.model": "sdk_gphone64_arm64", "ro.build.version.release": "16"])
        XCTAssertEqual(emulator.kind, .androidEmulator)
        XCTAssertEqual(emulator.name, AndroidTools.avdName)
    }

    func testTheScreenIsReadAsText() {
        let xml = """
        <?xml version='1.0' encoding='UTF-8' standalone='yes' ?><hierarchy rotation="0">
        <node index="0" text="" resource-id="" class="android.widget.FrameLayout" package="a" content-desc="" checkable="false" checked="false" clickable="false" enabled="true" focusable="false" focused="false" scrollable="false" long-clickable="false" password="false" selected="false" bounds="[0,0][1080,2424]">
        <node index="0" text="Hello Android!" resource-id="" class="android.widget.TextView" package="a" content-desc="" checkable="false" checked="false" clickable="false" enabled="true" focusable="false" focused="false" scrollable="false" long-clickable="false" password="false" selected="false" bounds="[42,184][323,247]" />
        <node index="1" text="" resource-id="" class="android.widget.Button" package="a" content-desc="Add" checkable="false" checked="false" clickable="true" enabled="true" focusable="true" focused="false" scrollable="false" long-clickable="false" password="false" selected="false" bounds="[840,2100][1040,2300]" />
        <node index="2" text="milk" resource-id="" class="android.widget.EditText" package="a" content-desc="" checkable="false" checked="false" clickable="true" enabled="true" focusable="true" focused="true" scrollable="false" long-clickable="true" password="false" selected="false" bounds="[0,400][1080,520]" hint="What to buy" />
        </node></hierarchy>
        """
        guard let screen = Adb.Screen.parse(xml, scale: 3) else { return XCTFail("the dump didn't parse") }
        XCTAssertEqual(screen.items.map(\.id), ["t1", "b1", "f1"])
        XCTAssertEqual(screen.find("Add")?.id, "b1")
        XCTAssertEqual(Int(screen.find("b1")!.frame.midX), 313)
        XCTAssertTrue(screen.text.contains("t1 text \"Hello Android!\" @61,72 94x21"), screen.text)
        XCTAssertTrue(screen.text.contains("f1 field \"What to buy\" = milk"), screen.text)
    }
}
