import Foundation

extension Platform {
    /// An app for a device Lamp has no kit for, made and put on it the way its integration declares (`DeviceApps`),
    /// which `LampProject.integration` names.
    static let device = Platform(kind: "device")
}

extension Target {
    static let device = Target(
        platform: .device, places: [.device],
        identity: Identity(name: "the device's app", phrase: "an app for one of the person's own devices", analytics: "device",
                           made: { device, whose in "\(whose) \(device ?? "device")" },
                           // One of a wish's apps like any other, by its integration's id.
                           devices: Words(words: [], toolNote: "or the id of a device integration that declares its apps (\"roku\"), for an app that runs on that device",
                                            hint: nil, claims: { $0.count == 1 && $0.first.map(DeviceApps.makesApps) == true && !GameKit.claims($0) },
                                            owns: DeviceApps.makesApps, alone: false),
                           tryOnHelp: { "Where it opens: which of your \(DeviceApps.integration(for: $0)?.name ?? "devices") it goes on" },
                           place: { _ in .device }),
        guidance: Guidance(prompt: Agent.devicePrompt,
                           changeRules: { project in
                               Agent.Rules.deviceEdit + Agent.Rules.deviceKind(DeviceApps.integration(for: project)) + Agent.Rules.deviceTry(project)
                           },
                           skills: { [] },
                           noAI: { project in
                               DeviceSupport.libraries(for: project).isEmpty
                                   ? "- None: this device's integration takes none of Lamp's building blocks, so the app has no AI from Lamp." : nil
                           },
                           elsewhere: { "- On the person's \(DeviceApps.integration(for: $0)?.name ?? "device"): the same, while it's on this Mac's Wi‑Fi with Lamp open; away from it, or with Lamp closed, no AI" }),
        // Its build is the integration's package step, which Lamp holds; its own files are the building blocks the
        // integration asks for, and its code says which device it's for.
        recipe: Recipe(language: .device, fill: DeviceApps.fill, ownedFiles: DeviceSupport.write(for:), support: DeviceSupport.write(for:),
                       isMade: DeviceApps.isScaffolded, scaffolded: { dir, project in project.platform == .device && DeviceApps.isScaffolded(dir) },
                       sources: { DeviceApps.sourceRoots($0).map(\.lastPathComponent) },
                       // A new package step is a change too.
                       inputs: { project in
                           guard let declared = DeviceApps.integration(for: project)?.app?.declared else { return nil }
                           return declared.package + "\n" + declared.output + "\n" + (project.integration ?? "")
                       },
                       builtURL: DeviceApps.packageURL(for:), marker: DeviceApps.marker, refills: true, integration: DeviceApps.integrationID(in:),
                       shareRefusal: "Lamp doesn't share apps for devices like this one yet."),
        // One of a wish's apps in a folder named for its device (Roku/), one per wish: what makes it, builds it and puts it
        // on the device is its integration's, as for a wish of its own. It doesn't join the wish's room yet.
        part: Part(folder: "Device", family: "device", word: "device", menu: ("Device", "appletvremote.gen4"),
                   rules: { Agent.devicePrompt(part: $0, alone: $1) }, wishRule: Agent.Rules.deviceAmongApps,
                   isMade: { dir, wish in DeviceApps.isMade(dir, wish: wish) },
                   folderFor: DeviceApps.folder(for:), moreFolders: DeviceApps.folders, joinsWish: false),
        setup: .none)
}

extension Language {
    /// Each device's own: going to a device app always writes the app again in the scaffold its integration gave.
    static let device = Language(name: "device", code: "the code that was for the device", leftover: "the files that were for the device") {
        "Write the app again for the device, in the scaffold its integration gave (it's there now), reading \($0) for what it does, then delete \($1) with delete_file. "
    }
}
