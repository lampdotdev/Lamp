import SwiftUI
import RealityKit

/// What the HUD shows, updated a few times a second.
final class HUDModel: ObservableObject {
    @Published var loaded = false
    @Published var failed = false
    /// The place's map came, but with no streets to drive (open sea, a park's middle): somewhere else is needed.
    @Published var noStreets = false
    /// What the loading screen says while the city is got ready.
    @Published var status = "Building downtown \(CityConfig.current.name)…"
    /// Bumped on travelling somewhere: the scene is made anew for the new place.
    @Published var place = 0
    @Published var speed: Float = 0
    @Published var street = ""
    @Published var area = ""
    @Published var heading: Float = 0
    @Published var pos: SIMD2<Float> = .zero
    @Published var boost: Float = 1
    @Published var boosting = false
    @Published var crash: Float = 0
    @Published var damage: Float = 0
    @Published var prompt: String?
    @Published var toast: String?
    var city: City?
    @Published var business: BusinessInfo?
    var businesses: [BusinessMarker] = []
    var traffic: [SIMD2<Float>] = []
    var rails: [[SIMD2<Float>]] = []
    var trains: [SIMD2<Float>] = []
    /// The F3 readout: frame rate, slowest frame, main-thread costs; nil while hidden.
    @Published var debug: String?
}

/// The game: the city, the player's car, the traffic and the chase camera.
@MainActor
final class Game {
    let hud = HUDModel()
    let nav = NavModel()
    private var mapHeld = false
    private var travelHeld = false
    /// When the build finished, for lifting the loading screen once the world is drawn.
    private var readyAt: CFTimeInterval?
    private var city: City?
    private var physics: Physics?
    private var traffic: Traffic?
    private var crowd: Crowd?
    private var riders: Riders?
    private var shops: Businesses?
    private var railway: Railway?
    private var lastRear: ObjectIdentifier?
    private var streamer: TileStreamer?
    private let player = 0
    private var parked: [Int] = []
    private var steer: Float = 0
    private var boost: Float = 1
    private var camHeading: Float?
    private var camPos: SIMD3<Float>?
    private var fov: Float = 62
    private var shake: Float = 0
    private var lastHUD: Float = -1
    private var lastCull: Float = -1
    private var resetHeld = false
    private var switchHeld = false
    private var onFoot = false
    private var walker: (root: Entity, figure: Entity, legs: [Entity], arms: [Entity])?
    private var walkPhase: Float = 0
    private var spareSlots: [Int] = []
    private var jumpY: Float = 0, jumpV: Float = 0
    private var riding: RideKind?
    private var rig: (root: Entity, figure: Entity, legs: [Entity], arms: [Entity])?
    private var ridePhase: Float = 0
    private var parkedRides: [(entity: Entity, kind: RideKind, pos: SIMD2<Float>)] = []
    private var sirenOn = false
    private var qHeld = false
    private var gHeld = false
    private var actionOn = false
    private var actionAmount: Float = 0
    private var hopY: Float = 0
    private var hopV: Float = 0
    private var fx: CrashFX?
    /// Your clothes, the same on foot and on anything you ride.
    private var playerLook = Crowd.Look()
    private var treeFall: TreeFall?
    private var geysers: Geysers?
    private var lastThud: Float = 0
    private var drivingTrain: Int?
    private var toastUntil: Float = 0
    /// How long the player's car has been under water.
    private var sunkFor: Float = 0
    private var lastFlash: Float = 0
    private var now: Float = 0

    nonisolated init() {}

    static let props: [String: @MainActor () -> Entity] = [
        "suv": { CarFactory.make(.suv, color: CarFactory.colors[4]) },
        "sports": { CarFactory.make(.sports, color: CarStyle.sports.paint(0)) },
        "pickup": { CarFactory.make(.pickup, color: CarFactory.colors[3]) },
        "van": { CarFactory.make(.van, color: CarFactory.colors[0]) },
        "police": { CarFactory.make(.police, color: CarStyle.police.paint(0)) },
        "taxi": { CarFactory.make(.taxi, color: CarStyle.taxi.paint(0)) },
        "ambulance": { CarFactory.make(.ambulance, color: CarStyle.ambulance.paint(0)) },
        "boxtruck": { CarFactory.make(.boxTruck, color: CarFactory.colors[4]) },
        "bus": { CarFactory.make(.bus, color: CarStyle.bus.paint(0)) },
        "bulldozer": { CarFactory.make(.bulldozer, color: CarStyle.bulldozer.paint(0)) },
        "excavator": { CarFactory.make(.excavator, color: CarStyle.excavator.paint(0)) },
        "dumptruck": { CarFactory.make(.dumpTruck, color: CarStyle.dumpTruck.paint(0)) },
        "mixer": { CarFactory.make(.cementMixer, color: CarStyle.cementMixer.paint(3)) },
        "firetruck": { CarFactory.make(.fireTruck, color: CarStyle.fireTruck.paint(0)) },
        "garbage": { CarFactory.make(.garbageTruck, color: CarStyle.garbageTruck.paint(0)) },
        "monster": { CarFactory.make(.monsterTruck, color: CarStyle.monsterTruck.paint(1)) },
        "limo": { CarFactory.make(.limo, color: CarStyle.limo.paint(0)) },
        "golfcart": { CarFactory.make(.golfCart, color: CarStyle.golfCart.paint(0)) },
        "icecream": { CarFactory.make(.iceCream, color: CarStyle.iceCream.paint(0)) },
        "supercar": { CarFactory.make(.supercar, color: CarStyle.supercar.paint(2)) },
        "hatch": { CarFactory.make(.hatch, color: CarFactory.colors[3]) },
        "tree": { TreeFactory.make(0) },
        "person": { Crowd.makePerson().0 },
        "freight": { RollingStock.sample(RollingStock.freight()) },
        "intercity": { RollingStock.sample(RollingStock.intercity()) },
        "shops1": { ShopBuilder.sample([.cafe, .restaurant, .bar, .pub]) },
        "shops2": { ShopBuilder.sample([.fastFood, .bank, .theatre, .clothes]) },
        "shops3": { ShopBuilder.sample([.books, .gifts, .grocery, .pharmacy]) },
        "shops4": { ShopBuilder.sample([.salon, .garage, .hotel, .generic]) },
        "cyclist": { Riders.makeRider(.bike).0 },
        "scooter": { Riders.makeRider(.scooter).0 },
        "hoverboard": { Riders.makeRider(.hoverboard).0 },
        "unicycle": { Riders.makeRider(.unicycle).0 },
        "skateboard": { Riders.makeRider(.skateboard).0 },
        "wheelboard": { Riders.makeRider(.wheelboard).0 },
        "rollerblades": { Riders.makeRider(.rollerblades).0 },
    ]

