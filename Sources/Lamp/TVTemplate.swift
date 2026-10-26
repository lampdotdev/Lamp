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
        try Template.write(lampJS(for: project), to: supportFile, for: project)
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

    /// lamp.js as an app is given it: with `Lamp.wish` only for a TV app with others in its wish
    /// (`Template.talksToOtherApps`), so a TV app on its own is written as it was before the block existed.
    static func lampJS(for project: LampProject) -> String {
        Template.talksToOtherApps(project) ? lampJS
            : DeviceSupport.webJS + remoteJS.replacingOccurrences(of: wishLine, with: "") + controllersJS
    }

    private static let wishLine = " * Lamp.wish          the wish's other apps (an iPhone, Mac or Android app): who is open, messages; see its comment below\n"

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

    /// Phones as controllers (`PhoneControllers`): the TV page's half. The page asks Lamp where its relay is
    /// (`/app/controller`), as it opens and every few seconds after, and opens its own socket there, where phones' pages
    /// join. A wish's own apps (`LampController`) come the way the wish's apps reach each other instead, which the wish's
    /// block joins here (`_attach`), so they go on playing with Lamp closed. The page numbers the players itself, whichever
    /// way they came. What a player holds down is let go when it leaves or its link drops, and movement that arrives late
    /// is dropped.
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
          // Players that come another way than Lamp's relay: each way's own code joins them here (`_attach`).
          var others = [];
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
          function join(key, route, offset) {
            if (byKey[key]) return byKey[key];
            var number = numberFor(key, route.place);
            byKey[key] = number;
            players[number] = { key: key, route: route, held: {}, seen: {}, offset: offset === undefined ? null : offset };
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

          // The link to Lamp's relay, where phones' pages join.
          function sendOn(l, m) {
            if (!l.socket || l.socket.readyState !== 1) return false;
            l.socket.send(JSON.stringify(m));
            return true;
          }
          function routeOn(l, place) {
            return {
              key: 'r' + place, place: place,
              text: function (m) { m.player = place; return sendOn(l, m); },
              say: function (data) { return sendOn(l, { t: 'send', player: place, data: data }); },
              binary: function (buffer) { if (!l.socket || l.socket.readyState !== 1) return false; l.socket.send(buffer); return true; },
              buffered: function () { return l.socket ? l.socket.bufferedAmount : 0; }
            };
          }
          function fromLink(l, m) {
            if (typeof m.now === 'number') l.offset = m.now - Date.now();
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
          }
          // What another way's code is given to join its players here, each by a key of its own: its route says how to reach
          // the player (text, say, and sendFile for a way that carries files itself), and `offset` how far its clock is
          // from this page's, for telling late movement.
          function hooks() {
            return {
              join: function (key, route, offset) { return join(key, route, offset); },
              leave: leave,
              input: function (key, m) { var n = byKey[key]; if (n) input(n, m, players[n].offset); },
              file: function (key, file) { var n = byKey[key]; if (n) emit('file', [n, file]); else file.cancel(); },
              tooBig: function (key, size) { tooBig('Player ' + (byKey[key] || '?') + "'s message", size); }
            };
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
              socket.send(JSON.stringify({ t: 'hello', app: l.app, credential: l.credential }));
            };
            socket.onmessage = function (event) {
              l.heard = Date.now();
              if (typeof event.data !== 'string') {
                var view = new Uint8Array(event.data);
                if (view.length > 1) files.binary(routeOn(l, view[1]), view);
                return;
              }
              var m; try { m = JSON.parse(event.data); } catch (e) { return; }
              if (m && typeof m === 'object') fromLink(l, m);
            };
            socket.onclose = function (event) { if (l.socket === socket) lost(l, event.code); };
          }
          // The relay's link dropping lets its players go, and it's opened again after a moment (with a fresh credential
          // once Lamp has given one).
          function lost(l, code) {
            l.socket = null;
            for (var key in byKey) if (key.charAt(0) === 'r') leave(key);
            if (!started) return;
            // Turned away, or the session ended: its credential is no use, and Lamp gives a fresh one.
            if (code === 4003 || code === 4005) return ask(1000);
            l.again = setTimeout(function () { connect(l); }, code === 4009 ? 5000 : 2000);
          }
          function ask(after) {
            clearTimeout(askTimer);
            askTimer = setTimeout(function () {
              if (!started) return;
              LampAI._post('/app/controller', {}, 20000).then(function (answer) {
                if (!started) return;
                var list = answer.links || [];
                for (var i = 0; i < list.length; i++) {
                  var info = list[i], id = 'relay';
                  if (info.kind !== 'relay') continue;
                  var l = links[id] || (links[id] = { id: id, kind: info.kind, socket: null, offset: null });
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
              for (var i = 0; i < others.length; i++) others[i].start(hooks());
              return Promise.resolve();
            },
            stop: function () {
              started = false;
              clearTimeout(askTimer); clearInterval(beatTimer); clearInterval(linkTimer);
              for (var id in links) { var l = links[id]; clearTimeout(l.again); if (l.socket) { var s = l.socket; l.socket = null; s.close(); } }
              for (var i = 0; i < others.length; i++) others[i].stop();
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
                for (var id in links) went = sendOn(links[id], { t: 'send', player: 0, data: data }) || went;
                for (var p in players) if (players[p].key.charAt(0) !== 'r') went = players[p].route.say(data) || went;
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
              var route = players[player].route;
              return route.sendFile ? route.sendFile(data, info) : files.send(route, data, info);
            },
            isHeld: function (player, name) { return !!(players[player] && players[player].held[name]); },
            players: function () { var list = []; for (var p in players) list.push(+p); return list.sort(function (a, b) { return a - b; }); },
            onLink: adder('link'), onJoin: adder('join'), onLeave: adder('leave'), onButton: adder('button'),
            onAxis: adder('axis'), onMessage: adder('message'), onFile: adder('file'), onError: adder('error'),
            // For another way players come by: `source.start(hooks)` as the game starts (now, if it has), `source.stop()`
            // as it stops.
            _attach: function (source) { others.push(source); if (started) source.start(hooks()); }
          };
          if (window.Lamp) window.Lamp.controllers = api;
        })();

        """#.replacingOccurrences(of: "/*LAMP_FILES*/", with: filesJS)

    /// The wish's other apps (`WishRooms`): the TV page's half of `LampWish`, the same block the wish's Swift and Kotlin
    /// apps have. The page asks Lamp for its room (`/app/wish`, through the preview's bridge or the gateway), opens its own
    /// socket to the relay there and hears who else is in it; what the apps say to each other never passes through Lamp.
    /// The wish's channel's crypto for lamp.js (`WishChannel` on the relay's side): SHA-256, HMAC, AES-256-GCM and X25519 in
    /// plain ES5, since a TV's page opened from its package has no WebCrypto, held to CryptoKit's own by `WishChannelTests`.
    /// Only a TV app with others in its wish carries it.
    static let wishCryptoJS = #"""
        (function () {
          'use strict';
          // SHA-256, HMAC, AES-256-GCM and X25519 in plain ES5, for TVs whose browsers have no WebCrypto on a page
          // opened from a file. Bytes are Uint8Arrays throughout. X25519 is TweetNaCl's (public domain).
          var K = [0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
            0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
            0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
            0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
            0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
            0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
            0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
            0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2];

          function concat(list) {
            var n = 0, i, out, at = 0;
            for (i = 0; i < list.length; i++) n += list[i].length;
            out = new Uint8Array(n);
            for (i = 0; i < list.length; i++) { out.set(list[i], at); at += list[i].length; }
            return out;
          }

          function sha256(data) {
            var h = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
            var length = data.length, padded = ((length + 72) >> 6) << 6, m = new Uint8Array(padded), w = new Array(64);
            var bits = length * 8, high = Math.floor(bits / 4294967296), i, j, o;
            m.set(data);
            m[length] = 0x80;
            for (i = 0; i < 4; i++) { m[padded - 1 - i] = (bits >>> (8 * i)) & 255; m[padded - 5 - i] = (high >>> (8 * i)) & 255; }
            for (o = 0; o < padded; o += 64) {
              for (i = 0; i < 16; i++) w[i] = (m[o + 4 * i] << 24) | (m[o + 4 * i + 1] << 16) | (m[o + 4 * i + 2] << 8) | m[o + 4 * i + 3];
              for (i = 16; i < 64; i++) {
                var x = w[i - 15], y = w[i - 2];
                var s0 = ((x >>> 7) | (x << 25)) ^ ((x >>> 18) | (x << 14)) ^ (x >>> 3);
                var s1 = ((y >>> 17) | (y << 15)) ^ ((y >>> 19) | (y << 13)) ^ (y >>> 10);
                w[i] = (w[i - 16] + s0 + w[i - 7] + s1) | 0;
              }
              var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], k = h[7];
              for (j = 0; j < 64; j++) {
                var t1 = (k + (((e >>> 6) | (e << 26)) ^ ((e >>> 11) | (e << 21)) ^ ((e >>> 25) | (e << 7))) + ((e & f) ^ (~e & g)) + K[j] + w[j]) | 0;
                var t2 = ((((a >>> 2) | (a << 30)) ^ ((a >>> 13) | (a << 19)) ^ ((a >>> 22) | (a << 10))) + ((a & b) ^ (a & c) ^ (b & c))) | 0;
                k = g; g = f; f = e; e = (d + t1) | 0; d = c; c = b; b = a; a = (t1 + t2) | 0;
              }
              h[0] = (h[0] + a) | 0; h[1] = (h[1] + b) | 0; h[2] = (h[2] + c) | 0; h[3] = (h[3] + d) | 0;
              h[4] = (h[4] + e) | 0; h[5] = (h[5] + f) | 0; h[6] = (h[6] + g) | 0; h[7] = (h[7] + k) | 0;
            }
            var out = new Uint8Array(32);
            for (i = 0; i < 8; i++) { out[4 * i] = h[i] >>> 24; out[4 * i + 1] = (h[i] >>> 16) & 255; out[4 * i + 2] = (h[i] >>> 8) & 255; out[4 * i + 3] = h[i] & 255; }
            return out;
          }

          function hmac(key, data) {
            if (key.length > 64) key = sha256(key);
            var inner = new Uint8Array(64), outer = new Uint8Array(64);
            for (var i = 0; i < 64; i++) { var k = i < key.length ? key[i] : 0; inner[i] = k ^ 0x36; outer[i] = k ^ 0x5c; }
            return sha256(concat([outer, sha256(concat([inner, data]))]));
          }

          // AES-256 on one 16-byte block, byte by byte: SubBytes, ShiftRows, MixColumns and the round keys.
          var SBOX = (function (hex) {
            var box = new Uint8Array(256);
            for (var i = 0; i < 256; i++) box[i] = parseInt(hex.substr(2 * i, 2), 16);
            return box;
          })('637c777bf26b6fc53001672bfed7ab76ca82c97dfa5947f0add4a2af9ca472c0b7fd9326363ff7cc34a5e5f171d8311504c723c31896059a071280e2eb27b27509832c1a1b6e5aa0523bd6b329e32f8453d100ed20fcb15b6acbbe394a4c58cfd0efaafb434d338545f9027f503c9fa851a3408f929d38f5bcb6da2110fff3d2cd0c13ec5f974417c4a77e3d645d197360814fdc222a908846eeb814de5e0bdbe0323a0a4906245cc2d3ac629195e479e7c8376d8dd54ea96c56f4ea657aae08ba78252e1ca6b4c6e8dd741f4bbd8b8a703eb5664803f60e613557b986c11d9ee1f8981169d98e949b1e87e9ce5528df8ca1890dbfe6426841992d0fb054bb16');
          function xtime(x) { return ((x << 1) ^ (x & 0x80 ? 0x1b : 0)) & 255; }
          function expand(key) {
            var w = new Array(60), i, rcon = 1;
            for (i = 0; i < 8; i++) w[i] = (key[4 * i] << 24) | (key[4 * i + 1] << 16) | (key[4 * i + 2] << 8) | key[4 * i + 3];
            for (i = 8; i < 60; i++) {
              var t = w[i - 1];
              if (i % 8 === 0) t = ((t << 8) | (t >>> 24));
              if (i % 8 === 0 || i % 8 === 4) t = (SBOX[t >>> 24] << 24) | (SBOX[(t >>> 16) & 255] << 16) | (SBOX[(t >>> 8) & 255] << 8) | SBOX[t & 255];
              if (i % 8 === 0) { t ^= rcon << 24; rcon = xtime(rcon); }
              w[i] = w[i - 8] ^ t;
            }
            return w;
          }
          function encrypt(w, block) {
            var s = new Uint8Array(16), t = new Uint8Array(16), r, c, i;
            function addKey(round) {
              for (c = 0; c < 4; c++) {
                var k = w[round * 4 + c];
                s[4 * c] ^= k >>> 24; s[4 * c + 1] ^= (k >>> 16) & 255; s[4 * c + 2] ^= (k >>> 8) & 255; s[4 * c + 3] ^= k & 255;
              }
            }
            function subShift() {
              for (i = 0; i < 16; i++) t[i] = SBOX[s[i]];
              for (c = 0; c < 4; c++) for (r = 0; r < 4; r++) s[r + 4 * c] = t[r + 4 * ((c + r) % 4)];
            }
            s.set(block);
            addKey(0);
            for (var round = 1; round < 14; round++) {
              subShift();
              for (c = 0; c < 4; c++) {
                var a0 = s[4 * c], a1 = s[4 * c + 1], a2 = s[4 * c + 2], a3 = s[4 * c + 3], all = a0 ^ a1 ^ a2 ^ a3;
                s[4 * c] ^= all ^ xtime(a0 ^ a1); s[4 * c + 1] ^= all ^ xtime(a1 ^ a2);
                s[4 * c + 2] ^= all ^ xtime(a2 ^ a3); s[4 * c + 3] ^= all ^ xtime(a3 ^ a0);
              }
              addKey(round);
            }
            subShift();
            addKey(14);
            return s;
          }

          // GCM: counter mode from the nonce, and GHASH over what was sealed, multiplied in GF(2^128) bit by bit.
          function words(b, at) { return [(b[at] << 24 | b[at + 1] << 16 | b[at + 2] << 8 | b[at + 3]) >>> 0, (b[at + 4] << 24 | b[at + 5] << 16 | b[at + 6] << 8 | b[at + 7]) >>> 0,
                                           (b[at + 8] << 24 | b[at + 9] << 16 | b[at + 10] << 8 | b[at + 11]) >>> 0, (b[at + 12] << 24 | b[at + 13] << 16 | b[at + 14] << 8 | b[at + 15]) >>> 0]; }
          function times(x, h) {
            var z0 = 0, z1 = 0, z2 = 0, z3 = 0, v0 = h[0], v1 = h[1], v2 = h[2], v3 = h[3];
            for (var i = 0; i < 128; i++) {
              if ((x[i >>> 5] >>> (31 - (i & 31))) & 1) { z0 ^= v0; z1 ^= v1; z2 ^= v2; z3 ^= v3; }
              var low = v3 & 1;
              v3 = (v3 >>> 1) | ((v2 & 1) << 31); v2 = (v2 >>> 1) | ((v1 & 1) << 31); v1 = (v1 >>> 1) | ((v0 & 1) << 31); v0 = v0 >>> 1;
              if (low) v0 ^= 0xe1000000;
            }
            return [z0 >>> 0, z1 >>> 0, z2 >>> 0, z3 >>> 0];
          }
          function ghash(h, data) {
            var x = [0, 0, 0, 0], padded = new Uint8Array(((data.length + 15) >> 4) << 4), at, bits = data.length * 8;
            padded.set(data);
            for (at = 0; at < padded.length; at += 16) {
              var y = words(padded, at);
              x = times([x[0] ^ y[0], x[1] ^ y[1], x[2] ^ y[2], x[3] ^ y[3]], h);
            }
            return times([x[0], x[1], x[2] ^ Math.floor(bits / 4294967296), (x[3] ^ bits) >>> 0], h);
          }
          function counter(w, nonce, data) {
            var out = new Uint8Array(data.length), block = new Uint8Array(16), n = 2, at, i;
            block.set(nonce);
            for (at = 0; at < data.length; at += 16, n++) {
              block[12] = n >>> 24; block[13] = (n >>> 16) & 255; block[14] = (n >>> 8) & 255; block[15] = n & 255;
              var stream = encrypt(w, block);
              for (i = 0; i < 16 && at + i < data.length; i++) out[at + i] = data[at + i] ^ stream[i];
            }
            return out;
          }
          function tag(w, nonce, sealed) {
            var h = words(encrypt(w, new Uint8Array(16)), 0), j0 = new Uint8Array(16), mask, out = new Uint8Array(16), i;
            j0.set(nonce); j0[15] = 1;
            mask = encrypt(w, j0);
            var x = ghash(h, sealed);
            for (i = 0; i < 16; i++) out[i] = mask[i] ^ ((x[i >> 2] >>> (24 - 8 * (i & 3))) & 255);
            return out;
          }
          function same(a, b) {
            if (a.length !== b.length) return false;
            var d = 0;
            for (var i = 0; i < a.length; i++) d |= a[i] ^ b[i];
            return d === 0;
          }
          // What was said, then its 16-byte tag, as CryptoKit's AES.GCM writes it with no additional data.
          function seal(key, nonce, plain) {
            var w = expand(key), sealed = counter(w, nonce, plain);
            return concat([sealed, tag(w, nonce, sealed)]);
          }
          function open(key, nonce, box) {
            if (box.length < 16) return null;
            var w = expand(key), sealed = box.subarray(0, box.length - 16);
            if (!same(tag(w, nonce, sealed), box.subarray(box.length - 16))) return null;
            return counter(w, nonce, sealed);
          }

          // X25519, from TweetNaCl.
          function gf(init) { var r = new Float64Array(16); if (init) for (var i = 0; i < init.length; i++) r[i] = init[i]; return r; }
          var C121665 = gf([0xdb41, 1]);
          function car(o) {
            var i, v, c = 1;
            for (i = 0; i < 16; i++) { v = o[i] + c + 65535; c = Math.floor(v / 65536); o[i] = v - c * 65536; }
            o[0] += c - 1 + 37 * (c - 1);
          }
          function sel(p, q, b) { var t, c = ~(b - 1); for (var i = 0; i < 16; i++) { t = c & (p[i] ^ q[i]); p[i] ^= t; q[i] ^= t; } }
          function pack(o, n) {
            var i, j, b, m = gf(), t = gf();
            for (i = 0; i < 16; i++) t[i] = n[i];
            car(t); car(t); car(t);
            for (j = 0; j < 2; j++) {
              m[0] = t[0] - 0xffed;
              for (i = 1; i < 15; i++) { m[i] = t[i] - 0xffff - ((m[i - 1] >> 16) & 1); m[i - 1] &= 0xffff; }
              m[15] = t[15] - 0x7fff - ((m[14] >> 16) & 1);
              b = (m[15] >> 16) & 1;
              m[14] &= 0xffff;
              sel(t, m, 1 - b);
            }
            for (i = 0; i < 16; i++) { o[2 * i] = t[i] & 0xff; o[2 * i + 1] = t[i] >> 8; }
          }
          function unpack(o, n) { for (var i = 0; i < 16; i++) o[i] = n[2 * i] + (n[2 * i + 1] << 8); o[15] &= 0x7fff; }
          function add(o, a, b) { for (var i = 0; i < 16; i++) o[i] = a[i] + b[i]; }
          function sub(o, a, b) { for (var i = 0; i < 16; i++) o[i] = a[i] - b[i]; }
          function mul(o, a, b) {
            var i, j, t = new Float64Array(31);
            for (i = 0; i < 16; i++) for (j = 0; j < 16; j++) t[i + j] += a[i] * b[j];
            for (i = 0; i < 15; i++) t[i] += 38 * t[i + 16];
            for (i = 0; i < 16; i++) o[i] = t[i];
            car(o); car(o);
          }
          function inverse(o, i) {
            var c = gf(), a;
            for (a = 0; a < 16; a++) c[a] = i[a];
            for (a = 253; a >= 0; a--) { mul(c, c, c); if (a !== 2 && a !== 4) mul(c, c, i); }
            for (a = 0; a < 16; a++) o[a] = c[a];
          }
          function x25519(scalar, point) {
            var z = new Uint8Array(32), x = new Float64Array(80), q = new Uint8Array(32), r, i;
            var a = gf(), b = gf(), c = gf(), d = gf(), e = gf(), f = gf();
            for (i = 0; i < 31; i++) z[i] = scalar[i];
            z[31] = (scalar[31] & 127) | 64;
            z[0] &= 248;
            unpack(x, point);
            for (i = 0; i < 16; i++) { b[i] = x[i]; d[i] = a[i] = c[i] = 0; }
            a[0] = d[0] = 1;
            for (i = 254; i >= 0; --i) {
              r = (z[i >>> 3] >>> (i & 7)) & 1;
              sel(a, b, r); sel(c, d, r);
              add(e, a, c); sub(a, a, c); add(c, b, d); sub(b, b, d);
              mul(d, e, e); mul(f, a, a); mul(a, c, a); mul(c, b, e);
              add(e, a, c); sub(a, a, c); mul(b, a, a); sub(c, d, f);
              mul(a, c, C121665); add(a, a, d); mul(c, c, a); mul(a, d, f); mul(d, b, x); mul(b, e, e);
              sel(a, b, r); sel(c, d, r);
            }
            for (i = 0; i < 16; i++) { x[i + 16] = a[i]; x[i + 32] = c[i]; x[i + 48] = b[i]; x[i + 64] = d[i]; }
            var x32 = x.subarray(32), x16 = x.subarray(16);
            inverse(x32, x32);
            mul(x16, x16, x32);
            pack(q, x16);
            return q;
          }
          var BASE = new Uint8Array(32);
          BASE[0] = 9;

          var B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
          function toBase64(b) {
            var out = '';
            for (var i = 0; i < b.length; i += 3) {
              var n = (b[i] << 16) | ((i + 1 < b.length ? b[i + 1] : 0) << 8) | (i + 2 < b.length ? b[i + 2] : 0);
              out += B64.charAt((n >>> 18) & 63) + B64.charAt((n >>> 12) & 63) + (i + 1 < b.length ? B64.charAt((n >>> 6) & 63) : '=') + (i + 2 < b.length ? B64.charAt(n & 63) : '=');
            }
            return out;
          }
          // Null for anything that isn't base64.
          function fromBase64(s) {
            if (typeof s !== 'string' || !/^[A-Za-z0-9+\/]*={0,2}$/.test(s) || s.length % 4) return null;
            var clean = s.replace(/=+$/, ''), out = new Uint8Array(Math.floor(clean.length * 3 / 4)), j = 0, n = 0, bits = 0;
            for (var i = 0; i < clean.length; i++) {
              n = ((n << 6) | B64.indexOf(clean.charAt(i))) & 0xffffff;
              bits += 6;
              if (bits >= 8) { bits -= 8; out[j++] = (n >>> bits) & 255; }
            }
            return out.subarray(0, j);
          }
          function utf8(text) {
            var s = unescape(encodeURIComponent(text)), b = new Uint8Array(s.length);
            for (var i = 0; i < s.length; i++) b[i] = s.charCodeAt(i);
            return b;
          }
          // Throws for bytes that aren't UTF-8.
          function fromUtf8(b) {
            var s = '';
            for (var i = 0; i < b.length; i += 4096) s += String.fromCharCode.apply(null, Array.prototype.slice.call(b.subarray(i, i + 4096)));
            return decodeURIComponent(escape(s));
          }
          function random(n) {
            var c = window.crypto || window.msCrypto;
            if (!c || !c.getRandomValues) throw new Error('This browser has no source of random numbers, which the wish\'s apps need to talk.');
            return c.getRandomValues(new Uint8Array(n));
          }
          // Every value the channel derives: an HMAC under the wish's key of a label, a zero byte and what it's about.
          function derive(label, key, data) { return hmac(key, concat([utf8(label), new Uint8Array(1), data || new Uint8Array(0)])); }
          function nonce(count) {
            var n = new Uint8Array(12), high = Math.floor(count / 4294967296);
            for (var i = 0; i < 4; i++) { n[11 - i] = (count >>> (8 * i)) & 255; n[7 - i] = (high >>> (8 * i)) & 255; }
            return n;
          }
          return { sha256: sha256, hmac: hmac, seal: seal, open: open, x25519: x25519, base: BASE, concat: concat, same: same,
                   toBase64: toBase64, fromBase64: fromBase64, utf8: utf8, fromUtf8: fromUtf8, random: random, derive: derive, nonce: nonce };
        })()
        """#

    static let wishJS = wishJSBody.replacingOccurrences(of: "/*LAMP_WISH_CRYPTO*/", with: wishCryptoJS.trimmingCharacters(in: .whitespacesAndNewlines))
        .replacingOccurrences(of: "/*LAMP_FILES*/", with: filesJS)

    private static let wishJSBody = #"""
        /* The wish's other apps. Written by Lamp before every build; don't edit.
         *
         * The other apps of this app's wish (an iPhone app, a Mac app, an Android app, a TV app, a game, a screen): which
         * are open now, and messages between them over the home Wi-Fi, through Lamp on the Mac and straight to the apps that
         * listen, so they go on with Lamp closed, with nothing to pair, host or set up. What they say is sealed with a key
         * only the wish's apps have. Each app of the wish is a peer named by its folder in the wish: "tv", "iphone",
         * "apple" (an app for iPhone and Mac), "mac", "android", "game", "screen"; its kind is the device word the tools
         * use for it.
         *
         * Lamp.wish.start()                  joins the wish's room; call it as the app opens (the other calls do it too)
         * Lamp.wish.peers()                  the wish's other apps open now: [{ peer: 'iphone', kind, name, device, status }]
         * Lamp.wish.apps()                   every other app of the wish, open or not
         * Lamp.wish.peer('iphone')           that app, open or not ({ ..., open, status }); null when the wish has none
         * Lamp.wish.peer('iphone').status    { state: 'connected', 'outOfDate' or 'notOpen', reason, lastSeen }: show reason as it is
         *                                     ("Open the iPhone app on your iPhone.", "The iPhone app was last open 5 min
         *                                     ago. Open it on your iPhone."); lastSeen is when it was last open on this
         *                                     device, or since when while it is, in ms since 1970, or null
         * Lamp.wish.onPeers(fn(list))        fn now and whenever any app's status changes (the open ones)
         * Lamp.wish.onApps(fn(list))         fn now and whenever any app's status changes, open or not, its reason
         *                                     included ("5 min ago" becoming "6 min ago"): every app, as apps() gives them
         * Lamp.wish.send(data, 'iphone')     JSON to one app; false (with why in the console) when it wasn't sent
         * Lamp.wish.send(data)               to every other app of the wish
         * Lamp.wish.onMessage(fn(from, data))   what another app sent: its peer name and its JSON
         * Lamp.wish.state(), status()        this app's link: 'connecting', 'connected', 'alone' (the wish has no other
         *                                     app), 'away' (neither Lamp nor another app of the wish is reachable), 'ended';
         *                                     status() is { state, reason }
         * Lamp.wish.onState(fn(state, status))   fn now and whenever this app's link changes
         * Lamp.wish.me()                     this app's own peer name
         * Lamp.wish.values()                 the values the wish's apps share, kept on each device: { list: [...], ... };
         *                                     those kept here come once the page knows its wish, with onChange
         * Lamp.wish.set('list', value)       sets one here and in every other app, now or when they next meet; null
         *                                     removes it; false (with why in the console) when it wasn't set
         * Lamp.wish.onChange(fn(key, value, from))   a value changed, here (from is me()) or in another app
         * Lamp.wish.sendFile(data, 'iphone', { name, type })   a File, Blob, ArrayBuffer, bytes or text, up to 64 MB, to
         *                                     one app open now (two at a time to each); gives a transfer: onProgress(fn(sent,
         *                                     size)), cancel(), done (a Promise that fails with why it didn't get there)
         * Lamp.wish.onFile(fn(from, file))   another app is sending a file: file.name, .type, .size,
         *                                     file.onProgress(fn(received, size)), file.cancel(), file.done.then(fn(arrayBuffer))
         * Lamp.wish.messageLimit             16384: the most bytes one message takes as JSON; anything bigger goes with sendFile
         * Lamp.wish.valueLimit, valuesLimit  8192 and 65536: the most bytes one value, and all of them, take as JSON
         * Lamp.wish.statusView('iphone')     a ready-made element of all that, kept up to date (the same one each time): a line for each other app
         *                                     ("TV app connected"), or that app's alone; it takes the page's font and colour
         * Lamp.wish.stop()
         *
         * More states may come: compare with the names above and treat any other as not connected. An open app built by
         * an older Lamp is 'outOfDate', still open, with a reason saying to open it from Lamp. Show a reason as it
         * is rather than words of your own (it changes as time goes by: "5 min ago"), and keep the app usable while an app
         * isn't open. A message or a file is for apps open now; values are for what must outlast an app being closed, and
         * where two apps set one while apart, the later setting wins in both. A phone steering this app as a game
         * controller is Lamp.controllers (above), not this; the wish's own apps that do (LampController) join
         * Lamp.controllers through this, the same way as everything else here.
         */
        (function () {
          'use strict';
          var MESSAGE = 16384, VALUE = 8192, VALUES = 65536;
          // What the wish's apps say to each other, numbered: an app that says another number was built by another Lamp.
          // 2 brought values, 3 files and a game's controls; an app from before says none, which counts as 1.
          var WIRE = 3;
          var REASONS = { connecting: "Connecting to the wish's other apps…",
                          away: "Can't reach the wish's other apps. Keep this device on the same Wi‑Fi as them." };
          var UNCLAIMED = 'This app needs Lamp to put it on this TV once more before it can reach the wish\'s other apps: press Play in Lamp on your Mac.';
          var C = /*LAMP_WISH_CRYPTO*/;
          var on = { peers: [], apps: [], message: [], state: [], change: [], file: [] };
          var started = false, socket = null, again = null, askTimer = null, beatTimer = null, heard = 0;
          var address = null, mine = '', state = 'connecting', reason = null, retry = 0, away = false, undeliveredSaid = {};
          // This link's handshake while it's under way, then its seals each way: what goes, and what comes, each counted.
          var hello = null, sent = 0, opened = 0, sendKey = null, openKey = null;
          var bridge = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.lampGateway;
          // In Lamp's WebView2 host on the Xbox the page is https, which may not open the plain links the wish's apps
          // speak: the host opens them for it and passes each frame both ways as it is (`opener`, below), while
          // everything here, the handshake and the seals included, stays the page's.
          var pipe = !bridge && window.chrome && window.chrome.webview && typeof window.chrome.webview.postMessage === 'function'
            ? window.chrome.webview : null;
          var device = bridge ? 'TV preview' : pipe ? 'Xbox' : 'TV';
          // Where Lamp is, filled in by Lamp in the package it puts on a TV, and the wish's key: the preview is given it by
          // Lamp through its bridge; a TV asks Lamp for it sealed to a key pair it makes, just after Lamp put the app
          // there (`claim`), and keeps it.
          var installed = /*LAMP_INSTALL*/null;
          var key = null, claiming = null, claims = 0, claimPair = null;
          // In the app of Lamp's own around a game's or a screen's page on the Mac, an iPhone or an iPad, and around a
          // game's on Android, that app is the wish's peer, with the same LampWish as the wish's Swift and Kotlin apps (it
          // listens, is found, keeps the values on the device), and this page mirrors it (`hosted`, below); Android's
          // takes text. On the Xbox the page is the peer itself, as on a TV, its links opened by the host. A page served
          // over https anywhere else can't open the plain links the wish's apps speak, nor ask Lamp itself, and a game's
          // page in Lamp's own preview has no way to Lamp at all, so each says so.
          var host = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.lampWish;
          if (!host && window.lampWishHost && typeof window.lampWishHost.postMessage === 'function') {
            host = { postMessage: function (m) { window.lampWishHost.postMessage(JSON.stringify(m)); } };
          }
          if (host) pipe = null;
          var where = window.location ? window.location.protocol : '';
          var stranded = !host && !bridge && !pipe && (where === 'https:' || where === 'lamp-game:');
          var STRANDED = "Can't reach the wish's other apps on this device yet.";
          // Two ways to the others, used together: Lamp's room while Lamp is open on the Mac, and a link straight to each
          // app of the wish that listens (a TV page can't listen itself), at the address it was last reached at or said it
          // listens, else looked for on this network at the wish's port for it. Each is sealed the same way, with the
          // wish's key; a message goes the straight way when there is one. So the apps go on talking with Lamp closed.
          var relayIn = false, lampAway = false, alone = false, relayPresent = {}, roster = [], restored = false;
          var directs = {}, dialing = {}, nextDial = {}, told = {}, openSince = {}, lastSeen = {}, devices = {};
          var apps = [], lastOpen = '[]', swept = 0, here = null, pending = [], epoch = 0;
          // The apps Lamp hasn't made yet, what this page last told Lamp's room of its link, and the status views to draw.
          var waiting = {}, reported = '', beats = 0, views = [], lastDrawn = '', lastApps = '[]';
          // Each value as it was last set, here or by another app, and when ({ v, c: [ms, n, peer] }; a removed one keeps
          // its c, so an older setting from an app that was away doesn't bring it back), and this page's clock for them:
          // the latest it has set or heard of, so what it sets next is later than anything it knows of.
          var entries = Object.create(null), clock = [0, 0];
          // Files to and from the other apps, each on the way it started on (a file's pieces and acknowledgements can't
          // change ways halfway): a route for each app and way (`routeTo`); what a file is for (`ch`: '' for onFile, 'pad'
          // for Lamp.controllers) is said as it starts.
          var routes = {}, links_ = 0, coming = '';
        /*LAMP_FILES*/
          var files = lampFiles(function (route, file) {
            var ch = coming, key = ch.indexOf('pad') === 0 ? padKey(route.peer, ch.slice(4)) : null;
            // A file that stops coming ends, as one that stops going does.
            var watch = setTimeout(stalled, 20000);
            function stalled() { file.cancel(); }
            file.onProgress(function () { clearTimeout(watch); watch = setTimeout(stalled, 20000); });
            file.done.then(function () { clearTimeout(watch); }, function () { clearTimeout(watch); });
            if (key !== null) { if (padHooks && padPlayers[key]) padHooks.file(key, file); else file.cancel(); }
            else if (on.file.length) emit('file', [route.peer, file]);
            else file.cancel();
          });
          // The wish's own apps playing this app's game (LampController): joined to Lamp.controllers while it takes
          // players, each controller of each app a player of its own ('w' + its app's peer name + ':' + its id).
          var padHooks = null, padPlayers = {};
          function padKey(peer, id) { return 'w' + peer + (typeof id === 'string' && /^[a-z0-9]{1,16}$/.test(id) ? ':' + id : ''); }

          function emit(name, args) {
            var list = on[name];
            for (var i = 0; i < list.length; i++) { try { list[i].apply(null, args); } catch (e) { if (window.console) console.error(e); } }
          }
          function status() { return { state: state, reason: reason !== null ? reason : (REASONS[state] || '') }; }
          function setState(next, why) {
            var said = why === undefined ? null : why;
            if (state === next && reason === said) return;
            state = next; reason = said;
            emit('state', [state, status()]);
            draw();
          }
          function copy(p) { return { peer: p.peer, kind: p.kind, name: p.name, device: p.device, open: p.open,
                                      status: { state: p.status.state, reason: p.status.reason, lastSeen: p.status.lastSeen } }; }
          function allOnes() { var list = []; for (var i = 0; i < apps.length; i++) list.push(copy(apps[i])); return list; }
          function openOnes() { var list = []; for (var i = 0; i < apps.length; i++) if (apps[i].open) list.push(copy(apps[i])); return list; }
          function find(id) { for (var i = 0; i < apps.length; i++) if (apps[i].peer === id) return apps[i]; return null; }
          // Why another app isn't there, in the same words in every language Lamp's apps are written in: where to open
          // it, and when it was last open here when it has been.
          var PLACES = { tv: 'your TV', mac: 'your Mac', iphone: 'your iPhone', android: 'your Android device' };
          function notOpen(name, kind, seen, notYet, now) {
            var title = name.charAt(0).toUpperCase() + name.slice(1), place = PLACES[kind] || 'its device';
            // Having been open here outranks a list that still says it isn't made.
            if (notYet && !seen) return title + " isn't ready yet.";
            if (!seen) return 'Open ' + name + ' on ' + place + '.';
            return title + ' was last open ' + ago(now - seen) + '. Open it on ' + place + '.';
          }
          function ago(ms) {
            var minutes = Math.floor(Math.max(0, ms) / 60000), hours = Math.floor(minutes / 60), days = Math.floor(hours / 24);
            if (minutes < 1) return 'a moment ago';
            if (minutes < 60) return minutes + ' min ago';
            if (hours < 24) return hours === 1 ? 'an hour ago' : hours + ' hours ago';
            return days === 1 ? 'yesterday' : days + ' days ago';
          }
          function outOfDate(name, older) {
            return older ? name.charAt(0).toUpperCase() + name.slice(1) + ' is out of date. Open it from Lamp on your Mac to update it.'
                         : 'This app is older than ' + name + '. Open it from Lamp on your Mac to update it.';
          }
          function connected(name) { return (name.indexOf('the ') === 0 ? name.slice(4) : name) + ' connected'; }
          function bytes(text) { try { return unescape(encodeURIComponent(text)).length; } catch (e) { return text.length * 3; } }
          function say(line) { if (window.console) console.error('Lamp.wish: ' + line); }
          function isName(n) { return typeof n === 'string' && /^[a-z0-9-]{1,32}$/.test(n); }
          function hex(b) { var s = ''; for (var i = 0; i < b.length; i++) s += (b[i] < 16 ? '0' : '') + b[i].toString(16); return s; }

          // The state and the list of apps, from what each way says now.
          function rebuild() {
            var now = Date.now(), next = [], any = false, arrived = [], named = false;
            // Values set before this page knew its own name take it now, so two apps' settings never tie.
            if (mine) for (var k in entries) if (entries[k].c[2] === '') { entries[k].c = [entries[k].c[0], entries[k].c[1], mine]; named = true; }
            if (named) keepValues();
            for (var i = 0; i < roster.length; i++) {
              var a = roster[i];
              if (a.peer === mine) continue;
              var d = directs[a.peer] && directs[a.peer].ready ? directs[a.peer] : null, r = relayPresent[a.peer];
              var open = started && (!!d || !!r);
              if (open) {
                // Open, so made, whatever a list kept from before said.
                delete waiting[a.peer];
                if (!openSince[a.peer]) { openSince[a.peer] = r && r.since || now; arrived.push(a.peer); }
                var dev = d ? d.device : r.device;
                if (dev) devices[a.peer] = dev;
              } else if (openSince[a.peer]) { delete openSince[a.peer]; lastSeen[a.peer] = now; keep(); }
              var w = d ? d.wire : r ? r.wire : WIRE;
              next.push({ peer: a.peer, kind: a.kind, name: a.name, device: devices[a.peer] || '', open: open,
                          status: open && w !== WIRE ? { state: 'outOfDate', reason: outOfDate(a.name, w < WIRE), lastSeen: openSince[a.peer] }
                                : open ? { state: 'connected', reason: '', lastSeen: openSince[a.peer] }
                                       : { state: 'notOpen', reason: notOpen(a.name, a.kind, lastSeen[a.peer], waiting[a.peer], now), lastSeen: lastSeen[a.peer] || null } });
            }
            apps = next;
            for (var id in directs) if (directs[id].ready) any = true;
            // An app no longer open takes its files and its place in the game with it; one that has just come is told the
            // game takes players.
            for (var g = 0; g < apps.length; g++) {
              if (apps[g].open) continue;
              dropRoutes(apps[g].peer, null, apps[g].name.charAt(0).toUpperCase() + apps[g].name.slice(1) + ' closed.');
              for (var pk in padPlayers) if (padPlayers[pk].peer === apps[g].peer) { delete padPlayers[pk]; if (padHooks) padHooks.leave(pk); }
            }
            if (padHooks) for (var q = 0; q < arrived.length; q++) sendPad(arrived[q], { t: 'host' });
            // This page's own state first: code that hears an app arrive in peers sends to it at once, and must find this
            // page connected when it does.
            if (started) {
              var s = alone ? 'alone' : (relayIn || any) ? 'connected' : lampAway ? 'away' : 'connecting';
              if (s === 'connected') away = false;
              if (s !== state || reason !== null) setState(s);
            }
            var said = JSON.stringify(openOnes());
            if (said !== lastOpen) { lastOpen = said; emit('peers', [openOnes()]); }
            var every = JSON.stringify(apps);
            if (every !== lastApps) { lastApps = every; emit('apps', [allOnes()]); }
            draw();
            report();
            // An app that has just come is told every value this page has, and tells this page its own, so the two agree
            // again whichever was open meanwhile.
            for (var j = 0; j < arrived.length; j++) if (wireOf(arrived[j]) >= 2) share(entries, arrived[j]);
          }
          // What another open app speaks: 1 for an app from before values, which says nothing of it.
          function wireOf(id) {
            var d = directs[id];
            if (d && d.ready) return d.wire;
            return relayPresent[id] ? relayPresent[id].wire : 1;
          }
          // Tells Lamp's room how this page's link stands (its state, and which apps it reaches straight), only when that
          // changes, so the builder can tell an app that can't reach the others on the network from one that does.
          function report() {
            if (!relayIn || !sendKey || !socket) return;
            var direct = [];
            for (var id in directs) if (directs[id].ready) direct.push(id);
            direct.sort();
            var now = state + ' ' + direct.join(',');
            if (now === reported) return;
            reported = now;
            seal(JSON.stringify({ t: 'status', state: state, direct: direct }));
          }
          // The status views (statusView), drawn again when what they show has changed.
          function lines(only) {
            var list = [], s = status();
            // Stopped: it no longer knows who is open.
            if (state === 'ended') return list;
            if (state !== 'connected' && s.reason) return [['#f59e0b', s.reason]];
            for (var i = 0; i < apps.length; i++) {
              var a = apps[i];
              if (!only || a.peer === only) list.push(a.status.state === 'connected' ? ['#22c55e', connected(a.name)]
                                                       : a.status.state === 'outOfDate' ? ['#f59e0b', a.status.reason] : ['#9ca3af', a.status.reason]);
            }
            return list;
          }
          function draw(force) {
            if (!views.length) return;
            var drawn = JSON.stringify([state, status().reason, apps]);
            if (drawn === lastDrawn && !force) return;
            lastDrawn = drawn;
            for (var v = 0; v < views.length; v++) {
              var el = views[v].el, list = lines(views[v].only);
              while (el.firstChild) el.removeChild(el.firstChild);
              for (var i = 0; i < list.length; i++) {
                var row = document.createElement('div'), dot = document.createElement('span'), text = document.createElement('span');
                row.style.margin = '0.2em 0';
                dot.style.cssText = 'display:inline-block;width:0.5em;height:0.5em;border-radius:50%;margin-right:0.45em;vertical-align:middle;background:' + list[i][0];
                text.textContent = list[i][1];
                row.appendChild(dot); row.appendChild(text);
                el.appendChild(row);
              }
            }
          }
          function setRoster(list) {
            var given = [];
            for (var i = 0; list && i < list.length; i++) {
              var a = list[i];
              if (a && isName(a.peer)) given.push({ peer: a.peer, kind: a.kind || '', name: typeof a.name === 'string' ? a.name : a.peer });
            }
            if (!given.length) return;
            roster = given;
            waiting = {};
            for (var w = 0; list && w < list.length; w++) if (list[w] && list[w].waiting === true && isName(list[w].peer)) waiting[list[w].peer] = true;
            for (var id in directs) if (!inRoster(id)) drop(directs[id]);
            keep();
            rebuild();
          }
          function inRoster(id) { for (var i = 0; i < roster.length; i++) if (roster[i].peer === id) return true; return false; }

          // The values: every app orders two settings the same way, by the clock of the app that set it, then the count
          // within that millisecond, then that app's name. Times within 2^50 ms and counts within a million, whole.
          var LATEST = 1125899906842624, COUNTS = 1000000, REMOVALS_KEPT = 30 * 24 * 3600 * 1000;
          function later(a, b) { return a[0] !== b[0] ? a[0] > b[0] : a[1] !== b[1] ? a[1] > b[1] : a[2] > b[2]; }
          function whole(x, most) { return typeof x === 'number' && x >= 0 && x % 1 === 0 && x <= most; }
          function stampOk(c) {
            return c instanceof Array && c.length === 3 && whole(c[0], LATEST) && whole(c[1], COUNTS) && typeof c[2] === 'string' && bytes(c[2]) <= 32;
          }
          // A name every app can keep a value under: 1 to 64 bytes, and not the one that changes what a page's object is.
          function nameOk(k) { return typeof k === 'string' && k.length > 0 && bytes(k) <= 64 && k !== '__proto__'; }
          function own(o, k) { return Object.prototype.hasOwnProperty.call(o, k); }
          function names(o) { var list = []; for (var k in o) if (own(o, k)) list.push(k); list.sort(); return list; }
          function copyOf(v) { return v === undefined ? null : JSON.parse(JSON.stringify(v)); }
          // What a setting takes in the store: its name, and its value as JSON or at least 32 bytes, which is what its
          // removal takes while kept. Counted the same when an app sets and when it takes from others, so all an app can
          // make, removals included, fits in what the others take from it.
          function heldBy(key, v) { return bytes(key) + (v === undefined ? 32 : Math.max(32, bytes(JSON.stringify(v)))); }
          // What the store takes, removals kept included, leaving one name out.
          function sizeWithout(key) {
            var total = 0;
            for (var k in entries) if (k !== key) total += heldBy(k, entries[k].v);
            return total;
          }
          function valuesNow() { var o = {}; for (var k in entries) if (entries[k].v !== undefined) o[k] = entries[k].v; return o; }
          function valuesChanged(changed, from) {
            keepValues();
            // Each handler gets a copy, so changing it changes nothing kept.
            for (var i = 0; i < changed.length; i++) emit('change', [changed[i][0], copyOf(changed[i][1]), from]);
          }
          // What every setting this page has adds up to, sealed with the wish's key: two apps with the same say the same.
          function digest() {
            if (!key) return '';
            var parts = [], list = names(entries);
            for (var i = 0; i < list.length; i++) {
              var c = entries[list[i]].c;
              parts.push(C.utf8(list[i]), new Uint8Array([0]), C.utf8(String(c[0])), new Uint8Array([0]), C.utf8(String(c[1])), new Uint8Array([0]), C.utf8(c[2]), new Uint8Array([0]));
            }
            return C.toBase64(C.derive('lamp-wish values', key, C.concat(parts)).subarray(0, 8));
          }
          // What another app sent of the values: settings, taken when later than this page's; what all of its add up to
          // (sum), answered with all of this page's and a request for all of its when they differ; and that request (ask),
          // answered with all of this page's. So a setting lost on the way is made up within a minute.
          function heardValues(m, from) {
            merge(m.values, from);
            if (typeof m.sum === 'string' && m.sum !== digest()) share(entries, from, { ask: true });
            else if (m.ask === true) share(entries, from);
          }
          // Settings another app sent: each taken when it's later than what this page has, so whichever order they come
          // in, every app ends with the same.
          function merge(given, from) {
            if (!given || typeof given !== 'object') return;
            var changed = [], list = names(given);
            // What the store holds may grow, from other apps, to what every app of the wish could have set between them
            // (each sets at most the limit of the whole), twice over for how apps measure: everything they set fits, so
            // they still agree, and an app gone wrong or hostile that floods the others gets no further.
            dropExpired();
            var most = VALUES * 2 * Math.max(2, roster.length), held = 0, removals = null, next = 0;
            for (var h in entries) held += heldBy(h, entries[h].v);
            // The oldest removal kept, other than this name's: let go first when something needs room, since a removal
            // only outvotes an older copy of what it removed, and the oldest matter least.
            function oldestRemoval(except) {
              if (!removals) {
                removals = [];
                for (var r in entries) if (entries[r].v === undefined) removals.push(r);
                removals.sort(function (a, b) { return later(entries[a].c, entries[b].c) ? 1 : later(entries[b].c, entries[a].c) ? -1 : 0; });
              }
              while (next < removals.length) {
                var k = removals[next++];
                if (k !== except && entries[k] && entries[k].v === undefined) return k;
              }
              return null;
            }
            for (var i = 0; i < list.length; i++) {
              var key = list[i], e = given[key];
              if (!nameOk(key) || !e || typeof e !== 'object' || !stampOk(e.c)) continue;
              if (e.c[0] > clock[0] || (e.c[0] === clock[0] && e.c[1] > clock[1])) clock = [e.c[0], e.c[1]];
              if (entries[key] && !later(e.c, entries[key].c)) continue;
              var v = e.v === null ? undefined : e.v;
              // Held to twice a value's limit, since apps measure a little differently, and not to the whole: apps apart
              // may each have filled it, and taking every app's values whatever the order is what makes them agree.
              if (v !== undefined && bytes(JSON.stringify(v)) > VALUE * 2) continue;
              var old = entries[key] ? heldBy(key, entries[key].v) : 0, need = heldBy(key, v), gone;
              while (held - old + need > most && (gone = oldestRemoval(key))) { held -= heldBy(gone, undefined); delete entries[gone]; }
              if (held - old + need > most) {
                // A value that doesn't fit beside the others' values is left; a removal goes all the same, without
                // keeping it, so a value removed is never left behind.
                if (v !== undefined || !entries[key]) continue;
                var had = entries[key].v;
                held -= old;
                delete entries[key];
                if (had !== undefined) changed.push([key, undefined]);
                continue;
              }
              held = held - old + need;
              entries[key] = { v: v, c: e.c };
              changed.push([key, v]);
            }
            if (changed.length) valuesChanged(changed, from);
          }
          // Sends settings to another open app, the straight way when there is one, else through Lamp's room, a few at a
          // time so each message stays within what a message may be; extra goes with the last.
          function share(list, id, extra) {
            var batch = {}, size = 0, any = false;
            function flush(last) {
              if (!any && !(last && extra)) return;
              var frame = { t: 'values', values: batch };
              if (last && extra) for (var x in extra) frame[x] = extra[x];
              var d = directs[id];
              if (d && d.ready) directSeal(d, JSON.stringify(frame));
              else if (relayPresent[id] && socket && socket.readyState === 1 && sendKey) { frame.to = id; seal(JSON.stringify(frame)); }
              batch = {}; size = 0; any = false;
            }
            var keys = names(list);
            for (var i = 0; i < keys.length; i++) {
              var e = list[keys[i]], json = { c: e.c };
              if (e.v !== undefined) json.v = e.v;
              // The name as JSON writes it, escapes included.
              var b = bytes(JSON.stringify(json)) + bytes(JSON.stringify(keys[i])) + 2;
              if (size + b > 12288) flush(false);
              batch[keys[i]] = json; size += b; any = true;
            }
            flush(true);
          }
          // A removal is kept for a month, then let go: before anything is weighed against a limit, and before what's
          // kept is written, so an app whose removals filled it can set values again once the month is over.
          function dropExpired() {
            var old = Date.now() - REMOVALS_KEPT;
            for (var k in entries) if (entries[k].v === undefined && entries[k].c[0] <= old) delete entries[k];
          }
          function keepValues() {
            dropExpired();
            var n = keptName();
            if (!n) return;
            var kept = {};
            for (var k in entries) {
              kept[k] = { c: entries[k].c };
              if (entries[k].v !== undefined) kept[k].v = entries[k].v;
            }
            storage(n + '.values', { values: kept, clock: clock });
          }
          // What was kept on this TV, once the wish's key is known: taken in beside anything set before then, and said to
          // onChange, since a page may have looked at values() before it was there.
          function restoreValues() {
            var k = storage(keptName() + '.values');
            if (!k || typeof k !== 'object') return;
            if (k.clock instanceof Array && k.clock.length === 2 && whole(k.clock[0], LATEST) && whole(k.clock[1], COUNTS)
                && (k.clock[0] > clock[0] || (k.clock[0] === clock[0] && k.clock[1] > clock[1]))) clock = [k.clock[0], k.clock[1]];
            var kept = k.values && typeof k.values === 'object' ? k.values : {}, list = names(kept), changed = [];
            for (var i = 0; i < list.length; i++) {
              var key = list[i], e = kept[key];
              if (!nameOk(key) || !e || !stampOk(e.c)) continue;
              if (entries[key] && !later(e.c, entries[key].c)) continue;
              entries[key] = { v: e.v === null ? undefined : e.v, c: e.c };
              changed.push([key, entries[key].v]);
            }
            keepValues();
            for (var j = 0; j < changed.length; j++) emit('change', [changed[j][0], copyOf(changed[j][1]), mine]);
          }

          // What the page keeps on the TV, beside LampAI's own: the routes it was told and the wish's key it claimed, and
          // by the wish's tag who it is, the wish's apps and where each was last reached, so it finds them with Lamp closed.
          function storage(name, value) {
            try {
              if (value === undefined) { var v = window.localStorage.getItem('lamp:' + name); return v === null ? null : JSON.parse(v); }
              window.localStorage.setItem('lamp:' + name, JSON.stringify(value));
            } catch (e) {}
            return null;
          }
          function keptName() { return key ? 'wish.' + hex(C.derive('lamp-wish tag', key).subarray(0, 8)) : null; }
          function keep() {
            var n = keptName(), list = [];
            if (!n) return;
            for (var i = 0; i < roster.length; i++) {
              var a = roster[i], kept = { peer: a.peer, kind: a.kind, name: a.name };
              if (waiting[a.peer]) kept.waiting = true;
              list.push(kept);
            }
            storage(n, { me: mine, apps: list, at: told, seen: lastSeen });
          }
          function restore() {
            if (restored || !key) return;
            restored = true;
            restoreValues();
            var k = storage(keptName());
            if (!k) return;
            if (!mine && isName(k.me)) mine = k.me;
            if (k.at && typeof k.at === 'object') for (var id in k.at) if (isName(id) && k.at[id] instanceof Array) told[id] = k.at[id].slice(0, 6);
            if (k.seen && typeof k.seen === 'object') for (var p in k.seen) if (isName(p) && typeof k.seen[p] === 'number') lastSeen[p] = k.seen[p];
            if (!roster.length && k.apps instanceof Array) { setRoster(k.apps); alone = roster.length < 2 && roster.length > 0; }
          }
          function remember(id, places) {
            if (id === mine || !(places instanceof Array)) return;
            var list = [], had = told[id] || [], i;
            for (i = 0; i < places.length; i++) if (typeof places[i] === 'string' && places[i] && list.indexOf(places[i]) < 0) list.push(places[i]);
            if (!list.length) return;
            for (i = 0; i < had.length; i++) if (list.indexOf(had[i]) < 0) list.push(had[i]);
            told[id] = list.slice(0, 6);
            keep();
          }

          // A link as a WebSocket, or on the Xbox its stand-in over the host's pipe, with the same calls the code below
          // uses (send, close, readyState, bufferedAmount, onopen, onmessage, onclose, onerror). The host may open only
          // links to this network, and tells the page as each frame has gone, so a file's flow counts what's still to go.
          var piped = {}, pipeIds = 0;
          function opener(url) {
            if (!pipe) return new WebSocket(url);
            var id = ++pipeIds, sizes = [];
            var s = piped[id] = { readyState: 0, bufferedAmount: 0, binaryType: 'arraybuffer', onopen: null, onmessage: null, onclose: null, onerror: null,
              send: function (data) {
                if (s.readyState !== 1) throw new Error('The link is not open.');
                var m = { lamp: 'ws', op: 'send', id: id }, n;
                if (typeof data === 'string') { m.text = data; n = data.length; }
                else {
                  var b = data instanceof ArrayBuffer ? new Uint8Array(data) : new Uint8Array(data.buffer, data.byteOffset, data.byteLength), t = '';
                  for (var i = 0; i < b.length; i += 32768) t += String.fromCharCode.apply(null, b.subarray(i, i + 32768));
                  m.data = btoa(t); n = b.length;
                }
                sizes.push(n); s.bufferedAmount += n;
                pipe.postMessage(m);
              },
              close: function () {
                if (s.readyState >= 2) return;
                s.readyState = 2;
                pipe.postMessage({ lamp: 'ws', op: 'close', id: id });
                setTimeout(function () { gone(1000); }, 0);
              } };
            function gone(code) {
              if (piped[id] !== s) return;
              delete piped[id];
              s.readyState = 3;
              if (code === 1006 && s.onerror) s.onerror({});
              if (s.onclose) s.onclose({ code: code });
            }
            s._heard = function (m) {
              if (m.ev === 'open' && s.readyState === 0) { s.readyState = 1; if (s.onopen) s.onopen({}); }
              else if (m.ev === 'message' && s.readyState === 1 && s.onmessage) {
                var data = m.text;
                if (typeof data !== 'string') {
                  var t = atob(m.data || ''), b = new Uint8Array(t.length);
                  for (var i = 0; i < t.length; i++) b[i] = t.charCodeAt(i);
                  data = b.buffer;
                }
                s.onmessage({ data: data });
              } else if (m.ev === 'sent' && sizes.length) s.bufferedAmount -= sizes.shift();
              else if (m.ev === 'close') gone(typeof m.code === 'number' ? m.code : 1006);
            };
            pipe.postMessage({ lamp: 'ws', op: 'open', id: id, url: url });
            return s;
          }
          if (pipe) pipe.addEventListener('message', function (e) {
            var m = e.data;
            if (!m || m.lamp !== 'ws') return;
            if (m.ev === 'here') {
              var list = m.addresses instanceof Array ? m.addresses : [];
              for (var i = 0; i < list.length; i++) if (typeof list[i] === 'string' && /^\d+\.\d+\.\d+\.\d+$/.test(list[i])) { here = list[i]; break; }
              return;
            }
            if (piped[m.id]) piped[m.id]._heard(m);
          });

          // The wish's key from Lamp, sealed to a key pair made here and now, so nobody else on the network can open it.
          function claim() {
            if (claiming) return claiming;
            var routes = (storage('install.routes') || []).concat(installed && installed.routes || []);
            var ipv4 = /^http:\/\/\d+\.\d+\.\d+\.\d+:/;
            routes = routes.filter(function (r) { return ipv4.test(r); }).concat(routes.filter(function (r) { return !ipv4.test(r); }));
            // One key pair for the page's tries, so a try after an answer lost on its way is answered again.
            if (!claimPair) { var made = C.random(32); claimPair = { secret: made, ours: C.x25519(made, C.base) }; }
            var secret = claimPair.secret, ours = claimPair.ours;
            function attempt(i) {
              if (i >= routes.length) return Promise.reject(new Error(UNCLAIMED));
              var body = JSON.stringify({ app: installed.app, 'public': C.toBase64(ours) });
              // On the Xbox, Lamp's plain-http gateway is asked through the host, as LampAI asks it.
              var asked = pipe && LampAI._exchange ? LampAI._exchange(routes[i], '/app/wish/claim', '', body, 10000) : new Promise(function (resolve, reject) {
                var xhr = new XMLHttpRequest();
                xhr.open('POST', routes[i] + '/app/wish/claim');
                xhr.timeout = 10000;
                xhr.setRequestHeader('Content-Type', 'application/json');
                xhr.onload = function () { var r = null; try { r = JSON.parse(xhr.responseText); } catch (e) {} resolve({ status: xhr.status, reply: r || {} }); };
                xhr.onerror = xhr.ontimeout = function () { reject(new Error('unreachable')); };
                xhr.send(body);
              });
              return asked.then(function (answer) {
                if (answer.status !== 200) throw new Error(UNCLAIMED);
                var theirs = C.fromBase64(answer.reply['public']), nonce = C.fromBase64(answer.reply.nonce), box = C.fromBase64(answer.reply.sealed);
                if (!theirs || theirs.length !== 32 || !nonce || nonce.length !== 12 || !box) throw new Error(UNCLAIMED);
                var shared = C.x25519(secret, theirs), zero = 0;
                // A key that makes every secret zero (a low-order point) seals nothing anyone should trust.
                for (var z = 0; z < shared.length; z++) zero |= shared[z];
                if (!zero) throw new Error(UNCLAIMED);
                var sealing = C.derive('lamp-wish claim', shared, C.concat([theirs, ours]));
                var unsealed = C.open(sealing, nonce, box);
                if (!unsealed || unsealed.length !== 32) throw new Error(UNCLAIMED);
                storage('install.wish', { app: installed.app, key: C.toBase64(unsealed) });
                return unsealed;
              }, function () { return attempt(i + 1); });
            }
            claiming = attempt(0);
            claiming.then(function () { claiming = null; }, function () { claiming = null; });
            return claiming;
          }
          function kept() {
            var k = storage('install.wish');
            var b = k && installed && k.app === installed.app ? C.fromBase64(k.key) : null;
            return b && b.length === 32 ? b : null;
          }
          // On a TV, opened by Lamp's install, the page asks for the key at once, while the claim is open; one kept from
          // before is used meanwhile, and the new one replaces it.
          if (installed && !bridge && !stranded) {
            key = kept();
            claim().then(function (fresh) { key = fresh; }, function () {});
          }

          function hear(m) {
            var i;
            if (m.t === 'welcome') {
              retry = 0; undeliveredSaid = {}; lampAway = false; relayIn = true; alone = false; reported = '';
              if (isName(m.peer)) mine = m.peer;
              setRoster(m.apps || []);
              relayPresent = {};
              var list = m.peers || [];
              for (i = 0; i < list.length; i++) present(list[i]);
              rebuild();
              reach();
            } else if (m.t === 'joined' && m.peer) {
              present(m.peer); rebuild(); reach();
            } else if (m.t === 'left') {
              // What was on its way through the room to or from it can't arrive now, even if it's still reached straight.
              delete relayPresent[m.peer]; dropRoutes(m.peer, 'r', 'The link was lost.'); rebuild();
            } else if (m.t === 'at' && isName(m.peer)) {
              remember(m.peer, m.addresses); lookAgain();
            } else if (m.t === 'apps') {
              // The wish gained an app or lost one: the others keep what's known of them.
              setRoster(m.apps || []);
            } else if (m.t === 'message' && typeof m.from === 'string' && m.data !== undefined) {
              emit('message', [m.from, m.data]);
            } else if (m.t === 'values' && isName(m.from)) {
              heardValues(m, m.from);
            } else if (m.t === 'pad' && isName(m.from) && m.m && typeof m.m === 'object') {
              heardPad(m.m, m.from);
            } else if (typeof m.t === 'string' && m.t.indexOf('file') === 0 && isName(m.from)) {
              fileText(routeTo(m.from, null), m);
            } else if (m.t === 'undelivered' && typeof m.to === 'string') {
              if (!undeliveredSaid[m.to]) { undeliveredSaid[m.to] = true; say('a message to "' + m.to + '" did not arrive: ' + (m.reason || 'it is not in the room') + '.'); }
            }
          }
          function present(p) {
            if (!p || !isName(p.peer)) return;
            relayPresent[p.peer] = { device: typeof p.device === 'string' ? p.device : '', since: typeof p.since === 'number' ? p.since : Date.now(),
                                     wire: typeof p.wire === 'number' ? p.wire : 1 };
            if (p.at instanceof Array && p.at.length) remember(p.peer, p.at);
          }
          // Seals a message (text, or a file's piece as bytes) with the next number this way and sends it.
          function seal(text) {
            var box = C.seal(sendKey, C.nonce(sent), typeof text === 'string' ? C.utf8(text) : text);
            sent++;
            socket.send(box.buffer);
          }
          function transcriptOf(tag, client, server, theirs, ours) {
            var c = C.utf8(client), s = C.utf8(server);
            return C.concat([tag, new Uint8Array([c.length]), c, new Uint8Array([s.length]), s, theirs, ours]);
          }
          // The relay proved it holds the wish's key: this page proves it does too, and both seal from here on.
          function answer(m) {
            var theirs = C.fromBase64(m.nonce), proof = C.fromBase64(m.proof);
            if (!hello || typeof m.peer !== 'string' || m.peer.length < 1 || m.peer.length > 32 || !theirs || theirs.length !== 16 || !proof) return false;
            var transcript = transcriptOf(hello.tag, mine, m.peer, hello.nonce, theirs);
            if (!C.same(proof, C.derive('lamp-wish server', key, transcript))) return false;
            hello = null;
            socket.send(JSON.stringify({ t: 'proof', proof: C.toBase64(C.derive('lamp-wish client', key, transcript)) }));
            sendKey = C.derive('lamp-wish c2s', key, transcript); openKey = C.derive('lamp-wish s2c', key, transcript);
            sent = 0; opened = 0;
            seal(JSON.stringify({ t: 'join', device: device, wire: WIRE }));
            return true;
          }
          // Before the handshake is done only its challenge is heard, in clear; after it, only sealed messages and beats.
          // Anything else was made up on the way, and lets the link go.
          function arrived(s, data) {
            if (typeof data === 'string') {
              var m; try { m = JSON.parse(data); } catch (e) { m = null; }
              if (m && m.t === 'beat') return;
              if (!sendKey && m && m.t === 'challenge' && answer(m)) return;
            } else if (openKey) {
              var plain = C.open(openKey, C.nonce(opened), new Uint8Array(data)), said = null;
              if (plain) opened++;
              // A file's piece, else a message.
              if (plain && plain[0] === 1) return piece(plain, null);
              if (plain) { try { said = JSON.parse(C.fromUtf8(plain)); } catch (e) {} }
              if (said && typeof said === 'object') return hear(said);
            }
            say('the link to the wish\'s other apps heard something that was not theirs, and started again.');
            socket = null; s.close(); lost(0);
          }
          function connect() {
            if (!started || socket) return;
            var s;
            try { s = opener(address); } catch (e) { return lost(0); }
            s.binaryType = 'arraybuffer';
            socket = s;
            sendKey = openKey = null;
            heard = Date.now();
            s.onopen = function () {
              hello = { nonce: C.random(16), tag: C.derive('lamp-wish tag', key).subarray(0, 8) };
              s.send(JSON.stringify({ t: 'hello', tag: C.toBase64(hello.tag), peer: mine, nonce: C.toBase64(hello.nonce) }));
            };
            s.onmessage = function (event) {
              if (socket !== s) return;
              heard = Date.now();
              arrived(s, event.data);
            };
            s.onclose = function (event) { if (socket === s) lost(event.code); };
          }
          // Turned away, or the room ended, or dropped before it was let in: Lamp is asked again where to join and who this
          // page is; dropped otherwise, the page comes back after a moment.
          function lost(code) {
            var wasIn = relayIn;
            socket = null; hello = null; sendKey = openKey = null; relayIn = false; relayPresent = {};
            dropRoutes(null, 'r', 'The link was lost.');
            rebuild();
            if (!started) return;
            if (code === 4003 || code === 4005 || !wasIn || retry >= 3) address = null;
            retry = Math.min(retry + 1, 6);
            clearTimeout(again);
            again = setTimeout(open, retry * 750);
          }
          function open() {
            if (!started || socket) return;
            if (!key && !bridge) {
              if (!installed) { setState('away', 'This copy wasn\'t opened from Lamp, so it can\'t reach the wish\'s other apps. Open it from Lamp on your Mac.'); return; }
              // Tried again while the page is open, less often each time, since the claim stays open for a while after
              // Lamp put the app here and the network may just have been down.
              claim().then(function (fresh) { key = fresh; claims = 0; open(); }, function (error) {
                if (!started) return;
                setState('away', error.message);
                claims = Math.min(claims + 1, 5);
                clearTimeout(askTimer);
                askTimer = setTimeout(open, 2000 * Math.pow(2, claims));
              });
              return;
            }
            restore();
            reach();
            if (address && key) return connect();
            clearTimeout(askTimer);
            LampAI._post('/app/wish', { device: device }, 20000).then(function (answer) {
              if (!started) return;
              if (answer.alone) {
                // The wish has no other app: nothing to join, until one is added.
                if (answer.me && isName(answer.me.peer)) { mine = answer.me.peer; setRoster([answer.me]); }
                alone = true; lampAway = false; rebuild();
                askTimer = setTimeout(open, (answer.renew || 300) * 1000);
                return;
              }
              if (bridge && answer.key) { key = C.fromBase64(answer.key); restore(); }
              if (!answer.socket || !answer.peer || !key || key.length !== 32) throw new Error(answer.error || 'Lamp did not say where the wish\'s apps meet.');
              address = answer.socket; mine = answer.peer; alone = false;
              setRoster(answer.apps || []);
              rebuild();
              connect();
            }, function (error) {
              if (!started) return;
              // Lamp isn't there (closed, restarting, or the Mac asleep): the apps go on the straight way meanwhile, and
              // Lamp is asked again after a while. Said once each time Lamp goes.
              if (!lampAway) say(error.message);
              lampAway = true;
              rebuild();
              askTimer = setTimeout(open, 3000);
            });
          }

          // Straight to an app of the wish that listens: the same handshake as Lamp's room, that app taking the relay's
          // side and naming itself, so only an app holding the wish's key answers it, and only the one it was dialled as.
          // `failed` is called if it never gets ready, `settled` once it's over either way.
          function attempt(id, place, failed, settled) {
            var ws, d, timer, mine_ = epoch;
            if (!started) return;
            try { ws = opener('ws://' + place + '/'); } catch (e) { return failed(); }
            ws.binaryType = 'arraybuffer';
            d = { ws: ws, peer: id, place: place, ready: false, over: false, hello: null, sendKey: null, openKey: null, sent: 0, opened: 0, heard: Date.now(), device: '', settled: settled || null,
                  way: 'd' + (++links_) };
            function end() {
              if (d.over) return;
              d.over = true;
              dropRoutes(null, d.way, 'The link was lost.');
              clearTimeout(timer);
              try { ws.close(); } catch (e) {}
              var at = pending.indexOf(d);
              if (at >= 0) pending.splice(at, 1);
              if (directs[id] === d) { delete directs[id]; rebuild(); }
              // A try that stop() ended goes no further: nothing dials or sweeps on after it.
              else if (!d.ready && mine_ === epoch && started) failed();
            }
            d.end = end;
            pending.push(d);
            timer = setTimeout(function () { if (!d.ready) end(); }, 4000);
            ws.onopen = function () {
              d.hello = { nonce: C.random(16), tag: C.derive('lamp-wish tag', key).subarray(0, 8) };
              ws.send(JSON.stringify({ t: 'hello', tag: C.toBase64(d.hello.tag), peer: mine, nonce: C.toBase64(d.hello.nonce) }));
            };
            ws.onmessage = function (event) { if (!d.over) { d.heard = Date.now(); directArrived(d, event.data); } };
            ws.onclose = ws.onerror = end;
            return d;
          }
          function directArrived(d, data) {
            if (typeof data === 'string') {
              var m; try { m = JSON.parse(data); } catch (e) { m = null; }
              if (m && m.t === 'beat') return;
              var theirs = m && C.fromBase64(m.nonce), proof = m && C.fromBase64(m.proof);
              if (m && m.t === 'challenge' && d.hello && !d.sendKey && m.peer === d.peer && theirs && theirs.length === 16 && proof) {
                var transcript = transcriptOf(d.hello.tag, mine, d.peer, d.hello.nonce, theirs);
                if (C.same(proof, C.derive('lamp-wish server', key, transcript))) {
                  d.hello = null;
                  d.ws.send(JSON.stringify({ t: 'proof', proof: C.toBase64(C.derive('lamp-wish client', key, transcript)) }));
                  d.sendKey = C.derive('lamp-wish c2s', key, transcript); d.openKey = C.derive('lamp-wish s2c', key, transcript);
                  directSeal(d, JSON.stringify({ t: 'join', device: device, wire: WIRE }));
                  return;
                }
              }
            } else if (d.openKey) {
              var plain = C.open(d.openKey, C.nonce(d.opened), new Uint8Array(data)), said = null;
              if (plain) d.opened++;
              if (plain && plain[0] === 1 && d.ready) return piece(plain, d);
              if (plain) { try { said = JSON.parse(C.fromUtf8(plain)); } catch (e) {} }
              if (said && said.t === 'welcome' && !d.ready) return ready(d, said);
              if (said && said.t === 'message' && d.ready && said.data !== undefined) return emit('message', [d.peer, said.data]);
              if (said && said.t === 'values' && d.ready) return heardValues(said, d.peer);
              if (said && said.t === 'pad' && d.ready && said.m && typeof said.m === 'object') return heardPad(said.m, d.peer);
              if (said && typeof said.t === 'string' && said.t.indexOf('file') === 0 && d.ready) return fileText(routeTo(d.peer, d), said);
              if (said && typeof said === 'object') return;
            }
            d.end();
          }
          function directSeal(d, text) {
            var box = C.seal(d.sendKey, C.nonce(d.sent), typeof text === 'string' ? C.utf8(text) : text);
            d.sent++;
            d.ws.send(box.buffer);
          }

          // A route to another app on one way (d: a link straight to it; null: Lamp's room), as the files' code takes it:
          // its messages go sealed on that way, and its pieces as the wish's apps write them (1, a peer's name with its
          // length before it, none straight, the transfer's id, the bytes), not the controllers' 8-byte header.
          function routeTo(peer, d) {
            var way = d ? d.way : 'r', k = 'w-' + peer + '-' + way;
            if (routes[k]) return routes[k];
            function up() { return d ? !d.over && directs[peer] === d && d.ready : relayIn && !!socket && socket.readyState === 1 && !!sendKey && !!relayPresent[peer]; }
            var route = routes[k] = {
              key: k, place: 0, peer: peer, way: way,
              text: function (m) {
                if (!up()) return false;
                if (d) directSeal(d, JSON.stringify(m));
                else { m.to = peer; seal(JSON.stringify(m)); }
                return true;
              },
              binary: function (buffer) {
                if (!up()) return false;
                var v = new Uint8Array(buffer), n = d ? new Uint8Array(0) : C.utf8(peer), out = new Uint8Array(2 + n.length + v.length - 4);
                out[0] = 1; out[1] = n.length; out.set(n, 2); out.set(v.subarray(4), 2 + n.length);
                if (d) directSeal(d, out); else seal(out);
                return true;
              },
              buffered: function () { return d ? d.ws.bufferedAmount : socket ? socket.bufferedAmount : 0; }
            };
            return route;
          }
          // The files of one app (null: every app) on one way (null: every way) end, with why.
          function dropRoutes(peer, way, reason) {
            for (var k in routes) {
              var r = routes[k];
              if ((peer === null || r.peer === peer) && (way === null || r.way === way)) { files.drop(r, reason); delete routes[k]; }
            }
          }
          // A file's message from another app: what a coming one is for is kept while the files' code takes it.
          function fileText(route, m) {
            coming = typeof m.ch === 'string' ? m.ch : '';
            try { files.text(route, m); } finally { coming = ''; }
          }
          // A file's piece, as the files' code reads one: with the controllers' 8-byte header.
          function piece(plain, d) {
            var n = plain[1], at = 2 + n;
            if (plain.length <= at + 4 || n > 32) return;
            var peer = d ? d.peer : C.fromUtf8(plain.subarray(2, at));
            if (!isName(peer)) return;
            var view = new Uint8Array(4 + plain.length - at);
            view[0] = 1;
            view.set(plain.subarray(at), 4);
            files.binary(routeTo(peer, d), view);
          }
          // A file to another app open now, the straight way when there is one, else through Lamp's room.
          function sendFile(peer, data, info, ch) {
            var p = find(peer), d = directs[peer] && directs[peer].ready ? directs[peer] : null, why = null;
            if (!p) why = 'the wish has no app called "' + peer + '".';
            else if (!p.open || state !== 'connected') why = p.status.reason || p.name + ' is not open now.';
            else if (wireOf(peer) < 3) why = outOfDate(p.name, true);
            else if (!d && !(relayIn && relayPresent[peer] && socket && socket.readyState === 1 && sendKey)) why = p.name + ' is not reachable now.';
            if (why) {
              say('a file was not sent: ' + why);
              var none = { name: String((info && info.name) || 'file'), size: 0, sent: 0, onProgress: function () {}, cancel: function () {}, done: Promise.reject(new Error(why)) };
              none.done.catch(function () {});
              return none;
            }
            var base = routeTo(peer, d), route = base;
            if (ch) route = { key: base.key, place: 0, peer: peer, way: base.way, binary: base.binary, buffered: base.buffered,
                              text: function (m) { if (m.t === 'file') m.ch = ch; return base.text(m); } };
            return files.send(route, data, info);
          }

          // A game's controls between a wish's app (LampController) and this app's Lamp.controllers.
          function sendPad(peer, m) {
            var d = directs[peer] && directs[peer].ready ? directs[peer] : null;
            if (wireOf(peer) < 3) return false;
            if (d) { directSeal(d, JSON.stringify({ t: 'pad', m: m })); return true; }
            if (relayIn && relayPresent[peer] && socket && socket.readyState === 1 && sendKey) { seal(JSON.stringify({ t: 'pad', m: m, to: peer })); return true; }
            return false;
          }
          function heardPad(m, peer) {
            if (!padHooks) return;
            var id = typeof m.pad === 'string' ? m.pad : '', key = padKey(peer, id);
            if (m.t === 'join') {
              // Asked again (a controller that missed its welcome): it's told again, with the number it has.
              padPlayers[key] = { peer: peer, pad: id };
              var n = padHooks.join(key, {
                key: key, place: 0,
                text: function (out) { if (id) out.pad = id; return sendPad(peer, out); },
                say: function (data) { var out = { t: 'message', data: data }; if (id) out.pad = id; return sendPad(peer, out); },
                sendFile: function (data, info) { return sendFile(peer, data, info, id ? 'pad:' + id : 'pad'); }
              }, typeof m.now === 'number' ? m.now - Date.now() : null);
              var welcome = { t: 'welcome' }, number = { t: 'player', number: n };
              if (id) { welcome.pad = id; number.pad = id; }
              sendPad(peer, welcome);
              sendPad(peer, number);
            } else if (!padPlayers[key]) {
              return;
            } else if (m.t === 'leave') {
              delete padPlayers[key];
              padHooks.leave(key);
            } else if (m.t === 'too-big') {
              padHooks.tooBig(key, m.bytes);
            } else if (m.t === 'button' || m.t === 'axis' || m.t === 'message') {
              padHooks.input(key, m);
            }
          }
          // Lamp.controllers taking players, or no longer: the wish's open apps are told, and those that play join.
          var padSource = {
            start: function (h) {
              padHooks = h;
              api.start();
              for (var i = 0; i < apps.length; i++) if (apps[i].open) sendPad(apps[i].peer, { t: 'host' });
            },
            stop: function () {
              var told = {};
              for (var k in padPlayers) if (!told[padPlayers[k].peer]) { told[padPlayers[k].peer] = true; sendPad(padPlayers[k].peer, { t: 'state', host: false }); }
              padPlayers = {};
              padHooks = null;
            }
          };
          function ready(d, welcome) {
            var at = pending.indexOf(d);
            if (at >= 0) pending.splice(at, 1);
            if (!started) { d.ready = true; return d.end(); }
            var had = directs[d.peer], settled = d.settled;
            d.settled = null;
            if (settled) settled();
            if (had && had !== d && had.ready) { d.ready = true; d.over = true; try { d.ws.close(); } catch (e) {} return; }
            d.ready = true;
            d.device = typeof welcome.device === 'string' ? welcome.device.slice(0, 40) : '';
            d.wire = typeof welcome.wire === 'number' ? welcome.wire : 1;
            directs[d.peer] = d;
            delete dialing[d.peer]; delete nextDial[d.peer];
            if (/^[0-9.]+:\d+$/.test(d.place)) remember(d.peer, [d.place]);
            rebuild();
          }
          function drop(d) { d.end(); }

          // Each place in turn, the last reached first; then, once in a while, every address on this network at the
          // wish's port for that app, a few dozen at a time; then again later, less often each time.
          function dial(id, places) {
            if (!places.length) {
              delete dialing[id];
              var tries = (nextDial[id] ? nextDial[id].tries : 0) + 1;
              nextDial[id] = { at: Date.now() + Math.min(30, Math.pow(2, tries)) * 1000 * (0.8 + Math.random() * 0.4), tries: tries };
              return;
            }
            dialing[id] = true;
            attempt(id, places[0], function () { dial(id, places.slice(1)); });
          }
          function placeOk(p) {
            var m = /^([A-Za-z0-9.-]{1,253}):(\d{1,5})$/.exec(p);
            return !!m && +m[2] > 0 && +m[2] < 65536 && (bridge || m[1].indexOf('127.') !== 0);
          }
          function port(id) {
            var ids = [], i;
            for (i = 0; i < roster.length; i++) ids.push(roster[i].peer);
            ids.sort();
            var rank = ids.indexOf(id), d = C.derive('lamp-wish port', key);
            return rank >= 0 && rank < 8 ? 20000 + ((d[0] << 8) | d[1]) % 1500 * 8 + rank : null;
          }
          function sweep(missing) {
            var nets = {}, list = [], id, i, h;
            if (here) nets[here.replace(/\.\d+$/, '')] = true;
            for (id in told) for (i = 0; i < told[id].length; i++) {
              var m = /^(\d+\.\d+\.\d+)\.\d+:\d+$/.exec(told[id][i]);
              if (m && m[1].indexOf('127.') !== 0) nets[m[1]] = true;
            }
            for (var net in nets) for (i = 0; i < missing.length; i++) {
              var p = port(missing[i]);
              if (p) for (h = 1; h < 255; h++) list.push({ id: missing[i], place: net + '.' + h + ':' + p });
            }
            if (!list.length) return;
            swept = Date.now();
            var at = 0, running = 0;
            for (i = 0; i < missing.length; i++) dialing[missing[i]] = true;
            function next() {
              while (running < 32 && at < list.length) {
                var one = list[at++];
                if (directs[one.id]) continue;
                running++;
                var done = function () { running--; next(); };
                attempt(one.id, one.place, done, done);
              }
              if (!running && at >= list.length) for (var j = 0; j < missing.length; j++) if (!directs[missing[j]]) dial(missing[j], []);
            }
            next();
          }
          // This TV's own address, where its system says it: the network to look on when nothing was remembered.
          function whereAmI() {
            if (pipe) { try { pipe.postMessage({ lamp: 'ws', op: 'here' }); } catch (e) {} return; }
            try {
              if (window.tizen && tizen.systeminfo) {
                ['WIFI_NETWORK', 'ETHERNET_NETWORK'].forEach(function (kind) {
                  tizen.systeminfo.getPropertyValue(kind, function (n) { if (n && /^\d+\.\d+\.\d+\.\d+$/.test(n.ipAddress)) here = n.ipAddress; }, function () {});
                });
              } else if (window.webOS && webOS.service) {
                webOS.service.request('luna://com.palm.connectionmanager', { method: 'getStatus', parameters: {}, onSuccess: function (r) {
                  var a = r && ((r.wired && r.wired.ipAddress) || (r.wifi && r.wifi.ipAddress));
                  if (a && /^\d+\.\d+\.\d+\.\d+$/.test(a)) here = a;
                } });
              }
            } catch (e) {}
          }
          function reach() {
            if (!started || alone || !key || !mine || roster.length < 2) return;
            var now = Date.now(), missing = [];
            for (var i = 0; i < roster.length; i++) {
              var id = roster[i].peer;
              if (id === mine || directs[id] || dialing[id]) continue;
              if (nextDial[id] && nextDial[id].at > now) continue;
              var places = (told[id] || []).filter(placeOk);
              // Where it was reached or said it listens, always; and once that has failed twice, the network as well.
              if (!relayPresent[id] && (!places.length || (nextDial[id] && nextDial[id].tries >= 2))) missing.push(id);
              if (places.length) dial(id, places);
            }
            // A sweep only for apps Lamp's room doesn't have either, and not more than once a minute.
            if (missing.length && now - swept > 60000) sweep(missing);
          }
          function lookAgain() { nextDial = {}; reach(); }

          // A beat on every link, in clear since it carries nothing: whoever hears nothing for a while lets the other go.
          function beat() {
            if (socket && socket.readyState === 1) {
              if (Date.now() - heard > 15000) { var s = socket; socket = null; s.close(); lost(0); }
              else socket.send('{"t":"beat"}');
            }
            for (var id in directs) {
              var d = directs[id];
              if (Date.now() - d.heard > 15000) d.end();
              else try { d.ws.send('{"t":"beat"}'); } catch (e) { d.end(); }
            }
            // When each open app was last seen is kept every minute, so it's known even when this page is closed while
            // the other is open; and the reasons are worked out again, since they say how long ago.
            var now = Date.now();
            for (var i = 0; i < apps.length; i++) if (apps[i].open) lastSeen[apps[i].peer] = now;
            beats++;
            if (beats % 12 === 0 && openOnes().length) keep();
            // Once a minute each open app is told what this page's values add up to, so one that missed a setting asks.
            if (beats % 12 === 0) for (var j = 0; j < apps.length; j++) if (apps[j].open && wireOf(apps[j].peer) >= 2) share({}, apps[j].peer, { sum: digest() });
            // A page without the wish's key keeps saying why (open, claim) rather than "Connecting…".
            if (key) rebuild();
            reach();
          }
          function adder(name) {
            return function (fn) {
              on[name].push(fn);
              api.start();
              if (name === 'peers') fn(openOnes());
              if (name === 'apps') fn(allOnes());
              if (name === 'state') fn(state, status());
              return function () { var i = on[name].indexOf(fn); if (i >= 0) on[name].splice(i, 1); };
            };
          }
          if (window.addEventListener) window.addEventListener('online', function () { lookAgain(); });

          var api = {
            start: function () {
              if (started) return;
              started = true;
              whereAmI();
              open();
              beatTimer = setInterval(beat, 5000);
            },
            stop: function () {
              started = false;
              clearTimeout(askTimer); clearTimeout(again); clearInterval(beatTimer);
              if (socket) { var s = socket; socket = null; s.close(); }
              sendKey = openKey = null; relayIn = false; relayPresent = {};
              epoch++;
              dropRoutes(null, null, 'The link was stopped.');
              for (var id in directs) directs[id].end();
              while (pending.length) pending[0].end();
              dialing = {}; nextDial = {};
              rebuild();
              setState('ended');
            },
            peers: function () { api.start(); return openOnes(); },
            apps: function () { api.start(); return allOnes(); },
            peer: function (id) { api.start(); var p = find(id); return p ? copy(p) : null; },
            me: function () { api.start(); return mine; },
            state: function () { api.start(); return state; },
            status: function () { api.start(); return status(); },
            messageLimit: MESSAGE, valueLimit: VALUE, valuesLimit: VALUES,
            values: function () { api.start(); return JSON.parse(JSON.stringify(valuesNow())); },
            set: function (key, value) {
              api.start();
              var what = 'the value "' + key + '"', text = null;
              if (!nameOk(key)) { say(what + ' was not set: a value\'s name is 1 to 64 bytes, and not __proto__.'); return false; }
              dropExpired();
              if (value !== null && value !== undefined) {
                try { text = JSON.stringify(value); } catch (e) { text = undefined; }
                if (text === undefined) { say(what + ' was not set: it holds nothing JSON can.'); return false; }
                var b = bytes(text);
                if (b > VALUE) { say(what + ' of ' + b + ' bytes was not set: a value is at most ' + VALUE + ' bytes as JSON.'); return false; }
                if (sizeWithout(key) + bytes(key) + Math.max(32, b) > VALUES) { say(what + ' was not set: the wish\'s values would pass ' + VALUES + ' bytes (each name counts 32 bytes at least, and a removed one for a month). Keep to fewer names, and reuse them.'); return false; }
              }
              // Kept as it reads back from JSON, so this page sees what the others will (NaN reads back as null, and
              // so removes it, as it does everywhere).
              var v = text === null ? undefined : JSON.parse(text), now = Date.now();
              if (v === null) v = undefined;
              clock = now > clock[0] ? [now, 0] : clock[1] < COUNTS ? [clock[0], clock[1] + 1] : [clock[0] + 1, 0];
              var one = {};
              entries[key] = one[key] = { v: v, c: [clock[0], clock[1], mine] };
              valuesChanged([[key, v]], mine);
              for (var i = 0; i < apps.length; i++) if (apps[i].open && wireOf(apps[i].peer) >= 2) share(one, apps[i].peer);
              return true;
            },
            statusView: function (only) {
              // The same element each time it's asked for the same line, so a page drawn again doesn't pile them up.
              for (var i = 0; i < views.length; i++) if (views[i].only === (only || null)) return views[i].el;
              var el = document.createElement('div');
              el.className = 'lamp-wish-status';
              views.push({ el: el, only: only || null });
              api.start();
              draw(true);
              return el;
            },
            send: function (data, to) {
              api.start();
              var what = to ? 'a message to "' + to + '"' : 'a message to the wish\'s apps';
              if (state !== 'connected') {
                if (!away) { away = true; say(what + ' was not sent: not connected (' + state + '). Check state() and peers() before sending.'); }
                return false;
              }
              if (to) { var p = find(to); if (!p || !p.open) { say(what + ' was not sent: that app is not open now.'); return false; } }
              var frame = { t: 'send', data: data };
              if (to) frame.to = to;
              var text = JSON.stringify(frame);
              if (data === undefined || text === undefined) { say(what + ' was not sent: it holds nothing JSON can.'); return false; }
              var targets = to ? [to] : openOnes().map(function (o) { return o.peer; }), viaRoom = [], longest = '';
              for (var t = 0; t < targets.length; t++) if (bytes(targets[t]) > bytes(longest)) longest = targets[t];
              // Measured as it goes through Lamp's room to each app, with that app's name: the longest, when it's for all of them.
              var measured = bytes(JSON.stringify({ t: 'send', data: data, to: longest }));
              if (measured > MESSAGE) { say(what + ' of ' + measured + ' bytes was not sent: a message between the wish\'s apps is at most ' + MESSAGE + ' bytes as JSON.'); return false; }
              // Each app the straight way when there is one, else through Lamp's room.
              for (var i = 0; i < targets.length; i++) {
                var d = directs[targets[i]];
                if (d && d.ready) directSeal(d, JSON.stringify({ t: 'message', data: data }));
                else if (relayPresent[targets[i]]) viaRoom.push(targets[i]);
              }
              if (viaRoom.length && socket && socket.readyState === 1 && sendKey) {
                // To all of them in one when every app goes through the room, as it always did.
                if (!to && viaRoom.length === targets.length) seal(text);
                else for (var k = 0; k < viaRoom.length; k++) seal(JSON.stringify({ t: 'send', data: data, to: viaRoom[k] }));
              }
              return true;
            },
            sendFile: function (data, to, info) { api.start(); return sendFile(to, data, info, ''); },
            onMessage: adder('message'), onPeers: adder('peers'), onApps: adder('apps'), onState: adder('state'), onChange: adder('change'),
            onFile: adder('file')
          };

          // The app around the page is the peer: what it says of the wish comes to `window.__lampWish`, and what the page
          // does goes to it. Kept here as the page's own state is everywhere else, so everything that reads it (peers,
          // apps, values, the status views) is the same code.
          function hosted() {
            var transfers = {}, nextTransfer = 0, filesAsked = false;
            function post(m) { try { host.postMessage(m); } catch (e) { say(String(e)); } }
            function toBase64(b) {
              var s = '';
              for (var i = 0; i < b.length; i += 32768) s += String.fromCharCode.apply(null, b.subarray(i, i + 32768));
              return btoa(s);
            }
            function fromBase64(t) {
              var s = atob(t), b = new Uint8Array(s.length);
              for (var i = 0; i < s.length; i++) b[i] = s.charCodeAt(i);
              return b;
            }
            function bytesOf(data) {
              if (typeof data === 'string') return Promise.resolve(new TextEncoder().encode(data));
              if (data instanceof ArrayBuffer) return Promise.resolve(new Uint8Array(data));
              if (ArrayBuffer.isView(data)) return Promise.resolve(new Uint8Array(data.buffer, data.byteOffset, data.byteLength));
              if (typeof Blob !== 'undefined' && data instanceof Blob) return data.arrayBuffer().then(function (a) { return new Uint8Array(a); });
              return Promise.reject(new Error('a file is a File, a Blob, an ArrayBuffer, bytes or text.'));
            }
            window.__lampWish = function (m) {
              if (!m || typeof m !== 'object') return;
              if (m.t === 'state') {
                if (typeof m.me === 'string') mine = m.me;
                apps = m.apps instanceof Array ? m.apps : [];
                if (m.status && (m.status.state !== state || m.status.reason !== reason)) setState(m.status.state, m.status.reason);
                var said = JSON.stringify(openOnes());
                if (said !== lastOpen) { lastOpen = said; emit('peers', [openOnes()]); }
                var every = JSON.stringify(apps);
                if (every !== lastApps) { lastApps = every; emit('apps', [allOnes()]); }
                draw();
              } else if (m.t === 'values') {
                // Every value the app has that differs from the page's copy is said to onChange: those it kept on the
                // device come in its first snapshot, and a page opened again finds them there, as values kept on a TV
                // are said once the page knows its wish. A change the page made is said as it's made, so it differs
                // from nothing when the app's copy of it comes back.
                var given = m.values && typeof m.values === 'object' ? m.values : {}, by = {}, said = [], k;
                var changed = m.changed instanceof Array ? m.changed : [];
                for (var i = 0; i < changed.length; i++) if (changed[i] && typeof changed[i].key === 'string') by[changed[i].key] = changed[i].from;
                for (k in entries) if (!own(given, k)) { if (entries[k].v !== undefined) said.push([k, undefined]); delete entries[k]; }
                for (k in given) if (own(given, k) && !(entries[k] && JSON.stringify(entries[k].v) === JSON.stringify(given[k]))) {
                  entries[k] = { v: given[k], c: [0, 0, ''] };
                  said.push([k, given[k]]);
                }
                for (var j = 0; j < said.length; j++) emit('change', [said[j][0], copyOf(said[j][1]), own(by, said[j][0]) ? by[said[j][0]] : mine]);
              } else if (m.t === 'message') {
                emit('message', [m.from, m.data]);
              } else if (m.t === 'file') {
                var data = fromBase64(m.data || ''), size = data.length;
                var file = { name: m.name, type: m.type, size: size, onProgress: function (fn) { try { fn(size, size); } catch (e) {} },
                             cancel: function () {}, done: Promise.resolve(data.buffer) };
                emit('file', [m.from, file]);
              } else if (m.t === 'transfer' && transfers[m.id]) {
                var t = transfers[m.id];
                t.sent = m.sent;
                for (var j = 0; j < t.watchers.length; j++) { try { t.watchers[j](t.sent, t.size); } catch (e) {} }
                if (m.state === 'done') { delete transfers[m.id]; t.resolve(); }
                else if (m.state === 'failed') { delete transfers[m.id]; t.reject(new Error(m.error || 'The file did not get there.')); }
              }
            };
            api.start = function () {
              if (started) return;
              started = true;
              post({ op: 'start' });
            };
            api.stop = function () {
              if (!started) return;
              started = false;
              post({ op: 'stop' });
            };
            var plainSet = api.set;
            api.set = function (key, value) {
              // Weighed and kept here as everywhere, so values() reads it back at once, then set in the app.
              if (!plainSet(key, value)) return false;
              post({ op: 'set', key: key, value: JSON.stringify(entries[key].v === undefined ? null : entries[key].v) });
              return true;
            };
            api.send = function (data, to) {
              api.start();
              var what = to ? 'a message to "' + to + '"' : 'a message to the wish\'s apps';
              if (state !== 'connected') {
                if (!away) { away = true; say(what + ' was not sent: not connected (' + state + '). Check state() and peers() before sending.'); }
                return false;
              }
              if (to) { var p = find(to); if (!p || !p.open) { say(what + ' was not sent: that app is not open now.'); return false; } }
              var text = data === undefined ? undefined : JSON.stringify(data);
              if (text === undefined) { say(what + ' was not sent: it holds nothing JSON can.'); return false; }
              var measured = bytes(JSON.stringify({ t: 'send', data: data, to: to || '' })) + 32;
              if (measured > MESSAGE) { say(what + ' of ' + measured + ' bytes was not sent: a message between the wish\'s apps is at most ' + MESSAGE + ' bytes as JSON.'); return false; }
              post({ op: 'send', data: text, to: to || null });
              return true;
            };
            api.sendFile = function (data, to, info) {
              api.start();
              var id = ++nextTransfer, name = String((info && info.name) || (data && data.name) || 'file');
              var type = String((info && info.type) || (data && data.type) || 'application/octet-stream');
              var t = { watchers: [], sent: 0, size: 0, posted: false, over: false };
              // Cancelled while its bytes are still being read, it never starts; once it has, the app cancels it.
              var transfer = { name: name, size: 0, sent: 0, onProgress: function (fn) { t.watchers.push(fn); },
                               cancel: function () {
                                 if (t.over) return;
                                 if (t.posted) return post({ op: 'cancel', id: id });
                                 t.over = true;
                                 t.reject(new Error('The file was cancelled.'));
                               } };
              transfer.done = new Promise(function (resolve, reject) { t.resolve = resolve; t.reject = reject; });
              transfer.done.catch(function () {});
              transfer.done.then(function () { t.over = true; }, function () { t.over = true; });
              t.watchers.push(function (sent) { transfer.sent = sent; });
              bytesOf(data).then(function (b) {
                if (t.over) return;
                t.posted = true;
                t.size = transfer.size = b.length;
                transfers[id] = t;
                post({ op: 'sendFile', id: id, to: to, name: name, type: type, data: toBase64(b) });
              }, function (error) { say('a file was not sent: ' + error.message); t.reject(error); });
              return transfer;
            };
            var plainOnFile = api.onFile;
            api.onFile = function (fn) {
              // Files come once the page listens for them, as an app with no onFile turns them down.
              if (!filesAsked) { filesAsked = true; post({ op: 'files' }); }
              return plainOnFile(fn);
            };
          }
          if (host) hosted();
          else if (stranded) {
            var standStill = function () { started = true; setState('away', STRANDED); };
            api.start = function () { if (!started) standStill(); };
            api.stop = function () { started = false; setState('ended'); };
          }
          if (window.Lamp) window.Lamp.wish = api;
          if (!host && window.Lamp && window.Lamp.controllers && window.Lamp.controllers._attach) window.Lamp.controllers._attach(padSource);
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
    static func tvPrompt(skills: [String: Skills.Skill] = Skills.all, part: String? = nil, alone: Bool = false) -> String {
        let rules = part == nil
            ? [Rules.tvEdit, Rules.ask, Rules.shell, Rules.tvFrameworks, Rules.tvDesign, Rules.tvKeys, Rules.tvData, Rules.tvPhone, Rules.webAI, Rules.webSound,
               Rules.icon, Rules.about, Rules.tvAttachments, Rules.tvLogs, Rules.tvTry, Rules.appMd, Rules.audience,
               Skills.index(Skills.offered(.tv), from: skills), Rules.begin, Rules.finish]
            : [Rules.tvEdit, Rules.tvFrameworks, Rules.tvDesign, Rules.tvKeys, Rules.tvData, Rules.tvPhone, Rules.webAI, Rules.webSound, Rules.tvLogs, Rules.tvTry,
               alone ? "" : Rules.tvParts, Skills.index(Skills.offered(.tv), from: skills)]
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
    - Phones can steer the app (controllers, a buzzer, a remote) or be its second screen in more than one way; choose \
    what fits. A page in Phone/ is opened by any phone in its browser, with nothing to install; Lamp serves it while \
    the app runs, so never start a server or anything that keeps running for it. Open the phone-controllers skill \
    first for one. Apps of the wish's own on the iPhone or Android (`make_app_for`) suit what a page does poorly, such as the \
    phone's hardware or data the phone keeps.
    """

    /// For a TV app with another app beside it in the same wish (`Parts`): how they talk (`wishTalk`), and how an iPhone
    /// or Mac app steers the TV app's game as a player of `Lamp.controllers`.
    static let tvParts = String(wishTalk.dropFirst()) + """
    - When the wish's iPhone or Mac app steers the TV app as a player (`LampController`, one way to, suited to a \
    game's controls), it joins the TV app the way a phone's page does, as a player of `Lamp.controllers`, beside \
    `Lamp.wish` for everything else: its buttons, sticks \
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
