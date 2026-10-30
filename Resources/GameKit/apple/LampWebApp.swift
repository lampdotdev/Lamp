// Lamp's common app around a page, on the Mac, the iPhone and the iPad: a window (or the whole screen) that is the
// page in Web/, shown in a web view of its own by LampPage.swift. Lamp writes this file before every build.
//
// The page is served at {{PAGE_SCHEME}}://app/, the app's own address for good. A page laid out at a fixed size of its own
// is zoomed to fill the window or screen; one that isn't is laid out at the window's size, as a browser would. A change
// of the page goes in while the app is open (`LampPageLive`): the page opens again with what it saved.
import SwiftUI
import WebKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@main
struct LampWebApp: SwiftUI.App {
    var body: some SwiftUI.Scene {
        WindowGroup("{{NAME}}") {
            LampWebAppView()
                .ignoresSafeArea()
                #if os(macOS)
                .frame(minWidth: 480, minHeight: 270)
                #else
                .statusBarHidden()
                .persistentSystemOverlays(.hidden)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1280, height: 720)
        .commands { LampCommands() }
        #endif
    }
}

@MainActor enum LampWebAppPage {
    static let files = LampPageFiles(scheme: "{{PAGE_SCHEME}}")
    static func make() -> WKWebView { LampPageView.make(files, live: true) }
    /// The size the page is laid out at, or nil for the window's.
    static let canvas: CGSize? = {{PAGE_CANVAS}}
}

struct LampWebAppView: View {
    var body: some View {
        GeometryReader { space in
            ZStack {
                Color.black
                LampWebAppSurface(size: space.size)
            }
        }
    }
}

#if os(macOS)
struct LampWebAppSurface: NSViewRepresentable {
    let size: CGSize
    func makeNSView(context: Context) -> WKWebView { LampWebAppPage.make() }
    func updateNSView(_ view: WKWebView, context: Context) {
        LampPageView.fit(view, in: size, canvas: LampWebAppPage.canvas)
        DispatchQueue.main.async { if view.window?.firstResponder !== view { view.window?.makeFirstResponder(view) } }
    }
}
#else
struct LampWebAppSurface: UIViewRepresentable {
    let size: CGSize
    func makeUIView(context: Context) -> WKWebView { LampWebAppPage.make() }
    func updateUIView(_ view: WKWebView, context: Context) { LampPageView.fit(view, in: size, canvas: LampWebAppPage.canvas) }
}
#endif
