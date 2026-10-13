import Foundation

/// Runs an iPhone app in Apple's iOS Simulator: the app is built for the Simulator (build.sh), installed
/// into a booted iPhone, launched with its output going to the app's log, and photographed on request.
/// Needs Xcode (the Simulator and its iOS runtime come with it), not just the Command Line Tools.
enum Simulator {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Whether Xcode and a simulator of the kind are on this Mac, with a plain message when not.
    static func problem(_ family: DeviceFamily = .iphone) -> String? {
        PhoneTools.checked(family: family, useCache: true).issue?.message
    }

    /// The apps Lamp makes need this iOS (the scaffold's deployment target), so only simulators that run it count.
    static let minimumIOS = PhoneTools.minimumIOS

    /// The iPhone (or iPad) to use: one that's already booted, else the newest available, among those on a
    /// runtime the apps can run on. Sorted by name after the runtime, so the choice is the same every time.
    static func device(_ family: DeviceFamily = .iphone) -> String? {
        let listing = Subprocess.runBlocking("/usr/bin/xcrun", ["simctl", "list", "devices", "available", "-j"], mergeErrors: false, timeout: 30).output
        return device(family, listing: listing)
    }

    /// Shared with the prerequisite check, so a passed check selects the same simulator as a build.
    static func device(_ family: DeviceFamily, listing: String) -> String? {
        guard let data = listing.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devices = json["devices"] as? [String: [[String: Any]]] else { return nil }
        // Runtime keys look like com.apple.CoreSimulator.SimRuntime.iOS-18-6.
        typealias Candidate = (version: Int, name: String, booted: Bool, udid: String)
        var candidates: [Candidate] = []
        for (runtime, list) in devices {
            guard let range = runtime.range(of: "SimRuntime.iOS-"),
                  let major = Int(runtime[range.upperBound...].split(separator: "-").first ?? ""), major >= minimumIOS else { continue }
            for device in list {
                guard let name = device["name"] as? String, name.hasPrefix(family.name), let udid = device["udid"] as? String else { continue }
                candidates.append((major, name, device["state"] as? String == "Booted", udid))
            }
        }
        let ordered = candidates.sorted { ($0.booted ? 1 : 0, $0.version, $0.name) > ($1.booted ? 1 : 0, $1.version, $1.name) }
        return ordered.first?.udid
    }

    /// Boots the iPhone (a no-op when it already is) and opens the Simulator app so the user can see it.
    static func boot(_ udid: String, show: Bool) async throws {
        _ = await Subprocess.run("/usr/bin/xcrun", ["simctl", "boot", udid], timeout: 60)   // "already booted" is fine
        let status = await Subprocess.run("/usr/bin/xcrun", ["simctl", "bootstatus", udid, "-b"], timeout: 120)
        guard status.ok else { throw Failure(message: "The iPhone simulator didn't start.") }
        if show { await self.show(udid) }
    }

    static func install(_ app: URL, on udid: String) async throws {
        let result = await Subprocess.run("/usr/bin/xcrun", ["simctl", "install", udid, app.path], timeout: 120)
        guard result.ok else { throw Failure(message: "Couldn't put the app on the simulator: \(result.output.trimmed)") }
    }

    /// Launches the app with its output going to `log`. Returns its process id.
    static func launch(_ bundleID: String, on udid: String, log: URL) async throws -> Int32 {
        let result = await Subprocess.run("/usr/bin/xcrun", ["simctl", "launch", "--stdout=\(log.path)", "--stderr=\(log.path)", udid, bundleID],
                                          mergeErrors: false, timeout: 60)
        // "bundle.id: 12345"
        guard result.ok, let pid = result.output.split(separator: ":").last.flatMap({ Int32(String($0).trimmed) }) else {
            throw Failure(message: "The app didn't launch: \(result.errors.trimmed)")
        }
        return pid
    }

    static func terminate(_ bundleID: String, on udid: String) async {
        _ = await Subprocess.run("/usr/bin/xcrun", ["simctl", "terminate", udid, bundleID], timeout: 30)
    }

    /// Whether the launched app is still running (it crashed if not).
    static func isRunning(pid: Int32) -> Bool { kill(pid, 0) == 0 }

    /// A picture of the iPhone's screen, at the screen's size in points rather than pixels: smaller for the
    /// model to look at, and a pixel in it is a point on the screen, so the agent's aim needs no scaling.
    static func screenshot(on udid: String, to file: URL) async -> Bool {
        guard await Subprocess.run("/usr/bin/xcrun", ["simctl", "io", udid, "screenshot", "--type=png", file.path], timeout: 30).ok else { return false }
        if let scale = Double((await Subprocess.run("/usr/bin/xcrun", ["simctl", "getenv", udid, "SIMULATOR_MAINSCREEN_SCALE"], timeout: 20)).output.trimmed),
           let width = Double((await Subprocess.run("/usr/bin/xcrun", ["simctl", "getenv", udid, "SIMULATOR_MAINSCREEN_WIDTH"], timeout: 20)).output.trimmed),
           scale > 1 {
            _ = await Subprocess.run("/usr/bin/sips", ["--resampleWidth", String(Int(width / scale)), file.path], timeout: 30)
        }
        return true
    }

    /// The app that puts simulators on the Mac's screen: Simulator, or Device Hub, which took its place in
    /// Xcode 27. Both show the iPhone's screen and its accessibility tree the same way.
    static let viewers = ["com.apple.iphonesimulator", "com.apple.dt.Devices"]

    /// Where that app is in this Xcode, given its Developer folder (found by the readiness check too).
    static func viewer(in developer: String) -> URL? { PhoneTools.viewer(in: developer) }

    /// Brings the simulator's window to the front, showing this iPhone when the app shows one device at a time.
    static func show(_ udid: String? = nil) async {
        guard await open(inFront: true) else { return }
        if let udid { await Driver.choose(udid) }
    }

    /// Opens that app, in front or behind whatever the person is doing. False when this Xcode has none.
    static func open(inFront: Bool) async -> Bool {
        guard let developer = PhoneTools.discover(), let viewer = viewer(in: developer) else { return false }
        return await Subprocess.run("/usr/bin/open", (inFront ? [] : ["-g"]) + [viewer.path], timeout: 30).ok
    }

    /// What the person knows that app as, for telling them or the agent about it.
    static func viewerName(oneAtATime: Bool) -> String { oneAtATime ? "Device Hub" : "Simulator" }

    /// The same, before it's running: by which of the two this Xcode has.
    static func viewerName() -> String {
        viewerName(oneAtATime: PhoneTools.discover().flatMap(viewer(in:))?.lastPathComponent == "DeviceHub.app")
    }
}

// MARK: - Driving the simulator

import AppKit

/// Where another app's accessibility tree is read: one queue of Lamp's own, never the main thread. Each
/// read is a message to that app and waits for its answer, so a busy or stuck Device Hub would otherwise
/// hold up Lamp's own windows for as long as it took.
@globalActor
actor AccessibilityActor {
    static let shared = AccessibilityActor()
    private static let queue = DispatchSerialQueue(label: "dev.lamp.accessibility", qos: .userInitiated)
    nonisolated var unownedExecutor: UnownedSerialExecutor { Self.queue.asUnownedSerialExecutor() }
}

