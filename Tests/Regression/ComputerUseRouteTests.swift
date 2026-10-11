import XCTest
@testable import Lamp

/// A task in the person's other apps, from an app nobody chose a model for, prefers a sign-in, then the
/// computer-use OpenRouter model. Computer use has its own default rather than the text default.
final class ComputerUseRouteTests: XCTestCase {
    private func route(_ id: String, _ kind: AppAI.TextRoute.Kind, available: Bool = true) -> AppAI.TextRoute {
        AppAI.TextRoute(id: id, label: id, group: "", name: id, kind: kind, available: available)
    }

    private var sonnet: AppAI.TextRoute { route("sonnet", .openRouter(model: "anthropic/claude-sonnet-5.5")) }

    private func routes(key: Bool = false, claude: Bool = false, codex: Bool = false) -> [AppAI.TextRoute] {
        [route("opus", .openRouter(model: "anthropic/claude-opus-5.5"), available: key),
         route("sonnet", .openRouter(model: "anthropic/claude-sonnet-5.5"), available: key),
         route("engine:claude:opus", .engine(.claude, model: "opus"), available: claude),
         route("engine:claude:sonnet", .engine(.claude, model: "sonnet"), available: claude),
         route("engine:codex:best", .engine(.codex, model: "best"), available: codex),
         route("engine:codex:fast", .engine(.codex, model: "fast"), available: codex)]
    }

    func testAKeyAloneGoesToTheModelThatDidTheTask() {
        let chosen = AppAI.computerDefault(among: routes(key: true), builder: .pi, textDefault: sonnet, hasKey: true)
        XCTAssertEqual(chosen.kind, .openRouter(model: AppAI.computerOpenRouterModel.id))
        XCTAssertNotEqual(chosen.id, "sonnet")
    }

    func testASignInComesBeforeAKey() {
        XCTAssertEqual(AppAI.computerDefault(among: routes(key: true, codex: true), builder: .pi, textDefault: sonnet, hasKey: true).id, "engine:codex:best")
        XCTAssertEqual(AppAI.computerDefault(among: routes(key: true, claude: true), builder: .pi, textDefault: sonnet, hasKey: true).id, "engine:claude:opus")
    }

    func testTheSignInThatBuildsAppsComesFirst() {
        let both = routes(key: true, claude: true, codex: true)
        XCTAssertEqual(AppAI.computerDefault(among: both, builder: .claude, textDefault: sonnet, hasKey: true).id, "engine:claude:opus")
        XCTAssertEqual(AppAI.computerDefault(among: both, builder: .codex, textDefault: sonnet, hasKey: true).id, "engine:codex:best")
    }

    func testSomeoneStayingOnThisMacStaysThere() {
        let local = route("local:small", .localModel(provider: "local", model: "small"))
        XCTAssertEqual(AppAI.computerDefault(among: routes(key: true, claude: true), builder: .pi, textDefault: local, hasKey: true).id, "local:small")
    }

    func testWithNothingBetterTheTextDefaultAnswers() {
        let own = route("engine:pi", .engine(.pi, model: "x"))
        XCTAssertEqual(AppAI.computerDefault(among: routes() + [own], builder: .pi, textDefault: own, hasKey: false).id, "engine:pi")
    }

    /// A call still in flight when the task passes its limit is cut off there, not waited for.
    func testWorkInFlightAtTheLimitIsCutOff() async {
        let began = Date()
        var cut = false
        do {
            _ = try await ComputerUse.within({ Date().timeIntervalSince(began) > 0.2 ? ComputerUse.tookTooLong : nil },
                                             every: .milliseconds(50), cut: { cut = true }) {
                try await Task.sleep(for: .seconds(30))
                return "late"
            }
            XCTFail("The work should not have finished.")
        } catch {
            XCTAssertEqual(error.localizedDescription, ComputerUse.tookTooLong.message)
        }
        XCTAssertTrue(cut)
        XCTAssertLessThan(Date().timeIntervalSince(began), 5)
    }

    /// Some of what a task waits on can't be cancelled (a browser's AppleScript): the limit doesn't wait for it.
    func testTheLimitDoesNotWaitForWorkThatCannotBeCancelled() async {
        let began = Date()
        do {
            _ = try await ComputerUse.within({ Date().timeIntervalSince(began) > 0.2 ? ComputerUse.tookTooLong : nil },
                                             every: .milliseconds(50)) {
                await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 4) { done.resume() }
                }
                return "late"
            }
            XCTFail("The work should not have been waited for.")
        } catch {
            XCTAssertEqual(error.localizedDescription, ComputerUse.tookTooLong.message)
        }
        XCTAssertLessThan(Date().timeIntervalSince(began), 2)
    }

    func testWorkThatFinishesInTimeIsItsOwnAnswer() async throws {
        let answer = try await ComputerUse.within({ nil }, every: .milliseconds(50)) { "done" }
        XCTAssertEqual(answer, "done")
    }
}
