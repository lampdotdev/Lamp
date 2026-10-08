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

    /// Where that app is in this Xcode, given its Developer folder.
    static func viewer(in developer: String) -> URL? {
        let xcode = URL(fileURLWithPath: developer).deletingLastPathComponent()
        return [URL(fileURLWithPath: developer + "/Applications/Simulator.app"), xcode.appendingPathComponent("Applications/DeviceHub.app")]
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Brings the simulator's window to the front, showing this iPhone when the app shows one device at a time.
    static func show(_ udid: String? = nil) async {
        guard let developer = PhoneTools.discover(), let viewer = viewer(in: developer) else { return }
        _ = await Subprocess.run("/usr/bin/open", [viewer.path], timeout: 30)
        if let udid { await Driver.choose(udid) }
    }
}

// MARK: - Driving the simulator

import AppKit

extension Simulator {
    /// Uses the app in the simulator the way a person would, for the agent's `use_app`. The Simulator app on
    /// the Mac shows the iPhone's whole accessibility tree through the Mac's accessibility system, so Lamp
    /// finds what's under a point, taps it, fills in fields and reads what things are, the same way the Mac
    /// apps' own driver does inside them. Gestures (swipes, scrolls) are real mouse events sent to the
    /// Simulator. The same tree, read whole, is the screen as text that follows every look and use
    /// (`screenText`). This needs Lamp to be allowed to control the computer (System Settings → Privacy &
    /// Security → Accessibility); the first use asks.
    @MainActor
    enum Driver {
        struct Action: Decodable {
            let action: String
            var x: Double?
            var y: Double?
            var text: String?
            var key: String?
            var item: String?
            var amount: Double?
            var direction: String?
        }

        static var isAllowed: Bool { AXIsProcessTrusted() }

        /// Asks macOS to let Lamp control the computer: the system opens the Accessibility list once.
        static func ask() {
            _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        }

