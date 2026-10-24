import CryptoKit
import JavaScriptCore
import LampRelayKit
import XCTest
@testable import Lamp

/// The wish's channel is written four times (the relay's side, and the connecting side in Swift, Kotlin and lamp.js), so
/// each copy is held to CryptoKit's answers: lamp.js's own SHA-256, HMAC, AES-GCM and X25519, which a TV needs since its
/// page has no WebCrypto, give the same bytes as CryptoKit for random inputs, refuse what was changed, and open the
/// wish's key Lamp seals for a TV's claim.
final class WishChannelTests: XCTestCase {
    private func crypto() throws -> JSContext {
        let context = try XCTUnwrap(JSContext())
        context.exceptionHandler = { _, value in XCTFail(value?.toString() ?? "?") }
        // The page's random numbers, from this Mac's.
        let random: @convention(block) (Int) -> [UInt8] = { count in [UInt8](WishChannel.random(count)) }
        context.setObject(random, forKeyedSubscript: "macRandom" as NSString)
        context.evaluateScript("""
            var window = { crypto: { getRandomValues: function (a) { var r = macRandom(a.length); for (var i = 0; i < a.length; i++) a[i] = r[i]; return a; } } };
            var C = \(TVTemplate.wishCryptoJS);
            function hex(b) { var s = ''; for (var i = 0; i < b.length; i++) s += (b[i] < 16 ? '0' : '') + b[i].toString(16); return s; }
            function bytes(h) { var b = new Uint8Array(h.length / 2); for (var i = 0; i < b.length; i++) b[i] = parseInt(h.substr(2 * i, 2), 16); return b; }
            """)
        return context
    }

    private func js(_ context: JSContext, _ script: String) -> String { context.evaluateScript(script)?.toString() ?? "" }

