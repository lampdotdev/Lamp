import Foundation

extension Template {
    /// Where Lamp writes LampScene.swift in a Mac app whose code builds a 3D scene, and its name.
    static let sceneSupportFile = "LampScene.swift"
    static let sceneSupportPath = "Sources/" + sceneSupportFile

    /// Whether a Mac app builds a 3D scene: some Swift of its own in Sources/ imports RealityKit. Asked before
    /// every build, as `hasWidget` is, so the first such import brings LampScene and the last one takes it away.
    /// Such an app needs macOS 15, where RealityView begins.
    static func usesScene(_ project: LampProject) -> Bool {
        guard project.platform == .mac else { return false }
        let sources = project.dir.appendingPathComponent("Sources")
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
        return files.contains { file in
            file.pathExtension == "swift" && !["LampSupport.swift", sceneSupportFile].contains(file.lastPathComponent)
                && ((try? String(contentsOf: file, encoding: .utf8))?.range(of: #"(?m)^\s*(@\w+\s+)?import\s+RealityKit\b"#, options: .regularExpression) != nil)
        }
    }

    /// LampScene.swift, written like LampSupport.swift (before every turn and build) for an app that uses it,
    /// and taken away from one that no longer does, so nothing builds against a stale copy.
    static func writeSceneSupport(for project: LampProject) throws {
        let url = project.dir.appendingPathComponent(sceneSupportPath)
        guard usesScene(project) else {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            return
        }
        let contents = lampSceneSwift
            .replacingOccurrences(of: "{{SLUG}}", with: project.id)
            .replacingOccurrences(of: "{{NOTE}}", with: Edition.notificationPrefix)
        if (try? String(contentsOf: url, encoding: .utf8)) != contents {
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// The oldest macOS a Mac app runs on: 15 with a 3D scene (RealityView begins there), else 14. Whatever compiles
    /// the app's code outside its own build (live reload's checks and libraries) targets this, as the build does.
    static func macMinimum(_ project: LampProject) -> String { usesScene(project) ? "15.0" : "14.0" }

    /// Package.swift and build.sh for a Mac app with a 3D scene: macOS 15 at least, as RealityView needs.
    static func withScene(_ template: String, for project: LampProject) -> String {
        guard usesScene(project) else { return template }
        precondition(template.contains(".macOS(.v14)") || template.contains("<string>14.0</string>"), "the Mac template changed")
        return template
            .replacingOccurrences(of: ".macOS(.v14)", with: #".macOS("15.0")"#)
            .replacingOccurrences(of: "<key>LSMinimumSystemVersion</key><string>14.0</string>",
                                  with: "<key>LSMinimumSystemVersion</key><string>15.0</string>")
    }

    /// The building blocks for 3D scenes (RealityKit), written into a Mac app that imports RealityKit. Its own
    /// header says what's in it; the agent's rule (`Agent.Rules.scene3D`) says how to use it.
    static let lampSceneSwift = #"""
    // LampScene.swift: Lamp's building blocks for 3D scenes in RealityKit. Lamp writes this file into an app whose
    // code imports RealityKit and rewrites it before every build, so changes made here are lost.
    //
    //  LampSceneView(sky: .day, camera: .orbit(), props: Props.all) { scene in
    //      scene.add(ModelEntity(mesh: LampMesh.box([1, 1, 1], corner: 0.05), materials: [LampMaterial.paint(.systemRed)]))
    //  } update: { scene, dt in ... }
    //
    //  Shapes: LampMesh.box, sphere, cylinder, cone, lathe, extrude, sweep, tube, plane, text.
    //  Materials: LampMaterial.metal, chrome, brushed, plastic, rubber, glass, paint, wood, fabric, ceramic,
    //             concrete, asphalt, brick, tiles, grass, glow.
    //  Parts: entity.lampPress { }, lampTurn(axis:range:), lampSlide(axis:range:), lampGrab(), lampPhysics(), lampShadow().
    //  Many copies of one thing: LampScene.copies(of:at:). A big world: scene.stream(tile:radius:) { tile in … }.
    //  Props: a dictionary of name to a function making the prop; `scene.place(name, at:)` puts one in the scene.

    import SwiftUI
    import RealityKit
    import AppKit

    // MARK: - The view

    /// A 3D scene that fills its space: a sky that lights it, a camera rig, the keyboard and mouse, and a function
    /// called every frame. Build the scene in `build`, add to `scene.root` (or `scene.add`), move things in `update`.
    struct LampSceneView: View {
        var sky: LampSky = .day
        var camera: LampCameraRig = .orbit()
        /// Named props, each a function making a fresh one. Lamp's builder looks at one of them on its own.
        var props: [String: @MainActor () -> Entity] = [:]
        var build: @MainActor (LampScene) async -> Void
        var update: (@MainActor (LampScene, Float) -> Void)? = nil
        /// Runs after Lamp puts a code change into the open app: redraw here what the app built itself and wants to
        /// show the new code (its own tiles, a level's scenery), keeping the game's state. Call named functions, as
        /// a closure written out in place keeps the code it was made with.
        var onLiveChange: (@MainActor (LampScene) -> Void)? = nil

        @State private var scene = LampScene()
        @State private var studio: String?
        /// Whether the scene has keyboard focus: it does when it appears and when it's clicked, and loses it when
        /// Tab or a click gives another control focus, whose keys are then its own.
        @FocusState private var focused: Bool

        var body: some View {
            GeometryReader { geometry in
                RealityView { content in
                    await scene.start(&content, sky: sky, rig: camera, props: props, build: build, update: update)
                }
                .realityViewCameraControls(.none)
                .focusable()
                .focusEffectDisabled()
                .focused($focused)
                .onChange(of: focused) { _, now in scene.hasFocus = now }
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged {
                        if !focused { focused = true }
                        scene.hasFocus = true
                        scene.dragChanged(from: $0.startLocation, to: $0.location)
                    }
                    .onEnded { scene.dragEnded(from: $0.startLocation, to: $0.location) })
                .background(LampSceneWindow { view in
                    scene.window = view?.window
                    scene.marker = view
                })
                .onAppear {
                    scene.viewSize = geometry.size
                    focused = true
                }
                #if LAMP_LIVE
                // A change Lamp put into the open app replaces functions, but the scene is updated every frame by the
                // closure it was first given, which still runs the old code: it takes this view's, so a changed game
                // rule shows at once, and remakes each prop in place. Building the whole scene again would cost a big
                // world seconds of a stalled app and reset it, so a change to the rest shows at the next launch.
                .onChange(of: LampLive.generation) { _, _ in
                    scene.refresh(update: update, props: props)
                    onLiveChange?(scene)
                }
                #endif
                .onChange(of: geometry.size) { _, size in scene.viewSize = size }
            }
            .overlay {
                if let studio, let make = props[studio] {
                    LampPropStudio(name: studio, make: make).transition(.opacity)
                }
            }
            .onReceive(DistributedNotificationCenter.default().publisher(for: LampScene.propRequest)) { note in
                let name = note.userInfo?["name"] as? String ?? ""
                if props[name] == nil {
                    LampScene.answerProp(name.isEmpty ? "" : "There's no prop named \(name). The props are: "
                                         + props.keys.sorted().joined(separator: ", ") + ".")
                    return
                }
                studio = name
                // The pictures, once the four views have drawn; then the scene again.
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.6))
                    LampRuntime.snapshot()
                    LampScene.answerProp("shown")
                    try? await Task.sleep(for: .seconds(0.6))
                    if studio == name { studio = nil }
                }
            }
        }
    }

    // MARK: - The scene

    /// What `build` and `update` work with: the root to add to, the camera, the keys held and the mouse.
    @MainActor
    final class LampScene {
        let root = Entity()
        let camera = PerspectiveCamera()
        var rig: LampCameraRig = .orbit()
        /// Seconds since the scene started.
        private(set) var time: Float = 0
        var viewSize = CGSize(width: 800, height: 600)

        private var keys = Set<UInt16>()
        /// The window the scene is drawn in: only its keys are the scene's.
        weak var window: NSWindow?
        /// A view drawn with the scene, to tell where in the window keyboard focus really is.
        weak var marker: NSView?
        /// Whether the scene has keyboard focus (see `LampSceneView.focused`).
        var hasFocus = false
        private var subscription: EventSubscription?
        private var monitor: Any?
        private var update: ((LampScene, Float) -> Void)?
        private var drag: Drag?
        private var orbitYaw: Float = 0.6, orbitPitch: Float = 0.35, orbitDistance: Float = 4
        private var lookYaw: Float = 0, lookPitch: Float = 0
        private var chaseHeading: Float?
        private var chasePosition: SIMD3<Float>?

        nonisolated init() {}

        func add(_ entity: Entity) { root.addChild(entity) }

        /// The view's props, by name: what `place` makes.
        private(set) var props: [String: @MainActor () -> Entity] = [:]

        /// Puts a new copy of the prop with this name in the scene (or in `parent`), at a point and turned to a
        /// heading in radians, and hands it back for the app to keep and move. Placed this way, it carries the
        /// prop's name, so a change to the prop's code shows in the open app. Nil when there's no such prop.
        @discardableResult
        func place(_ name: String, at position: SIMD3<Float> = .zero, heading: Float = 0, in parent: Entity? = nil) -> Entity? {
            guard let make = props[name] else {
                print("LampScene: there's no prop named \(name). The props are: \(props.keys.sorted().joined(separator: ", ")).")
                return nil
            }
            let entity = make()
            entity.name = name
            entity.position = position
            entity.orientation = simd_quatf(angle: heading, axis: [0, 1, 0])
            // A prop that turns or slides as a whole measures that from where it's placed, not where it was made.
            if var part = entity.components[LampPart.self] {
                part.rest = entity.orientation
                part.restPosition = entity.position
                entity.components.set(part)
            }
            (parent ?? root).addChild(entity)
            return entity
        }

        /// After a live change: the frame loop runs the new code, and every entity named after a prop is made of
        /// what the new code makes (see LampSceneView's live reload).
        func refresh(update: ((LampScene, Float) -> Void)?, props: [String: @MainActor () -> Entity]) {
            self.update = update
            self.props = props
            restream()
            for (name, make) in props {
                var found: [Entity] = []
                func visit(_ e: Entity) {
                    if e.name == name { found.append(e); return }
                    for child in e.children { visit(child) }
                }
                visit(root)
                // The entity itself stays (the app's code holds it, and moves it); what it's made of is the new code's.
                for old in found {
                    // A prop whose own handlers (a press action, a change handler) may refer to it or its parts is left
                    // as it is: they'd go on acting on what the refresh replaces. It's made anew at the next launch.
                    func handles(_ e: Entity) -> Bool {
                        guard let part = e.components[LampPart.self] else { return false }
                        if case .press = part.kind { return true }
                        return part.changed != nil
                    }
                    if handles(old) { continue }
                    let fresh = make()
                    if handles(fresh) { continue }
                    for child in Array(old.children) { child.removeFromParent() }
                    for child in Array(fresh.children) { old.addChild(child, preservingWorldTransform: false) }
                    // What the prop's code sets on the entity itself goes over too: its look, its collision shape,
                    // its physics and what it does when clicked or dragged. Where it is, how it's moving and how
                    // far a part has been turned or slid stay the running app's.
                    for kind in [ModelComponent.self, CollisionComponent.self] as [any Component.Type] {
                        if let new = fresh.components[kind] { old.components.set(new) } else { old.components.remove(kind) }
                    }
                    if var body = fresh.components[PhysicsBodyComponent.self] {
                        if let mode = old.components[PhysicsBodyComponent.self]?.mode, mode == .kinematic { body.mode = mode }
                        old.components.set(body)
                    } else {
                        old.components.remove(PhysicsBodyComponent.self)
                    }
                    if var part = fresh.components[LampPart.self] {
                        if let was = old.components[LampPart.self] {
                            part.rest = was.rest
                            part.restPosition = was.restPosition
                            part.value = was.value
                        }
                        old.components.set(part)
                    } else {
                        old.components.remove(LampPart.self)
                    }
                }
            }
        }

        /// The first entity with this name anywhere in the scene.
        func find(_ name: String) -> Entity? { root.findEntity(named: name) }

        /// Whether a key is held: letters, digits, .up, .down, .left, .right, .space, .shift, .escape, .enter. (Tab
        /// moves keyboard focus, so it's never the scene's.)
        func isDown(_ key: LampKey) -> Bool {
            key == .shift ? NSEvent.modifierFlags.contains(.shift) : keys.contains(key.code)
        }

        func start(_ content: inout RealityViewCameraContent, sky: LampSky, rig: LampCameraRig, props: [String: @MainActor () -> Entity],
                   build: (LampScene) async -> Void, update: ((LampScene, Float) -> Void)?) async {
            self.rig = rig
            self.update = update
            self.props = props
            if case .orbit(_, let distance, let yaw, let pitch) = rig { orbitDistance = distance; orbitYaw = yaw; orbitPitch = pitch }
            if case .firstPerson(let position, let heading) = rig { camera.position = position; lookYaw = heading }
            content.add(root)
            // The near plane far enough out that surfaces a few millimetres apart still sort cleanly (RealityKit's
            // default of 1 cm makes distant ground layers and decals fight and flicker).
            camera.camera.near = 0.1
            camera.camera.far = 4000
            camera.camera.fieldOfViewInDegrees = 60
            content.add(camera)
            content.camera = .virtual
            await sky.apply(to: &content, lighting: root)
            await build(self)
            subscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
                MainActor.assumeIsolated { self?.tick(min(Float(event.deltaTime), 1 / 20)) }
            }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .scrollWheel, .leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self else { return event }
                if event.type == .keyUp {
                    self.keys.remove(event.keyCode)
                    return event
                }
                guard let window = self.window, event.window === window else { return event }
                // A click in the window outside the scene's own content (Lamp's chat beside the app, drawn by another
                // process, which AppKit's focus doesn't follow) takes the keyboard away from the scene; a click back
                // in the scene gives it back (the drag gesture).
                if event.type == .leftMouseDown || event.type == .rightMouseDown {
                    if let content = self.content(), !content.bounds.contains(content.convert(event.locationInWindow, from: nil)) {
                        self.hasFocus = false
                        self.keys.removeAll()
                        // RealityKit's view keeps the window's keyboard focus through a click elsewhere, so the keys
                        // would still go to it: they go to what was clicked instead, once the click has landed.
                        let point = event.locationInWindow
                        DispatchQueue.main.async {
                            guard let responder = window.firstResponder as? NSView, responder.isDescendant(of: content),
                                  let frame = window.contentView?.superview,
                                  let hit = frame.hitTest(frame.convert(point, from: nil)) else { return }
                            let target = sequence(first: hit, next: \.superview).first { $0.acceptsFirstResponder }
                            window.makeFirstResponder(target)
                        }
                    }
                    return event
                }
                if event.type == .scrollWheel {
                    self.orbitDistance = max(0.3, self.orbitDistance * (1 - Float(event.scrollingDeltaY) * 0.01))
                    return event
                }
                // Keys only while the scene has focus: when a field, a button or anything else in the window has it
                // (by a click or Tab), its typing, Space and Return are its own, as menu shortcuts always are. Tab is
                // never the scene's: it's how the keyboard moves focus out of it.
                guard self.hasFocus, event.keyCode != 48, !event.modifierFlags.contains(.command),
                      !(window.firstResponder is NSText), self.focusIsHere(in: window) else { return event }
                self.keys.insert(event.keyCode)
                return nil
            }
        }