    // MARK: Building the city

    /// Back to how a new game starts: build can run again on the same game (a live change can give the view a
    /// fresh scene), so everything it fills is emptied first and running it twice is the same as running it once.
    private func resetState() {
        streamer = nil
        city = nil; physics = nil; traffic = nil; crowd = nil; riders = nil; shops = nil; railway = nil
        fx = nil; treeFall = nil; geysers = nil
        lastRear = nil
        parked = []; spareSlots = []; parkedRides = []
        steer = 0; boost = 1; camHeading = nil; camPos = nil; fov = 62; shake = 0
        lastHUD = -1; lastCull = -1; lastThud = 0; lastFlash = 0; toastUntil = 0; now = 0
        resetHeld = false; switchHeld = false; mapHeld = false; qHeld = false; gHeld = false
        onFoot = false; walker = nil; walkPhase = 0; jumpY = 0; jumpV = 0
        riding = nil; rig = nil; ridePhase = 0
        sirenOn = false; actionOn = false; actionAmount = 0; hopY = 0; hopV = 0
        drivingTrain = nil
        Synth.shared.motor = false; Synth.shared.siren = false; Synth.shared.horn = false; Synth.shared.spray = 0
        readyAt = nil
        hud.street = ""; hud.area = ""; hud.speed = 0
        hud.loaded = false; hud.failed = false; hud.noStreets = false; hud.toast = nil; hud.prompt = nil; hud.business = nil
        hud.traffic = []; hud.trains = []; hud.rails = []; hud.businesses = []
        nav.mapOpen = false
        nav.travelOpen = false
        nav.clear()
        nav.onTravel = { [weak self] place in self?.travel(to: place) }
    }

    /// Sets the game somewhere else: remembers the place and has the view build the game afresh there.
    func travel(to place: TravelPlace) {
        place.remember()
        CityConfig.current = place.config
        hud.status = "Building \(place.name)…"
        hud.loaded = false
        hud.place += 1
    }

    func build(_ scene: LampScene) async {
        resetState()
        scene.root.findEntity(named: "nightLight")?.removeFromParent()
        scene.root.addChild(DayTime.extraLight())
        try? await Task.sleep(for: .milliseconds(80))
        // The city's downtown: from its cache, or made from the map the first time the city is opened.
        let hud = self.hud
        guard let file = await CityLoader.load(CityConfig.current, status: { text in Task { @MainActor in hud.status = text } }) else {
            hud.failed = true
            return
        }
        guard !file.edges.isEmpty else {
            hud.noStreets = true
            hud.failed = true
            return
        }
        // The real lie of the land, before anything is set on it.
        await Terrain.shared.load(CityConfig.current, status: { text in Task { @MainActor in hud.status = text } })
        let city = City(file: file)
        self.city = city
        hud.city = city
        nav.city = city
        nav.onLook = { [weak self] area in self?.streamer?.lookArea = area }
        nav.onTrip = { [weak self] dest in
            guard let self, let physics = self.physics else { return }
            self.streamer?.trip = (physics.bodies[self.player].pos, dest)
        }
        let physics = Physics(city: city)
        self.physics = physics
        let traffic = Traffic(city: city, physics: physics)
        self.traffic = traffic

        // The city's data is the game's; its looks are drawn 150 m at a time by the scene's streaming.
        let builder = CityBuilder(city: city)
        builder.buildGround(into: scene.root)
        let shops = Businesses(city: city)
        CityTiles.reset()
        CityTiles.city = city
        CityTiles.traffic = traffic
        CityTiles.shops = shops
        CityTiles.add(builder.downtown(), shops: Array(shops.all.indices))
        fx = CrashFX(into: scene.root)
        treeFall = TreeFall(into: scene.root)
        geysers = Geysers(into: scene.root)
        let railway = Railway(city: city, physics: physics)
        self.railway = railway
        hud.rails = railway.lines.map(\.pts)
        self.shops = shops
        city.addShops(shops.all.map(\.pos))
        hud.businesses = shops.markers
        refreshPlaces()

        // The player starts in a vehicle picked at random (any kind but the excavator, which can't drive far),
        // on the street nearest the place's centre.
        let start = startPoint(city)
        let style = CarStyle.allCases.filter { $0 != .excavator }.randomElement() ?? .sedan
        let car = CarFactory.make(style, color: style.paint(Int.random(in: 0..<1000)))
        scene.add(car)
        let size = CarFactory.size(style)
        let mass = style.handling.mass
        var me = Body(pos: start.0, heading: start.1, mass: mass, inertia: mass * (size.x * size.x + size.y * size.y) / 12,
                      halfLength: size.x / 2, halfWidth: size.y / 2, kind: .player, dynamic: true, entity: car)
        me.style = style
        physics.bodies.append(me)
        physics.sync(player)

        // Tracks, crossings and trains (after the player, who is body 0).
        railway.build(scene.root)

        // Parked cars along the kerbs.
        addParked(city.file.parked, to: scene.root)
        physics.rebuildGrid()

        // Traffic.
        traffic.spawnAll(count: 70, around: start.0)
        for d in traffic.drivers { scene.add(physics.bodies[d.body].entity) }
        physics.rebuildGrid()
        let crowd = Crowd(city: city, physics: physics)
        crowd.spawn(count: 110, around: start.0, into: scene.root)
        self.crowd = crowd
        let riders = Riders(city: city, physics: physics)
        riders.spawn([(.bike, 26), (.scooter, 16), (.hoverboard, 7), (.unicycle, 4), (.skateboard, 9), (.wheelboard, 6), (.rollerblades, 7)],
                      around: start.0, into: scene.root)
        self.riders = riders
        traffic.updateLamps(time: 0)
        cull()
        hud.pos = start.0
        hud.heading = start.1
        hud.area = city.neighbourhood(start.0)
        // The city drawn 150 m at a time round the car.
        scene.stream(tile: CityTiles.size, radius: CityTiles.radius, around: { [weak self] in
            guard let self, let p = self.physics?.bodies.first?.pos else { return .zero }
            return w3(p, 0)
        }, prepare: { tile in CityTiles.plan(tile) }, make: { tile, plan in CityTiles.make(tile, plan) })

        // The rest of the city's data loads round the car, ahead of being drawn.
        streamer = TileStreamer(city: city) { [weak self, weak scene] out, part in
            // Data a loader from an earlier build fetched belongs to that build's city: dropped.
            guard let self, self.city === city, let shops = self.shops else { return }
            let indices = shops.add(out.shops)
            self.city?.addShops(indices.filter { $0 < shops.all.count }.map { shops.all[$0].pos })
            self.hud.businesses = shops.markers
            self.refreshPlaces()
            self.nav.mapVersion += 1
            // More streets known: a trip still waiting for its way, or still loading along it, is worked out again.
            if self.nav.destination != nil && (self.nav.route == nil || self.streamer?.tripPending == true) { self.nav.reroute() }
            self.addParked(out.parked, to: scene?.root ?? Entity())
            let touched = CityTiles.add(part, shops: indices, of: city)
            // A square already drawn without this data is drawn again.
            if let scene, touched.contains(where: { scene.isBuilt(CityTiles.tile($0)) }) { scene.restream() }
        }
        // The loading screen stays until the scene shows the world: the first frames tick and the squares round
        // the car are drawn (`update`), so nothing half-made shows through.
        readyAt = CACurrentMediaTime()
        hud.status = "Drawing the streets…"
    }

