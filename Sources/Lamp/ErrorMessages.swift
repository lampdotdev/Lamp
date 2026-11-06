import Foundation

/// Store and Provider use these same phrases that the bug reporter recognizes, so editing the
/// user-facing wording cannot silently disconnect it from the privacy-safe report summaries.
enum ErrorMessages {
    static let buildFailed = "Sorry, I couldn't get that change working. Try describing it differently, or press Undo."
    static let appDoesNotBuild = "This app doesn't build right now. Describe a change and I'll fix it, or press Undo."
    static let restoreFailed = "Lamp couldn't go back to how the app was before that message, so nothing was sent."
    static let providerBusy = "The AI is busy right now. Wait a minute and try again."
    static let connectionFailed = "Couldn't reach the AI. Check your internet connection and try again."
    static let localServerUnreachable = "Couldn't reach the local model server. Check Settings → AI Providers → Native Mac AI."
    /// A model on this Mac that the server couldn't start, most often one newer than this Lamp's copy of llama.cpp.
    static let localModelFailed = "The model on this Mac couldn't start. Pick another in Settings → AI Providers → Native Mac AI, or update Lamp."
    static let localModelCantRunSuffix = " is too new for this Lamp to run. Pick another model in Settings → AI Providers → Native Mac AI, or update Lamp."
    static func localModelCantRun(_ model: String) -> String { model + localModelCantRunSuffix }

    static let openFailedPrefix = "Couldn't open the app: "
    static let installFailedPrefix = "Couldn't install the app: "
    static let aiFailedPrefix = "Something went wrong talking to the AI: "
    static let authenticationFailedSuffix = " key or sign-in didn't work. Check it in Lamp → Settings (⌘,)."
    static let quotaExceededSuffix = " account is out of credit or quota. Top it up, or pick another provider in Settings."
    static let crashAfterLaunchSuffix = " crashes when it opens. Ask me to fix the crash, or press Undo."
    static let crashedSuffix = " crashed again. Ask me to fix it, or press Undo."
    static let quitsAfterLaunchSuffix = " still quits right after opening. Try describing the change differently, or press Undo."
    static let setAsideSuffix = " crashed with the last change, so it's back as it was before it, with your data. The change is set aside to be fixed."

    /// A turn's change that was made but couldn't be saved as a version.
    static let versionNotSaved = "Lamp couldn't save this change as a version. It's in your app, and your next change will save both."

    /// The person's chat (its lines, what's typed in its box, a file sent with it) couldn't be written. It's still in
    /// Lamp's memory, above every chat and on the desk until Try Again writes it (`Store.saveTrouble`).
    static let chatNotSavedDiskFull = "Lamp couldn't save your chat. Free up disk space, then click Try Again."
    static let chatNotSaved = "Lamp couldn't save your chat. Click Try Again."

    /// Quitting with work that couldn't be saved (`AppDelegate.unsavedWorkLetsQuit`).
    static let quitUnsaved = "Lamp couldn't save your chat."
    static let quitUnsavedDiskFull = "Free up disk space, then click Retry. If you quit anyway, what wasn't saved is lost."
    static let quitUnsavedOther = "Click Retry to try again. If you quit anyway, what wasn't saved is lost."

    /// A failed write whose own error, or one beneath it, says the disk is full; or one that says nothing of why, on a
    /// disk with next to nothing left.
    static func isOutOfSpace(_ error: Error) -> Bool {
        var said: [String] = []
        var next: NSError? = error as NSError
        while let current = next {
            if current.domain == NSPOSIXErrorDomain, [Int(ENOSPC), Int(EDQUOT)].contains(current.code) { return true }
            if current.domain == NSCocoaErrorDomain, current.code == NSFileWriteOutOfSpaceError { return true }
            said.append(current.localizedDescription)
            next = current.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return isOutOfSpace(said)
    }

    /// The disk is full: something said so, or there's next to nothing left on it.
    static func isOutOfSpace(_ output: [String]) -> Bool {
        if output.contains(where: { $0.localizedCaseInsensitiveContains("no space left") || $0.contains("os error 28") }) { return true }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let free = (try? home.resourceValues(forKeys: [.volumeAvailableCapacityKey]))?.volumeAvailableCapacity
        return free.map { $0 < 200_000_000 } ?? false
    }

    /// A connection that didn't work, whatever Lamp was fetching: callers look things up as well as download them.
    static let noConnection = "Lamp couldn't connect. Check your internet connection and try again."

    /// What to show for an error from setting something up: the plain sentence for a connection that didn't work, the
    /// error's own words for anything else, and nil for a request that was cancelled, where there's nothing to report.
    static func reason(_ error: Error) -> String? {
        if isCancelled(error) { return nil }
        return isConnectivity(error) ? noConnection : error.localizedDescription
    }

    /// Asked to stop, by Swift's cancellation or URLSession's.
    static func isCancelled(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let error = error as NSError
        return error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled
    }

    /// Only the errors that mean the far end wasn't reached. A bad certificate, a refused sign-in, a bad address, a
    /// reply that can't be read or a file that can't be written are other problems, and a connection check won't fix them.
    static func isConnectivity(_ error: Error) -> Bool {
        let error = error as NSError
        guard error.domain == NSURLErrorDomain else { return false }
        return [NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut, NSURLErrorCannotFindHost,
                NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed, NSURLErrorInternationalRoamingOff,
                NSURLErrorDataNotAllowed].contains(error.code)
    }

    static func openFailed(_ detail: String) -> String { openFailedPrefix + detail }
    /// A build that found the app open, where the person chose to keep it open rather than lose what it held.
    static func stayedOpen(_ app: String) -> String { app + " stayed open, so it's still the earlier version. Close it to get the new one." }
    /// Beside Force Quit, for an app that was asked to quit and doesn't answer: what the click costs.
    static func notResponding(_ app: String) -> String { app + " isn't responding. Forcing it to quit loses anything unsaved in it." }
    static func notDeleted(_ app: String) -> String { app + " stayed open, so it wasn't deleted." }
    static func installFailed(_ detail: String) -> String { installFailedPrefix + detail }
    static func aiFailed(_ detail: String) -> String { aiFailedPrefix + detail }
    static func authenticationFailed(_ provider: String) -> String { "Your " + provider + authenticationFailedSuffix }
    static func quotaExceeded(_ provider: String) -> String { "Your " + provider + quotaExceededSuffix }
    static func crashAfterLaunch(_ app: String) -> String { app + crashAfterLaunchSuffix }
    static func quitsAfterLaunch(_ app: String) -> String { app + quitsAfterLaunchSuffix }
    static func crashed(_ app: String) -> String { app + crashedSuffix }
    /// A change that crashed the open app as it went in: the version before it is open again.
    static func setAside(_ app: String) -> String { app + setAsideSuffix }
}
