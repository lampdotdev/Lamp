import Foundation
import WebKit

/// Removing a page's saved data (the TV preview's store, by its UUID: `TVPreview.store(for:)`). WebKit answers its calls
/// about stores that aren't open (`WKWebsiteDataStore.remove(forIdentifier:)`, and the list of them) on its own main run
/// loop, which exists only once something of WebKit has started in the process: made first, as when a wish is deleted
/// after Lamp was opened again without opening a preview, such a call crashes Lamp. So WebKit's default store is made
/// first, which starts it, and the calls are made and answered on the main thread. Kept apart from the preview, so a
/// test can run it in a process where nothing of WebKit has started.
@MainActor
enum PreviewStores {
    /// Removes the store, trying again while a page that has just closed still holds it (WebKit lets go a few seconds
    /// later); true once it's gone, which is at once for a store that isn't there.
    static func remove(_ id: UUID, tries: Int = 120, every: Duration = .milliseconds(250)) async -> Bool {
        _ = WKWebsiteDataStore.default()
        for attempt in 0..<tries {
            let error: Error? = await withCheckedContinuation { done in
                WKWebsiteDataStore.remove(forIdentifier: id) { done.resume(returning: $0) }
            }
            if error == nil { return true }
            if attempt + 1 < tries { try? await Task.sleep(for: every) }
        }
        return false
    }
}
