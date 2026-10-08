import XCTest
import AppKit
import SwiftUI
@testable import Lamp

/// The sharing picker opens from the control Share… was chosen under. Shown at a point with no size, it
/// opened beside the window instead, so each control that offers Share… has a real view to open it from.
final class SharePickerAnchorTests: XCTestCase {
    @MainActor
    func testEachShareControlHasItsOwnPlaceInItsWindow() async throws {
        _ = NSApplication.shared
        let content = HStack(spacing: 0) {
            Text("Coin Flip").frame(width: 120, height: 30).background(ShareAnchor(origin: .app("coinflip")))
            Text("Share").frame(width: 40, height: 30).background(ShareAnchor(origin: .toolbar))
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 160, height: 30), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content)
        window.orderFront(nil)
        try await Task.sleep(for: .milliseconds(300))

        let toolbar = try XCTUnwrap(Sharing.anchor(for: .toolbar, in: window))
        let row = try XCTUnwrap(Sharing.anchor(for: .app("coinflip"), in: window))
        XCTAssertFalse(toolbar === row)
        XCTAssertEqual(toolbar.bounds.size, NSSize(width: 40, height: 30), "the picker opens from the whole control, not a point")
        XCTAssertEqual(row.bounds.size, NSSize(width: 120, height: 30))
        XCTAssertNil(toolbar.hitTest(NSPoint(x: 5, y: 5)), "the place behind a control never takes its clicks")

        // An app that isn't on screen has no place, and neither does a control in another window.
        XCTAssertNil(Sharing.anchor(for: .app("other"), in: window))
        let elsewhere = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10), styleMask: [.titled], backing: .buffered, defer: false)
        elsewhere.isReleasedWhenClosed = false
        XCTAssertNil(Sharing.anchor(for: .toolbar, in: elsewhere))
        window.close()
    }
}
