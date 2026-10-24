import CryptoKit
import JavaScriptCore
import LampRelayKit
import XCTest
@testable import Lamp

/// `Lamp.wish` in lamp.js, the TV page's half of LampWish, against the relay's own side of the channel (`WishChannel`): it
/// asks Lamp where its room is, proves it holds the wish's key, seals what it sends and opens what comes, keeps the list
/// of the wish's other apps as they come and go, and lets its link go when anything comes that the relay didn't seal. On
/// a TV it claims the wish's key from Lamp sealed to a key pair of its own.
@MainActor
final class WishPageTests: XCTestCase {
    private let key = WishChannel.random(32)
    /// The relay's side of the page's current link, once its handshake is done.
    private var sealer: WishChannel.Sealer?
    private var opener: WishChannel.Sealer?

    private func page(installed: String? = nil, answer: String? = nil, before: (JSContext) -> Void = { _ in }) throws -> JSContext {
        let context = try XCTUnwrap(JSContext())
        context.exceptionHandler = { _, value in XCTFail(value?.toString() ?? "?") }
        let random: @convention(block) (Int) -> [UInt8] = { count in [UInt8](WishChannel.random(count)) }
        context.setObject(random, forKeyedSubscript: "macRandom" as NSString)
        // Lamp's answer to /app/wish: the preview's, which carries the key, unless the test gives its own.
        let told = answer ?? "{ socket: 'ws://127.0.0.1:47900/', peer: 'tv', key: '\(key.base64EncodedString())', peers: [], apps: [] }"
        context.evaluateScript("""
            var window = this, sent = [], errors = [], sockets = [], later = [], peerLists = [], states = [], heard = [], store = {};
            var console = { error: function (m) { errors.push(String(m)); }, log: function () {} };
            window.crypto = { getRandomValues: function (a) { var r = macRandom(a.length); for (var i = 0; i < a.length; i++) a[i] = r[i]; return a; } };
            window.localStorage = { getItem: function (k) { return k in store ? store[k] : null; }, setItem: function (k, v) { store[k] = String(v); }, removeItem: function (k) { delete store[k]; } };
            \(installed == nil ? "window.webkit = { messageHandlers: { lampGateway: {} } };" : "")
            window.Lamp = {};
            function hex(b) { var s = ''; for (var i = 0; i < b.length; i++) s += (b[i] < 16 ? '0' : '') + b[i].toString(16); return s; }
            function bytes(h) { var b = new Uint8Array(h.length / 2); for (var i = 0; i < b.length; i++) b[i] = parseInt(h.substr(2 * i, 2), 16); return b; }
            var LampAI = { _post: function (path, body) {
              sent.push(JSON.stringify({ post: path, body: body }));
              return Promise.resolve(\(told));
            } };
            function WebSocket(url) { this.url = url; this.readyState = 1; sockets.push(this); }
            WebSocket.prototype.send = function (x) { sent.push(typeof x === 'string' ? x : 'sealed:' + hex(new Uint8Array(x))); };
            WebSocket.prototype.close = function () { this.closed = true; };
            function setInterval() { return 0; } function clearInterval() {}
            function setTimeout(fn) { later.push(fn); return later.length; } function clearTimeout() {}
            """)
        before(context)
        context.evaluateScript(installed.map { TVTemplate.wishJS.replacingOccurrences(of: DeviceSupport.webMarker, with: "/*LAMP_INSTALL*/" + $0) } ?? TVTemplate.wishJS)
        return context
    }

    /// Promises settle on the context's microtask queue, which runs when the script returns.
    private func settle(_ context: JSContext) { context.evaluateScript("0") }

    private func sentItems(_ context: JSContext) -> [String] { context.evaluateScript("sent")?.toArray() as? [String] ?? [] }

