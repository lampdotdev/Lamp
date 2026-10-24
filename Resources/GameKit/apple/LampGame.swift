// Lamp's game kit: the app around the game on the Mac, the iPhone and the iPad. Lamp writes this file before every
// build; the game itself is the C++ in Game/, which this calls each frame (Lamp/lamp_apple.mm).
//
// On the Mac it's one window with the game filling it, under a title bar with nothing in it, so Lamp's wand floats at
// its top right and the chat opens beside it like any app's; the keyboard plays as the first controller. On an iPhone
// or iPad it's the whole screen, on its side, with touch controls over the game while no controller is connected.
import LampGameHost
import QuartzCore
import SwiftUI
#if os(macOS)
import AppKit
#else
import GameController
import UIKit
#endif

@main
struct LampGameApp: SwiftUI.App {
    var body: some SwiftUI.Scene {
        WindowGroup("{{NAME}}") {
            LampGameScreen()
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 720)
        .commands { LampCommands() }
        #endif
    }
}

/// Where the game's files are: what it reads in the app's bundle, and the saves it keeps beside the app's data.
private enum LampGameFiles {
    static var assets: String { LampAssets.folder?.path ?? "" }
    static var saves: String {
        let folder = LampStore.folder.appendingPathComponent("Saves")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.path
    }
}

struct LampGameScreen: View {
    #if os(macOS)
    @State private var showsKeys = true
    #endif

    var body: some View {
        ZStack {
            Color.black
            LampGameSurface()
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
            #if os(iOS)
            LampTouchControls()
            #else
            if showsKeys {
                // How to play, over the game for its first seconds: there may be no controller connected to the Mac.
                Text("WASD or arrows to move · IJKL to look · Space A · Esc B · F X · R Y · Q E bumpers · Z C triggers · P Menu\nA controller connected to this Mac works too.")
                    .font(.system(size: 12, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(16)
                    .transition(.opacity)
                    .task {
                        try? await Task.sleep(for: .seconds(8))
                        withAnimation(.easeOut(duration: 1)) { showsKeys = false }
                    }
            }
            #endif
        }
        .ignoresSafeArea()
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 270)
        #else
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        #endif
    }
}

// MARK: - The Mac

#if os(macOS)
/// The layer the game draws into, with the keyboard while its window is in front.
final class LampGameView: NSView {
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { nil }

    override func makeBackingLayer() -> CALayer { CAMetalLayer() }
    override var wantsUpdateLayer: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, link == nil, let layer else { return }
        lamp_apple_start(Unmanaged.passUnretained(layer).toOpaque(), LampGameFiles.assets, LampGameFiles.saves)
        window.makeFirstResponder(self)
        let link = displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { _ in
            lamp_apple_keys_up()
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = last == 0 ? 1.0 / 60.0 : now - last
        last = now
        lamp_apple_frame(dt, window?.isKeyWindow == true && window?.firstResponder === self)
    }

    override func keyDown(with event: NSEvent) {
        // ⌘ and its keys are the menus'.
        guard !event.modifierFlags.contains(.command) else { return super.keyDown(with: event) }
        lamp_apple_key(event.keyCode, true)
    }
    override func keyUp(with event: NSEvent) { lamp_apple_key(event.keyCode, false) }
    override func flagsChanged(with event: NSEvent) {}
    // A click on the game gives it the keyboard back after the chat had it.
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }
}

struct LampGameSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> LampGameView { LampGameView(frame: .zero) }
    func updateNSView(_ view: LampGameView, context: Context) {}
}
#endif

// MARK: - iPhone and iPad

#if os(iOS)
final class LampGameView: UIView {
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0

    override class var layerClass: AnyClass { CAMetalLayer.self }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, link == nil else { return }
        lamp_apple_start(Unmanaged.passUnretained(layer).toOpaque(), LampGameFiles.assets, LampGameFiles.saves)
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = last == 0 ? 1.0 / 60.0 : now - last
        last = now
        lamp_apple_frame(dt, false)
    }
}

struct LampGameSurface: UIViewRepresentable {
    func makeUIView(context: Context) -> LampGameView { LampGameView() }
    func updateUIView(_ view: LampGameView, context: Context) {}
}

/// The controller drawn over the game while no real one is connected, or once the screen is touched (the simulator
/// passes the Mac's controllers through, and a person may hold a phone with a controller paired and still play by
/// touch): a stick wherever the left thumb goes down,
/// a right-hand drag as the right stick when the game wants it, and the buttons the game asked for
/// (`lamp_touch_buttons`) under the right thumb, Menu at the top.
struct LampTouchControls: View {
    @State private var controllers = Int(lamp_apple_controllers())
    @State private var left: (start: CGPoint, now: CGPoint)?
    @State private var right: (start: CGPoint, now: CGPoint)?
    @State private var held: UInt32 = 0
    @State private var touched = false
    private let wanted = lamp_apple_touch_buttons()
    private let reach: CGFloat = 60

