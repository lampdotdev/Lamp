import AppKit
import LampRelayKit
import WebKit

/// A game's own phone page in Lamp's hidden preview, so the agent can see it and press it: the files of `Phone/` and
/// Lamp's real lamp-controller.js in a web view no one sees, sideways at a phone's size unless a play turns it upright.
/// Its link to the game is a stand-in for the relay's socket: what the page sends waits here until the game's play
/// reaches the next step and takes it (`WebGamePreview`, lamp-game.js's `phoneStep`), and the game's `Lamp.controllers`
/// hears it as it hears any player, so a play with a phone stays one script played from the start. The page's timers and
/// clocks go by the game's frames (`step`'s `elapsed`), since a play runs far faster than the time it stands for, so a long
/// press or a countdown there lasts what the script says; a CSS animation runs by real time. Nothing here is a
/// network: the page is held to its own files, and no relay, link or credential is involved, so the join itself and
/// everything a real phone's browser does (rotation lock, notches, the keyboard, tilt) is still only a real phone's to show.
@MainActor
final class PhonePreview: NSObject, WKNavigationDelegate {
    nonisolated static let wide = NSSize(width: 844, height: 390)
    /// Stands in for a phone's Safari, for a page that asks what it's on.
    private static let agent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    private var webView: WKWebView?
    private let files = StagedFiles()
    private var loaded: CheckedContinuation<Bool, Never>?

    /// Opens the page in `folder` and waits for it; false when it didn't load.
    func open(_ folder: URL) async -> Bool {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.inactiveSchedulingPolicy = .none
        // A preview on this Mac is on this Mac's network, which a page held to nothing can't reach.
        files.folder = folder
        files.own = "lamp-phone://app"
        files.policy = NetworkPolicy()
        NetworkPolicy.holdBack(configuration.preferences)
        configuration.setURLSchemeHandler(files, forURLScheme: "lamp-phone")
        configuration.userContentController.addUserScript(WKUserScript(source: Self.script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let view = WKWebView(frame: NSRect(origin: .zero, size: Self.wide), configuration: configuration)
        view.customUserAgent = Self.agent
        view.navigationDelegate = self
        webView = view
        // The address's hash is what lamp-controller.js takes for the join link's credential.
        view.load(URLRequest(url: URL(string: "lamp-phone://app/index.html#preview")!))
        let timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            self?.finish(false)
        }
        let ready = await withCheckedContinuation { loaded = $0 }
        timeout.cancel()
        return ready
    }

    func close() {
        webView?.stopLoading()
        webView = nil
    }

    private func finish(_ ready: Bool) {
        loaded?.resume(returning: ready)
        loaded = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(true) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(false) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(false) }

    /// The page never leaves its own address.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url, !NetworkPolicy().allowsFrame(url, own: files.own) else { return decisionHandler(.allow) }
        decisionHandler(.cancel)
    }

    /// One step of a play: the game's messages go in (`inbox`, JSON), the action happens on the page, and what the page
    /// sent comes back as JSON. `hosted`: whether the game has started its controllers. `elapsed`: the milliseconds of play
    /// since the last step, which pass on the page's clock before anything else happens.
    func step(_ action: [String: Any], inbox: String, hosted: Bool, elapsed: Double = 0) async -> String {
        guard let webView else { return "{}" }
        if action["do"] as? String == "rotate", let turn = Self.turn(action["direction"] as? String) {
            webView.setFrameSize(turn.size)
            return await call("return await __lampPhone.step({ do: 'rotate', angle: a }, b, c, d)", ["a": turn.angle, "b": inbox, "c": hosted, "d": elapsed]) ?? "{}"
        }
        return await call("return await __lampPhone.step(a, b, c, d)", ["a": action, "b": inbox, "c": hosted, "d": elapsed]) ?? "{}"
    }

