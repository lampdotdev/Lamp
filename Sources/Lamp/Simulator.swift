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
        if show { await self.show() }
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

    /// Brings the Simulator window to the front.
    static func show() async {
        guard let developer = PhoneTools.discover() else { return }
        _ = await Subprocess.run("/usr/bin/open", [developer + "/Applications/Simulator.app"], timeout: 30)
    }
}

// MARK: - Driving the simulator

import AppKit

extension Simulator {
    /// Uses the app in the simulator the way a person would, for the agent's `use_app`. The Simulator app on
    /// the Mac shows the iPhone's whole accessibility tree through the Mac's accessibility system, so Lamp
    /// finds what's under a point, taps it, fills in fields and reads what things are, the same way the Mac
    /// apps' own driver does inside them. Gestures (swipes, scrolls) are real mouse events sent to the
    /// Simulator. This needs Lamp to be allowed to control the computer (System Settings → Privacy &
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
            guard let simulator = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.iphonesimulator").first else { return nil }
            let width = Double((await Subprocess.run("/usr/bin/xcrun", ["simctl", "getenv", udid, "SIMULATOR_MAINSCREEN_WIDTH"], timeout: 20)).output.trimmed) ?? 0
            let height = Double((await Subprocess.run("/usr/bin/xcrun", ["simctl", "getenv", udid, "SIMULATOR_MAINSCREEN_HEIGHT"], timeout: 20)).output.trimmed) ?? 0
            let scale = Double((await Subprocess.run("/usr/bin/xcrun", ["simctl", "getenv", udid, "SIMULATOR_MAINSCREEN_SCALE"], timeout: 20)).output.trimmed) ?? 0
            guard width > 0, height > 0, scale > 0 else { return nil }
            let app = AXUIElementCreateApplication(simulator.processIdentifier)
            // The Simulator titles each window "<device> – <runtime>", which is the whole identity it shows:
            // the one window with exactly this device's title, and none when two devices share it.
            guard let title = deviceTitle(udid) else { return nil }
            let windows = (attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? [])
                .filter { attribute($0, kAXTitleAttribute) as? String == title }
            guard windows.count == 1, let window = windows.first else { return nil }
            // The screen is the group shaped like the device's screen (the Simulator may draw it smaller or
            // larger than its size in points: its window can be zoomed), the largest such if several.
            let points = CGSize(width: width / scale, height: height / scale)
            let ratio = points.width / points.height
            // Spelled out step by step: as one chained expression it's more than the compiler can type-check.
            let elements: [AXUIElement] = children(window).filter { (element: AXUIElement) -> Bool in
                attribute(element, kAXRoleAttribute) as? String == kAXGroupRole
            }
            let groups: [CGRect] = elements.map { frame(of: $0) }.filter { (rect: CGRect) -> Bool in
                guard rect.width > 50, rect.height > 50 else { return false }
                let shape: CGFloat = rect.width / rect.height
                return abs(shape - ratio) < 0.02
            }
            guard let frame = groups.max(by: { $0.width < $1.width }) else { return nil }
            return Screen(app: app, window: window, rect: frame, udid: udid, owner: owner, scale: scale,
                          zoom: frame.width / points.width, pid: simulator.processIdentifier)
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
