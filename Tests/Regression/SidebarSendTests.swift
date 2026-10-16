import XCTest
import LampSidebarKit

final class SidebarSendTests: XCTestCase {
    /// What a sidebar built before Send carried a count writes for Send, as encoded by that sidebar:
    /// an app installed by an earlier Lamp still has it until it's rebuilt, and its messages must still go.
    func testSendFromAnEarlierSidebarStillReads() throws {
        let line = Data(#"{"send":{"_0":"Make it blue"}}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(SidebarCommand.self, from: line), .send("Make it blue", sends: nil))
    }
}
