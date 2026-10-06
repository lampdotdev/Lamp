import AppKit
import SceneKit
import SwiftUI
import CoreImage

let args = CommandLine.arguments
let out = URL(fileURLWithPath: args.count > 2 ? args[2] : "out")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func writePNG(_ cg: CGImage, _ url: URL) {
    try! NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!.write(to: url)
}

/// Renders at twice the asked-for size and scales down with a Lanczos filter: smooths edges, fine ridges
/// and the shading SceneKit computes at a lower resolution, beyond what multisampling alone does.
@MainActor func supersampled(_ r: SCNRenderer, pixels: CGSize) -> CGImage {
    let big = r.snapshot(atTime: 0, with: CGSize(width: pixels.width * 2, height: pixels.height * 2),
                         antialiasingMode: .multisampling4X)
    let ci = CIImage(cgImage: big.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
    let f = CIFilter(name: "CILanczosScaleTransform")!
    f.setValue(ci, forKey: kCIInputImageKey)
    f.setValue(0.5, forKey: kCIInputScaleKey)
    f.setValue(1.0, forKey: kCIInputAspectRatioKey)
    let out = f.outputImage!
    return CIContext().createCGImage(out, from: CGRect(origin: .zero, size: pixels))!
}

@MainActor func run() {
    let stage = StageScene()
    let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
    renderer.scene = stage.scene
    renderer.pointOfView = stage.camera
    let scale: CGFloat = 2
    let size = Welcome.stage

    func frame(_ t: Double) -> Welcome {
        stage.update(t)
        stage.reflect(t)
        let image = renderer.snapshot(atTime: t, with: CGSize(width: size.width * scale, height: size.height * scale),
                                      antialiasingMode: .multisampling4X)
        let labels = stage.labels(renderer, t: t, height: size.height, scale: scale)
        return Welcome(picture: image.cgImage(forProposedRect: nil, context: nil, hints: nil)!, labels: labels)
    }

    func save(_ view: Welcome, _ name: String, scale: CGFloat) {
        let r = ImageRenderer(content: view)
        r.scale = scale
        writePNG(r.cgImage!, out.appendingPathComponent(name))
    }

    switch args.count > 1 ? args[1] : "still" {
    case "steps", "tour":
        let clay = ClayScene()
        let r = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        r.scene = clay.scene
        r.pointOfView = clay.camera
        let scale: CGFloat = args[1] == "steps" ? 2 : 1.5
        func shot(_ pose: Pose, step: Double) -> Steps {
            clay.pose(pose)
            let img = supersampled(r, pixels: CGSize(width: 1080 * scale, height: 760 * scale))
            return Steps(picture: img, scale: scale, step: step)
        }
        func save(_ v: Steps, _ name: String, _ scale: CGFloat) {
            let ir = ImageRenderer(content: v)
            ir.scale = scale
            writePNG(ir.cgImage!, out.appendingPathComponent(name))
        }
        if args[1] == "steps" {
            for (i, p) in ClayScene.poses.enumerated() { save(shot(p, step: Double(i)), "step\(i).png", 2) }
        } else {
            let rest = 4.5, glide = 1.8, fps = 30.0
            let total = Double(ClayScene.poses.count - 1) * (rest + glide) + rest
            let frames = out.appendingPathComponent("tour")
            try? FileManager.default.removeItem(at: frames)
            try! FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
            for f in 0..<Int(total * fps) {
                let t = Double(f) / fps
                let i = min(Int(t / (rest + glide)), ClayScene.poses.count - 1)
                let into = t - Double(i) * (rest + glide)
                let e = into > rest && i < ClayScene.poses.count - 1 ? (into - rest) / glide : 0
                let step = Double(i) + e * e * (3 - 2 * e)
                save(shot(ClayScene.tour(t, rest: rest, glide: glide), step: step), String(format: "tour/%04d.png", f), 1.5)
            }
        }
    case "aa":
        // The same frame with and without multisampling, to see whether it's taking effect.
        let clay = ClayScene()
        let r = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        r.scene = clay.scene
        r.pointOfView = clay.camera
        writePNG(supersampled(r, pixels: CGSize(width: 1080, height: 760)), out.appendingPathComponent("aa-ssao.png"))
        clay.camera.camera!.screenSpaceAmbientOcclusionIntensity = 0
        writePNG(supersampled(r, pixels: CGSize(width: 1080, height: 760)), out.appendingPathComponent("aa-plain.png"))
    case "icon":
        let doc = try! AppIcon.write(to: out)
        let ictool = "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
        for (look, size) in [("Light", 1024), ("Dark", 1024), ("Light", 128), ("Light", 32)] {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: ictool)
            p.arguments = [doc.path, "--export-preview", "macOS", look, "\(size)", "\(size)", "1",
                           out.appendingPathComponent("icon-\(look)-\(size).png").path]
            try! p.run()
            p.waitUntilExit()
        }
        // `icon <out> <Resources folder>` also replaces the app's icon files.
        if args.count > 3 {
            try! AppIcon.export(doc, to: URL(fileURLWithPath: args[3]), scratch: out)
        }
    case "poses":
        let clay = ClayScene()
        let r = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        r.scene = clay.scene
        r.pointOfView = clay.camera
        for (i, p) in ClayScene.poses.enumerated() {
            clay.pose(p)
            let img = r.snapshot(atTime: 0, with: CGSize(width: 1080, height: 760), antialiasingMode: .multisampling4X)
            writePNG(img.cgImage(forProposedRect: nil, context: nil, hints: nil)!, out.appendingPathComponent("pose\(i).png"))
        }
    case "still":
        for t in [10.0, 14.0, 18.6] { save(frame(t), "still-\(Int(t)).png", scale: 2) }
    case "probe":
        stage.update(12)
        stage.reflect(12)
        for (i, img) in (stage.scene.lightingEnvironment.contents as! [NSImage]).enumerated() {
            writePNG(img.cgImage(forProposedRect: nil, context: nil, hints: nil)!, out.appendingPathComponent("face\(i).png"))
        }
    case "video":
        let fps = 30.0, seconds = Double(args.count > 3 ? args[3] : "14")!
        let frames = out.appendingPathComponent("frames")
        try? FileManager.default.removeItem(at: frames)
        try! FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
        for f in 0..<Int(fps * seconds) {
            save(frame(10 + Double(f) / fps), String(format: "frames/%04d.png", f), scale: 1.5)
        }
    default: break
    }
}

MainActor.assumeIsolated { run() }
