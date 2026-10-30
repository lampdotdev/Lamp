import SwiftUI
import SceneKit
import LampSidebarKit

/// The welcome's stage, in 3D behind its words: the site's six stripes coming down a back wall and running along the
/// floor toward the person, and three of the things Lamp comes with coming down to float over them as thin boxes, each
/// with its picture on the front and its shadow on the stripes. The stripes come first, then the boxes, the words with them
/// (`HelloStep`). The boxes lean a little toward the pointer. Going on to setup, the camera moves right, so the stage
/// slides left as setup comes in, its stripes staying at the frame's left edge.
struct WelcomeScene: NSViewRepresentable {
    /// Where the welcome is: the hello, with the stage in view, or a later step, with the camera moved past it.
    let atHello: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    func makeNSView(context: Context) -> SCNView {
        let view = PassThroughSceneView()
        let stage = WelcomeStage(dark: scheme == .dark)
        view.scene = stage.scene
        view.pointOfView = stage.camera
        view.backgroundColor = WelcomeStage.page(dark: scheme == .dark)
        view.antialiasingMode = .multisampling4X
        view.isPlaying = true
        context.coordinator.stage = stage
        if !reduceMotion { view.pointerMoved = { [weak stage] x, y in stage?.follow(x: x, y: y) } }
        stage.look(atHello: atHello, animated: false)
        // The stripes and the boxes arrive once, as the hello first shows; met again (Back from setup), it's all there.
        if atHello, !reduceMotion, !WelcomeStage.arrived {
            stage.arrive()
        } else {
            stage.settle(moving: !reduceMotion)
        }
        WelcomeStage.arrived = true
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        // SceneKit takes a fixed color, so the page and the boxes' sides are painted again as the Mac's appearance changes.
        view.backgroundColor = WelcomeStage.page(dark: scheme == .dark)
        context.coordinator.stage?.paint(dark: scheme == .dark)
        context.coordinator.stage?.look(atHello: atHello, animated: !reduceMotion)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var stage: WelcomeStage?
    }

    /// Behind the welcome's words and buttons: clicks go to them, never to the scene. It still hears the pointer move
    /// over it, for the boxes to lean toward.
    final class PassThroughSceneView: SCNView {
        var pointerMoved: ((CGFloat, CGFloat) -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
        }

        override func mouseMoved(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            guard bounds.width > 0, bounds.height > 0 else { return }
            pointerMoved?(point.x / bounds.width * 2 - 1, point.y / bounds.height * 2 - 1)
        }
    }
}

