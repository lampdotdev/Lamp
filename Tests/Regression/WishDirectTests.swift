import CryptoKit
import JavaScriptCore
import LampRelayKit
import XCTest
@testable import Lamp

/// Two Swift apps of one wish go on talking without Lamp: they meet in Lamp's room, each listens and is found on the
/// network, and when the relay goes (Lamp quit, the Mac asleep) their messages keep arriving over the link straight
/// between them, sealed with the wish's key. Opened again with no Lamp at all, they find each other from what they kept.
@MainActor
final class WishDirectTests: XCTestCase {
    /// Each app sends the other a number every half second and says what it heard, for as long as it's told to run.
    static let talker = """
        @main struct Talker {
            @MainActor static func main() {
                setvbuf(stdout, nil, _IONBF, 0)
                let env = ProcessInfo.processInfo.environment
                let to = env["LAMP_TO"]!, seconds = Double(env["LAMP_SECONDS"] ?? "20")!
                let wish = LampWish.shared
                wish.onMessage { from, data in
                    print("heard \\((data as? [String: Any])?["n"] as? Int ?? -1) from \\(from)")
                }
                let end = Date().addingTimeInterval(seconds)
                var n = 0, last = Date.distantPast
                while Date() < end {
                    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
                    if Date().timeIntervalSince(last) > 0.5, wish.peer(to)?.isOpen == true {
                        last = Date()
                        n += 1
                        _ = wish.send(["n": n], to: to)
                    }
                }
                print("state \\(wish.state.rawValue)")
            }
        }
        """

