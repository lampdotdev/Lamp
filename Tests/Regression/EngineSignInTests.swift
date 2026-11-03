import XCTest
@testable import Lamp

/// Sign-ins that overlap, each with a real process standing in for the tool's login.
final class EngineSignInTests: XCTestCase {
    private static func login(seconds: String, started: @escaping @Sendable (Process) -> Void) async -> Int32 {
        await Subprocess.run("/bin/sleep", [seconds], timeout: 30, started: started).status
    }

    func testCancelStillReachesASignInStartedWhileACancelledOneSettles() async {
        let loggingIn = AsyncStream<Void>.makeStream()
        let settling = AsyncStream<Void>.makeStream()
        let settled = AsyncStream<Void>.makeStream()
        let first = Task {
            await EngineSignIn.signIn(.claude, ready: { true }, login: { started in
                await Self.login(seconds: "30") { started($0); loggingIn.continuation.yield() }
            }, settle: {
                settling.continuation.yield()
                for await _ in settled.stream { break }
            })
        }
        for await _ in loggingIn.stream { break }
        EngineSignIn.cancelSignIn(.claude)
        for await _ in settling.stream { break }

        let replacementLoggingIn = AsyncStream<Void>.makeStream()
        let replacement = Task {
            await EngineSignIn.signIn(.claude, ready: { true }, login: { started in
                await Self.login(seconds: "3") { started($0); replacementLoggingIn.continuation.yield() }
            }, settle: {})
        }
        for await _ in replacementLoggingIn.stream { break }

        settled.continuation.yield()
        let firstResult = await first.value
        XCTAssertNil(firstResult, "the first attempt was cancelled, whatever came after it")

        EngineSignIn.cancelSignIn(.claude)
        let replacementResult = await replacement.value
        XCTAssertNil(replacementResult, "Cancel has to stop the replacement, not leave it to finish")
    }
}