extension Simulator {
    /// Uses the app in the simulator the way a person would, for the agent's `use_app`. The Simulator app on
    /// the Mac shows the iPhone's whole accessibility tree through the Mac's accessibility system, so Lamp
    /// finds what's under a point, taps it, fills in fields and reads what things are, the same way the Mac
    /// apps' own driver does inside them. Gestures (swipes, scrolls) are real mouse events sent to the
    /// Simulator; Device Hub passes none of those on, so there they are the actions the iPhone's own
    /// elements offer, and what has no such action is refused with the reason. The same tree, read whole, is the screen as text that follows every look and use
    /// (`screenText`). This needs Lamp to be allowed to control the computer (System Settings → Privacy &
    /// Security → Accessibility); the first use asks.
    ///
    /// It is another app's window being driven, so nothing here may wait on it without a limit: every call
    /// to it gives up after `patience`, and once one has, the rest are skipped for a moment (`notAnswering`)
    /// rather than each waiting its turn to time out.
    @AccessibilityActor
    enum Driver {
        struct Action: Decodable, Sendable {
            let action: String
            var target: String?       // what to act on: an id ("b2") or exact name from the screen as text
            var x: Double?
            var y: Double?
            var text: String?
            var key: String?
            var item: String?
            var amount: Double?
            var direction: String?
        }

        nonisolated static var isAllowed: Bool { AXIsProcessTrusted() }

        /// Takes the person to the Accessibility list with Lamp to drag into it (`SettingsGuide`), and brings
        /// Lamp back to the front once it's allowed. Asking again brings the list and Lamp's place in it back.
        nonisolated static func ask() {
            Task { @MainActor in
                if await SettingsGuide.ask(.accessibility, isOn: { AXIsProcessTrusted() }) {
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }

        /// The simulated iPhone's screen as the Mac sees it: the Simulator's accessibility app element, the
        /// screen's origin on the Mac's display, and the device's pixel scale, for turning picture pixels
        /// into points on screen.
        struct Screen: @unchecked Sendable {
            let app: AXUIElement
            let window: AXUIElement     // the one Simulator window showing this device: lookups stay inside it
            let box: AXUIElement        // the screen itself in that window; `rect` is where it was when found
            let rect: CGRect            // the device's screen on the Mac's display
            let udid: String
            let owner: String           // the project and launch these actions are for; remembered fields are theirs
            let scale: Double           // the device's pixels per point
            let zoom: Double            // how big the Simulator draws a point on the Mac's display (its window scale)
            let pid: pid_t
            var title = ""              // the window's title when found: "<device> – <runtime>"
            var oneAtATime = false      // Device Hub: one window for whichever device is chosen in its list
            var origin: CGPoint { rect.origin }
            /// What the person calls the app showing it.
            var viewer: String { Simulator.viewerName(oneAtATime: oneAtATime) }
            /// Pictures are made at point size (`screenshot`), so a pixel in them is a point on the device, which
            /// the Simulator shows `zoom` times as large.
            func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: origin.x + x * zoom, y: origin.y + y * zoom) }
        }

        /// Why the iPhone's screen can't be read or tapped just now. Each is its own case because each has
        /// its own remedy, and the agent is told the one that happened.
        enum Trouble: Error, Equatable {
            case locked             // the Mac's screen is locked: no window can be read or tapped
            case notOpen            // the app that shows simulators isn't running, and didn't open
            case notAnswering       // it's running but not answering accessibility calls
            case noDevice           // the simulator itself couldn't be asked about its screen
            case notListed          // Device Hub has no row for this device, or wouldn't select it
            case noWindow           // no window is showing this device
            case connecting         // the window is this device's, but its screen isn't up in it yet
            case unclear            // more than one thing could be the screen: no guessing

            /// For the agent: what's wrong, that nothing was touched, and what to do. `viewer` is the app this
            /// Xcode has (Simulator, or Device Hub from Xcode 27) and `device` what's being tried (iPhone, iPad).
            func message(viewer: String, device: String) -> String {
                switch self {
                case .locked:
                    "The Mac's screen is locked, and \(viewer)'s window can't be read or tapped while it is. Nothing was tapped. " +
                        "Go by the picture from look_at_app, and tell the user in plain words that trying the app by hand has to wait until the Mac is unlocked."
                case .notOpen:
                    "\(viewer), the app from Xcode that shows the \(device), isn't open, and Lamp couldn't open it. Nothing was tapped. " +
                        "Tell the user in plain words that \(viewer) needs to be open, and try again once they say it is."
                case .notAnswering:
                    "\(viewer) is open but isn't answering Lamp (it's busy or stuck), so nothing was tapped. Try once more; " +
                        "if it still isn't answering, tell the user in plain words that \(viewer) seems stuck and may need quitting and opening again."
                case .noDevice:
                    "Lamp couldn't ask the \(device) simulator about its screen, so nothing was tapped. Call look_at_app, which opens the app again, then try again."
                case .notListed:
                    "\(viewer) is open but this \(device) simulator isn't in its list of devices (it lists the ones added to it, not every one running), " +
                        "so Lamp can't bring up its screen. Nothing was tapped. Tell the user in plain words that the \(device) simulator " +
                        "needs adding to \(viewer) with the + button above its list, and try again once they say it's there."
                case .noWindow:
                    "\(viewer) is open but has no window showing this \(device). Nothing was tapped. " +
                        "Call look_at_app and try again; if it's the same, tell the user in plain words that \(viewer) isn't showing their \(device)."
                case .connecting:
                    "\(viewer) has this \(device) up but is still connecting to its screen, so there's nothing to tap yet. Nothing was tapped. " +
                        "Try again once; if it's the same, \(viewer) has lost the \(device)'s screen (it does after the simulator restarts): tell the user " +
                        "in plain words to click another device in \(viewer)'s list and then the \(device) again, and try again once they have."
                case .unclear:
                    "Lamp found more than one thing in \(viewer)'s window that could be the \(device)'s screen, and won't guess which. Nothing was tapped. " +
                        "Go by the picture from look_at_app, and tell the user in plain words that you could look at the app but not use it this time."
                }
            }
        }

        // MARK: Not waiting on a stuck app

        /// The longest one call to the other app may take. A screen's whole tree is read in a fifth of a
        /// second, so an answer this late isn't coming.
        nonisolated static var patience: TimeInterval { 2 }

        /// Until when the other app is taken as not answering: a short while after a call to it timed out.
        private static var silentUntil = Date.distantPast
        private static var hurried = false

        /// Whether a call to the other app just timed out. While it is true nothing more is asked of it.
        static var notAnswering: Bool { Date() < silentUntil }