    /// The relay's half of the handshake on socket `n`: its challenge to the page's hello, then the page's proof and its
    /// first sealed message, which says what device it is.
    @discardableResult
    private func handshake(_ context: JSContext, socket n: Int = 0, proof forged: Data? = nil, key given: Data? = nil) throws -> [String: Any] {
        context.evaluateScript("sockets[\(n)].onopen();")
        let hello = try XCTUnwrap(sentItems(context).last.flatMap(Self.parse))
        XCTAssertEqual(hello["t"] as? String, "hello")
        XCTAssertNil(hello["credential"])
        let wishKey = SymmetricKey(data: given ?? key)
        let tag = try XCTUnwrap((hello["tag"] as? String).flatMap { Data(base64Encoded: $0) })
        XCTAssertEqual(tag, WishChannel.tag(for: wishKey), "the page names its wish by tag alone")
        let nonce = try XCTUnwrap((hello["nonce"] as? String).flatMap { Data(base64Encoded: $0) })
        let ours = WishChannel.random(16)
        let transcript = WishChannel.transcript(tag: tag, client: hello["peer"] as? String ?? "", server: "lamp", clientNonce: nonce, serverNonce: ours)
        let proof = forged ?? WishChannel.serverProof(key: wishKey, transcript: transcript)
        let before = sentItems(context).count
        deliverText(context, socket: n, ["t": "challenge", "peer": "lamp", "nonce": ours.base64EncodedString(), "proof": proof.base64EncodedString()])
        let after = Array(sentItems(context).dropFirst(before))
        guard forged == nil else { XCTAssertTrue(after.isEmpty, "nothing said to a relay that couldn't prove the key: \(after)"); return [:] }
        let theirs = try XCTUnwrap(after.first.flatMap(Self.parse))
        XCTAssertEqual(theirs["t"] as? String, "proof")
        XCTAssertEqual(Data(base64Encoded: theirs["proof"] as? String ?? ""), WishChannel.clientProof(key: wishKey, transcript: transcript))
        let keys = WishChannel.keys(key: wishKey, transcript: transcript)
        sealer = WishChannel.Sealer(key: keys.server)
        opener = WishChannel.Sealer(key: keys.client)
        return try opened(try XCTUnwrap(after.dropFirst().first))
    }

    private func opened(_ item: String) throws -> [String: Any] {
        XCTAssertTrue(item.hasPrefix("sealed:"), "sealed: \(item)")
        let data = Data(hexString: String(item.dropFirst("sealed:".count)))
        let plain = try XCTUnwrap(opener?.open(data), "opens as the next message from the page")
        return try XCTUnwrap((try JSONSerialization.jsonObject(with: plain)) as? [String: Any])
    }

    private func deliverText(_ context: JSContext, socket n: Int = 0, _ value: [String: Any]) {
        let text = String(decoding: (try? JSONSerialization.data(withJSONObject: value)) ?? Data(), as: UTF8.self)
        context.evaluateScript("sockets[\(n)].onmessage({ data: \(Self.quoted(text)) });")
    }

    /// What the relay says, sealed, as the next message to the page.
    private func deliver(_ context: JSContext, socket n: Int = 0, _ value: [String: Any]) {
        let plain = (try? JSONSerialization.data(withJSONObject: value)) ?? Data()
        let sealed = sealer!.seal(plain)
        context.evaluateScript("sockets[\(n)].onmessage({ data: bytes('\(sealed.hex)').buffer });")
    }

    private let roster: [[String: Any]] = [["peer": "tv", "kind": "tv", "name": "the TV app"], ["peer": "iphone", "kind": "iphone", "name": "the iPhone app"],
                                           ["peer": "android", "kind": "android", "name": "the Android app"]]

