import XCTest
@testable import Lamp

/// Stop pressed while an app's new copy is being signed (`Store.Staging`): the signing command and what it started are
/// ended through the turn, the staging stops rather than counting it a failure to sign, and a Stop from before the
/// staging began doesn't stop it.
@MainActor final class StagingStopTests: XCTestCase {
    func testStopEndsTheSigningCommandAndWhatItStarted() async throws {
        let turn = Store.Turn()
        let staging = Store.Staging(for: turn)
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-staging-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: marker) }
        // A shell with a child of its own, as codesign is under the signing command's zsh: the child writes its pid.
        let command = Task { @MainActor in
            await Shell.run("/bin/sleep 30 & echo $! > \"$MARK\"; wait", cwd: FileManager.default.temporaryDirectory,
                            env: ["MARK": marker.path], login: false, started: staging.started) { _ in }
        }
        let deadline = Date().addingTimeInterval(10)
        while (turn.build == nil || !FileManager.default.fileExists(atPath: marker.path)), Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        let shell = try XCTUnwrap(turn.build, "the signing command wasn't the turn's build")
        XCTAssertTrue(turn.isWorking)
        let child = try XCTUnwrap(pid_t(String(contentsOf: marker, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))

        let started = Date()
        let signaled = turn.cancel()
        XCTAssertTrue(signaled.contains(shell.processIdentifier))
        XCTAssertTrue(signaled.contains(child))
        let status = await command.value
        XCTAssertNotEqual(status, 0)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(Subprocess.alive([child]), "the command's child outlived Stop")

        XCTAssertThrowsError(try staging.ended()) { XCTAssertTrue($0 is Store.Staging.Stopped) }
        XCTAssertNil(turn.build)
        XCTAssertFalse(turn.isWorking)
    }

    func testAStopBeforeTheStagingBeganDoesNotStopIt() throws {
        let turn = Store.Turn()
        turn.cancel()
        turn.stopped = false   // the agent has stopped and the turn goes on, to install what was made
        let staging = Store.Staging(for: turn)
        XCTAssertNoThrow(try staging.check())
        turn.cancel()
        XCTAssertThrowsError(try staging.check())
    }

    func testAStopStillCountsOnceTheAgentsRunHasClearedIt() {
        let turn = Store.Turn()
        let staging = Store.Staging(for: turn)
        turn.cancel()
        turn.stopped = false
        XCTAssertTrue(staging.stopped)
    }

    func testWithoutATurnNothingStopsIt() {
        XCTAssertNoThrow(try Store.Staging(for: nil).check())
    }
}