    /// The size the phone is held at and the angle a browser would say.
    nonisolated static func turn(_ direction: String?) -> (size: NSSize, angle: Int)? {
        switch direction {
        case "up": (NSSize(width: wide.height, height: wide.width), 0)
        case "left": (wide, 90)
        case "right": (wide, 270)
        default: nil
        }
    }

    /// Where the page has got to, as `Report` reads it.
    func report() async -> Report {
        let text = await call("return __lampPhone.report()", [:]) ?? "{}"
        let said = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
        return Report(link: said["link"] as? String ?? "?", player: said["player"] as? Int, held: said["held"] as? Bool ?? false,
                      sent: said["sent"] as? [String] ?? [], screen: said["screen"] as? [String] ?? [], logged: said["logged"] as? [String] ?? [],
                      size: (said["width"] as? Int ?? 0, said["height"] as? Int ?? 0))
    }

    private func call(_ body: String, _ arguments: [String: Any]) async -> String? {
        guard let webView else { return nil }
        return (try? await webView.callAsyncJavaScript(body, arguments: arguments, contentWorld: .page)) as? String
    }

    /// The page as drawn, one pixel to a CSS pixel, so the x and y of a tap are read straight off the picture.
    func picture() async -> Data? {
        guard let webView else { return nil }
        let size = webView.frame.size
        let configuration = WKSnapshotConfiguration()
        configuration.afterScreenUpdates = true
        return await withCheckedContinuation { (done: CheckedContinuation<Data?, Never>) in
            webView.takeSnapshot(with: configuration) { image, _ in
                MainActor.assumeIsolated { done.resume(returning: image.flatMap { WebGamePreview.png($0, width: Int(size.width), height: Int(size.height)) }) }
            }
        }
    }

    /// What the agent is told of the page after a play.
    struct Report {
        var link: String
        var player: Int?
        var held: Bool
        var sent: [String]
        var screen: [String]
        var logged: [String]
        var size: (width: Int, height: Int)

        /// `screen`: the page's words and controls, the picture's kin, and `log`: what its code said, the log's.
        func text(screen sharesScreen: Bool, log sharesLog: Bool) -> String {
            var lines = ["The phone page, at \(size.width)x\(size.height): \(link)" + (player.map { ", player \($0)" } ?? "") + (held ? ", a finger still down." : ".")]
            lines.append(sent.isEmpty ? "It has sent the game nothing." : "What it sent the game, latest last:\n" + sent.suffix(20).joined(separator: "\n"))
            if sharesScreen, !screen.isEmpty { lines.append("On it (x y width height in the picture's pixels):\n" + screen.joined(separator: "\n")) }
            if sharesLog, !logged.isEmpty { lines.append("What the page logged:\n" + logged.suffix(20).joined(separator: "\n")) }
            return lines.joined(separator: "\n\n")
        }
    }

