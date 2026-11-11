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

    private func load(_ page: String = PageClickTests.page, last: String = "btnOff") async throws -> WKWebView {
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
        view.loadHTMLString(page, baseURL: URL(string: "https://lamp.test/"))
        for _ in 0..<100 {
            if (try? await view.evaluateJavaScript("document.readyState === 'complete' && !!document.getElementById('\(last)')")) as? Bool == true { return view }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw XCTSkip("the page didn't load")
    }

    /// The page's things as the screen read lists them (`PageScreen.script`): name, middle, size and `ref`.
    private func screen(_ view: WKWebView) async throws -> [(name: String, x: Double, y: Double, w: Double, h: Double, ref: Int)] {
        let read = try await view.evaluateJavaScript(PageScreen.script) as? String
        let json = try XCTUnwrap(read)
        let list = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        return list.map { entry in
            func n(_ key: String) -> Double { (entry[key] as? NSNumber)?.doubleValue ?? 0 }
            return (entry["name"] as? String ?? "", n("x") + n("w") / 2, n("y") + n("h") / 2, n("w"), n("h"), (entry["ref"] as? NSNumber)?.intValue ?? -1)
        }
    }

    /// A click on the thing the screen read lists under `name` (the `index`th of that name), as the callers name it.
    private func click(_ view: WKWebView, named name: String, index: Int = 0) async throws -> (did: Bool, said: String) {
        let items = try await screen(view)
        let item = try XCTUnwrap(items.filter { $0.name == name }.dropFirst(index).first, "nothing called \(name)")
        return try await click(view, item.x, item.y, want: "{ ref: \(item.ref), w: \(item.w), h: \(item.h) }")
    }

    /// The click script's answer, as `TVPreview.perform` and LampPage.swift call it.
    private func click(_ view: WKWebView, _ x: Double, _ y: Double, want: String = "null") async throws -> (did: Bool, said: String) {
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
        let run = try await click(view, named: "Run")
        let ran = try await number(view, "ran")
        XCTAssertEqual(ran, 1, "Run was never pressed: \(run.said)")
        XCTAssertTrue(run.did, run.said)
        XCTAssertTrue(run.said.contains("blocklyScrollbarBackground"), run.said)

        // A button wholly under the scrollbar isn't clicked, and the answer says it missed and what's on top.
        let hidden = try await click(view, named: "Hidden")
        let hiddenClicks = try await number(view, "hidden")
        XCTAssertFalse(hidden.did, hidden.said)
        XCTAssertEqual(hiddenClicks, 0)
        XCTAssertTrue(hidden.said.hasPrefix("missed") && hidden.said.contains("blocklyScrollbarBackground"), hidden.said)

        // A dimmed button is reported blocked, not clicked.
        let off = try await click(view, named: "Off")
        XCTAssertFalse(off.did, off.said)
        XCTAssertTrue(off.said.contains("dimmed"), off.said)

        // A thing that moved since the screen was read gets no click at all.
        let items = try await screen(view)
        let before = try XCTUnwrap(items.first { $0.name == "Run" })
        _ = try await view.evaluateJavaScript("document.getElementById('btnRun').style.left = '30px'; 1")
        let gone = try await click(view, before.x, before.y, want: "{ ref: \(before.ref), w: \(before.w), h: \(before.h) }")
        XCTAssertFalse(gone.did, gone.said)
        XCTAssertTrue(gone.said.hasPrefix("missed"), gone.said)
        let ranAfterGone = try await number(view, "ran")
        XCTAssertEqual(ranAfterGone, 1)
    }

    /// A bare point says what it landed on: here the scrollbar, not Run, which stays unpressed.
    func testABarePointSaysWhatItLandedOn() async throws {
        let view = try await load()
        let bare = try await click(view, 129, 129)
        let ran = try await number(view, "ran")
        XCTAssertEqual(ran, 0)
        XCTAssertTrue(bare.said.contains("blocklyScrollbarBackground") && bare.said.contains("blocklyDiv"), bare.said)

        let left = try await click(view, 105, 129)
        let ranLeft = try await number(view, "ran")
        XCTAssertEqual(ranLeft, 1)
        XCTAssertTrue(left.said.contains("button \"Run\""), left.said)
    }

    /// Two things sharing a box (a pair of buttons laid one on another, a label read as text) are each clicked by their
    /// own name: the click goes to the thing the screen read listed, not to whichever has the same box.
    func testANamedThingIsTheOneTheScreenListed() async throws {
        let view = try await load("""
            <!doctype html><html><body style="margin:0">
            <button id="under" style="position:absolute; left:10px; top:10px; width:80px; height:40px; z-index:2" onclick="window.played = (window.played || 0) + 1">Play</button>
            <button id="over" style="position:absolute; left:10px; top:10px; width:80px; height:40px; z-index:1" onclick="window.paused = (window.paused || 0) + 1">Pause</button>
            <input type="checkbox" id="check" style="position:absolute; left:10px; top:100px">
            <label for="check" style="position:absolute; left:40px; top:100px">Enable</label>
            </body></html>
            """, last: "check")
        // Play is drawn above Pause, though Pause comes later in the page.
        let play = try await click(view, named: "Play")
        let underCount = try await number(view, "played"), overCount = try await number(view, "paused")
        XCTAssertTrue(play.did, play.said)
        XCTAssertEqual([underCount, overCount], [1, 0], play.said)
        // Pause is under Play, all of it: missed, with what's on top named.
        let pause = try await click(view, named: "Pause")
        let overAfter = try await number(view, "paused")
        XCTAssertFalse(pause.did, pause.said)
        XCTAssertEqual(overAfter, 0)
        XCTAssertTrue(pause.said.contains("Play"), pause.said)
        // A label is listed as text, and clicking it by that name ticks its box, as a person's click does.
        let label = try await click(view, named: "Enable")
        let ticked = try await view.evaluateJavaScript("document.getElementById('check').checked") as? Bool
        XCTAssertTrue(label.did, label.said)
        XCTAssertEqual(ticked, true, label.said)
    }
}
