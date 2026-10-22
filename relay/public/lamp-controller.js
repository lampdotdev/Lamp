/* Lamp's phone controller, served with every phone page at /lamp-controller.js. The page is the app's own; this
 * joins it to the TV app as a player and carries its buttons, sticks and tilt there.
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
 *     .catch(function (error) { ... });              // right 1, y: away -1 to toward 1) about 30 times a second
 */
(function () {
  'use strict';
  var relay = window.LAMP_RELAY;
  var keyName = 'lamp-controller:' + relay.session;

  function connect(handlers) {
    handlers = handlers || {};
    var socket = null, seq = 0, player = null, closedForGood = false, beat = null, lastHeard = 0, retry = 0;
    // The link's credential is read once and taken out of the address, so it isn't left in the history or shared
    // by mistake; the phone then keeps the credential the relay gives it, for coming back as the same player.
    var join = (location.hash || '').replace(/^#/, '');
    if (join) history.replaceState(null, '', location.pathname + location.search);
    function state(s) { if (handlers.onState) handlers.onState(s); }

    function open() {
      var credential = sessionStorage.getItem(keyName) || join;
      if (!credential) { state('ended'); return; }
      state('connecting');
      socket = new WebSocket(relay.socket);
      socket.onopen = function () {
        lastHeard = Date.now();
        socket.send(JSON.stringify({ t: 'hello', session: relay.session, credential: credential }));
      };
      socket.onmessage = function (event) {
        lastHeard = Date.now();
        var m; try { m = JSON.parse(event.data); } catch (e) { return; }
        if (m.t === 'welcome') {
          retry = 0; join = '';
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
        if (event.code === 4003 || event.code === 4005) { sessionStorage.removeItem(keyName); closedForGood = true; state('ended'); }
        if (closedForGood) return;
        state('connecting');
        retry = Math.min(retry + 1, 5);
        setTimeout(open, 500 * retry);
      };
    }

    function post(message) {
      if (!socket || socket.readyState !== 1) return false;
      message.seq = ++seq;
      socket.send(JSON.stringify(message));
      return true;
    }

    // A beat both ways: the relay lets a quiet phone go, and a phone that hears nothing reconnects.
    beat = setInterval(function () {
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
      close: function () { closedForGood = true; clearInterval(beat); if (socket) socket.close(); }
    };
  }

  // The phone's tilt, from gravity: the same however far it's leaned back, held upright or on its side.
  function tilt(pad, options) {
    options = options || {};
    var range = options.degrees || 40;
    var D = window.DeviceMotionEvent;
    if (!D) return Promise.reject(new Error('This phone has no motion sensors.'));
    if (!window.isSecureContext) return Promise.reject(new Error('Tilt needs the page to be opened from its secure link.'));
    var asked = typeof D.requestPermission === 'function' ? D.requestPermission() : Promise.resolve('granted');
    return asked.then(function (answer) {
      if (answer !== 'granted') throw new Error('Motion access was turned down. Allow it in the browser to steer by tilting.');
      var last = 0, x = 0, y = 0;
      window.addEventListener('devicemotion', function (event) {
        var g = event.accelerationIncludingGravity;
        if (!g || g.x === null) return;
        var turn = typeof screen.orientation === 'object' ? screen.orientation.angle : (window.orientation || 0);
        var gx = g.x, gy = g.y;
        if (turn === 90) { gx = -g.y; gy = g.x; } else if (turn === -90 || turn === 270) { gx = g.y; gy = -g.x; } else if (turn === 180) { gx = -g.x; gy = -g.y; }
        var side = Math.atan2(gx, Math.sqrt(gy * gy + g.z * g.z)) * 180 / Math.PI;
        var lean = Math.atan2(gy, Math.sqrt(gx * gx + g.z * g.z)) * 180 / Math.PI;
        x = Math.max(-1, Math.min(1, side / range));
        y = Math.max(-1, Math.min(1, lean / range));
        var now = Date.now();
        if (now - last >= 33) { last = now; pad.axis('tilt', x, y); }
      });
    });
  }

  window.LampController = { connect: connect, tilt: tilt };
})();