    /// Parked cars at the kerb: each a body that sleeps until something hits it.
    func addParked(_ list: [[Float]], to root: Entity) {
        guard let physics else { return }
        for (k, p) in list.enumerated() {
            let seed = k * 31 + Int(abs(p[0]) * 7) + Int(abs(p[1]) * 3)
            let style = CarStyle.parked(seed)
            let e = CarFactory.make(style, color: style.paint(seed / 7))
            root.addChild(e)
            let size = CarFactory.size(style)
            let mass = style.handling.mass
            var body = Body(pos: SIMD2(p[0], p[1]), heading: p[2], mass: mass,
                            inertia: mass * (size.x * size.x + size.y * size.y) / 12,
                            halfLength: size.x / 2, halfWidth: size.y / 2, kind: .parked, dynamic: true,
                            asleep: true, entity: e)
            body.style = style
            physics.bodies.append(body)
            parked.append(physics.bodies.count - 1)
            physics.sync(physics.bodies.count - 1)
        }
    }

    /// On the street nearest the city's starting point (its centre unless it says otherwise), facing north along it,
    /// in the lane traffic drives in.
    private func startPoint(_ city: City) -> (SIMD2<Float>, Float) {
        let cfg = CityConfig.current
        let target = cfg.start.map { MapGeo.local(lat: $0.lat, lon: $0.lon) } ?? .zero
        var best: (SIMD2<Float>, Float, Float)?
        for e in city.edges where !e.isService && !e.name.isEmpty {
            for k in stride(from: Float(5), to: e.length - 5, by: 4) {
                var (p, dir) = e.sample(k)
                if dir.y < 0 && !e.oneway { dir = -dir }
                let d = simd_distance(p, target)
                if best == nil || d < best!.2 {
                    best = (p + perpRight(dir) * (e.oneway ? 0 : e.driveWidth / 4 * cfg.style.side), atan2(dir.x, dir.y), d)
                }
            }
        }
        return best.map { ($0.0, $0.1) } ?? (.zero, 0)
    }


    // MARK: Every frame

    /// Everything the big map can search for: businesses and streets.
    private func refreshPlaces() {
        guard let city, let shops else { return }
        nav.places = shops.all.map { Place(name: $0.data.n, detail: [$0.info.label, $0.data.a].compactMap { $0 }.joined(separator: " · "), pos: $0.pos) }
            + NavModel.streets(city)
    }

    /// Where the player is, for the F3 readout's triangle count.
    var playerPos: SIMD2<Float>? {
        guard let physics, player < physics.bodies.count else { return nil }
        return physics.bodies[player].pos
    }

