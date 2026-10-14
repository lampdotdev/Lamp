import XCTest
@testable import Lamp

@MainActor
final class PhoneSetupTests: XCTestCase {
    private func ready() -> PhoneTools.Report { PhoneTools.Report(passed: [.xcode, .tools, .firstLaunch, .platform, .runtime, .simulator]) }
    private func settle(_ model: PhoneSetup) async {
        for _ in 0..<200 {
            await Task.yield()
            if !model.checking { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("The check did not finish")
    }

    func testAMessageGoesAheadOfABuildStoppedForAPaidMembership() async {
        var issue = PhoneTools.Issue(step: .account, title: "Needs a paid membership", message: "Join", action: .membership)
        issue.needsPaidTeam = true
        let stopped = PhoneTools.Report(issue: issue)
        let model = PhoneSetup(presentsWindow: false) { context in context.requiresPaidTeam ? stopped : self.ready() }
        var built = false, buildCancelled = false, sent = false, sendCancelled = false
        model.perform(resolve: { .init(requiresTeam: true, requiresPaidTeam: true) }, cancelled: { buildCancelled = true }) { built = true }
        await settle(model)
        XCTAssertTrue(model.hasRequest)
        XCTAssertFalse(built)
        // The window is still up when the person sends a message.
        model.perform(resolve: { .init(requiresTeam: true) }, cancelled: { sendCancelled = true }) { sent = true }
        await settle(model)
        XCTAssertTrue(sent)
        XCTAssertFalse(sendCancelled)
        XCTAssertTrue(buildCancelled)
        XCTAssertFalse(built)
        XCTAssertFalse(model.hasRequest)
    }

    func testEveryActionRunsWhenSubmittedDuringAnotherCheck() async {
        var release: CheckedContinuation<PhoneTools.Report, Never>?
        var calls = 0
        let model = PhoneSetup(presentsWindow: false) { _ in
            calls += 1
            if calls == 1 { return await withCheckedContinuation { release = $0 } }
            return self.ready()
        }
        var completed: [Int] = []
        model.perform { completed.append(1) }
        model.perform { completed.append(2) }
        model.perform { completed.append(3) }
        while release == nil { await Task.yield() }
        XCTAssertTrue(completed.isEmpty)
        release?.resume(returning: ready())
        await settle(model)
        XCTAssertEqual(completed, [1, 2, 3])
        XCTAssertEqual(calls, 3)
    }
}
