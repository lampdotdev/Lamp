import XCTest
@testable import Lamp

/// An Android app travels as its app/ folder, says a format a Lamp from before Android can't open, and becomes an
/// app under this Mac's own package name when it's opened.
final class SharingAndroidTests: XCTestCase {
    private var root: URL?
    override func setUp() { expectNoSharingFoldersLeft() }
    override func tearDown() { if let root { try? FileManager.default.removeItem(at: root) } }

    private func write(_ text: String, to path: String, in folder: URL) throws {
        let url = folder.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func testAnAndroidAppIsSharedWithoutWhatItsBuildLeftAndOpensUnderThisMacsName() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("lamp-share-android-\(UUID().uuidString)")
        self.root = root
        let sender = try Template.scaffold(name: "Tally", platform: .android, in: root)
        try write("stale", to: "app/build/outputs/apk/debug/app-debug.apk", in: sender.dir)
        try write("sdk.dir=/Users/someone/Android", to: "app/local.properties", in: sender.dir)
        try write("{}", to: "app/.lamp/state.json", in: sender.dir)
        let manifest = "app/src/main/AndroidManifest.xml"
        let text = try String(contentsOf: sender.dir.appendingPathComponent(manifest), encoding: .utf8)
        try write(text.replacingOccurrences(of: "<application", with: "<uses-permission android:name=\"android.permission.INTERNET\" />\n<uses-permission android:name=\"android.permission.READ_SMS\" />\n<application"),
                  to: manifest, in: sender.dir)
        let build = sender.dir.appendingPathComponent("app/build.gradle.kts")
        try (String(contentsOf: build, encoding: .utf8).replacingOccurrences(of: "dependencies {", with: "dependencies {\n    implementation(\"com.squareup.retrofit2:retrofit:2.11.0\")"))
            .write(to: build, atomically: true, encoding: .utf8)

        let package = try opened(try exported(sender))
        let lampFile = try JSONSerialization.jsonObject(with: Data(contentsOf: package.folder.appendingPathComponent("lamp-app.json"))) as? [String: Any]
        XCTAssertEqual(lampFile?["format"] as? Int, 9)
        XCTAssertEqual(lampFile?["platform"] as? String, "android")
        let carried = (FileManager.default.enumerator(atPath: package.folder.path)?.allObjects as? [String]) ?? []
        XCTAssertFalse(carried.contains { $0.hasPrefix("app/build/") || $0.contains("local.properties") || $0.contains(".lamp") })
        XCTAssertFalse(carried.contains { ["build.sh", "settings.gradle.kts", "build.gradle.kts", "gradle.properties", "gradle"].contains($0) })
        XCTAssertTrue(carried.contains("app/build.gradle.kts"))

        // The review reads the manifest and the build file in the Mac's words.
        let labels = Sharing.inspect(package).detected.map(\.label)
        XCTAssertTrue(labels.contains("Connects to the internet"))
        XCTAssertTrue(labels.contains("Reads or sends your text messages"))
        XCTAssertTrue(labels.contains { $0.contains("retrofit") })

        // Opened as another app here, its code is renamed to this Mac's package, which Lamp launches it by.
        let receiver = try Template.scaffold(name: "Counter", platform: .android, in: root)
        try Sharing.install(package, into: receiver)
        let ours = Template.androidPackage(for: receiver)
        let activity = receiver.dir.appendingPathComponent("app/src/main/kotlin/\(ours.replacingOccurrences(of: ".", with: "/"))/MainActivity.kt")
        XCTAssertTrue(try String(contentsOf: activity, encoding: .utf8).contains("package \(ours)\n"))
        let received = try String(contentsOf: receiver.dir.appendingPathComponent("app/build.gradle.kts"), encoding: .utf8)
        XCTAssertTrue(received.contains("applicationId = \"\(ours)\"") && received.contains("namespace = \"\(ours)\""))
        XCTAssertFalse(FileManager.default.fileExists(atPath: receiver.dir.appendingPathComponent("app/src/main/kotlin/\(Template.androidPackage(for: sender).replacingOccurrences(of: ".", with: "/"))").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: receiver.dir.appendingPathComponent("settings.gradle.kts").path))
    }
}