    func update(_ scene: LampScene, _ dt: Float) {
        let frameStart = CACurrentMediaTime()
        Perf.shared.beginLaps(frameStart)
        defer { Perf.shared.lap("hud"); Perf.shared.frame(start: frameStart, game: self, scene: scene) }
        guard let physics, let traffic, let city, dt > 0 else { return }
        if !hud.loaded, let r = readyAt, CityTiles.made >= 6 || CACurrentMediaTime() - r > 12 {
            hud.loaded = true
            // Say what you've been given to drive.
            hud.toast = physics.bodies[player].style?.name
            toastUntil = scene.time + 3
        }
        // M opens the big map; the world waits while it's open.
        if scene.isDown(.m) && !mapHeld { nav.mapOpen = true }
        mapHeld = scene.isDown(.m)
        if scene.isDown(.t) && !travelHeld && hud.loaded { nav.travelOpen = true }
        travelHeld = scene.isDown(.t)
        if nav.travelOpen { Synth.shared.motor = false; return }
        if nav.mapOpen {
            // The map keeps loading while you plan, including the area the big map shows.
            streamer?.update(player: physics.bodies[player].pos, time: scene.time)
            let pending = streamer?.lookPending ?? false
            if nav.loadingMap != pending { nav.loadingMap = pending }
            Synth.shared.motor = false
            return
        }
        now = scene.time
        if let t = drivingTrain { driveTrain(t, scene, dt) }
        else if riding != nil { ride(scene, dt) } else if onFoot { walk(scene, dt) } else { drive(scene, dt) }
        engineSound(scene)
        Perf.shared.lap("drive")
        if hud.toast != nil && now > toastUntil { hud.toast = nil }
        // Cement mixers' drums keep turning.
        for b in physics.bodies where b.style == .cementMixer && b.entity.isEnabled { VehicleModels.spin(b.entity, by: dt * 1.6) }
        // Police, ambulance and fire truck lights take turns, four times a second.
        if now - lastFlash > 0.25 {
            lastFlash = now
            let phase = Int(now * 4) % 2 == 0
            for (i, b) in physics.bodies.enumerated() where b.style?.flashes == true && b.entity.isEnabled {
                // Yours flash only with the siren on.
                if i == player && !sirenOn { VehicleModels.flash(b.entity, phase: true); (b.entity.findEntity(named: "lightA") as? ModelEntity)?.model?.materials = [VehicleModels.lightOff] }
                else { VehicleModels.flash(b.entity, phase: phase) }
            }
        }
        railway?.update(dt, traffic: traffic)
        Perf.shared.lap("railway")
        streamer?.update(player: physics.bodies[player].pos, time: scene.time)
        Perf.shared.lap("streamer")
        traffic.update(dt, time: scene.time, player: physics.bodies[player].pos)
        Perf.shared.lap("traffic")
        crowd?.playerRiding = riding != nil
        riders?.playerRiding = riding != nil
        crowd?.update(dt, time: scene.time, player: player)
        Perf.shared.lap("crowd")
        riders?.update(dt, time: scene.time, player: player)
        Perf.shared.lap("riders")
        shops?.tick(time: scene.time)
        Perf.shared.lap("shops")
        let physicsStart = CACurrentMediaTime()
        physics.step(dt)
        Perf.shared.physics(CACurrentMediaTime() - physicsStart, physics.profile)
        crashEffects(dt)
        Perf.shared.lap("physics+fx")
        traffic.updateLamps(time: scene.time)
        Perf.shared.lap("lamps")

        // Moved cars' pictures.
        for i in physics.bodies.indices where physics.bodies[i].dynamic && !physics.bodies[i].asleep && i != player {
            physics.sync(i)
        }
        let b = physics.bodies[player]
        let vl = simd_dot(b.vel, b.right)
        physics.sync(player, roll: onFoot ? 0 : max(-0.06, min(0.06, vl * 0.012 + b.spin * simd_dot(b.vel, b.forward) * 0.004)))
        if !onFoot { vehicleControls(scene, dt) }

        if physics.playerImpact > 5 { shake = max(shake, min(0.7, physics.playerImpact / 25)) }
        shake *= exp(-dt * 5)
        if scene.isDown(.r) && !resetHeld { resetToRoad(city) }
        resetHeld = scene.isDown(.r)
        if scene.isDown(.f) && !switchHeld {
            if drivingTrain != nil { leaveTrain() }
            else if riding != nil { getOff() }
            else if onFoot, let t = railway?.locomotive(near: physics.bodies[player].pos, within: 10) { boardTrain(t) }
            else if onFoot {
                // Whichever is nearer: a car, a rider, or a ride left standing.
                let p = physics.bodies[player].pos
                let car = nearestCar(within: 4.5).map { ($0, simd_distance(physics.bodies[$0].pos, p)) }
                let ride = nearestRide(within: 3)
                if let c = car, ride == nil || c.1 <= ride!.1 { getIn(c.0) } else if ride != nil { mount() }
            } else if simd_length(b.vel) < 4 { getOut() }
        }
        switchHeld = scene.isDown(.f)
        camera(scene, dt)
        Perf.shared.lap("camera")

        if scene.time - lastCull > 0.5 { lastCull = scene.time; cull() }
        Perf.shared.lap("cull")
        if scene.time - lastHUD > 0.1 {
            lastHUD = scene.time
            let p = b.pos
            hud.speed = simd_length(b.vel) * CityConfig.current.style.speedFactor
            hud.pos = p
            hud.heading = camHeading ?? b.heading
            nav.track(p, heading: b.heading)
            if nav.arrived {
                nav.arrived = false
                hud.toast = "You've arrived"
                toastUntil = now + 2.5
            }
            hud.boost = boost
            hud.boosting = boosting
            if let road = city.nearestRoad(p, within: 30), road.distance < 18 {
                let name = city.edges[road.edge].name
                if name.isEmpty {
                    hud.street = city.edges[road.edge].isService ? "Alley" : ""
                } else if let number = city.houseNumber(near: p, on: name) {
                    hud.street = "\(number) \(name)"
                } else {
                    hud.street = name
                }
            }
            hud.area = city.neighbourhood(p)
            let passing = shops?.nearest(to: p)?.info
            if passing != hud.business { hud.business = passing }
            hud.traffic = traffic.drivers.map { physics.bodies[$0.body].pos }
            hud.trains = railway?.positions ?? []
            if physics.playerImpact > 6 { hud.crash = 1 } else { hud.crash *= 0.6 }
            var prompt: String?
            if drivingTrain != nil { prompt = "F  Leave the train     W  Throttle     S  Brake     E  Horn" }
            else if onFoot && riding == nil, railway?.locomotive(near: physics.bodies[player].pos, within: 10) != nil { prompt = "F  Drive the train" }
            else if riding != nil { prompt = "F  Get off" }
            else if onFoot {
                let p = physics.bodies[player].pos
                let car = nearestCar(within: 4.5).map { simd_distance(physics.bodies[$0].pos, p) }
                let ride = nearestRide(within: 3)
                if let c = car, ride == nil || c <= ride!.1 { prompt = "F  Get in" }
                else if let r = ride { prompt = "F  Ride the \(r.0.title)" }
            } else {
                var keys: [String] = []
                if simd_length(physics.bodies[player].vel) < 4 { keys.append("F  Get out") }
                keys.append("E  Horn")
                if let style = physics.bodies[player].style {
                    if style.flashes { keys.append(sirenOn ? "Q  Siren off" : "Q  Siren") }
                    if let g = style.actionName(on: actionOn) { keys.append("G  \(g)") }
                    if style == .monsterTruck { keys.append("Space  Hop") }
                }
                prompt = keys.joined(separator: "     ")
            }
            if prompt != hud.prompt { hud.prompt = prompt }
        }
    }

    private var boosting = false