        /// Whether AppKit's keyboard focus is in the scene's own SwiftUI content (or the window itself). SwiftUI's
        /// focus state doesn't see a view outside its content take focus, such as Lamp's chat beside the app,
        /// whose typing must be its own.
        private func focusIsHere(in window: NSWindow) -> Bool {
            guard let responder = window.firstResponder as? NSView else { return true }
            guard let marker else { return false }
            if marker.isDescendant(of: responder) { return true }
            return content().map { responder.isDescendant(of: $0) } ?? false
        }

        /// SwiftUI's view for the window's content (its class names vary: NSHostingView, AppKitWindowHostingView), in
        /// which RealityKit's own view takes focus when the scene has it. Lamp's chat is outside it.
        private func content() -> NSView? {
            marker.flatMap { sequence(first: $0, next: \.superview).first { String(describing: type(of: $0)).contains("HostingView") } }
        }

        private func tick(_ dt: Float) {
            time += dt
            update?(self, dt)
            moveCamera(dt)
            streamStep()
        }

        // MARK: A world built as you go

        private struct Streaming {
            var size: Float
            var radius: Float
            var focus: (@MainActor () -> SIMD3<Float>)?
            var make: @MainActor (LampTile) -> Entity?
            var built: [LampTile: Entity] = [:]
            var first = true
        }
        private var streaming: Streaming?
        private var slowTiles = 0
        private let streamRoot = Entity()

