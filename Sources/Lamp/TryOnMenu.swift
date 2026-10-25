import AppKit

/// Try On's choices for a kind whose places are given one at a time (a game, a screen), as one list: where it's played
/// or shown now and on what (a tick on where Play puts it), and each place it hasn't got yet. Lamp's window draws it in
/// the toolbar's Try On menu and the chat beside the app draws it in its bar's device button (`SidebarTryOn`), so the
/// two never offer different things. A choice is named by its `id` and done by `Store.tryOn(_:_:)`.
struct TryOnMenu: Equatable {
    struct Item: Equatable, Identifiable {
        /// What choosing it does, for `Store.tryOn`: "mac", "family:ipad", "simulator:<udid>", "phone:<udid>", "pair:<udid>", "emulator",
        /// "android:<serial>", "preview", "tv:<id>", "device:<id>", "add:<place>", or "settings" and "look".
        let id: String
        let title: String
        let symbol: String
        var checked = false
        var disabled = false
    }

    struct Section: Equatable {
        let title: String?
        let items: [Item]
        /// Drawn as a submenu under its title (Choose Simulator's models), not inline.
        var submenu = false
    }

    let sections: [Section]
    /// The symbol for where Play puts it now, for the chat's button.
    let symbol: String

    @MainActor static func make(for project: LampProject, store: Store) -> TryOnMenu? {
        guard project.platform.addsPlaces else { return nil }
        let places = project.openPlaces, verb = project.platform == .screen ? "Show" : "Play"
        var sections: [Section] = []
        func step(_ device: Device) -> String { device.setup() == .ready && !device.isAway ? "" : " (\(device.status))" }
        if places.contains(.mac) {
            sections.append(Section(title: nil, items: [Item(id: "mac", title: "My Mac", symbol: "laptopcomputer", checked: project.destination == .mac)]))
        }
        if places.contains(.ios) {
            let simulator = project.onIOS && project.device == nil
            // Lamp's pick of the family, unless one simulator was chosen by name.
            let byFamily = simulator && project.simulator == nil
            sections.append(Section(title: "Simulator", items: [
                Item(id: "family:iphone", title: "iPhone", symbol: "iphone", checked: byFamily && project.family == .iphone),
                Item(id: "family:ipad", title: "iPad", symbol: "ipad", checked: byFamily && project.family == .ipad),
            ]))
            // A particular model, for what only some have (a Dynamic Island, an iPad's size).
            let models = store.simulators.filter { Store.opens(project, on: $0.family) }.map { choice in
                Item(id: "simulator:\(choice.udid)", title: choice.label, symbol: choice.family.symbol,
                     checked: simulator && project.simulator == choice.udid)
            }
            if !models.isEmpty { sections.append(Section(title: "Choose Simulator", items: models, submenu: true)) }
            let phones = store.devices.filter { $0.kind.isPhone }
            var mine = phones.filter(\.paired).map { device in
                Item(id: "phone:\(device.udid)", title: "\(device.name) · \(device.model)\(step(device))", symbol: device.kind.symbol,
                     checked: project.onIOS && project.device == device.udid)
            }
            mine += phones.filter { !$0.paired }.map { device in
                let pairing = store.pairing.contains(device.udid)
                return Item(id: "pair:\(device.udid)", title: pairing ? "Pairing with \(device.name)…" : "Pair \(device.name) (\(device.model))…",
                            symbol: device.kind.symbol, disabled: pairing)
            }
            if !mine.isEmpty { sections.append(Section(title: "Your iPhones and iPads", items: mine)) }
        }
        if places.contains(.android) {
            var items = [Item(id: "emulator", title: AndroidTools.avdName, symbol: "smartphone", checked: project.onAndroid && project.device == nil)]
            items += store.devices.filter { $0.kind == .android }.map { device in
                Item(id: "android:\(device.udid)", title: "\(device.name)\(step(device))", symbol: "smartphone",
                     checked: project.onAndroid && project.device == device.udid)
            }
            sections.append(Section(title: "Android", items: items))
        }
        if places.contains(.tv) {
            var items = [Item(id: "preview", title: "TV Preview", symbol: "tv", checked: project.onTV && project.device == nil)]
            items += store.devices.filter { $0.kind.isTV }.map { tv in
                Item(id: "tv:\(tv.udid)", title: "\(tv.name)\(step(tv))", symbol: "tv", checked: project.onTV && project.device == tv.udid)
            }
            sections.append(Section(title: "TVs", items: items))
        }
        if places.contains(.device) {
            let name = DeviceApps.integration(for: project)?.name ?? "Xbox"
            let mine = store.devices.filter { $0.integration != nil && $0.integration == project.deviceIntegration }
            let items = mine.map { device in
                Item(id: "device:\(device.id)", title: "\(device.name)\(step(device))", symbol: device.kind.symbol,
                     checked: project.onDevice && project.device == device.id)
            }
            sections.append(Section(title: "Your \(name)s", items: items.isEmpty
                ? [Item(id: "look", title: "No \(name) found. Look Again", symbol: Device.Kind.other.symbol, checked: project.onDevice)] : items))
        }
        let missing = Store.placesToAdd(project).map { place in
            Item(id: "add:\(place.rawValue)", title: "\(verb) on \(place == .ios ? "iPhone and iPad" : GameKit.placeName(place)) Too", symbol: "plus")
        }
        if !missing.isEmpty { sections.append(Section(title: nil, items: missing)) }
        sections.append(Section(title: nil, items: [Item(id: "settings", title: "All Your Devices…", symbol: "gearshape"),
                                                    Item(id: "look", title: "Look for Devices Again", symbol: "arrow.clockwise")]))
        let symbol = sections.flatMap(\.items).first(where: \.checked)?.symbol ?? "laptopcomputer"
        return TryOnMenu(sections: sections, symbol: symbol)
    }
}