    private func drive(_ scene: LampScene, _ dt: Float) {
        guard let physics else { return }
        var b = physics.bodies[player]
        // Sinking in water: no control, and after a few seconds you're fished out onto the nearest road.
        if b.ground < -0.4 {
            sunkFor += dt
            if sunkFor > 3.5, let city {
                sunkFor = 0
                resetToRoad(city)
                physics.bodies[player].ground = Heights.road
                hud.toast = "Sploosh. Fished out and back on the road."
                toastUntil = now + 3
                return
            }
        } else { sunkFor = 0 }
        // Tipped far over, in the air or under water, nothing you do reaches the road.
        let grounded = !b.flipped && b.lift < 0.15 && b.ground > -0.4
        let gas = grounded && (scene.isDown(.w) || scene.isDown(.up))
        let brake = grounded && (scene.isDown(.s) || scene.isDown(.down))
        let left = grounded && (scene.isDown(.a) || scene.isDown(.left))
        let right = grounded && (scene.isDown(.d) || scene.isDown(.right))
        let handbrake = scene.isDown(.space) && b.style != .monsterTruck
        let want: Float = (right ? 1 : 0) - (left ? 1 : 0)
        steer += (want - steer) * min(1, dt * (want == 0 ? 9 : 5))

        let f = b.forward, r = b.right
        var vf = simd_dot(b.vel, f), vl = simd_dot(b.vel, r)
        boosting = scene.isDown(.shift) && gas && boost > 0.02
        boost = boosting ? max(0, boost - dt * 0.2) : min(1, boost + dt * 0.07)
        let hd = b.style?.handling ?? .standard
        let top: Float = hd.top * (boosting ? 1.45 : 1)
        if gas {
            if vf < -0.5 { vf += 14 * dt } else { vf += hd.accel * (boosting ? 1.9 : 1) * max(0, 1 - vf / top) * dt }
        } else if brake {
            if vf > 0.5 { vf -= 17 * dt } else { vf -= 6 * max(0, 1 + vf / 14) * dt }
        } else {
            let drag = (1.3 + 0.001 * vf * vf) * dt
            vf = vf > 0 ? max(0, vf - drag) : min(0, vf + drag)
        }
        if handbrake { vf = vf > 0 ? max(0, vf - 7 * dt) : min(0, vf + 7 * dt) }

        let maxSteer: Float = 0.6 * hd.steer / (1 + abs(vf) / 15)
        var yaw = vf * tan(steer * maxSteer) / 2.7
        if handbrake { yaw *= 1.6 }
        if grounded {
            b.spin += (yaw - b.spin) * min(1, dt * (handbrake ? 3 : 9))
            vl *= exp(-dt * (handbrake ? 1.6 : hd.grip))
        } else if b.flipped {
            // Sliding on its side or roof.
            vf = vf > 0 ? max(0, vf - 9 * dt) : min(0, vf + 9 * dt)
            vl = vl > 0 ? max(0, vl - 9 * dt) : min(0, vl + 9 * dt)
            b.spin *= exp(-2 * dt)
        }
        b.vel = f * vf + r * vl
        let braking = brake && vf > 0.5 || handbrake
        // The rear lights are looked up each time: a live change to the car's model replaces them.
        let rear = b.entity.findEntity(named: "rear") as? ModelEntity
        let rearID = rear.map { ObjectIdentifier($0) }
        if braking != b.braking || rearID != lastRear {
            b.braking = braking
            lastRear = rearID
            rear?.model?.materials = [braking ? CarFactory.brakeLight : CarFactory.taillight]
        }
        physics.bodies[player] = b
    }

    /// A car close enough to jump into, while slow: a parked one or one in traffic (not a train).
    private func nearestCar(within reach: Float = 6.5) -> Int? {
        guard let physics else { return nil }
        let me = physics.bodies[player]
        var best: (Int, Float)?
        physics.query(me.pos, 7) { j in
            let b = physics.bodies[j]
            guard j != self.player, b.kind == .traffic || b.kind == .parked, b.entity.isEnabled else { return }
            let d = simd_distance(b.pos, me.pos)
            if d < reach && (best == nil || d < best!.1) { best = (j, d) }
        }
        return best?.0
    }

    // MARK: On foot

    // MARK: Riding

    /// The nearest bike, scooter or board you could ride: someone's, or one left standing. Its kind and distance.
    private func nearestRide(within r: Float) -> (RideKind, Float)? {
        guard let physics else { return nil }
        let p = physics.bodies[player].pos
        var best: (RideKind, Float)?
        if let rider = riders?.nearest(to: p, within: r) { best = (rider.kind, rider.distance) }
        for parkedRide in parkedRides {
            let d = simd_distance(parkedRide.pos, p)
            if d < r && (best == nil || d < best!.1) { best = (parkedRide.kind, d) }
        }
        return best
    }

    /// On to the nearest ride: a rider is knocked off and hurries away; one left standing is picked up.
    // MARK: Vehicle controls

    /// E horn, Q siren on emergency vehicles, G each vehicle's own trick, Space hops a monster truck.
    private func vehicleControls(_ scene: LampScene, _ dt: Float) {
        guard let physics else { return }
        let b = physics.bodies[player]
        let style = b.style
        let synth = Synth.shared
        let horn = scene.isDown(.e)
        if horn && !synth.horn { synth.start() }
        synth.horn = horn
        if horn { crowd?.scare(from: b.pos, toward: b.forward); riders?.honk(from: b.pos) }
        if scene.isDown(.q) && !qHeld, style?.flashes == true {
            sirenOn.toggle()
            synth.start()
            synth.siren = sirenOn
        }
        qHeld = scene.isDown(.q)
        // Traffic ahead pulls over for the siren.
        traffic?.siren = sirenOn ? (b.pos, b.forward) : nil
        if scene.isDown(.g) && !gHeld, let style, style.actionName(on: actionOn) != nil {
            actionOn.toggle()
            switch style {
            case .iceCream: synth.playTune(); actionOn = false
            case .taxi: VehicleModels.sign(b.entity, on: !actionOn)
            default: break
            }
        }
        gHeld = scene.isDown(.g)
        if let style, VehicleModels.hinge(style) != nil {
            let goal: Float = actionOn ? 1 : 0
            if actionAmount != goal {
                actionAmount += max(-dt * 0.5, min(dt * 0.5, goal - actionAmount))
                VehicleModels.move(b.entity, style: style, amount: actionAmount)
            }
        }
        // The mixer pours: its drum runs backwards, fast.
        if style == .cementMixer && actionOn { VehicleModels.spin(b.entity, by: -dt * 6) }
        if style == .monsterTruck {
            if scene.isDown(.space) && hopY == 0 && hopV == 0 { hopV = 6.5 }
            if hopY > 0 || hopV > 0 {
                hopV -= 14 * dt
                hopY = max(0, hopY + hopV * dt)
                if hopY == 0 { hopV = 0; shake = max(shake, 0.4) }
            }
            b.entity.position.y += hopY
        }
    }

    // MARK: Trains

    /// Up into the locomotive's cab: you drive the whole train along its line.
    private func boardTrain(_ t: Int) {
        guard let physics, let railway, let w = walker else { return }
        leaveVehicle()
        let loco = physics.bodies[railway.locomotiveBody(t)]
        let parent = w.root.parent
        w.root.removeFromParent()
        let ghost = Entity()
        parent?.addChild(ghost)
        // You, in the cab: a stand-in that rides with the locomotive (the train itself does the colliding).
        physics.bodies[player] = Body(pos: loco.pos, heading: loco.heading, mass: 80, inertia: 6, halfLength: 10, halfWidth: 1.5,
                                      kind: .player, dynamic: false, entity: ghost)
        railway.setDriven(t, true)
        drivingTrain = t
        onFoot = false
        camHeading = loco.heading
        hud.toast = railway.lines[railway.trains[t].line].trainName
        toastUntil = now + 2.5
    }