        /// The simulated iPhone's screen as the Mac sees it: the Simulator's accessibility app element, the
        /// screen's origin on the Mac's display, and the device's pixel scale, for turning picture pixels
        /// into points on screen.
        struct Screen {
            let app: AXUIElement
            let window: AXUIElement     // the one Simulator window showing this device: lookups stay inside it
            let rect: CGRect            // the device's screen on the Mac's display
            let udid: String
            let owner: String           // the project and launch these actions are for; remembered fields are theirs
            let scale: Double           // the device's pixels per point
            let zoom: Double            // how big the Simulator draws a point on the Mac's display (its window scale)
            let pid: pid_t
            var origin: CGPoint { rect.origin }
            /// Pictures are made at point size (`screenshot`), so a pixel in them is a point on the device, which
            /// the Simulator shows `zoom` times as large.
            func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: origin.x + x * zoom, y: origin.y + y * zoom) }
        }

        static func screen(of udid: String, owner: String) async -> Screen? {
            guard let pid = viewer() else { return nil }
            let width = Double((await Subprocess.run("/usr/bin/xcrun", ["simctl", "getenv", udid, "SIMULATOR_MAINSCREEN_WIDTH"], timeout: 20)).output.trimmed) ?? 0
            let height = Double((await Subprocess.run("/usr/bin/xcrun", ["simctl", "getenv", udid, "SIMULATOR_MAINSCREEN_HEIGHT"], timeout: 20)).output.trimmed) ?? 0
            let scale = Double((await Subprocess.run("/usr/bin/xcrun", ["simctl", "getenv", udid, "SIMULATOR_MAINSCREEN_SCALE"], timeout: 20)).output.trimmed) ?? 0
            guard width > 0, height > 0, scale > 0 else { return nil }
            let app = AXUIElementCreateApplication(pid)
            // Each window is titled "<device> – <runtime>", which is the whole identity it shows: the one
            // window with exactly this device's title, and none when two devices share it.
            guard let title = deviceTitle(udid) else { return nil }
            func titled() -> [AXUIElement] {
                (attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []).filter { attribute($0, kAXTitleAttribute) as? String == title }
            }
            var windows = titled()
            // Device Hub has one window for whichever device is chosen in its list: choose this one.
            if windows.isEmpty, choose(udid, in: app) {
                for _ in 0..<10 where windows.isEmpty {
                    try? await Task.sleep(for: .milliseconds(200))
                    windows = titled()
                }
            }
            guard windows.count == 1, let window = windows.first else { return nil }
            let points = CGSize(width: width / scale, height: height / scale)
            // The picture of the screen can arrive a moment after the window does.
            var found = screenFrame(in: window, shaped: points)
            for _ in 0..<10 where found == nil {
                try? await Task.sleep(for: .milliseconds(200))
                found = screenFrame(in: window, shaped: points)
            }
            guard let frame = found else { return nil }
            return Screen(app: app, window: window, rect: frame, udid: udid, owner: owner, scale: scale,
                          zoom: frame.width / points.width, pid: pid)
        }

        /// The screen is the group shaped like the device's screen (it may be drawn smaller or larger than
        /// its size in points: the window can be zoomed), the largest such if several. Simulator has it at
        /// the top of its window and Device Hub a few layers down, so the window is searched; not inside a
        /// match, where the app's own full-screen views have the same shape.
        private static func screenFrame(in window: AXUIElement, shaped points: CGSize) -> CGRect? {
            let ratio = points.width / points.height
            var matches: [CGRect] = []
            func visit(_ element: AXUIElement, depth: Int) {
                for child in children(element) {
                    let rect = frame(of: child)
                    if attribute(child, kAXRoleAttribute) as? String == kAXGroupRole, rect.width > 50, rect.height > 50,
                       abs(rect.width / rect.height - ratio) < 0.02 {
                        matches.append(rect)
                    } else if depth < 8, rect.width > 50, rect.height > 50 {
                        visit(child, depth: depth + 1)
                    }
                }
            }
            visit(window, depth: 0)
            return matches.max(by: { $0.width < $1.width })
        }

        /// The process showing simulators on screen (Simulator.viewers), if it's running.
        private static func viewer() -> pid_t? {
            for id in Simulator.viewers {
                guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first else { continue }
                if app.processIdentifier > 0 { return app.processIdentifier }
                // Device Hub can be listed without its process id; its windows still say whose they are.
                let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
                let pids = Set(windows.filter { $0[kCGWindowOwnerName as String] as? String == app.localizedName }
                    .compactMap { $0[kCGWindowOwnerPID as String] as? pid_t })
                if let pid = pids.first(where: { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier == id }) { return pid }
            }
            return nil
        }

        /// Has Device Hub show this simulator: it shows one device at a time, the one chosen in its list,
        /// where each row carries its device's identifier. Simulator needs none of this (every booted device
        /// has a window), and without the permission to control the computer the list is left as it is.
        static func choose(_ udid: String) async {
            guard isAllowed else { return }
            // Just opened: its window takes a moment to arrive.
            for _ in 0..<15 {
                if let pid = viewer(), choose(udid, in: AXUIElementCreateApplication(pid)) { return }
                if NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.iphonesimulator").first != nil { return }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }

        @discardableResult
        private static func choose(_ udid: String, in app: AXUIElement) -> Bool {
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
                guard let row = row(in: window, depth: 0) else { continue }
                if (attribute(row, kAXSelectedAttribute) as? Bool) == true { return true }
                return AXUIElementSetAttributeValue(row, kAXSelectedAttribute as CFString, kCFBooleanTrue) == .success
            }
            return false
        }

        /// Carries out the actions in order and says what each one did, like the Mac apps' driver. `live` is
        /// asked before every action: when the turn was stopped, the app deleted or the app gone, the rest of
        /// the batch is dropped rather than carried out on whatever the simulator shows next.
        static func perform(_ actions: [Action], on screen: Screen, picture: URL, live: () -> Bool) async -> String {
            var lines: [String] = []
            var before = try? Data(contentsOf: picture)
            for action in actions {
                guard live() else { lines.append("stopped before the rest: the app was stopped, deleted or closed"); break }
                lines.append(await carryOut(action, on: screen, live: live))
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

        private static func carryOut(_ action: Action, on screen: Screen, live: () -> Bool) async -> String {
            let at = "\(Int(action.x ?? 0)), \(Int(action.y ?? 0))"
            let point = screen.point(action.x ?? 0, action.y ?? 0)
            switch action.action {
            case "click", "double_click", "right_click":
                guard let hit = element(at: point, in: screen) else { return "\(action.action) at \(at): nothing there" }
                // A tap that lands beside a control (on its label, say) is meant for the control.
                let element = isInteractive(hit) ? hit : (nearestInteractive(to: point, in: screen) ?? hit)
                lastFields[screen.owner] = isTextInput(element) ? element : nil
                let name = describe(element) + (element == hit ? "" : " (the nearest thing to tap; the point itself was \(describe(hit)))")
                if action.action == "right_click" {
                    // A long press: the finger held down, which opens context menus and the like.
                    mouse(.leftMouseDown, at: point, pid: screen.pid)
                    try? await Task.sleep(for: .milliseconds(800))
                    mouse(.leftMouseUp, at: point, pid: screen.pid)   // the finger comes up whatever happened meanwhile
                    return "long press at \(at): \(name)"
                }
                var pressed = AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
                if !pressed {   // not everything takes a press through accessibility: a real tap then
                    mouse(.leftMouseDown, at: point, pid: screen.pid); mouse(.leftMouseUp, at: point, pid: screen.pid); pressed = true
                }
                if action.action == "double_click" {
                    try? await Task.sleep(for: .milliseconds(80))
                    if live() { _ = AXUIElementPerformAction(element, kAXPressAction as CFString) }
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
                let result = AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, text as CFTypeRef)
                return result == .success ? "typed \"\(text)\" into \(describe(field)); it now holds that" : "couldn't type into \(describe(field))"
            case "key":
                let key = (action.key ?? "").lowercased()
                guard key == "return" || key == "enter" || key == "escape" || key == "esc" else {
                    return "key \(action.key ?? ""): an iPhone has no such key; tap, type, scroll or swipe instead"
                }
                // Keys reach the simulated iPhone only while the Simulator is the active app.
                NSRunningApplication(processIdentifier: screen.pid)?.activate()
                try? await Task.sleep(for: .milliseconds(300))
                guard live() else { return "stopped before pressing \(key)" }
                let code: CGKeyCode = key.hasPrefix("ret") || key == "enter" ? 36 : 53
                CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)?.postToPid(screen.pid)
                CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)?.postToPid(screen.pid)
                return "pressed \(key.hasPrefix("ret") || key == "enter" ? "return" : "escape")"
            case "scroll":
                let amount = action.amount ?? 300
                swipe(from: point, by: CGVector(dx: 0, dy: -amount * screen.zoom), pid: screen.pid)
                return "scrolled \(amount >= 0 ? "down" : "up") at \(at)"
            case "swipe":
                let direction = action.direction ?? "left"
                let distance = 220.0 * screen.zoom
                let delta: CGVector = switch direction {
                case "left": CGVector(dx: -distance, dy: 0)
                case "right": CGVector(dx: distance, dy: 0)
                case "up": CGVector(dx: 0, dy: -distance)
                default: CGVector(dx: 0, dy: distance)
                }
                swipe(from: point, by: delta, pid: screen.pid)
                if let item = action.item {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard live() else { return "swiped \(direction) at \(at), then stopped before tapping \"\(item)\"" }
                    // What the swipe uncovered (a row's actions, say): tap the one named.
                    if let button = button(named: item, in: screen) {
                        _ = AXUIElementPerformAction(button, kAXPressAction as CFString)
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
        struct Item: Equatable {
            var role: String
            var label = ""
            var value = ""
            var frame: CGRect
            var selected = false
            var disabled = false
        }

        /// The most things listed: a full screen is a few dozen, and past this the list costs more than it tells.
        static let itemLimit = 120

        /// The whole screen in words, for the agent to read beside the picture: what's there, what each thing
        /// holds and where to tap it. Nil when the screen shows nothing with a name.
        static func screenText(on screen: Screen) -> String? { text(for: items(on: screen)) }

        /// Everything on this device's screen that says something or can be tapped, in the order the screen
        /// reads. Containers with no name of their own are left out, and so is a control's own caption (a
        /// button's text is the button).
        static func items(on screen: Screen) -> [Item] {
            var found: [Item] = []
            let wanted = [kAXRoleAttribute, kAXSubroleAttribute, kAXDescriptionAttribute, kAXTitleAttribute, kAXValueAttribute,
                          kAXPositionAttribute, kAXSizeAttribute, kAXSelectedAttribute, kAXEnabledAttribute, kAXChildrenAttribute]
            func visit(_ element: AXUIElement, depth: Int, under: String) {
                guard depth < 40, found.count < 400 else { return }
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
            return found
        }

        /// What a thing is called and what it holds. Plain text keeps its words in its value, so they are
        /// its name; a control's value is its state (a switch on, a field's contents), and stays that even
        /// when the control has no name, which is then plain to see.
        static func naming(control: Bool, label: String, value: String) -> (label: String, value: String) {
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
            guard AXUIElementCopyMultipleAttributeValues(element, names as CFArray, [], &values) == .success,
                  let list = values as? [AnyObject], list.count == names.count else { return names.map { attribute(element, $0) } }
            return list.map { value in
                // What an element doesn't have comes back as an error value in its place.
                if value is NSNull || (CFGetTypeID(value) == AXValueGetTypeID() && AXValueGetType(value as! AXValue) == .axError) { return nil }
                return value
            }
        }

        /// One short line for each thing: what it is, its name, what it holds, the point to tap and its size.
        static func text(for items: [Item]) -> String? {
            guard !items.isEmpty else { return nil }
            func short(_ text: String, _ limit: Int) -> String {
                let line = text.replacingOccurrences(of: "\n", with: " ")
                return line.count > limit ? line.prefix(limit - 1) + "…" : line
            }
            var lines = items.prefix(itemLimit).map { item -> String in
                var line = word(for: item.role)
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
            return "The screen as text, in reading order. Each line is what a thing is, its name, \"= \" what it holds, " +
                "then @x,y (its middle in the picture: where to tap it) and its size:\n" + lines.joined(separator: "\n")
        }

        private static func word(for role: String) -> String {
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
            guard AXUIElementCopyElementAtPosition(screen.app, Float(point.x), Float(point.y), &element) == .success, let element else { return nil }
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
            func visit(_ element: AXUIElement, depth: Int) {
                guard depth < 40, found.count < 400 else { return }
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

        private static func button(named name: String, in screen: Screen) -> AXUIElement? {
            interactiveElements(in: screen).first { element in
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
            AXUIElementCopyAttributeValue(element, name as CFString, &value)
            return value
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
