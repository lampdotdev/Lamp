import CoreImage
import CryptoKit
import JavaScriptCore
import XCTest
@testable import Lamp
import LampRelayKit

/// lamp.js's `LampQR` draws a join link a phone's camera reads back exactly, however long Lamp's signed link is.
final class LampQRTests: XCTestCase {
    private let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/phone-join-qr")
    private let library = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Resources/WebLibraries/qrcode")

    /// A page with lamp.js's LampQR (the encoder read from the repository, as a test bundle has no resources) and a
    /// canvas that keeps what's drawn on it.
    private func page(ratio: Double = 2) throws -> JSContext {
        let context = try XCTUnwrap(JSContext())
        context.exceptionHandler = { _, error in XCTFail("page threw: \(error?.toString() ?? "")") }
        context.evaluateScript("""
            var window = this; window.devicePixelRatio = \(ratio);
            function makeCanvas() {
              var c = { width: 0, height: 0, style: {}, rects: [] };
              c.getContext = function () { return { fillStyle: '', fillRect: function (x, y, w, h) { c.rects.push([this.fillStyle, x, y, w, h]); } }; };
              return c;
            }
            var document = { createElement: function () { return makeCanvas(); } };
            """)
        let encoder = try String(contentsOf: library.appendingPathComponent("qrcode.js"), encoding: .utf8)
        let license = try String(contentsOf: library.appendingPathComponent("LICENSE"), encoding: .utf8)
        context.evaluateScript(DeviceSupport.qrJS(encoder: encoder, license: license))
        return context
    }

    /// What a phone's camera reads from the canvas `LampQR.draw` filled: its rectangles painted into an image.
    private func scan(_ context: JSContext, _ text: String) throws -> (decoded: [String], side: Int, style: String) {
        context.setObject(text, forKeyedSubscript: "text" as NSString)
        context.evaluateScript("var canvas = LampQR.draw(null, text, { size: 240 });")
        let side = Int(try XCTUnwrap(context.evaluateScript("canvas.width")?.toInt32()))
        let rects = try XCTUnwrap(context.evaluateScript("canvas.rects")?.toArray() as? [[Any]])
        let gc = try XCTUnwrap(CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
        for rect in rects {
            let n = rect.dropFirst().map { ($0 as? NSNumber)?.doubleValue ?? 0 }
            gc.setFillColor(gray: (rect[0] as? String) == "#ffffff" ? 1 : 0, alpha: 1)
            gc.fill(CGRect(x: n[0], y: Double(side) - n[1] - n[3], width: n[2], height: n[3]))
        }
        let image = CIImage(cgImage: try XCTUnwrap(gc.makeImage()))
        let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let decoded = detector.features(in: image).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        let style = context.evaluateScript("canvas.style.width + ' ' + canvas.style.imageRendering")?.toString() ?? ""
        return (decoded, side, style)
    }

    func testTheRecordedJoinLinkTheGamesOwnEncoderGaveUpOnScansBackExactly() throws {
        let link = try String(contentsOf: fixtures.appendingPathComponent("join-link.txt"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(link.utf8.count, 167)

        // The encoder the agent wrote stops at 134 bytes and gives null, which its page took for "no phones".
        let generated = try XCTUnwrap(JSContext())
        generated.exceptionHandler = { _, error in XCTFail("the generated encoder threw: \(error?.toString() ?? "")") }
        // A browser's TextEncoder, which JavaScriptCore alone lacks.
        generated.evaluateScript("""
            function TextEncoder() {}
            TextEncoder.prototype.encode = function (s) { return unescape(encodeURIComponent(s)).split('').map(function (c) { return c.charCodeAt(0); }); };
            """)
        generated.evaluateScript(try String(contentsOf: fixtures.appendingPathComponent("generated-qr.js"), encoding: .utf8)
            .replacingOccurrences(of: "export function", with: "function"))
        generated.setObject(link, forKeyedSubscript: "link" as NSString)
        XCTAssertTrue(generated.evaluateScript("qr(link) === null")?.toBool() == true)

        let scanned = try scan(try page(), link)
        XCTAssertEqual(scanned.decoded, [link], "the code reads back as the whole link, byte for byte")
        let modules = try page().evaluateScript("LampQR.matrix(\(String(reflecting: link))).size")?.toInt32() ?? 0
        XCTAssertEqual(scanned.side % (Int(modules) + 8), 0, "whole pixels per module, with a four-module border")
        XCTAssertEqual(scanned.style, String(format: "%gpx pixelated", Double(scanned.side) / 2), "shown at its size on a screen of two pixels a point")
    }

    /// A link the relay makes now, for an app with a long name on a long host, scans back to a credential that checks.
    func testAFreshLongJoinLinkScansBackToACredentialThatChecks() throws {
        let key = SymmetricKey(size: .bits256)
        let app = "com.example.lamp-apps.the-very-long-name-of-a-party-game-for-the-whole-family.game"
        let token = ControllerToken.issue(kind: .join, app: app, generation: 3, key: key)
        let link = "http://the-living-room-mac-with-a-long-name.local:49321/#" + token
        XCTAssertGreaterThan(link.utf8.count, 250)

        let scanned = try scan(try page(ratio: 1), link)
        XCTAssertEqual(scanned.decoded, [link])
        let read = try XCTUnwrap(scanned.decoded.first?.components(separatedBy: "#").last)
        XCTAssertNotNil(ControllerToken.check(read, kinds: [.join], app: app, generation: 3, key: key))
    }

    func testTextNoQRCodeHoldsIsAnErrorThatSaysSo() throws {
        let context = try page()
        context.exceptionHandler = nil
        let said = context.evaluateScript("""
            (function () { try { LampQR.draw(null, new Array(3001).join('x')); return 'drawn'; } catch (e) { return e.message; } })()
            """)?.toString()
        XCTAssertEqual(said, "This text is 3000 bytes, more than a QR code holds.")
    }
}
