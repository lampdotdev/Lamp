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
                       "notOpen|Open the Android app on your Android device.")
        XCTAssertEqual(context.evaluateScript("Lamp.wish.peer('iphone').status.reason")?.toString(),
                       "The iPhone app was last open a moment ago. Open it on your iPhone.")
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
        let before = sentItems(context).count
        deliver(context, ["t": "welcome", "role": "peer", "peer": "tv", "apps": roster,
                          "peers": [["peer": "iphone", "kind": "iphone", "name": "the iPhone app", "device": "iPhone", "since": 1]]])
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
        let said = try sentItems(context).dropFirst(before).map(opened)
        // Once in the room the page tells it how its link stands, for the builder: connected, straight to no app yet.
        XCTAssertEqual(said.first?["t"] as? String, "status")
        XCTAssertEqual(said.first?["state"] as? String, "connected")
        XCTAssertEqual(said.first?["direct"] as? [String], [])
        let frames = Array(said.dropFirst())
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
                          "peers": [["peer": "iphone", "kind": "iphone", "name": "the iPhone app", "device": "iPhone", "since": 1, "wire": 5]],
                          "apps": [["peer": "tv", "kind": "tv", "name": "the TV app"], ["peer": "iphone", "kind": "iphone", "name": "the iPhone app"],
                                   ["peer": "mac", "kind": "mac", "name": "the Mac app"]]])
        deliver(context, ["t": "apps", "apps": roster])
        XCTAssertEqual(context.evaluateScript("Lamp.wish.apps().map(function (p) { return p.peer + ':' + p.status.state; }).join(',')")?.toString(),
                       "iphone:connected,android:notOpen")
        XCTAssertEqual(context.evaluateScript("Lamp.wish.peer('android').status.reason")?.toString(), "Open the Android app on your Android device.")
        XCTAssertTrue(context.evaluateScript("Lamp.wish.peer('mac')")?.isNull == true, "taken from the wish")
    }

    /// An app the wish asks for and Lamp hasn't made says it isn't ready; when another app was last open is kept on the
    /// device, so a page opened again later still says how long ago; and the status view shows each app's line and follows
    /// as they change.
    func testThePageSaysWhatsMissingAndKeepsWhenAnAppWasLastOpen() throws {
        let context = try page(before: Self.document)
        context.evaluateScript("var view = Lamp.wish.statusView(); Lamp.wish.start();")
        settle(context)
        try handshake(context)
        let apps: [[String: Any]] = [["peer": "tv", "kind": "tv", "name": "the TV app"], ["peer": "iphone", "kind": "iphone", "name": "the iPhone app"],
                                     ["peer": "android", "kind": "android", "name": "the Android app", "waiting": true]]
        deliver(context, ["t": "welcome", "role": "peer", "peer": "tv", "apps": apps,
                          "peers": [["peer": "iphone", "kind": "iphone", "name": "the iPhone app", "device": "iPhone", "since": 1, "wire": 5]]])
        XCTAssertEqual(context.evaluateScript("Lamp.wish.peer('android').status.reason")?.toString(), "The Android app isn't ready yet.")
        XCTAssertEqual(context.evaluateScript("view.text()")?.toString(), "iPhone app connected|The Android app isn't ready yet.")
        deliver(context, ["t": "left", "peer": "iphone"])
        XCTAssertEqual(context.evaluateScript("view.text()")?.toString(),
                       "The iPhone app was last open a moment ago. Open it on your iPhone.|The Android app isn't ready yet.")

        // Opened again later: what was kept says when the iPhone app was last open, 5 minutes before now.
        let kept = try XCTUnwrap(context.evaluateScript("""
            (function () { for (var k in store) if (k.indexOf('lamp:wish.') === 0) {
              var v = JSON.parse(store[k]); v.seen.iphone = Date.now() - 5 * 60000 - 1000; store[k] = JSON.stringify(v); }
              return JSON.stringify(store); })()
            """)?.toString())
        let again = try page(before: { $0.evaluateScript("store = \(kept);") })
        again.evaluateScript("Lamp.wish.start();")
        settle(again)
        XCTAssertEqual(again.evaluateScript("Lamp.wish.peer('iphone').status.reason")?.toString(),
                       "The iPhone app was last open 5 min ago. Open it on your iPhone.")
        XCTAssertEqual(again.evaluateScript("Lamp.wish.peer('android').status.reason")?.toString(), "The Android app isn't ready yet.")
    }

    /// What a page says stays right as the beats go by: a copy that wasn't opened from Lamp keeps saying so, and an app
    /// once marked not made yet, then open, is never called not ready again.
    func testWhatThePageSaysStaysRightAsTheBeatsGoBy() throws {
        let beats = "var beaters = []; setInterval = function (fn) { beaters.push(fn); return 1; };"
        let stray = try page(installed: "null", before: { $0.evaluateScript(beats) })
        stray.evaluateScript("Lamp.wish.start(); beaters[0](); beaters[0]();")
        XCTAssertEqual(stray.evaluateScript("Lamp.wish.status().reason")?.toString(),
                       "This copy wasn't opened from Lamp, so it can't reach the wish's other apps. Open it from Lamp on your Mac.")

        let context = try page(before: { $0.evaluateScript(beats) })
        context.evaluateScript("Lamp.wish.start();")
        settle(context)
        try handshake(context)
        let apps: [[String: Any]] = [["peer": "tv", "kind": "tv", "name": "the TV app"], ["peer": "android", "kind": "android", "name": "the Android app", "waiting": true]]
        deliver(context, ["t": "welcome", "role": "peer", "peer": "tv", "apps": apps, "peers": []])
        // Made and open now, though the list hasn't said so yet (Lamp closed, the apps meeting straight).
        deliver(context, ["t": "joined", "peer": ["peer": "android", "kind": "android", "name": "the Android app", "device": "Android", "since": 2]])
        deliver(context, ["t": "left", "peer": "android"])
        context.evaluateScript("beaters[0]();")
        XCTAssertEqual(context.evaluateScript("Lamp.wish.peer('android').status.reason")?.toString(),
                       "The Android app was last open a moment ago. Open it on your Android device.")
    }

    /// A page's own view of every app hears a closed app's reason age as the beats go by, and an app once open is never
    /// called not ready again by a list that still marks it so.
    func testEveryAppsReasonIsHeardAsItChangesAndBeingSeenOutranksAWaitingMark() throws {
        let context = try page(before: { $0.evaluateScript("""
            var beaters = []; setInterval = function (fn) { beaters.push(fn); return 1; };
            var clock = Date.now(); Date.now = function () { return clock; };
            """) })
        context.evaluateScript("var heardApps = []; Lamp.wish.onApps(function (list) { heardApps.push(list.map(function (p) { return p.peer + ':' + p.status.reason; }).join('|')); }); Lamp.wish.start();")
        settle(context)
        try handshake(context)
        let apps: [[String: Any]] = [["peer": "tv", "kind": "tv", "name": "the TV app"], ["peer": "android", "kind": "android", "name": "the Android app", "waiting": true]]
        deliver(context, ["t": "welcome", "role": "peer", "peer": "tv", "apps": apps, "peers": []])
        deliver(context, ["t": "joined", "peer": ["peer": "android", "kind": "android", "name": "the Android app", "device": "Android", "since": 2]])
        deliver(context, ["t": "left", "peer": "android"])
        // Lamp's list comes again still marking it not made (sent before it knew).
        deliver(context, ["t": "apps", "apps": apps])
        XCTAssertEqual(context.evaluateScript("Lamp.wish.peer('android').status.reason")?.toString(),
                       "The Android app was last open a moment ago. Open it on your Android device.")
        context.evaluateScript("clock += 5 * 60000 + 1000; beaters[0]();")
        XCTAssertEqual(context.evaluateScript("heardApps[heardApps.length - 1]")?.toString(),
                       "android:The Android app was last open 5 min ago. Open it on your Android device.")
    }

    /// Values set before any other app is there are kept and go to each app as it comes, with this page's name in when
    /// they were set; what another app sends is taken only when it's later than what the page has, a removal included;
    /// what the page sets after hearing a later one is later still; and it's all still there when the page opens again.
    func testValuesGoToEachAppAsItComesAndTheLaterSettingWins() throws {
        let context = try page()
        context.evaluateScript("""
            var changes = [];
            Lamp.wish.onChange(function (key, value, from) { changes.push(key + '=' + JSON.stringify(value) + ' from ' + from); });
            var early = Lamp.wish.set('list', ['milk']);
            var odd = Lamp.wish.set('odd', function () {});
            var big = Lamp.wish.set('big', new Array(9000).join('a'));
            var unnamed = Lamp.wish.set('', 1);
            Lamp.wish.start();
            """)
        settle(context)
        XCTAssertEqual(context.evaluateScript("[early, odd, big, unnamed].join(',')")?.toString(), "true,false,false,false",
                       "set with nobody there, and refused when it can't be a value")
        let join = try handshake(context)
        XCTAssertEqual(join["wire"] as? Int, 5, "the page says what it speaks")
        let before = sentItems(context).count
        deliver(context, ["t": "welcome", "role": "peer", "peer": "tv", "apps": roster,
                          "peers": [["peer": "iphone", "kind": "iphone", "name": "the iPhone app", "device": "iPhone", "since": 1, "wire": 5]]])
        let pushed = try XCTUnwrap(try sentItems(context).dropFirst(before).map(opened).first { $0["t"] as? String == "values" })
        XCTAssertEqual(pushed["to"] as? String, "iphone")
        let list = try XCTUnwrap((pushed["values"] as? [String: Any])?["list"] as? [String: Any])
        XCTAssertEqual(list["v"] as? [String], ["milk"])
        XCTAssertTrue(((list["c"] as? [Any])?.last as? String)?.hasPrefix("tv.") == true, "stamped with the page's copy: \(list)")

        let later = Int(Date().timeIntervalSince1970 * 1000) + 60_000
        deliver(context, ["t": "values", "from": "iphone", "values": ["list": ["v": ["eggs"], "c": [1, 0, "iphone"]],
                                                                      "score": ["v": 3, "c": [later, 0, "iphone"]]]])
        XCTAssertEqual(context.evaluateScript("JSON.stringify(Lamp.wish.values())")?.toString(), #"{"list":["milk"],"score":3}"#,
                       "an older setting is left, a later one taken")
        deliver(context, ["t": "values", "from": "iphone", "values": ["list": ["c": [later, 1, "iphone"]]]])
        XCTAssertEqual(context.evaluateScript("JSON.stringify(Lamp.wish.values())")?.toString(), #"{"score":3}"#, "removed")
        let sentBefore = sentItems(context).count
        context.evaluateScript("Lamp.wish.set('score', 4);")
        let mine = try XCTUnwrap(try sentItems(context).dropFirst(sentBefore).map(opened).first)
        let stamp = try XCTUnwrap(((mine["values"] as? [String: Any])?["score"] as? [String: Any])?["c"] as? [Any])
        XCTAssertGreaterThanOrEqual(stamp.first as? Int ?? 0, later, "later than the latest it heard of, whatever this device's clock says")
        XCTAssertEqual(context.evaluateScript("changes.join('|')")?.toString(),
                       #"list=["milk"] from |score=3 from iphone|list=null from iphone|score=4 from tv"#,
                       "a change made here is from this page's name, none yet before it first joined")

        let kept = try XCTUnwrap(context.evaluateScript("JSON.stringify(store)")?.toString())
        let again = try page(before: { $0.evaluateScript("store = \(kept);") })
        again.evaluateScript("Lamp.wish.start();")
        settle(again)
        XCTAssertEqual(again.evaluateScript("JSON.stringify(Lamp.wish.values())")?.toString(), #"{"score":4}"#)
    }

    /// A setting lost on the way is made up: an app whose values add up differently is sent all of the page's and asked
    /// for all of its, and an app that asks is sent all. Names a page's objects already hold are only values here, and
    /// one called `__proto__` is refused; NaN removes, as it reads back as null everywhere.
    func testALostSettingIsMadeUpAndOddNamesAreJustNames() throws {
        let context = try page()
        context.evaluateScript("""
            var changes = [];
            Lamp.wish.onChange(function (key, value, from) { changes.push(key + '=' + JSON.stringify(value)); });
            Lamp.wish.set('list', ['milk']);
            var proto = Lamp.wish.set('__proto__', 1);
            Lamp.wish.start();
            """)
        settle(context)
        try handshake(context)
        var seen = sentItems(context).count
        func said() throws -> [[String: Any]] {
            let items = try sentItems(context).dropFirst(seen).map(opened)
            seen = sentItems(context).count
            return items
        }
        deliver(context, ["t": "welcome", "role": "peer", "peer": "tv", "apps": roster,
                          "peers": [["peer": "iphone", "kind": "iphone", "name": "the iPhone app", "device": "iPhone", "since": 1, "wire": 5]]])
        _ = try said()
        XCTAssertEqual(context.evaluateScript("proto")?.toBool(), false)
        let later = Int(Date().timeIntervalSince1970 * 1000) + 60_000
        deliver(context, ["t": "values", "from": "iphone", "values": ["constructor": ["v": 1, "c": [later, 0, "iphone"]],
                                                                      "toString": ["v": "x", "c": [later, 0, "iphone"]]]])
        XCTAssertEqual(context.evaluateScript("JSON.stringify(Lamp.wish.values())")?.toString(), #"{"list":["milk"],"constructor":1,"toString":"x"}"#)
        context.evaluateScript("Lamp.wish.set('constructor', NaN);")
        _ = try said()
        XCTAssertEqual(context.evaluateScript("JSON.stringify(Lamp.wish.values())")?.toString(), #"{"list":["milk"],"toString":"x"}"#)

        deliver(context, ["t": "values", "from": "iphone", "values": [:], "sum": "AAAAAAAAAAA="])
        let answer = try said()
        XCTAssertEqual(answer.count, 1)
        XCTAssertEqual(answer.first?["ask"] as? Bool, true, "asked for all of the other app's")
        XCTAssertEqual(Set((answer.first?["values"] as? [String: Any])?.keys ?? [:].keys), ["list", "constructor", "toString"], "and sent all of its own")
        deliver(context, ["t": "values", "from": "iphone", "values": [:], "ask": true])
        let all = try said()
        XCTAssertEqual(all.count, 1)
        XCTAssertNil(all.first?["ask"], "an answer to a request asks nothing back")
        XCTAssertEqual((all.first?["values"] as? [String: Any])?.count, 3)
        XCTAssertTrue((context.evaluateScript("errors.join('|')")?.toString() ?? "").contains("not __proto__"))
    }

    /// A catch-up is cut into messages by their size as they go, names escaped as JSON included, so none passes what a
    /// message may be, even when every name is made of characters JSON writes six bytes for.
    func testCatchUpMessagesStayWithinAMessageWhateverTheNames() throws {
        let context = try page()
        context.evaluateScript("""
            var odd = new Array(61).join(String.fromCharCode(1));
            for (var i = 100; i < 200; i++) Lamp.wish.set(odd + i, 1);
            Lamp.wish.start();
            """)
        settle(context)
        try handshake(context)
        let before = sentItems(context).count
        deliver(context, ["t": "welcome", "role": "peer", "peer": "tv", "apps": roster,
                          "peers": [["peer": "iphone", "kind": "iphone", "name": "the iPhone app", "device": "iPhone", "since": 1, "wire": 5]]])
        let frames = sentItems(context).dropFirst(before)
        let values = try frames.map(opened).filter { $0["t"] as? String == "values" }
        XCTAssertEqual(values.reduce(0) { $0 + (($1["values"] as? [String: Any])?.count ?? 0) }, 100, "every value went")
        for frame in frames { XCTAssertLessThanOrEqual((frame.count - "sealed:".count) / 2 - 16, 16384, "a message within the limit") }
    }

    /// Three apps that each filled the values while apart end with the same values whichever order the others' arrive
    /// in: what another app set is held only to the limit of one value.
    func testAppsThatEachFilledTheValuesApartAgreeWhateverTheOrder() throws {
        func filled(_ peer: String) -> [String: Any] {
            Dictionary(uniqueKeysWithValues: (0..<7).map { ("\(peer)\($0)", ["v": String(repeating: "x", count: 8190), "c": [1000 + $0, 0, peer]] as [String: Any]) })
        }
        var ends: [String] = []
        for order in [["iphone", "android"], ["android", "iphone"]] {
            let context = try page()
            context.evaluateScript("for (var i = 0; i < 7; i++) Lamp.wish.set('tv' + i, new Array(8191).join('x')); Lamp.wish.start();")
            settle(context)
            try handshake(context)
            deliver(context, ["t": "welcome", "role": "peer", "peer": "tv", "apps": roster, "peers": []])
            for peer in order { deliver(context, ["t": "values", "from": peer, "values": filled(peer)]) }
            ends.append(context.evaluateScript("Object.keys(Lamp.wish.values()).sort().join(',')")?.toString() ?? "")
        }
        XCTAssertEqual(ends[0], ends[1])
        XCTAssertEqual(ends[0].split(separator: ",").count, 21, "all of each app's values: \(ends[0])")
    }

    /// An app of the wish that floods another with values (hostile, or wrong) gets no further than what every app of the
    /// wish could have set between them: the wish's apps times the limit of the whole, with room to spare.
    func testAFloodOfValuesPastWhatTheWishsAppsCouldSetIsDropped() throws {
        let context = try page()
        context.evaluateScript("Lamp.wish.start();")
        settle(context)
        try handshake(context)
        deliver(context, ["t": "welcome", "role": "peer", "peer": "tv", "apps": roster, "peers": []])
        let later = Int(Date().timeIntervalSince1970 * 1000) + 60_000
        for batch in 0..<100 {
            deliver(context, ["t": "values", "from": "iphone",
                              "values": ["flood\(batch)": ["v": String(repeating: "x", count: 8190), "c": [later + batch, 0, "iphone"]]]])
        }
        let held = context.evaluateScript("var o = Lamp.wish.values(), b = 0, n = 0; for (var k in o) { n++; b += k.length + JSON.stringify(o[k]).length; } [n, b]")?.toArray() as? [Int] ?? []
        XCTAssertGreaterThan(held.first ?? 0, 0, "values within the bound are taken")
        XCTAssertLessThan(held.first ?? 100, 100, "the flood past it is dropped: \(held)")
        XCTAssertLessThanOrEqual(held.last ?? .max, 3 * 2 * 65536, "three apps' worth of the whole, twice over")
    }

    /// Removals never stop at the bound: an app that removes thousands of small values it set, more than the bound holds
    /// as removals, still leaves every other app without them; and a value set after removals filled the bound is taken,
    /// the oldest removals letting it in.
    func testRemovalsAlwaysGoAndAValueOutranksOldRemovalsAtTheBound() throws {
        let two: [[String: Any]] = [["peer": "tv", "kind": "tv", "name": "the TV app"], ["peer": "iphone", "kind": "iphone", "name": "the iPhone app"]]
        let start = Int(Date().timeIntervalSince1970 * 1000)
        func names(_ prefix: String) -> [String] { (0..<8000).map { String(format: "\(prefix)%04d", $0) } }
        func send(_ context: JSContext, _ list: [String], stamp: Int, value: Any?) {
            for chunk in stride(from: 0, to: list.count, by: 1000) {
                var values: [String: Any] = [:]
                for (i, name) in list[chunk..<min(chunk + 1000, list.count)].enumerated() {
                    values[name] = value.map { ["v": $0, "c": [stamp, chunk + i, "iphone"]] } ?? ["c": [stamp, chunk + i, "iphone"]]
                }
                deliver(context, ["t": "values", "from": "iphone", "values": values])
            }
        }
        func joined() throws -> JSContext {
            let context = try page()
            context.evaluateScript("Lamp.wish.start();")
            settle(context)
            try handshake(context)
            deliver(context, ["t": "welcome", "role": "peer", "peer": "tv", "apps": two, "peers": []])
            return context
        }

        // 8,000 values of 1 under five-byte names, more than the bound holds, then each removed: every one taken goes.
        let kept = try joined()
        send(kept, names("k"), stamp: start, value: 1)
        XCTAssertGreaterThan(kept.evaluateScript("Object.keys(Lamp.wish.values()).length")?.toInt32() ?? 0, 0)
        send(kept, names("k"), stamp: start + 1, value: nil)
        XCTAssertEqual(kept.evaluateScript("Object.keys(Lamp.wish.values()).length")?.toInt32(), 0, "every removal went")

        // Removals of names never set, past the bound; then a real value of 4 KB.
        let crowded = try joined()
        send(crowded, names("r"), stamp: start, value: nil)
        deliver(crowded, ["t": "values", "from": "iphone", "values": ["real": ["v": String(repeating: "x", count: 4000), "c": [start + 1, 0, "iphone"]]]])
        XCTAssertEqual(crowded.evaluateScript("typeof Lamp.wish.values().real")?.toString(), "string", "the value was taken")
    }

    /// Every name an app sets counts at least 32 bytes against the limit of the whole, and so does a name it removed
    /// while the removal is kept: so all an app can make, removals included, fits in what another app takes from it,
    /// no removal there is ever let go, and an older copy from an app that was away can't bring a removed value back.
    func testAnAppThatWasAwayCantBringBackWhatAnotherRemoved() throws {
        // As much as one app can set under small names, then all of it removed.
        let setter = try page()
        setter.evaluateScript("""
            var made = [];
            for (var i = 0; i < 20000; i++) { var k = 'k' + ('0000' + i.toString(36)).slice(-4); if (!Lamp.wish.set(k, 1)) break; made.push(k); }
            var removed = made.every(function (k) { return Lamp.wish.set(k, null); });
            """)
        let made = setter.evaluateScript("made")?.toArray() as? [String] ?? []
        XCTAssertEqual(setter.evaluateScript("removed")?.toBool(), true, "every removal was made")
        XCTAssertLessThanOrEqual(made.count * (5 + 32), 65536, "each name counts at least 32 bytes: \(made.count)")

        // Another app of a wish of three had them, took every removal, then hears an older copy from the app that was away.
        let three: [[String: Any]] = [["peer": "tv", "kind": "tv", "name": "the TV app"], ["peer": "iphone", "kind": "iphone", "name": "the iPhone app"],
                                      ["peer": "android", "kind": "android", "name": "the Android app"]]
        let context = try page()
        context.evaluateScript("Lamp.wish.start();")
        settle(context)
        try handshake(context)
        deliver(context, ["t": "welcome", "role": "peer", "peer": "tv", "apps": three, "peers": []])
        let start = Int(Date().timeIntervalSince1970 * 1000)
        func send(from peer: String, stamp: Int, value: Any?) {
            for chunk in stride(from: 0, to: made.count, by: 1000) {
                var values: [String: Any] = [:]
                for (i, name) in made[chunk..<min(chunk + 1000, made.count)].enumerated() {
                    values[name] = value.map { ["v": $0, "c": [stamp, chunk + i, "iphone"]] } ?? ["c": [stamp, chunk + i, "iphone"]]
                }
                deliver(context, ["t": "values", "from": peer, "values": values])
            }
        }
        send(from: "iphone", stamp: start, value: 1)
        send(from: "iphone", stamp: start + 1, value: nil)
        send(from: "android", stamp: start, value: 1)
        XCTAssertEqual(context.evaluateScript("Object.keys(Lamp.wish.values()).length")?.toInt32(), 0, "nothing removed came back")
    }

    /// Removals kept a month are let go when the month is over, before anything is weighed against the limit, so an app
    /// whose removals filled it can set values again then, even if nothing else happened meanwhile.
    func testExpiredRemovalsMakeRoomEvenInAnIdleApp() throws {
        let context = try page(before: { $0.evaluateScript("var clock = Date.now(); Date.now = function () { return clock; };") })
        context.evaluateScript("""
            var made = [];
            for (var i = 0; i < 20000; i++) { var k = 'k' + ('0000' + i.toString(36)).slice(-4); if (!Lamp.wish.set(k, 1)) break; made.push(k); }
            made.forEach(function (k) { Lamp.wish.set(k, null); });
            var full = Lamp.wish.set('fresh', 'x');
            clock += 31 * 24 * 3600 * 1000;
            var later = Lamp.wish.set('fresh', 'x');
            """)
        XCTAssertEqual(context.evaluateScript("full")?.toBool(), false, "the removals fill the limit while they're kept")
        XCTAssertEqual(context.evaluateScript("later")?.toBool(), true, "a month on, they're let go and the value is set")
    }

    /// An open app built by another Lamp is shown as out of date, still open, with what to do in words to show: an
    /// older one (saying nothing of what it speaks) is to be opened from Lamp, a newer one means this one is. An older
    /// one is sent no values; the status view shows the line.
    func testAnAppBuiltByAnotherLampIsOutOfDate() throws {
        let context = try page(before: Self.document)
        context.evaluateScript("var view = Lamp.wish.statusView(); Lamp.wish.set('score', 1); Lamp.wish.start();")
        settle(context)
        try handshake(context)
        let before = sentItems(context).count
        deliver(context, ["t": "welcome", "role": "peer", "peer": "tv", "apps": roster,
                          "peers": [["peer": "iphone", "kind": "iphone", "name": "the iPhone app", "device": "iPhone", "since": 1],
                                    ["peer": "android", "kind": "android", "name": "the Android app", "device": "Android", "since": 1, "wire": 6]]])
        XCTAssertEqual(context.evaluateScript("var p = Lamp.wish.peer('iphone'); p.open + '|' + p.status.state + '|' + p.status.reason")?.toString(),
                       "true|outOfDate|The iPhone app is out of date. Open it from Lamp on your Mac to update it.")
        XCTAssertEqual(context.evaluateScript("Lamp.wish.peer('android').status.reason")?.toString(),
                       "This app is older than the Android app. Open it from Lamp on your Mac to update it.")
        XCTAssertEqual(context.evaluateScript("view.text()")?.toString(),
                       "The iPhone app is out of date. Open it from Lamp on your Mac to update it.|This app is older than the Android app. Open it from Lamp on your Mac to update it.")
        let pushed = try sentItems(context).dropFirst(before).map(opened).filter { $0["t"] as? String == "values" }
        XCTAssertEqual(pushed.map { $0["to"] as? String }, ["android"], "the app from before values is sent none")
    }

    /// Just enough of a page's document for the status view: elements that hold children, a style and text.
    private static func document(_ context: JSContext) {
        context.evaluateScript("""
            function Element() { this.children = []; this.style = {}; this.textContent = ''; }
            Object.defineProperty(Element.prototype, 'firstChild', { get: function () { return this.children[0] || null; } });
            Element.prototype.appendChild = function (c) { this.children.push(c); return c; };
            Element.prototype.removeChild = function (c) { this.children.splice(this.children.indexOf(c), 1); return c; };
            Element.prototype.text = function () {
              return this.children.map(function (row) { return row.children.map(function (c) { return c.textContent; }).join(''); }).join('|');
            };
            var document = { createElement: function () { return new Element(); } };
            """)
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

    /// A TV page looks for the apps Lamp's room doesn't have on its own network at each one's port, a few dozen addresses
    /// at a time. Once that's done, finding one of them doesn't keep it from dialling another when it's told where that one
    /// is.
    func testATVPageSweepsItsNetworkAndStillDialsAnAppItsToldOfAfter() throws {
        let apps: [[String: Any]] = [["peer": "tv", "kind": "tv", "name": "the TV app"], ["peer": "mac", "kind": "mac", "name": "the Mac app"],
                                     ["peer": "iphone", "kind": "iphone", "name": "the iPhone app"]]
        let roster = String(decoding: try JSONSerialization.data(withJSONObject: apps), as: UTF8.self)
        let context = try page(answer: "{ socket: 'ws://127.0.0.1:47900/', peer: 'tv', key: '\(key.base64EncodedString())', peers: [], apps: \(roster) }") { context in
            context.evaluateScript("window.tizen = { systeminfo: { getPropertyValue: function (kind, ok) { if (kind === 'WIFI_NETWORK') ok({ ipAddress: '10.0.0.5' }); } } };")
        }
        context.evaluateScript("Lamp.wish.start();")
        settle(context)
        try handshake(context)
        deliver(context, ["t": "welcome", "role": "peer", "peer": "tv", "apps": apps, "peers": []])
        // The wish's port for each app, by its place in the sorted list: iphone, mac, tv.
        let d = WishChannel.derive("lamp-wish port", key: SymmetricKey(data: key))
        let base = 20000 + (Int(d[0]) << 8 | Int(d[1])) % 1500 * 8
        XCTAssertEqual(context.evaluateScript("Object.keys(sockets).length")?.toInt32(), 33, "Lamp's room and 32 addresses at a time")
        let mac = "ws://10.0.0.1:\(base + 1)/"
        let n = try XCTUnwrap(context.evaluateScript("sockets.map(function (s) { return s.url; }).indexOf('\(mac)')")?.toInt32(), "the Mac app's port tried at the first address")
        XCTAssertGreaterThan(n, 0)
        // The Mac app answers there: it proves it holds the wish's key and names itself, and the page joins.
        context.evaluateScript("sockets[\(n)].onopen();")
        let hello = try XCTUnwrap(sentItems(context).last.flatMap(Self.parse))
        // The page names itself as its copy of the TV app.
        let me = try XCTUnwrap(hello["peer"] as? String)
        XCTAssertTrue(me.hasPrefix("tv."), me)
        let wishKey = SymmetricKey(data: key)
        let tag = try XCTUnwrap((hello["tag"] as? String).flatMap { Data(base64Encoded: $0) })
        let nonce = try XCTUnwrap((hello["nonce"] as? String).flatMap { Data(base64Encoded: $0) })
        let ours = WishChannel.random(16)
        let transcript = WishChannel.transcript(tag: tag, client: me, server: "mac", clientNonce: nonce, serverNonce: ours)
        deliverText(context, socket: Int(n), ["t": "challenge", "peer": "mac", "nonce": ours.base64EncodedString(),
                                              "proof": WishChannel.serverProof(key: wishKey, transcript: transcript).base64EncodedString()])
        let keys = WishChannel.keys(key: wishKey, transcript: transcript)
        var toPage = WishChannel.Sealer(key: keys.server)
        let welcome = toPage.seal(try JSONSerialization.data(withJSONObject: ["t": "welcome", "peer": "mac", "device": "Mac"]))
        context.evaluateScript("sockets[\(n)].onmessage({ data: bytes('\(welcome.hex)').buffer });")
        XCTAssertEqual(context.evaluateScript("Lamp.wish.peer('mac').open")?.toBool(), true, "the Mac app is open, straight")
        XCTAssertEqual(context.evaluateScript("Lamp.wish.peer('mac').device")?.toString(), "Mac")
        // Nothing else answers anywhere on the network.
        for _ in 0..<40 {
            context.evaluateScript("for (var i = 1; i < sockets.length; i++) if (i !== \(n) && !sockets[i].ended) { sockets[i].ended = true; sockets[i].onclose({ code: 1006 }); }")
        }
        XCTAssertEqual(context.evaluateScript("sockets.filter(function (s) { return /:\(base)\\/$/.test(s.url); }).length")?.toInt32(), 254,
                       "every address once for the iPhone app, which nothing answered for")
        // Lamp's room says where the iPhone app listens: the page dials it there.
        deliver(context, ["t": "at", "peer": "iphone", "addresses": ["10.0.0.9:\(base)"]])
        XCTAssertEqual(context.evaluateScript("sockets[sockets.length - 1].url")?.toString(), "ws://10.0.0.9:\(base)/")
    }

    /// A page in the room whose list holds a Mac app, with time it can move on, beats it can run and a socket it can close.
    private func roomPage(apps: [[String: Any]], peers: [[String: Any]] = []) throws -> JSContext {
        let context = try page { context in
            context.evaluateScript("var now = 1000000, beats = []; Date.now = function () { return now; }; function setInterval(fn) { beats.push(fn); return 1; }")
        }
        context.evaluateScript("Lamp.wish.start();")
        settle(context)
        try handshake(context)
        deliver(context, ["t": "welcome", "role": "peer", "peer": "tv", "apps": apps, "peers": peers])
        return context
    }
    private let macAndTV: [[String: Any]] = [["peer": "tv", "kind": "tv", "name": "the TV app"], ["peer": "mac", "kind": "mac", "name": "the Mac app"]]
    private func urls(_ context: JSContext) -> [String] { context.evaluateScript("sockets.map(function (s) { return s.url; })")?.toArray() as? [String] ?? [] }

    /// A message for all the wish's apps goes through Lamp's room to each with its name added: it's measured that way, so
    /// one the room would turn away is refused here, with why, rather than said to be sent.
    func testAMessageToAllIsMeasuredAsItGoesToEachApp() throws {
        let context = try roomPage(apps: roster, peers: [["peer": "iphone", "kind": "iphone", "name": "the iPhone app", "device": "iPhone", "since": 1],
                                                         ["peer": "android", "kind": "android", "name": "the Android app", "device": "Android", "since": 1]])
        let sent = context.evaluateScript("""
            var pad = new Array(16384 - JSON.stringify({ t: 'send', data: '' }).length + 1).join('A');
            JSON.stringify({ t: 'send', data: pad }).length + '|' + Lamp.wish.send(pad)
            """)?.toString()
        XCTAssertEqual(sent, "16384|false", "16,384 bytes alone, more once it names the app it's for")
        XCTAssertTrue((context.evaluateScript("errors.join('\\n')")?.toString() ?? "").contains("at most 16384 bytes"))
    }

    /// The Mac app listens on a port of its own (another program has the wish's), which Lamp's room told the page. Its
    /// first two tries there fail; from then on the page sweeps its network too, and goes on trying there as well.
    func testATVPageGoesOnTryingWhereAnAppSaidItListens() throws {
        let context = try roomPage(apps: macAndTV)
        deliver(context, ["t": "at", "peer": "mac", "addresses": ["10.0.0.9:45000"]])
        for _ in 0..<3 {
            context.evaluateScript("""
                var told = sockets.filter(function (s) { return s.url === 'ws://10.0.0.9:45000/'; }).pop();
                told.onclose({ code: 1006 }); now += 60000; beats[0]();
                """)
        }
        let tried = urls(context).filter { $0 == "ws://10.0.0.9:45000/" }.count
        XCTAssertEqual(tried, 4, "tried there again after the sweep began: \(urls(context).suffix(3))")
    }

    /// stop() ends every try under way: nothing dials the next place, or sweeps on, after it.
    func testStoppedThePageDialsNothingMore() throws {
        let context = try roomPage(apps: macAndTV)
        deliver(context, ["t": "at", "peer": "mac", "addresses": ["10.0.0.9:45000", "10.0.0.10:45000"]])
        XCTAssertEqual(urls(context).last, "ws://10.0.0.9:45000/")
        let before = urls(context).count
        context.evaluateScript("var first = sockets[sockets.length - 1]; Lamp.wish.stop(); if (first.onclose) first.onclose({ code: 1006 });")
        XCTAssertEqual(urls(context).count, before, "no new socket: \(urls(context).suffix(2))")
        XCTAssertEqual(context.evaluateScript("first.closed")?.toBool(), true)
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
