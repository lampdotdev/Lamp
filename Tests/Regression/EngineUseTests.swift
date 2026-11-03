import XCTest
@testable import Lamp

/// Choosing Claude or ChatGPT in the setup sheet, with what it depends on stood in for.
@MainActor
final class EngineUseTests: XCTestCase {
    private final class Calls {
        var signIns = 0
        var rechecks = 0
        var stages: [EngineUse.Stage?] = []
    }

    private func use(ready: Bool = true, signedIn: Bool? = false, signInResult: Bool? = true, calls: Calls,
                     duringEnsure: @escaping @MainActor () async -> Void = {}) -> EngineUse {
        EngineUse(ensure: { _ in await duringEnsure(); return ready },
                  isSignedIn: { _ in signedIn },
                  signIn: { _ in calls.signIns += 1; return signInResult },
                  recheck: { calls.rechecks += 1 })
    }

    func testAFailedDownloadGoesNoFurtherForEitherEngine() async {
        for engine in [Engine.claude, .codex] {
            let calls = Calls()
            await use(ready: false, calls: calls).run(engine) { calls.stages.append($0) }
            XCTAssertEqual(calls.signIns, 0)
            XCTAssertEqual(calls.rechecks, 0)
            XCTAssertEqual(calls.stages, [nil])
        }
    }

    func testADownloadThatWorksGoesOnToTheSignInAndSetupLooksAgain() async {
        let calls = Calls()
        await use(calls: calls).run(.claude) { calls.stages.append($0) }
        XCTAssertEqual(calls.signIns, 1)
        XCTAssertEqual(calls.rechecks, 1)
        XCTAssertEqual(calls.stages, [.checkingSignIn, .signingIn, nil])
    }

    func testAMacAlreadySignedInOpensNoBrowser() async {
        let calls = Calls()
        await use(signedIn: true, calls: calls).run(.codex) { calls.stages.append($0) }
        XCTAssertEqual(calls.signIns, 0)
        XCTAssertEqual(calls.rechecks, 1)
    }

    func testASignInThatFailedIsSaidAndOneCancelledIsNot() async {
        let failed = Calls()
        await use(signInResult: false, calls: failed).run(.claude) { failed.stages.append($0) }
        XCTAssertEqual(failed.stages.last, .signInFailed)
        let cancelled = Calls()
        await use(signInResult: nil, calls: cancelled).run(.claude) { cancelled.stages.append($0) }
        XCTAssertEqual(cancelled.stages.last, .some(nil))
    }

    func testPickingAnotherEngineDuringTheDownloadOpensNoSignIn() async {
        let calls = Calls()
        let started = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        let engineUse = use(calls: calls) {
            started.continuation.yield()
            for await _ in release.stream { break }
        }
        let task = Task { @MainActor in await engineUse.run(.claude) { calls.stages.append($0) } }
        for await _ in started.stream { break }
        task.cancel()
        release.continuation.yield()
        await task.value
        XCTAssertEqual(calls.signIns, 0)
        XCTAssertEqual(calls.stages.count, 0, "a stopped use leaves the row to the engine picked since")
    }

    private func status(stage: EngineUse.Stage? = nil, installed: Bool = false, downloading: Bool = false,
                        progress: Double? = nil, failure: String? = nil) -> EngineUseRow.Status {
        .of(stage: stage, installed: installed, downloading: downloading, progress: progress, failure: failure)
    }

    func testTheRowFollowsTheDownload() {
        XCTAssertEqual(status(), .use)
        XCTAssertEqual(status(downloading: true, progress: 0.4), .downloading(0.4))
        XCTAssertEqual(status(failure: "No internet."), .failed("No internet."))
    }

    func testAFailureShowsOnlyWhileTheEngineIsMissing() {
        XCTAssertEqual(status(installed: true, failure: "No internet."), .use)
    }

    func testTryAgainReplacesTheFailureAtOnce() {
        XCTAssertEqual(status(stage: .gettingCopy, failure: "No internet."), .gettingReady)
        XCTAssertEqual(status(stage: .gettingCopy, downloading: true, progress: 0, failure: nil), .downloading(0))
    }
}
