import XCTest
@testable import Lamp

/// A web game's look came back blank: the first picture an app saved was of a clear window in front of the game
/// (280 by 168 pixels, every one of them fully transparent), and the game's own frame was only the second picture, which
/// a game's look never sends once the first looks blank. And when the window server gives no picture, the app's own
/// drawing of a window leaves out its web page. Here the template's checks are cut out, compiled into a small app, and
/// run on a picture like the one that came back and on windows with and without a web page.
@MainActor
final class WindowPictureTests: XCTestCase {
    func testAClearPictureAndAWebPageAreToldApart() throws {
        let support = Template.lampSupportSwift
        let start = try XCTUnwrap(support.range(of: "// begin LampRuntime.pictureChecks"))
        let end = try XCTUnwrap(support.range(of: "// end LampRuntime.pictureChecks", range: start.upperBound..<support.endIndex))
        let program = """
        import AppKit
        import WebKit
        import ImageIO

        enum LampRuntime {
        \(support[start.upperBound..<end.lowerBound])
        }

        func png(width: Int, height: Int, fill: NSColor?) -> Data {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                          samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                          bytesPerRow: 0, bitsPerPixel: 0)!
            if let fill {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
                fill.setFill()
                NSRect(x: 0, y: 0, width: width, height: height).fill()
                NSGraphicsContext.restoreGraphicsState()
            }
            return bitmap.representation(using: .png, properties: [:])!
        }

        MainActor.assumeIsolated {
            _ = NSApplication.shared
            // The clear window's picture, as it came back: 280 by 168, nothing drawn.
            print("clear:", LampRuntime.isClear(png(width: 280, height: 168, fill: nil)))
            // A frame of one dark color is a picture of the window, for the look to call blank, not a missing one.
            print("dark frame:", LampRuntime.isClear(png(width: 1024, height: 576, fill: .black)))
            let plain = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: true)
            plain.contentView?.addSubview(NSTextField(labelWithString: "Score 3"))
            print("plain window:", LampRuntime.drawsElsewhere(plain))
            let game = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: true)
            let holder = NSView(frame: game.contentView!.bounds)
            holder.addSubview(WKWebView(frame: holder.bounds))
            game.contentView?.addSubview(holder)
            print("web game window:", LampRuntime.drawsElsewhere(game))
            exit(0)
        }
        """
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-pictures-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        try program.write(to: work.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        let built = TestShell.run(Shell.compatibleSDK + "xcrun swiftc -o app main.swift 2>&1", in: work)
        XCTAssertEqual(built.status, 0, built.output)

        let ran = TestShell.run("./app", in: work)
        XCTAssertEqual(ran.status, 0, ran.output)
        XCTAssertTrue(ran.output.contains("clear: true"), ran.output)
        XCTAssertTrue(ran.output.contains("dark frame: false"), ran.output)
        XCTAssertTrue(ran.output.contains("plain window: false"), ran.output)
        XCTAssertTrue(ran.output.contains("web game window: true"), ran.output)
    }
}
