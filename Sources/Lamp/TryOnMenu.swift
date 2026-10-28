import AppKit

/// Try On's choices, as one list: where the wish opens now and on what (a tick on where Play puts it), and for a kind
/// whose places are given one at a time (a game, a screen) each place it hasn't got yet; any other kind reaches another
/// device as one more app of the wish (`another`). The chat's bar draws it in its
/// device button (`SidebarTryOn`) and the desk in a wish's menu, so the two never offer different things. A choice is
/// named by its `id` and done by `Store.tryOn(_:_:)`.
struct TryOnMenu: Equatable {
    struct Item: Equatable, Identifiable {
        /// What choosing it does, for `Store.tryOn`: "mac", "family:ipad", "simulator:<udid>", "phone:<udid>", "pair:<udid>", "emulator",
        /// "emulator:tv", "android:<serial>", "androidtv:<serial>", "preview", "tv:<id>", "device:<id>", "add:<place>", "another", or "settings", "look" and "localnetwork".
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
    /// The symbol for where Play puts it now, for the chat's button: nil for a wish that opens nowhere itself.
    let symbol: String?

    /// Every kind's places but a Mac app's alone, which has only this Mac: a game's or a screen's (`places`), a TV app's,
    /// a device app's, an Android app's, and an Apple app's simulators and phones.
    @MainActor static func make(for project: LampProject, store: Store) -> TryOnMenu? {
        // A wish whose apps are all in folders of their own opens nowhere itself: each app has its own menu, and the wish
        // has only the way to one more app.
        guard project.holdsApp else {
            return project.isPart || project.partFolders.isEmpty ? nil : TryOnMenu(sections: [Section(title: nil, items: [another])], symbol: nil)
        }
        guard project.platform.addsPlaces else { return choices(for: project, store: store) }
        let places = project.openPlaces, verb = ScreenKit.isScreen(project) ? "Show" : "Play"
        // A place whose copy is older than the code says so, and that opening it there brings it up to date.
        let behind = store.placesBehind[project.id] ?? []
        func older(_ place: Destination, _ title: String) -> String { behind.contains(place) ? title + Self.olderNote : title }
        var sections: [Section] = []
        func step(_ device: Device) -> String { device.setup() == .ready && !device.isAway ? "" : " (\(device.status))" }
        func stopped(_ device: Device) -> String { PhoneRenewals.stoppedOpening(project, on: device.udid) ? " (stopped opening)" : "" }
        if places.contains(.mac) {
            sections.append(Section(title: nil, items: [Item(id: "mac", title: older(.mac, "My Mac"), symbol: "laptopcomputer", checked: project.destination == .mac)]))
        }
        if places.contains(.ios) {
            let simulator = project.onIOS && project.device == nil
            // Lamp's pick of the family, unless one simulator was chosen by name.
            let byFamily = simulator && project.simulator == nil
            sections.append(Section(title: older(.ios, "Simulator"), items: [
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
                Item(id: "phone:\(device.udid)", title: "\(device.name) · \(device.model)\(step(device))\(stopped(device))", symbol: device.kind.symbol,
                     checked: project.onIOS && project.device == device.udid)
            }
            mine += phones.filter { !$0.paired }.map { device in
                let pairing = store.pairing.contains(device.udid)
                return Item(id: "pair:\(device.udid)", title: pairing ? "Pairing with \(device.name)…" : "Pair \(device.name) (\(device.model))…",
                            symbol: device.kind.symbol, disabled: pairing)
            }
            if !mine.isEmpty { sections.append(Section(title: "Your iPhones and iPads", items: mine)) }
        }
        // One app of Lamp's around the page on Android phones and TVs alike: each place its emulator and its devices.
        for place in [Destination.android, .androidTV] where places.contains(place) {
            let tv = place == .androidTV, here = project.destination == place
            var items = [Item(id: tv ? "emulator:tv" : "emulator", title: tv ? AndroidTools.tvAVDName : AndroidTools.avdName,
                              symbol: tv ? "tv" : "smartphone", checked: here && project.device == nil)]
            items += store.devices.filter { $0.kind == .android && $0.features.contains("tv") == tv }.map { device in
                Item(id: (tv ? "androidtv:" : "android:") + device.udid, title: "\(device.name)\(step(device))", symbol: tv ? "tv" : "smartphone",
                     checked: here && project.device == device.udid)
            }
            sections.append(Section(title: older(place, tv ? "Android TV" : "Android"), items: items))
        }
        if places.contains(where: \.isAndroid) {
            let tv = !places.contains(.android)
            sections.append(Section(title: nil, items: [Item(id: "wifi:android", title: tv ? "Connect a TV Over Wi‑Fi…" : "Connect Over Wi‑Fi…", symbol: "wifi")]))
        }
        if places.contains(.tv) {
            var items = [Item(id: "preview", title: "TV Preview", symbol: "tv", checked: project.onTV && project.device == nil)]
            items += store.devices.filter { $0.kind.isTV }.map { tv in
                Self.item(tv, id: "tv:\(tv.udid)", title: "\(tv.name)\(step(tv))", symbol: "tv", checked: project.onTV && project.device == tv.udid)
            }
            sections.append(Section(title: older(.tv, "TVs"), items: items))
        }
        if places.contains(.device) {
            let name = DeviceApps.integration(for: project)?.name ?? "Xbox"
            let mine = store.devices.filter { $0.integration != nil && $0.integration == project.deviceIntegration }
            let items = mine.map { device in
                Self.item(device, id: "device:\(device.id)", title: "\(device.name)\(step(device))", symbol: device.kind.symbol,
                          checked: project.onDevice && project.device == device.id)
            }
            sections.append(Section(title: older(.device, "Your \(name)s"), items: items.isEmpty
                ? [Item(id: "look", title: "No \(name) found. Look Again", symbol: Device.Kind.other.symbol, checked: project.onDevice)] : items))
        }
        var missing = Store.placesToAdd(project).map { place in
            Item(id: "add:\(place.rawValue)", title: "\(verb) on \(place == .ios ? "iPhone and iPad" : GameKit.placeName(place)) Too", symbol: "plus")
        }
        // Where a page can't go, said under the places it can, whether or not one is left to add: every built-in row
        // with no host, and an integration's only once the person has one of its devices. Lamp's own gap is told apart
        // from the device's.
        let mine = Set(store.devices.filter(\.isSetUp).compactMap(\.integration))
        missing += Places.noPage().filter { Places.builtIn.contains($0) || mine.contains($0.id) }.map { place in
            Item(id: "native:\(place.id)", title: "\(place.name): \(place.noHostYet ? "Native Only for Now" : "Needs a Native Version")",
                 symbol: "nosign", disabled: true)
        }
        if !missing.isEmpty { sections.append(Section(title: nil, items: missing)) }
        sections.append(look(store))
        let symbol = sections.flatMap(\.items).first(where: \.checked)?.symbol ?? "laptopcomputer"
        return TryOnMenu(sections: sections, symbol: symbol)
    }
}

extension TryOnMenu {
    /// Said beside a place whose copy is older than the code (`Store.placesBehind`).
    static let olderNote = " (older version, updated when opened)"

    @MainActor private static func step(_ device: Device) -> String { device.setup() == .ready && !device.isAway ? "" : " (\(device.status))" }

    /// A TV or device as a place: one set up with Lamp is chosen as it is; one only found on the network may be a
    /// neighbor's, so it's offered to set up instead, and choosing it runs its setup and chooses it once that's done
    /// (`Store.setTVDevice`, `Store.setDeviceAppDevice`). One already chosen keeps its tick.
    static func item(_ device: Device, id: String, title: String, symbol: String, checked: Bool) -> Item {
        guard !device.isSetUp, !checked else { return Item(id: id, title: title, symbol: symbol, checked: checked) }
        return Item(id: id, title: "Set Up \(device.name)…", symbol: "gearshape")
    }

    /// Every list's last section: all the devices, and looking again; and when macOS refused the last look on the
    /// network, the way to allow Lamp there.
    @MainActor static func look(_ store: Store) -> Section {
        var items = [Item(id: "settings", title: "All Your Devices…", symbol: "gearshape"),
                     Item(id: "look", title: "Look for Devices Again", symbol: "arrow.clockwise")]
        if store.localNetworkRefused {
            items.insert(Item(id: "localnetwork", title: "Allow Lamp on Your Local Network…", symbol: "wifi.exclamationmark"), at: 1)
        }
        return Section(title: nil, items: items)
    }

    /// One more app of the wish, for another device: the wish's chat is asked for it, as the person would ask
    /// (`Store.tryOn`), and the agent asks which device and whether it's a second app or this one changed.
    static let another = Item(id: "another", title: "Add an App for Another Device…", symbol: "plus")
    /// What choosing it says in the wish's chat, as the person's request.
    static let anotherRequest = "Add an app for another device to this wish."

    /// The places of a kind given its places by what it is, not one at a time: nil for a Mac app, which has only this Mac.
    @MainActor static func choices(for project: LampProject, store: Store) -> TryOnMenu? {
        guard project.platform.target.places != [.mac] else { return nil }
        var sections: [Section] = []
        let look = look(store)
        if project.onDevice {
            let name = DeviceApps.integration(for: project)?.name ?? "device"
            let mine = store.devices.filter { $0.integration != nil && $0.integration == project.deviceIntegration }
            sections.append(Section(title: "Your \(name)s", items: mine.isEmpty
                ? [Item(id: "look", title: "No \(name) found. Look Again", symbol: Device.Kind.other.symbol, checked: true)]
                : mine.map { device in
                    item(device, id: "device:\(device.id)", title: (device.name == device.model ? device.name : "\(device.name) · \(device.model)") + step(device),
                         symbol: device.kind.symbol, checked: project.device == device.id)
                }))
            var setups = mine.filter { $0.isSetUp && $0.setup() != .ready && !$0.isAway }.map { Item(id: "setup:\($0.id)", title: "Set Up \($0.name)…", symbol: "gearshape") }
            if GameKit.isGame(project) { setups.append(Item(id: "check:xbox", title: "Check Xbox Setup for Games…", symbol: "checklist")) }
            if !setups.isEmpty { sections.append(Section(title: nil, items: setups)) }
        } else if project.onTV {
            let tvs = store.devices.filter { $0.kind.isTV }
            sections.append(Section(title: "Preview", items: [Item(id: "preview", title: "TV Preview", symbol: "tv", checked: project.device == nil)]))
            var items = tvs.map { tv in
                let model = "\(tv.maker) \(tv.model)"
                return item(tv, id: "tv:\(tv.udid)", title: (tv.name == model ? tv.name : "\(tv.name) · \(model)") + step(tv), symbol: "tv",
                            checked: project.device == tv.udid)
            }
            if let chosen = project.device, !tvs.contains(where: { $0.udid == chosen }) {
                items.append(Item(id: "tv:\(chosen)", title: "Chosen TV (not on the network)", symbol: "tv", checked: true))
            }
            if items.isEmpty { items.append(Item(id: "look", title: "No Samsung or LG TV found. Look Again", symbol: "tv", disabled: false)) }
            sections.append(Section(title: "Your TVs", items: items))
            let setups = tvs.filter { $0.isSetUp && $0.setup() != .ready && !$0.isAway }.map { Item(id: "tvsetup:\($0.udid)", title: "Set Up \($0.name)…", symbol: "gearshape") }
            if !setups.isEmpty { sections.append(Section(title: nil, items: setups)) }
        } else if project.onAndroid {
            let devices = store.devices.filter { $0.kind == .android }
            let tv = project.destination == .androidTV, prefix = tv ? "androidtv:" : "android:"
            var items = [Item(id: tv ? "emulator:tv" : "emulator", title: tv ? AndroidTools.tvAVDName : AndroidTools.avdName, symbol: tv ? "tv" : "smartphone", checked: project.device == nil)]
            items += devices.map { Item(id: prefix + $0.udid, title: "\($0.name)\(step($0))", symbol: "smartphone", checked: project.device == $0.udid) }
            if let chosen = project.device, !devices.contains(where: { $0.udid == chosen }) {
                items.append(Item(id: prefix + chosen, title: "Chosen device (not connected)", symbol: "smartphone", checked: true))
            }
            sections.append(Section(title: "Android", items: items))
            sections.append(Section(title: nil, items: [Item(id: "wifi:android", title: tv ? "Connect a TV Over Wi‑Fi…" : "Connect Over Wi‑Fi…", symbol: "wifi"),
                                                        Item(id: "check:android", title: "Check Android Setup…", symbol: "checklist")]))
        } else {
            if project.platform.choosesPlace, project.hasMac {
                // An app for both: this Mac is a place to open it too, beside the simulators and phones.
                let older = store.placesBehind[project.id]?.contains(.mac) == true
                sections.append(Section(title: nil, items: [Item(id: "mac", title: "My Mac" + (older ? olderNote : ""), symbol: "laptopcomputer", checked: project.destination == .mac)]))
            }
            let simulator = project.onIOS && project.device == nil
            let byFamily = simulator && project.simulator == nil
            var families = [Item(id: "family:iphone", title: "iPhone", symbol: "iphone", checked: byFamily && project.family == .iphone),
                            Item(id: "family:ipad", title: "iPad", symbol: "ipad", checked: byFamily && project.family == .ipad)]
            // The same SwiftUI app built for tvOS or visionOS: an app's own code, not a game's kit, which is iOS's.
            if Store.opens(project, on: .appletv) {
                families += [Item(id: "family:appletv", title: "Apple TV", symbol: "appletv", checked: byFamily && project.family == .appletv),
                             Item(id: "family:vision", title: "Apple Vision Pro", symbol: "visionpro", checked: byFamily && project.family == .vision)]
            }
            sections.append(Section(title: "Simulator" + (store.placesBehind[project.id]?.contains(.ios) == true ? olderNote : ""), items: families))
            let models = store.simulators.filter { Store.opens(project, on: $0.family) }.map { choice in
                Item(id: "simulator:\(choice.udid)", title: choice.label, symbol: choice.family.symbol, checked: simulator && project.simulator == choice.udid)
            }
            if !models.isEmpty { sections.append(Section(title: "Choose Simulator", items: models, submenu: true)) }
            let phones = store.devices.filter { $0.kind.isPhone }
            var mine = phones.filter(\.paired).map { device in
                Item(id: "phone:\(device.udid)", title: "\(device.name) · \(device.model)\(step(device))\(PhoneRenewals.stoppedOpening(project, on: device.udid) ? " (stopped opening)" : "")", symbol: device.kind.symbol,
                     checked: project.onIOS && project.device == device.udid)
            }
            if let chosen = project.device, project.onIOS, !phones.contains(where: { $0.udid == chosen && $0.paired }) {
                mine.append(Item(id: "phone:\(chosen)", title: "Chosen phone (not paired)", symbol: "iphone.slash", checked: true))
            }
            mine += phones.filter { !$0.paired }.map { device in
                let pairing = store.pairing.contains(device.udid)
                return Item(id: "pair:\(device.udid)", title: pairing ? "Pairing with \(device.name)…" : "Pair \(device.name) (\(device.model))…",
                            symbol: device.kind.symbol, disabled: pairing)
            }
            if !mine.isEmpty { sections.append(Section(title: "Your iPhones and iPads", items: mine)) }
            sections.append(Section(title: nil, items: [Item(id: "check:iphone", title: "Check iPhone & iPad Setup…", symbol: "checklist")]))
        }
        // A kind not given places one at a time reaches another device as one more app of the wish, asked for in its chat.
        if !project.isPart { sections.append(Section(title: nil, items: [another])) }
        sections.append(look)
        let symbol = sections.flatMap(\.items).first(where: \.checked)?.symbol ?? (project.onTV ? "tv" : project.onAndroid ? "smartphone" : "iphone")
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
        case "emulator": setAndroidDevice(project, nil, place: value == "tv" ? .androidTV : .android)
        case "android": setAndroidDevice(project, value)
        case "androidtv": setAndroidDevice(project, value, place: .androidTV)
        case "preview": setTVDevice(project, nil)
        case "tv": setTVDevice(project, value)
        case "device": setDeviceAppDevice(project, value)
        case "add": if let place = Destination(rawValue: value) { addPlace(project, place) }
        case "another":
            // As asking for it in the chat, which comes forward with the request in it.
            let wish = wish(of: project)
            send(TryOnMenu.anotherRequest, to: wish)
            showChat(wish.id)
            return
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
        case "localnetwork":
            NSWorkspace.shared.open(Store.localNetworkSettings)
            return
        case "setup":
            if let device = devices.first(where: { $0.id == value }) { DeviceSetupWindow.show(device) }
            return
        case "tvsetup":
            TVSetup.shared.show(value)
            return
        case "wifi":
            AndroidWiFi.shared.show()
            return
        case "check":
            NSApp.activate()
            switch value {
            case "xbox": WindowsSetup.shared.show()
            case "android": AndroidSetup.shared.show(device: project.device)
            default: PhoneSetup.shared.show(family: project.family, phone: project.device)
            }
            return
        default: return
        }
        // Pairing puts a question on the phone; the person chooses the phone once it's done.
        guard open, what != "pair", let wanted = Chosen(what, value) else { return }
        openWhenThere(project, wanted, again: { [weak self] in
            // A choice refused while the app was held (a build) is made again once it isn't; one with a setup isn't.
            guard let self, let now = self.current(project), ["mac", "family", "simulator", "emulator", "preview", "add"].contains(what) else { return }
            self.tryOn(now, id)
        })
    }

    /// Exactly where a choice puts the app: its place, its device (nil for a simulator, the emulator, the preview or
    /// the Mac), and for the simulator which one.
    private struct Chosen {
        let place: Destination
        let device: String?
        var family: DeviceFamily?
        var simulator: String??

        init?(_ what: String, _ value: String) {
            switch what {
            case "mac": (place, device) = (.mac, nil)
            case "family": (place, device, family, simulator) = (.ios, nil, DeviceFamily(rawValue: value), .some(nil))
            case "simulator": (place, device, simulator) = (.ios, nil, .some(value))
            case "phone": (place, device) = (.ios, value)
            case "emulator": (place, device) = (value == "tv" ? .androidTV : .android, nil)
            case "android": (place, device) = (.android, value)
            case "androidtv": (place, device) = (.androidTV, value)
            case "preview": (place, device) = (.tv, nil)
            case "tv": (place, device) = (.tv, value)
            case "device": (place, device) = (.device, value)
            case "add":
                guard let added = Destination(rawValue: value) else { return nil }
                (place, device) = (added, nil)
            default: return nil
            }
        }

        func matches(_ project: LampProject) -> Bool {
            guard project.destination == place, project.device == device || place == .mac else { return false }
            if let family, project.family != family { return false }
            if let simulator, project.simulator != simulator { return false }
            return true
        }
    }

    /// Opens the app where it was just chosen to open, once it points exactly there: at once for most choices, and after
    /// a check or the device's setup for the rest, however long that takes (a quarter of an hour at most). A choice
    /// refused while the app was held is made `again` once it isn't. A later choice takes this one's place. Opened even
    /// when a copy is open elsewhere, since this is where the person asked for it.
    private func openWhenThere(_ project: LampProject, _ wanted: Chosen, again: @escaping () -> Void) {
        let token = UUID()
        openingChosen[project.id] = token
        Task { @MainActor in
            var triedAgain = false
            for _ in 0..<1800 {
                try? await Task.sleep(for: .milliseconds(500))
                guard openingChosen[project.id] == token, let now = current(project) else { return }
                guard !busy.contains(now.id) else { continue }
                if wanted.matches(now) {
                    openingChosen[project.id] = nil
                    openPrepared(now)
                    return
                }
                if !triedAgain { triedAgain = true; again() }
            }
            if openingChosen[project.id] == token { openingChosen[project.id] = nil }
        }
    }
}
