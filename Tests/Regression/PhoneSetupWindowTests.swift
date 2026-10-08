import XCTest
import AppKit
import SwiftUI
@testable import Lamp

/// The setup window takes its size from its content by hand, between layout passes: a window sized by
/// AppKit's constraints changed size inside a layout pass, which crashed Lamp on macOS 26.
final class PhoneSetupWindowTests: XCTestCase {
    @MainActor
    func testWindowFollowsItsContentWithoutConstraintSizing() async throws {
        _ = NSApplication.shared
        let model = PhoneSetup(presentsWindow: true) { _ in PhoneTools.Report() }
        model.show()
        try await Task.sleep(for: .milliseconds(300))
        let window = try XCTUnwrap(NSApp.windows.first { $0.title == "iPhone & iPad Setup" })
        let controller = try XCTUnwrap(window.contentViewController as? NSHostingController<PhoneSetupView>)
        XCTAssertTrue(controller.sizingOptions.isEmpty, "the window's frame must not follow the content's constraints")
        let before = window.frame.size
        XCTAssertGreaterThan(before.height, 50)
        // More to say: the window grows to fit, from a change made outside any layout pass.
        model.actionProblem = String(repeating: "A long explanation of what to do next, so the text wraps onto several lines. ", count: 4)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertGreaterThan(window.frame.height, before.height)
        window.close()
    }
}
