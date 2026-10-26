// Takes a picture of one window of a running app, wherever it is and whatever covers it, without bringing it to the
// front or touching the mouse or keyboard: how a change is looked at while other work goes on on the same screen.
//   swift scripts/window-shot.swift <pid>                      lists the app's windows (id and title)
//   swift scripts/window-shot.swift <pid> <title> <out.png>    the first window whose title contains <title>
import CoreGraphics
import Foundation

let arguments = CommandLine.arguments.dropFirst()
guard let pid = arguments.first.flatMap(Int32.init) else {
    FileHandle.standardError.write("usage: window-shot.swift <pid> [<title> <out.png>]\n".data(using: .utf8)!)
    exit(2)
}
// Without Screen & System Audio Recording for whatever runs this (the terminal, or the agent's host), macOS hides other
// apps' window titles and pictures, and listing them asks for nothing: say so, rather than find no window by its title.
guard CGPreflightScreenCaptureAccess() else {
    FileHandle.standardError.write("""
        This needs Screen & System Audio Recording for the app running it (System Settings → Privacy & Security), \
        which macOS hasn't given. Once it's on, quit and reopen that app, then run this again.

        """.data(using: .utf8)!)
    exit(3)
}
let all = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
// Only the app's own ordinary windows with a size: menus, tooltips and off-screen helpers are on other layers.
let windows = all.filter {
    ($0[kCGWindowOwnerPID as String] as? Int32) == pid && ($0[kCGWindowLayer as String] as? Int) == 0
        && (($0[kCGWindowBounds as String] as? [String: Double])?["Width"] ?? 0) > 1
}
let rest = Array(arguments.dropFirst())
guard rest.count == 2 else {
    for window in windows { print(window[kCGWindowNumber as String] ?? "", window[kCGWindowName as String] ?? "") }
    exit(0)
}
guard let window = windows.first(where: { ($0[kCGWindowName as String] as? String ?? "").localizedCaseInsensitiveContains(rest[0]) }),
      let id = window[kCGWindowNumber as String] as? Int else {
    FileHandle.standardError.write("no window of \(pid) titled \"\(rest[0])\"\n".data(using: .utf8)!)
    exit(1)
}
let capture = Process()
capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
capture.arguments = ["-x", "-o", "-l", String(id), rest[1]]
try capture.run()
capture.waitUntilExit()
exit(capture.terminationStatus)
