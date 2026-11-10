import XCTest
@testable import Lamp

/// Lamp's app has lamp's command line do what's the command line's own (`LampCLI`, cli/calls.mjs), and an Xbox's
/// package is the first of it: the app lays the files out and reads back what Windows will call the package. Run on
/// Node, as a test run finds it, and on the runtime Lamp's app carries (pi's, in an app built here) when there is one.
final class LampCLITests: XCTestCase {
    private static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// The runtime as Lamp's app runs it (`LampCLI.launch`'s first choice), from an app `build.sh` made in this folder.
    private static var inAnApp: LampCLI.Launch? {
        let apps = (try? FileManager.default.contentsOfDirectory(at: repository.appendingPathComponent("build"), includingPropertiesForKeys: nil)) ?? []
        guard let pi = apps.map({ $0.appendingPathComponent("Contents/Resources/pi/pi") }).first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else { return nil }
        return LampCLI.Launch(tool: pi.path, arguments: ["--no-install", "--no-env-file", repository.appendingPathComponent("cli/calls.mjs").path],
                              environment: ["BUN_BE_BUN": "1"])
    }

    func testAnXboxPackageIsMadeByLampsCommandLine() async throws {
        let found = LampCLI.launch, signer = MSIX.signerFolder
        defer { LampCLI.launch = found; MSIX.signerFolder = signer }
        let launches = [found, Self.inAnApp].compactMap { $0 }
        guard !launches.isEmpty else { throw XCTSkip("No Node here to run lamp's command line on") }
        for launch in launches {
            LampCLI.launch = launch
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-cli-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: folder) }
            MSIX.signerFolder = folder.appendingPathComponent("signer")
            let package = folder.appendingPathComponent("out/package.msix"), certificate = folder.appendingPathComponent("out/certificate.cer")
            func make(_ payload: [(path: String, data: Data)], after: String? = nil) async throws -> MSIX.Identity {
                try await MSIX.make(payload: payload, displayName: "Harbor <Racer>", slug: "harbor-racer", after: after, architecture: "x64", entry: .webHost,
                                    icon: nil, in: folder.appendingPathComponent("work"), package: package, certificate: certificate)
            }
            let files = [(path: "App.exe", data: Data("host".utf8)), (path: "Web/index.html", data: Data("<p>the game</p>".utf8))]

            let identity = try await make(files)
            XCTAssertEqual(identity.name, "Lamp.harbor-racer")
            XCTAssertEqual(identity.architecture, "x64")
            // Every file but the signature is stored as it is, so the package can be read for what's in it.
            let made = try Data(contentsOf: package)
            XCTAssertEqual(made.prefix(4), Data([0x50, 0x4B, 0x03, 0x04]))
            for part in ["<p>the game</p>", "Name=\"\(identity.name)\"", "Version=\"\(identity.version)\"", "<DisplayName>Harbor &lt;Racer&gt;</DisplayName>", "AppxSignature.p7x"] {
                XCTAssertNotNil(made.range(of: Data(part.utf8)), part)
            }
            XCTAssertFalse(try Data(contentsOf: certificate).isEmpty, "the certificate a device installs beside the package")
            let key = MSIX.signerFolder.appendingPathComponent("key.der")
            XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: key.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600, "Lamp's key is the person's alone to read")
            XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("work").path), "nothing of the app's files is left behind")

            // The next package is a newer version, which Windows needs to replace the last.
            let next = try await make(files, after: identity.version)
            XCTAssertTrue(identity.version.split(separator: ".").map { Int($0)! }.lexicographicallyPrecedes(next.version.split(separator: ".").map { Int($0)! }))

            // What the command line says the person can put right comes back in its own words, and a path that isn't a
            // plain one inside the package never reaches it.
            do { _ = try await make([files[1]]); XCTFail("a package with nothing to start") } catch {
                XCTAssertEqual(error.localizedDescription, "The package has no App.exe for the app to start at.")
            }
            do { _ = try await make(files + [(path: "../outside.txt", data: Data())]); XCTFail("a file outside the package") } catch {
                XCTAssertTrue(error.localizedDescription.contains("../outside.txt"))
            }
        }
    }
}