/// What's in the welcome's scene, and how it moves.
@MainActor
final class WelcomeStage {
    /// The stage plays its arrival once a launch: going back to the hello finds it already set.
    static var arrived = false
    /// When the boxes start down, the stripes in place: the words come in with them (`HelloStep`).
    static let arrival: Double = 0.6
    /// Paper's page and card, resolved for SceneKit, which draws a fixed color rather than one that follows the Mac.
    static func page(dark: Bool) -> NSColor { resolved(Paper.page, dark: dark) }
    private static func side(dark: Bool) -> NSColor { resolved(Paper.card, dark: dark) }
    private static func resolved(_ color: Color, dark: Bool) -> NSColor {
        var fixed = NSColor(color)
        NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            fixed = NSColor(color).usingColorSpace(.sRGB) ?? fixed
        }
        return fixed
    }

    let scene = SCNScene()
    let camera = SCNNode()
    private var walls: [SCNNode] = []
    private var floors: [SCNNode] = []
    private var boxes: [(node: SCNNode, rest: SCNVector3)] = []
    /// Inside each box's own node, what turns and shifts it toward the pointer, apart from its arrival and its floating.
    private var leans: [SCNNode] = []
    private var dark: Bool

    /// Stripe width, and where the six start across: the right half of the frame, beside the words.
    private static let stripe: CGFloat = 0.55
    private static let left: CGFloat = 1.35
    private static let wallZ: CGFloat = -5
    private static let wallHeight: CGFloat = 10
    private static let floorLength: CGFloat = 18
    /// How far right the camera moves for the steps after the hello: the stripes go to the frame's left, a little past
    /// its edge, and stay there beside setup.
    private static let away: CGFloat = 9.6
    private static let colors: [UInt32] = [0x1F8A4A, 0x7CBF3A, 0xF6B81C, 0xF08A1C, 0xE2402A, 0xD23778]

    init(dark: Bool) {
        self.dark = dark
        scene.background.contents = Self.page(dark: dark)

        let lens = SCNCamera()
        lens.fieldOfView = 38
        lens.zNear = 0.1
        lens.zFar = 100
        camera.camera = lens
        camera.position = SCNVector3(0, 2.1, 9.5)
        camera.eulerAngles.x = -0.07
        scene.rootNode.addChildNode(camera)

        // Soft light everywhere, and one from above and in front that casts the boxes' shadows on the stripes.
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light!.type = .ambient
        ambient.light!.intensity = 700
        scene.rootNode.addChildNode(ambient)
        let sun = SCNNode()
        let light = SCNLight()
        light.type = .directional
        light.intensity = 420
        light.castsShadow = true
        light.shadowMode = .forward
        light.shadowColor = NSColor.black.withAlphaComponent(0.32)
        light.shadowRadius = 6
        light.shadowSampleCount = 16
        light.shadowMapSize = CGSize(width: 2048, height: 2048)
        light.automaticallyAdjustsShadowProjection = true
        sun.light = light
        // Nearly overhead, so each box's shadow falls on the stripes under it.
        sun.eulerAngles = SCNVector3(-1.45, 0, 0)
        scene.rootNode.addChildNode(sun)

        // No floor of its own: the stripes are the floor, and the boxes' shadows fall on them. Anything more tinted the
        // page around the words.
        for (index, hex) in Self.colors.enumerated() {
            let x = Self.left + Self.stripe * (CGFloat(index) + 0.5)
            // Up the wall: grown from the top down, so its pivot is its top edge.
            let wall = SCNNode()
            wall.position = SCNVector3(x, Self.wallHeight, Self.wallZ)
            let wallPlane = SCNNode(geometry: SCNPlane(width: Self.stripe, height: Self.wallHeight))
            wallPlane.geometry!.firstMaterial = Self.flat(NSColor(hex: hex))
            wallPlane.position = SCNVector3(0, -Self.wallHeight / 2, 0)
            // Only the boxes cast shadows: a stripe's would be a smudge on the page.
            wallPlane.castsShadow = false
            wall.addChildNode(wallPlane)
            scene.rootNode.addChildNode(wall)
            walls.append(wall)
            // Along the floor toward the person: grown from the wall, so its pivot is the wall's foot.
            let floor = SCNNode()
            floor.position = SCNVector3(x, 0.004, Self.wallZ)
            let floorPlane = SCNNode(geometry: SCNPlane(width: Self.stripe, height: Self.floorLength))
            floorPlane.geometry!.firstMaterial = Self.flat(NSColor(hex: hex))
            floorPlane.eulerAngles.x = -.pi / 2
            floorPlane.position = SCNVector3(0, 0, Self.floorLength / 2)
            floorPlane.castsShadow = false
            floor.addChildNode(floorPlane)
            scene.rootNode.addChildNode(floor)
            floors.append(floor)
        }

        // The boxes, thin, floating over the stripes at heights of their own, a little turned each, their shadows on the
        // stripes below.
        let placed: [(x: CGFloat, y: CGFloat, z: CGFloat, turn: CGFloat)] = [(2.05, 1.75, 1.7, 0.3), (3.75, 2.75, -1.2, -0.06), (2.3, 0.85, 3.4, -0.3)]
        for (picture, place) in zip(Self.pictures(), placed) {
            let node = SCNNode()
            let lean = SCNNode()
            let slab = SCNNode(geometry: Self.slab(picture, side: Self.side(dark: dark)))
            slab.castsShadow = true
            slab.eulerAngles.y = place.turn
            lean.addChildNode(slab)
            node.addChildNode(lean)
            let rest = SCNVector3(place.x, place.y, place.z)
            node.position = rest
            scene.rootNode.addChildNode(node)
            leans.append(lean)
            boxes.append((node, rest))
        }
    }

    /// Everything where it ends up, at once; the boxes bobbing where they float, unless nothing's to move.
    func settle(moving: Bool) {
        for node in walls + floors { node.scale = SCNVector3(1, 1, 1) }
        for (index, box) in boxes.enumerated() {
            box.node.position = box.rest
            box.node.opacity = 1
            if moving { box.node.runAction(Self.bob(index)) }
        }
    }

    /// The stripes come down the wall one after another and run out along the floor toward the person; then the boxes
    /// come down over them, slowing to float there.
    func arrive() {
        for (index, wall) in walls.enumerated() {
            wall.scale = SCNVector3(1, 0.001, 1)
            wall.runAction(.sequence([.wait(duration: 0.07 * Double(index)), Self.grow(\.y, over: 0.5)]))
        }
        for (index, floor) in floors.enumerated() {
            floor.scale = SCNVector3(1, 1, 0.001)
            floor.runAction(.sequence([.wait(duration: 0.45 + 0.07 * Double(index)), Self.grow(\.z, over: 0.6)]))
        }
        for (index, box) in boxes.enumerated() {
            let rest = box.rest
            // Out of sight until it starts down, so its shadow doesn't come first.
            box.node.position = SCNVector3(rest.x, rest.y + 7, rest.z)
            box.node.opacity = 0
            let fall = SCNAction.move(to: rest, duration: 0.75)
            fall.timingMode = .easeOut
            box.node.runAction(.sequence([.wait(duration: Self.arrival + 0.16 * Double(index)),
                                          .group([.fadeIn(duration: 0.2), fall]), Self.bob(index)]))
        }
    }

    /// A box's slow rise and fall where it floats, each out of step with the others.
    private static func bob(_ index: Int) -> SCNAction {
        let rise = SCNAction.moveBy(x: 0, y: 0.025, z: 0, duration: 1.8 + 0.3 * Double(index))
        rise.timingMode = .easeInEaseOut
        return .sequence([.wait(duration: 0.4 * Double(index)), .repeatForever(.sequence([rise, rise.reversed()]))])
    }

    /// The camera at the hello, or moved right for the steps after it, the stripes at the frame's left.
    func look(atHello: Bool, animated: Bool) {
        let x: CGFloat = atHello ? 0 : Self.away
        guard camera.position.x != x else { return }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.9 : 0
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        camera.position.x = x
        // The boxes are the hello's: past it they fade as they go, so none is left cut off at the frame's edge.
        for lean in leans { lean.opacity = atHello ? 1 : 0 }
        SCNTransaction.commit()
    }

    /// Leans the boxes a little toward the pointer, `x` and `y` running -1 to 1 across the frame (up is positive): each
    /// turns to face it and moves a touch its way, easing there.
    func follow(x: CGFloat, y: CGFloat) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.6
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeOut)
        for lean in leans {
            lean.eulerAngles = SCNVector3(-y * 0.14, x * 0.22, 0)
            lean.position = SCNVector3(x * 0.12, y * 0.07, 0)
        }
        SCNTransaction.commit()
    }

    /// A box as a thin slab rounded every way: its corners in a rounded rectangle, its edges chamfered front and back.
    /// The picture is on its front, sized to it.
    private static func slab(_ picture: NSImage?, side color: NSColor) -> SCNGeometry {
        let width: CGFloat = 2.0, height: CGFloat = 1.17
        let path = NSBezierPath(roundedRect: NSRect(x: -width / 2, y: -height / 2, width: width, height: height), xRadius: 0.13, yRadius: 0.13)
        path.flatness = 0.002
        let shape = SCNShape(path: path, extrusionDepth: 0.1)
        shape.chamferRadius = 0.04
        shape.chamferMode = .both
        let side = flat(color)
        // Front, back, sides, then the chamfers front and back.
        shape.materials = [flat(picture ?? NSColor(hex: 0x1B1A17)), side, side, side, side]
        return shape
    }

    /// The page and the boxes' sides in the Mac's appearance, when it changes while the welcome is up.
    func paint(dark: Bool) {
        guard dark != self.dark else { return }
        self.dark = dark
        scene.background.contents = Self.page(dark: dark)
        for box in boxes {
            box.node.enumerateHierarchy { node, _ in
                guard let materials = node.geometry?.materials, materials.count > 1 else { return }
                materials.dropFirst().forEach { $0.diffuse.contents = Self.side(dark: dark) }
            }
        }
    }

    /// Grows a node's scale along one axis from nothing to whole, easing out.
    private static func grow(_ axis: WritableKeyPath<SCNVector3, CGFloat>, over duration: Double) -> SCNAction {
        SCNAction.customAction(duration: duration) { node, elapsed in
            let t = min(1, Double(elapsed) / duration)
            var scale = node.scale
            scale[keyPath: axis] = max(0.001, CGFloat(1 - pow(1 - t, 3)))
            node.scale = scale
        }
    }

    /// A surface lit softly and evenly, so a stripe reads as its color, with shadows falling on it.
    private static func flat(_ contents: Any) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .lambert
        material.diffuse.contents = contents
        // Smooth as a picture shrinks, and across a surface seen at a slant.
        material.diffuse.minificationFilter = .linear
        material.diffuse.magnificationFilter = .linear
        material.diffuse.mipFilter = .linear
        material.diffuse.maxAnisotropy = 16
        return material
    }

    /// The pictures of the three things the welcome shows, as their starters shipped them.
    private static func pictures() -> [NSImage?] {
        ["homehq", "newyork", "fireside"].map { folder in
            Starters.bundled.first { $0.folder.lastPathComponent == folder }.flatMap { NSImage(contentsOf: Starters.preview(of: $0)) }
        }
    }
}
