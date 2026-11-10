import WebKit
import XCTest
@testable import Lamp

/// A click on a page says what it landed on, in WebKit's own hit-testing. The page is laid out as an imported block
/// editor was: its scrollbar, in a layer above the editor's bar, lies over the middle of the bar's Run button, so a click
/// at the button's middle lands on the scrollbar. Before, the click went to whatever was at the middle and was reported
/// as "clicked in the page" while Run was never pressed.
@MainActor
final class PageClickTests: XCTestCase {
    private static let page = """
        <!doctype html><html><body style="margin:0">
        <div class="editor-bar" style="position:absolute; left:0; top:100px; width:400px; height:58px; z-index:5">
          <button id="btnRun" style="position:absolute; left:100px; top:0; width:58px; height:58px" onclick="window.ran = (window.ran || 0) + 1">Run</button>
          <button id="btnHidden" style="position:absolute; left:250px; top:0; width:40px; height:40px" onclick="window.hidden = 1">Hidden</button>
          <button id="btnOff" disabled style="position:absolute; left:320px; top:0; width:40px; height:40px" onclick="window.off = 1">Off</button>
        </div>
        <div id="blocklyDiv" style="position:absolute; left:125px; top:100px; width:200px; height:58px; z-index:20">
          <svg width="200" height="58" style="display:block"><rect class="blocklyScrollbarBackground" x="0" y="0" width="200" height="58" fill="rgba(0,0,0,0.01)"/></svg>
        </div>
        </body></html>
        """

    private func load() async throws -> WKWebView {
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
        view.loadHTMLString(Self.page, baseURL: URL(string: "https://lamp.test/"))
        for _ in 0..<100 {
            if (try? await view.evaluateJavaScript("document.readyState === 'complete' && !!document.getElementById('btnOff')")) as? Bool == true { return view }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw XCTSkip("the page didn't load")
    }

    /// The click script's answer, as `TVPreview.perform` and LampPage.swift call it.
    private func click(_ view: WKWebView, _ x: Double, _ y: Double, box: (w: Double, h: Double)?) async throws -> (did: Bool, said: String) {
        let want = box.map { "{ w: \($0.w), h: \($0.h) }" } ?? "null"
        let json = try await view.evaluateJavaScript(PageScreen.click + "(\(x), \(y), \(want), 1)") as? String
        let told = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(try XCTUnwrap(json).utf8)) as? [String: Any])
        return (told["did"] as? Bool ?? false, told["said"] as? String ?? "")
    }

    private func number(_ view: WKWebView, _ name: String) async throws -> Int {
        (try await view.evaluateJavaScript("window.\(name) || 0") as? NSNumber)?.intValue ?? -1
    }

    func testANamedButtonUnderAnotherLayerIsPressedWhereItShowsOrReportedMissed() async throws {
        let view = try await load()
        // WebKit itself puts the scrollbar at Run's middle.
        let atMiddle = try await view.evaluateJavaScript("document.elementFromPoint(129, 129).getAttribute('class')") as? String
        XCTAssertEqual(atMiddle, "blocklyScrollbarBackground")

        // Run, named: pressed at its uncovered part, and the answer names what lies over its middle.
        let run = try await click(view, 129, 129, box: (58, 58))
        let ran = try await number(view, "ran")
        XCTAssertEqual(ran, 1, "Run was never pressed: \(run.said)")
        XCTAssertTrue(run.did, run.said)
        XCTAssertTrue(run.said.contains("blocklyScrollbarBackground"), run.said)

        // A button wholly under the scrollbar isn't clicked, and the answer says it missed and what's on top.
        let hidden = try await click(view, 270, 120, box: (40, 40))
        let hiddenClicks = try await number(view, "hidden")
        XCTAssertFalse(hidden.did, hidden.said)
        XCTAssertEqual(hiddenClicks, 0)
        XCTAssertTrue(hidden.said.hasPrefix("missed") && hidden.said.contains("blocklyScrollbarBackground"), hidden.said)

        // A dimmed button is reported blocked, not clicked.
        let off = try await click(view, 340, 120, box: (40, 40))
        XCTAssertFalse(off.did, off.said)
        XCTAssertTrue(off.said.contains("dimmed"), off.said)

        // A thing whose box isn't there any more (it moved since the screen was read) gets no click at all.
        let gone = try await click(view, 129, 129, box: (90, 30))
        XCTAssertFalse(gone.did, gone.said)
        XCTAssertTrue(gone.said.hasPrefix("missed"), gone.said)
        let ranAfterGone = try await number(view, "ran")
        XCTAssertEqual(ranAfterGone, 1)
    }

    /// A bare point says what it landed on: here the scrollbar, not Run, which stays unpressed.
    func testABarePointSaysWhatItLandedOn() async throws {
        let view = try await load()
        let bare = try await click(view, 129, 129, box: nil)
        let ran = try await number(view, "ran")
        XCTAssertEqual(ran, 0)
        XCTAssertTrue(bare.said.contains("blocklyScrollbarBackground") && bare.said.contains("blocklyDiv"), bare.said)

        let left = try await click(view, 105, 129, box: nil)
        let ranLeft = try await number(view, "ran")
        XCTAssertEqual(ranLeft, 1)
        XCTAssertTrue(left.said.contains("button \"Run\""), left.said)
    }
}
