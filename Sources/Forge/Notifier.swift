import AppKit
import UserNotifications

/// Tells you when an app you're not looking at is ready, has a reply, or ran into a problem.
/// macOS is only asked for permission the first time there's something to send.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    /// Settings → Building. On unless turned off.
    static var enabled: Bool { UserDefaults.standard.object(forKey: "notify") as? Bool ?? true }

    /// Nil when running without a bundle (`swift run`), where the notification center crashes.
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : .current()
    }

    /// The permission request in flight, so apps finishing together share one prompt.
    private var asking: Task<Bool, Never>?

    func start() {
        center?.delegate = self
    }

    /// One notification per app: a newer one replaces the last. The subtitle says what happened.
    func post(for project: ForgeProject, subtitle: String, body: String) {
        guard Self.enabled, let center else { return }
        Task {
            guard await allowed(center) else { return }
            let content = UNMutableNotificationContent()
            // From Forge about the app, not from the app itself.
            content.title = "Lamp on \(project.name)"
            content.subtitle = subtitle
            content.body = body
            content.sound = .default
            content.threadIdentifier = project.id
            content.userInfo = ["app": project.id]
            if let icon = Self.iconCopy(for: project),
               let attachment = try? UNNotificationAttachment(identifier: "icon", url: icon) {
                content.attachments = [attachment]
            }
            try? await center.add(UNNotificationRequest(identifier: project.id, content: content, trigger: nil))
        }
    }

    /// Takes away an app's notification once its chat has been seen.
    func clear(_ id: String) {
        center?.removeDeliveredNotifications(withIdentifiers: [id])
    }

    /// The Dock badge counts the chats waiting for you.
    func setBadge(_ count: Int) {
        NSApp?.dockTile.badgeLabel = count > 0 && Self.enabled ? "\(count)" : nil
    }

    /// True when macOS has notifications turned off for Forge.
    func isDenied() async -> Bool {
        guard let center else { return false }
        return await center.notificationSettings().authorizationStatus == .denied
    }

    private func allowed(_ center: UNUserNotificationCenter) async -> Bool {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            let ask = asking ?? Task {
                (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            }
            asking = ask
            return await ask.value
        default:
            return false
        }
    }

    /// The system moves attachments into its own store, so it gets a copy of the icon.
    private static func iconCopy(for project: ForgeProject) -> URL? {
        let icon = Icons.previewURL(project)
        guard FileManager.default.fileExists(atPath: icon.path) else { return nil }
        let copy = FileManager.default.temporaryDirectory
            .appendingPathComponent("forge-notification-\(UUID().uuidString).\(icon.pathExtension)")
        return (try? FileManager.default.copyItem(at: icon, to: copy)) == nil ? nil : copy
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Shown while Forge is in front too, unless that app's chat is already on screen.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let id = notification.request.content.userInfo["app"] as? String
        Task { @MainActor in
            completionHandler(Store.shared.isWatching(id) ? [] : [.banner, .sound])
        }
    }

    /// Clicking a notification opens that app's chat.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.content.userInfo["app"] as? String
        Task { @MainActor in
            if let id { Store.shared.showChat(id) }
            completionHandler()
        }
    }
}