    func testThePageProvesItHoldsTheKeyAndFollowsWhoIsThere() throws {
        let context = try page()
        context.evaluateScript("""
            Lamp.wish.onPeers(function (list) { peerLists.push(list.map(function (p) { return p.peer; }).join(',')); });
            Lamp.wish.onState(function (s) { states.push(s); });
            Lamp.wish.onMessage(function (from, data) { heard.push(from + ':' + JSON.stringify(data)); });
            Lamp.wish.start();
            """)
        settle(context)
        XCTAssertEqual(context.evaluateScript("sockets.length")?.toInt32(), 1, "asked Lamp, then opened its socket to the relay")
        XCTAssertEqual(context.evaluateScript("sockets[0].url")?.toString(), "ws://127.0.0.1:47900/")
        let join = try handshake(context)
        XCTAssertEqual(join["t"] as? String, "join")
        XCTAssertEqual(join["device"] as? String, "TV preview")
        deliver(context, ["t": "welcome", "role": "peer", "peer": "tv", "apps": roster,
                          "peers": [["peer": "iphone", "kind": "iphone", "name": "the iPhone app", "device": "iPhone", "since": 1]]])
        context.evaluateScript("var androidBefore = Lamp.wish.peer('android');")
        deliver(context, ["t": "joined", "peer": ["peer": "android", "kind": "android", "name": "the Android app", "device": "Android emulator", "since": 2]])
        deliver(context, ["t": "message", "from": "android", "data": ["score": 3]])
        context.evaluateScript("sockets[0].onmessage({ data: '{\"t\":\"beat\"}' });")   // a beat, in clear, is let be
        deliver(context, ["t": "left", "peer": "iphone"])
        XCTAssertEqual(context.evaluateScript("Lamp.wish.me()")?.toString(), "tv")
        XCTAssertEqual(context.evaluateScript("Lamp.wish.state()")?.toString(), "connected")
        XCTAssertEqual(context.evaluateScript("peerLists.join('|')")?.toString(), "|iphone|iphone,android|android")
        XCTAssertEqual(context.evaluateScript("heard.join('|')")?.toString(), "android:{\"score\":3}")
        XCTAssertEqual(context.evaluateScript("Lamp.wish.peer('android').name")?.toString(), "the Android app")
        // Every app of the wish is known, open or not, with why in words to show and when it was last seen.
        XCTAssertEqual(context.evaluateScript("androidBefore.status.state + '|' + androidBefore.status.reason")?.toString(),
                       "notOpen|The Android app isn't open.")
        XCTAssertEqual(context.evaluateScript("Lamp.wish.peer('iphone').status.reason")?.toString(), "The iPhone app isn't open.")
        XCTAssertEqual(context.evaluateScript("typeof Lamp.wish.peer('iphone').status.lastSeen")?.toString(), "number")
        XCTAssertTrue(context.evaluateScript("Lamp.wish.peer('roku')")?.isNull == true, "no such app in the wish")
        XCTAssertEqual(context.evaluateScript("Lamp.wish.status().state + '|' + Lamp.wish.status().reason")?.toString(), "connected|")
        XCTAssertEqual(context.evaluateScript("states.join(',')")?.toString(), "connecting,connected")
        XCTAssertNotEqual(context.evaluateScript("sockets[0].closed")?.toBool(), true)
    }

    func testAMessageGoesToOneAppOrAllSealedAndIsRefusedWhenItCant() throws {
        let context = try page()
        context.evaluateScript("Lamp.wish.start();")
        settle(context)
        context.evaluateScript("var early = Lamp.wish.send({ hi: 1 }, 'iphone');")
        try handshake(context)
        deliver(context, ["t": "welcome", "role": "peer", "peer": "tv", "apps": roster,
                          "peers": [["peer": "iphone", "kind": "iphone", "name": "the iPhone app", "device": "iPhone", "since": 1]]])
        let before = sentItems(context).count
        context.evaluateScript("""
            var toOne = Lamp.wish.send({ score: 3 }, 'iphone');
            var toAll = Lamp.wish.send('round 2');
            var toAbsent = Lamp.wish.send({ x: 1 }, 'android');
            var big = Lamp.wish.send({ chunk: new Array(17000).join('A') });
            """)
        XCTAssertEqual(context.evaluateScript("early")?.toBool(), false, "nothing goes before the welcome")
        XCTAssertEqual(context.evaluateScript("toOne")?.toBool(), true)
        XCTAssertEqual(context.evaluateScript("toAll")?.toBool(), true)
        XCTAssertEqual(context.evaluateScript("toAbsent")?.toBool(), false, "the Android app isn't open")
        XCTAssertEqual(context.evaluateScript("big")?.toBool(), false)
        let frames = try sentItems(context).dropFirst(before).map(opened)
        XCTAssertEqual(frames.count, 2, "only the two that could go went: \(frames)")
        XCTAssertEqual(frames.first?["to"] as? String, "iphone")
        XCTAssertEqual((frames.first?["data"] as? [String: Any])?["score"] as? Int, 3)
        XCTAssertNil(frames.last?["to"], "to all")
        let errors = context.evaluateScript("errors.join('\\n')")?.toString() ?? ""
        XCTAssertTrue(errors.contains("not connected"), errors)
        XCTAssertTrue(errors.contains("is not open now"), errors)
        XCTAssertTrue(errors.contains("at most 16384 bytes"), errors)
    }

    /// A relay that can't prove it holds the wish's key gets no proof, and the page lets the link go.
    func testThePageSaysNothingToARelayThatCantProveTheKey() throws {
        let context = try page()
        context.evaluateScript("Lamp.wish.start();")
        settle(context)
        try handshake(context, proof: WishChannel.random(32))
        XCTAssertEqual(context.evaluateScript("sockets[0].closed")?.toBool(), true)
        XCTAssertEqual(context.evaluateScript("Lamp.wish.state()")?.toString(), "connecting")
    }