    // The kit's bits, as lamp_game.h has them.
    private static let a: UInt32 = 1 << 0, b: UInt32 = 1 << 1, x: UInt32 = 1 << 2, y: UInt32 = 1 << 3
    private static let lb: UInt32 = 1 << 4, rb: UInt32 = 1 << 5, menu: UInt32 = 1 << 6, view: UInt32 = 1 << 7, rstick: UInt32 = 1 << 13

    var body: some View {
        GeometryReader { space in
            ZStack {
                if controllers == 0 || touched {
                    HStack(spacing: 0) {
                        stickArea(isLeft: true)
                        if wanted & Self.rstick != 0 { stickArea(isLeft: false) } else { Color.clear }
                    }
                    faceButtons.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(.trailing, 36).padding(.bottom, 28)
                    topButtons.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).padding(.top, 14)
                } else {
                    // Hidden, but listening: the first touch brings the controls.
                    Color.white.opacity(0.001).onTapGesture { touched = true }
                }
            }
            .frame(width: space.size.width, height: space.size.height)
        }
        .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidConnect)) { _ in
            controllers = Int(lamp_apple_controllers())
            touched = false
            send()
        }
        .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidDisconnect)) { _ in controllers = Int(lamp_apple_controllers()) }
    }

    private func stickArea(isLeft: Bool) -> some View {
        let touch = isLeft ? left : right
        return ZStack {
            Color.white.opacity(0.001)
            if let touch {
                Circle().fill(.white.opacity(0.18)).frame(width: reach * 2, height: reach * 2).position(touch.start)
                Circle().fill(.white.opacity(0.45)).frame(width: 54, height: 54).position(clamped(touch))
            } else if isLeft {
                Circle().strokeBorder(.white.opacity(0.25), lineWidth: 2).frame(width: reach * 2, height: reach * 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).padding(.leading, 40).padding(.bottom, 32)
            }
        }
        .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
            let now = (start: drag.startLocation, now: drag.location)
            if isLeft { left = now } else { right = now }
            send()
        }.onEnded { _ in
            if isLeft { left = nil } else { right = nil }
            send()
        })
    }

    private func clamped(_ touch: (start: CGPoint, now: CGPoint)) -> CGPoint {
        let dx = touch.now.x - touch.start.x, dy = touch.now.y - touch.start.y
        let length = max(1, (dx * dx + dy * dy).squareRoot())
        let scale = min(1, reach / length)
        return CGPoint(x: touch.start.x + dx * scale, y: touch.start.y + dy * scale)
    }

    private func axes(_ touch: (start: CGPoint, now: CGPoint)?) -> (Float, Float) {
        guard let touch else { return (0, 0) }
        let point = clamped(touch)
        return (Float((point.x - touch.start.x) / reach), Float(-(point.y - touch.start.y) / reach))
    }

    private var faceButtons: some View {
        // As on a controller: Y at the top, A at the bottom, X left and B right, only those the game uses.
        VStack(spacing: 8) {
            button(Self.y, "Y")
            HStack(spacing: 44) { button(Self.x, "X"); button(Self.b, "B") }
            button(Self.a, "A")
        }
    }

    private var topButtons: some View {
        HStack(spacing: 12) {
            button(Self.lb, "LB", small: true)
            button(Self.view, "⧉", small: true)
            Spacer()
            button(Self.menu, "≡", small: true)
            button(Self.rb, "RB", small: true)
        }
        .padding(.horizontal, 28)
    }

    @ViewBuilder private func button(_ bit: UInt32, _ title: String, small: Bool = false) -> some View {
        let size: CGFloat = small ? 40 : 58
        if wanted & bit != 0 {
            Text(title)
                .font(.system(size: small ? 15 : 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Circle().fill(.white.opacity(held & bit != 0 ? 0.5 : 0.22)))
                .gesture(DragGesture(minimumDistance: 0).onChanged { _ in
                    guard held & bit == 0 else { return }
                    held |= bit; send()
                }.onEnded { _ in held &= ~bit; send() })
        } else {
            Color.clear.frame(width: size, height: size)
        }
    }

    private func send() {
        let (lx, ly) = axes(left), (rx, ry) = axes(right)
        lamp_apple_touch(lx, ly, rx, ry, held)
    }
}
#endif