    /// Down from the cab beside the track; the train carries on by itself.
    private func leaveTrain() {
        guard let physics, let railway, let t = drivingTrain, let w = walker else { return }
        leaveVehicle()
        railway.setDriven(t, false)
        drivingTrain = nil
        let loco = physics.bodies[railway.locomotiveBody(t)]
        let ghost = physics.bodies[player].entity
        ghost.parent?.addChild(w.root)
        ghost.removeFromParent()
        physics.bodies[player] = Body(pos: loco.pos + loco.right * 3.5, heading: loco.heading, mass: 80, inertia: 6,
                                      halfLength: 0.3, halfWidth: 0.3, kind: .player, dynamic: true, entity: w.root)
        physics.sync(player)
        onFoot = true
    }

    /// W opens the throttle, S brakes and then backs up.
    private func driveTrain(_ t: Int, _ scene: LampScene, _ dt: Float) {
        guard let physics, let railway else { return }
        let input: Float = (scene.isDown(.w) || scene.isDown(.up) ? 1 : 0) - (scene.isDown(.s) || scene.isDown(.down) ? 1 : 0)
        railway.throttle(t, input, dt)
        let loco = physics.bodies[railway.locomotiveBody(t)]
        physics.bodies[player].pos = loco.pos
        physics.bodies[player].heading = loco.heading
        physics.bodies[player].vel = loco.vel
    }

    /// The engine note for whatever you're driving, following speed, gear and throttle.
    private func engineSound(_ scene: LampScene) {
        guard let physics else { return }
        let synth = Synth.shared
        let b = physics.bodies[player]
        let speed = simd_length(b.vel)
        let gas = scene.isDown(.w) || scene.isDown(.up)
        if let t = drivingTrain, let railway {
            if !synth.motor { synth.start() }
            synth.motor = true
            synth.motorPitch = 0.42
            synth.motorRPM = Double(min(1, 0.15 + abs(railway.speed(t)) / 30))
            synth.motorLoad = gas ? 1 : 0.3
            return
        }
        guard !onFoot, riding == nil else { synth.motor = false; return }
        if !synth.motor { synth.start() }
        synth.motor = true
        // Gears: the revs climb through each band of speed, then drop as it shifts up.
        let bands: [Float] = [0, 7, 14, 23, 34, 48, 200]
        var rpm: Float = 0.12
        for g in 0..<(bands.count - 1) where speed >= bands[g] && speed < bands[g + 1] {
            rpm = 0.25 + 0.75 * (speed - bands[g]) / (bands[g + 1] - bands[g])
            if g == 0 { rpm = 0.12 + 0.88 * speed / bands[1] }
        }
        synth.motorRPM = Double(rpm)
        synth.motorLoad = gas ? 1 : 0.25
        synth.motorPitch = b.style?.enginePitch ?? 1
    }

    /// Everything a vehicle was doing stops when you leave it.
    private func leaveVehicle() {
        sirenOn = false
        actionOn = false
        actionAmount = 0
        hopY = 0; hopV = 0
        Synth.shared.siren = false
        Synth.shared.horn = false
        traffic?.siren = nil
    }

    private func mount() {
        guard let physics, let me = Optional(physics.bodies[player]), let parent = me.entity.parent else { return }
        let p = me.pos
        var kind: RideKind?
        var heading = me.heading
        let standing = parkedRides.enumerated().min { simd_distance($0.element.pos, p) < simd_distance($1.element.pos, p) }
        let rider = riders?.nearest(to: p, within: 3)
        if let r = rider, standing == nil || r.distance <= simd_distance(standing!.element.pos, p) {
            if let taken = riders?.take(r.index) {
                kind = taken.kind
                heading = taken.heading
                crowd?.addDriver(at: taken.pos + perpRight(forwardOf(taken.heading)) * 1.2, heading: taken.heading + .pi, into: parent)
            }
        } else if let s = standing, simd_distance(s.element.pos, p) < 3 {
            kind = s.element.kind
            s.element.entity.removeFromParent()
            parkedRides.remove(at: s.offset)
        }
        guard let kind else { return }
        let (root, _, figure, legs, arms) = Riders.makeRider(kind, look: playerLook)
        parent.addChild(root)
        me.entity.removeFromParent()
        rig = (root, figure, legs, arms)
        riding = kind
        jumpY = 0; jumpV = 0
        physics.bodies[player] = Body(pos: p, heading: heading, mass: 110, inertia: 20,
                                      halfLength: kind == .bike ? 0.85 : 0.5, halfWidth: 0.35, kind: .player, dynamic: true, entity: root)
        physics.sync(player)
        camHeading = heading
        hud.toast = kind.title.capitalized
        toastUntil = now + 2
    }

    /// Off again, on foot; the ride stays standing where you left it.
    private func getOff() {
        guard let physics, let kind = riding, let r = rig, let w = walker else { riding = nil; return }
        let me = physics.bodies[player]
        if kind != .rollerblades, let machine = r.root.children.first?.children.first {
            machine.removeFromParent()
            machine.transform = Transform(rotation: simd_quatf(angle: -me.heading, axis: [0, 1, 0]),
                                          translation: w3(me.pos, kind == .bike ? Heights.road : Heights.sidewalk))
            r.root.parent?.addChild(machine)
            parkedRides.append((machine, kind, me.pos))
        }
        r.root.parent?.addChild(w.root)
        r.root.removeFromParent()
        rig = nil
        riding = nil
        physics.bodies[player] = Body(pos: me.pos + perpRight(me.forward) * -0.8, heading: me.heading, mass: 80, inertia: 6,
                                      halfLength: 0.3, halfWidth: 0.3, kind: .player, dynamic: true, entity: w.root)
        physics.sync(player)
    }

    /// Riding: W faster, S slower and back, A and D steer.
    private func ride(_ scene: LampScene, _ dt: Float) {
        guard let physics, let kind = riding, let r = rig else { return }
        var b = physics.bodies[player]
        let top = kind.playerTop
        let vf = simd_dot(b.vel, b.forward)
        let gas = scene.isDown(.w) || scene.isDown(.up), back = scene.isDown(.s) || scene.isDown(.down)
        let want: Float = gas ? top : (back ? -1.5 : 0)
        let next = vf + max(-7 * dt, min(kind.playerAccel * dt, want - vf))
        let turn: Float = (scene.isDown(.d) || scene.isDown(.right) ? 1 : 0) - (scene.isDown(.a) || scene.isDown(.left) ? 1 : 0)
        b.heading += turn * 2.4 * min(1, 0.35 + abs(next) / 4) / (1 + abs(next) / 12) * dt * (next < 0 ? -1 : 1)
        b.spin = 0
        b.vel = b.forward * next
        physics.bodies[player] = b
        ridePhase += abs(next) * dt * kind.cadence
        Riders.pose(r.figure, r.legs, r.arms, kind: kind, phase: ridePhase)
    }

