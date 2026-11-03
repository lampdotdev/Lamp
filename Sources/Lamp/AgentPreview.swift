import Foundation

/// Where the agent looks at and uses an app when the person asks it to try it: a preview Lamp runs on this Mac (the app's
/// window here, the iPhone and iPad simulator, Lamp's Android emulators, the TV preview, a device integration's own
/// preview), never a device of the person's (their phone, iPad or Android device, a TV, the Xbox, a Roku). Try On still
/// says where the person's own Play, Reload and the turn's end put the app: that's delivery, and it reads the app as it's
/// kept. Only the agent's looks and uses go through here.
///
/// A preview isn't held apart from the world: it runs on the real network, so an app's own code there can reach the
/// person's devices, and a press in a remote app's preview changes the real TV. That press is what `device_permission`
/// allows (`DevicePermissions.useNeedsDevice`); the card never moves the test onto the device.
enum AgentPreview {
    /// The app as the agent looks at and uses it: where Try On points, with any device of the person's taken out, so it
    /// opens in that place's preview. Nil when the place has none Lamp can open and the app has no window on this Mac (a
    /// game in C++ for the Xbox, a device app whose integration has no preview).
    static func app(for project: LampProject) -> LampProject? {
        var preview = project
        switch project.destination {
        case .mac:
            return project
        case .ios:
            // `device` is only ever a physical phone or iPad (devicectl's listing); the simulator chosen under Try On is
            // `simulator`, a simulator's own udid, and stays.
            preview.device = nil
        case .android, .androidTV:
            // The person's phone, tablet or TV out; one of Lamp's own emulators, picked by its serial, is a preview.
            if let device = project.device, !isEmulator(device) { preview.device = nil }
        case .tv:
            preview.device = nil
        case .device:
            if DeviceApps.previewFolder(for: project) != nil {
                preview.device = nil
            } else if project.hasMac {
                return project.at(.mac)
            } else {
                return nil
            }
        }
        return preview
    }

    /// Whether an Android device key is one of Lamp's own emulators, by the serial adb gives it.
    static func isEmulator(_ key: String) -> Bool {
        Emulator.Kind.allCases.contains { $0.serial == key }
    }

    /// What a look or use says of an app with no preview Lamp can open.
    static func none(_ project: LampProject) -> String {
        "\(project.name) has no preview Lamp can open, so Lamp built it but didn't open it or look at it, and use_app can't "
            + "press anything in it. Never say it works: tell the person it's built, and that to see it they press Play or "
            + "pick their device under Try On."
    }
}