    /// After the handshake, a sealed message sent again, one changed on the way, or JSON in clear (someone on the network
    /// putting in a welcome of their own): the page lets that link go rather than believe it.
    func testAMessageReplayedChangedOrInClearLetsThePagesLinkGo() throws {
        for attack in ["replayed", "changed", "clear"] {
            let context = try page()
            context.evaluateScript("Lamp.wish.onMessage(function (from, data) { heard.push(from + ':' + JSON.stringify(data)); }); Lamp.wish.start();")
            settle(context)
            try handshake(context)
            deliver(context, ["t": "welcome", "role": "peer", "peer": "tv", "apps": roster, "peers": []])
            let message = try JSONSerialization.data(withJSONObject: ["t": "message", "from": "iphone", "data": 1])
            let sealed = sealer!.seal(message)
            context.evaluateScript("sockets[0].onmessage({ data: bytes('\(sealed.hex)').buffer });")
            switch attack {
            case "replayed": context.evaluateScript("sockets[0].onmessage({ data: bytes('\(sealed.hex)').buffer });")
            case "changed":
                var changed = sealer!.seal(message)
                changed[changed.startIndex] ^= 1
                context.evaluateScript("sockets[0].onmessage({ data: bytes('\(changed.hex)').buffer });")
            default: deliverText(context, ["t": "message", "from": "iphone", "data": 2])
            }
            XCTAssertEqual(context.evaluateScript("heard.join('|')")?.toString(), "iphone:1", "only the real one was heard (\(attack))")
            XCTAssertEqual(context.evaluateScript("sockets[0].closed")?.toBool(), true, attack)
            XCTAssertEqual(context.evaluateScript("Lamp.wish.state()")?.toString(), "connecting", attack)
        }
    }

    /// The wish's list of apps changes while the page is in the room: a new app is known, not open, with its reason; one
    /// still there keeps its status; one taken away is gone.
    func testThePageFollowsTheWishsAppsAsTheyChange() throws {
        let context = try page()
        context.evaluateScript("Lamp.wish.start();")
        settle(context)
        try handshake(context)
        deliver(context, ["t": "welcome", "role": "peer", "peer": "tv",
                          "peers": [["peer": "iphone", "kind": "iphone", "name": "the iPhone app", "device": "iPhone", "since": 1]],
                          "apps": [["peer": "tv", "kind": "tv", "name": "the TV app"], ["peer": "iphone", "kind": "iphone", "name": "the iPhone app"],
                                   ["peer": "mac", "kind": "mac", "name": "the Mac app"]]])
        deliver(context, ["t": "apps", "apps": roster])
        XCTAssertEqual(context.evaluateScript("Lamp.wish.apps().map(function (p) { return p.peer + ':' + p.status.state; }).join(',')")?.toString(),
                       "iphone:connected,android:notOpen")
        XCTAssertEqual(context.evaluateScript("Lamp.wish.peer('android').status.reason")?.toString(), "The Android app isn't open.")
        XCTAssertTrue(context.evaluateScript("Lamp.wish.peer('mac')")?.isNull == true, "taken from the wish")
    }

    func testTurnedAwayThePageAsksLampAgain() throws {
        let context = try page()
        context.evaluateScript("Lamp.wish.start();")
        settle(context)
        context.evaluateScript("sockets[0].onopen(); sockets[0].onclose({ code: 4003 }); later.pop()();")
        settle(context)
        XCTAssertEqual(context.evaluateScript("sent.filter(function (s) { return s.indexOf('\"post\":\"/app/wish\"') >= 0; }).length")?.toInt32(), 2,
                       "asked twice: once at the start, once after being turned away")
        XCTAssertEqual(context.evaluateScript("sockets.length")?.toInt32(), 2)
        try handshake(context, socket: 1)
    }