    /// Out of the car on the driver's side; the car stays where it is, parked.
    private func getOut() {
        leaveVehicle()
        guard let physics else { return }
        let car = physics.bodies[player]
        if walker == nil {
            let (root, figure, legs, arms) = Crowd.makePerson(playerLook)
            walker = (root, figure, legs, arms)
        }
        guard let w = walker else { return }
        var left = car
        left.kind = .parked
        left.asleep = false
        left.braking = false
        left.vel *= 0.5
        (left.entity.findEntity(named: "rear") as? ModelEntity)?.model?.materials = [CarFactory.taillight]
        let slot: Int
        if let s = spareSlots.popLast() { slot = s; physics.bodies[s] = left } else { physics.bodies.append(left); slot = physics.bodies.count - 1 }
        parked.append(slot)
        physics.sync(slot)
        car.entity.parent?.addChild(w.root)
        physics.bodies[player] = Body(pos: car.pos - car.right * 1.9, heading: car.heading, mass: 80, inertia: 6,
                                      halfLength: 0.3, halfWidth: 0.3, kind: .player, dynamic: true, entity: w.root)
        physics.sync(player)
        onFoot = true
        lastRear = nil
        physics.rebuildGrid()
    }

    /// Into a parked or traffic car; a car taken from traffic loses its driver.
    private func getIn(_ j: Int) {
        leaveVehicle()
        guard let physics, let traffic else { return }
        var car = physics.bodies[j]
        if let d = traffic.drivers.firstIndex(where: { $0.body == j }) {
            traffic.removeDriver(d)
            // The driver gets out on their side and runs off.
            if let parent = physics.bodies[player].entity.parent {
                crowd?.addDriver(at: car.pos - car.right * (car.halfWidth + 0.7), heading: car.heading, into: parent)
            }
        }
        parked.removeAll { $0 == j }
        hud.toast = car.style?.name ?? "Car"
        toastUntil = now + 2.5
        car.kind = .player
        car.dynamic = true
        car.asleep = false
        car.restTime = 0
        car.vel = .zero
        car.spin = 0
        physics.bodies[player].entity.removeFromParent()
        physics.bodies[player] = car
        // The slot the car came from waits, empty and far away, for the next car you leave.
        physics.bodies[j] = Body(pos: SIMD2(90000, 90000), heading: 0, kind: .parked, dynamic: false, asleep: true, entity: Entity())
        spareSlots.append(j)
        physics.sync(player)
        onFoot = false
        lastRear = nil
        camHeading = car.heading
        physics.rebuildGrid()
    }

    /// Walking: W forward (Shift to run), S back, A and D turn.
    private func walk(_ scene: LampScene, _ dt: Float) {
        guard let physics, let w = walker else { return }
        var b = physics.bodies[player]
        let turn: Float = (scene.isDown(.d) || scene.isDown(.right) ? 1 : 0) - (scene.isDown(.a) || scene.isDown(.left) ? 1 : 0)
        b.heading += turn * 2.8 * dt
        b.spin = 0
        let gas = scene.isDown(.w) || scene.isDown(.up), back = scene.isDown(.s) || scene.isDown(.down)
        let want: Float = gas ? (scene.isDown(.shift) ? 6 : 2.3) : (back ? -1.4 : 0)
        let vf = simd_dot(b.vel, b.forward)
        let next = vf + max(-14 * dt, min(14 * dt, want - vf))
        b.vel = b.forward * next
        physics.bodies[player] = b
        walkPhase += abs(next) * dt * 3.4
        let swing = sin(walkPhase) * min(1, abs(next) / 2) * (abs(next) > 3 ? 0.9 : 0.55)
        w.legs[0].orientation = simd_quatf(angle: swing, axis: [1, 0, 0])
        w.legs[1].orientation = simd_quatf(angle: -swing, axis: [1, 0, 0])
        w.arms[0].orientation = simd_quatf(angle: -swing * 0.8, axis: [1, 0, 0])
        w.arms[1].orientation = simd_quatf(angle: swing * 0.8, axis: [1, 0, 0])
        // Space jumps.
        if scene.isDown(.space) && jumpY == 0 && jumpV == 0 { jumpV = 4.6 }
        if jumpY > 0 || jumpV > 0 {
            jumpV -= 13 * dt
            jumpY += jumpV * dt
            if jumpY <= 0 { jumpY = 0; jumpV = 0 }
        }
        w.figure.position = [0, 0.9 + jumpY + abs(cos(walkPhase)) * 0.03 * min(1, abs(next)), 0]
        if jumpY > 0 {
            w.legs[0].orientation = simd_quatf(angle: 0.6, axis: [1, 0, 0])
            w.legs[1].orientation = simd_quatf(angle: -0.25, axis: [1, 0, 0])
            w.arms[0].orientation = simd_quatf(angle: -2.6, axis: [1, 0, 0])
            w.arms[1].orientation = simd_quatf(angle: -2.6, axis: [1, 0, 0])
        }
        w.figure.orientation = simd_quatf(angle: abs(next) > 3 ? -0.15 : 0, axis: [1, 0, 0])
    }