    func testTwoAppsGoOnTalkingWithLampGoneAndFindEachOtherWithoutIt() async throws {
        let relay = Relay(key: SymmetricKey(size: .bits256))
        let started: UInt16? = await withCheckedContinuation { done in relay.start { done.resume(returning: $0) } }
        let port = try XCTUnwrap(started)
        let key = WishChannel.random(32)
        relay.configureRoom("wish:direct", key: key, apps: ["mac": ("mac", "the Mac app"), "iphone": ("iphone", "the iPhone app")])

        let work = try Self.talkerBuilt(key: key)
        defer { try? FileManager.default.removeItem(at: work) }

        let suite = "lamp-wish-direct-\(UUID().uuidString)"
        defer { for each in ["mac", "iphone"] { UserDefaults.standard.removePersistentDomain(forName: "\(suite)-\(each)") } }
        func run(_ me: String, to: String, seconds: Int, lamp: Bool, log: String) -> Task<Void, Never> {
            let socket = lamp ? "LAMP_SOCKET='ws://127.0.0.1:\(port)/' " : ""
            let command = "\(socket)LAMP_DEFAULTS=\(suite)-\(me) LAMP_PEER=\(me) LAMP_TO=\(to) LAMP_SECONDS=\(seconds) ./talker > \(log) 2>&1"
            return Task.detached { _ = TestShell.run(command, in: work) }
        }
        func heard(_ log: String) -> [Int] {
            ((try? String(contentsOf: work.appendingPathComponent(log), encoding: .utf8)) ?? "").split(separator: "\n")
                .compactMap { $0.hasPrefix("heard ") ? Int($0.split(separator: " ")[1]) : nil }
        }

        // With Lamp: they meet in the room, and find each other straight too.
        let phone = run("iphone", to: "mac", seconds: 30, lamp: true, log: "phone.txt")
        let mac = run("mac", to: "iphone", seconds: 30, lamp: true, log: "mac.txt")
        for _ in 0..<200 where heard("phone.txt").count < 4 { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertFalse(heard("phone.txt").isEmpty, "they talked while Lamp was there")

        // Lamp goes.
        relay.stop()
        let before = heard("phone.txt").max() ?? 0
        try await Task.sleep(for: .seconds(8))
        let after = heard("phone.txt").filter { $0 > before }
        XCTAssertGreaterThan(after.count, 5, "messages kept arriving after the relay went: \(heard("phone.txt"))")
        _ = await (phone.value, mac.value)

        // Opened again with no Lamp at all: they find each other from what they kept.
        let phone2 = run("iphone", to: "mac", seconds: 15, lamp: false, log: "phone2.txt")
        let mac2 = run("mac", to: "iphone", seconds: 15, lamp: false, log: "mac2.txt")
        _ = await (phone2.value, mac2.value)
        XCTAssertGreaterThan(heard("phone2.txt").count, 5, "no Lamp: \((try? String(contentsOf: work.appendingPathComponent("phone2.txt"), encoding: .utf8)) ?? "")")
        XCTAssertGreaterThan(heard("mac2.txt").count, 5, "both ways")
    }

    /// The talker built with the wish's key in its Info.plist, as Lamp installs an app of a wish.
    static func talkerBuilt(key: Data) throws -> URL {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-wish-direct-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try WishNativeTests.program(main: talker).write(to: work.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        let plist = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>dev.lamp.test.direct</string>"
            + Template.wishKeyPlistLines(key) + "</dict></plist>"
        try plist.write(to: work.appendingPathComponent("wish.plist"), atomically: true, encoding: .utf8)
        let built = TestShell.run(Shell.compatibleSDK + "xcrun swiftc -parse-as-library -o talker main.swift -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker wish.plist 2>&1", in: work)
        XCTAssertEqual(built.status, 0, built.output)
        return work
    }

    /// A TV page can't listen nor look names up: with Lamp gone it finds the Mac app by sweeping its own network at the
    /// port the wish's key gives that app, which the Mac app worked out the same way, and they talk, sealed.
    func testATVPageFindsTheMacAppOnItsNetworkWithoutLamp() async throws {
        let relay = Relay(key: SymmetricKey(size: .bits256))
        let started: UInt16? = await withCheckedContinuation { done in relay.start { done.resume(returning: $0) } }
        let port = try XCTUnwrap(started)
        let key = WishChannel.random(32)
        let apps: [String: (String, String)] = ["mac": ("mac", "the Mac app"), "tv": ("tv", "the TV app")]
        relay.configureRoom("wish:tv", key: key, apps: apps)
        let work = try Self.talkerBuilt(key: key)
        defer { try? FileManager.default.removeItem(at: work) }
        let suite = "lamp-wish-direct-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: "\(suite)-mac") }
        // The Mac app learns its wish from Lamp's room, then Lamp goes.
        let command = "LAMP_SOCKET='ws://127.0.0.1:\(port)/' LAMP_APPS=mac,tv LAMP_DEFAULTS=\(suite)-mac LAMP_PEER=mac LAMP_TO=tv LAMP_SECONDS=30 ./talker > mac.txt 2>&1"
        let mac = Task.detached { _ = TestShell.run(command, in: work) }
        try await Task.sleep(for: .seconds(4))
        relay.stop()

        // The TV page, with the key it claimed and the wish's apps it kept from an earlier opening, and nothing about
        // where the Mac app is.
        let page = PageWithSockets()
        let tag = WishChannel.tag(for: SymmetricKey(data: key)).map { String(format: "%02x", $0) }.joined()
        page.context.evaluateScript("""
            store['lamp:install.wish'] = JSON.stringify({ app: 'wishapp', key: '\(key.base64EncodedString())' });
            store['lamp:wish.\(tag)'] = JSON.stringify({ me: 'tv', apps: [{ peer: 'mac', kind: 'mac', name: 'the Mac app' }, { peer: 'tv', kind: 'tv', name: 'the TV app' }], at: {} });
            window.tizen = { systeminfo: { getPropertyValue: function (kind, ok) { if (kind === 'WIFI_NETWORK') ok({ ipAddress: '127.0.0.1' }); } } };
            """)
        page.context.evaluateScript(TVTemplate.wishJS.replacingOccurrences(of: DeviceSupport.webMarker, with: #"/*LAMP_INSTALL*/{"app":"wishapp","routes":[]}"#))
        page.context.evaluateScript("""
            var heard = [], n = 0;
            Lamp.wish.onMessage(function (from, data) { heard.push(from + ':' + data.n); });
            Lamp.wish.start();
            setInterval(function () { if (Lamp.wish.peer('mac') && Lamp.wish.peer('mac').open) Lamp.wish.send({ n: ++n }, 'mac'); }, 500);
            """)
        for _ in 0..<200 where (page.context.evaluateScript("heard.length")?.toInt32() ?? 0) < 6 { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertGreaterThanOrEqual(page.context.evaluateScript("heard.length")?.toInt32() ?? 0, 6,
                                    "the page heard the Mac app: \(page.context.evaluateScript("JSON.stringify([Lamp.wish.state(), heard, said.slice(0, 6)])")?.toString() ?? "")")
        XCTAssertEqual(page.context.evaluateScript("Lamp.wish.state()")?.toString(), "connected")
        try await Task.sleep(for: .seconds(2))
        page.end()
        _ = await mac.value
        let said = (try? String(contentsOf: work.appendingPathComponent("mac.txt"), encoding: .utf8)) ?? ""
        XCTAssertTrue(said.contains("heard 3 from tv"), "and the Mac app heard the page: \(said)")
    }

    /// Another program has the port the wish's key gives the Mac app: it listens on another one, says so in Lamp's room,
    /// and the TV preview's page, told there, goes on talking to it straight once Lamp's relay is gone.
    func testAMacAppWhoseWishPortIsTakenListensElsewhereAndIsReachedThere() async throws {
        let relay = Relay(key: SymmetricKey(size: .bits256))
        let started: UInt16? = await withCheckedContinuation { done in relay.start { done.resume(returning: $0) } }
        let port = try XCTUnwrap(started)
        let key = WishChannel.random(32)
        relay.configureRoom("wish:taken", key: key, apps: ["mac": ("mac", "the Mac app"), "tv": ("tv", "the TV app")])
        // The Mac app's place among mac and tv is the first: the wish's port for it, held by another program.
        let d = WishChannel.derive("lamp-wish port", key: SymmetricKey(data: key))
        let wishPort = UInt16(20000 + (Int(d[0]) << 8 | Int(d[1])) % 1500 * 8)
        let other = socket(AF_INET, SOCK_STREAM, 0)
        defer { Darwin.close(other) }
        var address = sockaddr_in(sin_len: UInt8(MemoryLayout<sockaddr_in>.size), sin_family: sa_family_t(AF_INET), sin_port: wishPort.bigEndian,
                                  sin_addr: in_addr(s_addr: INADDR_ANY), sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
        let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(other, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        try XCTSkipIf(bound != 0, "the wish's port was taken already")
        XCTAssertEqual(Darwin.listen(other, 1), 0)

        let work = try Self.talkerBuilt(key: key)
        defer { try? FileManager.default.removeItem(at: work) }
        let suite = "lamp-wish-direct-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: "\(suite)-mac") }
        let command = "LAMP_SOCKET='ws://127.0.0.1:\(port)/' LAMP_APPS=mac,tv LAMP_DEFAULTS=\(suite)-mac LAMP_PEER=mac LAMP_TO=tv LAMP_SECONDS=30 ./talker > mac.txt 2>&1"
        let mac = Task.detached { _ = TestShell.run(command, in: work) }

        // The TV preview's page, which Lamp gives the key and the room through its bridge.
        let page = PageWithSockets()
        page.context.evaluateScript("""
            window.webkit = { messageHandlers: { lampGateway: {} } };
            var answer = { socket: 'ws://127.0.0.1:\(port)/', peer: 'tv', key: '\(key.base64EncodedString())', peers: [],
                           apps: [{ peer: 'mac', kind: 'mac', name: 'the Mac app' }, { peer: 'tv', kind: 'tv', name: 'the TV app' }] };
            var lampThere = true;
            LampAI = { _post: function () { return lampThere ? Promise.resolve(answer) : Promise.reject(new Error("Couldn't reach Lamp.")); } };
            """)
        page.context.evaluateScript(TVTemplate.wishJS)
        page.context.evaluateScript("""
            var heard = [];
            Lamp.wish.onMessage(function (from, data) { heard.push(data.n); });
            Lamp.wish.start();
            """)
        func heard() -> Int { Int(page.context.evaluateScript("heard.length")?.toInt32() ?? 0) }
        for _ in 0..<150 where heard() < 6 { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertGreaterThanOrEqual(heard(), 6, "the page heard the Mac app with Lamp there")
        // Lamp goes.
        page.context.evaluateScript("lampThere = false;")
        relay.stop()
        try await Task.sleep(for: .seconds(1))
        let before = heard()
        try await Task.sleep(for: .seconds(6))
        XCTAssertGreaterThan(heard() - before, 6, "and straight after it went: \(page.context.evaluateScript("JSON.stringify([Lamp.wish.state(), heard, said.slice(0, 6)])")?.toString() ?? "")")
        page.end()
        _ = await mac.value
    }
}

/// A JavaScript context with WebSockets, timers, storage and randomness of the Mac's, so a page's script talks to real
/// apps over real sockets.
@MainActor
final class PageWithSockets: NSObject, URLSessionWebSocketDelegate {
    let context: JSContext
    private var session: URLSession!
    private var tasks: [Int: URLSessionWebSocketTask] = [:]
    private var timers: [Int: Timer] = [:]
    private var count = 0

    override init() {
        context = JSContext()
        super.init()
        session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: .main)
        context.exceptionHandler = { _, value in XCTFail(value?.toString() ?? "?") }
        let random: @convention(block) (Int) -> [UInt8] = { count in [UInt8](WishChannel.random(count)) }
        context.setObject(random, forKeyedSubscript: "macRandom" as NSString)
        let open: @convention(block) (String) -> Int = { [unowned self] url in
            MainActor.assumeIsolated {
                self.count += 1
                guard let address = URL(string: url) else { return self.count }
                let task = self.session.webSocketTask(with: address)
                task.taskDescription = String(self.count)
                self.tasks[self.count] = task
                task.resume()
                return self.count
            }
        }
        let send: @convention(block) (Int, JSValue) -> Void = { [unowned self] id, value in
            MainActor.assumeIsolated {
                guard let task = self.tasks[id] else { return }
                if value.isString { task.send(.string(value.toString())) { _ in } }
                else { task.send(.data(Data((value.toArray() as? [NSNumber] ?? []).map { $0.uint8Value }))) { _ in } }
            }
        }
        let close: @convention(block) (Int) -> Void = { [unowned self] id in
            MainActor.assumeIsolated { self.tasks[id]?.cancel(with: .goingAway, reason: nil); self.closed(id, code: 1000) }
        }
        let later: @convention(block) (JSValue, Double, Bool) -> Int = { [unowned self] fn, ms, repeats in
            MainActor.assumeIsolated {
                self.count += 1
                let id = self.count
                self.timers[id] = Timer.scheduledTimer(withTimeInterval: max(ms, 1) / 1000, repeats: repeats) { _ in
                    MainActor.assumeIsolated {
                        if !repeats { self.timers[id] = nil }
                        fn.call(withArguments: [])
                    }
                }
                return id
            }
        }
        let cancel: @convention(block) (Int) -> Void = { [unowned self] id in MainActor.assumeIsolated { self.timers[id]?.invalidate(); self.timers[id] = nil } }
        for (name, block) in [("macOpen", open as Any), ("macSend", send), ("macClose", close), ("macLater", later), ("macCancel", cancel)] {
            context.setObject(block, forKeyedSubscript: name as NSString)
        }
        context.evaluateScript("""
            var window = this, store = {}, sockets = {};
            var said = []; var console = { error: function (m) { said.push(String(m)); }, log: function () {} };
            window.crypto = { getRandomValues: function (a) { var r = macRandom(a.length); for (var i = 0; i < a.length; i++) a[i] = r[i]; return a; } };
            window.localStorage = { getItem: function (k) { return k in store ? store[k] : null; }, setItem: function (k, v) { store[k] = String(v); }, removeItem: function (k) { delete store[k]; } };
            window.Lamp = {};
            var LampAI = { _post: function () { return Promise.reject(new Error("Couldn't reach Lamp.")); } };
            function XMLHttpRequest() {}
            XMLHttpRequest.prototype.open = function () {}; XMLHttpRequest.prototype.setRequestHeader = function () {};
            XMLHttpRequest.prototype.send = function () { var x = this; setTimeout(function () { x.onerror(); }, 1); };
            function WebSocket(url) { this.url = url; this.readyState = 0; this.id = macOpen(url); sockets[this.id] = this; }
            WebSocket.prototype.send = function (x) { macSend(this.id, typeof x === 'string' ? x : Array.prototype.slice.call(new Uint8Array(x))); };
            WebSocket.prototype.close = function () { macClose(this.id); };
            function setTimeout(fn, ms) { return macLater(fn, ms || 0, false); } function clearTimeout(id) { if (id) macCancel(id); }
            function setInterval(fn, ms) { return macLater(fn, ms || 0, true); } function clearInterval(id) { if (id) macCancel(id); }
            function deliver(id, data) { var s = sockets[id]; if (s && s.onmessage) s.onmessage({ data: data }); }
            function bytes(list) { return new Uint8Array(list).buffer; }
            """)
    }

    func end() {
        for timer in timers.values { timer.invalidate() }
        timers = [:]
        for task in tasks.values { task.cancel(with: .goingAway, reason: nil) }
        tasks = [:]
        session.invalidateAndCancel()
    }

    private func closed(_ id: Int, code: Int) {
        guard tasks.removeValue(forKey: id) != nil else { return }
        context.evaluateScript("(function () { var s = sockets[\(id)]; if (s) { s.readyState = 3; delete sockets[\(id)]; if (s.onclose) s.onclose({ code: \(code) }); } })();")
    }

    private func receive(_ id: Int, _ task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            MainActor.assumeIsolated {
                guard let self, self.tasks[id] === task else { return }
                switch result {
                case .success(.string(let text)):
                    self.context.objectForKeyedSubscript("deliver").call(withArguments: [id, text])
                case .success(.data(let data)):
                    let buffer = self.context.objectForKeyedSubscript("bytes").call(withArguments: [[UInt8](data).map(NSNumber.init(value:))])
                    self.context.objectForKeyedSubscript("deliver").call(withArguments: [id, buffer as Any])
                case .success:
                    break
                case .failure:
                    return self.closed(id, code: 1006)
                }
                self.receive(id, task)
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        MainActor.assumeIsolated {
            guard let id = Int(webSocketTask.taskDescription ?? ""), tasks[id] === webSocketTask else { return }
            context.evaluateScript("(function () { var s = sockets[\(id)]; if (s) { s.readyState = 1; if (s.onopen) s.onopen(); } })();")
            receive(id, webSocketTask)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        MainActor.assumeIsolated {
            guard let id = Int(task.taskDescription ?? "") else { return }
            closed(id, code: 1006)
        }
    }
}
