import Sparkle
import SwiftUI

/// Updates Lamp with Sparkle: once a day it reads the update feed (SUFeedURL in Info.plist, served by
/// updates/ on Vercel from the GitHub releases), and when there's a newer version it shows Sparkle's
/// standard window with the release notes and an Install button. Every update must be signed with
/// Lamp's update key (SUPublicEDKey) and by the same Developer ID team, or Sparkle refuses it.
///
/// Only release builds update: a build from source (no Apple Team ID) has nothing to update from, and
/// would otherwise offer to replace itself with the latest release.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    private let controller: SPUStandardUpdaterController?
    @Published private(set) var canCheck = false

    var isEnabled: Bool { controller != nil }

    private init() {
        guard KeyStore.usesKeychain, Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else {
            controller = nil
            return
        }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        controller?.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
    }

    func checkForUpdates() { controller?.checkForUpdates(nil) }
}

/// Lamp → Check for Updates…, in release builds.
struct CheckForUpdatesCommand: Commands {
    @ObservedObject private var updater = Updater.shared

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            if updater.isEnabled {
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheck)
            }
        }
    }
}