    /// A crunch for each hard hit (no flying debris).
    private func crashEffects(_ dt: Float) {
        guard let physics, let fx else { return }
        let me = physics.bodies[player].pos
        for c in physics.crashes.prefix(4) {
            let d = simd_distance(c.pos, me)
            if d < 70 { Synth.shared.crash(min(1, c.strength / 16) * (1 - d / 70)) }
        }
        // Trees knocked down: a stump left, the tree going over, leaves flying, a crack, and a crash when it lands.
        for t in physics.felled {
            let d = simd_distance(t.pos, me)
            if t.kind == 3 {
                // A hydrant: knocked flying, and water shooting up from the pipe.
                CityTiles.knockHydrant(t.pos)
                geysers?.start(at: t.pos, toward: t.dir, speed: t.speed)
                if d < 80 { Synth.shared.clang(0.7 * (1 - d / 80)) }
                continue
            }
            if t.kind == 4 {
                // A street lamp: bent over at its foot with a clang.
                if let e = CityTiles.knockLamp(t.pos) {
                    treeFall?.topple(e, at: t.pos, toward: t.dir, speed: t.speed, height: 7.2)
                }
                if d < 80 { Synth.shared.clang(1 - d / 80) }
                continue
            }
            if t.kind > 0 {
                // A street sign or signal pole: bent over at its foot with a clang.
                if let e = CityTiles.knockOver(t.pos) {
                    treeFall?.topple(e, at: t.pos, toward: t.dir, speed: t.speed, height: t.kind == 1 ? 3.6 : 6.2)
                }
                if d < 80 { Synth.shared.clang(1 - d / 80) }
                continue
            }
            if let look = CityTiles.fell(t.pos) {
                treeFall?.fell(at: t.pos, toward: t.dir, speed: t.speed, variant: look.variant, scale: look.scale)
            }
            fx.leaves(at: w3(t.pos, Heights.ground + 3.5 * t.scale), count: 14, spread: 1.2 * t.scale)
            if d < 80 { Synth.shared.crack(1 - d / 80) }
        }
        physics.felled.removeAll()
        // Spraying hydrants: drops, the flying hydrant, and a hiss that's louder close by.
        let spray = geysers?.update(dt, near: me) ?? 0
        Synth.shared.spray = Double(spray)
        for l in treeFall?.update(dt) ?? [] {
            let d = simd_distance(l.pos, me)
            if l.metal {
                if d < 80 { Synth.shared.clang(0.6 * l.strength * (1 - d / 80)) }
                continue
            }
            fx.leaves(at: w3(l.pos, Heights.ground + 1), count: 10, spread: 1.8)
            if d < 80 { Synth.shared.thud(l.strength * (1 - d / 80)) }
        }
        // Smaller knocks: scrapes and bumps the player takes, a little apart so a long scrape doesn't drone.
        let impact = physics.playerImpact
        if impact > 1.2 && now - lastThud > 0.18 && physics.crashes.isEmpty {
            lastThud = now
            Synth.shared.thud(min(0.8, impact / 8))
        }
        // People hit by anything nearby.
        for p in (crowd?.hits ?? []) + (riders?.hits ?? []) {
            let d = simd_distance(p, me)
            if d < 60 { Synth.shared.oof(1 - d / 60) }
        }
        crowd?.hits.removeAll()
        riders?.hits.removeAll()
        fx.update(dt)
    }

    /// Back onto the nearest street, pointing along it.
    private func resetToRoad(_ city: City) {
        guard let physics else { return }
        let p = physics.bodies[player].pos
        guard let road = city.nearestRoad(p, within: 120) else { return }
        let e = city.edges[road.edge]
        var bestS: Float = 0, bestD = Float.infinity
        for s in stride(from: Float(0), through: e.length, by: 2) {
            let d = simd_distance(e.sample(s).0, p)
            if d < bestD { bestD = d; bestS = s }
        }
        var (q, dir) = e.sample(bestS)
        if simd_dot(dir, physics.bodies[player].forward) < 0 && !e.oneway { dir = -dir }
        physics.bodies[player].pos = q + perpRight(dir) * (e.oneway ? 0 : e.driveWidth / 4 * CityConfig.current.style.side)
        physics.bodies[player].heading = atan2(dir.x, dir.y)
        physics.bodies[player].vel = .zero
        physics.bodies[player].spin = 0
        physics.rightSideUp(player)
    }

    /// Parked cars far away are hidden, and left out of collisions.
    private func cull() {
        guard let physics else { return }
        let p = physics.bodies[player].pos
        CityTiles.showDetail(around: p)
        for i in parked {
            let near = simd_distance(physics.bodies[i].pos, p) < 280
            if physics.bodies[i].entity.isEnabled != near { physics.bodies[i].entity.isEnabled = near }
        }
    }

    // MARK: Camera

    private func camera(_ scene: LampScene, _ dt: Float) {
        guard let physics else { return }
        let b = physics.bodies[player]
        let speed = simd_length(b.vel)
        let vf = simd_dot(b.vel, b.forward)
        var goalHeading = b.heading
        // Follow the way the car is going when it slides, not just the way it points.
        if vf > 4 { let mv = atan2(b.vel.x, b.vel.y); goalHeading = b.heading + angle(mv - b.heading) * 0.5 }
        var h = camHeading ?? goalHeading
        h += angle(goalHeading - h) * min(1, dt * 3.2)
        camHeading = h
        let f = forwardOf(h)
        let big = max(0, b.halfLength - 2.3)       // trucks and buses: further back and higher
        let dist: Float = riding != nil ? 5 : (onFoot ? 4.2 : 7.2 + big * 1.3 + min(speed, 60) * 0.045)
        let height: Float = riding != nil ? 2.2 : (onFoot ? 1.9 : 2.7 + big * 0.5 + min(speed, 60) * 0.012)
        let car3 = w3(b.pos, Heights.road)
        var goal2 = b.pos - f * dist
        let hit = physics.firstWall(from: b.pos, to: goal2)
        if hit < 1 { goal2 = b.pos + (goal2 - b.pos) * max(0.25, hit - 0.08) }
        let goal = w3(goal2, Heights.road + height + (hit < 1 ? 1.2 : 0))
        var pos = camPos ?? goal
        pos += (goal - pos) * (1 - exp(-dt * 10))
        camPos = pos
        var jitter = SIMD3<Float>(0, 0, 0)
        if shake > 0.01 {
            jitter = SIMD3(Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -1...1)) * shake * 0.25
        }
        let look = car3 + w3(f * (onFoot ? 2 : 3.5), onFoot ? 1.4 : 1.3)
        scene.camera.look(at: look, from: pos + jitter, relativeTo: nil)
        let wantFov: Float = boosting ? 74 : 62 + min(speed, 40) * 0.12
        fov += (wantFov - fov) * min(1, dt * 3)
        scene.camera.camera.fieldOfViewInDegrees = fov
    }

    private func angle(_ a: Float) -> Float {
        var a = a
        while a > .pi { a -= 2 * .pi }
        while a < -.pi { a += 2 * .pi }
        return a
    }
}

struct ContentView: View {
    @State private var game = Game()

    var body: some View {
        GameScreen(game: game, hud: game.hud)
            .frame(minWidth: 960, minHeight: 620)
    }
}

/// The scene and the HUD over it; the scene is made anew whenever the game travels somewhere else.
struct GameScreen: View {
    let game: Game
    @ObservedObject var hud: HUDModel

    var body: some View {
        ZStack {
            LampSceneView(sky: DayTime.sky, camera: .manual, props: Game.props) { scene in
                await game.build(scene)
            } update: { scene, dt in
                game.update(scene, dt)
            }
            .id(hud.place)
            HUDView(model: game.hud, nav: game.nav)
        }
    }
}
