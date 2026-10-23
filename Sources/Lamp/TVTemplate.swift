import CryptoKit
import Foundation

/// A TV app: HTML, CSS and JavaScript in the app's `Web/` folder, the same files for a Samsung TV and an LG TV. The
/// agent owns them; Lamp owns `Web/lamp.js` (the remote's keys, moving focus with the arrows, Back, and a small store),
/// rewritten before every build, and writes each TV's manifest itself when it packages the app (`TVPackage`), so
/// nothing the agent wrote decides what a TV is asked to allow.
enum TVTemplate {
    static let webFolder = "Web"
    static let supportFile = "Web/lamp.js"
    /// A page for a phone, as a controller or a companion to the TV app, which Lamp hands out from this Mac while the app
    /// runs (`Store.phonePage`). It never goes on the TV.
    static let phoneFolder = "Phone"
    /// Where Lamp writes the phone page's address into the staged copy of lamp.js (`TVs.stage`).
    static let phoneMarker = "/*LAMP_PHONE*/null"

    /// Whether an app's folder is a TV app, read off what every version keeps: Lamp's script in `Web/`. A device app
    /// whose integration takes the web building blocks may keep them at the same path (an Xbox's), so its own marker
    /// says it's that instead.
    static func isTV(_ dir: URL) -> Bool {
        FileManager.default.fileExists(atPath: dir.appendingPathComponent(supportFile).path) && !DeviceApps.isScaffolded(dir)
    }

    static func writeOwnedFiles(for project: LampProject) throws {
        try Template.write(lampJS, to: supportFile, for: project)
    }

    static func fill(_ project: LampProject) throws {
        try Template.write(indexHTML, to: "Web/index.html", for: project)
        try Template.write(styleCSS, to: "Web/style.css", for: project)
        try Template.write(appJS, to: "Web/app.js", for: project)
        try Template.write(appMd, to: "APP.md", for: project)
        try Template.write(".lamp/\n", to: ".gitignore", for: project)
        try writeOwnedFiles(for: project)
    }

    // MARK: Ids and manifests

    /// Samsung's ids: a package id of exactly ten letters and digits, worked out from the app's own id so it stays
    /// the same build to build, and the app id under it.
    static func tizenIDs(for project: LampProject) -> (package: String, app: String) {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        let digest = SHA256.hash(data: Data(project.bundleID.utf8))
        let package = String(digest.prefix(10).map { alphabet[Int($0) % alphabet.count] })
        let name = project.exe.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        return (package, package + "." + (name.isEmpty ? "App" : String(name.prefix(40))))
    }

    /// LG's id: the app's own, in the letters webOS allows.
    static func webOSID(for project: LampProject) -> String {
        String((Edition.appBundlePrefix + project.id).lowercased().map { $0.isLetter || $0.isNumber || $0 == "." ? $0 : "-" })
    }