    /// What's in the page before its own code: the socket's stand-in, and what a browser on a phone says of itself and its
    /// touches. A synthetic finger is dispatched as a phone's events would be, pointer events and touch events with the
    /// click after them; WebKit refuses pointer capture for a finger it didn't see, so capture is kept here.
    static let script = #"""
        (function () {
          'use strict';
          var outbox = [], socket = null, opened = false, lost = false, away = false, hosted = false, player = null;
          var sent = [], logged = [], finger = null, angle = 90;

          // The page's time, moved on by `advance`: the play's, not the wall's. Lamp's own waits keep the real timers.
          var realTimeout = window.setTimeout.bind(window), RealDate = Date, started = RealDate.now(), clock = 0;
          var timers = new Map(), nextTimer = 1, firing = false;
          var drain = new MessageChannel(), drained = null;
          drain.port1.onmessage = function () { var done = drained; drained = null; done(); };
          // Whatever a timer's promises set going finishes here, with the clock still at that timer's moment. A message is
          // a task of its own, so every promise in a chain gets its turn, and it isn't slowed as a nested timeout is.
          function settle() { return new Promise(function (done) { drained = done; drain.port2.postMessage(0); }); }
          function schedule(fn, delay, args, every) {
            var id = nextTimer++;
            var run = typeof fn === 'function' ? function () { fn.apply(window, args); } : function () { (0, eval)(String(fn)); };
            // As in a browser, a timer set from a timer waits a little: the clock moves on for a page that keeps setting them.
            delay = Math.max(firing ? 4 : 0, +delay || 0);
            timers.set(id, { run: run, at: clock + delay, every: every ? Math.max(1, delay) : 0 });
            return id;
          }
          window.setTimeout = function (fn, delay) { return schedule(fn, delay, Array.prototype.slice.call(arguments, 2), false); };
          window.setInterval = function (fn, delay) { return schedule(fn, delay, Array.prototype.slice.call(arguments, 2), true); };
          window.clearTimeout = window.clearInterval = function (id) { timers.delete(id); };
          window.requestAnimationFrame = function (fn) {
            // The next whole frame after the clock, counted in frames: a gap of a rounding error added to the clock leaves
            // it where it was, and a page drawing every frame would never let time pass.
            var frame = 1000 / 60, next = Math.floor(clock / frame) + 1;
            while (next * frame <= clock) next++;
            var id = schedule(function () { fn(clock); }, 0, [], false);
            timers.get(id).at = next * frame;
            return id;
          };
          window.cancelAnimationFrame = function (id) { timers.delete(id); };
          function PageDate() {
            if (!new.target) return new RealDate(started + clock).toString();
            if (!arguments.length) return new RealDate(started + clock);
            return new (Function.prototype.bind.apply(RealDate, [null].concat(Array.prototype.slice.call(arguments))))();
          }
          PageDate.prototype = RealDate.prototype;
          PageDate.UTC = RealDate.UTC; PageDate.parse = RealDate.parse;
          PageDate.now = function () { return started + clock; };
          window.Date = PageDate;
          Object.defineProperty(performance, 'now', { configurable: true, value: function () { return clock; } });
          // Each timer due in the time passed, in order, with the clock at its moment. A page whose timer never stops
          // adding timers can't hold the play up.
          async function advance(ms) {
            var end = clock + Math.max(0, +ms || 0), fired = 0;
            await settle();
            for (;;) {
              var due = null, dueId = 0;
              timers.forEach(function (t, id) { if (t.at <= end && (!due || t.at < due.at)) { due = t; dueId = id; } });
              if (!due || fired++ > 20000) break;
              clock = Math.max(clock, due.at);
              if (due.every) due.at += due.every; else timers.delete(dueId);
              firing = true;
              try { due.run(); } catch (e) { logged.push('Error: ' + e.message); }
              firing = false;
              await settle();
            }
            clock = end;
            await settle();
          }

          function deliver(m) { if (socket && socket.readyState === 1 && socket.onmessage) socket.onmessage({ data: JSON.stringify(m) }); }
          function Socket(url) {
            var self = this;
            this.url = url; this.readyState = 0; this.binaryType = 'blob'; this.bufferedAmount = 0;
            socket = this;
            realTimeout(function () {
              if (socket !== self) return;
              if (lost) { self.readyState = 3; if (self.onclose) self.onclose({ code: 1006 }); return; }
              self.readyState = 1;
              if (self.onopen) self.onopen({});
            }, 0);
          }
          Socket.prototype.send = function (text) {
            if (typeof text !== 'string') { logged.push('A file was not sent: the preview carries no files.'); return; }
            var m; try { m = JSON.parse(text); } catch (e) { return; }
            if (m.t === 'hello') { opened = true; outbox.push({ t: 'hello' }); deliver({ t: 'welcome', credential: 'preview', host: hosted && !away }); return; }
            if (m.t === 'beat') { deliver({ t: 'beat' }); return; }
            if (m.t === 'button') sent.push('button ' + m.name + (m.down ? ' down' : ' up'));
            else if (m.t === 'axis') sent.push('axis ' + m.name + ' ' + (+m.x).toFixed(2) + ', ' + (+m.y).toFixed(2));
            else if (m.t === 'message') sent.push('message ' + JSON.stringify(m.data).slice(0, 120));
            outbox.push(m);
          };
          Socket.prototype.close = function () {
            if (this.readyState === 3) return;
            this.readyState = 3;
            if (socket === this) { outbox.push({ t: 'bye' }); opened = false; }
            if (this.onclose) this.onclose({ code: 1000 });
          };
          Socket.prototype.addEventListener = function () {};
          window.WebSocket = Socket;

          // What a phone says of itself.
          function define(object, name, value) { try { Object.defineProperty(object, name, { configurable: true, get: value }); } catch (e) {} }
          function size() { return { width: window.innerWidth, height: window.innerHeight }; }
          var orientation = new EventTarget();
          define(orientation, 'angle', function () { return angle; });
          define(orientation, 'type', function () { return angle === 0 ? 'portrait-primary' : angle === 90 ? 'landscape-primary' : 'landscape-secondary'; });
          orientation.lock = function () { return Promise.reject(new DOMException('Not available here.', 'NotSupportedError')); };
          orientation.unlock = function () {};
          define(screen, 'orientation', function () { return orientation; });
          define(screen, 'width', function () { return size().width; });
          define(screen, 'height', function () { return size().height; });
          define(window, 'orientation', function () { return angle === 270 ? -90 : angle; });
          define(navigator, 'maxTouchPoints', function () { return 5; });
          window.ontouchstart = null;

          ['log', 'warn', 'error'].forEach(function (name) {
            var was = console[name];
            console[name] = function () {
              logged.push(Array.prototype.map.call(arguments, String).join(' ').slice(0, 300));
              return was.apply(console, arguments);
            };
          });
          window.addEventListener('error', function (e) { logged.push('Error: ' + e.message); });
          window.addEventListener('unhandledrejection', function (e) { logged.push('Error: ' + (e.reason && e.reason.message || e.reason)); });

          // Pointer capture for the stand-in finger; a real pointer, were there one, goes on as it would.
          var capture = Element.prototype.setPointerCapture, release = Element.prototype.releasePointerCapture;
          Element.prototype.setPointerCapture = function (id) {
            if (finger && id === finger.id) { finger.captured = this; return; }
            return capture.call(this, id);
          };
          Element.prototype.releasePointerCapture = function (id) {
            if (finger && id === finger.id) { finger.captured = null; return; }
            return release.call(this, id);
          };
          var hasCapture = Element.prototype.hasPointerCapture;
          Element.prototype.hasPointerCapture = function (id) {
            if (finger && id === finger.id) return finger.captured === this;
            return hasCapture.call(this, id);
          };

          function pointer(el, type, x, y, buttons) {
            return el.dispatchEvent(new PointerEvent(type, {
              bubbles: true, cancelable: true, composed: true, clientX: x, clientY: y, screenX: x, screenY: y,
              pointerId: finger.id, pointerType: 'touch', isPrimary: true, button: type === 'pointermove' ? -1 : 0, buttons: buttons,
              width: 40, height: 40, pressure: buttons ? 0.5 : 0
            }));
          }
          function touch(el, type, x, y, ended) {
            var t = { identifier: finger.id, target: finger.element, clientX: x, clientY: y, pageX: x + window.scrollX, pageY: y + window.scrollY,
                      screenX: x, screenY: y, radiusX: 20, radiusY: 20, force: 0.5 };
            var e = new Event(type, { bubbles: true, cancelable: true, composed: true });
            function list(items) { items.item = function (i) { return items[i] || null; }; return items; }
            e.touches = list(ended ? [] : [t]); e.targetTouches = list(ended ? [] : [t]); e.changedTouches = list([t]);
            return el.dispatchEvent(e);
          }
          function mouse(el, type, x, y) { return el.dispatchEvent(new MouseEvent(type, { bubbles: true, cancelable: true, composed: true, clientX: x, clientY: y, button: 0 })); }

          // What a step points at: a selector or the words on a thing, or a point.
          function find(target) {
            var el = null;
            try { el = document.querySelector(target); } catch (e) {}
            if (el) return el;
            var all = document.querySelectorAll('button, a, input, select, textarea, label, [role="button"], [aria-label], [data-button], [data-control], div, span, p');
            var wanted = target.trim().toLowerCase();
            for (var i = 0; i < all.length; i++) {
              var words = (all[i].getAttribute('aria-label') || all[i].textContent || '').trim().toLowerCase();
              if (words === wanted && visible(all[i])) return all[i];
            }
            return null;
          }
          function point(step) {
            if (step.target !== undefined) {
              var el = find(step.target);
              if (!el) { logged.push('Nothing on the page is "' + step.target + '".'); return null; }
              var r = el.getBoundingClientRect();
              return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
            }
            return typeof step.x === 'number' && typeof step.y === 'number' ? { x: step.x, y: step.y } : null;
          }
          function visible(el) {
            var r = el.getBoundingClientRect(), s = getComputedStyle(el);
            return r.width > 0 && r.height > 0 && s.visibility !== 'hidden' && s.display !== 'none' && +s.opacity > 0
              && r.right > 0 && r.bottom > 0 && r.left < window.innerWidth && r.top < window.innerHeight;
          }

          function down(step) {
            var at = point(step);
            if (!at) return;
            if (finger) up();
            var el = document.elementFromPoint(at.x, at.y);
            if (!el) { logged.push('There is nothing at ' + at.x + ', ' + at.y + ' on the page.'); return; }
            finger = { id: 7, element: el, captured: null, x: at.x, y: at.y, from: at, quiet: true };
            pointer(el, 'pointerdown', at.x, at.y, 1);
            if (!touch(el, 'touchstart', at.x, at.y, false)) finger.quiet = false;
          }
          function move(step) {
            if (!finger) return;
            var from = { x: finger.x, y: finger.y }, moves = 6;
            for (var i = 1; i <= moves; i++) {
              var x = from.x + (step.x - from.x) * i / moves, y = from.y + (step.y - from.y) * i / moves;
              pointer(finger.captured || finger.element, 'pointermove', x, y, 1);
              touch(finger.element, 'touchmove', x, y, false);
              finger.x = x; finger.y = y;
            }
          }
          function up() {
            if (!finger) return;
            var f = finger, x = f.x, y = f.y;
            pointer(f.captured || f.element, 'pointerup', x, y, 0);
            var quiet = touch(f.element, 'touchend', x, y, true) && f.quiet;
            finger = null;
            // A tap ends in a click, as on a phone, unless the page took the touch for itself or the finger moved away.
            if (!quiet || Math.hypot(x - f.from.x, y - f.from.y) > 10) return;
            mouse(f.element, 'mousedown', x, y);
            mouse(f.element, 'mouseup', x, y);
            if (f.element.focus) f.element.focus();
            f.element.click ? f.element.click() : mouse(f.element, 'click', x, y);
          }
          function type(step) {
            var el = step.target === undefined ? document.activeElement : find(step.target);
            if (!el || !('value' in el)) { logged.push('There is no field to type in.'); return; }
            el.focus();
            var setter = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(el), 'value');
            if (setter && setter.set) setter.set.call(el, step.text || ''); else el.value = step.text || '';
            el.dispatchEvent(new Event('input', { bubbles: true }));
            el.dispatchEvent(new Event('change', { bubbles: true }));
          }
          function link(what) {
            if (what === 'lost') {
              lost = true;
              if (socket && socket.readyState === 1) {
                var s = socket;
                s.readyState = 3;
                opened = false;
                outbox.push({ t: 'bye' });
                if (s.onclose) s.onclose({ code: 1006 });
              }
            } else if (what === 'away') {
              away = true;
              deliver({ t: 'state', host: false });
            } else if (what === 'back') {
              lost = false;
              if (away) { away = false; deliver({ t: 'state', host: hosted }); }
            }
          }
          function pause(ms) { return new Promise(function (done) { realTimeout(done, ms); }); }
          // `passing`: the page's clock runs meanwhile, for a page trying its link again on its own timer.
          async function joined(ms, passing) { for (var i = 0; i * 20 < ms && !opened; i++) { await pause(20); if (passing) await advance(50); } }
          var first = true;

          window.__lampPhone = {
            step: async function (step, inbox, nowHosted, elapsed) {
              var was = hosted;
              hosted = !!nowHosted;
              if (hosted !== was && !away) deliver({ t: 'state', host: hosted });
              if (first) { first = false; await joined(400, false); }
              await advance(elapsed);
              (JSON.parse(inbox || '[]')).forEach(function (m) { if (m.t === 'player') player = m.number; deliver(m); });
              switch (step.do) {
                case 'down': down(step); break;
                case 'move': move(step); break;
                case 'up': up(); break;
                case 'type': type(step); break;
                case 'link': link(step.what); if (step.what === 'back') await joined(3000, true); break;
                case 'rotate':
                  angle = step.angle;
                  // WebKit tells the page of its new size on its own; a phone's turn also says this.
                  await pause(50);
                  window.dispatchEvent(new Event('orientationchange'));
                  orientation.dispatchEvent(new Event('change'));
                  break;
              }
              // What the step set going right away, on the page's clock and off it.
              await advance(0);
              await pause(40);
              await advance(0);
              return JSON.stringify({ messages: outbox.splice(0) });
            },
            report: function () {
              var words = [], walk = document.createTreeWalker(document.body || document.documentElement, NodeFilter.SHOW_TEXT), seen = 0, n;
              while ((n = walk.nextNode()) && seen < 60) {
                var text = n.textContent.trim(), el = n.parentElement;
                if (!text || !el || /^(SCRIPT|STYLE)$/.test(el.tagName) || !visible(el)) continue;
                if (el.closest('button, a, input, select, textarea, [role="button"]')) continue;
                var r = el.getBoundingClientRect();
                words.push('"' + text.slice(0, 80) + '" ' + [r.left, r.top, r.width, r.height].map(Math.round).join(' '));
                seen++;
              }
              var controls = [], all = document.querySelectorAll('button, a[href], input, select, textarea, canvas, [role="button"], [data-button], [data-control]');
              for (var i = 0; i < all.length && controls.length < 40; i++) {
                if (!visible(all[i])) continue;
                var b = all[i].getBoundingClientRect(), name = (all[i].getAttribute('aria-label') || all[i].value || all[i].textContent || all[i].id || '').trim().slice(0, 60);
                controls.push(all[i].tagName.toLowerCase() + (all[i].id ? '#' + all[i].id : '') + ' "' + name + '" ' + [b.left, b.top, b.width, b.height].map(Math.round).join(' '));
              }
              return JSON.stringify({ link: lost ? 'link lost' : !opened ? 'not joined' : away || !hosted ? 'joined, the game is not there' : 'joined', player: player,
                                      held: !!finger, sent: sent, screen: controls.concat(words), logged: logged, width: window.innerWidth, height: window.innerHeight });
            }
          };
        })();
        """#
}

extension GameKit {
    /// Where the copy of a game's phone page is kept for the preview: beside the copy of its page, never the published one
    /// a game's real phones are served from, which changes only as the game is built for where it's played.
    static func phonePreviewFolder(_ project: LampProject) -> URL {
        stagingFolder(project).appendingPathComponent("phone")
    }

    /// `use_app`'s action on the phone page, as lines of the preview's script ending just before its picture: a step on the
    /// page is a `phone` line, played where it stands among the frames, so every play goes the same way.
    static func phoneMoves(_ action: [String: Any]) -> (lines: [String], said: String?, problem: String?) {
        func step(_ fields: [String: Any]) -> String {
            let data = (try? JSONSerialization.data(withJSONObject: fields, options: .sortedKeys)) ?? Data("{}".utf8)
            return "phone " + String(decoding: data, as: UTF8.self)
        }
        func frames(_ seconds: Double) -> String { Hold(frames: max(1, Int((seconds * 60).rounded()))).line }
        let held = min(max(action["amount"] as? Double ?? 0, 0), 60)
        let target = (action["target"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let x = action["x"] as? Double, y = action["y"] as? Double
        var place: [String: Any] = [:]
        if let target { place["target"] = target } else if let x, let y { place = ["x": x, "y": y] }
        let named = target.map { "\"\($0)\"" } ?? x.flatMap { x in y.map { "\(x.formatted()), \($0.formatted())" } } ?? "the page"
        let needsPlace = "Say where on the phone page: `target` (a selector or the words on it), or `x` and `y` in its picture."
        switch action["action"] as? String ?? "" {
        case "wait":
            return ([step(["do": "sync"]), frames(action["amount"] == nil ? 1 : held)], "Waited on the phone page.", nil)
        case "click":
            guard !place.isEmpty else { return ([], nil, needsPlace) }
            let down = step(place.merging(["do": "down"]) { $1 })
            return ([down, frames(max(held, 0.1)), step(["do": "up"]), frames(0)], "Tapped \(named) on the phone page" + (held > 0 ? ", held \(held.formatted()) s." : "."), nil)
        case "press":
            guard !place.isEmpty else { return ([], nil, needsPlace) }
            return ([step(place.merging(["do": "down"]) { $1 }), frames(max(held, 0))], "Put a finger down on \(named) on the phone page, and left it there.", nil)
        case "release":
            return ([step(["do": "up"]), frames(0)], "Lifted the finger from the phone page.", nil)
        case "drag":
            guard let toX = action["to_x"] as? Double, let toY = action["to_y"] as? Double else {
                return ([], nil, "A drag on the phone page ends at `to_x` and `to_y`.")
            }
            let move = step(["do": "move", "x": toX, "y": toY])
            // From a place the finger goes down and lifts at the end; with none it's the finger a `press` left down.
            if place.isEmpty { return ([move, frames(held)], "Moved the finger on the phone page to \(toX.formatted()), \(toY.formatted()).", nil) }
            return ([step(place.merging(["do": "down"]) { $1 }), move, frames(max(held, 0.1)), step(["do": "up"]), frames(0)],
                    "Dragged from \(named) to \(toX.formatted()), \(toY.formatted()) on the phone page.", nil)
        case "type":
            return ([step(place.merging(["do": "type", "text": action["text"] as? String ?? ""]) { $1 }), frames(0)], "Typed on the phone page.", nil)
        case "rotate":
            let direction = (action["direction"] as? String)?.lowercased()
            guard PhonePreview.turn(direction) != nil else { return ([], nil, "`rotate` takes `direction`: up (upright), or left or right (sideways, each way round).") }
            return ([step(["do": "rotate", "direction": direction ?? ""]), frames(0)], "Turned the phone \(direction ?? "").", nil)
        case "link":
            let item = (action["item"] as? String)?.lowercased() ?? ""
            guard ["lost", "away", "back"].contains(item) else {
                return ([], nil, "`link` takes `item`: lost (the phone loses its link), away (the game goes away) or back.")
            }
            return ([step(["do": "link", "what": item]), frames(0.1)], "The phone's link: \(item).", nil)
        default:
            return ([], nil, "On the phone page, use click, press, release, drag, type, rotate, link or wait.")
        }
    }
}
