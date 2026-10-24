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
    static var lampJS: String { DeviceSupport.webJS + remoteJS + controllersJS + wishJS }

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
         * Lamp.wish          the wish's other apps (an iPhone, Mac or Android app): who is open, messages; see its comment below
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
    /// Files between a phone and the TV in pieces (`ControllerWire`), the same code in lamp.js and lamp-controller.js:
    /// at most a window ahead of what the receiver has acknowledged, a piece only once the socket has sent the one before,
    /// so a button pressed meanwhile never waits long, and each file held to the size it was announced at.
    static let filesJS = #"""
          // Files in pieces: the same on the TV and on the phone.
          function lampFiles(onIncoming) {
            var CHUNK = 65536, HEADER = 8, WINDOW = 524288, LIMIT = 67108864, STALL = 20000;
            var TAKING = 134217728;   // bytes of files coming in at once, from everyone: a TV's memory is small
            var TOO_BIG = 'The file is too big to send: 64 MB at most.';
            var nextID = 1, outgoing = {}, incoming = {}, taking = 0;
            function noop() {}
            function key(route, id) { return route.key + ':' + id; }
            function fire(list, args) {
              for (var i = 0; i < list.length; i++) { try { list[i].apply(null, args); } catch (e) { if (window.console) console.error(e); } }
            }
            function bytesOf(data) {
              if (data instanceof ArrayBuffer) return Promise.resolve(new Uint8Array(data));
              if (data && data.buffer instanceof ArrayBuffer && typeof data.byteLength === 'number') {
                return Promise.resolve(new Uint8Array(data.buffer, data.byteOffset || 0, data.byteLength));
              }
              if (typeof Blob !== 'undefined' && data instanceof Blob) {
                // Refused by its size before it's read: reading a whole video into memory could end the page first.
                if (data.size > LIMIT) return Promise.reject(new Error(TOO_BIG));
                return new Promise(function (resolve, reject) {
                  var reader = new FileReader();
                  reader.onload = function () { resolve(new Uint8Array(reader.result)); };
                  reader.onerror = function () { reject(new Error('The file couldn\'t be read.')); };
                  reader.readAsArrayBuffer(data);
                });
              }
              if (typeof data === 'string') {
                var text = unescape(encodeURIComponent(data)), out = new Uint8Array(text.length);
                for (var i = 0; i < text.length; i++) out[i] = text.charCodeAt(i);
                return Promise.resolve(out);
              }
              return Promise.reject(new Error('sendFile takes a File, a Blob, an ArrayBuffer, bytes or text.'));
            }

            function send(route, data, info) {
              info = info || {};
              var id = nextID++;
              if (nextID > 2147483646) nextID = 1;
              var progress = [], settled = false, bytes = null, offset = 0, acked = 0, timer = null, watch = null, resolve, reject;
              var transfer = {
                id: id, name: String(info.name || (data && data.name) || 'file'),
                type: String(info.type || (data && data.type) || 'application/octet-stream'), size: 0, sent: 0,
                onProgress: function (fn) { progress.push(fn); },
                cancel: function () { if (!settled) { route.text({ t: 'file-cancel', id: id }); fail('The file was cancelled.'); } }
              };
              transfer.done = new Promise(function (yes, no) { resolve = yes; reject = no; });
              transfer.done.catch(noop);
              function fail(message) {
                if (settled) return;
                settled = true;
                clearTimeout(timer); clearTimeout(watch);
                delete outgoing[key(route, id)];
                reject(new Error(message));
              }
              function stalled() { route.text({ t: 'file-cancel', id: id }); fail('The file stopped moving.'); }
              function pump() {
                clearTimeout(timer); timer = null;
                if (settled) return;
                while (offset < transfer.size && offset - acked < WINDOW) {
                  if (route.buffered() > CHUNK) { timer = setTimeout(pump, 10); return; }
                  var n = Math.min(CHUNK, transfer.size - offset), piece = new Uint8Array(HEADER + n);
                  piece[0] = 1; piece[1] = route.place || 0;
                  piece[4] = (id >>> 24) & 255; piece[5] = (id >>> 16) & 255; piece[6] = (id >>> 8) & 255; piece[7] = id & 255;
                  piece.set(bytes.subarray(offset, offset + n), HEADER);
                  if (!route.binary(piece.buffer)) return fail('The link was lost.');
                  offset += n;
                }
              }
              bytesOf(data).then(function (read) {
                if (settled) return;
                if (read.length > LIMIT) return fail(TOO_BIG);
                bytes = read;
                transfer.size = read.length;
                outgoing[key(route, id)] = {
                  ack: function (got) {
                    if (typeof got !== 'number' || got < acked || got > offset) return;
                    acked = got;
                    transfer.sent = got;
                    clearTimeout(watch); watch = setTimeout(stalled, STALL);
                    fire(progress, [got, transfer.size]);
                    if (got === transfer.size) {
                      settled = true;
                      clearTimeout(timer); clearTimeout(watch);
                      delete outgoing[key(route, id)];
                      resolve(transfer);
                    } else pump();
                  },
                  fail: fail
                };
                if (!route.text({ t: 'file', id: id, name: transfer.name, type: transfer.type, size: transfer.size })) return fail('Not connected.');
                watch = setTimeout(stalled, STALL);
                pump();
              }, function (error) { fail(error.message); });
              return transfer;
            }

            function receive(route, m) {
              var id = m.id, size = m.size, k = key(route, id);
              if (typeof id !== 'number' || typeof size !== 'number' || size < 0 || size > LIMIT || incoming[k] || taking + size > TAKING) {
                route.text({ t: 'file-refuse', id: id, reason: 'The file is too big to take now.' });
                return;
              }
              taking += size;
              var parts = [], got = 0, progress = [], settled = false, resolve, reject;
              var file = {
                id: id, name: String(m.name || 'file'), type: String(m.type || ''), size: size, received: 0,
                onProgress: function (fn) { progress.push(fn); },
                cancel: function () { if (!settled) { route.text({ t: 'file-refuse', id: id, reason: 'Turned down.' }); fail('The file was cancelled.'); } }
              };
              file.done = new Promise(function (yes, no) { resolve = yes; reject = no; });
              file.done.catch(noop);
              function fail(message) {
                if (settled) return;
                settled = true;
                taking -= size;
                delete incoming[k];
                reject(new Error(message));
              }
              function finish() {
                var all = new Uint8Array(size), at = 0;
                for (var i = 0; i < parts.length; i++) { all.set(parts[i], at); at += parts[i].length; }
                parts = [];
                settled = true;
                taking -= size;
                delete incoming[k];
                resolve(all.buffer);
              }
              incoming[k] = {
                piece: function (bytes) {
                  if (settled) return;
                  if (got + bytes.length > size) { route.text({ t: 'file-refuse', id: id, reason: 'The file was bigger than it said.' }); return fail('The file was bigger than it said.'); }
                  parts.push(new Uint8Array(bytes));
                  got += bytes.length;
                  file.received = got;
                  route.text({ t: 'file-ack', id: id, got: got });
                  fire(progress, [got, size]);
                  if (got === size) finish();
                },
                fail: fail
              };
              onIncoming(route, file);
              if (size === 0 && !settled) { route.text({ t: 'file-ack', id: id, got: 0 }); finish(); }
            }

            return {
              send: send,
              // A file message: true when it was one.
              text: function (route, m) {
                var k = key(route, m.id);
                if (m.t === 'file') { receive(route, m); return true; }
                if (m.t === 'file-ack') { if (outgoing[k]) outgoing[k].ack(m.got); return true; }
                if (m.t === 'file-refuse') { if (outgoing[k]) outgoing[k].fail(m.reason || 'The file was turned down.'); return true; }
                if (m.t === 'file-cancel') { if (incoming[k]) incoming[k].fail('The sender cancelled the file.'); return true; }
                return false;
              },
              binary: function (route, view) {
                if (view.length < HEADER || view[0] !== 1) return;
                var id = view[4] * 16777216 + (view[5] << 16) + (view[6] << 8) + view[7];
                var file = incoming[key(route, id)];
                if (file) file.piece(view.subarray(HEADER));
              },
              // The link to someone is gone: every file on its way to or from them ends.
              drop: function (route, reason) {
                var prefix = route.key + ':', k;
                for (k in outgoing) if (k.indexOf(prefix) === 0) outgoing[k].fail(reason);
                for (k in incoming) if (k.indexOf(prefix) === 0) incoming[k].fail(reason);
              }
            };
          }

        """#

    /// Phones as controllers (`PhoneControllers`): the TV page's half. The page asks Lamp who its players are
    /// (`/app/controller`), as it opens and every few seconds after, and opens its own sockets to them: one to the relay,
    /// where phones' pages and the wish's Mac app join, and one straight to each of the wish's iPhone apps that's
    /// listening. Lamp carries none of it. The page numbers the players itself, whichever way they came. What a phone holds
    /// down is let go when it leaves or its link drops, and movement that arrives late is dropped.
    static let controllersJS = #"""
        /* Phones as controllers. Written by Lamp before every build; don't edit.
         *
         * Lamp.controllers.start()                    opens a game for phones on this Wi-Fi; Promise. The phones' page is
         *                                              Phone/index.html, loading lamp-controller.js (its own comment says how);
         *                                              the wish's iPhone or Mac app joins with LampController.
         * Lamp.controllers.onLink(fn(url))             the address phones open (show it as a QR code); it changes every
         *                                              few minutes, and fn is called each time
         * Lamp.controllers.onJoin(fn(player)), onLeave(fn(player))      players are numbered 1, 2, ... as phones join
         * Lamp.controllers.onButton(fn(player, name, down))             a button held (down true) or let go
         * Lamp.controllers.onAxis(fn(player, name, x, y))               a stick, or the phone's tilt ('tilt'), -1 to 1
         * Lamp.controllers.onMessage(fn(player, data))                  anything else a phone sent (JSON, 16 KB at most)
         * Lamp.controllers.onFile(fn(player, file))                     a phone is sending a file (up to 64 MB):
         *     file.name, file.type, file.size; file.onProgress(fn(received, size)); file.cancel();
         *     file.done.then(fn(arrayBuffer)) once all of it is here, or .catch(fn(error)) when it didn't come
         * Lamp.controllers.onError(fn(message))                         it couldn't start, the link was lost, or a
         *                                                               message was too big to send (messageLimit)
         * Lamp.controllers.send(player, data)          JSON to one phone, or to every phone with player 0; false when it
         *                                              wasn't sent, with the reason in the console
         * Lamp.controllers.messageLimit                16384: the most bytes one message takes as JSON, either way; anything
         *                                              bigger goes with sendFile
         * Lamp.controllers.sendFile(player, data, { name, type })       a File, Blob, ArrayBuffer, bytes or text, to one
         *     phone; gives a transfer: onProgress(fn(sent, size)), cancel(), done (a Promise)
         * Lamp.controllers.isHeld(player, name), players()
         * Lamp.controllers.stop()
         *
         * A phone that leaves, or whose link drops, has every button it held let go (onButton with down false) before
         * onLeave, and its files end. Movement that arrives late is dropped rather than acted on. A message over
         * messageLimit isn't sent, from the TV or from a phone, and the console here says so.
         */
        (function () {
          'use strict';
          var LATE = 300;          // ms after which a stick or tilt reading is dropped as stale
          var MESSAGE = 16384;     // bytes of JSON in one message, the most the relay passes on (ControllerWire.message)
          var on = { link: [], join: [], leave: [], button: [], axis: [], message: [], file: [], error: [] };
          var players = {}, byKey = {}, kept = {}, links = {}, link = null, linkTimer = null, askTimer = null, beatTimer = null, started = false, away = false;
        /*LAMP_FILES*/
          var files = lampFiles(function (route, file) {
            var number = byKey[route.key];
            if (number) emit('file', [number, file]); else file.cancel();
          });

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

          // Players: numbered here, whichever way they came, the lowest free number first; one who drops off and comes
          // back within two minutes gets the number they had.
          function numberFor(key, prefer) {
            var now = Date.now(), taken = {}, n, mine = kept[key];
            delete kept[key];
            for (n in players) taken[n] = true;
            for (n in kept) { if (kept[n].until > now) taken[kept[n].number] = true; else delete kept[n]; }
            if (mine && mine.until > now && !taken[mine.number]) return mine.number;
            if (prefer && !taken[prefer]) return prefer;
            for (n = 1; taken[n]; n++) {}
            return n;
          }
          function join(key, route) {
            if (byKey[key]) return byKey[key];
            var number = numberFor(key, route.place);
            byKey[key] = number;
            players[number] = { key: key, route: route, held: {}, seen: {} };
            route.text({ t: 'player', number: number });
            emit('join', [number]);
            return number;
          }
          function leave(key) {
            var number = byKey[key];
            if (!number) return;
            var player = players[number];
            files.drop(player.route, 'The player left.');
            for (var name in player.held) if (player.held[name]) emit('button', [number, name, false]);
            delete players[number];
            delete byKey[key];
            kept[key] = { number: number, until: Date.now() + 120000 };
            emit('leave', [number]);
          }
          // Each phone counts its messages from 1 on every new link, so what's been seen is forgotten when it leaves.
          function fresh(player, m) {
            var name = m.t + ':' + m.name;
            if (player.seen[name] !== undefined && m.seq <= player.seen[name]) return false;
            player.seen[name] = m.seq;
            return true;
          }
          function clamp(v) { return typeof v === 'number' && isFinite(v) ? Math.max(-1, Math.min(1, v)) : 0; }
          function bytes(text) { try { return unescape(encodeURIComponent(text)).length; } catch (e) { return text.length * 3; } }
          // What isn't sent is said in the console, which the preview keeps in the app's log: the code that sent it can't
          // tell otherwise why the other side never heard it.
          function tooBig(what, size) {
            var line = 'Lamp.controllers: ' + what + ' of ' + size + ' bytes was not sent: a message between devices is at most ' +
              MESSAGE + ' bytes as JSON. Send something big with sendFile (pad.sendFile on a phone).';
            if (window.console) console.error(line);
            emit('error', [line]);
          }
          function input(number, m, offset) {
            var player = players[number];
            if (!player || (m.t !== 'message' && !(typeof m.name === 'string' && /^[A-Za-z0-9_-]{1,32}$/.test(m.name)))) return;
            if (m.t === 'button') {
              if (!fresh(player, m)) return;
              player.held[m.name] = !!m.down;
              emit('button', [number, m.name, !!m.down]);
            } else if (m.t === 'axis') {
              if (!fresh(player, m)) return;
              if (offset !== null && typeof m.at === 'number' && Date.now() + offset - m.at > LATE) return;
              emit('axis', [number, m.name, clamp(m.x), clamp(m.y)]);
            } else if (m.t === 'message') {
              emit('message', [number, m.data]);
            }
          }

          // Links: one socket to the relay, and one to each of the wish's iPhone apps that's listening.
          function sendOn(l, m) {
            if (!l.socket || l.socket.readyState !== 1) return false;
            l.socket.send(JSON.stringify(m));
            return true;
          }
          function routeOn(l, place) {
            var relay = l.kind === 'relay';
            return {
              key: relay ? 'r' + place : 'd' + l.device, place: relay ? place : 0,
              text: function (m) { if (relay) m.player = place; return sendOn(l, m); },
              say: function (data) { return sendOn(l, relay ? { t: 'send', player: place, data: data } : { t: 'message', data: data }); },
              binary: function (buffer) { if (!l.socket || l.socket.readyState !== 1) return false; l.socket.send(buffer); return true; },
              buffered: function () { return l.socket ? l.socket.bufferedAmount : 0; }
            };
          }
          function fromLink(l, m) {
            if (typeof m.now === 'number') l.offset = m.now - Date.now();
            if (l.kind === 'relay') {
              if (m.t === 'welcome') {
                for (var i = 0; i < (m.players || []).length; i++) join('r' + m.players[i], routeOn(l, m.players[i]));
                askLink();
              } else if (m.t === 'link') {
                link = m.url;
                emit('link', [link]);
              } else if (m.t === 'joined') {
                leave('r' + m.player);
                join('r' + m.player, routeOn(l, m.player));
              } else if (m.t === 'left') {
                leave('r' + m.player);
              } else if (m.t === 'too-big') {
                tooBig('Player ' + (byKey['r' + m.player] || m.player) + "'s message", m.bytes);
              } else if (typeof m.player === 'number' && !files.text(routeOn(l, m.player), m) && /^(button|axis|message)$/.test(m.t)) {
                input(byKey['r' + m.player] || join('r' + m.player, routeOn(l, m.player)), m, l.offset);
              }
            } else if (m.t === 'welcome') {
              l.welcomed = true;
              join('d' + l.device, routeOn(l, 0));
            } else if (l.welcomed && m.t === 'too-big') {
              tooBig('Player ' + byKey['d' + l.device] + "'s message", m.bytes);
            } else if (l.welcomed && !files.text(routeOn(l, 0), m)) {
              input(byKey['d' + l.device], m, l.offset);
            }
          }
          function connect(l) {
            clearTimeout(l.again);
            if (!started || l.socket) return;
            var socket;
            try { socket = new WebSocket(l.address); } catch (e) { return lost(l, 0); }
            socket.binaryType = 'arraybuffer';
            l.socket = socket;
            l.heard = Date.now();
            socket.onopen = function () {
              socket.send(JSON.stringify(l.kind === 'relay' ? { t: 'hello', app: l.app, credential: l.credential } : { t: 'hello', credential: l.credential }));
            };
            socket.onmessage = function (event) {
              l.heard = Date.now();
              if (typeof event.data !== 'string') {
                var view = new Uint8Array(event.data);
                if (view.length > 1) files.binary(routeOn(l, l.kind === 'relay' ? view[1] : 0), view);
                return;
              }
              var m; try { m = JSON.parse(event.data); } catch (e) { return; }
              if (m && typeof m === 'object') fromLink(l, m);
            };
            socket.onclose = function (event) { if (l.socket === socket) lost(l, event.code); };
          }
          // A link that drops lets its players go. The relay's is opened again after a moment (with a fresh credential
          // once Lamp has given one); a phone's goes, and comes back if Lamp still lists it.
          function lost(l, code) {
            l.socket = null;
            l.welcomed = false;
            for (var key in byKey) if (l.kind === 'relay' ? key.charAt(0) === 'r' : key === 'd' + l.device) leave(key);
            if (!started) return;
            if (l.kind === 'relay') {
              // Turned away, or the session ended: its credential is no use, and Lamp gives a fresh one.
              if (code === 4003 || code === 4005) return ask(1000);
              l.again = setTimeout(function () { connect(l); }, code === 4009 ? 5000 : 2000);
            } else {
              delete links[l.id];
              ask(2000);
            }
          }
          function ask(after) {
            clearTimeout(askTimer);
            askTimer = setTimeout(function () {
              if (!started) return;
              LampAI._post('/app/controller', {}, 20000).then(function (answer) {
                if (!started) return;
                var list = answer.links || [];
                for (var i = 0; i < list.length; i++) {
                  var info = list[i], id = info.kind === 'relay' ? 'relay' : 'd' + info.device;
                  var l = links[id] || (links[id] = { id: id, kind: info.kind, device: info.device, socket: null, offset: null });
                  l.credential = info.credential;
                  l.app = info.app;
                  if (!l.socket) { l.address = info.socket; connect(l); }
                }
                ask((answer.renew || 15) * 1000);
              }, function (error) {
                emit('error', [error.message]);
                ask(5000);
              });
            }, after || 0);
          }
          function askLink() {
            if (links.relay) sendOn(links.relay, { t: 'link' });
            clearInterval(linkTimer);
            linkTimer = setInterval(function () { if (links.relay) sendOn(links.relay, { t: 'link' }); }, 10 * 60 * 1000);
          }
          // A beat both ways: whoever hears nothing for a while lets the other go.
          function beat() {
            var now = Date.now();
            for (var id in links) {
              var l = links[id];
              if (!l.socket || l.socket.readyState !== 1) continue;
              if (now - l.heard > 15000) { l.socket.close(); continue; }
              l.socket.send('{"t":"beat"}');
            }
          }

          var api = {
            start: function () {
              if (started) return Promise.resolve();
              started = true;
              ask(0);
              beatTimer = setInterval(beat, 5000);
              return Promise.resolve();
            },
            stop: function () {
              started = false;
              clearTimeout(askTimer); clearInterval(beatTimer); clearInterval(linkTimer);
              for (var id in links) { var l = links[id]; clearTimeout(l.again); if (l.socket) { var s = l.socket; l.socket = null; s.close(); } }
              for (var key in byKey) leave(key);
              links = {}; link = null;
            },
            send: function (player, data) {
              var text = JSON.stringify({ t: 'send', player: 8, data: data });
              if (data === undefined || text === undefined) { if (window.console) console.error('Lamp.controllers: a message was not sent: it holds nothing JSON can.'); return false; }
              if (bytes(text) > MESSAGE) { tooBig('A message', bytes(text)); return false; }
              var went = false;
              if (player) {
                went = !!players[player] && players[player].route.say(data);
              } else {
                for (var id in links) {
                  var l = links[id];
                  if (l.kind === 'relay') went = sendOn(l, { t: 'send', player: 0, data: data }) || went;
                  else if (l.welcomed) went = sendOn(l, { t: 'message', data: data }) || went;
                }
              }
              // Being away is said once until a message goes again.
              if (went) { away = false; return true; }
              if (!away && window.console) console.error('Lamp.controllers: a message was not sent: ' + (!started ? 'call Lamp.controllers.start() first.' : player ? 'there is no player ' + player + ' now.' : 'no phone is connected.'));
              away = true;
              return false;
            },
            messageLimit: MESSAGE,
            sendFile: function (player, data, info) {
              if (!players[player]) {
                var none = { onProgress: function () {}, cancel: function () {}, done: Promise.reject(new Error('There is no player ' + player + '.')) };
                none.done.catch(function () {});
                return none;
              }
              return files.send(players[player].route, data, info);
            },
            isHeld: function (player, name) { return !!(players[player] && players[player].held[name]); },
            players: function () { var list = []; for (var p in players) list.push(+p); return list.sort(function (a, b) { return a - b; }); },
            onLink: adder('link'), onJoin: adder('join'), onLeave: adder('leave'), onButton: adder('button'),
            onAxis: adder('axis'), onMessage: adder('message'), onFile: adder('file'), onError: adder('error')
          };
          if (window.Lamp) window.Lamp.controllers = api;
        })();

        """#.replacingOccurrences(of: "/*LAMP_FILES*/", with: filesJS)

    /// The wish's other apps (`WishRooms`): the TV page's half of `LampWish`, the same block the wish's Swift and Kotlin
    /// apps have. The page asks Lamp for its room (`/app/wish`, through the preview's bridge or the gateway), opens its own
    /// socket to the relay there and hears who else is in it; what the apps say to each other never passes through Lamp.
    static let wishJS = #"""
        /* The wish's other apps. Written by Lamp before every build; don't edit.
         *
         * The other apps of this app's wish (an iPhone app, a Mac app, an Android app): who is open now, and messages
         * between them, through Lamp on the Mac over the home Wi-Fi, with nothing to pair, host or set up. Each app of the
         * wish is a peer named by its part: "tv" (this one), "iphone", "mac", "android".
         *
         * Lamp.wish.start()                  joins the wish's room; call it as the app opens (the other calls do it too)
         * Lamp.wish.peers()                  the wish's other apps open now: [{ peer: 'iphone', kind, name, device, since }]
         * Lamp.wish.peer('iphone')           that app's entry, or null while it isn't open
         * Lamp.wish.onPeers(fn(list))        fn now and whenever the list changes
         * Lamp.wish.send(data, 'iphone')     JSON to one app; false (with why in the console) when it wasn't sent
         * Lamp.wish.send(data)               to every other app of the wish
         * Lamp.wish.onMessage(fn(from, data))   what another app sent: its peer name and its JSON
         * Lamp.wish.state(), onState(fn)     'connecting', 'connected', 'alone' (the wish has no other app), 'away' (Lamp
         *                                     isn't reachable), 'ended'
         * Lamp.wish.me()                     this app's own peer name
         * Lamp.wish.messageLimit             16384: the most bytes one message takes as JSON; files aren't carried yet
         * Lamp.wish.stop()
         *
         * Show plainly when an app this one needs isn't open ("Open it on your phone"), and keep the app usable meanwhile.
         * A phone steering this app as a game controller is Lamp.controllers (above), not this.
         */
        (function () {
          'use strict';
          var MESSAGE = 16384;
          var on = { peers: [], message: [], state: [] };
          var started = false, socket = null, again = null, askTimer = null, beatTimer = null, heard = 0;
          var room = null, address = null, credential = null, mine = '', peers = [], state = 'connecting', retry = 0, away = false, undeliveredSaid = {};
          var bridge = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.lampGateway;
          var device = bridge ? 'TV preview' : 'TV';

          function emit(name, args) {
            var list = on[name];
            for (var i = 0; i < list.length; i++) { try { list[i].apply(null, args); } catch (e) { if (window.console) console.error(e); } }
          }
          function setState(next) { if (state === next) return; state = next; emit('state', [state]); }
          function setPeers(next) { peers = next; emit('peers', [peers.slice()]); }
          function bytes(text) { try { return unescape(encodeURIComponent(text)).length; } catch (e) { return text.length * 3; } }
          function say(line) { if (window.console) console.error('Lamp.wish: ' + line); }

          function hear(m) {
            if (m.t === 'welcome') {
              retry = 0; away = false; undeliveredSaid = {};
              if (typeof m.peer === 'string') mine = m.peer;
              setPeers(m.peers || []);
              setState('connected');
            } else if (m.t === 'joined' && m.peer && typeof m.peer.peer === 'string') {
              setPeers(peers.filter(function (p) { return p.peer !== m.peer.peer; }).concat([m.peer]));
            } else if (m.t === 'left') {
              setPeers(peers.filter(function (p) { return p.peer !== m.peer; }));
            } else if (m.t === 'message' && typeof m.from === 'string' && m.data !== undefined) {
              emit('message', [m.from, m.data]);
            } else if (m.t === 'undelivered' && typeof m.to === 'string') {
              if (!undeliveredSaid[m.to]) { undeliveredSaid[m.to] = true; say('a message to "' + m.to + '" did not arrive: ' + (m.reason || 'it is not in the room') + '.'); }
            }
          }
          function connect() {
            if (!started || socket) return;
            var s;
            try { s = new WebSocket(address); } catch (e) { return lost(0); }
            socket = s;
            heard = Date.now();
            s.onopen = function () { s.send(JSON.stringify({ t: 'hello', app: room, credential: credential, device: device })); };
            s.onmessage = function (event) {
              heard = Date.now();
              if (typeof event.data !== 'string') return;
              var m; try { m = JSON.parse(event.data); } catch (e) { return; }
              if (m && typeof m === 'object') hear(m);
            };
            s.onclose = function (event) { if (socket === s) lost(event.code); };
          }
          // Turned away, or the room ended: the credential is no use, so Lamp is asked again; dropped otherwise, the
          // same room is joined again after a moment.
          function lost(code) {
            socket = null;
            setPeers([]);
            if (!started) return;
            if (state === 'connected') setState('connecting');
            if (code === 4003 || code === 4005 || state === 'connecting' && retry >= 3) { credential = null; address = null; }
            retry = Math.min(retry + 1, 6);
            clearTimeout(again);
            again = setTimeout(open, retry * 750);
          }
          function open() {
            if (!started || socket) return;
            if (credential && address) return connect();
            clearTimeout(askTimer);
            LampAI._post('/app/wish', { device: device }, 20000).then(function (answer) {
              if (!started) return;
              if (answer.alone) {
                // The wish has no other app: nothing to join, until one is added.
                setPeers([]); setState('alone');
                if (answer.me && answer.me.peer) mine = answer.me.peer;
                askTimer = setTimeout(open, (answer.renew || 300) * 1000);
                return;
              }
              if (!answer.socket || !answer.room || !answer.credential) throw new Error(answer.error || 'Lamp did not say where the wish\'s apps meet.');
              address = answer.socket; room = answer.room; credential = answer.credential; mine = answer.peer || mine;
              if (state !== 'connected') setState('connecting');
              connect();
            }, function (error) {
              if (!started) return;
              if (state !== 'alone') setState('away');
              say(error.message);
              askTimer = setTimeout(open, 3000);
            });
          }
          function beat() {
            if (!socket || socket.readyState !== 1) return;
            if (Date.now() - heard > 15000) { var s = socket; socket = null; s.close(); lost(0); return; }
            socket.send('{"t":"beat"}');
          }
          function adder(name) {
            return function (fn) {
              on[name].push(fn);
              api.start();
              if (name === 'peers') fn(peers.slice());
              if (name === 'state') fn(state);
              return function () { var i = on[name].indexOf(fn); if (i >= 0) on[name].splice(i, 1); };
            };
          }

          var api = {
            start: function () {
              if (started) return;
              started = true;
              open();
              beatTimer = setInterval(beat, 5000);
            },
            stop: function () {
              started = false;
              clearTimeout(askTimer); clearTimeout(again); clearInterval(beatTimer);
              if (socket) { var s = socket; socket = null; s.close(); }
              setPeers([]);
              setState('ended');
            },
            peers: function () { api.start(); return peers.slice(); },
            peer: function (id) { api.start(); for (var i = 0; i < peers.length; i++) if (peers[i].peer === id) return peers[i]; return null; },
            me: function () { api.start(); return mine; },
            state: function () { api.start(); return state; },
            messageLimit: MESSAGE,
            send: function (data, to) {
              api.start();
              var what = to ? 'a message to "' + to + '"' : 'a message to the wish\'s apps';
              if (state !== 'connected' || !socket || socket.readyState !== 1) {
                if (!away) { away = true; say(what + ' was not sent: not connected (' + state + '). Check state() and peers() before sending.'); }
                return false;
              }
              if (to && !api.peer(to)) { say(what + ' was not sent: that app is not open now.'); return false; }
              var frame = { t: 'send', data: data };
              if (to) frame.to = to;
              var text = JSON.stringify(frame);
              if (data === undefined || text === undefined) { say(what + ' was not sent: it holds nothing JSON can.'); return false; }
              if (bytes(text) > MESSAGE) { say(what + ' of ' + bytes(text) + ' bytes was not sent: a message between the wish\'s apps is at most ' + MESSAGE + ' bytes as JSON.'); return false; }
              socket.send(text);
              return true;
            },
            onMessage: adder('message'), onPeers: adder('peers'), onState: adder('state')
          };
          if (window.Lamp) window.Lamp.wish = api;
        })();

        """#

    /// Phones as controllers: the phone page's half, served by Lamp beside the app's Phone/ files as lamp-controller.js
    /// (`Store.phonePage`). Its socket goes to the controllers' relay, on this Mac by the name the page was reached at, at
    /// the port Lamp says before each try (`lamp-relay.json`), never to Lamp.
    static let phoneControllerJS = #"""
        /* Lamp's phone controller. The page is the app's own; this joins it to the TV app as a player and carries its
         * buttons, sticks, tilt and files there, over this Wi-Fi, through Lamp's relay on the Mac.
         *
         *   var pad = LampController.connect({
         *     onPlayer: function (n) { ... },        // the player number the TV app gave this phone (1, 2, ...)
         *     onMessage: function (data) { ... },   // what the TV app sent this phone (or every phone)
         *     onFile: function (file) { ... },      // the TV app is sending a file: file.name, .type, .size,
         *                                           // .onProgress(fn(received, size)), .cancel(), .done.then(fn(arrayBuffer))
         *     onState: function (state) { ... }     // 'connecting', 'connected', 'waiting' (the TV app isn't there), 'ended', 'full'
         *   });
         *   pad.button('a', true); pad.button('a', false);   // a button held, then let go
         *   pad.axis('stick', x, y);                          // a stick or slider, each from -1 to 1
         *   pad.send({ ready: true });                        // JSON to the TV app; false when it wasn't sent
         *   LampController.messageLimit                       // 16384: the most bytes one message takes as JSON. A bigger
         *                                                     // one isn't sent, and the TV app's log says so: send it
         *                                                     // with sendFile
         *   var t = pad.sendFile(file, { name, type });       // a File (from <input type="file">), Blob, ArrayBuffer, bytes
         *   t.onProgress(fn(sent, size)); t.cancel();         // or text, up to 64 MB; t.done is a Promise
         *   LampController.tilt(pad)                          // from a tap (a Start button): asks for the motion sensors,
         *     .then(function () { ... })                     // then sends the phone's tilt as axis 'tilt' (x: left -1 to
         *     .catch(function (error) { ... });              // right 1, y: away -1 to toward 1) about 30 times a second.
         *   LampController.canTilt()                          // false where the browser keeps its sensors from this page:
         *                                                     // phones give them only to https pages, and this one is http
         */
        (function () {
          'use strict';
          var MESSAGE = 16384;   // bytes of JSON in one message, the most the relay passes on (ControllerWire.message)
          function bytes(text) { try { return unescape(encodeURIComponent(text)).length; } catch (e) { return text.length * 3; } }
          var base = location.pathname.replace(/[^\/]*$/, '');
          var keyName = 'lamp-controller:' + base;
        /*LAMP_FILES*/
          // Where the relay is: asked of Lamp before each try, since it may have started again elsewhere.
          function where() {
            return fetch(base + 'lamp-relay.json', { cache: 'no-store' }).then(function (answer) {
              if (!answer.ok) throw new Error('Lamp isn\'t there.');
              return answer.json();
            });
          }

          function connect(handlers) {
            handlers = handlers || {};
            var socket = null, seq = 0, player = null, closedForGood = false, lastHeard = 0, retry = 0, again = null, host = false;
            var route = {
              key: 'tv', place: 0,
              text: function (m) { if (!socket || socket.readyState !== 1) return false; socket.send(JSON.stringify(m)); return true; },
              binary: function (buffer) { if (!socket || socket.readyState !== 1) return false; socket.send(buffer); return true; },
              buffered: function () { return socket ? socket.bufferedAmount : 0; }
            };
            var files = lampFiles(function (r, file) { if (handlers.onFile) handlers.onFile(file); else file.cancel(); });
            // The link's credential is read once and taken out of the address, so it isn't left in the history or shared
            // by mistake; the phone then keeps the one Lamp gives it, for coming back as the same player.
            var join = (location.hash || '').replace(/^#/, '');
            if (join) history.replaceState(null, '', location.pathname + location.search);
            function state(s) { if (handlers.onState) handlers.onState(s); }
            function later() {
              if (closedForGood) return;
              state('connecting');
              retry = Math.min(retry + 1, 5);
              again = setTimeout(open, 500 * retry);
            }

            // A link just opened always wins over a credential kept from before: that one may be for a game that has
            // ended, or have run out while the page was away, and the link is what the person just chose.
            function open() {
              again = null;
              // A pad closed while a reconnect waited stays closed: it mustn't rejoin beside the one that replaced it.
              if (closedForGood) return;
              var credential = join || sessionStorage.getItem(keyName);
              if (!credential) { state('ended'); return; }
              state('connecting');
              where().then(function (relay) {
                if (closedForGood) return;
                var s = new WebSocket((location.protocol === 'https:' ? 'wss:' : 'ws:') + '//' + location.hostname + ':' + relay.port + '/');
                s.binaryType = 'arraybuffer';
                socket = s;
                s.onopen = function () {
                  lastHeard = Date.now();
                  s.send(JSON.stringify({ t: 'hello', app: relay.app, credential: credential }));
                };
                s.onmessage = function (event) {
                  lastHeard = Date.now();
                  if (typeof event.data !== 'string') { files.binary(route, new Uint8Array(event.data)); return; }
                  var m; try { m = JSON.parse(event.data); } catch (e) { return; }
                  if (!m || typeof m !== 'object' || files.text(route, m)) return;
                  if (m.t === 'welcome') {
                    retry = 0; join = ''; seq = 0;
                    sessionStorage.setItem(keyName, m.credential);
                    host = !!m.host;
                    state(m.host ? 'connected' : 'waiting');
                  } else if (m.t === 'player') {
                    player = m.number;
                    if (handlers.onPlayer) handlers.onPlayer(player);
                  } else if (m.t === 'credential') {
                    sessionStorage.setItem(keyName, m.credential);
                  } else if (m.t === 'state') {
                    if (!m.host) files.drop(route, 'The TV app left.');
                    host = !!m.host;
                    state(m.host ? 'connected' : 'waiting');
                  } else if (m.t === 'message') {
                    if (handlers.onMessage) handlers.onMessage(m.data);
                  } else if (m.t === 'full') {
                    closedForGood = true; state('full');
                  }
                };
                s.onclose = function (event) {
                  if (socket !== s) return;
                  socket = null; host = false;
                  files.drop(route, 'The link was lost.');
                  if (event.code === 4003 || event.code === 4005) {
                    sessionStorage.removeItem(keyName);
                    closedForGood = true; state('ended');
                  }
                  later();
                };
              }, later);
            }

            // Too big to pass on: refused here, with a word to the TV app, whose log the builder reads (this page's
            // console is on the phone, where nobody looks), rather than sent for the relay to close the link over.
            function post(message) {
              // While the TV app isn't there ('waiting'), there's no one to give it to.
              if (!socket || socket.readyState !== 1 || !host) return false;
              message.seq = seq + 1;
              var text = JSON.stringify(message), size = bytes(text);
              if (size > MESSAGE) {
                if (window.console) console.error('LampController: a message of ' + size + ' bytes was not sent: a message between devices is at most ' + MESSAGE + ' bytes as JSON. Send something big with pad.sendFile.');
                socket.send(JSON.stringify({ t: 'too-big', bytes: size }));
                return false;
              }
              seq++;
              socket.send(text);
              return true;
            }

            // A beat both ways: Lamp's relay lets a quiet phone go, and a phone that hears nothing opens its link again.
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
              sendFile: function (data, info) { return files.send(route, data, info); },
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

          window.LampController = { connect: connect, tilt: tilt, canTilt: canTilt, messageLimit: MESSAGE };
        })();

        """#.replacingOccurrences(of: "/*LAMP_FILES*/", with: filesJS)

}

extension Agent {
    /// The rules for a TV app, in the same shape as the others' and said for the web on a TV, offering `skills`.
    /// `part`: the folder of a wish's other part this is for (`Parts.pack`), as `prompt(platform:…)` takes it.
    static func tvPrompt(skills: [String: Skills.Skill] = Skills.all, part: String? = nil) -> String {
        let rules = part == nil
            ? [Rules.tvEdit, Rules.ask, Rules.shell, Rules.tvFrameworks, Rules.tvDesign, Rules.tvKeys, Rules.tvData, Rules.tvPhone, Rules.webAI, Rules.webSound,
               Rules.icon, Rules.about, Rules.tvAttachments, Rules.tvLogs, Rules.tvTry, Rules.appMd, Rules.audience,
               Skills.index(Skills.offered(.tv), from: skills), Rules.begin, Rules.finish]
            : [Rules.tvEdit, Rules.tvFrameworks, Rules.tvDesign, Rules.tvKeys, Rules.tvData, Rules.tvPhone, Rules.webAI, Rules.webSound, Rules.tvLogs, Rules.tvTry,
               Rules.tvParts, Skills.index(Skills.offered(.tv), from: skills)]
        let header = part.map { Rules.partHeader("a TV app (HTML, CSS and JavaScript in Web/, the same files for Samsung and LG TVs, with no build step)", folder: $0) }
            ?? Rules.tvHeader
        return (header + "\n\nRules:\n" + rules.joined())
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

    /// For a TV app with another app beside it in the same wish (`Parts`): how they talk (`wishTalk`), and how an iPhone
    /// or Mac app steers the TV app's game as a player of `Lamp.controllers`.
    static let tvParts = String(wishTalk.dropFirst()) + """
    - When the wish's iPhone or Mac app steers the TV app (a game's controller, a remote), it joins the TV app the way a \
    phone's page does, as a player of `Lamp.controllers`, beside `Lamp.wish` for everything else: its buttons, sticks \
    and messages arrive in onButton, onAxis and onMessage, the files it sends in onFile, and `Lamp.controllers.send` \
    and `sendFile` reach it. Call `Lamp.controllers.start()` as the TV app opens; it needs no page in Phone/ for that.
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

    /// Sound in a web app on a device (the TV kit's and a declared web kind's): the browser's own Web Audio, which
    /// every one of them has, in the form the oldest TV browsers take.
    static let webSound = """
    - Sound, in every game and wherever else it helps (a timer's end, a buzzer): the browser's Web Audio. Make one \
    AudioContext (window.AudioContext || window.webkitAudioContext) when the app starts, and on every key press call \
    its resume() while its state isn't 'running', since a device may hold sound back until the person presses \
    something. Short effects, under a second: fetch the file with XMLHttpRequest as an arraybuffer and \
    decodeAudioData it once at the start, then play each time with a new AudioBufferSourceNode through a GainNode; \
    or, with no files, make them with an OscillatorNode (a square or triangle wave sliding up for good, down for bad) \
    and a GainNode that rises over a few milliseconds and fades out, so nothing clicks. Files are .mp3 or .wav, which \
    every device plays. Music only when it suits, quiet (gain 0.3 to 0.4) under effects at 0.6 to 0.8: an <audio> \
    element with loop, started like the context on a key press when play() is refused. A game's settings or pause \
    screen turns sound and music on and off, kept in LampStore. The preview on this Mac plays it aloud.
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