        /// A big world built a square tile at a time: the tiles within `radius` metres of the camera (or of what
        /// `around` returns, such as the player's car) are made by `make` as they come into reach, nearest first, a
        /// few milliseconds' worth each frame so the app never stalls, and taken away again once well out of
        /// reach. So the app opens at once however big the world is. `make` returns what's drawn on one tile (its
        /// buildings, roads, trees, signs), or nil for an empty one; what the game itself needs everywhere
        /// (collisions, routes, the map's data) stays outside it, made once. Have `make` call a named function, so a
        /// live change to how tiles look reaches the open app.
        func stream(tile size: Float = 100, radius: Float = 400, around: (@MainActor () -> SIMD3<Float>)? = nil,
                    make: @escaping @MainActor (LampTile) -> Entity?) {
            for entity in streaming?.built.values ?? [:].values { entity.removeFromParent() }
            if streamRoot.parent == nil { root.addChild(streamRoot) }
            streaming = Streaming(size: max(size, 1), radius: max(radius, size), focus: around, make: make)
        }

        /// Whether a tile is built right now.
        func isBuilt(_ tile: LampTile) -> Bool { streaming?.built[tile] != nil }

        private func streamStep() {
            guard var s = streaming else { return }
            let at = s.focus?() ?? camera.position(relativeTo: nil)
            let here = SIMD2<Float>(at.x, at.z)
            let reach = Int((s.radius / s.size).rounded(.up))
            let cx = Int(floor(at.x / s.size)), cz = Int(floor(at.z / s.size))
            func distance(_ t: LampTile) -> Float {
                let lo = SIMD2<Float>(Float(t.x), Float(t.z)) * s.size
                return simd_distance(here, simd_clamp(here, lo, lo + s.size))
            }
            // Far ones go (a little past reach, so a tile on the edge isn't made and dropped over and over).
            for (tile, entity) in s.built where distance(tile) > s.radius * 1.25 {
                entity.removeFromParent()
                s.built[tile] = nil
            }
            var wanted: [(LampTile, Float)] = []
            for x in (cx - reach)...(cx + reach) {
                for z in (cz - reach)...(cz + reach) {
                    let tile = LampTile(x: x, z: z, size: s.size)
                    let d = distance(tile)
                    if d <= s.radius, s.built[tile] == nil { wanted.append((tile, d)) }
                }
            }
            wanted.sort { $0.1 < $1.1 }
            // At the start, everything within half the reach, before the first frame: one pause while the app opens
            // rather than a stutter once it's moving. After that, nearest first within a few milliseconds a frame.
            let budget: Double = s.first ? 3 : 0.006
            let started = Date()
            for (tile, distance) in wanted {
                if s.first, distance > s.radius / 2 { break }
                let began = Date()
                let entity = s.make(tile) ?? Entity()
                let took = Date().timeIntervalSince(began)
                // A tile that takes longer than a frame stalls the app however it's scheduled: said in the log, where
                // the builder sees it, so it can make the tile cheaper (meshes and text made once and reused).
                if took > 0.02 {
                    slowTiles += 1
                    if slowTiles <= 3 { print("LampScene: tile \(tile.x),\(tile.z) took \(Int(took * 1000)) ms to build; a tile should take a few.") }
                }
                entity.name = "tile \(tile.x),\(tile.z)"
                streamRoot.addChild(entity)
                s.built[tile] = entity
                if Date().timeIntervalSince(started) > budget { break }
            }
            s.first = false
            streaming = s
        }

        /// Drops every built tile, so they're made again as they come into reach. After a live change, the new code
        /// is what makes them only if `make` calls a named function (`{ tile in World.tile(tile) }`): a live change
        /// replaces functions, and a closure written out in place keeps running the code it was made with.
        func restream() {
            guard var s = streaming else { return }
            for entity in s.built.values { entity.removeFromParent() }
            s.built = [:]
            streaming = s
        }

        // MARK: Camera

        private func moveCamera(_ dt: Float) {
            switch rig {
            case .orbit(let target, _, _, _):
                let p = SIMD3<Float>(cos(orbitPitch) * sin(orbitYaw), sin(orbitPitch), cos(orbitPitch) * cos(orbitYaw)) * orbitDistance
                camera.look(at: target, from: target + p, relativeTo: nil)
            case .chase(let name, let distance, let height):
                guard let target = find(name) else { return }
                let at = target.position(relativeTo: nil)
                let forward = target.orientation(relativeTo: nil).act([0, 0, -1])
                let heading = atan2(-forward.x, -forward.z)
                var h = chaseHeading ?? heading
                var dh = heading - h
                while dh > .pi { dh -= 2 * .pi }
                while dh < -.pi { dh += 2 * .pi }
                h += dh * min(1, dt * 3.5)
                chaseHeading = h
                let behind = SIMD3<Float>(sin(h), 0, cos(h)) * distance + [0, height, 0]
                let goal = at + behind
                var pos = chasePosition ?? goal
                pos += (goal - pos) * (1 - exp(-dt * 4.5))
                chasePosition = pos
                camera.look(at: at + [0, height * 0.4, 0] - SIMD3(sin(h), 0, cos(h)) * 4, from: pos, relativeTo: nil)
            case .firstPerson(_, _):
                let forward = SIMD3<Float>(-sin(lookYaw), 0, -cos(lookYaw)), right = SIMD3<Float>(cos(lookYaw), 0, -sin(lookYaw))
                var move = SIMD3<Float>(0, 0, 0)
                if isDown(.w) || isDown(.up) { move += forward }
                if isDown(.s) || isDown(.down) { move -= forward }
                if isDown(.d) || isDown(.right) { move += right }
                if isDown(.a) || isDown(.left) { move -= right }
                if simd_length(move) > 0 { camera.position += simd_normalize(move) * dt * (isDown(.shift) ? 7 : 3) }
                camera.orientation = simd_quatf(angle: lookYaw, axis: [0, 1, 0]) * simd_quatf(angle: lookPitch, axis: [1, 0, 0])
            case .fixed(let position, let target):
                camera.look(at: target, from: position, relativeTo: nil)
            case .manual:
                break
            }
        }

        // MARK: Pointer

        private struct Drag {
            var part: Entity?
            var start: CGPoint
            var last: CGPoint
            var value: Float = 0
            var offset = SIMD3<Float>(0, 0, 0)
            var planeY: Float = 0
        }

        /// The ray from the camera through a point in the view, in the scene's space.
        func ray(through point: CGPoint) -> (origin: SIMD3<Float>, direction: SIMD3<Float>) {
            let size = viewSize
            let x = Float(point.x / max(size.width, 1)) * 2 - 1, y = 1 - Float(point.y / max(size.height, 1)) * 2
            let t = tan(camera.camera.fieldOfViewInDegrees * .pi / 360)
            let aspect = Float(size.width / max(size.height, 1))
            let o = camera.orientation(relativeTo: nil)
            let direction = simd_normalize(o.act([x * t * aspect, y * t, -1]))
            return (camera.position(relativeTo: nil), direction)
        }

        /// Where a point in the scene appears in the view, or nil when it's behind the camera.
        func project(_ point: SIMD3<Float>) -> CGPoint? {
            let local = camera.orientation(relativeTo: nil).inverse.act(point - camera.position(relativeTo: nil))
            guard local.z < -0.001 else { return nil }
            let t = tan(camera.camera.fieldOfViewInDegrees * .pi / 360)
            let aspect = Float(viewSize.width / max(viewSize.height, 1))
            let x = local.x / -local.z / (t * aspect), y = local.y / -local.z / t
            return CGPoint(x: CGFloat((x + 1) / 2) * viewSize.width, y: CGFloat((1 - y) / 2) * viewSize.height)
        }

        /// The nearest entity under a point that has collision shapes (parts get theirs from the lamp… calls).
        func entity(at point: CGPoint) -> Entity? {
            let r = ray(through: point)
            return root.scene?.raycast(origin: r.origin, direction: r.direction, length: 2000, query: .nearest).first?.entity
        }