    static func tizenConfig(for project: LampProject) -> String {
        let ids = tizenIDs(for: project)
        let name = project.name.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <widget xmlns="http://www.w3.org/ns/widgets" xmlns:tizen="http://tizen.org/ns/widgets" id="http://lamp.dev/\(project.id)" version="1.0.0" viewmodes="maximized">
                <tizen:application id="\(ids.app)" package="\(ids.package)" required_version="3.0"/>
                <content src="index.html"/>
                <feature name="http://tizen.org/feature/screen.size.normal.1080.1920"/>
                <icon src="icon.png"/>
                <name>\(name)</name>
                <tizen:profile name="tv-samsung"/>
                <access origin="*" subdomains="true"/>
                <tizen:privilege name="http://tizen.org/privilege/internet"/>
                <tizen:privilege name="http://tizen.org/privilege/tv.inputdevice"/>
                <tizen:setting screen-orientation="landscape" context-menu="disable" background-support="disable" encryption="disable" install-location="auto" hwkey-event="enable"/>
            </widget>

            """
    }

    static func webOSAppInfo(for project: LampProject) -> String {
        let info: [String: Any] = ["id": webOSID(for: project), "version": "1.0.0", "vendor": "Lamp", "type": "web", "main": "index.html",
                                   "title": project.name, "icon": "icon.png", "largeIcon": "largeIcon.png", "resolution": "1920x1080",
                                   "disableBackHistoryAPI": true]
        return String(decoding: (try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys])) ?? Data(), as: UTF8.self)
    }

    // MARK: The scaffold

    static let indexHTML = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=1920, height=1080">
        <title>{{NAME}}</title>
        <link rel="stylesheet" href="style.css">
        </head>
        <body>
        <main id="app">
          <h1>{{NAME}}</h1>
          <p class="status">Lamp is making this app.</p>
        </main>
        <script src="lamp.js"></script>
        <script src="app.js"></script>
        </body>
        </html>

        """

    static let styleCSS = """
        html, body {
          margin: 0;
          width: 1920px;
          height: 1080px;
          overflow: hidden;
          background: #101418;
          color: #f2f4f6;
          font-family: "Samsung One", "LG Smart UI", "Helvetica Neue", Arial, sans-serif;
        }
        #app {
          box-sizing: border-box;
          height: 100%;
          padding: 54px 96px;
          display: flex;
          flex-direction: column;
          justify-content: center;
          align-items: center;
        }
        h1 { font-size: 72px; margin: 0 0 24px; }
        .status { font-size: 36px; opacity: 0.7; }
        /* What has the remote's focus is always plain to see from the sofa. */
        :focus { outline: 6px solid #4da3ff; outline-offset: 6px; }

        """

    static let appJS = """
        // The app's own code. Lamp's building blocks are on `Lamp` (lamp.js).

        """

    static let appMd = """
        # {{NAME}}

        A TV app in HTML, CSS and JavaScript, built and changed with Lamp. It runs on Samsung and LG TVs, and in the TV preview on this Mac.

        ## What it does
        Nothing yet: fresh scaffold.

        ## Structure
        - `Web/index.html`: the page, which loads `lamp.js` and then `app.js`.
        - `Web/style.css`: the look, laid out for a 1920×1080 screen.
        - `Web/app.js`: the app's code.
        - `Web/lamp.js`: Lamp's building blocks (AI, saved data, the app's files, the remote's keys, focus, Back). Written by Lamp; don't edit.

        """

    /// Lamp's building blocks in every TV app, written before every build: LampAI, LampStore and LampAssets
    /// (`DeviceSupport.webJS`, shared with the web apps integrations declare), then the remote. It runs on Samsung's and
    /// LG's TVs and in the preview, whose browsers are about Chrome 79's age, so it's plain ES5.
    static var lampJS: String { DeviceSupport.webJS + remoteJS + controllersJS }

    static let remoteJS = """
        /* The remote, for a TV app. Written by Lamp before every build; don't edit. LampAI, LampStore and LampAssets
         * are above.
         *
         * Lamp.onKey(function (name, event) { ... return true if handled })   every remote key, by name:
         *   up down left right enter back, play pause playpause stop fastforward rewind,
         *   red green yellow blue, channelup channeldown, info, 0-9
         * Lamp.onBack(function () { ... return true if handled })  Back, innermost first; unhandled, it leaves the app
         * Lamp.focus(elementOrSelector), Lamp.focusFirst()          give the remote's focus to something
         * Lamp.scope = element or null                              keep the arrows inside a dialog while it's open
         * Lamp.navigation = false                                   turn off moving focus with the arrows (a game)
         * Lamp.store   LampStore, under the name it had first
         * Lamp.platform   "tizen", "webos" or "browser" (the preview on the Mac)
         * Lamp.phonePage(hash)   the address of the app's Phone/ page for a phone on the Mac's Wi-Fi (for a QR code),
         *   with "#" + hash after it when given; null when the app has no Phone/index.html
         * Lamp.onPhonePage(fn)   fn() now when there is an address, and again whenever it changes: draw the QR code there
         * Lamp.controllers   phones on the same Wi-Fi as controllers: see its comment below
         *
         * The arrows move focus between what can take it (buttons, links, fields, and anything with data-focus),
         * to the nearest in that direction; OK clicks what has it.
         */
        (function () {
          'use strict';
          var platform = (typeof tizen !== 'undefined') ? 'tizen'
            : (typeof webOS !== 'undefined' || typeof PalmSystem !== 'undefined') ? 'webos' : 'browser';
          var names = { 37: 'left', 38: 'up', 39: 'right', 40: 'down', 13: 'enter', 10009: 'back', 461: 'back', 27: 'back',
            415: 'play', 19: 'pause', 10252: 'playpause', 413: 'stop', 417: 'fastforward', 412: 'rewind',
            403: 'red', 404: 'green', 405: 'yellow', 406: 'blue', 427: 'channelup', 428: 'channeldown', 457: 'info' };
          for (var d = 0; d <= 9; d++) names[48 + d] = String(d);
          if (platform === 'tizen') {
            try {
              tizen.tvinputdevice.registerKeyBatch(['MediaPlay', 'MediaPause', 'MediaPlayPause', 'MediaStop', 'MediaFastForward',
                'MediaRewind', 'ColorF0Red', 'ColorF1Green', 'ColorF2Yellow', 'ColorF3Blue', 'ChannelUp', 'ChannelDown', 'Info',
                '0', '1', '2', '3', '4', '5', '6', '7', '8', '9']);
            } catch (e) {}
          }
          var keyHandlers = [], backHandlers = [];
          var FOCUSABLE = '[data-focus], button, a[href], input, select, textarea, [tabindex]:not([tabindex="-1"])';

          function typing(el) {
            return !!el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.isContentEditable);
          }
          function visible(el) {
            var r = el.getBoundingClientRect();
            if (r.width <= 0 || r.height <= 0 || el.disabled) return false;
            var s = window.getComputedStyle(el);
            return s.visibility !== 'hidden' && s.display !== 'none';
          }
          function focusables() {
            var scope = Lamp.scope || document;
            return Array.prototype.filter.call(scope.querySelectorAll(FOCUSABLE), visible);
          }
          function give(el) {
            if (!el) return;
            if (!el.hasAttribute('tabindex') && !/^(BUTTON|A|INPUT|SELECT|TEXTAREA)$/.test(el.tagName)) el.setAttribute('tabindex', '-1');
            el.focus();
            if (el.scrollIntoView) el.scrollIntoView({ block: 'nearest', inline: 'nearest' });
          }
          function move(direction) {
            var list = focusables(), current = document.activeElement;
            if (!list.length) return false;
            if (!current || list.indexOf(current) < 0) { give(list[0]); return true; }
            var a = current.getBoundingClientRect(), ax = a.left + a.width / 2, ay = a.top + a.height / 2;
            var best = null, bestScore = Infinity;
            list.forEach(function (el) {
              if (el === current) return;
              var b = el.getBoundingClientRect(), bx = b.left + b.width / 2, by = b.top + b.height / 2, main, cross;
              if (direction === 'left') { if (b.right > a.left + 1) return; main = ax - bx; cross = Math.abs(by - ay); }
              else if (direction === 'right') { if (b.left < a.right - 1) return; main = bx - ax; cross = Math.abs(by - ay); }
              else if (direction === 'up') { if (b.bottom > a.top + 1) return; main = ay - by; cross = Math.abs(bx - ax); }
              else { if (b.top < a.bottom - 1) return; main = by - ay; cross = Math.abs(bx - ax); }
              var score = main + cross * 2;
              if (score < bestScore) { bestScore = score; best = el; }
            });
            if (best) { give(best); return true; }
            return false;
          }
          function exit() {
            try {
              if (platform === 'tizen') tizen.application.getCurrentApplication().exit();
              else if (platform === 'webos') { if (window.webOS && webOS.platformBack) webOS.platformBack(); else window.close(); }
            } catch (e) {}
          }
          var store = window.LampStore;
          // Filled in by Lamp in the copy it opens or packages, while the app has a phone page.
          var phone = \(phoneMarker);
          var phoneHandlers = [];
          // Lamp may have to move the page to another port (another program took its own), so the address is asked for
          // again as the page opens and now and then after, and the preview is told at once.
          function setPhone(address) {
            if (!phone || typeof address !== 'string' || !address || address === phone) return;
            phone = address;
            for (var i = 0; i < phoneHandlers.length; i++) { try { phoneHandlers[i](); } catch (e) { if (window.console) console.error(e); } }
          }
          window.__lampPhonePage = setPhone;
          function askPhone() {
            if (phone && window.LampAI && LampAI._post) LampAI._post('/app/phone-page', {}, 20000).then(function (r) { setPhone(r && r.url); }, function () {});
          }
          if (phone) { setTimeout(askPhone, 0); setInterval(askPhone, 30000); }

          document.addEventListener('keydown', function (event) {
            var name = names[event.keyCode];
            // Backspace is Back only where nothing is being typed (the preview's keyboard stands in for the remote).
            if (!name && event.keyCode === 8 && !typing(event.target)) name = 'back';
            if (!name) return;
            for (var i = keyHandlers.length - 1; i >= 0; i--) {
              if (keyHandlers[i](name, event) === true) { event.preventDefault(); return; }
            }
            if (name === 'back') {
              event.preventDefault();
              for (var j = backHandlers.length - 1; j >= 0; j--) { if (backHandlers[j]() === true) return; }
              exit();
              return;
            }
            if (Lamp.navigation === false) return;
            if (name === 'left' || name === 'right' || name === 'up' || name === 'down') {
              if (typing(event.target) && (name === 'left' || name === 'right')) return;
              if (move(name)) event.preventDefault();
            } else if (name === 'enter') {
              var target = document.activeElement;
              if (target && target !== document.body && !typing(target) && !/^(BUTTON|A|SELECT)$/.test(target.tagName) && target.click) {
                event.preventDefault();
                target.click();
              }
            }
          }, true);

          var Lamp = window.Lamp = {
            platform: platform,
            navigation: true,
            scope: null,
            store: store,
            key: function (event) { return names[event.keyCode] || null; },
            onKey: function (handler) {
              keyHandlers.push(handler);
              return function () { var i = keyHandlers.indexOf(handler); if (i >= 0) keyHandlers.splice(i, 1); };
            },
            onBack: function (handler) {
              backHandlers.push(handler);
              return function () { var i = backHandlers.indexOf(handler); if (i >= 0) backHandlers.splice(i, 1); };
            },
            focus: function (el) { give(typeof el === 'string' ? document.querySelector(el) : el); },
            focusFirst: function () { var list = focusables(); if (list.length) give(list[0]); },
            move: move,
            exit: exit,
            phonePage: function (hash) { return phone ? phone + (hash ? '#' + hash : '') : null; },
            onPhonePage: function (fn) {
              phoneHandlers.push(fn);
              if (phone) { try { fn(); } catch (e) { if (window.console) console.error(e); } }
              return function () { var i = phoneHandlers.indexOf(fn); if (i >= 0) phoneHandlers.splice(i, 1); };
            }
          };
          document.addEventListener('DOMContentLoaded', function () {
            setTimeout(function () { if (!document.activeElement || document.activeElement === document.body) Lamp.focusFirst(); }, 0);
          });
        })();

        """
}

extension TVTemplate {
    /// Phones as controllers (`PhoneControllers`): the TV page's half. In the preview the page is the app's host in Lamp
    /// itself (the `lampController` bridge); on a TV it asks Lamp for a credential once and opens a socket to Lamp's
    /// gateway over the Wi‑Fi. What a phone holds down is let go when it leaves or the link drops, and movement that
    /// arrives late is dropped.
    static let controllersJS = #"""
        /* Phones as controllers. Written by Lamp before every build; don't edit.
         *
         * Lamp.controllers.start()                    opens a game for phones on this Wi-Fi; Promise. The phones' page is
         *                                              Phone/index.html, loading lamp-controller.js (its own comment says how).
         * Lamp.controllers.onLink(fn(url))             the address phones open (show it as a QR code); it changes every
         *                                              few minutes, and fn is called each time
         * Lamp.controllers.onJoin(fn(player)), onLeave(fn(player))      players are numbered 1, 2, ... as phones join
         * Lamp.controllers.onButton(fn(player, name, down))             a button held (down true) or let go
         * Lamp.controllers.onAxis(fn(player, name, x, y))               a stick, or the phone's tilt ('tilt'), -1 to 1
         * Lamp.controllers.onMessage(fn(player, data))                  anything else a phone's page sent
         * Lamp.controllers.onError(fn(message))                         it couldn't start, or the link was lost
         * Lamp.controllers.send(player, data)          to one phone, or to every phone with player 0
         * Lamp.controllers.isHeld(player, name), players()
         * Lamp.controllers.stop()
         *
         * A phone that leaves, or whose link drops, has every button it held let go (onButton with down false) before
         * onLeave. Movement that arrives late is dropped rather than acted on.
         */
        (function () {
          'use strict';
          var LATE = 300;   // ms after which a stick or tilt reading is dropped as stale
          var on = { link: [], join: [], leave: [], button: [], axis: [], message: [], error: [] };
          var held = {}, seen = {}, joined = {}, offset = null, link = null, transport = null, linkTimer = null, started = false;

          function emit(name, args) {
            var list = on[name];
            for (var i = 0; i < list.length; i++) { try { list[i].apply(null, args); } catch (e) { if (window.console) console.error(e); } }
          }
          function adder(name) {
            return function (fn) {
              on[name].push(fn);
              if (name === 'link' && link) fn(link);
              return function () { var i = on[name].indexOf(fn); if (i >= 0) on[name].splice(i, 1); };
            };
          }
          // Each phone counts its messages from 1 on every new link, so what's been seen is forgotten when it leaves.
          function fresh(m) {
            var mine = seen[m.player] || (seen[m.player] = {});
            var key = m.t + ':' + m.name;
            if (mine[key] !== undefined && m.seq <= mine[key]) return false;
            mine[key] = m.seq;
            return true;
          }
          function release(player) {
            var names = held[player] || {};
            for (var name in names) if (names[name]) emit('button', [player, name, false]);
            held[player] = {};
          }
          function leave(player) {
            delete seen[player];
            if (!joined[player]) return;
            release(player);
            delete joined[player];
            emit('leave', [player]);
          }
          function join(player) {
            delete seen[player];
            if (joined[player]) return;
            joined[player] = true;
            held[player] = {};
            emit('join', [player]);
          }
          function leaveAll() { for (var p in joined) leave(+p); seen = {}; }

          function receive(m) {
            if (!m || typeof m !== 'object') return;
            if (m.now) offset = m.now - Date.now();
            if (m.t === 'welcome') {
              for (var i = 0; i < (m.players || []).length; i++) join(m.players[i]);
              askLink();
            } else if (m.t === 'link') {
              link = m.url;
              emit('link', [link]);
            } else if (m.t === 'joined') {
              leave(m.player);
              join(m.player);
            } else if (m.t === 'left') {
              leave(m.player);
            } else if (m.t === 'button') {
              if (!joined[m.player]) join(m.player);
              if (!fresh(m)) return;
              held[m.player][m.name] = !!m.down;
              emit('button', [m.player, m.name, !!m.down]);
            } else if (m.t === 'axis') {
              if (!joined[m.player]) join(m.player);
              if (!fresh(m)) return;
              if (offset !== null && Date.now() + offset - m.at > LATE) return;
              emit('axis', [m.player, m.name, m.x, m.y]);
            } else if (m.t === 'message') {
              emit('message', [m.player, m.data]);
            } else if (m.t === 'closed') {
              leaveAll();
            }
          }
          window.__lampControllers = receive;

          function askLink() {
            if (transport) transport.send({ t: 'link' });
            clearInterval(linkTimer);
            linkTimer = setInterval(function () { if (transport) transport.send({ t: 'link' }); }, 10 * 60 * 1000);
          }

          // The preview on the Mac: the page is the app's host in Lamp itself.
          function bridgeTransport(handler) {
            handler.postMessage({ op: 'start' });
            return {
              send: function (message) { handler.postMessage({ op: 'send', message: message }); },
              stop: function () { handler.postMessage({ op: 'stop' }); }
            };
          }

          // On a TV: a socket to Lamp on the Mac, over the Wi-Fi, opened again when it drops.
          function socketTransport() {
            var socket = null, beat = null, stopped = false, session = null;
            function connect() {
              if (stopped) return;
              socket = new WebSocket(session.socket);
              socket.onopen = function () { socket.send(JSON.stringify({ t: 'hello', credential: session.host })); };
              socket.onmessage = function (event) { var m; try { m = JSON.parse(event.data); } catch (e) { return; } receive(m); };
              socket.onclose = function () { leaveAll(); if (!stopped) setTimeout(open, 2000); };
            }
            function open() {
              if (stopped) return;
              LampAI._post('/app/controller', {}, 20000).then(function (answer) {
                session = answer;
                connect();
              }, function (error) {
                emit('error', [error.message]);
                if (!stopped) setTimeout(open, 5000);
              });
            }
            open();
            beat = setInterval(function () { if (socket && socket.readyState === 1) socket.send('{"t":"beat"}'); }, 5000);
            return {
              send: function (message) { if (socket && socket.readyState === 1) socket.send(JSON.stringify(message)); },
              stop: function () { stopped = true; clearInterval(beat); if (socket) socket.close(); }
            };
          }

          var api = {
            start: function () {
              if (started) return Promise.resolve();
              started = true;
              var handlers = window.webkit && window.webkit.messageHandlers;
              transport = handlers && handlers.lampController ? bridgeTransport(handlers.lampController) : socketTransport();
              return Promise.resolve();
            },
            stop: function () {
              if (transport) transport.stop();
              transport = null; started = false; link = null;
              clearInterval(linkTimer);
              leaveAll();
            },
            send: function (player, data) { if (transport) transport.send({ t: 'send', player: player || 0, data: data }); },
            isHeld: function (player, name) { return !!(held[player] && held[player][name]); },
            players: function () { var list = []; for (var p in joined) list.push(+p); return list; },
            onLink: adder('link'), onJoin: adder('join'), onLeave: adder('leave'), onButton: adder('button'),
            onAxis: adder('axis'), onMessage: adder('message'), onError: adder('error')
          };
          if (window.Lamp) window.Lamp.controllers = api;
        })();