    func testLampJSHashesSealsAndOpensAsCryptoKitDoes() throws {
        let context = try crypto()
        for round in 0..<60 {
            // Short ones near every block edge, then sizes up to a whole message between the wish's apps and its seal.
            let size = round < 40 ? round : Int.random(in: 0...(ControllerWire.message + 64))
            let data = WishChannel.random(size), key = WishChannel.random(32)
            let nonce = WishChannel.random(12)
            let (d, k, n) = (data.hex, key.hex, nonce.hex)
            XCTAssertEqual(js(context, "hex(C.sha256(bytes('\(d)')))"), Data(SHA256.hash(data: data)).hex, "SHA-256 of \(size) bytes")
            XCTAssertEqual(js(context, "hex(C.hmac(bytes('\(k)'), bytes('\(d)')))"),
                           Data(HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key))).hex, "HMAC of \(size) bytes")
            let box = try AES.GCM.seal(data, using: SymmetricKey(data: key), nonce: AES.GCM.Nonce(data: nonce))
            let sealed = box.ciphertext + box.tag
            XCTAssertEqual(js(context, "hex(C.seal(bytes('\(k)'), bytes('\(n)'), bytes('\(d)')))"), sealed.hex, "AES-GCM of \(size) bytes")
            XCTAssertEqual(js(context, "hex(C.open(bytes('\(k)'), bytes('\(n)'), bytes('\(sealed.hex)')))"), d, "opens what CryptoKit sealed")
            var changed = sealed
            changed[changed.startIndex + Int.random(in: 0..<changed.count)] ^= 1 << UInt8.random(in: 0...7)
            XCTAssertEqual(js(context, "String(C.open(bytes('\(k)'), bytes('\(n)'), bytes('\(changed.hex)')))"), "null", "a changed seal doesn't open")
            XCTAssertEqual(js(context, "C.toBase64(bytes('\(d)'))"), data.base64EncodedString())
            XCTAssertEqual(js(context, "hex(C.fromBase64('\(data.base64EncodedString())'))"), d)
        }
        // The channel's own values: its derivation and its nonces.
        let key = WishChannel.random(32), transcript = WishChannel.random(50)
        XCTAssertEqual(js(context, "hex(C.derive('lamp-wish server', bytes('\(key.hex)'), bytes('\(transcript.hex)')))"),
                       WishChannel.serverProof(key: SymmetricKey(data: key), transcript: transcript).hex)
        XCTAssertEqual(js(context, "hex(C.derive('lamp-wish tag', bytes('\(key.hex)')).subarray(0, 8))"), WishChannel.tag(for: SymmetricKey(data: key)).hex)
        var sealer = WishChannel.Sealer(key: SymmetricKey(data: key))
        for count in 0..<3 {
            let plain = Data("message \(count)".utf8)
            XCTAssertEqual(js(context, "hex(C.seal(bytes('\(key.hex)'), C.nonce(\(count)), C.utf8('message \(count)')))"), sealer.seal(plain).hex, "the nth message with nonce n")
        }
    }

    func testLampJSAgreesOnX25519WithCryptoKit() throws {
        let context = try crypto()
        for _ in 0..<8 {
            let page = Curve25519.KeyAgreement.PrivateKey(), lamp = Curve25519.KeyAgreement.PrivateKey()
            let secret = page.rawRepresentation.hex
            XCTAssertEqual(js(context, "hex(C.x25519(bytes('\(secret)'), C.base))"), page.publicKey.rawRepresentation.hex)
            let shared = try page.sharedSecretFromKeyAgreement(with: lamp.publicKey).withUnsafeBytes { Data($0) }
            XCTAssertEqual(js(context, "hex(C.x25519(bytes('\(secret)'), bytes('\(lamp.publicKey.rawRepresentation.hex)')))"), shared.hex)
        }
    }

    /// A TV app claiming its wish's key: the page sends the public half of a key pair it made, Lamp seals the key to it,
    /// and only the page that made the pair opens it; what crossed the network holds no key in clear.
    @MainActor
    func testATVsClaimOpensOnlyWithThePagesOwnKeyPair() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("wish-keys-\(UUID().uuidString)")
        let kept = WishKeys.folder
        WishKeys.folder = folder
        defer { WishKeys.folder = kept; try? FileManager.default.removeItem(at: folder) }
        let wish = LampProject(id: "scoreboard", name: "Scoreboard", exe: "Scoreboard", dir: URL(fileURLWithPath: "/tmp/scoreboard"), platform: .tv)
        let phone = LampProject(id: "scoreboard.iphone", name: "Scoreboard", exe: "Scoreboard", dir: URL(fileURLWithPath: "/tmp/scoreboard/iPhone"), platform: .iphone, partOf: "scoreboard")
        let context = try crypto()
        context.evaluateScript("var secret = C.random(32), ours = C.x25519(secret, C.base);")
        let ours = try XCTUnwrap(Data(base64Encoded: js(context, "C.toBase64(ours)")))
        let (status, answer) = WishRooms.claim(for: wish, apps: [wish, phone], publicKey: ours)
        XCTAssertEqual(status, 200, "\(answer)")
        let wire = String(decoding: try JSONSerialization.data(withJSONObject: answer), as: UTF8.self)
        let key = WishKeys.key(for: wish)
        XCTAssertFalse(wire.contains(key.base64EncodedString()), "the key isn't in what goes back")
        let opened = js(context, """
            (function () {
              var theirs = C.fromBase64('\(answer["public"] as? String ?? "")'), shared = C.x25519(secret, theirs);
              var sealing = C.derive('lamp-wish claim', shared, C.concat([theirs, ours]));
              var key = C.open(sealing, C.fromBase64('\(answer["nonce"] as? String ?? "")'), C.fromBase64('\(answer["sealed"] as? String ?? "")'));
              return key ? C.toBase64(key) : 'null';
            })()
            """)
        XCTAssertEqual(opened, key.base64EncodedString(), "the page opens the wish's key")
        // Someone else's key pair, seeing the same answer, opens nothing.
        let other = Curve25519.KeyAgreement.PrivateKey()
        let shared = try other.sharedSecretFromKeyAgreement(with: Curve25519.KeyAgreement.PublicKey(rawRepresentation: Data(base64Encoded: answer["public"] as? String ?? "")!))
        let sealing = SymmetricKey(data: WishRooms.claimKey(secret: shared.withUnsafeBytes { Data($0) }, lamp: Data(base64Encoded: answer["public"] as? String ?? "")!,
                                                            page: other.publicKey.rawRepresentation))
        let sealed = Data(base64Encoded: answer["sealed"] as? String ?? "")!
        let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: Data(base64Encoded: answer["nonce"] as? String ?? "")!), ciphertext: sealed.dropLast(16), tag: sealed.suffix(16))
        XCTAssertNil(try? AES.GCM.open(box, using: sealing))
        // A point every secret comes out zero for is refused, and a wish of one app has no key to claim.
        XCTAssertEqual(WishRooms.claim(for: wish, apps: [wish, phone], publicKey: Data(count: 32)).0, 400)
        XCTAssertEqual(WishRooms.claim(for: wish, apps: [wish], publicKey: ours).1["alone"] as? Bool, true)
    }

    /// The claim of a wish's key is answered once, for minutes: someone on the network who rewrites the page's public
    /// half after that, or once the page has its key, gets nothing. A request that failed spends nothing, and an answer
    /// lost on its way is given again to the page's own key pair, so the page's tries again still get the key; opening
    /// the app again on the TV doesn't open the claim again.
    @MainActor
    func testAWishsKeyIsClaimedOnceAndForMinutes() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("wish-keys-\(UUID().uuidString)")
        let kept = WishKeys.folder
        WishKeys.folder = folder
        defer { WishKeys.folder = kept; try? FileManager.default.removeItem(at: folder) }
        let wish = LampProject(id: "scoreboard", name: "Scoreboard", exe: "Scoreboard", dir: URL(fileURLWithPath: "/tmp/scoreboard"), platform: .tv)
        let phone = LampProject(id: "scoreboard.iphone", name: "Scoreboard", exe: "Scoreboard", dir: URL(fileURLWithPath: "/tmp/scoreboard/iPhone"), platform: .iphone, partOf: "scoreboard")
        let tv = "192.168.1.30"
        func claim(_ key: Data, from address: String = tv) -> Int {
            WishRooms.claim(for: wish, wish: wish, apps: [wish, phone], publicKey: key, from: address).0
        }
        let page = Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation
        let theirs = Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation

        // Lamp puts the app on the TV: a try that failed on the way, then the page's own claim.
        WishClaims.shared.open(wish.id, from: tv)
        XCTAssertEqual(claim(page, from: "192.168.1.99"), 403, "only from the TV")
        XCTAssertEqual(claim(Data(count: 32)), 400, "a key that can't be used spends nothing")
        XCTAssertEqual(claim(page), 200)
        XCTAssertEqual(claim(theirs), 403, "a public half put in the page's place after it gets nothing")
        XCTAssertEqual(claim(page), 200, "the page's own try again, after an answer lost on its way, is answered")
        XCTAssertEqual(claim(page, from: "192.168.1.99"), 403)
        WishClaims.shared.renew(wish.id, from: tv)
        XCTAssertEqual(claim(theirs), 403, "the app opening on the TV after its claim doesn't open it again")

        // A new install opens it again; past its minutes it's closed, answered or not.
        let window = WishClaims.window
        WishClaims.window = 0.2
        defer { WishClaims.window = window }
        WishClaims.shared.open(wish.id, from: tv)
        XCTAssertEqual(claim(page), 200)
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertEqual(claim(page), 403, "the page's own key pair too, only for the claim's minutes")
        WishClaims.shared.open(wish.id, from: tv)
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertEqual(claim(theirs), 403, "minutes, not half an hour")
        XCTAssertLessThanOrEqual(window, 5 * 60)
    }

    /// The wish's key is made once, kept where only this Mac's account reads it, the same for every app of the wish and
    /// through a rename, different for another wish, and gone with the wish.
    func testAWishsKeyIsKeptByItsInstanceAndForgottenWithIt() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("wish-keys-\(UUID().uuidString)")
        let kept = WishKeys.folder
        WishKeys.folder = folder
        defer { WishKeys.folder = kept; try? FileManager.default.removeItem(at: folder) }
        var wish = LampProject(id: "scoreboard", name: "Scoreboard", exe: "Scoreboard", dir: URL(fileURLWithPath: "/tmp/scoreboard"), platform: .tv)
        wish.instance = "A1B2"
        let key = WishKeys.key(for: wish)
        XCTAssertEqual(key.count, 32)
        var renamed = LampProject(id: "tally", name: "Tally", exe: "Tally", dir: URL(fileURLWithPath: "/tmp/tally"), platform: .tv)
        renamed.instance = "A1B2"
        XCTAssertEqual(WishKeys.key(for: renamed), key, "a rename keeps the wish's instance, and its key")
        var other = LampProject(id: "other", name: "Other", exe: "Other", dir: URL(fileURLWithPath: "/tmp/other"), platform: .tv)
        other.instance = "C3D4"
        XCTAssertNotEqual(WishKeys.key(for: other), key)
        let file = folder.appendingPathComponent("A1B2")
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
        WishKeys.folder = folder   // what's in memory goes too: read again from the file
        XCTAssertEqual(WishKeys.key(for: wish), key, "read back from where it was kept")
        WishKeys.forget(wish)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertNotEqual(WishKeys.key(for: wish), key, "a wish made again under that instance gets a new key")
    }
}

extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