        /// Makes every call give up after `patience` instead of the system's six seconds. It is set for all
        /// of Lamp's accessibility calls, which are only the ones here.
        private static func hurry() {
            guard !hurried else { return }
            hurried = true
            AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), Float(patience))
        }

        /// One call to the other app. Skipped while it isn't answering; and a call that fails only after
        /// the whole wait is what a stuck app looks like (one that has quit fails at once).
        static func call(_ body: () -> AXError) -> AXError {
            guard !notAnswering else { return .cannotComplete }
            hurry()
            let began = Date()
            let result = body()
            if result == .cannotComplete, Date().timeIntervalSince(began) > patience * 0.75 { silentUntil = Date().addingTimeInterval(patience) }
            return result
        }

        // MARK: Finding the screen

        static func screen(of udid: String, owner: String) async -> Result<Screen, Trouble> {
            // Behind a locked screen every window reads as empty, which would pass for a device that isn't listed.
            guard !isLocked else { return .failure(.locked) }
            var found = viewer()
            if found == nil {
                // A look in the background never opened it: Lamp does, behind whatever the person is doing.
                guard await Simulator.open(inFront: false) else { return .failure(.notOpen) }
                for _ in 0..<40 where found == nil {
                    try? await Task.sleep(for: .milliseconds(250))
                    found = viewer()
                }
            }
            guard let (pid, oneAtATime) = found else { return .failure(.notOpen) }
            let width = Double((await Subprocess.run("/usr/bin/xcrun", ["simctl", "getenv", udid, "SIMULATOR_MAINSCREEN_WIDTH"], timeout: 20)).output.trimmed) ?? 0
            let height = Double((await Subprocess.run("/usr/bin/xcrun", ["simctl", "getenv", udid, "SIMULATOR_MAINSCREEN_HEIGHT"], timeout: 20)).output.trimmed) ?? 0
            let scale = Double((await Subprocess.run("/usr/bin/xcrun", ["simctl", "getenv", udid, "SIMULATOR_MAINSCREEN_SCALE"], timeout: 20)).output.trimmed) ?? 0
            guard width > 0, height > 0, scale > 0 else { return .failure(.noDevice) }
            let app = AXUIElementCreateApplication(pid)
            // Each window is titled "<device> – <runtime>", which is the whole identity it shows: the one
            // window with exactly this device's title, and none when two devices share it.
            guard let expected = deviceTitle(udid) else { return .failure(.noDevice) }
            // Device Hub writes an iPad's system as iPadOS where simctl says iOS, and there the device is
            // chosen by its identifier anyway: its window has only to carry the device's name.
            let name = expected.components(separatedBy: " – ")[0] + " – "
            func titled() -> [AXUIElement] {
                (attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []).filter {
                    guard let title = attribute($0, kAXTitleAttribute) as? String else { return false }
                    return oneAtATime ? title.hasPrefix(name) : title == expected
                }
            }
            var windows = titled()
            // Device Hub has one window for whichever device is chosen in its list: choose this one. Always
            // by its identifier, since a title alone could be another device of the same name and runtime.
            if oneAtATime {
                // Just opened, or the device just booted: its row takes a moment to arrive.
                var row = row(for: udid, in: app)
                for _ in 0..<20 where row == nil && !notAnswering {
                    try? await Task.sleep(for: .milliseconds(250))
                    row = self.row(for: udid, in: app)
                }
                guard let row else { return .failure(notAnswering ? .notAnswering : .notListed) }
                let already = isSelected(row)
                guard already || select(row) else { return .failure(notAnswering ? .notAnswering : .notListed) }
                if !already { windows = [] }   // what was there showed the device chosen before
                for _ in 0..<15 where windows.isEmpty && !notAnswering {
                    try? await Task.sleep(for: .milliseconds(200))
                    windows = titled()
                }
            }
            guard !notAnswering else { return .failure(.notAnswering) }
            guard let window = windows.first else { return .failure(.noWindow) }
            guard windows.count == 1 else { return .failure(.unclear) }
            let title = attribute(window, kAXTitleAttribute) as? String ?? expected
            let points = CGSize(width: width / scale, height: height / scale)
            // The screen arrives after the window does: Device Hub says it's connecting the display first.
            var boxes = screenBoxes(in: window, shaped: points, marked: oneAtATime)
            for _ in 0..<40 where boxes.isEmpty && !notAnswering {
                try? await Task.sleep(for: .milliseconds(200))
                boxes = screenBoxes(in: window, shaped: points, marked: oneAtATime)
            }
            guard !notAnswering else { return .failure(.notAnswering) }
            guard let box = boxes.first else { return .failure(.connecting) }
            // The same screen can be in the tree twice, in one place; two places is one too many to tap on.
            guard Self.places(boxes.map(\.rect)) == 1 else { return .failure(.unclear) }
            return .success(Screen(app: app, window: window, box: box.element, rect: box.rect, udid: udid, owner: owner, scale: scale,
                                   zoom: box.rect.width / points.width, pid: pid, title: title, oneAtATime: oneAtATime))
        }

        nonisolated static var isLocked: Bool {
            (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
        }

        /// Whether the window still shows this device, where it did.
        static func shows(_ screen: Screen) -> Bool { lost(screen) == nil }

        /// Why nothing more may be tapped or read on this screen, if so. Device Hub's one window goes to
        /// whichever device is chosen next (by the person, or by Lamp for another app), and what was this
        /// iPhone's screen is then another's; a window that was moved or resized has the screen somewhere
        /// else than the points were worked out for.
        static func lost(_ screen: Screen) -> String? {
            let title = attribute(screen.window, kAXTitleAttribute) as? String
            let chosen = !screen.oneAtATime || isChosen(screen.udid, in: screen.app)
            let rect = frame(of: screen.box)
            if isLocked { return "the Mac's screen was locked, and nothing can be tapped or read while it is." }
            if notAnswering { return "\(screen.viewer) stopped answering Lamp. Try once more; if it still isn't answering, tell the user it seems stuck." }
            guard title == screen.title, chosen else { return "the simulator is showing another device now. Call look_at_app to bring this one back." }
            guard rect == screen.rect else { return "\(screen.viewer)'s window was moved or resized, so the points no longer line up. Call use_app again." }
            return nil
        }

        /// A rectangle the shape of a device's screen, however large it's drawn: the window can be zoomed.
        nonisolated static func isShaped(_ rect: CGRect, like points: CGSize) -> Bool {
            rect.width > 50 && rect.height > 50 && abs(rect.width / rect.height - points.width / points.height) < 0.02
        }

        /// How many different places a list of candidates for the screen are in. The tree can hold the one
        /// screen more than once, each time with the same frame.
        nonisolated static func places(_ rects: [CGRect]) -> Int {
            rects.reduce(into: [CGRect]()) { seen, rect in
                if !seen.contains(where: { abs($0.minX - rect.minX) < 1 && abs($0.minY - rect.minY) < 1 && abs($0.width - rect.width) < 1 && abs($0.height - rect.height) < 1 }) { seen.append(rect) }
            }.count
        }

        /// What Device Hub calls the group holding a device's screen (its accessibility subrole). Apple
        /// doesn't document it; it is what there is beyond shape, and when it goes the screen isn't found
        /// and `use_app` says so, rather than something else of the right shape being tapped.
        nonisolated static var screenMark: String { "iOSContentGroup" }

        /// Everything in the window that could be the device's screen: a group shaped like it, and in
        /// Device Hub (`marked`) also marked as a device's content. Simulator has it at the top of its window
        /// and Device Hub a few layers down, so the window is searched; not inside a match, where the app's
        /// own full-screen views have the same shape.
        private static func screenBoxes(in window: AXUIElement, shaped points: CGSize, marked: Bool) -> [(element: AXUIElement, rect: CGRect)] {
            var matches: [(element: AXUIElement, rect: CGRect)] = []
            let limit = Date().addingTimeInterval(readLimit)
            func visit(_ element: AXUIElement, depth: Int) {
                for child in children(element) where Date() < limit {
                    let rect = frame(of: child)
                    let shaped = attribute(child, kAXRoleAttribute) as? String == kAXGroupRole && isShaped(rect, like: points)
                    if shaped, !marked || attribute(child, kAXSubroleAttribute) as? String == screenMark {
                        matches.append((child, rect))
                    } else if depth < 8, rect.width > 50, rect.height > 50 {
                        // Device Hub wraps the marked group in an unmarked one of the same shape: looked into.
                        visit(child, depth: depth + 1)
                    }
                }
            }
            visit(window, depth: 0)
            return matches
        }

        /// The process showing simulators on screen (Simulator.viewers), if it's running.
        private static func viewer() -> (pid: pid_t, oneAtATime: Bool)? {
            for id in Simulator.viewers {
                guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first else { continue }
                let oneAtATime = id != Simulator.viewers[0]
                if app.processIdentifier > 0 { return (app.processIdentifier, oneAtATime) }
                // Device Hub can be listed without its process id; its windows still say whose they are.
                let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
                let pids = Set(windows.filter { $0[kCGWindowOwnerName as String] as? String == app.localizedName }
                    .compactMap { $0[kCGWindowOwnerPID as String] as? pid_t })
                if let pid = pids.first(where: { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier == id }) { return (pid, oneAtATime) }
            }
            return nil
        }

        /// Has Device Hub show this simulator: it shows one device at a time, the one chosen in its list,
        /// where each row carries its device's identifier. Simulator needs none of this (every booted device
        /// has a window), and without the permission to control the computer the list is left as it is.
        static func choose(_ udid: String) async {
            guard isAllowed else { return }
            // Just opened: its window takes a moment to arrive.
            for _ in 0..<15 where !notAnswering {
                if let pid = viewer()?.pid, let row = row(for: udid, in: AXUIElementCreateApplication(pid)), isSelected(row) || select(row) { return }
                if NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.iphonesimulator").first != nil { return }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }

        private static func isSelected(_ row: AXUIElement) -> Bool { (attribute(row, kAXSelectedAttribute) as? Bool) == true }

        private static func select(_ row: AXUIElement) -> Bool {
            call { AXUIElementSetAttributeValue(row, kAXSelectedAttribute as CFString, kCFBooleanTrue) } == .success
        }

        private static func isChosen(_ udid: String, in app: AXUIElement) -> Bool {
            row(for: udid, in: app).map(isSelected) ?? false
        }

        /// The device's row in Device Hub's list: the one something in it names with the device's identifier.
        private static func row(for udid: String, in app: AXUIElement) -> AXUIElement? {
            func names(_ element: AXUIElement, depth: Int) -> Bool {
                if (attribute(element, kAXIdentifierAttribute) as? String)?.hasSuffix(udid) == true { return true }
                return depth < 4 && children(element).contains { names($0, depth: depth + 1) }
            }
            func row(in element: AXUIElement, depth: Int) -> AXUIElement? {
                if attribute(element, kAXRoleAttribute) as? String == kAXRowRole { return names(element, depth: 0) ? element : nil }
                guard depth < 12 else { return nil }
                for child in children(element) { if let found = row(in: child, depth: depth + 1) { return found } }
                return nil
            }
            for window in attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? [] {
                if let found = row(in: window, depth: 0) { return found }
            }
            return nil
        }

        /// Carries out the actions in order and says what each one did, like the Mac apps' driver. `live` is
        /// asked before every action: when the turn was stopped, the app deleted or the app gone, the rest of
        /// the batch is dropped rather than carried out on whatever the simulator shows next.
        static func perform(_ actions: [Action], on screen: Screen, picture: URL, live: @MainActor @Sendable () -> Bool) async -> String {
            var lines: [String] = []
            var before = try? Data(contentsOf: picture)
            // Asked again after every wait inside an action too: the screen has to be this iPhone's each time.
            // The turn last: reading the screen takes a moment, and Stop may come during it.
            func here() async -> Bool {
                guard shows(screen) else { return false }
                return await live()
            }
            for action in actions {
                guard await live() else {
                    lines.append("stopped before the rest: the app was stopped, deleted or closed")
                    break
                }
                if let reason = lost(screen) {
                    lines.append("stopped before the rest: " + reason)
                    break
                }
                lines.append(await carryOut(action, on: screen, live: here))
                // An action that ran into a stuck app found nothing where there was something: say which it was.
                if notAnswering {
                    lines[lines.count - 1] += " (\(screen.viewer) stopped answering Lamp during this, so it may not have happened; look at the picture)"
                }
                try? await Task.sleep(for: .milliseconds(350))
                _ = await Simulator.screenshot(on: screen.udid, to: picture)
                let after = try? Data(contentsOf: picture)
                if action.action != "wait", let before, let after, before == after { lines[lines.count - 1] += " (nothing changed on screen)" }
                before = after
            }
            return lines.joined(separator: "\n")
        }

        /// The app was relaunched: whatever field was remembered for the project is gone.
        static func forget(_ projectID: String) { lastFields = lastFields.filter { !$0.key.hasPrefix(projectID + ":") } }

        private static func carryOut(_ action: Action, on screen: Screen, live: () async -> Bool) async -> String {
            // What the action names is found in the screen as text, and acted on at its middle: on an iPhone
            // everything takes a tap, so the point is the action.
            var action = action
            if let target = action.target?.trimmed, !target.isEmpty {
                guard let items = items(on: screen) else { return "\(action.action) \"\(target)\": " + unread(screen) }
                switch find(target, in: items) {
                case .one(let index):
                    action.x = items[index].frame.midX
                    action.y = items[index].frame.midY
                case .none:
                    return "\(action.action) \"\(target)\": nothing on the screen is called that. Use an id or exact name from the " +
                        "screen as text, or x and y for what isn't listed there."
                case .several(let ids):
                    return "\(action.action) \"\(target)\": several things are called that (\(ids.joined(separator: ", "))). Use one of their ids."
                }
            }
            let at = "\(Int(action.x ?? 0)), \(Int(action.y ?? 0))"
            let point = screen.point(action.x ?? 0, action.y ?? 0)
            switch action.action {
            case "click", "double_click", "right_click":
                guard let hit = element(at: point, in: screen) else { return "\(action.action) at \(at): nothing there" }
                // A tap that lands beside a control (on its label, say) is meant for the control.
                let element = isInteractive(hit) ? hit : (nearestInteractive(to: point, in: screen) ?? hit)
                lastFields[screen.owner] = isTextInput(element) ? element : nil
                let name = describe(element) + (element == hit ? "" : " (the nearest thing to tap; the point itself was \(describe(hit)))")
                // Finding the target took a moment off the main thread, and Stop may have come meanwhile.
                guard await live() else { return "stopped before the \(action.action == "right_click" ? "long press" : "tap") at \(at)" }
                if action.action == "right_click" {
                    guard !screen.oneAtATime else {
                        return "long press at \(at): not done (it was aimed at \(name)). Device Hub doesn't pass a held finger on to the device. " +
                            "Check what a long press should do some other way, or say to the user that you couldn't try it."
                    }
                    // A long press: the finger held down, which opens context menus and the like.
                    mouse(.leftMouseDown, at: point, pid: screen.pid)
                    try? await Task.sleep(for: .milliseconds(800))
                    mouse(.leftMouseUp, at: point, pid: screen.pid)   // the finger comes up whatever happened meanwhile
                    return "long press at \(at): \(name)"
                }
                let pressed = press(element)
                if !pressed {
                    // Not everything takes a press through accessibility: a real tap then, where one arrives.
                    guard !screen.oneAtATime, !notAnswering else { return "\(action.action) at \(at): \(name) didn't take the tap" }
                    mouse(.leftMouseDown, at: point, pid: screen.pid); mouse(.leftMouseUp, at: point, pid: screen.pid)
                }
                if action.action == "double_click" {
                    try? await Task.sleep(for: .milliseconds(80))
                    if await live() { _ = press(element) }
                }
                return "\(action.action == "double_click" ? "double tap" : "tap") at \(at): \(name)"
            case "type":
                guard let text = action.text else { return "type: no text given" }
                // The field with the keyboard is the one last tapped; the bridge doesn't say which has focus,
                // so the text goes to the text field under the point given, or the one tapped last.
                guard let field = rememberedField(in: screen) ?? textField(near: point, in: screen) ?? onlyTextField(in: screen) else {
                    return "typed nothing: tap a text field first, then type"
                }
                // The text replaces what the field holds: a tapped field on an iPhone shows its old value
                // formatted ("0.00"), and typing after it would make nonsense of a number.
                guard await live() else { return "stopped before typing" }
                let result = call { AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, text as CFTypeRef) }
                return result == .success ? "typed \"\(text)\" into \(describe(field)); it now holds that" : "couldn't type into \(describe(field))"
            case "key":
                let key = (action.key ?? "").lowercased()
                guard key == "return" || key == "enter" || key == "escape" || key == "esc" else {
                    return "key \(action.key ?? ""): an iPhone has no such key; tap, type, scroll or swipe instead"
                }
                if screen.oneAtATime {
                    // Device Hub passes keys on only once a person has clicked in the device, so return is
                    // the keyboard's own key on the iPhone's screen, and escape has no such key.
                    guard key.hasPrefix("ret") || key == "enter" else {
                        return "key escape: not done. An iPhone has no escape key and Device Hub doesn't pass one on; tap the button that cancels or closes instead."
                    }
                    // The keyboard slides up a moment after the field is tapped.
                    var returnKey = returnKey(in: screen)
                    for _ in 0..<6 where returnKey == nil && !notAnswering {
                        try? await Task.sleep(for: .milliseconds(250))
                        returnKey = self.returnKey(in: screen)
                    }
                    guard await live() else { return "stopped before pressing return" }
                    guard let returnKey else {
                        return "key return: not done. The on-screen keyboard isn't showing, or has no return key Lamp knows. Tap a text field first; " +
                            "if it still doesn't show (it hides once a real keyboard has been used in Device Hub), tap the app's own button for this instead."
                    }
                    return press(returnKey) ? "pressed return (the keyboard's \(describe(returnKey)))" : "key return: the keyboard's key didn't take the press"
                }
                // Keys reach the simulated iPhone only while the Simulator is the active app.
                NSRunningApplication(processIdentifier: screen.pid)?.activate()
                try? await Task.sleep(for: .milliseconds(300))
                guard await live() else { return "stopped before pressing \(key)" }
                let code: CGKeyCode = key.hasPrefix("ret") || key == "enter" ? 36 : 53
                CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)?.postToPid(screen.pid)
                CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)?.postToPid(screen.pid)
                return "pressed \(key.hasPrefix("ret") || key == "enter" ? "return" : "escape")"
            case "scroll":
                let amount = action.amount ?? 300
                if screen.oneAtATime {
                    let scroller = scroller(down: amount >= 0, at: point, in: screen)
                    guard await live() else { return "stopped before scrolling at \(at)" }
                    return scroller.map(turnPage) == true ? "scrolled \(amount >= 0 ? "down" : "up") a page at \(at) (Device Hub scrolls a page at a time)"
                        : "scroll at \(at): nothing there scrolls \(amount >= 0 ? "down" : "up")"
                }
                guard await live() else { return "stopped before scrolling at \(at)" }
                swipe(from: point, by: CGVector(dx: 0, dy: -amount * screen.zoom), pid: screen.pid)
                return "scrolled \(amount >= 0 ? "down" : "up") at \(at)"
            case "swipe":
                let direction = action.direction ?? "left"
                if screen.oneAtATime {
                    // Device Hub doesn't pass a dragged finger on. What a swipe is for is still there: a row's
                    // swipe actions are the row's own actions by name, and a swipe up or down is a scroll.
                    if let item = action.item {
                        guard let hit = element(at: point, in: screen) else { return "swipe at \(at): nothing there" }
                        for element in [hit] + ancestors(of: hit) {
                            guard let named = actionNames(element).first(where: { Self.actionName($0)?.caseInsensitiveCompare(item) == .orderedSame }) else { continue }
                            guard await live() else { return "stopped before swiping at \(at)" }
                            let done = call { AXUIElementPerformAction(element, named as CFString) } == .success
                            return done ? "swiped \(direction) at \(at) and tapped \"\(item)\" (\(describe(element))'s own action)" : "swipe at \(at): \"\(item)\" didn't take the tap"
                        }
                        return "swipe at \(at): \(describe(hit)) has no swipe action called \"\(item)\""
                    }
                    if direction == "up" || direction == "down" {
                        let scroller = scroller(down: direction == "up", at: point, in: screen)
                        guard await live() else { return "stopped before swiping at \(at)" }
                        return scroller.map(turnPage) == true ? "swiped \(direction) at \(at) (a page: Device Hub scrolls a page at a time)"
                            : "swipe \(direction) at \(at): nothing there scrolls that way"
                    }
                    return "swipe \(direction) at \(at): not done. Device Hub doesn't pass a sideways swipe on to the device. " +
                        "For a row's swipe action, give its name in item; otherwise tap a control that does the same, or say to the user that you couldn't try it."
                }
                let distance = 220.0 * screen.zoom
                let delta: CGVector = switch direction {
                case "left": CGVector(dx: -distance, dy: 0)
                case "right": CGVector(dx: distance, dy: 0)
                case "up": CGVector(dx: 0, dy: -distance)
                default: CGVector(dx: 0, dy: distance)
                }
                // A button of that name already there (the keyboard has a "delete") isn't what the swipe uncovers.
                let already = action.item.map { buttons(named: $0, in: screen).map(frame) } ?? []
                guard await live() else { return "stopped before swiping at \(at)" }
                swipe(from: point, by: delta, pid: screen.pid)
                if let item = action.item {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard await live() else { return "swiped \(direction) at \(at), then stopped before tapping \"\(item)\"" }
                    // What the swipe uncovered (a row's actions, say): tap the one named.
                    if let button = buttons(named: item, in: screen).first(where: { !already.contains(frame(of: $0)) }) {
                        guard await live() else { return "swiped \(direction) at \(at), then stopped before tapping \"\(item)\"" }
                        _ = press(button)
                        return "swiped \(direction) at \(at) and tapped \"\(item)\""
                    }
                    return "swiped \(direction) at \(at), but nothing called \"\(item)\" appeared"
                }
                return "swiped \(direction) at \(at)"
            case "wait":
                let seconds = min(action.amount ?? 1, 10)
                try? await Task.sleep(for: .seconds(seconds))
                return "waited \(seconds) s"
            default:
                return "\(action.action): not something an iPhone app has; use click, double_click, right_click (a long press), type, key (return or escape), scroll, swipe or wait"
            }
        }

        // MARK: The screen as text

        /// One thing on the iPhone's screen, as its accessibility tree names it. `frame` is in the picture's
        /// pixels (points on the device), so what the agent reads lines up with what it sees and taps.
        struct Item: Equatable, Sendable {
            var role: String
            var label = ""
            var value = ""
            var frame: CGRect
            var selected = false
            var disabled = false
        }

        /// The most things listed: a full screen is a few dozen, and past this the list costs more than it tells.
        nonisolated static var itemLimit: Int { 120 }

        /// The whole screen in words, for the agent to read beside the picture: what's there, what each thing
        /// holds and where to tap it. Nil when the screen shows nothing with a name.
        /// A screen that couldn't be read whole says so in a line instead: half a screen would pass for all of it.
        static func screenText(on screen: Screen) -> String? {
            guard shows(screen) else { return notAnswering ? unread(screen) : nil }
            guard let items = items(on: screen) else { return unread(screen) }
            return text(for: items)
        }

        private static func unread(_ screen: Screen) -> String {
            "The screen as text is missing this time: \(screen.viewer) didn't answer Lamp in time. Go by the picture."
        }

        /// Everything on this device's screen that says something or can be tapped, in the order the screen
        /// reads. Containers with no name of their own are left out, and so is a control's own caption (a
        /// button's text is the button). Nil when the app stopped answering or took too long partway.
        static func items(on screen: Screen) -> [Item]? {
            var found: [Item] = []
            let limit = Date().addingTimeInterval(readLimit)
            let wanted = [kAXRoleAttribute, kAXSubroleAttribute, kAXDescriptionAttribute, kAXTitleAttribute, kAXValueAttribute,
                          kAXPositionAttribute, kAXSizeAttribute, kAXSelectedAttribute, kAXEnabledAttribute, kAXChildrenAttribute]
            func visit(_ element: AXUIElement, depth: Int, under: String) {
                guard depth < 40, found.count < 400, Date() < limit, !notAnswering else { return }
                let read = attributes(element, wanted)
                let role = read[0] as? String ?? "", subrole = read[1] as? String ?? ""
                var origin = CGPoint.zero, size = CGSize.zero
                if let position = read[5] { AXValueGetValue(position as! AXValue, .cgPoint, &origin) }
                if let extent = read[6] { AXValueGetValue(extent as! AXValue, .cgSize, &size) }
                let rect = CGRect(origin: origin, size: size)
                // The rest of the Simulator's window (its own buttons and lists) isn't the iPhone's screen.
                guard rect.isEmpty || screen.rect.intersects(rect) else { return }
                // Listed even with no name: something to tap, or a row of segments, which comes with nothing inside.
                let control = interactiveRoles.contains(role) || role == kAXTabGroupRole
                let (label, value) = naming(control: control, label: (read[2] as? String)?.nilIfEmpty ?? (read[3] as? String) ?? "",
                                            value: read[4].flatMap { $0 as? String ?? ($0 as? NSNumber).map(number) } ?? "")
                var caption = under
                let onScreen = !rect.isEmpty && screen.rect.contains(CGPoint(x: rect.midX, y: rect.midY))
                let named = !label.isEmpty && role != kAXWindowRole
                if onScreen, control || (named && !(label == under && role == kAXStaticTextRole)) {
                    let item = Item(role: subrole == "AXSearchField" || subrole == "AXSecureTextField" ? subrole : role,
                                    label: label, value: value,
                                    frame: CGRect(x: (rect.minX - screen.origin.x) / screen.zoom, y: (rect.minY - screen.origin.y) / screen.zoom,
                                                  width: rect.width / screen.zoom, height: rect.height / screen.zoom),
                                    selected: (read[7] as? Bool) == true, disabled: (read[8] as? Bool) == false)
                    // The Simulator can show the same screen twice in its tree: each thing is listed once.
                    if !found.contains(item) { found.append(item) }
                    if control { caption = label }
                }
                for child in read[9] as? [AXUIElement] ?? [] { visit(child, depth: depth + 1, under: caption) }
            }
            visit(screen.window, depth: 0, under: "")
            return Date() < limit && !notAnswering ? found : nil
        }

        /// The longest a whole screen may take to read or search. Usually a fifth of a second.
        nonisolated static var readLimit: TimeInterval { 6 }

        /// What a thing is called and what it holds. Plain text keeps its words in its value, so they are
        /// its name; a control's value is its state (a switch on, a field's contents), and stays that even
        /// when the control has no name, which is then plain to see.
        nonisolated static func naming(control: Bool, label: String, value: String) -> (label: String, value: String) {
            let label = label.trimmed, value = value.trimmed
            return label.isEmpty && !control ? (value, "") : (label, value)
        }

        /// A number as a person would write it: a slider at 0.3076923 is at 0.31.
        private static func number(_ value: NSNumber) -> String {
            let rounded = (value.doubleValue * 100).rounded() / 100
            return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
        }

        /// Several attributes in one round trip to the Simulator: asked for one at a time, a whole screen
        /// takes seconds to read.
        private static func attributes(_ element: AXUIElement, _ names: [String]) -> [CFTypeRef?] {
            var values: CFArray?
            guard call({ AXUIElementCopyMultipleAttributeValues(element, names as CFArray, [], &values) }) == .success,
                  let list = values as? [AnyObject], list.count == names.count else { return names.map { attribute(element, $0) } }
            return list.map { value in
                // What an element doesn't have comes back as an error value in its place.
                if value is NSNull || (CFGetTypeID(value) == AXValueGetTypeID() && AXValueGetType(value as! AXValue) == .axError) { return nil }
                return value
            }
        }

        /// One short line for each thing: its id, what it is, its name, what it holds, the point to tap and its size.
        /// The same lines a Mac app writes for its window (`LampScreen` in LampSupport.swift), so the agent
        /// learns one format: a change here is a change there, and a test holds the two together.
        nonisolated static func text(for items: [Item]) -> String? {
            guard !items.isEmpty else { return nil }
            func short(_ text: String, _ limit: Int) -> String {
                let line = text.replacingOccurrences(of: "\n", with: " ")
                return line.count > limit ? line.prefix(limit - 1) + "…" : line
            }
            var lines = zip(ids(for: items), items.prefix(itemLimit)).map { id, item -> String in
                var line = "\(id) \(word(for: item.role))"
                if !item.label.isEmpty { line += " \"\(short(item.label, 80))\"" }
                var value = item.value == item.label ? "" : item.value
                if item.role == kAXCheckBoxRole { value = value == "1" ? "on" : value == "0" ? "off" : value }
                if item.role == kAXRadioButtonRole || item.role == kAXButtonRole, value == "1" || value == "0" { value = "" }
                if !value.isEmpty { line += " = \(short(value, 60))" }
                if item.selected || (item.role == kAXRadioButtonRole && item.value == "1") { line += ", selected" }
                if item.disabled { line += ", dimmed" }
                return line + " @\(Int(item.frame.midX.rounded())),\(Int(item.frame.midY.rounded())) \(Int(item.frame.width.rounded()))x\(Int(item.frame.height.rounded()))"
            }
            if items.count > itemLimit { lines.append("… and \(items.count - itemLimit) more") }
            return heading + "\n" + lines.joined(separator: "\n")
        }

        nonisolated static let heading = "The screen as text, in reading order. Each line is a thing's id, what it is, its name, \"= \" what it holds, " +
            "then @x,y (its middle in the picture) and its size. Act on a thing with `target` set to its id or exact name; " +
            "x and y are for what isn't listed:"

        /// A thing's id: a letter for its kind and a number counted within that kind, so a new label doesn't
        /// renumber the buttons.
        nonisolated static func ids(for items: [Item]) -> [String] {
            var counts: [String: Int] = [:]
            return items.map { item in
                let letter = prefix(for: word(for: item.role))
                counts[letter, default: 0] += 1
                return "\(letter)\(counts[letter]!)"
            }
        }

        nonisolated static func prefix(for role: String) -> String {
            switch role {
            case "button": "b"
            case "text field", "text area", "search field", "password field", "combo box": "f"
            case "text", "heading": "t"
            case "switch": "s"
            case "choice", "tab": "c"
            case "slider", "stepper": "n"
            case "picture": "i"
            case "link": "k"
            case "picker", "menu button", "menu item", "tabs": "m"
            case "row": "r"
            default: "e"
            }
        }

        enum Found: Equatable { case one(Int), none, several([String]) }

        /// The thing a `target` names: an id from the list, else the one thing with exactly that name.
        nonisolated static func find(_ target: String, in items: [Item]) -> Found {
            let ids = ids(for: items)
            let wanted = plain(target)
            if let index = ids.firstIndex(where: { $0.lowercased() == wanted }) { return .one(index) }
            var matches = items.indices.filter { plain(items[$0].label) == wanted }
            // Something and its own caption are one thing: the control.
            if matches.count > 1 { matches = matches.filter { items[$0].role != kAXStaticTextRole } }
            switch matches.count {
            case 0: return .none
            case 1: return .one(matches[0])
            default: return .several(matches.map { ids[$0] })
            }
        }

        nonisolated private static func plain(_ text: String) -> String {
            text.lowercased().replacingOccurrences(of: "...", with: "…").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        nonisolated private static func word(for role: String) -> String {
            switch role {
            case kAXButtonRole: "button"
            case kAXRadioButtonRole: "choice"
            case kAXTextFieldRole: "text field"
            case kAXTextAreaRole: "text area"
            case "AXSearchField": "search field"
            case "AXSecureTextField": "password field"
            case kAXStaticTextRole: "text"
            case kAXCheckBoxRole: "switch"
            case kAXSliderRole: "slider"
            case kAXImageRole: "picture"
            case "AXLink": "link"
            case "AXHeading": "heading"
            case kAXTabGroupRole: "tabs"
            case kAXPopUpButtonRole: "picker"
            case kAXMenuItemRole: "menu item"
            case kAXIncrementorRole: "stepper"
            case kAXProgressIndicatorRole: "progress"
            case "AXCell": "row"
            default: "thing"
            }
        }

        // MARK: Finding and naming things

        /// The text field last tapped by each project's launch of its app, so `type` knows where the keyboard is.
        private static var lastFields: [String: AXUIElement] = [:]

        /// That field, if it's still on this device's screen (not a stale one from before a relaunch).
        private static func rememberedField(in screen: Screen) -> AXUIElement? {
            guard let field = lastFields[screen.owner] else { return nil }
            let rect = frame(of: field)
            guard isTextInput(field), screen.rect.intersects(rect) else {
                lastFields[screen.owner] = nil
                return nil
            }
            return field
        }

        private static func element(at point: CGPoint, in screen: Screen) -> AXUIElement? {
            var element: AXUIElement?
            guard call({ AXUIElementCopyElementAtPosition(screen.app, Float(point.x), Float(point.y), &element) }) == .success, let element else { return nil }
            return element
        }

        private static let interactiveRoles: Set<String> = [kAXButtonRole, kAXRadioButtonRole, kAXTextFieldRole, kAXTextAreaRole, kAXCheckBoxRole,
                                                             kAXSliderRole, "AXLink", kAXMenuItemRole, kAXPopUpButtonRole, kAXIncrementorRole, "AXCell", "AXSearchField"]

        private static func isInteractive(_ element: AXUIElement) -> Bool {
            interactiveRoles.contains(attribute(element, kAXRoleAttribute) as? String ?? "")
        }

        /// Everything that can be tapped on this device's screen, as the Mac sees it: its window only.
        private static func interactiveElements(in screen: Screen) -> [AXUIElement] {
            var found: [AXUIElement] = []
            let limit = Date().addingTimeInterval(readLimit)
            func visit(_ element: AXUIElement, depth: Int) {
                guard depth < 40, found.count < 400, Date() < limit, !notAnswering else { return }
                if isInteractive(element), screen.rect.intersects(frame(of: element)) { found.append(element) }
                for child in children(element) { visit(child, depth: depth + 1) }
            }
            visit(screen.window, depth: 0)
            return found
        }

        /// The control closest to a point, when it's within a finger's reach (about 44 points).
        private static func nearestInteractive(to point: CGPoint, in screen: Screen) -> AXUIElement? {
            let candidates = interactiveElements(in: screen).map { ($0, distance(from: point, to: frame(of: $0))) }
            guard let best = candidates.min(by: { $0.1 < $1.1 }), best.1 <= 44 * screen.zoom else { return nil }
            return best.0
        }

        private static func onlyTextField(in screen: Screen) -> AXUIElement? {
            let fields = interactiveElements(in: screen).filter(isTextInput)
            return fields.count == 1 ? fields[0] : nil
        }

        private static func distance(from point: CGPoint, to rect: CGRect) -> Double {
            let dx = max(rect.minX - point.x, 0, point.x - rect.maxX), dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
            return hypot(dx, dy)
        }

        /// A field, a text area (a note's body) or a search field: anything typed into.
        private static func isTextInput(_ element: AXUIElement) -> Bool {
            let role = attribute(element, kAXRoleAttribute) as? String ?? ""
            return role == kAXTextFieldRole || role == kAXTextAreaRole || role == "AXSearchField"
        }

        private static func textField(near point: CGPoint, in screen: Screen) -> AXUIElement? {
            guard let element = element(at: point, in: screen) else { return nil }
            return isTextInput(element) ? element : nil
        }

        private static func buttons(named name: String, in screen: Screen) -> [AXUIElement] {
            interactiveElements(in: screen).filter { element in
                let role = attribute(element, kAXRoleAttribute) as? String ?? ""
                guard role == kAXButtonRole || role == kAXMenuItemRole else { return false }
                let label = attribute(element, kAXDescriptionAttribute) as? String ?? attribute(element, kAXTitleAttribute) as? String ?? ""
                return label.caseInsensitiveCompare(name) == .orderedSame
            }
        }

        private static func describe(_ element: AXUIElement) -> String {
            let role = attribute(element, kAXRoleAttribute) as? String ?? ""
            let kind: String = switch role {
            case kAXButtonRole: "a button"
            case kAXRadioButtonRole: "a choice"
            case kAXTextFieldRole, kAXTextAreaRole: "a text field"
            case kAXStaticTextRole: "text"
            case kAXCheckBoxRole: "a switch"
            case kAXSliderRole: "a slider"
            case kAXImageRole: "a picture"
            case "AXLink": "a link"
            case "AXHeading": "a heading"
            case kAXTabGroupRole: "a set of choices"
            case kAXGroupRole: "the app's content"
            default: "something"
            }
            let label = ((attribute(element, kAXDescriptionAttribute) as? String)?.nilIfEmpty
                ?? (attribute(element, kAXTitleAttribute) as? String)?.nilIfEmpty ?? "").trimmed
            let value = attribute(element, kAXValueAttribute).map { "\($0)" }?.trimmed ?? ""
            var text = label.isEmpty ? kind : "\(kind) \"\(label)\""
            if !value.isEmpty, role != kAXStaticTextRole, value != "0" { text += " (\(value))" }
            if role == kAXRadioButtonRole, value == "1" { text += ", selected" }
            return text
        }

        private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            var value: CFTypeRef?
            _ = call { AXUIElementCopyAttributeValue(element, name as CFString, &value) }
            return value
        }

        /// What an element offers to do, as it names them: the standard actions, and an iPhone row's own
        /// (its swipe actions), which come as "Name:Delete" with two more lines after.
        private static func actionNames(_ element: AXUIElement) -> [String] {
            var names: CFArray?
            _ = call { AXUIElementCopyActionNames(element, &names) }
            return names as? [String] ?? []
        }

        /// The name a person sees for one of an element's own actions, nil for a standard one.
        nonisolated static func actionName(_ action: String) -> String? {
            guard action.hasPrefix("Name:") else { return nil }
            return action.dropFirst(5).split(separator: "\n").first.map { String($0).trimmed }
        }

        /// What an element sits in, nearest first, as far as the window.
        private static func ancestors(of element: AXUIElement) -> [AXUIElement] {
            var found: [AXUIElement] = []
            var current = element
            while found.count < 12, let parent = attribute(current, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() {
                let parent = parent as! AXUIElement
                if attribute(parent, kAXRoleAttribute) as? String == kAXWindowRole { break }
                found.append(parent)
                current = parent
            }
            return found
        }

        /// Whatever under the point, or what it sits in, offers to scroll that way by a page: the scrolling
        /// the iPhone's own elements offer. Nil when nothing there does.
        private static func scroller(down: Bool, at point: CGPoint, in screen: Screen) -> (element: AXUIElement, action: String)? {
            guard let hit = element(at: point, in: screen) else { return nil }
            let wanted = down ? "AXScrollDownByPage" : "AXScrollUpByPage"
            return ([hit] + ancestors(of: hit)).first { actionNames($0).contains(wanted) }.map { ($0, wanted) }
        }

        private static func turnPage(_ scroller: (element: AXUIElement, action: String)) -> Bool {
            call { AXUIElementPerformAction(scroller.element, scroller.action as CFString) } == .success
        }

        /// What the iPhone's keyboard calls its return key, by what the field is for.
        nonisolated static var returnKeyNames: Set<String> {
            ["return", "go", "search", "send", "done", "next", "join", "route", "continue", "google", "yahoo", "emergency call"]
        }

        /// The return key of the iPhone's keyboard when it's up. The keyboard is there when its space bar
        /// is, and the key is found by its name: it sits beside the space bar on an iPhone and a row up on
        /// an iPad.
        private static func returnKey(in screen: Screen) -> AXUIElement? {
            func name(_ key: AXUIElement) -> String { (attribute(key, kAXDescriptionAttribute) as? String ?? "").lowercased() }
            let keys = interactiveElements(in: screen).filter { attribute($0, kAXRoleAttribute) as? String == kAXButtonRole }
            guard let space = keys.first(where: { name($0) == "space" }) else { return nil }
            let bar = frame(of: space)
            return keys.filter { returnKeyNames.contains(name($0)) && frame(of: $0).midX > bar.maxX }.max(by: { frame(of: $0).midY < frame(of: $1).midY })
        }

        private static func press(_ element: AXUIElement) -> Bool {
            call { AXUIElementPerformAction(element, kAXPressAction as CFString) } == .success
        }

        private static func children(_ element: AXUIElement) -> [AXUIElement] {
            attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
        }

        private static func frame(of element: AXUIElement) -> CGRect {
            var origin = CGPoint.zero, size = CGSize.zero
            if let position = attribute(element, kAXPositionAttribute) { AXValueGetValue(position as! AXValue, .cgPoint, &origin) }
            if let extent = attribute(element, kAXSizeAttribute) { AXValueGetValue(extent as! AXValue, .cgSize, &size) }
            return CGRect(origin: origin, size: size)
        }

        /// The Simulator window's title for a device: "iPhone 16 – iOS 18.6", from its name and runtime.
        private static func deviceTitle(_ udid: String) -> String? {
            let listing = Subprocess.runBlocking("/usr/bin/xcrun", ["simctl", "list", "devices", "-j"], mergeErrors: false, timeout: 30).output
            guard let data = listing.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let devices = json["devices"] as? [String: [[String: Any]]] else { return nil }
            for (runtime, list) in devices {
                guard let device = list.first(where: { $0["udid"] as? String == udid }), let name = device["name"] as? String else { continue }
                // com.apple.CoreSimulator.SimRuntime.iOS-18-6 → iOS 18.6
                let version = runtime.components(separatedBy: "SimRuntime.").last?.replacingOccurrences(of: "-", with: " ")
                    .replacingOccurrences(of: #"^(\S+) (\d+) (\d+)$"#, with: "$1 $2.$3", options: .regularExpression) ?? ""
                return "\(name) – \(version)"
            }
            return nil
        }

        // MARK: Touches

        private static func mouse(_ type: CGEventType, at point: CGPoint, pid: pid_t) {
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.postToPid(pid)
        }

        /// A finger dragged across the screen: down, a dozen moves, up.
        private static func swipe(from start: CGPoint, by delta: CGVector, pid: pid_t) {
            mouse(.leftMouseDown, at: start, pid: pid)
            for step in 1...12 {
                let t = Double(step) / 12
                mouse(.leftMouseDragged, at: CGPoint(x: start.x + delta.dx * t, y: start.y + delta.dy * t), pid: pid)
                usleep(16_000)
            }
            mouse(.leftMouseUp, at: CGPoint(x: start.x + delta.dx, y: start.y + delta.dy), pid: pid)
        }
    }
}
