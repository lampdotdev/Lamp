import Foundation

/// Installs of an app's new icon that are waiting for the app to close.
///
/// Lamp never replaces an app on disk while it's running. Replacing deletes the copy the running app was
/// started from, and macOS then no longer takes the app for the owner of its own widget: every request to
/// redraw the widget is refused until the app is opened again, so the widget stays as it was. A build quits
/// the app before installing; a new icon doesn't need the app to quit, so its install waits here instead,
/// and happens when the app closes or with the next build, whichever comes first.
struct HeldInstalls {
    private(set) var waiting: Set<String> = []

    /// Asked before an install that isn't part of a build. True to install now; false keeps it for later.
    mutating func mayInstall(_ app: String, running: Bool) -> Bool {
        guard running else {
            waiting.remove(app)
            return true
        }
        waiting.insert(app)
        return false
    }

    /// The apps among these that have an install waiting and can take it now: closed, with a build to
    /// install. One that can't isn't due, however often it's asked about: an app with no build gets its icon
    /// with the next build, and asking again in the meantime must find nothing to do.
    func due(amongClosed closed: Set<String>, where installable: (String) -> Bool = { _ in true }) -> Set<String> {
        waiting.intersection(closed).filter(installable)
    }

    /// A build installed the app, icon and all: nothing is waiting for it any more.
    mutating func installed(_ app: String) { waiting.remove(app) }
}