        /// A click or drag in the view, from where it started to where the pointer is: on a part it works the part,
        /// elsewhere it moves the camera (orbit and first person).
        func dragChanged(from start: CGPoint, to location: CGPoint) {
            if drag == nil {
                var part = entity(at: start)
                while let p = part, p.components[LampPart.self] == nil { part = p.parent }
                var d = Drag(part: part, start: start, last: start)
                if let part, let info = part.components[LampPart.self] {
                    d.value = info.value
                    let at = part.position(relativeTo: nil)
                    d.planeY = at.y
                    if case .grab = info.kind, let hit = groundPoint(start, y: at.y) { d.offset = at - hit }
                    if case .grab = info.kind, var body = part.components[PhysicsBodyComponent.self], body.mode == .dynamic {
                        body.mode = .kinematic
                        part.components.set(body)
                    }
                }
                drag = d
            }
            guard var d = drag else { return }
            let dx = Float(location.x - d.last.x), dy = Float(location.y - d.last.y)
            d.last = location
            if let part = d.part, var info = part.components[LampPart.self] {
                switch info.kind {
                case .press:
                    break
                case .turn(let axis, let range):
                    d.value = min(max(d.value + (dx - dy) * 0.012, range.lowerBound), range.upperBound)
                    part.orientation = info.rest * simd_quatf(angle: d.value, axis: simd_normalize(axis))
                    info.value = d.value
                    info.changed?(d.value)
                case .slide(let axis, let range):
                    // How far a step along the axis moves on screen, so the part follows the pointer.
                    let at = part.position(relativeTo: nil)
                    let worldAxis = simd_normalize((part.parent?.orientation(relativeTo: nil) ?? simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)).act(axis))
                    if let a = project(at), let b = project(at + worldAxis * 0.1) {
                        let screen = SIMD2<Float>(Float(b.x - a.x), Float(b.y - a.y))
                        let len2 = max(simd_length_squared(screen), 0.0001)
                        d.value = min(max(d.value + simd_dot(SIMD2(dx, dy), screen) / len2 * 0.1, range.lowerBound), range.upperBound)
                        part.position = info.restPosition + simd_normalize(axis) * d.value
                        info.value = d.value
                        info.changed?(d.value)
                    }
                case .grab:
                    if let hit = groundPoint(location, y: d.planeY) {
                        part.setPosition(hit + d.offset, relativeTo: nil)
                    }
                }
                part.components.set(info)
            } else {
                switch rig {
                case .orbit:
                    orbitYaw -= dx * 0.008
                    orbitPitch = min(1.45, max(-0.2, orbitPitch + dy * 0.006))
                case .firstPerson:
                    lookYaw -= dx * 0.006
                    lookPitch = min(1.4, max(-1.4, lookPitch - dy * 0.006))
                default:
                    break
                }
            }
            drag = d
        }

        func dragEnded(from start: CGPoint, to location: CGPoint) {
            defer { drag = nil }
            guard let d = drag, let part = d.part, let info = part.components[LampPart.self] else { return }
            let moved = hypot(location.x - d.start.x, location.y - d.start.y)
            if case .press(let action) = info.kind, moved < 6 {
                // A press: in and out again, then the action.
                let rest = part.transform
                var pushed = rest
                pushed.scale *= 0.94
                part.move(to: pushed, relativeTo: part.parent, duration: 0.06)
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.08))
                    part.move(to: rest, relativeTo: part.parent, duration: 0.1)
                }
                action()
            }
            if case .grab = info.kind, var body = part.components[PhysicsBodyComponent.self], body.mode == .kinematic, info.wasDynamic {
                body.mode = .dynamic
                part.components.set(body)
            }
        }

        private func groundPoint(_ point: CGPoint, y: Float) -> SIMD3<Float>? {
            let r = ray(through: point)
            guard abs(r.direction.y) > 0.0001 else { return nil }
            let t = (y - r.origin.y) / r.direction.y
            guard t > 0 else { return nil }
            return r.origin + r.direction * t
        }

        // MARK: Many copies

        /// Many copies of one model, each where a transform puts it, drawn together: thousands cost about what one
        /// does (on macOS 26 and later; before that they're ordinary copies).
        static func copies(of model: Entity, at transforms: [Transform]) -> Entity {
            let group = Entity()
            guard !transforms.isEmpty else { return group }
            if #available(macOS 26.0, *) {
                let mats = transforms.map(\.matrix)
                func visit(_ e: Entity) {
                    if let part = e.components[ModelComponent.self] {
                        // Batches small enough in all: past a few million vertices a batch isn't drawn at all, and nothing
                        // says so. (A box with rounded corners has thousands.)
                        let local = e === model ? matrix_identity_float4x4 : e.transformMatrix(relativeTo: model)
                        let vertices = part.mesh.contents.models.reduce(0) { $0 + $1.parts.reduce(0) { $0 + $1.positions.count } }
                        let perBatch = max(1, 400_000 / max(vertices, 1))
                        for start in stride(from: 0, to: mats.count, by: perBatch) {
                            let slice = mats[start..<min(start + perBatch, mats.count)]
                            guard let data = try? LowLevelInstanceData(instanceCount: slice.count) else { continue }
                            data.withMutableTransforms { t in for (i, m) in slice.enumerated() { t[i] = m * local } }
                            let holder = Entity()
                            holder.components.set(part)
                            if let instances = try? MeshInstancesComponent(mesh: part.mesh, instances: data) { holder.components.set(instances) }
                            group.addChild(holder)
                        }
                    }
                    for child in e.children { visit(child) }
                }
                visit(model)
            } else {
                for t in transforms {
                    let copy = model.clone(recursive: true)
                    copy.transform = t
                    group.addChild(copy)
                }
            }
            return group
        }

        // MARK: Lamp's builder

        static let propRequest = Notification.Name("{{NOTE}}prop.{{SLUG}}")

        /// Tells Lamp the prop is on screen (or why it isn't), beside the pictures in the runtime folder.
        static func answerProp(_ text: String) {
            try? text.write(to: LampRuntime.folder.appendingPathComponent("prop.txt"), atomically: true, encoding: .utf8)
        }
    }

    /// Finds the window a view is drawn in.
    private struct LampSceneWindow: NSViewRepresentable {
        let found: (NSView?) -> Void
        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            DispatchQueue.main.async { [weak view] in found(view) }
            return view
        }
        func updateNSView(_ view: NSView, context: Context) {
            DispatchQueue.main.async { [weak view] in found(view) }
        }
    }

    /// One square of a streamed world (`LampScene.stream`): its place in the grid and the ground it covers.
    struct LampTile: Hashable, Sendable {
        let x: Int, z: Int
        let size: Float
        /// The corner with the smallest x and z, and the opposite one, at ground level.
        var min: SIMD3<Float> { [Float(x) * size, 0, Float(z) * size] }
        var max: SIMD3<Float> { [Float(x + 1) * size, 0, Float(z + 1) * size] }
        var center: SIMD3<Float> { [(Float(x) + 0.5) * size, 0, (Float(z) + 0.5) * size] }
        /// Whether a point on the ground (x and z) is on this tile: to share out a world's things among tiles.
        func contains(_ point: SIMD3<Float>) -> Bool {
            point.x >= min.x && point.x < max.x && point.z >= min.z && point.z < max.z
        }
        static func == (a: LampTile, b: LampTile) -> Bool { a.x == b.x && a.z == b.z }
        func hash(into hasher: inout Hasher) { hasher.combine(x); hasher.combine(z) }
    }

    /// A key, for `LampScene.isDown`.
    struct LampKey: Equatable, Sendable {
        let code: UInt16
        static let a = LampKey(code: 0), s = LampKey(code: 1), d = LampKey(code: 2), f = LampKey(code: 3), h = LampKey(code: 4)
        static let g = LampKey(code: 5), z = LampKey(code: 6), x = LampKey(code: 7), c = LampKey(code: 8), v = LampKey(code: 9)
        static let b = LampKey(code: 11), q = LampKey(code: 12), w = LampKey(code: 13), e = LampKey(code: 14), r = LampKey(code: 15)
        static let y = LampKey(code: 16), t = LampKey(code: 17), o = LampKey(code: 31), u = LampKey(code: 32), i = LampKey(code: 34)
        static let p = LampKey(code: 35), l = LampKey(code: 37), j = LampKey(code: 38), k = LampKey(code: 40), n = LampKey(code: 45), m = LampKey(code: 46)
        static let one = LampKey(code: 18), two = LampKey(code: 19), three = LampKey(code: 20), four = LampKey(code: 21), five = LampKey(code: 23)
        static let space = LampKey(code: 49), escape = LampKey(code: 53), enter = LampKey(code: 36)
        static let left = LampKey(code: 123), right = LampKey(code: 124), down = LampKey(code: 125), up = LampKey(code: 126)
        static let shift = LampKey(code: 56)
    }

    /// How the camera moves.
    enum LampCameraRig {
        /// Round a point: drag to turn, scroll to come closer.
        case orbit(target: SIMD3<Float> = [0, 0.5, 0], distance: Float = 4, yaw: Float = 0.6, pitch: Float = 0.35)
        /// Behind the entity with this name, turning with it, a little late, as in a driving game.
        case chase(String, distance: Float = 7, height: Float = 2.8)
        /// Walking: W A S D or the arrows move, shift runs, drag looks round.
        case firstPerson(position: SIMD3<Float> = [0, 1.7, 4], heading: Float = 0)
        /// Still, looking at a point.
        case fixed(position: SIMD3<Float>, lookAt: SIMD3<Float>)
        /// Left alone: move `scene.camera` yourself in `update`.
        case manual
    }

    // MARK: - Sky and light

    /// The sky behind the scene, which also lights it, with a sun to match. There are no sun shadows: in a large
    /// scene RealityKit drops the sunlight on some frames when they're on, and the whole picture flickers. Things
    /// standing on the ground get a soft shadow under them instead (`lampShadow`).
    enum LampSky {
        case day, sunset, overcast, night, studio
        /// An image in the app's Assets (an .hdr or .exr panorama, or a PNG laid out the same way), with where its sun is.
        case asset(String, sun: SIMD3<Float> = [-0.4, 0.7, 0.5])

        var sun: SIMD3<Float> {
            switch self {
            case .day: simd_normalize([-0.4, 0.75, 0.5])
            case .sunset: simd_normalize([-0.8, 0.15, 0.4])
            case .overcast: simd_normalize([0.2, 0.9, 0.3])
            case .night: simd_normalize([0.3, 0.6, -0.5])
            case .studio: simd_normalize([-0.5, 0.8, 0.6])
            case .asset(_, let sun): simd_normalize(sun)
            }
        }

        private var colors: (zenith: SIMD3<Float>, horizon: SIMD3<Float>, ground: SIMD3<Float>, sun: SIMD3<Float>, strength: Float) {
            switch self {
            case .day: ([0.22, 0.45, 0.85], [0.78, 0.86, 0.95], [0.36, 0.35, 0.33], [1, 0.97, 0.9], 1)
            case .sunset: ([0.2, 0.25, 0.5], [1, 0.62, 0.35], [0.25, 0.2, 0.2], [1, 0.75, 0.5], 0.8)
            case .overcast: ([0.62, 0.65, 0.7], [0.82, 0.83, 0.85], [0.4, 0.4, 0.4], [1, 1, 1], 0.4)
            case .night: ([0.01, 0.02, 0.06], [0.06, 0.08, 0.16], [0.02, 0.02, 0.03], [0.6, 0.7, 1], 0.12)
            case .studio, .asset: ([0.72, 0.73, 0.75], [0.88, 0.88, 0.89], [0.55, 0.55, 0.56], [1, 1, 1], 0.8)
            }
        }

        @MainActor
        func apply(to content: inout RealityViewCameraContent, lighting root: Entity) async {
            var image: CGImage?
            if case .asset(let name, _) = self, let url = LampAssets.url(name),
               let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
                image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            }
            let c = colors
            if let sky = try? await EnvironmentResource(equirectangular: image ?? LampSky.panorama(c, sun: sun)) {
                content.environment = .skybox(sky)
                // The sky lights everything, which on its own washes a scene out: turned down so the sun shapes it.
                let light = Entity()
                light.components.set(ImageBasedLightComponent(source: .single(sky), intensityExponent: -0.6))
                content.add(light)
                root.components.set(ImageBasedLightReceiverComponent(imageBasedLight: light))
            }
            let sunlight = DirectionalLight()
            sunlight.light.intensity = 7000 * c.strength
            sunlight.light.color = NSColor(red: CGFloat(c.sun.x), green: CGFloat(c.sun.y), blue: CGFloat(c.sun.z), alpha: 1)
            sunlight.look(at: .zero, from: sun * 100, relativeTo: nil)
            content.add(sunlight)
        }

        private static func panorama(_ c: (zenith: SIMD3<Float>, horizon: SIMD3<Float>, ground: SIMD3<Float>, sun: SIMD3<Float>, strength: Float),
                                     sun: SIMD3<Float>) -> CGImage {
            LampTexture.draw(1024, 512) { u, v in
                let phi = (0.5 - v) * .pi, lam = u * 2 * .pi - .pi
                let dir = SIMD3<Float>(cos(phi) * sin(lam), sin(phi), -cos(phi) * cos(lam))
                var col: SIMD3<Float>
                if phi > 0 { col = simd_mix(c.horizon, c.zenith, SIMD3(repeating: pow(phi / (.pi / 2), 0.5))) }
                else { col = simd_mix(c.horizon * 0.85, c.ground, SIMD3(repeating: min(1, -phi * 5))) }
                let d = max(0, simd_dot(dir, sun))
                col += c.sun * (pow(d, 800) * 8 + pow(d, 10) * 0.3) * c.strength
                return SIMD4(col, 1)
            }
        }
    }

    // MARK: - Shapes

    /// Meshes for props, in metres. Boxes, spheres and the like come from RealityKit; the rest are built here.
    enum LampMesh {
        /// A box centred on its middle. Square-edged, its texture is laid on in metres, so a brick wall's bricks are
        /// brick-sized however long the wall; with rounded corners (`corner`, for props) each face holds one copy.
        static func box(_ size: SIMD3<Float>, corner: Float = 0) -> MeshResource {
            guard corner <= 0 else { return .generateBox(size: size, cornerRadius: corner) }
            var b = LampMeshBuilder()
            let h = size / 2
            // Each face: its corner, its two edges (across, up), counter-clockwise from outside.
            let faces: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = [
                ([-h.x, -h.y, h.z], [size.x, 0, 0], [0, size.y, 0]), ([h.x, -h.y, -h.z], [-size.x, 0, 0], [0, size.y, 0]),
                ([h.x, -h.y, h.z], [0, 0, -size.z], [0, size.y, 0]), ([-h.x, -h.y, -h.z], [0, 0, size.z], [0, size.y, 0]),
                ([-h.x, h.y, h.z], [size.x, 0, 0], [0, 0, -size.z]), ([-h.x, -h.y, -h.z], [size.x, 0, 0], [0, 0, size.z])]
            for (o, a, u) in faces {
                let w = simd_length(a), t = simd_length(u)
                b.quad(o, o + a, o + a + u, o + u, uv: ([0, 0], [w, 0], [w, t], [0, t]))
            }
            return b.mesh() ?? .generateBox(size: size)
        }
        static func sphere(_ radius: Float) -> MeshResource { .generateSphere(radius: radius) }
        static func cylinder(radius: Float, height: Float) -> MeshResource { .generateCylinder(height: height, radius: radius) }
        static func cone(radius: Float, height: Float) -> MeshResource { .generateCone(height: height, radius: radius) }

        /// A flat rectangle lying on the ground, its texture repeated every `tile` metres.
        static func plane(width: Float, depth: Float, tile: Float = 1) -> MeshResource {
            var b = LampMeshBuilder()
            let w = width / 2, d = depth / 2
            b.quad([-w, 0, d], [w, 0, d], [w, 0, -d], [-w, 0, -d], uv: ([-w / tile, -d / tile], [w / tile, -d / tile], [w / tile, d / tile], [-w / tile, d / tile]))
            return b.mesh() ?? .generatePlane(width: width, depth: depth)
        }

        /// A shape turned on a lathe round the vertical axis, from its outline as (radius, height) points from bottom
        /// to top: bottles, vases, lamps, wheels lying down, poles, glasses, bowls. A radius of 0 closes that end.
        static func lathe(_ profile: [SIMD2<Float>], segments: Int = 40, sweep: Float = 2 * .pi) -> MeshResource {
            var b = LampMeshBuilder()
            let n = profile.count
            guard n > 1 else { return .generateSphere(radius: 0.01) }
            var along: [Float] = [0]
            for i in 1..<n { along.append(along[i - 1] + simd_distance(profile[i - 1], profile[i])) }
            // Smooth normals across the outline, except at sharp corners where each side keeps its own.
            func normal(_ i: Int, side: Int) -> SIMD2<Float> {
                func of(_ a: SIMD2<Float>, _ c: SIMD2<Float>) -> SIMD2<Float> { let t = simd_normalize(c - a); return [t.y, -t.x] }
                let before = i > 0 ? of(profile[i - 1], profile[i]) : nil
                let after = i < n - 1 ? of(profile[i], profile[i + 1]) : nil
                if let before, let after {
                    if simd_dot(before, after) < 0.7 { return side < 0 ? before : after }
                    return simd_normalize(before + after)
                }
                return before ?? after!
            }
            let rows = segments + 1
            for i in 0..<(n - 1) {
                for (k, j) in [i, i + 1].enumerated() {
                    let side = k == 0 ? 1 : -1
                    let nn = normal(j, side: side)
                    for s in 0..<rows {
                        let a = sweep * Float(s) / Float(segments)
                        let c = cos(a), sn = sin(a)
                        b.positions.append([profile[j].x * c, profile[j].y, -profile[j].x * sn])
                        b.normals.append(simd_normalize([nn.x * c, nn.y, -nn.x * sn]))
                        b.uvs.append([Float(s) / Float(segments) * max(profile.map(\.x).max()!, 0.05) * 2 * .pi, along[j]])
                    }
                }
                let base = UInt32(b.positions.count - 2 * rows)
                for s in 0..<UInt32(segments) {
                    let p = base + s, q = base + UInt32(rows) + s
                    b.indices += [p, p + 1, q + 1, p, q + 1, q]
                }
            }
            return b.mesh() ?? .generateSphere(radius: 0.01)
        }

        /// An outline (a SwiftUI Path, in metres, y up) given depth along z, with its edges rounded by `chamfer`:
        /// panels, brackets, signs, cut-out shapes, letters' outlines.
        static func extrude(_ outline: Path, depth: Float, chamfer: Float = 0) -> MeshResource {
            var options = MeshResource.ShapeExtrusionOptions()
            options.extrusionMethod = .linear(depth: depth)
            options.chamferRadius = chamfer
            options.boundaryResolution = .uniformSegmentsPerSpan(segmentCount: 12)
            return (try? MeshResource(extruding: outline, extrusionOptions: options)) ?? .generateBox(size: depth)
        }

        /// A cross-section (a SwiftUI Path, in metres) carried along points: frames, rails, handles, mouldings.
        static func sweep(_ section: Path, along points: [SIMD3<Float>]) -> MeshResource {
            var options = MeshResource.ShapeExtrusionOptions()
            options.extrusionMethod = .tracePositions(points)
            options.boundaryResolution = .uniformSegmentsPerSpan(segmentCount: 8)
            return (try? MeshResource(extruding: section, extrusionOptions: options)) ?? .generateSphere(radius: 0.01)
        }

        /// A round tube along points, curving smoothly through them unless `smooth` is false: cables, pipes, wire,
        /// rails, a handle's bend.
        static func tube(along points: [SIMD3<Float>], radius: Float, smooth: Bool = true) -> MeshResource {
            sweep(Path(ellipseIn: CGRect(x: -CGFloat(radius), y: -CGFloat(radius), width: CGFloat(radius * 2), height: CGFloat(radius * 2))),
                  along: smooth ? curve(through: points) : points)
        }

        /// Points along a smooth curve through the given ones (Catmull-Rom), for sweeps and tubes that bend.
        static func curve(through points: [SIMD3<Float>], steps: Int = 10) -> [SIMD3<Float>] {
            guard points.count > 2 else { return points }
            var out: [SIMD3<Float>] = []
            for i in 0..<(points.count - 1) {
                let p0 = points[max(i - 1, 0)], p1 = points[i], p2 = points[i + 1], p3 = points[min(i + 2, points.count - 1)]
                for s in 0..<steps {
                    let t = Float(s) / Float(steps), t2 = t * t, t3 = t2 * t
                    let a = 2 * p1, b = p2 - p0, c = 2 * p0 - 5 * p1 + 4 * p2 - p3, d = -p0 + 3 * p1 - 3 * p2 + p3
                    out.append(0.5 * (a + b * t + c * t2 + d * t3))
                }
            }
            out.append(points[points.count - 1])
            return out
        }

        /// Writing, in metres tall, given depth.
        static func text(_ string: String, size: Float, depth: Float = 0.01, weight: NSFont.Weight = .semibold) -> MeshResource {
            .generateText(string, extrusionDepth: depth, font: .systemFont(ofSize: CGFloat(size), weight: weight), alignment: .center)
        }
    }

    /// Builds a mesh from triangles, for shapes RealityKit doesn't make.
    struct LampMeshBuilder {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []

        /// Four corners, counter-clockwise seen from the side that shows.
        mutating func quad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>,
                           uv: (SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>) = ([0, 0], [1, 0], [1, 1], [0, 1])) {
            let n = simd_normalize(simd_cross(b - a, c - a))
            let base = UInt32(positions.count)
            positions += [a, b, c, d]
            normals += [n, n, n, n]
            uvs += [uv.0, uv.1, uv.2, uv.3]
            indices += [base, base + 1, base + 2, base, base + 2, base + 3]
        }

        func mesh() -> MeshResource? {
            guard !indices.isEmpty else { return nil }
            var d = MeshDescriptor()
            d.positions = MeshBuffers.Positions(positions)
            d.normals = MeshBuffers.Normals(normals)
            d.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
            d.primitives = .triangles(indices)
            return try? MeshResource.generate(from: [d])
        }
    }

    // MARK: - Materials

    /// Materials that look like what they're named for, with surface detail drawn in code (no image files). Textured
    /// ones repeat every metre of a shape's texture coordinates; pass `repeat` for finer or coarser.
    @MainActor
    enum LampMaterial {
        static func metal(_ color: NSColor = .gray, rough: Float = 0.35) -> PhysicallyBasedMaterial {
            base(color, rough: rough, metal: 1)
        }
        static var chrome: PhysicallyBasedMaterial { base(NSColor(white: 0.92, alpha: 1), rough: 0.08, metal: 1) }
        /// Brushed steel or aluminium: fine streaks along the texture's width.
        static func brushed(_ color: NSColor = NSColor(white: 0.75, alpha: 1), repeat r: Float = 1) -> PhysicallyBasedMaterial {
            var m = base(color, rough: 0.3, metal: 1, texture: LampTexture.brushed, repeat: r)
            m.roughness = .init(texture: .init(LampTexture.cached("brushed-rough") { LampTexture.gray(LampTexture.brushedRough) }, sampler: LampTexture.sampler))
            return m
        }
        static func plastic(_ color: NSColor, gloss: Float = 0.5) -> PhysicallyBasedMaterial { base(color, rough: 0.65 - gloss * 0.5) }
        static func rubber(_ color: NSColor = NSColor(white: 0.08, alpha: 1)) -> PhysicallyBasedMaterial { base(color, rough: 0.92) }
        static func ceramic(_ color: NSColor = .white) -> PhysicallyBasedMaterial {
            var m = base(color, rough: 0.15)
            m.clearcoat = .init(floatLiteral: 0.8)
            return m
        }
        /// Car paint, lacquer, enamel: a coloured coat under a clear one.
        static func paint(_ color: NSColor) -> PhysicallyBasedMaterial {
            var m = base(color, rough: 0.35, metal: 0.3)
            m.clearcoat = .init(floatLiteral: 1)
            m.clearcoatRoughness = .init(floatLiteral: 0.05)
            return m
        }
        /// See-through: `clear` from 0 (frosted, nearly opaque) to 1 (nearly invisible).
        static func glass(_ tint: NSColor = .white, clear: Float = 0.85) -> PhysicallyBasedMaterial {
            var m = base(tint, rough: 0.04)
            m.blending = .transparent(opacity: .init(floatLiteral: max(0.05, 1 - clear)))
            m.specular = .init(floatLiteral: 1)
            return m
        }
        static func wood(_ color: NSColor = NSColor(red: 0.55, green: 0.36, blue: 0.2, alpha: 1), repeat r: Float = 1) -> PhysicallyBasedMaterial {
            base(color, rough: 0.6, texture: LampTexture.wood, repeat: r)
        }
        static func fabric(_ color: NSColor, repeat r: Float = 4) -> PhysicallyBasedMaterial {
            detailed(color, rough: 0.95, color: LampTexture.weave, height: "weave", repeat: r)
        }
        static func concrete(_ color: NSColor = NSColor(white: 0.7, alpha: 1), repeat r: Float = 1) -> PhysicallyBasedMaterial {
            detailed(color, rough: 0.9, color: LampTexture.concrete, height: "concrete", repeat: r)
        }
        static func asphalt(repeat r: Float = 1) -> PhysicallyBasedMaterial {
            detailed(NSColor(white: 0.3, alpha: 1), rough: 0.95, color: LampTexture.concrete, height: "concrete", repeat: r * 2)
        }
        /// Bricks 25 cm long, laid in courses: `repeat` 4 per metre of texture by default.
        static func brick(_ color: NSColor = NSColor(red: 0.62, green: 0.3, blue: 0.22, alpha: 1), repeat r: Float = 1) -> PhysicallyBasedMaterial {
            detailed(color, rough: 0.85, color: LampTexture.brick, height: "brick", repeat: r)
        }
        /// Square tiles with grout between them, `size` metres across.
        static func tiles(_ color: NSColor = .white, size: Float = 0.2) -> PhysicallyBasedMaterial {
            var m = detailed(color, rough: 0.25, color: LampTexture.tiles, height: "tiles", repeat: 1 / (size * 4))
            m.clearcoat = .init(floatLiteral: 0.4)
            return m
        }
        static func grass(repeat r: Float = 1) -> PhysicallyBasedMaterial {
            base(NSColor(red: 0.3, green: 0.5, blue: 0.2, alpha: 1), rough: 1, texture: LampTexture.speckle, repeat: r * 3)
        }
        /// Gives off light of its own: screens, lamps, LEDs, signs. Doesn't light what's near it.
        static func glow(_ color: NSColor, strength: Float = 2) -> PhysicallyBasedMaterial {
            var m = base(color, rough: 0.4)
            m.emissiveColor = .init(color: color)
            m.emissiveIntensity = strength
            return m
        }

        private static func base(_ color: NSColor, rough: Float, metal: Float = 0, texture: String? = nil, repeat r: Float = 1) -> PhysicallyBasedMaterial {
            var m = PhysicallyBasedMaterial()
            let tex = texture.map { name in MaterialParameters.Texture(LampTexture.cached(name) { LampTexture.named(name) }, sampler: LampTexture.sampler) }
            m.baseColor = .init(tint: color.usingColorSpace(.sRGB) ?? color, texture: tex)
            m.roughness = .init(floatLiteral: rough)
            m.metallic = .init(floatLiteral: metal)
            m.textureCoordinateTransform.scale = [r, r]
            return m
        }

        /// Colour detail and a matching bumpiness (a normal map from the same height field).
        private static func detailed(_ tint: NSColor, rough: Float, color: String, height: String, repeat r: Float) -> PhysicallyBasedMaterial {
            var m = base(tint, rough: rough, texture: color, repeat: r)
            m.normal = .init(texture: .init(LampTexture.cached(height + "-normal", semantic: .normal) { LampTexture.normalMap(height) }, sampler: LampTexture.sampler))
            return m
        }
    }

    /// Surface detail drawn in code, made once and kept.
    @MainActor
    enum LampTexture {
        static let brushed = "brushed", wood = "wood", weave = "weave", concrete = "concrete", brick = "brick", tiles = "tiles", speckle = "speckle"
        static let brushedRough = "brushedRough"
        private static var cache: [String: TextureResource] = [:]

        static let sampler: MaterialParameters.Texture.Sampler = {
            let d = MTLSamplerDescriptor()
            d.sAddressMode = .repeat; d.tAddressMode = .repeat
            d.minFilter = .linear; d.magFilter = .linear; d.mipFilter = .linear
            d.maxAnisotropy = 8
            return .init(d)
        }()

        static func cached(_ key: String, semantic: TextureResource.Semantic = .color, _ make: () -> CGImage) -> TextureResource {
            if let t = cache[key] { return t }
            let t = try! TextureResource(image: make(), options: .init(semantic: semantic))
            cache[key] = t
            return t
        }

        static func named(_ name: String) -> CGImage {
            switch name {
            case brushed: return draw(512, 512) { u, v in let s = 0.85 + 0.15 * fbm(u * 2, v * 160, seed: 3); return [s, s, s, 1] }
            case wood: return draw(512, 512) { u, v in
                let rings = sin((u * 9 + fbm(u * 3, v * 0.6, seed: 7) * 2.5) * 2 * .pi) * 0.5 + 0.5
                let s = 0.75 + 0.25 * pow(rings, 3) - 0.08 * fbm(u * 40, v * 3, seed: 2)
                return [s, s * 0.97, s * 0.93, 1] }
            case weave: return draw(256, 256) { u, v in
                let a = sin(u * 64 * .pi), b = sin(v * 64 * .pi)
                let s = 0.82 + 0.1 * (a * b > 0 ? 1 : -1) + 0.08 * fbm(u * 20, v * 20, seed: 4)
                return [s, s, s, 1] }
            case concrete: return draw(512, 512) { u, v in let s = 0.8 + 0.2 * fbm(u * 12, v * 12, seed: 5); return [s, s, s * 0.99, 1] }
            case speckle: return draw(256, 256) { u, v in let s = 0.75 + 0.25 * fbm(u * 30, v * 30, seed: 6); return [s * 0.95, s, s * 0.9, 1] }
            default: return draw(512, 512) { u, v in
                let h = height(name, u, v)
                let s = h < 0.5 ? 0.78 : 0.85 + 0.15 * fbm(u * 18, v * 18, seed: 9)
                return [s, s, s, 1] }
            }
        }

        static func gray(_ name: String) -> CGImage {
            draw(512, 512, gray: true) { u, v in let s = 0.25 + 0.2 * fbm(u * 2, v * 160, seed: 8); return [s, s, s, 1] }
        }

        /// Bumps for bricks, tiles, weave and concrete: 1 on the face, 0 in the joints.
        nonisolated static func height(_ name: String, _ u: Float, _ v: Float) -> Float {
            switch name {
            case brick:
                // Four courses a tile, each brick half a tile long, every other course offset by half a brick.
                let course = Int(floor(v * 8)), y = v * 8 - Float(course)
                let x = u * 4 + (course % 2 == 0 ? 0 : 0.5), fx = x - floor(x)
                return (y < 0.08 || fx < 0.04) ? 0 : 1 - 0.1 * fbm(u * 20, v * 20, seed: 1)
            case tiles:
                let fx = u * 4 - floor(u * 4), fy = v * 4 - floor(v * 4)
                return (fx < 0.04 || fy < 0.04) ? 0 : 1
            case weave:
                return 0.5 + 0.5 * sin(u * 64 * .pi) * sin(v * 64 * .pi)
            default:
                return fbm(u * 16, v * 16, seed: 5)
            }
        }

        static func normalMap(_ name: String) -> CGImage {
            let n = 512
            var h = [Float](repeating: 0, count: n * n)
            for y in 0..<n { for x in 0..<n { h[y * n + x] = height(name, Float(x) / Float(n), Float(y) / Float(n)) } }
            return draw(n, n) { u, v in
                let x = Int(u * Float(n)) % n, y = Int(v * Float(n)) % n
                let dx = h[y * n + (x + 1) % n] - h[y * n + (x + n - 1) % n]
                let dy = h[((y + 1) % n) * n + x] - h[((y + n - 1) % n) * n + x]
                let nrm = simd_normalize(SIMD3<Float>(-dx * 2, dy * 2, 1))
                return SIMD4(nrm * 0.5 + 0.5, 1)
            }
        }

        /// Smooth value noise in octaves, 0 to 1, repeating every whole number of units.
        nonisolated static func fbm(_ x: Float, _ y: Float, seed: UInt32) -> Float {
            var total: Float = 0, amp: Float = 0.5, f: Float = 1
            for _ in 0..<4 { total += amp * noise(x * f, y * f, seed: seed); amp *= 0.5; f *= 2 }
            return total / 0.9375
        }

        nonisolated private static func noise(_ x: Float, _ y: Float, seed: UInt32) -> Float {
            func hash(_ i: Int32, _ j: Int32) -> Float {
                var h = UInt32(bitPattern: i) &* 374761393 &+ UInt32(bitPattern: j) &* 668265263 &+ seed &* 2246822519
                h = (h ^ (h >> 13)) &* 1274126177
                return Float(h & 0xffff) / 65535
            }
            let xi = Int32(floor(x)), yi = Int32(floor(y)), fx = x - floor(x), fy = y - floor(y)
            let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
            let a = hash(xi, yi), b = hash(xi + 1, yi), c = hash(xi, yi + 1), d = hash(xi + 1, yi + 1)
            return (a + (b - a) * sx) + ((c + (d - c) * sx) - (a + (b - a) * sx)) * sy
        }

        /// An image from a function of where in it (u and v from 0 to 1, v down) to RGBA from 0 to 1.
        nonisolated static func draw(_ w: Int, _ h: Int, gray: Bool = false, _ pixel: (Float, Float) -> SIMD4<Float>) -> CGImage {
            let comps = gray ? 1 : 4
            var data = [UInt8](repeating: 0, count: w * h * comps)
            for y in 0..<h {
                for x in 0..<w {
                    let p = simd_clamp(pixel((Float(x) + 0.5) / Float(w), (Float(y) + 0.5) / Float(h)), .zero, .one) * 255
                    let i = (y * w + x) * comps
                    if gray { data[i] = UInt8(p.x) } else { data[i] = UInt8(p.x); data[i + 1] = UInt8(p.y); data[i + 2] = UInt8(p.z); data[i + 3] = UInt8(p.w) }
                }
            }
            let space = gray ? CGColorSpaceCreateDeviceGray() : CGColorSpace(name: CGColorSpace.sRGB)!
            let info = gray ? CGImageAlphaInfo.none.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
            return data.withUnsafeMutableBytes { raw in
                CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * comps,
                          space: space, bitmapInfo: info)!.makeImage()!
            }
        }
    }

    // MARK: - Parts that do something

    /// What a part does when it's clicked or dragged (see the `lamp…` calls on Entity).
    struct LampPart: Component {
        enum Kind {
            case press(@MainActor () -> Void)
            case turn(axis: SIMD3<Float>, range: ClosedRange<Float>)
            case slide(axis: SIMD3<Float>, range: ClosedRange<Float>)
            case grab
        }
        var kind: Kind
        var value: Float = 0
        var rest = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        var restPosition = SIMD3<Float>(0, 0, 0)
        var wasDynamic = false
        var changed: (@MainActor (Float) -> Void)?
    }

    @MainActor
    extension Entity {
        /// A button: clicking it pushes it in and runs `action`.
        @discardableResult func lampPress(_ action: @escaping @MainActor () -> Void) -> Self {
            becomePart(.press(action))
        }

        /// A knob, dial, lid, door or lever: dragging turns it round `axis`, in its own space (a cylinder's axis is
        /// y), within `range` radians of where it is now. Turn a door or lid round its hinge by putting it in an
        /// entity at the hinge and making that the part. `changed` hears the angle.
        @discardableResult func lampTurn(axis: SIMD3<Float> = [0, 0, 1], range: ClosedRange<Float> = -.pi ... .pi,
                                         changed: (@MainActor (Float) -> Void)? = nil) -> Self {
            becomePart(.turn(axis: axis, range: range), changed: changed)
        }

        /// A drawer, slider or plunger: dragging moves it along `axis`, in its parent's space, within `range` metres
        /// of where it is now.
        @discardableResult func lampSlide(axis: SIMD3<Float> = [0, 0, 1], range: ClosedRange<Float> = 0 ... 0.4,
                                          changed: (@MainActor (Float) -> Void)? = nil) -> Self {
            becomePart(.slide(axis: axis, range: range), changed: changed)
        }

        /// Something loose: dragging carries it across the floor at its height; with `lampPhysics` it drops and
        /// tumbles when let go.
        @discardableResult func lampGrab() -> Self { becomePart(.grab) }

        /// Real physics: `.dynamic` falls, bounces and is knocked about; `.static` is what it lands on (a floor,
        /// a table). Its collision shape comes from its meshes.
        @discardableResult func lampPhysics(_ mode: PhysicsBodyMode = .dynamic, mass: Float = 1, bounce: Float = 0.2,
                                            friction: Float = 0.6) -> Self {
            if components[CollisionComponent.self] == nil { generateCollisionShapes(recursive: true, static: mode == .static) }
            let material = PhysicsMaterialResource.generate(staticFriction: friction, dynamicFriction: friction * 0.8, restitution: bounce)
            components.set(PhysicsBodyComponent(massProperties: .init(mass: mass), material: material, mode: mode))
            if var part = components[LampPart.self] { part.wasDynamic = mode == .dynamic; components.set(part) }
            return self
        }

        /// A soft shadow under it on the ground: the scene has no sun shadows, so things that stand on the floor
        /// need this not to look as if they float.
        @discardableResult func lampShadow() -> Self {
            components.set(GroundingShadowComponent(castsShadow: true))
            return self
        }

        private func becomePart(_ kind: LampPart.Kind, changed: (@MainActor (Float) -> Void)? = nil) -> Self {
            if components[CollisionComponent.self] == nil { generateCollisionShapes(recursive: true) }
            var part = LampPart(kind: kind, rest: orientation, restPosition: position, changed: changed)
            part.wasDynamic = components[PhysicsBodyComponent.self]?.mode == .dynamic
            components.set(part)
            return self
        }
    }

    // MARK: - Looking at one prop

    /// One prop on its own, from four sides, on a plain floor in even light: what Lamp's builder looks at to compare
    /// a prop with the picture it was made from.
    struct LampPropStudio: View {
        @MainActor private func copy() -> Entity {
            if let made { return made.clone(recursive: true) }
            let first = make()
            made = first
            return first.clone(recursive: true)
        }

        let name: String
        let make: @MainActor () -> Entity
        /// One copy for all four views, so a prop whose code varies it (a random rider, a random colour) shows the
        /// same thing from every side.
        @State private var made: Entity?
        private let views: [(String, Float, Float)] = [("Front", 0, 0.12), ("Right side", .pi / 2, 0.12),
                                                       ("From above, three quarters", .pi / 4, 0.6), ("Back", .pi, 0.12)]

        var body: some View {
            VStack(spacing: 2) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: 2) {
                        ForEach(0..<2, id: \.self) { col in
                            let v = views[row * 2 + col]
                            RealityView { content in
                                await LampPropStudio.stage(&content, prop: copy(), yaw: v.1, pitch: v.2)
                            }
                            .realityViewCameraControls(.none)
                            .overlay(alignment: .topLeading) {
                                Text(v.0).font(.system(size: 12, weight: .semibold)).foregroundStyle(.black.opacity(0.6)).padding(8)
                            }
                        }
                    }
                }
            }
            .background(Color(white: 0.85))
            .overlay(alignment: .bottom) {
                Text(name).font(.system(size: 13, weight: .bold)).foregroundStyle(.black).padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.white.opacity(0.85), in: Capsule()).padding(8)
            }
        }

        @MainActor
        static func stage(_ content: inout RealityViewCameraContent, prop: Entity, yaw: Float, pitch: Float) async {
            let holder = Entity()
            holder.addChild(prop)
            let bounds = prop.visualBounds(relativeTo: holder)
            let size = max(bounds.extents.x, bounds.extents.y, bounds.extents.z, 0.01)
            prop.position -= [bounds.center.x, bounds.min.y, bounds.center.z]
            content.add(holder)
            let floor = ModelEntity(mesh: .generatePlane(width: size * 40, depth: size * 40), materials: [LampMaterial.concrete(NSColor(white: 0.8, alpha: 1), repeat: 8)])
            floor.position.y = -0.001
            content.add(floor)
            prop.components.set(GroundingShadowComponent(castsShadow: true))
            let camera = PerspectiveCamera()
            camera.camera.near = size * 0.02
            camera.camera.fieldOfViewInDegrees = 35
            let target = SIMD3<Float>(0, bounds.extents.y / 2, 0)
            let distance = size * 2.2
            let eye = target + SIMD3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
            camera.look(at: target, from: eye, relativeTo: nil)
            content.add(camera)
            content.camera = .virtual
            await LampSky.studio.apply(to: &content, lighting: holder)
            // A second, softer light from the other side, so no face is lost in shade.
            let fill = DirectionalLight()
            fill.light.intensity = 2500
            fill.look(at: .zero, from: [0.6, 0.5, -0.7], relativeTo: nil)
            content.add(fill)
        }
    }
    """#
}
