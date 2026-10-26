import Foundation
import Network

/// Whether macOS lets Lamp reach the home network (System Settings → Privacy & Security → Local Network). The system
/// says so only by turning a look down, so a short Bonjour browse asks it: one turned down for policy is a no.
enum LocalNetwork {
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork")!

    static func isDenied() async -> Bool {
        await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
            let browser = NWBrowser(for: .bonjour(type: "_airplay._tcp", domain: nil), using: .tcp)
            let queue = DispatchQueue(label: "lamp.local-network")
            var answered = false
            func answer(_ denied: Bool) {
                guard !answered else { return }
                answered = true
                browser.cancel()
                done.resume(returning: denied)
            }
            browser.stateUpdateHandler = { state in
                switch state {
                case .ready: answer(false)
                case .waiting(let error), .failed(let error): answer(isPolicy(error))
                default: break
                }
            }
            browser.start(queue: queue)
            // A browser that says nothing for a while isn't turned down.
            queue.asyncAfter(deadline: .now() + 2) { answer(false) }
        }
    }

    private static func isPolicy(_ error: NWError) -> Bool {
        if case .dns(let code) = error { return code == -65570 }   // kDNSServiceErr_PolicyDenied
        return false
    }
}