extension Store {
    /// Does what a Try On choice says (`TryOnMenu.Item.id`), from Lamp's window or the chat beside the app. From the
    /// chat (`open`), a place chosen or given is also where the wish opens at once: the chat has no Play of its own.
    func tryOn(_ project: LampProject, _ id: String, open: Bool = false) {
        guard let project = current(project) else { return }
        let (what, value) = id.firstIndex(of: ":").map { (String(id[..<$0]), String(id[id.index(after: $0)...])) } ?? (id, "")
        switch what {
        case "mac": setMac(project)
        case "family": if let family = DeviceFamily(rawValue: value) { setSimulator(project, family) }
        case "simulator": if let choice = simulators.first(where: { $0.udid == value }) { setSimulator(project, choice) }
        case "phone": choosePreparedDevice(project, value)
        case "pair": if let device = devices.first(where: { $0.udid == value }) { pairDevice(device, for: project) }
        case "emulator": setAndroidDevice(project, nil)
        case "android": setAndroidDevice(project, value)
        case "preview": setTVDevice(project, nil)
        case "tv": setTVDevice(project, value)
        case "device": setDeviceAppDevice(project, value)
        case "add": if let place = Destination(rawValue: value) { addPlace(project, place) }
        case "settings":
            // Every device Lamp knows, with where its setup stands, is in Settings → Building.
            NSApp.activate()
            UserDefaults.standard.set("building", forKey: "settingsTab")
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            return
        case "look":
            refreshDevices()
            refreshSimulators()
            return
        default: return
        }
        // Pairing puts a question on the phone; the person chooses the phone once it's done.
        if open, what != "pair" { openOnceSettled(project) }
    }

    /// Opens the wish where it now points, once the change of place has gone through (it holds the wish for a moment,
    /// and a new place is saved after a check): what Play would do, unless it's open there already.
    private func openOnceSettled(_ project: LampProject) {
        Task { @MainActor in
            for _ in 0..<100 {
                try? await Task.sleep(for: .milliseconds(100))
                if !busy.contains(project.id) { break }
            }
            guard let now = current(project), !isWishOpen(now) else { return }
            openWish(now)
        }
    }
}