    /// On a TV, the page Lamp just put there claims the wish's key as it opens: it sends the public half of a key pair it
    /// made, opens the key Lamp sealed to it, keeps it, and joins with it. Lamp's answer to /app/wish says nothing of the
    /// key there.
    func testOnATVThePageClaimsTheKeySealedToItsOwnKeyPair() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("wish-keys-\(UUID().uuidString)")
        let keptKeys = WishKeys.folder
        WishKeys.folder = folder
        defer { WishKeys.folder = keptKeys; try? FileManager.default.removeItem(at: folder) }
        let wish = LampProject(id: "scoreboard", name: "Scoreboard", exe: "Scoreboard", dir: URL(fileURLWithPath: "/tmp/scoreboard"), platform: .tv)
        let phone = LampProject(id: "scoreboard.iphone", name: "Scoreboard", exe: "Scoreboard", dir: URL(fileURLWithPath: "/tmp/scoreboard/iPhone"), platform: .iphone, partOf: "scoreboard")
        let wishKey = WishKeys.key(for: wish)
        var claims: [[String: Any]] = []
        // Lamp's gateway, as the page's XMLHttpRequest reaches it.
        let gateway: @convention(block) (String, String) -> String = { url, body in
            let asked = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any] ?? [:]
            claims.append(asked)
            guard url.hasSuffix("/app/wish/claim"), let ours = (asked["public"] as? String).flatMap({ Data(base64Encoded: $0) }) else { return "" }
            let answer = WishRooms.claim(for: wish, apps: [wish, phone], publicKey: ours).1
            return String(decoding: (try? JSONSerialization.data(withJSONObject: answer)) ?? Data(), as: UTF8.self)
        }
        let context = try page(installed: #"{"app":"scoreboard","routes":["http://192.168.1.20:47821"]}"#,
                               answer: "{ socket: 'ws://192.168.1.20:47900/', peer: 'tv', peers: [], apps: [] }") { context in
            context.setObject(gateway, forKeyedSubscript: "macGateway" as NSString)
            context.evaluateScript("""
                function XMLHttpRequest() {}
                XMLHttpRequest.prototype.open = function (method, url) { this.url = url; };
                XMLHttpRequest.prototype.setRequestHeader = function () {};
                XMLHttpRequest.prototype.send = function (body) { var x = this; x.responseText = macGateway(x.url, body); x.status = x.responseText ? 200 : 403; later.push(function () { x.onload(); }); };
                """)
        }
        context.evaluateScript("while (later.length) later.shift()();")
        settle(context)
        XCTAssertEqual(claims.count, 1)
        XCTAssertEqual(claims.first?["app"] as? String, "scoreboard")
        XCTAssertNil(claims.first?["key"])
        let stored = context.evaluateScript("store['lamp:install.wish']")?.toString() ?? ""
        XCTAssertTrue(stored.contains(wishKey.base64EncodedString()), "kept on the TV: \(stored)")
        context.evaluateScript("Lamp.wish.start();")
        settle(context)
        let join = try handshake(context, key: wishKey)
        XCTAssertEqual(join["device"] as? String, "TV")
    }

    /// The network was down when the page first claimed its key: it tries again while the claim is open, rather than
    /// staying away until the app is opened again.
    func testOnATVAClaimThatFailedIsTriedAgain() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("wish-keys-\(UUID().uuidString)")
        let keptKeys = WishKeys.folder
        WishKeys.folder = folder
        defer { WishKeys.folder = keptKeys; try? FileManager.default.removeItem(at: folder) }
        let wish = LampProject(id: "scoreboard", name: "Scoreboard", exe: "Scoreboard", dir: URL(fileURLWithPath: "/tmp/scoreboard"), platform: .tv)
        let phone = LampProject(id: "scoreboard.iphone", name: "Scoreboard", exe: "Scoreboard", dir: URL(fileURLWithPath: "/tmp/scoreboard/iPhone"), platform: .iphone, partOf: "scoreboard")
        var reachable = false, asked = 0
        let gateway: @convention(block) (String, String) -> String = { url, body in
            asked += 1
            guard reachable, let ours = ((try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any])?["public"] as? String,
                  let data = Data(base64Encoded: ours) else { return "" }
            return String(decoding: (try? JSONSerialization.data(withJSONObject: WishRooms.claim(for: wish, apps: [wish, phone], publicKey: data).1)) ?? Data(), as: UTF8.self)
        }
        let context = try page(installed: #"{"app":"scoreboard","routes":["http://192.168.1.20:47821"]}"#,
                               answer: "{ socket: 'ws://192.168.1.20:47900/', peer: 'tv', peers: [], apps: [] }") { context in
            context.setObject(gateway, forKeyedSubscript: "macGateway" as NSString)
            context.evaluateScript("""
                function XMLHttpRequest() {}
                XMLHttpRequest.prototype.open = function (method, url) { this.url = url; };
                XMLHttpRequest.prototype.setRequestHeader = function () {};
                XMLHttpRequest.prototype.send = function (body) { var x = this, r = macGateway(x.url, body); later.push(function () { if (r) { x.responseText = r; x.status = 200; x.onload(); } else x.onerror(); }); };
                """)
        }
        context.evaluateScript("Lamp.wish.start();")
        // Every timer and answer that was waiting, until none is: the network still down.
        for _ in 0..<6 { context.evaluateScript("while (later.length) later.shift()();"); settle(context) }
        XCTAssertEqual(context.evaluateScript("Lamp.wish.state()")?.toString(), "away")
        XCTAssertEqual(context.evaluateScript("sockets.length")?.toInt32(), 0)
        reachable = true
        let before = asked
        for _ in 0..<6 { context.evaluateScript("while (later.length) later.shift()();"); settle(context) }
        XCTAssertGreaterThan(asked, before, "the claim was tried again")
        XCTAssertEqual(context.evaluateScript("sockets.length")?.toInt32(), 1, "and with the key, the page opened its link")
    }

    /// Lamp answered the page's claim and spent it, but the answer never reached the TV: the page asks again with the
    /// same key pair and is answered again, so a dropped connection doesn't need another install.
    func testOnATVAnAnswerLostOnItsWayIsAskedForAgain() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("wish-keys-\(UUID().uuidString)")
        let keptKeys = WishKeys.folder
        WishKeys.folder = folder
        defer { WishKeys.folder = keptKeys; try? FileManager.default.removeItem(at: folder) }
        let wish = LampProject(id: "scoreboard", name: "Scoreboard", exe: "Scoreboard", dir: URL(fileURLWithPath: "/tmp/scoreboard"), platform: .tv)
        let phone = LampProject(id: "scoreboard.iphone", name: "Scoreboard", exe: "Scoreboard", dir: URL(fileURLWithPath: "/tmp/scoreboard/iPhone"), platform: .iphone, partOf: "scoreboard")
        WishClaims.shared.open(wish.id, from: "192.168.1.30")
        var publics: [String] = []
        let gateway: @convention(block) (String, String) -> String = { _, body in
            guard let ours = ((try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any])?["public"] as? String,
                  let data = Data(base64Encoded: ours) else { return "" }
            publics.append(ours)
            let answer = WishRooms.claim(for: wish, wish: wish, apps: [wish, phone], publicKey: data, from: "192.168.1.30")
            // The first answer is lost on its way, after Lamp gave it.
            guard publics.count > 1, answer.0 == 200 else { return "" }
            return String(decoding: (try? JSONSerialization.data(withJSONObject: answer.1)) ?? Data(), as: UTF8.self)
        }
        let context = try page(installed: #"{"app":"scoreboard","routes":["http://192.168.1.20:47821"]}"#,
                               answer: "{ socket: 'ws://192.168.1.20:47900/', peer: 'tv', peers: [], apps: [] }") { context in
            context.setObject(gateway, forKeyedSubscript: "macGateway" as NSString)
            context.evaluateScript("""
                function XMLHttpRequest() {}
                XMLHttpRequest.prototype.open = function (method, url) { this.url = url; };
                XMLHttpRequest.prototype.setRequestHeader = function () {};
                XMLHttpRequest.prototype.send = function (body) { var x = this, r = macGateway(x.url, body); later.push(function () { if (r) { x.responseText = r; x.status = 200; x.onload(); } else x.onerror(); }); };
                """)
        }
        context.evaluateScript("Lamp.wish.start();")
        for _ in 0..<8 { context.evaluateScript("while (later.length) later.shift()();"); settle(context) }
        XCTAssertGreaterThan(publics.count, 1, "asked again")
        XCTAssertEqual(Set(publics).count, 1, "with the same key pair")
        XCTAssertEqual(context.evaluateScript("sockets.length")?.toInt32(), 1, "and with the key, the page opened its link")
    }

    private static func parse(_ text: String) -> [String: Any]? { (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] }
    private static func quoted(_ text: String) -> String {
        String(decoding: (try? JSONSerialization.data(withJSONObject: [text])) ?? Data(), as: UTF8.self).dropFirst().dropLast().description
    }
}

extension Data {
    init(hexString: String) {
        var bytes: [UInt8] = []
        var index = hexString.startIndex
        while index < hexString.endIndex, let next = hexString.index(index, offsetBy: 2, limitedBy: hexString.endIndex) {
            bytes.append(UInt8(hexString[index..<next], radix: 16) ?? 0)
            index = next
        }
        self.init(bytes)
    }
}
