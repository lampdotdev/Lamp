import XCTest
@testable import Lamp

@MainActor
final class PhoneSetupTests: XCTestCase {
    private func ready() -> PhoneTools.Report { PhoneTools.Report(passed: [.xcode, .tools, .firstLaunch, .platform, .runtime, .simulator]) }
    private func blocked(_ step: PhoneTools.Step = .tools) -> PhoneTools.Report {
        PhoneTools.Report(issue: .init(step: step, title: "Missing step", message: "Finish this step", action: .retry))
    }
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

    func testSubmissionDuringAutomaticRecheckKeepsItsOwnContext() async {
        var release: CheckedContinuation<PhoneTools.Report, Never>?
        var contexts: [PhoneSetup.Context] = []
        let model = PhoneSetup(presentsWindow: false) { context in
            contexts.append(context)
            if contexts.count == 1 { return await withCheckedContinuation { release = $0 } }
            return self.ready()
        }
        model.show(family: .iphone)
        var completed = false
        model.perform(family: .ipad, phone: "made-up-phone") { completed = true }
        while release == nil { await Task.yield() }
        release?.resume(returning: ready())
        await settle(model)
        XCTAssertTrue(completed)
        XCTAssertEqual(contexts, [.init(family: .iphone), .init(family: .ipad, phone: "made-up-phone")])
    }

    func testEitherSimulatorPolicySurvivesActionAndActivationRechecks() async {
        var toolsReady = false
        var contexts: [PhoneSetup.Context] = []
        let model = PhoneSetup(presentsWindow: false) { context in
            contexts.append(context)
            if !toolsReady { return self.blocked() }
            return context.eitherSimulator ? self.ready() : self.blocked(.simulator)
        }
        var completed = false
        model.perform(eitherSimulator: true) { completed = true }
        await settle(model)
        XCTAssertFalse(completed)
        toolsReady = true
        model.refresh() // What Use Xcode / Check Again does.
        await settle(model)
        model.refreshIfVisible() // Returning from Xcode.
        await settle(model)
        XCTAssertTrue(model.report?.ready == true)
        XCTAssertTrue(contexts.allSatisfy(\.eitherSimulator))
        XCTAssertFalse(completed) // A blocked request still requires Continue.
        model.finish()
        XCTAssertTrue(completed)
    }

    func testConfigurationChangeDuringCheckIsRecheckedBeforeAction() async {
        var current = PhoneSetup.Context(family: .iphone)
        var release: CheckedContinuation<PhoneTools.Report, Never>?
        var checked: [DeviceFamily] = []
        let model = PhoneSetup(presentsWindow: false) { context in
            checked.append(context.family)
            if checked.count == 1 { return await withCheckedContinuation { release = $0 } }
            return self.ready()
        }
        var applied: DeviceFamily?
        model.perform(resolve: { current }) { applied = current.family }
        while release == nil { await Task.yield() }
        current.family = .ipad
        release?.resume(returning: ready())
        await settle(model)
        XCTAssertEqual(checked, [.iphone, .ipad])
        XCTAssertEqual(applied, .ipad)
    }

    func testContinueRechecksChangedConfigurationAndResolvesLatestAction() async {
        var toolsReady = false
        var current = PhoneSetup.Context(family: .iphone)
        var name = "Original"
        var checked: [DeviceFamily] = []
        let model = PhoneSetup(presentsWindow: false) { context in
            checked.append(context.family)
            return toolsReady ? self.ready() : self.blocked()
        }
        var appliedName: String?
        model.perform(resolve: { current }) { appliedName = name }
        await settle(model)
        toolsReady = true
        model.refresh()
        await settle(model)
        name = "Renamed"
        current.family = .ipad
        model.finish()
        await settle(model)
        XCTAssertNil(appliedName)
        XCTAssertEqual(checked, [.iphone, .iphone, .ipad])
        model.finish()
        XCTAssertEqual(appliedName, "Renamed")
    }

    func testRemovedProjectCancelsWithoutApplyingAndNextRequestStillRuns() async {
        var current: PhoneSetup.Context? = .init()
        var toolsReady = false
        let model = PhoneSetup(presentsWindow: false) { _ in toolsReady ? self.ready() : self.blocked() }
        var applied = false, cancelled = false, nextRan = false
        model.perform(resolve: { current }, cancelled: { cancelled = true }) { applied = true }
        await settle(model)
        model.perform { nextRan = true }
        current = nil
        toolsReady = true
        model.refresh()
        await settle(model)
        XCTAssertTrue(cancelled)
        XCTAssertFalse(applied)
        XCTAssertTrue(nextRan)
    }

    func testClosingSetupCancelsAllPendingRequestsAndIgnoresLateResult() async {
        var release: CheckedContinuation<PhoneTools.Report, Never>?
        let model = PhoneSetup(presentsWindow: false) { _ in await withCheckedContinuation { release = $0 } }
        var completed = 0, cancelled = 0
        model.perform(cancelled: { cancelled += 1 }) { completed += 1 }
        model.perform(cancelled: { cancelled += 1 }) { completed += 1 }
        while release == nil { await Task.yield() }
        model.finishWithoutContinuing()
        release?.resume(returning: ready())
        await settle(model)
        XCTAssertEqual(cancelled, 2)
        XCTAssertEqual(completed, 0)
    }

    func testInspectingSetupDoesNotReplacePendingAction() async {
        var toolsReady = false
        let model = PhoneSetup(presentsWindow: false) { _ in toolsReady ? self.ready() : self.blocked() }
        var completed = false
        model.perform(eitherSimulator: true) { completed = true }
        await settle(model)
        model.show(family: .ipad)
        await settle(model)
        toolsReady = true
        model.refresh()
        await settle(model)
        model.finish()
        XCTAssertTrue(completed)
    }

    func testBusyDeviceChangeRetainsTheActionUntilItCanBeApplied() async {
        var busy = true
        let model = PhoneSetup(presentsWindow: false) { _ in self.ready() }
        var completed = 0
        model.perform(resolve: { .init() }, isReady: { !busy }) { completed += 1 }
        await settle(model)
        XCTAssertEqual(completed, 0)
        XCTAssertNotNil(model.actionProblem)
        busy = false
        model.finish()
        XCTAssertEqual(completed, 1)
    }

    func testChangingBlockedPhoneDraftToMacCompletesWithoutPhoneTools() async {
        var current = PhoneSetup.Context()
        var checks = 0, completed = 0
        let model = PhoneSetup(presentsWindow: false) { _ in
            checks += 1
            return self.blocked(.xcode)
        }
        model.perform(resolve: { current }) { completed += 1 }
        await settle(model)
        XCTAssertEqual(completed, 0)
        current.requiresPhoneTools = false
        model.refreshIfVisible()
        XCTAssertEqual(completed, 1)
        XCTAssertEqual(checks, 1)
    }

    func testChangingToMacDuringSlowPhoneCheckIgnoresItsBlockedResult() async {
        var current = PhoneSetup.Context()
        var release: CheckedContinuation<PhoneTools.Report, Never>?
        let model = PhoneSetup(presentsWindow: false) { _ in
            await withCheckedContinuation { release = $0 }
        }
        var completed = 0
        model.perform(resolve: { current }) { completed += 1 }
        while release == nil { await Task.yield() }
        current.requiresPhoneTools = false
        release?.resume(returning: blocked(.xcode))
        await settle(model)
        XCTAssertEqual(completed, 1)
        XCTAssertTrue(model.report?.ready == true)
    }

}