        """#

    /// Phones as controllers: the phone page's half, served by Lamp beside the app's Phone/ files as lamp-controller.js
    /// (`Store.phonePage`). Its socket is the page's own address with `socket` in place of the page, so it's the same
    /// whichever way the page was reached, http on the Wi‑Fi or https the person put in front.
    static let phoneControllerJS = #"""
        /* Lamp's phone controller. The page is the app's own; this joins it to the TV app as a player and carries its
         * buttons, sticks and tilt there, through Lamp on the Mac, over this Wi-Fi.
         *
         *   var pad = LampController.connect({
         *     onPlayer: function (n) { ... },        // the player number this phone was given (1, 2, ...)
         *     onMessage: function (data) { ... },   // what the TV app sent this phone (or every phone)
         *     onState: function (state) { ... }     // 'connecting', 'connected', 'waiting' (the TV app isn't there), 'ended', 'full'
         *   });
         *   pad.button('a', true); pad.button('a', false);   // a button held, then let go
         *   pad.axis('stick', x, y);                          // a stick or slider, each from -1 to 1
         *   pad.send({ ready: true });                        // anything small to the TV app
         *   LampController.tilt(pad)                          // from a tap (a Start button): asks for the motion sensors,
         *     .then(function () { ... })                     // then sends the phone's tilt as axis 'tilt' (x: left -1 to
         *     .catch(function (error) { ... });              // right 1, y: away -1 to toward 1) about 30 times a second.
         *   LampController.canTilt()                          // false where the browser keeps its sensors from this page:
         *                                                     // phones give them only to https pages, and this one is http
         */
        (function () {
          'use strict';
          var base = location.pathname.replace(/[^\/]*$/, '');
          var keyName = 'lamp-controller:' + base;
          var socketURL = (location.protocol === 'https:' ? 'wss:' : 'ws:') + '//' + location.host + base + 'socket';

          function connect(handlers) {
            handlers = handlers || {};
            var socket = null, seq = 0, player = null, closedForGood = false, lastHeard = 0, retry = 0, again = null;
            // The link's credential is read once and taken out of the address, so it isn't left in the history or shared
            // by mistake; the phone then keeps the one Lamp gives it, for coming back as the same player.
            var join = (location.hash || '').replace(/^#/, '');
            if (join) history.replaceState(null, '', location.pathname + location.search);
            function state(s) { if (handlers.onState) handlers.onState(s); }

            // A link just opened always wins over a credential kept from before: that one may be for a game that has
            // ended, or have run out while the page was away, and the link is what the person just chose.
            function open() {
              again = null;
              // A pad closed while a reconnect waited stays closed: it mustn't rejoin beside the one that replaced it.
              if (closedForGood) return;
              var credential = join || sessionStorage.getItem(keyName);
              if (!credential) { state('ended'); return; }
              state('connecting');
              socket = new WebSocket(socketURL);
              socket.onopen = function () {
                lastHeard = Date.now();
                socket.send(JSON.stringify({ t: 'hello', credential: credential }));
              };
              socket.onmessage = function (event) {
                lastHeard = Date.now();
                var m; try { m = JSON.parse(event.data); } catch (e) { return; }
                if (m.t === 'welcome') {
                  retry = 0; join = ''; seq = 0;
                  player = m.player;
                  sessionStorage.setItem(keyName, m.credential);
                  if (handlers.onPlayer) handlers.onPlayer(player);
                  state(m.host ? 'connected' : 'waiting');
                } else if (m.t === 'credential') {
                  sessionStorage.setItem(keyName, m.credential);
                } else if (m.t === 'state') {
                  state(m.host ? 'connected' : 'waiting');
                } else if (m.t === 'message') {
                  if (handlers.onMessage) handlers.onMessage(m.data);
                } else if (m.t === 'full') {
                  closedForGood = true; state('full');
                }
              };
              socket.onclose = function (event) {
                socket = null;
                if (event.code === 4003 || event.code === 4005) {
                  sessionStorage.removeItem(keyName);
                  closedForGood = true; state('ended');
                }
                if (closedForGood) return;
                state('connecting');
                retry = Math.min(retry + 1, 5);
                again = setTimeout(open, 500 * retry);
              };
            }

            function post(message) {
              if (!socket || socket.readyState !== 1) return false;
              message.seq = ++seq;
              socket.send(JSON.stringify(message));
              return true;
            }

            // A beat both ways: Lamp lets a quiet phone go, and a phone that hears nothing opens its link again.
            var beat = setInterval(function () {
              if (!socket || socket.readyState !== 1) return;
              if (Date.now() - lastHeard > 12000) { socket.close(); return; }
              socket.send(JSON.stringify({ t: 'beat' }));
            }, 5000);
            open();

            return {
              get player() { return player; },
              button: function (name, down) { return post({ t: 'button', name: name, down: !!down }); },
              axis: function (name, x, y) { return post({ t: 'axis', name: name, x: x, y: y }); },
              send: function (data) { return post({ t: 'message', data: data }); },
              close: function () { closedForGood = true; clearInterval(beat); clearTimeout(again); again = null; if (socket) socket.close(); }
            };
          }

          function canTilt() { return !!window.DeviceMotionEvent && window.isSecureContext; }

          // The phone's tilt, from gravity: the same however far it's leaned back, held upright or on its side.
          function tilt(pad, options) {
            options = options || {};
            var range = options.degrees || 40;
            var D = window.DeviceMotionEvent;
            if (!D) return Promise.reject(new Error('This phone has no motion sensors.'));
            if (!window.isSecureContext) return Promise.reject(new Error('This browser only shares tilt with pages opened over https.'));
            var asked = typeof D.requestPermission === 'function' ? D.requestPermission() : Promise.resolve('granted');
            return asked.then(function (answer) {
              if (answer !== 'granted') throw new Error('Motion access was turned down. Allow it in the browser to steer by tilting.');
              var last = 0;
              window.addEventListener('devicemotion', function (event) {
                var g = event.accelerationIncludingGravity;
                if (!g || g.x === null) return;
                var turn = typeof screen.orientation === 'object' ? screen.orientation.angle : (window.orientation || 0);
                var gx = g.x, gy = g.y;
                if (turn === 90) { gx = -g.y; gy = g.x; } else if (turn === -90 || turn === 270) { gx = g.y; gy = -g.x; } else if (turn === 180) { gx = -g.x; gy = -g.y; }
                var side = Math.atan2(gx, Math.sqrt(gy * gy + g.z * g.z)) * 180 / Math.PI;
                var lean = Math.atan2(gy, Math.sqrt(gx * gx + g.z * g.z)) * 180 / Math.PI;
                var now = Date.now();
                if (now - last < 33) return;
                last = now;
                pad.axis('tilt', Math.max(-1, Math.min(1, side / range)), Math.max(-1, Math.min(1, lean / range)));
              });
            });
          }

          window.LampController = { connect: connect, tilt: tilt, canTilt: canTilt };
        })();

        """#

}

extension Agent {
    /// The rules for a TV app, in the same shape as the others' and said for the web on a TV, offering `skills`.
    static func tvPrompt(skills: [String: Skills.Skill] = Skills.all) -> String {
        let rules = [Rules.tvEdit, Rules.ask, Rules.shell, Rules.tvFrameworks, Rules.tvDesign, Rules.tvKeys, Rules.tvData, Rules.tvPhone, Rules.webAI,
                     Rules.icon, Rules.about, Rules.tvAttachments, Rules.tvLogs, Rules.tvTry, Rules.appMd, Rules.audience,
                     Skills.index(Skills.offered(mac: false, tv: true), from: skills), Rules.begin, Rules.finish]
        return (Rules.tvHeader + "\n\nRules:\n" + rules.joined())
            .replacingOccurrences(of: "{{DEVICE}}", with: "TV")
            .replacingOccurrences(of: "{{A_DEVICE}}", with: "a TV")
            .replacingOccurrences(of: "{{RELAUNCH}}", with: "opens it in the TV preview")
    }
}

extension Agent.Rules {
    static let tvHeader = """
    You are Lamp's builder agent. The current directory is a TV app: HTML, CSS and JavaScript in Web/, the same \
    files for Samsung TVs (Tizen) and LG TVs (webOS), with no build step. Lamp opens it in the TV preview, a window \
    on the user's Mac driven with a remote's keys, and packages it and puts it on one of the user's own TVs when they \
    choose that TV under Try On and press Play. Where the app is now, as far as Lamp knows, comes with the request. \
    Read APP.md first for context.
    """

    static let tvEdit = """
    - Make the change the user asks for by editing the files in Web/: index.html, style.css, app.js, and more \
    files as the app grows (scripts, styles, pictures), loaded from index.html with relative paths. File names use \
    letters, digits, dots, dashes and underscores only. Web/lamp.js belongs to Lamp and is rewritten before every \
    build: never edit it, and keep index.html loading it before the app's own scripts.
    """

    static let tvFrameworks = """
    - Write code that runs first time on the TVs' browsers, which are about as old as Chrome 79: plain JavaScript and \
    CSS, no optional chaining (?.) or ?? or other syntax newer than 2019, no modules or top-level await, no build step, \
    no npm and no frameworks loaded from the internet. CSS grid and flexbox, CSS variables and transitions are fine. \
    The app can fetch from https APIs that allow it (no key you don't have); its AI comes from Lamp (below).
    """

    static let tvDesign = """
    - Design for a TV seen from across the room: the page is exactly 1920×1080 and never scrolls as a whole (lists \
    scroll inside their own box), with a margin of about 5% on every side the TV may cut off; text at least 28px, \
    headings much larger, high contrast, a dark background by default. Everything is reached with the remote's arrows \
    and OK: what has focus must be unmistakable (a large outline or a scale and glow), and focus moves the way the \
    layout looks. No hover, no tiny targets, no text fields unless the app needs them (typing with a remote is slow).
    """

    static let tvKeys = """
    - The remote: lamp.js moves focus with the arrows between buttons, links, fields and anything marked `data-focus`, \
    and OK clicks what has focus, so most apps need no key code of their own; give the first thing to focus with \
    `Lamp.focus(...)` when a screen opens. Back goes back a screen with `Lamp.onBack(fn)` (return true when handled); \
    unhandled on the first screen, it leaves the app. Other keys (play, pause, the colour keys, numbers) come by name \
    through `Lamp.onKey(fn)`. A game turns the arrows over to itself with `Lamp.navigation = false`. Read lamp.js's \
    opening comment for the rest.
    """

    static let tvData = """
    - Keep what the app saves with `LampStore` from lamp.js: `LampStore.load(key, fallback)` and \
    `LampStore.save(value, key)` for a value saved whole, `LampStore.collection(name)` for items saved one at a time \
    (put, get, all, delete), JSON kept on the TV. People rely on their data through every change you make, so once \
    something is saved, only ever add to it: a new field gets a default where it's read, and never rename or retype a \
    saved one. The app's own files (pictures, data) come in its package: `LampAssets.url(name)`, `.json(name)`.
    """

    static let tvPhone = """
    - A page for phones (controllers, a buzzer, a second screen) goes in Phone/, which Lamp serves while the app \
    runs: never start a server or anything that keeps running for it. Open the phone-controllers skill first.
    """

    /// Lamp's AI in a web app on a device (`DeviceSupport.webJS`): the TV kit's and a declared web kind's.
    static let webAI = """
    - For AI (text, pictures, decisions), use `LampAI` from lamp.js: Lamp on the person's Mac answers, with the AI \
    they set up, in the preview and on their own device while it's on the Mac's Wi‑Fi with Lamp open. Every call \
    gives back a Promise: `LampAI.ask(prompt, {data, json, images})`, `LampAI.makeImage(description)` (a data: URL), \
    `LampAI.isTrue`, `choose`, `rate`, `decide` and `decideEach` for quick judgments code acts on. Text from outside \
    the app goes in `data`, never into the prompt. Show progress while a call runs and `error.message` when it fails; \
    where a feature depends on AI, check `LampAI.isAvailable('text')` and show a short note when it can't answer. \
    Read LampAI's comment in lamp.js before using it; never call an AI service yourself.
    """

    static let tvAttachments = """
    - Files the user attaches are saved in Attachments/, for you to look at; they stay on this Mac. When the app \
    should use one (a logo, a picture, a data file), copy it into Web/ and load it with a relative path. \
    Screenshots and mockups are usually just references for you: leave them in Attachments/.
    """

    static let tvLogs = """
    - Beyond `look_at_app` and `use_app`, you can't watch the app run, but Lamp saves what the TV preview's console \
    prints (console.log, warnings, errors and uncaught exceptions with their line) in .lamp/runtime/log.txt for the \
    latest opening. When the user says something doesn't work, read the log before guessing. When Lamp mentions a \
    screenshot of the app, that is what the user was looking at.
    """

    static let tvTry = """
    - `look_at_app` opens the app in the TV preview on this Mac and shows you its screen; `use_app` then presses the \
    remote's keys (key up, down, left, right, enter, back, play, pause, red, green, yellow, blue, 0-9), clicks with \
    a target or x and y, types into a field, and waits, and tells you what each landed on and what has focus. Both \
    give you the screen as text: every focusable thing and piece of text with an id, its name, what it holds, \
    whether it has focus, and where it is. Try the app the way the user will, with the keys: a TV has no pointer. \
    Both reach only the preview, which runs in this Mac's browser: what you see there, its speed included, is the \
    preview's, so say so when you tell the user what you tried. To see whether something moves, look, then \
    `use_app` with a wait, and compare where it is. In a game or anything animated, keep the work done for each \
    frame small.
    """
}
